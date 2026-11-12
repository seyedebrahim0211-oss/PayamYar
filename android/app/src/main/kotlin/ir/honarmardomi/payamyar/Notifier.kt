package ir.honarmardomi.payamyar

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.ContactsContract
import android.widget.Toast
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.Person
import androidx.core.app.RemoteInput
import androidx.core.content.ContextCompat
import androidx.core.graphics.drawable.IconCompat

/**
 * Conversation-style notifications for incoming SMS: sender avatar, stacked messages per sender,
 * inline reply, "mark as read" and one-tap copy for verification codes.
 */
object Notifier {
    // V2 uses fresh channels; Android never updates sound on an existing channel.
    const val INCOMING_CHANNEL = "incoming_sms_v2"
    const val SENT_CHANNEL = "sent_sms_v2"
    private const val CHANNEL = INCOMING_CHANNEL
    const val ACTION_REPLY = "ir.honarmardomi.payamyar.NOTIFY_REPLY"
    const val ACTION_READ = "ir.honarmardomi.payamyar.NOTIFY_READ"
    const val ACTION_COPY = "ir.honarmardomi.payamyar.NOTIFY_COPY"
    const val KEY_REPLY = "reply_text"
    private const val BRAND = 0xFF087F81.toInt()
    private val COLORS = intArrayOf(0xFF087F81.toInt(), 0xFF305F91.toInt(), 0xFF75539A.toInt(), 0xFF9F5369.toInt(),
        0xFF47765F.toInt(), 0xFFA17A37.toInt(), 0xFFC0583B.toInt(), 0xFF3A7CA5.toInt())

    fun idFor(address: String) = 100_000 + (address.filter { it.isLetterOrDigit() }.hashCode() and 0x7FFFFFF)

    private fun latinDigits(s: String) = buildString {
        for (ch in s) append(when (ch) { in '۰'..'۹' -> '0' + (ch - '۰'); in '٠'..'٩' -> '0' + (ch - '٠'); else -> ch })
    }

    fun otp(body: String): String? =
        Regex("(?:کد|رمز|code|otp|password|pin)[^\\d\\n]{0,25}(\\d{4,8})(?!\\d)", RegexOption.IGNORE_CASE)
            .find(latinDigits(body))?.groupValues?.get(1)

    private fun avatar(label: String, seed: String): Bitmap {
        val size = 160
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        paint.color = COLORS[(seed.hashCode() and 0x7FFFFFFF) % COLORS.size]
        canvas.drawCircle(size / 2f, size / 2f, size / 2f, paint)
        paint.color = Color.WHITE
        paint.textAlign = Paint.Align.CENTER
        paint.typeface = Typeface.DEFAULT_BOLD
        val letter = label.trim().firstOrNull { it.isLetter() }?.toString()
        if (letter != null) {
            paint.textSize = 84f
            canvas.drawText(letter, size / 2f, size / 2f - (paint.descent() + paint.ascent()) / 2, paint)
        } else {
            // Unknown number: a simple person silhouette.
            canvas.drawCircle(size / 2f, size * .40f, size * .17f, paint)
            canvas.drawCircle(size / 2f, size * .92f, size * .34f, paint)
        }
        return bitmap
    }

    private fun profileBitmap(c: Context, address: String, label: String): Bitmap {
        if (ContextCompat.checkSelfPermission(c, Manifest.permission.READ_CONTACTS) == PackageManager.PERMISSION_GRANTED) {
            try {
                val uri = Uri.withAppendedPath(ContactsContract.PhoneLookup.CONTENT_FILTER_URI, Uri.encode(address))
                c.contentResolver.query(uri, arrayOf(ContactsContract.PhoneLookup.PHOTO_THUMBNAIL_URI),
                    null, null, null)?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        val photo = cursor.getString(0)
                        if (!photo.isNullOrBlank()) {
                            val bmp = c.contentResolver.openInputStream(Uri.parse(photo))?.use { BitmapFactory.decodeStream(it) }
                            if (bmp != null) return Bitmap.createScaledBitmap(bmp, 160, 160, true)
                        }
                    }
                }
            } catch (_: Exception) { }
        }
        return avatar(label, address)
    }

    private fun broadcast(c: Context, action: String, address: String, extra: String? = null, mutable: Boolean = false): PendingIntent {
        val intent = Intent(c, NotifyActionReceiver::class.java).setAction(action)
            .setData(Uri.parse("payamyar:notify/${Uri.encode(address)}/$action"))
            .putExtra("address", address).putExtra("extra", extra)
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            (if (mutable && Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else if (mutable) 0 else PendingIntent.FLAG_IMMUTABLE)
        return PendingIntent.getBroadcast(c, 0, intent, flags)
    }

    private fun enabled(c: Context, key: String): Boolean =
        c.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE).getBoolean("flutter.$key", true)

    fun configureChannels(c: Context) {
        if (Build.VERSION.SDK_INT < 26) return
        val manager = c.getSystemService(NotificationManager::class.java)
        val sound = android.media.RingtoneManager.getDefaultUri(android.media.RingtoneManager.TYPE_NOTIFICATION)
        val audio = android.media.AudioAttributes.Builder()
            .setUsage(android.media.AudioAttributes.USAGE_NOTIFICATION)
            .setContentType(android.media.AudioAttributes.CONTENT_TYPE_SONIFICATION).build()
        manager.createNotificationChannel(NotificationChannel(INCOMING_CHANNEL, "پیام‌های دریافتی", NotificationManager.IMPORTANCE_HIGH).apply {
            description = "صدای دریافت پیام، پیش‌نمایش و پاسخ سریع"
            enableVibration(true)
            vibrationPattern = longArrayOf(0, 150, 100, 160)
            setSound(sound, audio)
            lockscreenVisibility = android.app.Notification.VISIBILITY_PRIVATE
        })
        manager.createNotificationChannel(NotificationChannel(SENT_CHANNEL, "تأیید ارسال پیام", NotificationManager.IMPORTANCE_DEFAULT).apply {
            description = "صدای تأیید پذیرش پیامک توسط شبکه؛ قابل تغییر از تنظیمات اعلان گوشی"
            setSound(sound, audio)
            enableVibration(false)
            lockscreenVisibility = android.app.Notification.VISIBILITY_PRIVATE
        })
    }

    fun sent(c: Context, id: String) {
        if (!enabled(c, "notifySent")) return
        if (Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(c, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return
        val prefs = c.getSharedPreferences("sms_engine_v1", Context.MODE_PRIVATE)
        val now = System.currentTimeMillis()
        // A multi-recipient batch should not play hundreds of sounds.
        if (now - prefs.getLong("last_success_notification", 0) < 2500L) return
        prefs.edit().putLong("last_success_notification", now).apply()
        configureChannels(c)
        val open = PendingIntent.getActivity(c, 0, Intent(c, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val notification = NotificationCompat.Builder(c, SENT_CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_payamyar)
            .setColor(BRAND).setContentTitle("پیامک به شبکه ارسال شد")
            .setContentText("وضعیت ارسال توسط شبکه تأیید شد.")
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setCategory(NotificationCompat.CATEGORY_STATUS)
            .setContentIntent(open).setAutoCancel(true)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE).build()
        NotificationManagerCompat.from(c).notify(900_001, notification)
    }

    fun incoming(c: Context, address: String, contact: String?, body: String, time: Long) {
        if (!enabled(c, "notifyIncoming")) return
        configureChannels(c)
        val manager = c.getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 33 && ContextCompat.checkSelfPermission(c, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return
        val preview = c.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE).getBoolean("flutter.notifyPreview", true)
        val name = contact?.takeIf { it.isNotBlank() } ?: address
        val id = idFor(address)
        val text = if (preview) body else "پیامک جدید"
        val picture = profileBitmap(c, address, name)
        val sender = Person.Builder().setName(name).setKey(address)
            .setIcon(IconCompat.createWithBitmap(picture)).build()

        // Stack this message under earlier unread ones from the same sender.
        val existing = manager.activeNotifications.firstOrNull { it.id == id }?.notification
        val style = existing?.let { NotificationCompat.MessagingStyle.extractMessagingStyleFromNotification(it) }
            ?: NotificationCompat.MessagingStyle(Person.Builder().setName("شما").build())
        style.addMessage(text, time, sender)

        val open = PendingIntent.getActivity(c, 0,
            Intent(c, MainActivity::class.java).setAction("ir.honarmardomi.payamyar.OPEN_CONVERSATION")
                .setData(Uri.parse("payamyar:open/${Uri.encode(address)}")).putExtra("open_address", address)
                .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

        val builder = NotificationCompat.Builder(c, CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_payamyar)
            .setColor(BRAND)
            .setStyle(style)
            .setLargeIcon(picture)
            .setContentTitle(name).setContentText(text)
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setWhen(time).setShowWhen(true)
            .setContentIntent(open).setAutoCancel(true)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .setPublicVersion(NotificationCompat.Builder(c, CHANNEL).setSmallIcon(R.drawable.ic_stat_payamyar)
                .setColor(BRAND).setContentTitle("پیامیار").setContentText("پیامک جدید").build())

        val code = if (preview) otp(body) else null
        if (code != null) {
            builder.addAction(NotificationCompat.Action.Builder(0, "کپی کد $code", broadcast(c, ACTION_COPY, address, code)).build())
        }
        // Short codes and named senders (banks, services) cannot receive replies.
        if (Regex("^\\+?[0-9]{7,15}$").matches(address.replace(Regex("[\\s()-]"), ""))) {
            val input = RemoteInput.Builder(KEY_REPLY).setLabel("پاسخ…").build()
            builder.addAction(NotificationCompat.Action.Builder(0, "پاسخ", broadcast(c, ACTION_REPLY, address, mutable = true))
                .addRemoteInput(input).setAllowGeneratedReplies(false)
                .setSemanticAction(NotificationCompat.Action.SEMANTIC_ACTION_REPLY).build())
        }
        builder.addAction(NotificationCompat.Action.Builder(0, "خوانده شد", broadcast(c, ACTION_READ, address))
            .setSemanticAction(NotificationCompat.Action.SEMANTIC_ACTION_MARK_AS_READ).setShowsUserInterface(false).build())
        NotificationManagerCompat.from(c).notify(id, builder.build())
    }

    fun cancel(c: Context, address: String) {
        c.getSystemService(NotificationManager::class.java).cancel(idFor(address))
    }
}

class NotifyActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val address = intent.getStringExtra("address") ?: return
        when (intent.action) {
            Notifier.ACTION_COPY -> {
                val code = intent.getStringExtra("extra") ?: return
                context.getSystemService(ClipboardManager::class.java).setPrimaryClip(ClipData.newPlainText("کد تأیید", code))
                Handler(Looper.getMainLooper()).post { Toast.makeText(context, "کد $code کپی شد", Toast.LENGTH_SHORT).show() }
            }
            Notifier.ACTION_READ, Notifier.ACTION_REPLY -> {
                val reply = RemoteInput.getResultsFromIntent(intent)?.getCharSequence(Notifier.KEY_REPLY)?.toString()
                val pending = goAsync()
                Thread {
                    try {
                        if (intent.action == Notifier.ACTION_REPLY && !reply.isNullOrBlank()) {
                            val id = SmsCore.queue(context, address, reply, -1, 0)
                            SmsCore.dispatch(context, id)
                        }
                        SmsCore.markAddressRead(context, address)
                    } catch (_: Exception) {
                        SmsCore.notify(context, 4, "پاسخ ارسال نشد", "پیامیار را باز کنید و دوباره تلاش کنید.")
                    } finally {
                        Notifier.cancel(context, address)
                        pending.finish()
                    }
                }.start()
            }
        }
    }
}
