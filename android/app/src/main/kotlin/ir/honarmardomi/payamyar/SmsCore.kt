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
    private val COLUMNS = arrayOf("_id", "address", "body", "date", "type", "read", "status")
    private const val ORDER = "date DESC, _id DESC"

    /** Reads up to [limit] rows from the cursor as compact columns (typed arrays cross to Dart far faster than maps). */
    private fun chunk(cur: android.database.Cursor, limit: Int): Map<String, Any> {
        val ids = LongArray(limit); val dates = LongArray(limit)
        val types = IntArray(limit); val reads = IntArray(limit); val status = IntArray(limit)
        val senders = ArrayList<String?>(limit); val bodies = ArrayList<String?>(limit)
        var n = 0
        while (n < limit && cur.moveToNext()) {
            ids[n] = cur.getLong(0); senders.add(cur.getString(1)); bodies.add(cur.getString(2))
            dates[n] = cur.getLong(3); types[n] = cur.getInt(4); reads[n] = cur.getInt(5); status[n] = cur.getInt(6)
            n++
        }
        return mapOf("n" to n, "ids" to ids.copyOf(n), "dates" to dates.copyOf(n), "types" to types.copyOf(n),
            "reads" to reads.copyOf(n), "status" to status.copyOf(n), "senders" to senders, "bodies" to bodies)
    }

    /** Newest [limit] messages; used for quick refreshes after a change. */
    fun read(c: Context, limit: Int): Map<String, Any> {
        if (isDefault(c)) drainIncoming(c)
        c.contentResolver.query(Telephony.Sms.CONTENT_URI, COLUMNS, null, null, ORDER)?.use { cur ->
            return chunk(cur, limit.coerceIn(1, 5000))
        }
        return chunk(android.database.MatrixCursor(COLUMNS), 1)
    }

    /** Whole inbox in ONE query: a small first page for instant display, then large pages. Returns the total. */
    fun stream(c: Context, emit: (Map<String, Any>) -> Unit): Int {
        if (isDefault(c)) drainIncoming(c)
        var total = 0
        c.contentResolver.query(Telephony.Sms.CONTENT_URI, COLUMNS, null, null, ORDER)?.use { cur ->
            var size = 150
            while (true) {
                val page = chunk(cur, size)
                val n = page["n"] as Int
                if (n > 0) { total += n; emit(page) }
                if (n < size) break
                size = 4000
            }
        }
        return total
    }

    /** Marks every unread incoming message from this sender as read (notification "خوانده شد" action). */
    fun markAddressRead(c: Context, address: String): Int {
        if (!isDefault(c)) return 0
        return c.contentResolver.update(Telephony.Sms.Inbox.CONTENT_URI,
            ContentValues().apply { put("read", 1); put("seen", 1) }, "address = ? AND read = 0", arrayOf(address))
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
    /** Resolve a usable subscription BEFORE showing the five-second undo message.
     * Android returns INVALID_SUBSCRIPTION_ID when the device is set to "Ask every time".
     * On single-SIM devices we can select the sole active subscription automatically.
     */ 
    private fun resolveSubscription(c: Context, requested: Int): Int {
        val service = c.getSystemService(SubscriptionManager::class.java)
        val active = if (ContextCompat.checkSelfPermission(c, Manifest.permission.READ_PHONE_STATE) ==
            PackageManager.PERMISSION_GRANTED) {
            try { service.activeSubscriptionInfoList?.map { it.subscriptionId }.orEmpty() }
            catch (_: SecurityException) { emptyList() }
        } else emptyList()
        if (requested >= 0) {
            check(active.isEmpty() || active.contains(requested)) { "سیم‌کارت انتخابی فعال نیست؛ سیم‌کارت دیگری انتخاب کنید." }
            return requested
        }
        @Suppress("DEPRECATION")
        val defaultId = SubscriptionManager.getDefaultSmsSubscriptionId()
        if (defaultId >= 0 && defaultId != Int.MAX_VALUE &&
            (active.isEmpty() || active.contains(defaultId))) return defaultId
        if (active.size == 1) return active.first()
        error(if (active.size > 1) "برای ارسال، سیم‌کارت ۱ یا ۲ را در پیامیار انتخاب کنید."
            else "سیم‌کارت فعال شناسایی نشد. وضعیت سیم‌کارت و دسترسی تلفن را بررسی کنید.")
    }

    @Synchronized fun queue(c: Context, address: String, body: String, sim: Int, delayMs: Long = 5000): String {
        require(delayMs in 0L..(30L * 24 * 60 * 60 * 1000)) { "زمان ارسال باید حداکثر ۳۰ روز آینده باشد." }
        val to = address.replace(Regex("[\\s()-]"), "")
        require(Regex("^\\+?[0-9]{3,15}$").matches(to)) { "شماره گیرنده معتبر نیست." }
        require(body.isNotBlank() && body.length <= 2000) { "متن باید بین ۱ تا ۲۰۰۰ نویسه باشد." }
        check(ContextCompat.checkSelfPermission(c, Manifest.permission.SEND_SMS) == PackageManager.PERMISSION_GRANTED) { "مجوز ارسال پیامک لازم است." }
        val subscriptionId = resolveSubscription(c, sim)
        val id = UUID.randomUUID().toString()
        val item = JSONObject().put("to", to).put("body", body).put("sim", subscriptionId)
            .put("due", System.currentTimeMillis() + delayMs).put("scheduled", delayMs > 10000)
        check(prefs(c).edit().putString("queue:$id", item.toString()).putString("status:$id", "queued").commit())
        if (delayMs > 0) arm(c, id, item.getLong("due"))
        return id
    }
    private fun alarmIntent(c: Context, id: String) = PendingIntent.getBroadcast(c, 0,
        Intent(c, QueueReceiver::class.java).setData(Uri.parse("payamyar:queue/$id")).putExtra("id", id),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    private fun arm(c: Context, id: String, due: Long) {
        val alarms = c.getSystemService(AlarmManager::class.java)
        // Exact alarm keeps the 5 s undo window honest when the app is in the background.
        // Android 12+ may deny exact alarms (default on Android 14); then fall back to an inexact one.
        try {
            if (Build.VERSION.SDK_INT < 31 || alarms.canScheduleExactAlarms())
                alarms.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, due, alarmIntent(c, id))
            else alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, due, alarmIntent(c, id))
        } catch (_: SecurityException) {
            // Exact-alarm permission can be revoked between checking and scheduling.
            alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, due, alarmIntent(c, id))
        }
    }
    const val ACTION_DRAIN = "ir.honarmardomi.payamyar.DRAIN_INCOMING"
    private fun incomingDir(c: Context) = java.io.File(c.filesDir, "incoming_sms")
    fun hasPendingIncoming(c: Context) = incomingDir(c).listFiles()?.any { it.extension == "json" } == true
    /** Retry saved incoming SMS that could not be written to the provider, without needing the app to open. */
    fun scheduleDrain(c: Context, delayMs: Long) {
        val intent = PendingIntent.getBroadcast(c, 1, Intent(c, QueueReceiver::class.java).setAction(ACTION_DRAIN),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        c.getSystemService(AlarmManager::class.java)
            .setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, System.currentTimeMillis() + delayMs, intent)
    }
    fun drainAndReschedule(c: Context, retryMs: Long) {
        if (!isDefault(c)) return
        drainIncoming(c)
        if (hasPendingIncoming(c)) scheduleDrain(c, retryMs)
    }
    @Synchronized fun cancel(c: Context, id: String): Boolean {
        if (status(c, id) != "queued") return false
        val item = JSONObject(prefs(c).getString("queue:$id", "{}")!!)
        if (System.currentTimeMillis() >= item.optLong("due")) return false
        prefs(c).edit().remove("queue:$id").putString("status:$id", "cancelled").commit()
        c.getSystemService(AlarmManager::class.java).cancel(alarmIntent(c, id))
        return true
    }
    /** Restore future scheduled sends after restart; never unexpectedly replay expired SMS. */
    @Synchronized fun recover(c: Context) {
        val now = System.currentTimeMillis()
        prefs(c).all.keys.filter { it.startsWith("queue:") }.forEach { key ->
            val id = key.removePrefix("queue:")
            val entry = runCatching { JSONObject(prefs(c).getString(key, "{}")!!) }.getOrNull()
            if (entry != null && entry.optBoolean("scheduled") && entry.optLong("due") > now + 5000) {
                arm(c, id, entry.getLong("due"))
            } else {
                prefs(c).edit().remove(key).putString("status:$id", "cancelled_after_restart").commit()
            }
        }
    }
    /** Read native queued messages so their scheduled state remains visible after app restart. */
    @Synchronized fun pending(c: Context): List<Map<String, Any>> =
        prefs(c).all.keys.filter { it.startsWith("queue:") }.mapNotNull { key ->
            val id = key.removePrefix("queue:")
            if (status(c, id) != "queued") return@mapNotNull null
            try {
                val item = JSONObject(prefs(c).getString(key, "{}")!!)
                mapOf("id" to id, "to" to item.getString("to"), "body" to item.getString("body"),
                    "due" to item.getLong("due"), "scheduled" to item.optBoolean("scheduled"))
            } catch (_: Exception) { null }
        }.sortedBy { it["due"] as Long }
    @Synchronized fun dispatch(c: Context, id: String) {
        val raw = prefs(c).getString("queue:$id", null) ?: return
        if (status(c, id) != "queued") return
        val item = JSONObject(raw)
        if (System.currentTimeMillis() < item.getLong("due")) { arm(c, id, item.getLong("due")); return }
        // Commit before the radio call: never automatically retry an ambiguous send.
        prefs(c).edit().remove("queue:$id").putString("status:$id", "pending").commit()
        var row: Uri? = null
        try {
            val selected = resolveSubscription(c, item.getInt("sim"))
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
                    PendingIntent.FLAG_UPDATE_CURRENT or (if (delivered && Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else if (delivered) 0 else PendingIntent.FLAG_IMMUTABLE))
            })
            check(parts.isNotEmpty()) { "متن پیامک خالی است." }
            if (parts.size == 1) {
                manager.sendTextMessage(item.getString("to"), null, parts[0], callbacks(false)[0], callbacks(true)[0])
            } else {
                manager.sendMultipartTextMessage(item.getString("to"), null, parts, callbacks(false), callbacks(true))
            }
        } catch (e: Exception) {
            val reason = (e.message ?: e.javaClass.simpleName).take(180)
            prefs(c).edit().putString("status:$id", "send_failed:$reason").commit()
            if (row != null && isDefault(c)) c.contentResolver.update(row, ContentValues().apply { put("type", 5); put("status", 64) }, null, null)
            notify(c, id.hashCode(), "ارسال پیامک انجام نشد", "پیامیار را باز کنید و وضعیت سیم‌کارت و مجوزها را بررسی کنید.")
        }
    }
    @Synchronized fun receipt(c: Context, intent: Intent, code: Int) {
        val id = intent.getStringExtra("id") ?: return
        val delivered = intent.getBooleanExtra("delivered", false)
        var deliveryFailure = false
        if (delivered) {
            val pdu = intent.getByteArrayExtra("pdu") ?: return
            @Suppress("DEPRECATION")
            val report = intent.getStringExtra("format")?.let { android.telephony.SmsMessage.createFromPdu(pdu, it) }
                ?: android.telephony.SmsMessage.createFromPdu(pdu)
            val reportStatus = report?.status ?: return
            if (reportStatus < 0 || reportStatus in 32..63) return
            deliveryFailure = reportStatus >= 64
        }
        val count = intent.getIntExtra("parts", 1)
        val key = "acks:$id:$delivered"
        val set = prefs(c).getStringSet(key, emptySet())!!.toMutableSet()
        set.add(intent.getIntExtra("part", 0).toString())
        val previous = status(c, id)
        // A delivery report is stronger evidence than a vendor-specific SENT callback.
        // Some devices report RESULT_CANCELED (0) even when the SMS was transmitted.
        // Treat that result as unconfirmed, never as proof of a failed transmission.
        val next = when {
            delivered && !deliveryFailure -> "delivered"
            previous == "delivered" -> previous
            delivered && deliveryFailure -> "delivery_failed"
            delivered -> previous
            code == Activity.RESULT_CANCELED -> if (previous == "pending" || previous == "queued") "send_unconfirmed" else previous
            code != Activity.RESULT_OK -> if (previous == "accepted_by_radio") previous else "send_failed:$code"
            previous.startsWith("send_failed") -> previous
            set.size < count -> previous
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
        if (next.startsWith("send_failed") && next != previous)
            notify(c, id.hashCode(), "ارسال پیامک ناموفق بود", "شبکه ارسال را رد کرد؛ سیم‌کارت و وضعیت پیام را بررسی کنید.")
        else if (next == "delivered" && previous.startsWith("send_failed"))
            c.getSystemService(NotificationManager::class.java).cancel(id.hashCode())
    }
    @Synchronized fun drainIncoming(c: Context) {
        val dir = incomingDir(c)
        dir.listFiles()?.filter { it.extension == "json" }?.forEach { file ->
            try {
                val item = JSONObject(file.readText())
                val address = item.getString("address")
                val body = item.getString("body")
                val sent = item.getLong("sent")
                val sim = item.getInt("sim")
                // Retry a saved journal after provider errors without duplicating a completed insert.
                var exists = false
                c.contentResolver.query(Telephony.Sms.Inbox.CONTENT_URI, arrayOf("_id"),
                    "address = ? AND body = ? AND date_sent = ? AND sub_id = ?",
                    arrayOf(address, body, sent.toString(), sim.toString()), null)?.use { exists = it.moveToFirst() }
                if (!exists) {
                    val uri = c.contentResolver.insert(Telephony.Sms.Inbox.CONTENT_URI, ContentValues().apply {
                        put("address", address); put("body", body); put("date", item.getLong("received"))
                        put("date_sent", sent); put("read", 0); put("seen", 0); put("sub_id", sim)
                        put("thread_id", Telephony.Threads.getOrCreateThreadId(c, address))
                    })
                    check(uri != null)
                    Notifier.incoming(c, address, contactName(c, address), body, item.getLong("received"))
                }
                file.delete()
            } catch (_: Exception) {
                // Keep the private journal for retry on the next inbox refresh.
            }
        }
    }
    @Synchronized fun receive(c: Context, intent: Intent) {
        val parts = Telephony.Sms.Intents.getMessagesFromIntent(intent)
        if (parts.isEmpty()) return
        val item = JSONObject().put("address", parts[0].originatingAddress ?: "ناشناس")
            .put("body", parts.joinToString("") { it.messageBody ?: "" })
            .put("sent", parts[0].timestampMillis).put("received", System.currentTimeMillis())
            .put("sim", intent.getIntExtra("subscription", -1))
        val dir = incomingDir(c).apply { mkdirs() }
        val file = android.util.AtomicFile(java.io.File(dir, "${UUID.randomUUID()}.json"))
        val output = file.startWrite()
        try { output.write(item.toString().toByteArray(Charsets.UTF_8)); file.finishWrite(output) }
        catch (e: Exception) { file.failWrite(output); throw e }
        drainIncoming(c)
        if (hasPendingIncoming(c)) scheduleDrain(c, 60_000)
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
        }
        return affected
    }
    fun contactName(c: Context, address: String): String? {
        if (ContextCompat.checkSelfPermission(c, Manifest.permission.READ_CONTACTS) != PackageManager.PERMISSION_GRANTED) return null
        if (address.none { it.isDigit() }) return null
        return try {
            val uri = Uri.withAppendedPath(android.provider.ContactsContract.PhoneLookup.CONTENT_FILTER_URI, Uri.encode(address))
            c.contentResolver.query(uri, arrayOf(android.provider.ContactsContract.PhoneLookup.DISPLAY_NAME), null, null, null)?.use {
                if (it.moveToFirst()) it.getString(0) else null
            }
        } catch (_: Exception) { null }
    }
    fun notify(c: Context, id: Int, title: String, text: String) {
        val manager = c.getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) manager.createNotificationChannel(NotificationChannel("alerts", "هشدارهای پیامیار", NotificationManager.IMPORTANCE_DEFAULT))
        if (Build.VERSION.SDK_INT >= 33 && ContextCompat.checkSelfPermission(c, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return
        val open = PendingIntent.getActivity(c, 0, Intent(c, MainActivity::class.java), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val n = NotificationCompat.Builder(c, "alerts").setSmallIcon(R.drawable.ic_stat_payamyar).setColor(0xFF087F81.toInt())
            .setContentTitle(title).setContentText(text).setStyle(NotificationCompat.BigTextStyle().bigText(text))
            .setContentIntent(open).setAutoCancel(true)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE).build()
        NotificationManagerCompat.from(c).notify(id, n)
    }
}

class QueueReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val pending = goAsync()
        Thread {
            try {
                if (intent.action == SmsCore.ACTION_DRAIN) SmsCore.drainAndReschedule(context, 15 * 60_000L)
                else SmsCore.dispatch(context, intent.getStringExtra("id") ?: "")
            } catch (_: Exception) {
            } finally { pending.finish() }
        }.start()
    }
}
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return
        val pending = goAsync()
        Thread {
            try {
                SmsCore.recover(context)
                SmsCore.drainAndReschedule(context, 15 * 60_000L)
            } catch (_: Exception) {
            } finally { pending.finish() }
        }.start()
    }
}
class SendStatusReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val pending = goAsync(); val code = resultCode
        Thread { try { SmsCore.receipt(context, intent, code) } catch (_: Exception) { } finally { pending.finish() } }.start()
    }
}
class IncomingSmsReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_DELIVER_ACTION || !SmsCore.isDefault(context)) return
        val pending = goAsync()
        Thread {
            try {
                SmsCore.receive(context, intent)
            } catch (_: Exception) {
                SmsCore.notify(context, 3, "خطا در ذخیره پیامک", "فضای ذخیره‌سازی و مجوزهای پیامیار را بررسی کنید.")
            } finally { pending.finish() }
        }.start()
    }
}
/** Preserve the carrier notification, never silently pretend MMS was downloaded. */
class MmsReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.WAP_PUSH_DELIVER_ACTION) return
        if (!SmsCore.isDefault(context)) return
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
