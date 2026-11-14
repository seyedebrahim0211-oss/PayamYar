package ir.honarmardomi.payamyar

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.concurrent.Executors
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.PBEKeySpec

/**
 * Small encrypted key/value store for secrets (SMS panel credentials, PIN hashes).
 *
 *  - Values are AES-256-GCM encrypted with a non-exportable key in the Android Keystore.
 *  - PINs are never stored: only a salted PBKDF2 hash (120k rounds), compared in constant time.
 *  - Wrong PIN attempts are counted; after 5 failures the PIN is locked for an increasing period.
 *  - android:allowBackup="false" keeps the file out of cloud/adb backups.
 */
object SecureVault {
    private const val KEY_ALIAS = "payamyar_vault_v1"
    private const val PREFS = "payamyar_vault_v1"
    private val random = SecureRandom()

    private fun prefs(c: Context) = c.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(KeyGenParameterSpec.Builder(KEY_ALIAS,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .build())
        return generator.generateKey()
    }

    @Synchronized fun put(c: Context, name: String, value: String) {
        require(name.matches(Regex("[a-z0-9_]{1,40}")))
        require(value.length <= 4096)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key())
        val data = cipher.iv + cipher.doFinal(value.toByteArray(Charsets.UTF_8))
        check(prefs(c).edit().putString("v:$name", Base64.encodeToString(data, Base64.NO_WRAP)).commit())
    }

    @Synchronized fun get(c: Context, name: String): String? {
        val raw = prefs(c).getString("v:$name", null) ?: return null
        return try {
            val data = Base64.decode(raw, Base64.NO_WRAP)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, data, 0, 12))
            String(cipher.doFinal(data, 12, data.size - 12), Charsets.UTF_8)
        } catch (_: Exception) {
            null // Key lost (e.g. device restore): treat as not set.
        }
    }

    @Synchronized fun remove(c: Context, name: String) {
        prefs(c).edit().remove("v:$name").remove("fail:$name").remove("until:$name").commit()
    }

    private fun pbkdf2(pin: String, salt: ByteArray): ByteArray {
        val spec = PBEKeySpec(pin.toCharArray(), salt, 120_000, 256)
        // HMAC-SHA1 is the PBKDF2 variant available on every supported Android (7+), so a hash
        // stays valid after an OS upgrade. Together with the attempt lockout this is ample for a PIN.
        return SecretKeyFactory.getInstance("PBKDF2WithHmacSHA1").generateSecret(spec).encoded
    }

    @Synchronized fun setPin(c: Context, name: String, pin: String) {
        require(pin.length in 4..32 && pin.all { it.isDigit() }) { "رمز باید ۴ تا ۳۲ رقم باشد." }
        val salt = ByteArray(16).also { random.nextBytes(it) }
        val hash = pbkdf2(pin, salt)
        put(c, "pin_$name", Base64.encodeToString(salt, Base64.NO_WRAP) + ":" + Base64.encodeToString(hash, Base64.NO_WRAP))
        prefs(c).edit().remove("fail:$name").remove("until:$name").commit()
    }

    fun hasPin(c: Context, name: String) = prefs(c).contains("v:pin_$name")

    /** Seconds the PIN is still locked after too many wrong attempts (0 = free). */
    fun lockedFor(c: Context, name: String): Long =
        ((prefs(c).getLong("until:$name", 0) - System.currentTimeMillis()) / 1000).coerceAtLeast(0)

    /** "ok", "wrong:<attemptsLeft>", "locked:<seconds>" or "none". */
    @Synchronized fun verifyPin(c: Context, name: String, pin: String): String {
        // A persisted PIN record that cannot decrypt means key loss, NOT no PIN.
        if (!hasPin(c, name)) return "none"
        val stored = get(c, "pin_$name") ?: return "unavailable"
        val wait = lockedFor(c, name)
        if (wait > 0) return "locked:$wait"
        val parts = stored.split(':')
        if (parts.size != 2) return "unavailable"
        val salt = Base64.decode(parts[0], Base64.NO_WRAP)
        val expected = Base64.decode(parts[1], Base64.NO_WRAP)
        val ok = MessageDigest.isEqual(expected, pbkdf2(pin, salt))
        val p = prefs(c)
        if (ok) {
            p.edit().remove("fail:$name").remove("until:$name").commit()
            return "ok"
        }
        val fails = p.getInt("fail:$name", 0) + 1
        val edit = p.edit().putInt("fail:$name", fails)
        if (fails >= 5) {
            // 5 wrong → 1 min, then 5, 15, 60 minutes.
            val minutes = when (fails) { 5 -> 1L; 6 -> 5L; 7 -> 15L; else -> 60L }
            edit.putLong("until:$name", System.currentTimeMillis() + minutes * 60_000)
        }
        edit.commit()
        return if (fails >= 5) "locked:${lockedFor(c, name)}" else "wrong:${5 - fails}"
    }
}

/** Flutter side: MethodChannel "ir.honarmardomi.payamyar/vault". Work runs off the UI thread. */
class VaultChannel(private val context: Context, messenger: BinaryMessenger) {
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    init {
        MethodChannel(messenger, "ir.honarmardomi.payamyar/vault").setMethodCallHandler { call, result ->
            worker.execute {
                try {
                    val name = call.argument<String>("name").orEmpty()
                    val value: Any? = when (call.method) {
                        "get" -> SecureVault.get(context, name)
                        "put" -> { SecureVault.put(context, name, call.argument<String>("value").orEmpty()); true }
                        "remove" -> { SecureVault.remove(context, name); SecureVault.remove(context, "pin_$name"); true }
                        "setPin" -> { SecureVault.setPin(context, name, call.argument<String>("pin").orEmpty()); true }
                        "hasPin" -> SecureVault.hasPin(context, name)
                        "verifyPin" -> SecureVault.verifyPin(context, name, call.argument<String>("pin").orEmpty())
                        else -> { main.post { result.notImplemented() }; return@execute }
                    }
                    main.post { result.success(value) }
                } catch (e: Exception) {
                    main.post { result.error("VAULT", e.message ?: "خطای ذخیره‌ساز امن", null) }
                }
            }
        }
    }
}
