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
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.RadialGradient
import android.graphics.RectF
import android.graphics.Shader
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
import androidx.core.content.LocusIdCompat
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat

/**
 * Conversation-style notifications for incoming SMS: glass avatar, stacked messages per sender,
 * Android conversation bubbles, quick reply with ready-made answers, "mark as read" and one-tap
 * copy for verification codes. While PayamYar is on screen, a glass banner is shown inside the
 * app instead (see lib/screens/glass_banner.dart).
 *
 * Every look option is read from FlutterSharedPreferences ("flutter." prefix), written by AppSettings.
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
    private const val AVATAR = 160
    private val COLORS = intArrayOf(0xFF087F81.toInt(), 0xFF305F91.toInt(), 0xFF75539A.toInt(), 0xFF9F5369.toInt(),
        0xFF47765F.toInt(), 0xFFA17A37.toInt(), 0xFFC0583B.toInt(), 0xFF3A7CA5.toInt())
    private val DEFAULT_REPLIES = listOf("باشه 👍", "ممنون", "الان نمی‌تونم صحبت کنم", "بعداً تماس می‌گیرم", "رسیدم")

    fun idFor(address: String) = 100_000 + (address.filter { it.isLetterOrDigit() }.hashCode() and 0x7FFFFFF)

    private fun latinDigits(s: String) = buildString {
        for (ch in s) append(when (ch) { in '۰'..'۹' -> '0' + (ch - '۰'); in '٠'..'٩' -> '0' + (ch - '٠'); else -> ch })
    }

    fun otp(body: String): String? =
        Regex("(?:کد|رمز|code|otp|password|pin)[^\\d\\n]{0,25}(\\d{4,8})(?!\\d)", RegexOption.IGNORE_CASE)
            .find(latinDigits(body))?.groupValues?.get(1)

    // ───────────── user preferences ─────────────

    private fun prefs(c: Context): SharedPreferences =
        c.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

    private fun enabled(c: Context, key: String, default: Boolean = true): Boolean =
        try { prefs(c).getBoolean("flutter.$key", default) } catch (_: ClassCastException) { default }

    /** Flutter stores ints as Long. */
    private fun number(c: Context, key: String, default: Long): Long =
        try { prefs(c).getLong("flutter.$key", default) } catch (_: ClassCastException) { default }

    private fun accent(c: Context): Int = number(c, "notifyAccent", BRAND.toLong() and 0xFFFFFFFFL).toInt()

    private fun quickReplies(c: Context): Array<CharSequence> {
        val raw = try { prefs(c).getString("flutter.notifyQuickReplies", null) } catch (_: ClassCastException) { null }
        val list = raw?.split('\n')?.map { it.trim() }?.filter { it.isNotEmpty() } ?: DEFAULT_REPLIES
        return list.take(5).map { it as CharSequence }.toTypedArray()
    }

    // ───────────── glass avatar ─────────────

    private fun letterAvatar(label: String, seed: String): Bitmap {
        val bitmap = Bitmap.createBitmap(AVATAR, AVATAR, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val base = COLORS[(seed.hashCode() and 0x7FFFFFFF) % COLORS.size]
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        paint.shader = LinearGradient(0f, 0f, AVATAR.toFloat(), AVATAR.toFloat(),
            lighten(base, .28f), darken(base, .22f), Shader.TileMode.CLAMP)
        canvas.drawRect(0f, 0f, AVATAR.toFloat(), AVATAR.toFloat(), paint)
        paint.shader = null
        paint.color = Color.WHITE
        paint.textAlign = Paint.Align.CENTER
        paint.typeface = Typeface.DEFAULT_BOLD
        val letter = label.trim().firstOrNull { it.isLetter() }?.toString()
        if (letter != null) {
            paint.textSize = 80f
            canvas.drawText(letter, AVATAR / 2f, AVATAR / 2f - (paint.descent() + paint.ascent()) / 2, paint)
        } else {
            // Unknown number: a simple person silhouette.
            canvas.drawCircle(AVATAR / 2f, AVATAR * .40f, AVATAR * .17f, paint)
            canvas.drawCircle(AVATAR / 2f, AVATAR * .92f, AVATAR * .34f, paint)
        }
        return bitmap
    }

    private fun lighten(color: Int, f: Float) = Color.rgb(
        (Color.red(color) + (255 - Color.red(color)) * f).toInt(),
        (Color.green(color) + (255 - Color.green(color)) * f).toInt(),
        (Color.blue(color) + (255 - Color.blue(color)) * f).toInt())

    private fun darken(color: Int, f: Float) = Color.rgb(
        (Color.red(color) * (1 - f)).toInt(), (Color.green(color) * (1 - f)).toInt(), (Color.blue(color) * (1 - f)).toInt())

    /**
     * Clips the picture to a circle or soft square and, when the glass look is on, adds a frosted
     * top highlight, a soft inner glow and a two-tone ring in the user's accent colour.
     */
    private fun styledAvatar(c: Context, source: Bitmap): Bitmap {
        val size = AVATAR.toFloat()
        val out = Bitmap.createBitmap(AVATAR, AVATAR, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(out)
        val rounded = number(c, "notifyAvatarShape", 0L) == 1L
        val clip = Path().apply {
            if (rounded) addRoundRect(RectF(0f, 0f, size, size), size * .3f, size * .3f, Path.Direction.CW)
            else addCircle(size / 2, size / 2, size / 2, Path.Direction.CW)
        }
        val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
        canvas.save()
        canvas.clipPath(clip)
        canvas.drawBitmap(Bitmap.createScaledBitmap(source, AVATAR, AVATAR, true), 0f, 0f, paint)
        if (enabled(c, "notifyGlassAvatar")) {
            // Frosted reflection on the upper half.
            val gloss = Paint(Paint.ANTI_ALIAS_FLAG)
            gloss.shader = LinearGradient(0f, 0f, 0f, size * .58f, 0x99FFFFFF.toInt(), 0x00FFFFFF, Shader.TileMode.CLAMP)
            canvas.drawOval(RectF(-size * .15f, -size * .42f, size * 1.15f, size * .52f), gloss)
            // Light from the bottom edge, like thick glass.
            val glow = Paint(Paint.ANTI_ALIAS_FLAG)
            glow.shader = RadialGradient(size / 2, size * 1.05f, size * .55f, 0x55FFFFFF, 0x00FFFFFF, Shader.TileMode.CLAMP)
            canvas.drawRect(0f, 0f, size, size, glow)
            // Two tiny bubbles.
            val dot = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0x88FFFFFF.toInt() }
            canvas.drawCircle(size * .74f, size * .24f, size * .045f, dot)
            canvas.drawCircle(size * .83f, size * .36f, size * .025f, dot)
        }
        canvas.restore()
        val ring = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE }
        val inset = 4f
        val rect = RectF(inset, inset, size - inset, size - inset)
        ring.strokeWidth = 7f
        ring.color = accent(c)
        if (rounded) canvas.drawRoundRect(rect, size * .28f, size * .28f, ring) else canvas.drawOval(rect, ring)
        ring.strokeWidth = 2f
        ring.color = 0xB3FFFFFF.toInt()
        val inner = RectF(inset + 4.5f, inset + 4.5f, size - inset - 4.5f, size - inset - 4.5f)
        if (rounded) canvas.drawRoundRect(inner, size * .26f, size * .26f, ring) else canvas.drawOval(inner, ring)
        return out
    }

    /** 108dp adaptive canvas: the avatar sits inside the 72dp safe zone, on the accent colour. */
    private fun adaptive(c: Context, avatar: Bitmap): Bitmap {
        val size = 216
        val out = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(out)
        canvas.drawColor(accent(c))
        val inner = 144
        val offset = (size - inner) / 2f
        val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
        canvas.drawBitmap(Bitmap.createScaledBitmap(avatar, inner, inner, true), offset, offset, paint)
        paint.xfermode = PorterDuffXfermode(PorterDuff.Mode.DST_OVER)
        return out
    }

    private fun contactPhoto(c: Context, address: String): Bitmap? {
        if (ContextCompat.checkSelfPermission(c, Manifest.permission.READ_CONTACTS) != PackageManager.PERMISSION_GRANTED) return null
        try {
            val uri = Uri.withAppendedPath(ContactsContract.PhoneLookup.CONTENT_FILTER_URI, Uri.encode(address))
            c.contentResolver.query(uri, arrayOf(ContactsContract.PhoneLookup.PHOTO_THUMBNAIL_URI),
                null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val photo = cursor.getString(0)
                    if (!photo.isNullOrBlank()) {
                        // Bounded read + sampled decode: a huge contact photo must not crash the receiver.
                        val bytes = c.contentResolver.openInputStream(Uri.parse(photo))?.use {
                            Xlsx.readLimited(it, 6L * 1024 * 1024) } ?: return null
                        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
                        var sample = 1
                        while (bounds.outWidth / (sample * 2) >= 192 && bounds.outHeight / (sample * 2) >= 192) sample *= 2
                        return BitmapFactory.decodeByteArray(bytes, 0, bytes.size,
                            BitmapFactory.Options().apply { inSampleSize = sample })
                    }
                }
            }
        } catch (_: Exception) { }
        return null
    }

    private fun profileBitmap(c: Context, address: String, label: String): Bitmap =
        styledAvatar(c, contactPhoto(c, address) ?: letterAvatar(label, address))

    private fun broadcast(c: Context, action: String, address: String, extra: String? = null, mutable: Boolean = false): PendingIntent {
        val intent = Intent(c, NotifyActionReceiver::class.java).setAction(action)
            .setData(Uri.parse("payamyar:notify/" + Uri.encode(address) + "/" + action))
            .putExtra("address", address).putExtra("extra", extra)
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            (if (mutable && Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else if (mutable) 0 else PendingIntent.FLAG_IMMUTABLE)
        return PendingIntent.getBroadcast(c, 0, intent, flags)
    }

    fun configureChannels(c: Context) {
        if (Build.VERSION.SDK_INT < 26) return
        val manager = c.getSystemService(NotificationManager::class.java)
        val sound = android.media.RingtoneManager.getDefaultUri(android.media.RingtoneManager.TYPE_NOTIFICATION)
        val audio = android.media.AudioAttributes.Builder()
            .setUsage(android.media.AudioAttributes.USAGE_NOTIFICATION)
            .setContentType(android.media.AudioAttributes.CONTENT_TYPE_SONIFICATION).build()
        manager.createNotificationChannel(NotificationChannel(INCOMING_CHANNEL, "پیام‌های دریافتی", NotificationManager.IMPORTANCE_HIGH).apply {
            description = "صدای دریافت پیام، پیش‌نمایش، حباب گفتگو و پاسخ سریع"
            enableVibration(true)
            vibrationPattern = longArrayOf(0, 150, 100, 160)
            setSound(sound, audio)
            lockscreenVisibility = android.app.Notification.VISIBILITY_PRIVATE
            if (Build.VERSION.SDK_INT >= 29) setAllowBubbles(true)
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
        when (SentSound.mode(c)) {
            0 -> { SentSound.play(c); return }   // sound only, like a messenger "whoosh"
            2 -> return                          // silent
        }
        if (Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(c, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return
        val engine = c.getSharedPreferences("sms_engine_v1", Context.MODE_PRIVATE)
        val now = System.currentTimeMillis()
        // A multi-recipient batch should not play hundreds of sounds.
        if (now - engine.getLong("last_success_notification", 0) < 2500L) return
        engine.edit().putLong("last_success_notification", now).apply()
        configureChannels(c)
        val open = PendingIntent.getActivity(c, 0, Intent(c, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val notification = NotificationCompat.Builder(c, SENT_CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_payamyar)
            .setColor(accent(c)).setContentTitle("پیامک به شبکه ارسال شد")
            .setContentText("وضعیت ارسال توسط شبکه تأیید شد.")
            .setStyle(NotificationCompat.BigTextStyle()
                .bigText("شبکه ارسال پیامک را پذیرفت. تحویل قطعی به گوشی گیرنده فقط با گزارش تحویل مشخص می‌شود."))
            .setSubText("پیامیار • گزارش ارسال")
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setCategory(NotificationCompat.CATEGORY_STATUS)
            .setContentIntent(open).setAutoCancel(true)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE).build()
        NotificationManagerCompat.from(c).notify(900_001, notification)
    }

    private fun canReply(address: String) =
        Regex("^\\+?[0-9]{7,15}$").matches(address.replace(Regex("[\\s()-]"), ""))

    /** Long-lived conversation shortcut: required by Android 11+ for bubbles and the "Conversations" section. */
    private fun conversationShortcut(c: Context, address: String, name: String, sender: Person, icon: IconCompat): String? = try {
        val id = "conv_" + address.filter { it.isLetterOrDigit() }.ifEmpty { "x" }
        val shortcut = ShortcutInfoCompat.Builder(c, id)
            .setLongLived(true)
            .setShortLabel(name.take(24))
            .setPerson(sender)
            .setIcon(icon)
            .setLocusId(LocusIdCompat(id))
            .setIntent(Intent(c, MainActivity::class.java).setAction(Intent.ACTION_VIEW)
                .putExtra("open_address", address).putExtra("open_token", MainActivity.launchToken(c)))
            .build()
        ShortcutManagerCompat.pushDynamicShortcut(c, shortcut)
        id
    } catch (_: Exception) { null }

    private fun bubble(c: Context, address: String, icon: IconCompat): NotificationCompat.BubbleMetadata? {
        if (Build.VERSION.SDK_INT < 30 || !enabled(c, "notifyBubbles")) return null
        val target = Intent(c, BubbleActivity::class.java).setAction(Intent.ACTION_VIEW)
            .setData(Uri.parse("payamyar:bubble/" + Uri.encode(address)))
            .putExtra("open_address", address).putExtra("open_token", MainActivity.launchToken(c))
        val pending = PendingIntent.getActivity(c, 1, target,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE)
        return NotificationCompat.BubbleMetadata.Builder(pending, icon)
            .setDesiredHeight(640)
            .setAutoExpandBubble(false)
            .setSuppressNotification(false)
            .build()
    }

    /**
     * Shows a new message. When PayamYar is in front and the in-app banner is on, the glass banner
     * inside the app replaces the system notification (pass [forceSystem] for the settings preview).
     */
    fun incoming(c: Context, address: String, contact: String?, body: String, time: Long, forceSystem: Boolean = false) {
        if (!enabled(c, "notifyIncoming")) return
        val preview = enabled(c, "notifyPreview")
        val name = contact?.takeIf { it.isNotBlank() } ?: address
        val text = if (preview) body else "پیامک جدید"
        val code = if (preview && enabled(c, "notifyOtpCopy")) otp(body) else null
        val reply = canReply(address) && enabled(c, "notifyQuickReply")

        val front = MainActivity.foregroundChannel
        if (!forceSystem && front != null && enabled(c, "notifyInApp")) {
            val payload = mapOf("address" to address, "name" to name, "body" to text, "time" to time,
                "otp" to code, "canReply" to reply)
            Handler(Looper.getMainLooper()).post {
                try { front.invokeMethod("incomingBanner", payload) } catch (_: Exception) { }
            }
            // Keep the Android notification as a reliable fallback as well.
            // The Flutter channel can be alive while its page is not ready to show the banner.
        }

        configureChannels(c)
        val manager = c.getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 33 && ContextCompat.checkSelfPermission(c, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return
        val id = idFor(address)
        val picture = profileBitmap(c, address, name)
        val icon = IconCompat.createWithAdaptiveBitmap(adaptive(c, picture))
        val sender = Person.Builder().setName(name).setKey(address)
            .setIcon(IconCompat.createWithBitmap(picture)).setImportant(true).build()

        // Stack this message under earlier unread ones from the same sender.
        val existing = manager.activeNotifications.firstOrNull { it.id == id }?.notification
        val style = existing?.let { NotificationCompat.MessagingStyle.extractMessagingStyleFromNotification(it) }
            ?: NotificationCompat.MessagingStyle(Person.Builder().setName("شما").build())
        style.addMessage(text, time, sender)

        val open = PendingIntent.getActivity(c, 0,
            Intent(c, MainActivity::class.java).setAction("ir.honarmardomi.payamyar.OPEN_CONVERSATION")
                .setData(Uri.parse("payamyar:open/" + Uri.encode(address))).putExtra("open_address", address).putExtra("open_token", MainActivity.launchToken(c))
                .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

        val color = accent(c)
        val builder = NotificationCompat.Builder(c, CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_payamyar)
            .setColor(color)
            .setStyle(style)
            .setLargeIcon(picture)
            .setSubText("پیامیار")
            .setContentTitle(name).setContentText(text)
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setGroup("payamyar_incoming_sms")
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setWhen(time).setShowWhen(true)
            .setContentIntent(open).setAutoCancel(false)
            .setSilent(SentSound.quietNow(c))
            .setLights(color, 600, 2400)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .setPublicVersion(NotificationCompat.Builder(c, CHANNEL).setSmallIcon(R.drawable.ic_stat_payamyar)
                .setColor(color).setContentTitle("پیامیار").setContentText("پیامک جدید").build())

        conversationShortcut(c, address, name, sender, icon)?.let { shortcut ->
            builder.setShortcutId(shortcut).setLocusId(LocusIdCompat(shortcut))
            bubble(c, address, icon)?.let { builder.setBubbleMetadata(it) }
        }

        if (code != null) {
            builder.addAction(NotificationCompat.Action.Builder(0, "📋 کپی کد " + code, broadcast(c, ACTION_COPY, address, code)).build())
        }
        // Short codes and named senders (banks, services) cannot receive replies.
        if (reply) {
            val input = RemoteInput.Builder(KEY_REPLY).setLabel("پاسخ به " + name.take(18) + "…")
                .setChoices(quickReplies(c)).setAllowFreeFormInput(true).build()
            builder.addAction(NotificationCompat.Action.Builder(0, "↩ پاسخ سریع", broadcast(c, ACTION_REPLY, address, mutable = true))
                .addRemoteInput(input).setAllowGeneratedReplies(true)
                .setSemanticAction(NotificationCompat.Action.SEMANTIC_ACTION_REPLY).setShowsUserInterface(false).build())
        }
        builder.addAction(NotificationCompat.Action.Builder(0, "✓ خوانده شد", broadcast(c, ACTION_READ, address))
            .setSemanticAction(NotificationCompat.Action.SEMANTIC_ACTION_MARK_AS_READ).setShowsUserInterface(false).build())
        NotificationManagerCompat.from(c).notify(id, builder.build())
    }

    /** Sample notification from Settings so the user can see the chosen look and quick replies. */
    fun preview(c: Context) {
        incoming(c, "+989000000000", "پیامیار", "سلام! این نمونه اعلان شیشه‌ای پیامیار است. کد آزمایشی: 12345",
            System.currentTimeMillis(), forceSystem = true)
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
                Handler(Looper.getMainLooper()).post { Toast.makeText(context, "کد " + code + " کپی شد", Toast.LENGTH_SHORT).show() }
            }
            Notifier.ACTION_READ, Notifier.ACTION_REPLY -> {
                val reply = RemoteInput.getResultsFromIntent(intent)?.getCharSequence(Notifier.KEY_REPLY)?.toString()
                val pending = goAsync()
                Thread {
                    try {
                        // The settings preview uses a reserved sample number: never send to it.
                        if (intent.action == Notifier.ACTION_REPLY && !reply.isNullOrBlank() && address != "+989000000000") {
                            val id = SmsCore.queue(context, address, reply, -1, 0)
                            SmsCore.dispatch(context, id)
                        }
                        if (address != "+989000000000") SmsCore.markAddressRead(context, address)
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
