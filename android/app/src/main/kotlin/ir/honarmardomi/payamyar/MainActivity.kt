package ir.honarmardomi.payamyar

import android.Manifest
import android.app.Activity
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.database.Cursor
import android.net.Uri
import android.os.Build
import android.provider.Telephony
import android.telephony.SmsManager
import android.telephony.SubscriptionManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * This build is deliberately NOT eligible to become default SMS handler yet:
 * MMS delivery and robust inbound handling are not implemented.
 * Android's existing default SMS app remains responsible for inbound messages.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "ir.honarmardomi.payamyar/sms"
    private val permissions = arrayOf(Manifest.permission.READ_SMS, Manifest.permission.SEND_SMS)
    private val permissionRequestCode = 2104

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "isAvailable" -> result.success(
                            packageManager.hasSystemFeature(PackageManager.FEATURE_TELEPHONY_MESSAGING))
                        "permissionStatus" -> result.success(permissionStatus())
                        "requestPermissions" -> {
                            ActivityCompat.requestPermissions(
                                this, permissions, permissionRequestCode)
                            result.success(true) // Dialog launched, NOT permission granted.
                        }
                        "readMessages" -> {
                            if (!has(Manifest.permission.READ_SMS)) {
                                result.error("PERMISSION", "SMS read permission is not granted", null)
                            } else {
                                val limit = (call.argument<Int>("limit") ?: 200).coerceIn(1, 500)
                                result.success(readMessages(limit))
                            }
                        }
                        "sendSms" -> {
                            if (!has(Manifest.permission.SEND_SMS)) {
                                result.error("PERMISSION", "SMS send permission is not granted", null)
                            } else {
                                val to = call.argument<String>("to")?.trim().orEmpty()
                                val body = call.argument<String>("body").orEmpty()
                                val subscriptionId = call.argument<Int>("subscriptionId")
                                if (!isValidNumber(to) || body.isBlank() || body.length > 2000) {
                                    result.error("INVALID", "Invalid recipient or message", null)
                                } else {
                                    result.success(sendSms(to, body, subscriptionId))
                                }
                            }
                        }
                        "subscriptions" -> result.success(getSubscriptions())
                        "sendStatus" -> {
                            val id = call.argument<String>("requestId").orEmpty()
                            if (!Regex("^[0-9]{10,20}$").matches(id)) {
                                result.error("INVALID", "Invalid request id", null)
                            } else {
                                result.success(getSharedPreferences(
                                    "payamyar_sms_status", Context.MODE_PRIVATE)
                                    .getString(id, "unknown"))
                            }
                        }
                        else -> result.notImplemented()
                    }
                } catch (ex: SecurityException) {
                    result.error("SECURITY", "Permission denied", null)
                } catch (ex: Exception) {
                    result.error("NATIVE_ERROR", ex.javaClass.simpleName, null)
                }
            }
    }

    private fun has(permission: String): Boolean =
        ContextCompat.checkSelfPermission(this, permission) == PackageManager.PERMISSION_GRANTED

    private fun permissionStatus(): Map<String, Boolean> = mapOf(
        "read" to has(Manifest.permission.READ_SMS),
        "send" to has(Manifest.permission.SEND_SMS)
    )

    private fun isValidNumber(value: String): Boolean =
        Regex("^\\+?[0-9]{4,15}$").matches(
            value.replace(" ", "").replace("-", ""))

    private fun readMessages(limit: Int): List<Map<String, Any?>> {
        val entries = mutableListOf<Map<String, Any?>>()
        val projection = arrayOf("_id", "address", "body", "date", "type", "read")
        contentResolver.query(
            Telephony.Sms.CONTENT_URI, projection, null, null, "date DESC"
        )?.use { cursor ->
            val id = cursor.getColumnIndexOrThrow("_id")
            val address = cursor.getColumnIndexOrThrow("address")
            val body = cursor.getColumnIndexOrThrow("body")
            val date = cursor.getColumnIndexOrThrow("date")
            val type = cursor.getColumnIndexOrThrow("type")
            val read = cursor.getColumnIndexOrThrow("read")
            while (cursor.moveToNext() && entries.size < limit) {
                entries.add(mapOf(
                    "id" to cursor.getLong(id),
                    "sender" to (cursor.getString(address) ?: ""),
                    "body" to (cursor.getString(body) ?: ""),
                    "date" to cursor.getLong(date),
                    "outgoing" to (cursor.getInt(type) == Telephony.Sms.MESSAGE_TYPE_SENT),
                    "read" to (cursor.getInt(read) != 0)
                ))
            }
        }
        return entries
    }

    private fun getSubscriptions(): List<Map<String, Any?>> {
        // Avoid READ_PHONE_STATE or privileged subscription data in this pilot.
        // INVALID_SUBSCRIPTION_ID means use the system's default SMS SIM.
        return listOf(mapOf(
            "id" to SubscriptionManager.INVALID_SUBSCRIPTION_ID,
            "label" to "سیم‌کارت پیش‌فرض دستگاه"
        ))
    }

    private fun sendSms(to: String, body: String, subscriptionId: Int?): String {
        val cleanedTo = to.replace(" ", "").replace("-", "")
        val manager = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            if (subscriptionId != null &&
                subscriptionId != SubscriptionManager.INVALID_SUBSCRIPTION_ID) {
                getSystemService(SmsManager::class.java).createForSubscriptionId(subscriptionId)
            } else {
                getSystemService(SmsManager::class.java)
            }
        } else {
            @Suppress("DEPRECATION")
            if (subscriptionId != null &&
                subscriptionId != SubscriptionManager.INVALID_SUBSCRIPTION_ID) {
                SmsManager.getSmsManagerForSubscriptionId(subscriptionId)
            } else {
                SmsManager.getDefault()
            }
        }
        val id = System.currentTimeMillis().toString()
        val parts = manager.divideMessage(body)
        val sent = ArrayList<PendingIntent>(parts.size)
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        for (part in parts.indices) {
            val intent = Intent(this, SendStatusReceiver::class.java).apply {
                action = "ir.honarmardomi.payamyar.SMS_SENT"
                putExtra("requestId", id)
                putExtra("part", part)
                putExtra("parts", parts.size)
            }
            sent.add(PendingIntent.getBroadcast(this, ((System.nanoTime() + part) and 0x7fffffff).toInt(), intent, flags))
        }
        getSharedPreferences("payamyar_sms_status", Context.MODE_PRIVATE)
            .edit().putString(id, "pending").apply()
        manager.sendMultipartTextMessage(cleanedTo, null, parts, sent, null)
        return id // request queued by Android, not proof of carrier delivery
    }
}

class SendStatusReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val requestId = intent.getStringExtra("requestId") ?: return
        val parts = intent.getIntExtra("parts", 1).coerceAtLeast(1)
        val prefs = context.getSharedPreferences("payamyar_sms_status", Context.MODE_PRIVATE)
        val previous = prefs.getString(requestId, "pending") ?: "pending"
        if (previous.startsWith("send_failed")) return
        if (resultCode != Activity.RESULT_OK) {
            prefs.edit().putString(requestId, "send_failed:$resultCode").apply()
            return
        }
        val acknowledged = prefs.getInt("$requestId:acknowledged", 0) + 1
        prefs.edit()
            .putInt("$requestId:acknowledged", acknowledged)
            .putString(requestId, if (acknowledged >= parts) "accepted_by_radio" else "pending")
            .apply()
    }
}
