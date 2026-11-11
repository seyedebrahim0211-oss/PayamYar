package ir.honarmardomi.payamyar

import android.Manifest
import android.app.role.RoleManager
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.database.ContentObserver
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.BlockedNumberContract
import android.provider.ContactsContract
import android.provider.Settings
import android.provider.Telephony
import android.telecom.TelecomManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private var observing = false
    private var contactResult: MethodChannel.Result? = null
    private var permissionResult: MethodChannel.Result? = null
    private var defaultResult: MethodChannel.Result? = null
    private lateinit var channel: MethodChannel
    private val worker = Executors.newSingleThreadExecutor()
    private val handler = Handler(Looper.getMainLooper())
    private val observer = object : ContentObserver(handler) {
        override fun onChange(selfChange: Boolean) { channel.invokeMethod("messagesChanged", null) }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ir.honarmardomi.payamyar/sms")
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "pickContact" -> {
                    if (contactResult != null) result.error("BUSY", "Contact picker is already open", null)
                    else {
                        contactResult = result
                        try { startActivityForResult(Intent(Intent.ACTION_PICK, ContactsContract.CommonDataKinds.Phone.CONTENT_URI), 2110) }
                        catch (e: Exception) { contactResult = null; result.error("CONTACTS", "دفترچه مخاطبان در دسترس نیست.", null) }
                    }
                }
                "requestPermissions" -> {
                    // Completes after the user answers the Android dialog, with the new permission state.
                    permissionResult?.success(permissionMap())
                    permissionResult = null
                    val permissions = mutableListOf(Manifest.permission.READ_SMS, Manifest.permission.SEND_SMS,
                        Manifest.permission.RECEIVE_SMS, Manifest.permission.READ_PHONE_STATE, Manifest.permission.READ_CONTACTS)
                    if (Build.VERSION.SDK_INT >= 33) permissions.add(Manifest.permission.POST_NOTIFICATIONS)
                    val missing = permissions.filter { !has(it) }
                    if (missing.isEmpty()) result.success(permissionMap())
                    else {
                        permissionResult = result
                        ActivityCompat.requestPermissions(this, missing.toTypedArray(), 2104)
                    }
                }
                "requestDefault" -> requestDefault(result)
                "openAppSettings" -> {
                    try {
                        startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", packageName, null)))
                        result.success(true)
                    } catch (e: Exception) { result.success(false) }
                }
                "manageBlocked" -> {
                    try {
                        startActivity(getSystemService(TelecomManager::class.java).createManageBlockedNumbersIntent())
                        result.success(true)
                    } catch (e: Exception) { result.success(false) }
                }
                "takeComposeIntent" -> {
                    val data = intent
                    val address = data.data?.schemeSpecificPart?.substringBefore('?').orEmpty()
                    result.success(if (data.action == Intent.ACTION_SENDTO) mapOf("to" to address,
                        "body" to (data.getStringExtra("sms_body") ?: "")) else null)
                    intent = Intent(this, MainActivity::class.java)
                }
                else -> worker.execute {
                    try {
                        val value: Any? = when (call.method) {
                            "isAvailable" -> packageManager.hasSystemFeature(if (Build.VERSION.SDK_INT >= 33) PackageManager.FEATURE_TELEPHONY_MESSAGING else PackageManager.FEATURE_TELEPHONY)
                            "permissionStatus" -> permissionMap()
                            "readMessages" -> SmsCore.read(this, call.argument<Int>("limit") ?: 1000,
                                call.argument<Number>("beforeDate")?.toLong(), call.argument<Number>("beforeId")?.toLong())
                            "subscriptions" -> SmsCore.subscriptions(this)
                            "contactNames" -> contactNames(call.argument<List<String>>("addresses").orEmpty())
                            "blockNumber" -> blockNumber(call.argument<String>("address").orEmpty())
                            "queueSms" -> SmsCore.queue(this, call.argument<String>("to").orEmpty(),
                                call.argument<String>("body").orEmpty(), call.argument<Int>("subscriptionId") ?: -1).also { id ->
                                    handler.postDelayed({ worker.execute { SmsCore.dispatch(this, id) } }, 5100)
                                }
                            "cancelSms" -> SmsCore.cancel(this, call.argument<String>("requestId").orEmpty())
                            "sendStatus" -> SmsCore.status(this, call.argument<String>("requestId").orEmpty())
                            "markRead" -> SmsCore.mutate(this, call.argument<List<Number>>("ids").orEmpty(), false)
                            "deleteMessages" -> SmsCore.mutate(this, call.argument<List<Number>>("ids").orEmpty(), true)
                            else -> { runOnUiThread { result.notImplemented() }; return@execute }
                        }
                        runOnUiThread { result.success(value) }
                    } catch (e: Exception) {
                        runOnUiThread { result.error("SMS_ERROR", e.message ?: "SMS operation failed", null) }
                    }
                }
            }
        }
        observeMessages()
    }

    /** Opens Android's official "default SMS app" dialog and completes with whether PayamYar was chosen. */
    private fun requestDefault(result: MethodChannel.Result) {
        if (SmsCore.isDefault(this)) { result.success(true); return }
        defaultResult?.success(false)
        defaultResult = null
        try {
            if (Build.VERSION.SDK_INT >= 29) {
                val role = getSystemService(RoleManager::class.java)
                if (!role.isRoleAvailable(RoleManager.ROLE_SMS)) { result.success(false); return }
                defaultResult = result
                startActivityForResult(role.createRequestRoleIntent(RoleManager.ROLE_SMS), 2105)
            } else {
                defaultResult = result
                @Suppress("DEPRECATION")
                startActivityForResult(Intent(Telephony.Sms.Intents.ACTION_CHANGE_DEFAULT).putExtra(Telephony.Sms.Intents.EXTRA_PACKAGE_NAME, packageName), 2105)
            }
        } catch (e: Exception) {
            defaultResult = null
            result.success(false)
        }
    }

    private fun permissionMap() = mapOf(
        "read" to has(Manifest.permission.READ_SMS),
        "send" to has(Manifest.permission.SEND_SMS),
        "contacts" to has(Manifest.permission.READ_CONTACTS),
        "default" to SmsCore.isDefault(this))

    /** Display names for phone numbers, looked up one by one so the full address book is never loaded. */
    private fun contactNames(addresses: List<String>): Map<String, String> {
        if (!has(Manifest.permission.READ_CONTACTS)) return emptyMap()
        val names = mutableMapOf<String, String>()
        for (address in addresses.take(3000)) {
            if (address.none { it.isDigit() }) continue
            try {
                val uri = Uri.withAppendedPath(ContactsContract.PhoneLookup.CONTENT_FILTER_URI, Uri.encode(address))
                contentResolver.query(uri, arrayOf(ContactsContract.PhoneLookup.DISPLAY_NAME), null, null, null)?.use {
                    if (it.moveToFirst()) {
                        val name = it.getString(0)
                        if (!name.isNullOrBlank()) names[address] = name
                    }
                }
            } catch (_: Exception) {
                // Skip numbers the contacts provider cannot parse.
            }
        }
        return names
    }

    private fun blockNumber(address: String): Boolean {
        check(address.isNotBlank()) { "شماره معتبر نیست." }
        check(BlockedNumberContract.canCurrentUserBlockNumbers(this)) { "برای مسدود کردن، پیامیار باید پیامک‌رسان پیش‌فرض باشد." }
        contentResolver.insert(BlockedNumberContract.BlockedNumbers.CONTENT_URI, ContentValues().apply {
            put(BlockedNumberContract.BlockedNumbers.COLUMN_ORIGINAL_NUMBER, address)
        })
        return true
    }

    private fun observeMessages() {
        if (!observing && has(Manifest.permission.READ_SMS)) {
            try {
                contentResolver.registerContentObserver(Telephony.Sms.CONTENT_URI, true, observer)
                observing = true
            } catch (_: SecurityException) {
                // Permission was revoked between the check and the registration.
            }
        }
    }
    override fun onResume() {
        super.onResume()
        if (::channel.isInitialized) observeMessages()
    }
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == 2110) {
            val result = contactResult ?: return
            contactResult = null
            try {
                var number: String? = null
                if (resultCode == android.app.Activity.RESULT_OK && data?.data != null) {
                    contentResolver.query(data.data!!, arrayOf(ContactsContract.CommonDataKinds.Phone.NUMBER), null, null, null)?.use {
                        if (it.moveToFirst()) number = it.getString(0)
                    }
                }
                result.success(number)
            } catch (_: Exception) { result.error("CONTACTS", "خواندن شماره مخاطب ممکن نشد.", null) }
        }
        if (requestCode == 2105) {
            observeMessages()
            defaultResult?.success(SmsCore.isDefault(this))
            defaultResult = null
            channel.invokeMethod("messagesChanged", null)
        }
    }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        observeMessages()
        if (requestCode == 2104) {
            permissionResult?.success(permissionMap())
            permissionResult = null
        }
        channel.invokeMethod("messagesChanged", null)
    }
    private fun has(permission: String) = ContextCompat.checkSelfPermission(this, permission) == PackageManager.PERMISSION_GRANTED
    override fun onNewIntent(intent: Intent) { super.onNewIntent(intent); setIntent(intent); channel.invokeMethod("composeIntent", null) }
    override fun onDestroy() { if (observing) contentResolver.unregisterContentObserver(observer); super.onDestroy() }
}
