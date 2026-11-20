package ir.honarmardomi.payamyar

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.ClipData
import android.content.ClipDescription
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
import android.graphics.BitmapShader
import android.graphics.Matrix
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PersistableBundle
import android.provider.ContactsContract
import android.widget.Toast
import io.flutter.plugin.common.MethodChannel
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
    const val INCOMING_CHANNEL = "incoming_sms_v4"
    const val OVERLAY_CHANNEL = "incoming_sms_floating_v2"
    const val SENT_CHANNEL = "sent_sms_v2"
    private const val CHANNEL = INCOMING_CHANNEL
    const val ACTION_REPLY = "ir.honarmardomi.payamyar.NOTIFY_REPLY"
    const val ACTION_READ = "ir.honarmardomi.payamyar.NOTIFY_READ"
    const val ACTION_COPY = "ir.honarmardomi.payamyar.NOTIFY_COPY"
    const val KEY_REPLY = "reply_text"
    internal const val PREVIEW_ADDRESS = "payamyar-preview"
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

    fun copyTitle(c: Context, code: String): String =
        if (enabled(c, "bannerActionCode", false)) "کپی کد " + code.map { '۰' + (it - '0') }.joinToString("")
        else "کپی کد"

    fun copyOtp(c: Context, code: String) {
        val clip = ClipData.newPlainText("کد تأیید", code)
        clip.description.extras = PersistableBundle().apply { putBoolean(ClipDescription.EXTRA_IS_SENSITIVE, true) }
        c.getSystemService(ClipboardManager::class.java).setPrimaryClip(clip)
        if (Build.VERSION.SDK_INT < 33) Toast.makeText(c, "کد تأیید کپی شد", Toast.LENGTH_SHORT).show()
    }

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

    /** One transparent portrait is shared by MessagingStyle, the conversation shortcut and large icon. */
    internal fun styledAvatar(source: Bitmap, softSquare: Boolean, glass: Boolean, tint: Int): Bitmap {
        val size = AVATAR.toFloat()
        val out = Bitmap.createBitmap(AVATAR, AVATAR, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(out)
        val bounds = RectF(0f, 0f, size, size)
        val radius = if (softSquare) size * .28f else size / 2f
        val scale = maxOf(size / source.width, size / source.height)
        val crop = Matrix().apply {
            setScale(scale, scale)
            postTranslate((size - source.width * scale) / 2f, (size - source.height * scale) / 2f)
        }
        val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG).apply {
            shader = BitmapShader(source, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP).apply { setLocalMatrix(crop) }
        }
        canvas.drawRoundRect(bounds, radius, radius, paint)
        if (glass) {
            // Keep the face unobstructed; the glass highlight only traces the edge.
            paint.style = Paint.Style.STROKE
            paint.strokeWidth = 3f
            bounds.inset(1.5f, 1.5f)
            paint.shader = LinearGradient(0f, 0f, size, size,
                intArrayOf(0xD9FFFFFF.toInt(), lighten(tint, .38f), darken(tint, .12f)), null, Shader.TileMode.CLAMP)
            canvas.drawRoundRect(bounds, radius - 1.5f, radius - 1.5f, paint)
        }
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
        manager.createNotificationChannel(NotificationChannel(OVERLAY_CHANNEL, "پیام‌ها هنگام حباب شناور", NotificationManager.IMPORTANCE_LOW).apply {
            // A real glass overlay is the sole visual heads-up. Keep a quiet Android
            // MessagingStyle entry in the shade for reliable delivery/history and
            // OEM devices that reject overlay windows. Do not present two pop-ups.
            description = "سابقه بی‌صدا در نوار اعلان؛ اعلان شیشه‌ای جداگانه نمایش داده می‌شود"
            setSound(null, null)
            enableVibration(false)
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
            .setSubText("سوسلنگ • گزارش ارسال")
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
            .setIntent(Intent(c, BubbleActivity::class.java).setAction(Intent.ACTION_VIEW)
                .setData(Uri.parse("payamyar:bubble/" + Uri.encode(address)))
                .putExtra("open_address", address).putExtra("open_token", MainActivity.launchToken(c)))
            .build()
        ShortcutManagerCompat.pushDynamicShortcut(c, shortcut)
        id
    } catch (_: Exception) { null }

    private fun bubble(c: Context, shortcutId: String): NotificationCompat.BubbleMetadata? {
        if (Build.VERSION.SDK_INT < 30 || !enabled(c, "notifyBubbles", false)) return null
        // Android 11+ expects the *same* long-lived shortcut for both conversation
        // notification and bubble. The shortcut targets an embeddable BubbleActivity.
        return NotificationCompat.BubbleMetadata.Builder(shortcutId)
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
        val appLocked = enabled(c, "appLock", false)
        val preview = enabled(c, "notifyPreview", false) && !appLocked
        val source = if (preview) MessengerSender.fromAddress(address) else null
        val name = if (appLocked) "سوسلنگ" else contact?.takeIf { it.isNotBlank() } ?: source?.title ?: address
        val text = if (preview) body else "پیامک جدید"
        val code = if (preview && enabled(c, "notifyOtpCopy")) otp(body) else null
        val reply = canReply(address) && enabled(c, "notifyQuickReply") && !appLocked

        val front = MainActivity.foregroundChannel
        if (!forceSystem && front != null && enabled(c, "notifyInApp")) {
            val payload = mapOf("address" to address, "name" to name, "body" to text, "time" to time,
                "otp" to code, "canReply" to reply, "showBrand" to preview, "sourceColor" to source?.selectedColor(prefs(c))?.toLong()?.and(0xffffffffL))
            Handler(Looper.getMainLooper()).post {
                try {
                    front.invokeMethod("incomingBanner", payload, object : MethodChannel.Result {
                        override fun success(result: Any?) { /* Glass banner owns foreground alert. */ }
                        override fun error(errorCode: String, message: String?, details: Any?) {
                            systemIncoming(c, address, name, text, time, code, reply)
                        }
                        override fun notImplemented() {
                            systemIncoming(c, address, name, text, time, code, reply)
                        }
                    })
                } catch (_: Exception) {
                    systemIncoming(c, address, name, text, time, code, reply)
                }
            }
            // Do not show a second notification while the in-app glass card is active.
            return
        }
        systemIncoming(c, address, name, text, time, code, reply)
    }

    private fun systemIncoming(c: Context, address: String, name: String, text: String,
                               time: Long, code: String?, reply: Boolean, sample: Boolean = false, sampleSource: MessengerSender? = null) {
        if (Looper.myLooper() != Looper.getMainLooper()) {
            Handler(Looper.getMainLooper()).post { systemIncoming(c.applicationContext, address, name, text, time, code, reply, sample, sampleSource) }
            return
        }
        configureChannels(c)
        if (!NotificationManagerCompat.from(c).areNotificationsEnabled()) return
        FloatingNotifications.show(c, address, name, text, sample, time, sampleSource?.name) { visible ->
            if (enabled(c, "notifyIncoming") && NotificationManagerCompat.from(c).areNotificationsEnabled()) {
                val locked = enabled(c, "appLock", false)
                val reveal = !locked && enabled(c, "notifyPreview", false)
                postIncoming(c, address, if (locked) "سوسلنگ" else name, if (reveal) text else "پیامک جدید",
                    time, if (reveal) code else null, reply && !locked, sample, visible, sampleSource)
            }
        }
    }

    private fun postIncoming(c: Context, address: String, name: String, text: String, time: Long,
                             code: String?, reply: Boolean, sample: Boolean, floating: Boolean, sampleSource: MessengerSender?) {
        val manager = c.getSystemService(NotificationManager::class.java)
        val deliveryChannel = if (floating) OVERLAY_CHANNEL else CHANNEL
        val id = idFor(address)
        val color = if (enabled(c, "bannerSourceColors") && enabled(c, "notifyPreview", false) && !enabled(c, "appLock", false))
            (sampleSource ?: MessengerSender.fromAddress(address))?.selectedColor(prefs(c)) ?: accent(c) else accent(c)
        val source = if (enabled(c, "appLock", false)) letterAvatar("پ", "private")
            else (if (enabled(c, "notifyPreview", false)) BankLogos.picture(c, address) else null)
                ?: contactPhoto(c, address) ?: letterAvatar(name, address)
        val picture = styledAvatar(source, number(c, "notifyAvatarShape", 0L) == 1L, enabled(c, "notifyGlassAvatar"), color)
        val portrait = IconCompat.createWithBitmap(picture)
        // MessagingStyle retains conversation semantics and unread message history.
        val sender = Person.Builder().setName(name).setKey(address)
            .setIcon(portrait).setImportant(true).build()

        // Stack this message under earlier unread ones from the same sender.
        val existing = if (enabled(c, "notifyPreview", false) && !enabled(c, "appLock", false))
            manager.activeNotifications.firstOrNull { it.id == id }?.notification else null
        val style = existing?.let { NotificationCompat.MessagingStyle.extractMessagingStyleFromNotification(it) }
            ?: NotificationCompat.MessagingStyle(Person.Builder().setName("شما").build())
        style.addMessage(text, time, sender)

        // A sample must never open a fictitious conversation or create a real SMS.
        val openIntent = Intent(c, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        if (!sample) openIntent.setAction("ir.honarmardomi.payamyar.OPEN_CONVERSATION")
            .setData(Uri.parse("payamyar:open/" + Uri.encode(address)))
            .putExtra("open_address", address)
            .putExtra("open_token", MainActivity.launchToken(c))
        val open = PendingIntent.getActivity(c, idFor(address), openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

        val builder = NotificationCompat.Builder(c, deliveryChannel)
            .setSmallIcon(R.drawable.ic_stat_payamyar)
            .setColor(color)
            .setStyle(style)
            .setLargeIcon(picture)
            .setSubText("سوسلنگ")
            .setContentTitle(name).setContentText(text)
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setGroup("payamyar_incoming_sms")
            .setPriority(if (floating) NotificationCompat.PRIORITY_DEFAULT else NotificationCompat.PRIORITY_HIGH)
            .setWhen(time).setShowWhen(true)
            .setContentIntent(open).setAutoCancel(true)
            .setSilent(floating || SentSound.quietNow(c))
            .setLights(color, 600, 2400)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .setPublicVersion(NotificationCompat.Builder(c, CHANNEL).setSmallIcon(R.drawable.ic_stat_payamyar)
                .setColor(color).setContentTitle("سوسلنگ").setContentText("پیامک جدید").build())



        if (!sample && !enabled(c, "appLock", false)) {
            val shortcut = conversationShortcut(c, address, name, sender, portrait)
            if (shortcut != null) {
                builder.setShortcutId(shortcut).setLocusId(LocusIdCompat(shortcut))
                // One notification renderer: the custom sender bubble is never stacked with
                // a second OS bubble. MessagingStyle remains in the shade for OEM fallback.
            }
        }

        // The system shade uses MessagingStyle only: its OEM-owned layout handles large
        // fonts, accessibility and lock-screen redaction. Glass is a separate overlay window.
        val actionIcons = enabled(c, "bannerActionIcons")
        if (code != null) {
            builder.addAction(NotificationCompat.Action.Builder(if (actionIcons) R.drawable.ic_glass_copy else 0,
                copyTitle(c, code), broadcast(c, ACTION_COPY, address, code)).setAuthenticationRequired(true).build())
        }
        // Short codes and named senders (banks, services) cannot receive replies.
        if (reply) {
            val input = RemoteInput.Builder(KEY_REPLY).setLabel("پاسخ به " + name.take(18) + "…")
                .setChoices(quickReplies(c)).setAllowFreeFormInput(true).build()
            builder.addAction(NotificationCompat.Action.Builder(if (actionIcons) R.drawable.ic_glass_reply else 0,
                "پاسخ سریع", broadcast(c, ACTION_REPLY, address, mutable = true))
                .addRemoteInput(input).setAllowGeneratedReplies(true)
                .setSemanticAction(NotificationCompat.Action.SEMANTIC_ACTION_REPLY).setShowsUserInterface(false).build())
        }
        if (enabled(c, "notifyMarkRead")) builder.addAction(NotificationCompat.Action.Builder(
            if (actionIcons) R.drawable.ic_glass_read else 0, "خوانده شد", broadcast(c, ACTION_READ, address))
            .setSemanticAction(NotificationCompat.Action.SEMANTIC_ACTION_MARK_AS_READ).setShowsUserInterface(false).build())
        NotificationManagerCompat.from(c).notify(id, builder.build())
    }

    /** Sample Android notification. No message is sent, and it expires automatically. */
    private var sampleCounter = 0
    fun preview(c: Context, sourceKey: String? = null): Boolean {
        if (!enabled(c, "notifyIncoming") || !NotificationManagerCompat.from(c).areNotificationsEnabled() ||
            (Build.VERSION.SDK_INT >= 33 &&
             ContextCompat.checkSelfPermission(c, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED)) {
            return false
        }
        configureChannels(c)
        if (Build.VERSION.SDK_INT >= 26 && c.getSystemService(NotificationManager::class.java)
                .getNotificationChannel(CHANNEL)?.importance == NotificationManager.IMPORTANCE_NONE) return false
        val address = PREVIEW_ADDRESS
        val body = "سلام! کد تأیید آزمایشی شما ۱۲۳۴۵ است."
        val showingBody = enabled(c, "notifyPreview", false) && !enabled(c, "appLock", false)
        val source = if (showingBody) MessengerSender.fromKey(sourceKey) else null
        systemIncoming(c, address, source?.title ?: "سوسلنگ", if (showingBody) body else "پیامک جدید",
            System.currentTimeMillis(), if (showingBody && enabled(c, "notifyOtpCopy")) "12345" else null, false, sample = true, sampleSource = source)
        val token = ++sampleCounter
        Handler(Looper.getMainLooper()).postDelayed({
            if (sampleCounter == token) cancel(c, address)
        }, 10000L)
        return true
    }

    fun redactForLock(c: Context) {
        if (!enabled(c, "appLock", false)) return
        val manager = c.getSystemService(NotificationManager::class.java)
        for (item in manager.activeNotifications) {
            if (item.notification.category == NotificationCompat.CATEGORY_MESSAGE) manager.cancel(item.id)
        }
        FloatingNotifications.refresh()
    }

    fun cancel(c: Context, address: String) {
        FloatingNotifications.clear(address)
        c.getSystemService(NotificationManager::class.java).cancel(idFor(address))
    }
}

class NotifyActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val address = intent.getStringExtra("address") ?: return
        if (context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                .getBoolean("flutter.appLock", false) && intent.action != Notifier.ACTION_READ) {
            Toast.makeText(context, "برای پاسخ یا کپی کد، قفل سوسلنگ را باز کنید", Toast.LENGTH_SHORT).show()
            return
        }
        when (intent.action) {
            Notifier.ACTION_COPY -> {
                val code = intent.getStringExtra("extra") ?: return
                val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                if (!prefs.getBoolean("flutter.notifyOtpCopy", true) || !prefs.getBoolean("flutter.notifyPreview", false) ||
                    context.getSystemService(android.app.KeyguardManager::class.java).isDeviceLocked) return
                Notifier.copyOtp(context, code)
            }
            Notifier.ACTION_READ, Notifier.ACTION_REPLY -> {
                val reply = RemoteInput.getResultsFromIntent(intent)?.getCharSequence(Notifier.KEY_REPLY)?.toString()
                val pending = goAsync()
                Thread {
                    try {
                        // The settings preview uses a non-dialable sample ID: never send to it.
                        if (intent.action == Notifier.ACTION_REPLY && !reply.isNullOrBlank() && address != Notifier.PREVIEW_ADDRESS) {
                            val id = SmsCore.queue(context, address, reply, -1, 0)
                            SmsCore.dispatch(context, id)
                        }
                        if (address != Notifier.PREVIEW_ADDRESS) SmsCore.markAddressRead(context, address)
                        Notifier.cancel(context, address)
                    } catch (_: Exception) {
                        SmsCore.notify(context, 4, "پاسخ ارسال نشد", "سوسلنگ را باز کنید و دوباره تلاش کنید.")
                    } finally {
                        pending.finish()
                    }
                }.start()
            }
        }
    }
}
