package ir.honarmardomi.payamyar

import android.Manifest
import android.app.role.RoleManager
import android.content.Intent
import android.content.pm.PackageManager
import android.database.ContentObserver
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Telephony
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private var contactResult: MethodChannel.Result? = null
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
                        try { startActivityForResult(Intent(Intent.ACTION_PICK, android.provider.ContactsContract.CommonDataKinds.Phone.CONTENT_URI), 2110) }
                        catch (e: Exception) { contactResult = null; result.error("CONTACTS", "دفترچه مخاطبان در دسترس نیست.", null) }
                    }
                }
                "requestPermissions" -> {
                    val permissions = mutableListOf(Manifest.permission.READ_SMS, Manifest.permission.SEND_SMS,
                        Manifest.permission.RECEIVE_SMS, Manifest.permission.READ_PHONE_STATE)
                    if (Build.VERSION.SDK_INT >= 33) permissions.add(Manifest.permission.POST_NOTIFICATIONS)
                    ActivityCompat.requestPermissions(this, permissions.toTypedArray(), 2104)
                    result.success(null)
                }
                "requestDefault" -> {
                    if (Build.VERSION.SDK_INT >= 29) {
                        val role = getSystemService(RoleManager::class.java)
                        if (role.isRoleAvailable(RoleManager.ROLE_SMS)) startActivityForResult(role.createRequestRoleIntent(RoleManager.ROLE_SMS), 2105)
                    } else {
                        @Suppress("DEPRECATION")
                        startActivityForResult(Intent(Telephony.Sms.Intents.ACTION_CHANGE_DEFAULT).putExtra(Telephony.Sms.Intents.EXTRA_PACKAGE_NAME, packageName), 2105)
                    }
                    result.success(null)
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
                            "isAvailable" -> packageManager.hasSystemFeature(PackageManager.FEATURE_TELEPHONY_MESSAGING)
                            "permissionStatus" -> mapOf("read" to has(Manifest.permission.READ_SMS),
                                "send" to has(Manifest.permission.SEND_SMS), "default" to SmsCore.isDefault(this))
                            "readMessages" -> SmsCore.read(this, call.argument<Int>("limit") ?: 500,
                                call.argument<Number>("beforeDate")?.toLong(), call.argument<Number>("beforeId")?.toLong())
                            "subscriptions" -> SmsCore.subscriptions(this)
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
        contentResolver.registerContentObserver(Telephony.Sms.CONTENT_URI, true, observer)
    }
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == 2110) {
            val result = contactResult ?: return
            contactResult = null
            try {
                var number: String? = null
                if (resultCode == android.app.Activity.RESULT_OK && data?.data != null) {
                    contentResolver.query(data.data!!, arrayOf(android.provider.ContactsContract.CommonDataKinds.Phone.NUMBER), null, null, null)?.use {
                        if (it.moveToFirst()) number = it.getString(0)
                    }
                }
                result.success(number)
            } catch (_: Exception) { result.error("CONTACTS", "خواندن شماره مخاطب ممکن نشد.", null) }
        }
        if (requestCode == 2105) channel.invokeMethod("messagesChanged", null)
    }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        channel.invokeMethod("messagesChanged", null)
    }
    private fun has(permission: String) = ContextCompat.checkSelfPermission(this, permission) == PackageManager.PERMISSION_GRANTED
    override fun onNewIntent(intent: Intent) { super.onNewIntent(intent); setIntent(intent); channel.invokeMethod("composeIntent", null) }
    override fun onDestroy() { contentResolver.unregisterContentObserver(observer); super.onDestroy() }
}
