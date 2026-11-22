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
    private fun requireDefault(c: Context) {
        check(isDefault(c)) { "برای دسترسی به پیامک، پیام‌یار را پیامک‌رسان پیش‌فرض انتخاب کنید." }
    }
    fun status(c: Context, id: String): String = prefs(c).getString("status:$id", "unknown") ?: "unknown"
    private val COLUMNS = arrayOf("_id", "address", "body", "date", "type", "read", "status", "sub_id")
    private const val ORDER = "date DESC, _id DESC"

    /** Reads up to [limit] rows from the cursor as compact columns (typed arrays cross to Dart far faster than maps). */
    private fun simSlots(c: Context): Map<Int, Int> = try {
        c.getSystemService(SubscriptionManager::class.java).activeSubscriptionInfoList.orEmpty()
            .filter { it.simSlotIndex >= 0 }.associate { it.subscriptionId to it.simSlotIndex + 1 }
    } catch (_: SecurityException) { emptyMap() }

    private fun chunk(cur: android.database.Cursor, limit: Int, slots: Map<Int, Int> = emptyMap()): Map<String, Any> {
        val sim = IntArray(limit)
        val ids = LongArray(limit); val dates = LongArray(limit)
        val types = IntArray(limit); val reads = IntArray(limit); val status = IntArray(limit)
        val senders = ArrayList<String?>(limit); val bodies = ArrayList<String?>(limit)
        var n = 0
        while (n < limit && cur.moveToNext()) {
            ids[n] = cur.getLong(0); senders.add(cur.getString(1)); bodies.add(cur.getString(2))
            dates[n] = cur.getLong(3); types[n] = cur.getInt(4); reads[n] = cur.getInt(5); status[n] = cur.getInt(6)
            sim[n] = if (cur.isNull(7)) 0 else slots[cur.getInt(7)] ?: 0
            n++
        }
        return mapOf("n" to n, "ids" to ids.copyOf(n), "dates" to dates.copyOf(n), "types" to types.copyOf(n),
            "slots" to sim.copyOf(n), "reads" to reads.copyOf(n), "status" to status.copyOf(n), "senders" to senders, "bodies" to bodies)
    }

    /** Newest [limit] messages; used for quick refreshes after a change. */
    fun read(c: Context, limit: Int): Map<String, Any> {
        requireDefault(c)
        drainIncoming(c)
        c.contentResolver.query(Telephony.Sms.CONTENT_URI, COLUMNS, null, null, ORDER)?.use { cur ->
            return chunk(cur, limit.coerceIn(1, 5000), simSlots(c))
        }
        return chunk(android.database.MatrixCursor(COLUMNS), 1)
    }

    /** Whole inbox in ONE query: a small first page for instant display, then large pages. Returns the total. */
    fun stream(c: Context, emit: (Map<String, Any>) -> Unit): Int {
        requireDefault(c)
        drainIncoming(c)
        var total = 0
        c.contentResolver.query(Telephony.Sms.CONTENT_URI, COLUMNS, null, null, ORDER)?.use { cur ->
            val slots = simSlots(c)
            var size = 48
            while (true) {
                requireDefault(c)
                val page = chunk(cur, size, slots)
                val n = page["n"] as Int
                if (n > 0) { total += n; emit(page) }
                if (n < size) break
                size = 512
            }
        }
        return total
    }

    /** Marks every unread incoming message from this sender as read (notification "خوانده شد" action). */
    fun markAddressRead(c: Context, address: String, through: Long = Long.MAX_VALUE): Int {
        if (!isDefault(c)) return 0
        return c.contentResolver.update(Telephony.Sms.Inbox.CONTENT_URI,
            ContentValues().apply { put("read", 1); put("seen", 1) }, "address = ? AND read = 0 AND date <= ?", arrayOf(address, through.toString()))
    }
    fun subscriptions(c: Context): List<Map<String, Any>> {
        val result = mutableListOf<Map<String, Any>>()
        if (ContextCompat.checkSelfPermission(c, Manifest.permission.READ_PHONE_STATE) == PackageManager.PERMISSION_GRANTED) {
            c.getSystemService(SubscriptionManager::class.java).activeSubscriptionInfoList?.forEach {
                result.add(mapOf("id" to it.subscriptionId, "label" to "سیم ${it.simSlotIndex + 1} • ${it.displayName}"))
            }
        }
        return result
    }
    /** Never route an SMS through Android's implicit default/ask-every-time subscription.
     * A physical SIM must be selected and validated before the message enters the queue.
     */
    fun resolveSubscription(c: Context, requested: Int): Int {
        val service = c.getSystemService(SubscriptionManager::class.java)
        val active = if (ContextCompat.checkSelfPermission(c, Manifest.permission.READ_PHONE_STATE) ==
            PackageManager.PERMISSION_GRANTED) {
            try { service.activeSubscriptionInfoList?.map { it.subscriptionId }.orEmpty() }
            catch (_: SecurityException) { emptyList() }
        } else emptyList()
        check(active.isNotEmpty()) { "سیم‌کارت فعال شناسایی نشد. دسترسی تلفن را بررسی کنید." }
        // Background actions (quick reply and scheduled greetings) pass -1,
        // so use the last *explicitly selected* in-app SIM, never Android's
        // implicit default subscription. A single active SIM is unambiguous.
        val remembered = try {
            c.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                .getLong("flutter.selected_send_sim", -1L).toInt()
        } catch (_: ClassCastException) { -1 }
        val selected = if (requested >= 0) requested
            else if (active.size == 1) active.first()
            else remembered
        check(selected >= 0) { "قبل از ارسال، سیم‌کارت ۱ یا ۲ را در پیام‌یار انتخاب کنید." }
        check(active.contains(selected)) { "سیم‌کارت انتخابی دیگر فعال نیست؛ دوباره انتخاب کنید." }
        return selected
    }

    @Synchronized fun queue(c: Context, address: String, body: String, sim: Int, delayMs: Long = 5000, group: Boolean = false, groupTime: Long? = null): String {
        requireDefault(c)
        require(delayMs in 0L..(30L * 24 * 60 * 60 * 1000)) { "زمان ارسال باید حداکثر ۳۰ روز آینده باشد." }
        val to = address.map { it.digitToIntOrNull()?.digitToChar() ?: it }.joinToString("").replace(Regex("[\\s()-]"), "")
        require(Regex("^\\+?[0-9]{3,15}$").matches(to)) { "شماره گیرنده معتبر نیست." }
        require(body.isNotBlank() && body.length <= 2000) { "متن باید بین ۱ تا ۲۰۰۰ نویسه باشد." }
        check(ContextCompat.checkSelfPermission(c, Manifest.permission.SEND_SMS) == PackageManager.PERMISSION_GRANTED) { "مجوز ارسال پیامک لازم است." }
        val subscriptionId = resolveSubscription(c, sim)
        val id = UUID.randomUUID().toString()
        val item = JSONObject().put("to", to).put("body", body).put("sim", subscriptionId)
            .put("due", System.currentTimeMillis() + delayMs).put("scheduled", delayMs > 10000)
        if (groupTime != null) item.put("groupTime", groupTime)
        val grouped = group && delayMs <= 10000
        val due = item.getLong("due")
        // "t:$id" lets prune() drop the oldest finished sends first.
        val edit = prefs(c).edit().putString("queue:$id", SecureVault.encryptQueue(item.toString()))
            .putString("status:$id", "queued").putLong("t:$id", System.currentTimeMillis())
        if (grouped) edit.putLong("group:$id", due)
        check(edit.commit())
        try {
            if (grouped) {
                // The group shares ONE PendingIntent. After process death groupDue is forgotten,
                // so arming with only this item's due could postpone an earlier stored item.
                val earliest = prefs(c).all.entries.filter { it.key.startsWith("group:") }
                    .mapNotNull { it.value as? Long }.minOrNull() ?: due
                scheduleGroup(c.applicationContext, minOf(due, earliest))
            } else arm(c, id, due)
        } catch (e: RuntimeException) {
            prefs(c).edit().remove("queue:$id").remove("group:$id").remove("status:$id").remove("t:$id").commit()
            throw e
        }
        return id
    }
    private const val GROUP_WAKE = "group-wake"
    private val groupWorker = java.util.concurrent.Executors.newSingleThreadScheduledExecutor()
    private var groupTimer: java.util.concurrent.ScheduledFuture<*>? = null
    private var groupDue = Long.MAX_VALUE

    // One durable alarm backs the whole group. An in-process timer avoids waiting
    // for an inexact alarm while the application is running.
    private fun scheduleGroup(c: Context, due: Long) {
        if (groupDue <= due && groupTimer?.isDone == false) return
        arm(c, GROUP_WAKE, due)
        groupTimer?.cancel(false)
        groupDue = due
        groupTimer = groupWorker.schedule({ drainGroup(c) },
            (due - System.currentTimeMillis()).coerceAtLeast(0), java.util.concurrent.TimeUnit.MILLISECONDS)
    }

    @Synchronized fun drainGroup(c: Context) {
        groupTimer?.cancel(false)
        groupTimer = null
        groupDue = Long.MAX_VALUE
        val rows = prefs(c).all.entries.filter { it.key.startsWith("group:") && it.value is Long }
            .sortedBy { it.value as Long }
        val first = rows.firstOrNull() ?: return
        val due = first.value as Long
        val now = System.currentTimeMillis()
        if (due > now) { scheduleGroup(c, due); return }
        // Arm the next wake before claiming this message, including recovery
        // if the process exits before dispatch writes its durable claim.
        scheduleGroup(c, now + 650)
        dispatch(c, first.key.removePrefix("group:"))
    }

    fun receiveAlarm(c: Context, id: String) {
        if (id == GROUP_WAKE) drainGroup(c) else dispatch(c, id)
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
        val item = runCatching { JSONObject(SecureVault.decryptQueue(prefs(c).getString("queue:$id", "{}")!!)) }.getOrNull() ?: return false
        if (System.currentTimeMillis() >= item.optLong("due")) return false
        prefs(c).edit().remove("queue:$id").remove("group:$id").putString("status:$id", "cancelled").commit()
        c.getSystemService(AlarmManager::class.java).cancel(alarmIntent(c, id))
        return true
    }
    /** Removes bookkeeping of finished sends so the preferences file does not grow forever. */
    @Synchronized fun prune(c: Context, keep: Int = 300) {
        val p = prefs(c)
        val all = p.all
        val now = System.currentTimeMillis()
        fun age(id: String) = (all["t:$id"] as? Long) ?: 0L // missing (pre-upgrade) = oldest
        // Only terminal states. Dropping "queued"/"pending" (in-flight) would lose the row:
        // link and leave the provider row stuck in the outbox. "send_unconfirmed" may still
        // get its radio callback, so it is kept for a day.
        fun terminal(id: String, s: String) = s == "delivered" || s == "delivery_failed" ||
            s == "accepted_by_radio" || s.startsWith("send_failed") || s.startsWith("cancelled") ||
            s == "queue_unreadable" || (s == "send_unconfirmed" && now - age(id) > 24L * 60 * 60 * 1000)
        val finished = all.entries.filter { it.key.startsWith("status:") }
            .map { it.key.removePrefix("status:") to ((it.value as? String) ?: "") }
            .filter { (id, s) -> !all.containsKey("queue:$id") && terminal(id, s) }
            .map { it.first }
            .sortedBy { age(it) } // oldest first, not HashMap order
        if (finished.size <= keep) return
        val edit = p.edit()
        finished.take(finished.size - keep).forEach { id ->
            listOf("status:$id", "row:$id", "notified:$id", "acks:$id:true", "acks:$id:false",
                "ok:$id:true", "ok:$id:false", "t:$id").forEach { edit.remove(it) }
        }
        edit.apply()
    }
    /** Restore future scheduled sends after restart; never unexpectedly replay expired SMS. */
    @Synchronized fun recover(c: Context) {
        val now = System.currentTimeMillis()
        prefs(c).all.keys.filter { it.startsWith("queue:") }.forEach { key ->
            val id = key.removePrefix("queue:")
            val entry = runCatching { JSONObject(SecureVault.decryptQueue(prefs(c).getString(key, "{}")!!)) }.getOrNull()
            if (entry != null && entry.optBoolean("scheduled") && entry.optLong("due") > now + 5000) {
                arm(c, id, entry.getLong("due"))
            } else {
                prefs(c).edit().remove(key).remove("group:$id").putString("status:$id", "cancelled_after_restart").commit()
            }
        }
    }
    /** Read native queued messages so their scheduled state remains visible after app restart. */
    @Synchronized fun pending(c: Context): List<Map<String, Any>> =
        prefs(c).all.keys.filter { it.startsWith("queue:") }.mapNotNull { key ->
            val id = key.removePrefix("queue:")
            if (status(c, id) != "queued") return@mapNotNull null
            try {
                val item = JSONObject(SecureVault.decryptQueue(prefs(c).getString(key, "{}")!!))
                mapOf("id" to id, "to" to item.getString("to"), "body" to item.getString("body"),
                    "due" to item.getLong("due"), "scheduled" to item.optBoolean("scheduled"))
            } catch (_: Exception) { null }
        }.sortedBy { it["due"] as Long }
    @Synchronized fun dispatch(c: Context, id: String) {
        val raw = prefs(c).getString("queue:$id", null) ?: return
        if (status(c, id) != "queued") return
        val item = try {
            JSONObject(SecureVault.decryptQueue(raw))
        } catch (_: Exception) {
            // A missing Keystore key or tampered queue must never send an SMS.
            prefs(c).edit().remove("queue:$id").remove("group:$id").putString("status:$id", "queue_unreadable").commit()
            return
        }
        if (System.currentTimeMillis() < item.getLong("due")) { arm(c, id, item.getLong("due")); return }
        // Commit before the radio call: never automatically retry an ambiguous send.
        check(prefs(c).edit().remove("queue:$id").remove("group:$id").putString("status:$id", "pending").commit())
        var row: Uri? = null
        try {
            requireDefault(c)
            val selected = resolveSubscription(c, item.getInt("sim"))
            @Suppress("DEPRECATION")
            val manager = if (Build.VERSION.SDK_INT >= 31) c.getSystemService(SmsManager::class.java).createForSubscriptionId(selected)
                else SmsManager.getSmsManagerForSubscriptionId(selected)
            val parts = manager.divideMessage(item.getString("body"))
            row = c.contentResolver.insert(Telephony.Sms.Outbox.CONTENT_URI, ContentValues().apply {
                put("address", item.getString("to")); put("body", item.getString("body"))
                put("date", item.optLong("groupTime", System.currentTimeMillis())); put("read", 1); put("type", 4); put("status", 32); put("sub_id", selected)
                put("thread_id", Telephony.Threads.getOrCreateThreadId(c, item.getString("to")))
            })
            check(row != null) { "ذخیره پیام ممکن نشد." }
            prefs(c).edit().putString("row:$id", row.toString()).commit()
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
            notify(c, id.hashCode(), "ارسال پیامک انجام نشد", "پیام‌یار را باز کنید و وضعیت سیم‌کارت و مجوزها را بررسی کنید.")
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
            deliveryFailure = deliveryReportFailure(reportStatus, intent.getStringExtra("format")) ?: return
        }
        val count = intent.getIntExtra("parts", 1).coerceIn(1, 255)
        val part = intent.getIntExtra("part", 0)
        if (part !in 0 until count) return // Discard malformed or stale broadcasts.
        val partKey = part.toString()
        val preferences = prefs(c)
        val ackKey = "acks:$id:$delivered"
        val okKey = "ok:$id:$delivered"
        val acks = preferences.getStringSet(ackKey, emptySet())!!.toMutableSet()
        val accepted = preferences.getStringSet(okKey, emptySet())!!.toMutableSet()
        acks.add(partKey)
        if (if (delivered) !deliveryFailure else code == Activity.RESULT_OK) {
            accepted.add(partKey)
        }
        val previous = status(c, id)
        // Each segment has an independent sent callback and an optional delivery report.
        // A single delivered segment is NOT proof that the whole multipart SMS arrived.
        // RESULT_CANCELED (0) is an ambiguous vendor callback, not a confirmed failure.
        val next = when {
            previous == "delivered" -> previous
            delivered && deliveryFailure -> "delivery_failed"
            delivered && accepted.size == count -> "delivered"
            delivered -> previous
            code != Activity.RESULT_OK && code != Activity.RESULT_CANCELED ->
                "send_failed:${SmsSendDiagnostic.describe(code)}"
            previous.startsWith("send_failed") || previous == "delivery_failed" -> previous
            acks.size < count -> if (code == Activity.RESULT_CANCELED && previous == "pending") {
                "send_unconfirmed"
            } else previous
            accepted.size == count -> "accepted_by_radio"
            else -> "send_unconfirmed"
        }
        preferences.edit().putStringSet(ackKey, acks).putStringSet(okKey, accepted)
            .putString("status:$id", next).commit()
        val row = prefs(c).getString("row:$id", null)
        if (row != null && isDefault(c)) {
            val values = ContentValues()
            if (next.startsWith("send_failed")) { values.put("type", 5); values.put("status", 64) }
            else if (next == "accepted_by_radio" || next == "delivered" || next == "delivery_failed") {
                values.put("type", 2); values.put("status", if (next == "delivered") 0 else if (next == "delivery_failed") 64 else 32)
            }
            if (values.size() > 0) c.contentResolver.update(Uri.parse(row), values, null, null)
        }
        if ((next == "accepted_by_radio" || next == "delivered") && !prefs(c).getBoolean("notified:$id", false)) {
            prefs(c).edit().putBoolean("notified:$id", true).apply()
            Notifier.sent(c, id)
        }
        if (next.startsWith("send_failed") && next != previous)
            notify(c, id.hashCode(), "ارسال پیامک ناموفق بود",
                next.substringAfter(':', "شبکه ارسال را رد کرد؛ سیم‌کارت و وضعیت پیام را بررسی کنید."))
        else if (next == "delivered" && previous.startsWith("send_failed"))
            c.getSystemService(NotificationManager::class.java).cancel(id.hashCode())
    }
    private fun storeIncoming(c: Context, item: JSONObject) {
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
            runCatching { InboxWidget.refresh(c) }
            Notifier.incoming(c, address, contactName(c, address), body, item.getLong("received"))
        }
    }
    @Synchronized fun drainIncoming(c: Context) {
        val dir = incomingDir(c)
        dir.listFiles()?.filter { it.extension == "json" }?.forEach { file ->
            try {
                val item = JSONObject(SecureVault.decryptQueue(file.readText()))
                storeIncoming(c, item)
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
            .put("sim", intent.getIntExtra("android.telephony.extra.SUBSCRIPTION_INDEX", intent.getIntExtra("subscription", -1)))
        val dir = incomingDir(c).apply { mkdirs() }
        val file = android.util.AtomicFile(java.io.File(dir, "${UUID.randomUUID()}.json"))
        val ciphertext = try { SecureVault.encryptIncoming(item.toString()) } catch (_: Exception) {
            // A temporarily unavailable Keystore must not prevent normal inbox delivery.
            storeIncoming(c, item)
            return
        }
        val output = file.startWrite()
        try { output.write(ciphertext.toByteArray(Charsets.UTF_8)); file.finishWrite(output) }
        catch (e: Exception) { file.failWrite(output); throw e }
        drainIncoming(c)
        if (hasPendingIncoming(c)) scheduleDrain(c, 60_000)
    }
    fun mutate(c: Context, ids: List<Number>, delete: Boolean): Int {
        check(isDefault(c)) { "ابتدا پیام‌یار را پیامک‌رسان پیش‌فرض کنید." }
        require(ids.size <= 500)
        var affected = 0
        ids.forEach { id ->
            require(id.toLong() > 0)
            val uri = ContentUris.withAppendedId(Telephony.Sms.CONTENT_URI, id.toLong())
            affected += if (delete) c.contentResolver.delete(uri, null, null) else c.contentResolver.update(uri,
                ContentValues().apply { put("read", 1); put("seen", 1) }, null, null)
        }
        runCatching { InboxWidget.refresh(c) }
        return affected
    }
    /** Resolve address book labels for incoming SMS in local and international form. */
    fun contactName(c: Context, address: String): String? {
        if (ContextCompat.checkSelfPermission(c, Manifest.permission.READ_CONTACTS) != PackageManager.PERMISSION_GRANTED) return null
        if (address.none { it.isDigit() }) return null
        val variants = linkedSetOf(address)
        val digits = buildString {
            for (ch in address) {
                val digit = Character.digit(ch, 10)
                if (digit >= 0) append(digit)
            }
        }
        val local = when {
            digits.length == 11 && digits.startsWith("09") -> digits
            digits.length == 12 && digits.startsWith("989") -> "0" + digits.takeLast(10)
            digits.length == 14 && digits.startsWith("00989") -> "0" + digits.takeLast(10)
            else -> null
        }
        if (local != null) {
            variants.add(local)
            variants.add("+98" + local.drop(1))
            variants.add("0098" + local.drop(1))
        }
        return try {
            for (number in variants) {
                val uri = Uri.withAppendedPath(android.provider.ContactsContract.PhoneLookup.CONTENT_FILTER_URI, Uri.encode(number))
                c.contentResolver.query(uri, arrayOf(android.provider.ContactsContract.PhoneLookup.DISPLAY_NAME), null, null, null)?.use {
                    if (it.moveToFirst()) {
                        val name = it.getString(0)
                        if (!name.isNullOrBlank()) return name
                    }
                }
            }
            null
        } catch (_: Exception) { null }
    }
    fun notify(c: Context, id: Int, title: String, text: String) {
        val manager = c.getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) manager.createNotificationChannel(NotificationChannel("alerts", "هشدارهای پیام‌یار", NotificationManager.IMPORTANCE_DEFAULT))
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
                else SmsCore.receiveAlarm(context, intent.getStringExtra("id") ?: "")
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
                try { Birthdays.run(context) } catch (_: Exception) { }
                SmsCore.prune(context)
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
                SmsCore.notify(context, 3, "خطا در ذخیره پیامک", "فضای ذخیره‌سازی و مجوزهای پیام‌یار را بررسی کنید.")
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
        if (data.size > 64 * 1024) return // A WAP push notification is tiny; ignore oversized payloads.
        val pending = goAsync()
        Thread {
            try {
                val dir = java.io.File(context.filesDir, "pending_mms").apply { mkdirs() }
                // Keep only the newest 50 notifications so private storage cannot grow without bound.
                dir.listFiles()?.sortedByDescending { it.lastModified() }?.drop(49)?.forEach { it.delete() }
                java.io.File(dir, "${System.currentTimeMillis()}.pdu").writeBytes(data)
                SmsCore.notify(context, 2, "پیام چندرسانه‌ای دریافت شد", "این نسخه MMS را دانلود نمی‌کند؛ برای دریافت از پیامک‌رسان قبلی استفاده کنید.")
            } catch (_: Exception) {
            } finally { pending.finish() }
        }.start()
    }
}
class RespondService : Service() {
    override fun onBind(intent: Intent?) = null
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // System phone app supplies the recipient and the explicitly chosen quick reply.
        // sms:/smsto: may carry several recipients separated by , or ; and a ?body= query.
        val recipients = intent?.data?.schemeSpecificPart.orEmpty().substringBefore('?')
            .split(',', ';').map { it.trim() }.filter { it.isNotEmpty() }.take(20)
        val body = intent?.getStringExtra(Intent.EXTRA_TEXT).orEmpty()
        recipients.forEach { to -> try { SmsCore.queue(this, to, body, -1) } catch (_: Exception) { } }
        stopSelf(startId)
        return START_NOT_STICKY
    }
}
