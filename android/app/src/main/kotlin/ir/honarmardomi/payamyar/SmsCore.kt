package ir.honarmardomi.payamyar

import android.Manifest
import android.app.*
import android.content.*
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Telephony
import android.telephony.SmsManager
import android.telephony.SubscriptionManager
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import org.json.JSONObject
import java.util.UUID

object SmsCore {
    private fun prefs(c: Context) = c.getSharedPreferences("sms_engine_v1", Context.MODE_PRIVATE)
    fun isDefault(c: Context) = Telephony.Sms.getDefaultSmsPackage(c) == c.packageName
    fun status(c: Context, id: String): String = prefs(c).getString("status:$id", "unknown") ?: "unknown"
    fun read(c: Context, limit: Int, before: Long?, beforeId: Long?): List<Map<String, Any?>> {
        val rows = mutableListOf<Map<String, Any?>>()
        val selection = if (before != null && beforeId != null) "date < ? OR (date = ? AND _id < ?)" else null
        val args = if (selection != null) arrayOf(before.toString(), before.toString(), beforeId.toString()) else null
        c.contentResolver.query(Telephony.Sms.CONTENT_URI, arrayOf("_id", "address", "body", "date", "type", "read", "status"),
            selection, args, "date DESC, _id DESC")?.use { cur ->
            while (rows.size < limit.coerceIn(1, 500) && cur.moveToNext()) rows.add(mapOf(
                "id" to cur.getLong(0), "sender" to cur.getString(1), "body" to cur.getString(2),
                "date" to cur.getLong(3), "outgoing" to (cur.getInt(4) != 1), "read" to (cur.getInt(5) != 0),
                "type" to cur.getInt(4), "delivery" to cur.getInt(6)))
        }
        return rows
    }
    fun subscriptions(c: Context): List<Map<String, Any>> {
        val result = mutableListOf<Map<String, Any>>(mapOf("id" to -1, "label" to "سیم‌کارت پیش‌فرض"))
        if (ContextCompat.checkSelfPermission(c, Manifest.permission.READ_PHONE_STATE) == PackageManager.PERMISSION_GRANTED) {
            c.getSystemService(SubscriptionManager::class.java).activeSubscriptionInfoList?.forEach {
                result.add(mapOf("id" to it.subscriptionId, "label" to "سیم ${it.simSlotIndex + 1} • ${it.displayName}"))
            }
        }
        return result
    }
    @Synchronized fun queue(c: Context, address: String, body: String, sim: Int): String {
        val to = address.replace(Regex("[\\s()-]"), "")
        require(Regex("^\\+?[0-9]{3,15}$").matches(to)) { "شماره گیرنده معتبر نیست." }
        require(body.isNotBlank() && body.length <= 2000) { "متن باید بین ۱ تا ۲۰۰۰ نویسه باشد." }
        check(ContextCompat.checkSelfPermission(c, Manifest.permission.SEND_SMS) == PackageManager.PERMISSION_GRANTED) { "مجوز ارسال پیامک لازم است." }
        val id = UUID.randomUUID().toString()
        val item = JSONObject().put("to", to).put("body", body).put("sim", sim).put("due", System.currentTimeMillis() + 5000)
        check(prefs(c).edit().putString("queue:$id", item.toString()).putString("status:$id", "queued").commit())
        arm(c, id, item.getLong("due"))
        return id
    }
    private fun alarmIntent(c: Context, id: String) = PendingIntent.getBroadcast(c, 0,
        Intent(c, QueueReceiver::class.java).setData(Uri.parse("payamyar:queue/$id")).putExtra("id", id),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    private fun arm(c: Context, id: String, due: Long) {
        c.getSystemService(AlarmManager::class.java).setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, due, alarmIntent(c, id))
    }
    @Synchronized fun cancel(c: Context, id: String): Boolean {
        if (status(c, id) != "queued") return false
        val item = JSONObject(prefs(c).getString("queue:$id", "{}")!!)
        if (System.currentTimeMillis() >= item.optLong("due")) return false
        prefs(c).edit().remove("queue:$id").putString("status:$id", "cancelled").commit()
        c.getSystemService(AlarmManager::class.java).cancel(alarmIntent(c, id))
        return true
    }
    @Synchronized fun recover(c: Context) {
        // A reboot cancels queued sends: do not unexpectedly send an old message later.
        prefs(c).all.keys.filter { it.startsWith("queue:") }.forEach {
            prefs(c).edit().remove(it).putString("status:${it.removePrefix("queue:")}", "send_failed:reboot").commit()
        }
    }
    @Synchronized fun dispatch(c: Context, id: String) {
        val raw = prefs(c).getString("queue:$id", null) ?: return
        if (status(c, id) != "queued") return
        val item = JSONObject(raw)
        if (System.currentTimeMillis() < item.getLong("due")) { arm(c, id, item.getLong("due")); return }
        // Commit before the radio call: never automatically retry an ambiguous send.
        prefs(c).edit().remove("queue:$id").putString("status:$id", "pending").commit()
        var row: Uri? = null
        try {
            val sim = item.getInt("sim")
            val selected = if (sim >= 0) sim else SubscriptionManager.getDefaultSmsSubscriptionId()
            check(SubscriptionManager.isValidSubscriptionId(selected)) { "سیم‌کارت پیش‌فرض ارسال را در تنظیمات گوشی انتخاب کنید." }
            @Suppress("DEPRECATION")
            val manager = if (Build.VERSION.SDK_INT >= 31) c.getSystemService(SmsManager::class.java).createForSubscriptionId(selected)
                else SmsManager.getSmsManagerForSubscriptionId(selected)
            val parts = manager.divideMessage(item.getString("body"))
            if (isDefault(c)) {
                row = c.contentResolver.insert(Telephony.Sms.CONTENT_URI, ContentValues().apply {
                    put("address", item.getString("to")); put("body", item.getString("body"))
                    put("date", System.currentTimeMillis()); put("read", 1); put("type", 4); put("status", 32); put("sub_id", selected)
                    put("thread_id", Telephony.Threads.getOrCreateThreadId(c, item.getString("to")))
                })
                check(row != null) { "ذخیره پیام ممکن نشد." }
            }
            prefs(c).edit().putString("row:$id", row?.toString()).commit()
            fun callbacks(delivered: Boolean) = ArrayList(parts.indices.map { part ->
                PendingIntent.getBroadcast(c, 0, Intent(c, SendStatusReceiver::class.java)
                    .setData(Uri.parse("payamyar:status/$id/$delivered/$part"))
                    .putExtra("id", id).putExtra("part", part).putExtra("parts", parts.size).putExtra("delivered", delivered),
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            })
            manager.sendMultipartTextMessage(item.getString("to"), null, parts, callbacks(false), callbacks(true))
        } catch (e: Exception) {
            prefs(c).edit().putString("status:$id", "send_failed:${e.javaClass.simpleName}").commit()
            if (row != null && isDefault(c)) c.contentResolver.update(row, ContentValues().apply { put("type", 5); put("status", 64) }, null, null)
            notify(c, id.hashCode(), "ارسال پیامک انجام نشد", "پیامیار را باز کنید و وضعیت سیم‌کارت و مجوزها را بررسی کنید.")
        }
    }
    @Synchronized fun receipt(c: Context, intent: Intent, code: Int) {
        val id = intent.getStringExtra("id") ?: return
        val delivered = intent.getBooleanExtra("delivered", false)
        val count = intent.getIntExtra("parts", 1)
        val key = "acks:$id:$delivered"
        val set = prefs(c).getStringSet(key, emptySet())!!.toMutableSet()
        set.add(intent.getIntExtra("part", 0).toString())
        val previous = status(c, id)
        val next = when {
            previous.startsWith("send_failed") || previous == "delivered" -> previous
            code != Activity.RESULT_OK -> if (delivered) "delivery_failed" else "send_failed:$code"
            previous == "delivery_failed" -> previous
            set.size < count -> previous
            delivered -> "delivered"
            else -> "accepted_by_radio"
        }
        prefs(c).edit().putStringSet(key, set).putString("status:$id", next).commit()
        val row = prefs(c).getString("row:$id", null)
        if (row != null && isDefault(c)) {
            val values = ContentValues()
            if (next.startsWith("send_failed")) { values.put("type", 5); values.put("status", 64) }
            else if (next == "accepted_by_radio" || next == "delivered" || next == "delivery_failed") {
                values.put("type", 2); values.put("status", if (next == "delivered") 0 else if (next == "delivery_failed") 64 else 32)
            }
            if (values.size() > 0) c.contentResolver.update(Uri.parse(row), values, null, null)
        }
        if (next.startsWith("send_failed")) notify(c, id.hashCode(), "ارسال پیامک ناموفق بود", "برای بررسی پیام ارسال‌نشده، پیامیار را باز کنید.")
    }
    fun mutate(c: Context, ids: List<Number>, delete: Boolean): Int {
        check(isDefault(c)) { "ابتدا پیامیار را پیامک‌رسان پیش‌فرض کنید." }
        require(ids.size <= 500)
        var affected = 0
        ids.forEach { id ->
            require(id.toLong() > 0)
            val uri = ContentUris.withAppendedId(Telephony.Sms.CONTENT_URI, id.toLong())
            affected += if (delete) c.contentResolver.delete(uri, null, null) else c.contentResolver.update(uri,
                ContentValues().apply { put("read", 1); put("seen", 1) }, null, null)
            c.getSystemService(NotificationManager::class.java).cancel(id.toInt())
        }
        return affected
    }
    fun notify(c: Context, id: Int, title: String, text: String) {
        val manager = c.getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) manager.createNotificationChannel(NotificationChannel("messages", "پیامک‌ها", NotificationManager.IMPORTANCE_HIGH))
        if (Build.VERSION.SDK_INT >= 33 && ContextCompat.checkSelfPermission(c, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return
        val open = PendingIntent.getActivity(c, 0, Intent(c, MainActivity::class.java), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val n = NotificationCompat.Builder(c, "messages").setSmallIcon(android.R.drawable.stat_notify_chat)
            .setContentTitle(title).setContentText(text).setContentIntent(open).setAutoCancel(true)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE).build()
        NotificationManagerCompat.from(c).notify(id, n)
    }
}

class QueueReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val pending = goAsync()
        Thread { try { SmsCore.dispatch(context, intent.getStringExtra("id") ?: "") } finally { pending.finish() } }.start()
    }
}
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) { SmsCore.recover(context) }
}
class SendStatusReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val pending = goAsync(); val code = resultCode
        Thread { try { SmsCore.receipt(context, intent, code) } finally { pending.finish() } }.start()
    }
}
class IncomingSmsReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_DELIVER_ACTION || !SmsCore.isDefault(context)) return
        val pending = goAsync()
        Thread {
            try {
                val parts = Telephony.Sms.Intents.getMessagesFromIntent(intent)
                if (parts.isNotEmpty()) {
                    val address = parts[0].originatingAddress ?: "ناشناس"
                    val body = parts.joinToString("") { it.messageBody ?: "" }
                    val uri = context.contentResolver.insert(Telephony.Sms.Inbox.CONTENT_URI, ContentValues().apply {
                        put("address", address); put("body", body); put("date", System.currentTimeMillis())
                        put("date_sent", parts[0].timestampMillis); put("read", 0); put("seen", 0)
                        put("sub_id", intent.getIntExtra("subscription", -1))
                        put("thread_id", Telephony.Threads.getOrCreateThreadId(context, address))
                    })
                    SmsCore.notify(context, uri?.lastPathSegment?.toIntOrNull() ?: 1, address, "پیامک جدید دریافت شد")
                }
            } finally { pending.finish() }
        }.start()
    }
}
/** Preserve the carrier notification, never silently pretend MMS was downloaded. */
class MmsReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.WAP_PUSH_DELIVER_ACTION) return
        val data = intent.getByteArrayExtra("data") ?: return
        val dir = java.io.File(context.filesDir, "pending_mms").apply { mkdirs() }
        java.io.File(dir, "${System.currentTimeMillis()}.pdu").writeBytes(data)
        SmsCore.notify(context, 2, "پیام چندرسانه‌ای دریافت شد", "این نسخه MMS را دانلود نمی‌کند؛ برای دریافت از پیامک‌رسان قبلی استفاده کنید.")
    }
}
class RespondService : Service() {
    override fun onBind(intent: Intent?) = null
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // System phone app supplies the recipient and the explicitly chosen quick reply.
        val to = intent?.data?.schemeSpecificPart.orEmpty()
        val body = intent?.getStringExtra(Intent.EXTRA_TEXT).orEmpty()
        try { SmsCore.queue(this, to, body, -1) } catch (_: Exception) { }
        stopSelf(startId)
        return START_NOT_STICKY
    }
}
