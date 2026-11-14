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

open class MainActivity : FlutterActivity() {
    companion object {
        /** Set while a PayamYar screen is in front; Notifier then shows the in-app glass banner instead. */
        @Volatile @JvmStatic var foregroundChannel: MethodChannel? = null

        /**
         * Per-install secret placed on PayamYar's own notification, shortcut and bubble intents.
         * MainActivity is exported (sms:/smsto: links), so an "open_address" extra sent by any
         * other app is ignored unless it carries this token.
         */
        @JvmStatic fun launchToken(c: android.content.Context): String {
            val prefs = c.getSharedPreferences("payamyar_security", android.content.Context.MODE_PRIVATE)
            prefs.getString("launch_token", null)?.let { return it }
            val token = java.util.UUID.randomUUID().toString()
            prefs.edit().putString("launch_token", token).commit()
            return token
        }
    }
    private var observing = false
    private var contactResult: MethodChannel.Result? = null
    private var permissionResult: MethodChannel.Result? = null
    private var defaultResult: MethodChannel.Result? = null
    private lateinit var channel: MethodChannel
    private var contacts: ContactsChannel? = null
    private val worker = Executors.newSingleThreadExecutor()
    private val handler = Handler(Looper.getMainLooper())
    private val observer = object : ContentObserver(handler) {
        override fun onChange(selfChange: Boolean) { channel.invokeMethod("messagesChanged", null) }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ir.honarmardomi.payamyar/sms")
        contacts = ContactsChannel(this, flutterEngine.dartExecutor.binaryMessenger)
        VaultChannel(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
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
                    // Google Play: never ask for restricted SMS permissions until the user
                    // has deliberately chosen PayamYar as their default SMS handler.
                    if (!SmsCore.isDefault(this)) {
                        result.success(permissionMap())
                        return@setMethodCallHandler
                    }
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
                "loadAllMessages" -> {
                    // One pass over the inbox on its own thread; pages are pushed to Dart as they are read.
                    val generation = call.argument<Int>("generation") ?: 0
                    Thread {
                        try {
                            val total = SmsCore.stream(this) { page ->
                                runOnUiThread { channel.invokeMethod("messagesPage", page + ("generation" to generation)) }
                            }
                            runOnUiThread { result.success(total) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("SMS_ERROR", e.message ?: "SMS read failed", null) }
                        }
                    }.start()
                }
                "specialAccess" -> result.success(specialAccess())
                "requestBatteryExemption" -> {
                    try {
                        startActivity(Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:$packageName")))
                        result.success(true)
                    } catch (e: Exception) {
                        try { startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)); result.success(true) }
                        catch (e2: Exception) { result.success(false) }
                    }
                }
                "requestExactAlarm" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= 31) startActivity(Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, Uri.parse("package:$packageName")))
                        result.success(true)
                    } catch (e: Exception) { result.success(false) }
                }
                "openNotificationSettings" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= 26) startActivity(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, packageName))
                        result.success(true)
                    } catch (e: Exception) { result.success(false) }
                }
                "openNotificationChannel" -> {
                    try {
                        Notifier.configureChannels(this)
                        if (Build.VERSION.SDK_INT >= 26) {
                            startActivity(Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS)
                                .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                                .putExtra(Settings.EXTRA_CHANNEL_ID,
                                    if (call.argument<String>("channel") == "sent") Notifier.SENT_CHANNEL else Notifier.INCOMING_CHANNEL))
                        } else {
                            startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                Uri.fromParts("package", packageName, null)))
                        }
                        result.success(true)
                    } catch (_: Exception) { result.success(false) }
                }
                "clearNotifications" -> { Notifier.cancel(this, call.argument<String>("address").orEmpty()); result.success(null) }
                "shareText" -> {
                    try {
                        val send = Intent(Intent.ACTION_SEND).setType("text/plain")
                            .putExtra(Intent.EXTRA_SUBJECT, call.argument<String>("subject").orEmpty())
                            .putExtra(Intent.EXTRA_TEXT, call.argument<String>("text").orEmpty())
                        startActivity(Intent.createChooser(send, call.argument<String>("title") ?: "ارسال با"))
                        result.success(true)
                    } catch (_: Exception) { result.success(false) }
                }
                "birthdaysChanged" -> { worker.execute { try { Birthdays.schedule(this) } catch (_: Exception) { } }; result.success(null) }
                "birthdaySendNow" -> worker.execute {
                    val ok = try { Birthdays.sendNow(this, call.argument<String>("id").orEmpty()) } catch (e: Exception) { false }
                    runOnUiThread { result.success(ok) }
                }
                "previewNotification" -> { result.success(Notifier.preview(this)) }
                "openBubbleSettings" -> {
                    Notifier.configureChannels(this)
                    try {
                        if (Build.VERSION.SDK_INT >= 29) {
                            startActivity(Intent(Settings.ACTION_APP_NOTIFICATION_BUBBLE_SETTINGS)
                                .putExtra(Settings.EXTRA_APP_PACKAGE, packageName))
                        } else {
                            startActivity(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                                .putExtra(Settings.EXTRA_APP_PACKAGE, packageName))
                        }
                        result.success(true)
                    } catch (_: Exception) {
                        // Not all Android OEMs expose the bubble preferences activity.
                        // Open the app's notification settings instead of leaving a dead control.
                        try {
                            startActivity(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                                .putExtra(Settings.EXTRA_APP_PACKAGE, packageName))
                            result.success(true)
                        } catch (_: Exception) {
                            try {
                                startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                    Uri.fromParts("package", packageName, null)))
                                result.success(true)
                            } catch (_: Exception) {
                                result.success(false)
                            }
                        }
                    }
                }
                "previewSentSound" -> { SentSound.play(this); result.success(null) }
                "setSecureScreen" -> {
                    // Blocks screenshots, screen recording and the recent-apps preview of private chats.
                    if (call.argument<Boolean>("on") == true) window.addFlags(android.view.WindowManager.LayoutParams.FLAG_SECURE)
                    else window.clearFlags(android.view.WindowManager.LayoutParams.FLAG_SECURE)
                    result.success(null)
                }
                "openUrl" -> {
                    // Only fixed https pages of the SMS panel provider (charging credit, login).
                    val url = call.argument<String>("url").orEmpty()
                    val host = try { Uri.parse(url).host.orEmpty() } catch (_: Exception) { "" }
                    if (url.startsWith("https://") && (host == "melipayamak.com" || host.endsWith(".melipayamak.com"))) {
                        try { startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))); result.success(true) }
                        catch (_: Exception) { result.success(false) }
                    } else result.success(false)
                }
                "signingFingerprint" -> result.success(AppUpdater.installedSignerSha256(this))
                "canInstallUpdate" -> result.success(AppUpdater.canInstall(this))
                "installUpdate" -> {
                    val url = call.argument<String>("url").orEmpty()
                    if (!AppUpdater.canInstall(this)) {
                        // Android asks once: "allow installing apps from PayamYar".
                        try { AppUpdater.openInstallPermission(this) } catch (_: Exception) { }
                        result.success("needs_permission")
                    } else Thread {
                        try {
                            val size = call.argument<Number>("size")?.toLong() ?: 0L
                            val apk = AppUpdater.download(this, url, call.argument<String>("sha256").orEmpty(), size) {
                                p, done, total -> runOnUiThread {
                                    channel.invokeMethod("updateProgress", mapOf("percent" to p, "done" to done, "total" to total))
                                }
                            }
                            runOnUiThread {
                                try {
                                    AppUpdater.validateUpgrade(this, apk)
                                    AppUpdater.install(this, apk)
                                    result.success("installing")
                                }
                                catch (e: Exception) { result.error("UPDATE", e.message ?: "نصب انجام نشد.", null) }
                            }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("UPDATE", e.message ?: "دریافت نسخه جدید انجام نشد.", null) }
                        }
                    }.start()
                }
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
                    val open = data.getStringExtra("open_address")
                        ?.takeIf { data.getStringExtra("open_token") == launchToken(this) }
                    result.success(if (open != null) mapOf("open" to open)
                        else if (data.action == Intent.ACTION_SENDTO) mapOf("to" to address,
                        "body" to (data.getStringExtra("sms_body") ?: "")) else null)
                    intent = Intent(this, MainActivity::class.java)
                }
                else -> worker.execute {
                    try {
                        val value: Any? = when (call.method) {
                            "isAvailable" -> packageManager.hasSystemFeature(if (Build.VERSION.SDK_INT >= 33) PackageManager.FEATURE_TELEPHONY_MESSAGING else PackageManager.FEATURE_TELEPHONY)
                            "permissionStatus" -> permissionMap()
                            "readMessages" -> SmsCore.read(this, call.argument<Int>("limit") ?: 300)
                            "subscriptions" -> SmsCore.subscriptions(this)
                            "pendingSms" -> SmsCore.pending(this)
                            "contactNames" -> contactNames(call.argument<List<String>>("addresses").orEmpty())
                            "contactPhoto" -> contactPhoto(call.argument<String>("address").orEmpty())
                            "listContacts" -> listContacts()
                            "blockNumber" -> blockNumber(call.argument<String>("address").orEmpty())
                            "queueSms" -> SmsCore.queue(this, call.argument<String>("to").orEmpty(),
                                call.argument<String>("body").orEmpty(), call.argument<Int>("subscriptionId") ?: -1,
                                (call.argument<Number>("delayMs")?.toLong() ?: 5000L)).also { id ->
                                    // The alarm owns scheduled sends, even after the UI is closed.
                                    // Only the short five-second undo gets a foreground fallback.
                                    val delay = call.argument<Number>("delayMs")?.toLong() ?: 5000L
                                    if (delay <= 10000L) handler.postDelayed({ worker.execute { SmsCore.dispatch(this, id) } }, delay + 100L)
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

    private fun specialAccess(): Map<String, Boolean> {
        val power = getSystemService(android.os.PowerManager::class.java)
        val alarms = getSystemService(android.app.AlarmManager::class.java)
        return mapOf(
            "battery" to power.isIgnoringBatteryOptimizations(packageName),
            "exactAlarm" to (Build.VERSION.SDK_INT < 31 || alarms.canScheduleExactAlarms()),
            "notifications" to androidx.core.app.NotificationManagerCompat.from(this).areNotificationsEnabled())
    }

    private fun phoneKey(number: String): String {
        val digits = StringBuilder()
        for (ch in number) {
            val d = Character.digit(ch, 10)
            if (d >= 0) digits.append(d)
        }
        return if (digits.length > 10) digits.substring(digits.length - 10) else digits.toString()
    }

    /** Display names for phone numbers: the phone book is read in ONE query and matched by the last 10 digits. */
    private fun contactNames(addresses: List<String>): Map<String, String> {
        if (!has(Manifest.permission.READ_CONTACTS)) return emptyMap()
        val book = HashMap<String, String>()
        contentResolver.query(ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
            arrayOf(ContactsContract.CommonDataKinds.Phone.NUMBER, ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME),
            null, null, null)?.use {
            while (it.moveToNext()) {
                val number = it.getString(0) ?: continue
                val name = it.getString(1)
                val key = phoneKey(number)
                if (key.length >= 7 && !name.isNullOrBlank() && !book.containsKey(key)) book[key] = name
            }
        }
        val names = HashMap<String, String>()
        for (address in addresses) {
            if (address.any { it.isLetter() }) continue
            val key = phoneKey(address)
            val name = if (key.length >= 7) book[key] else null
            if (name != null) names[address] = name
        }
        return names
    }

    /** Read only the local contact thumbnail, never upload a photo or expose the full address book. */
    private fun contactPhoto(address: String): ByteArray? {
        if (!has(Manifest.permission.READ_CONTACTS) || address.isBlank()) return null
        if (phoneKey(address).length < 7) return null
        return try {
            val uri = Uri.withAppendedPath(ContactsContract.PhoneLookup.CONTENT_FILTER_URI, Uri.encode(address))
            contentResolver.query(uri,
                arrayOf(ContactsContract.PhoneLookup.PHOTO_THUMBNAIL_URI), null, null, null)?.use { cur ->
                if (!cur.moveToFirst()) return null
                val path = cur.getString(0)?.takeIf { it.isNotBlank() } ?: return null
                contentResolver.openInputStream(Uri.parse(path))?.use { stream ->
                    stream.readBytes().takeIf { it.size <= 512 * 1024 }
                }
            }
        } catch (_: Exception) { null }
    }

    /** The in-app contact selector reads the phone book once, not one contact at a time.
     * It returns only display name and telephone number, never any contact data to a server.
     */
    private fun listContacts(): List<Map<String, String>> {
        check(has(Manifest.permission.READ_CONTACTS)) { "برای دیدن مخاطبان، اجازه دفترچه تلفن را بدهید." }
        val entries = LinkedHashMap<String, Map<String, String>>()
        contentResolver.query(
            ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
            arrayOf(ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
                ContactsContract.CommonDataKinds.Phone.NUMBER),
            null, null, ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME + " COLLATE LOCALIZED ASC"
        )?.use { cursor ->
            while (cursor.moveToNext()) {
                val name = cursor.getString(0)?.trim().orEmpty()
                val raw = cursor.getString(1)?.trim().orEmpty()
                val digits = buildString {
                    raw.forEach { ch -> val digit = Character.digit(ch, 10); if (digit >= 0) append(digit) }
                }
                if (digits.length !in 7..15) continue
                val number = if (raw.startsWith("+")) "+$digits" else digits
                val key = phoneKey(number)
                if (key.length >= 7 && !entries.containsKey(key))
                    entries[key] = mapOf("name" to (name.ifEmpty { number }), "number" to number)
            }
        }
        return entries.values.toList()
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
        if (::channel.isInitialized) { observeMessages(); foregroundChannel = channel }
    }
    override fun onPause() {
        if (::channel.isInitialized && foregroundChannel === channel) foregroundChannel = null
        super.onPause()
    }
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (contacts?.onActivityResult(requestCode, resultCode, data) == true) return
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
        contacts?.onPermissionResult(requestCode)
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
