package ir.honarmardomi.payamyar

import android.app.*
import android.content.*
import android.content.res.Configuration
import android.content.pm.ServiceInfo
import android.graphics.*
import android.graphics.drawable.Drawable
import android.net.Uri
import android.os.*
import android.provider.Settings
import android.view.*
import android.widget.*
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import kotlin.math.*

/** User-started foreground service. Never started by an SMS receiver or at boot. */
class FloatingNotifications : Service() {
    companion object {
        private const val CHANNEL = "floating_controls_v1"
        private const val ID = 900_010
        private const val STOP = "payamyar.STOP_FLOATING"
        private const val SHOW = "payamyar.SHOW_INCOMING_FLOATING"
        @Volatile private var instance: FloatingNotifications? = null
        private fun prefs(c: Context) = c.getSharedPreferences("payamyar_overlay", MODE_PRIVATE)
        fun allowed(c: Context) = Settings.canDrawOverlays(c)
        fun enabled(c: Context) = prefs(c).getBoolean("enabled", false)
        fun status(c: Context): Map<String, Any> = mapOf(
            "permission" to allowed(c), "enabled" to enabled(c), "running" to (instance != null),
            "bubbleSize" to prefs(c).getInt("bubbleSize", 56),
            "textSize" to prefs(c).getInt("textSize", 15),
            "bubbleSeconds" to prefs(c).getInt("bubbleSeconds", 18),
            "bubbleOpacity" to prefs(c).getFloat("bubbleOpacity", .92f).toDouble(),
            "bubbleStyle" to prefs(c).getInt("bubbleStyle", 0),
            "bubbleShape" to prefs(c).getInt("bubbleShape", 0),
            "bubbleColor" to prefs(c).getInt("bubbleColor", 0xFF087F81.toInt()))
        /** Saves an opt-in preference. No idle foreground service or permanent chat head. */
        fun setEnabled(c: Context, value: Boolean): Boolean {
            if (value && !allowed(c)) return false
            prefs(c).edit().putBoolean("enabled", value).apply()
            if (!value) c.stopService(Intent(c, FloatingNotifications::class.java))
            return true
        }
        fun configure(c: Context, size: Int?, text: Int?, seconds: Int?, opacity: Double?,
                      style: Int?, shape: Int?, color: Int?) {
            val e = prefs(c).edit()
            size?.let { e.putInt("bubbleSize", it.coerceIn(48, 72)) }
            text?.let { e.putInt("textSize", it.coerceIn(12, 22)) }
            seconds?.let { e.putInt("bubbleSeconds", it.coerceIn(8, 60)) }
            opacity?.let { e.putFloat("bubbleOpacity", it.toFloat().coerceIn(.78f, 1f)) }
            style?.let { e.putInt("bubbleStyle", it.coerceIn(0, 1)) }
            shape?.let { e.putInt("bubbleShape", it.coerceIn(0, 1)) }
            color?.let { e.putInt("bubbleColor", it or 0xFF000000.toInt()) }
            e.apply()
            refresh()
        }
        fun refresh() { instance?.let { service -> service.main.post { service.refreshViews() } } }
        fun clear(address: String) { instance?.let { service -> service.main.post {
            service.messages.remove(address)
            if (service.shown?.address == address) { service.hideCard(); service.shown = null }
            service.renderBubble()
            if (service.messages.isEmpty()) service.stopSelf()
        } } }
        /**
         * Start a *short-lived* foreground service only for an actual arriving message.
         * Every SMS still gets a regular system notification as the delivery fallback.
         */
        fun show(c: Context, address: String, name: String, body: String, sample: Boolean = false): Boolean {
            if (!enabled(c) || !allowed(c) || (!sample && SentSound.quietNow(c))) return false
            if (!sample && MainActivity.foregroundChannel != null) return false
            val service = instance
            if (service != null) return service.display(address, name, body, sample)
            return try {
                ContextCompat.startForegroundService(c, Intent(c, FloatingNotifications::class.java)
                    .setAction(SHOW).putExtra("address", address).putExtra("name", name)
                    .putExtra("body", body).putExtra("sample", sample))
                true
            } catch (_: RuntimeException) {
                // Android/OEM background-launch restrictions: native MessagingStyle remains available.
                false
            }
        }
    }
    private data class Message(val address: String, val name: String, val body: String, val sample: Boolean)
    private val main = Handler(Looper.getMainLooper())
    private lateinit var wm: WindowManager
    private val messages = linkedMapOf<String, Message>()
    private var shown: Message? = null
    private var bubble: TextView? = null
    private var card: View? = null
    private val hide = Runnable { hideCard(); if (shown?.sample == true) { shown = null; stopSelf() } }
    private val expireBubble = Runnable {
        hideCard(); removeBubble(); messages.clear(); shown = null; stopSelf()
    }
    private val settings by lazy { getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE) }
    private val changed = SharedPreferences.OnSharedPreferenceChangeListener { _, _ -> main.post {
        // Never retain previously visible private text after enabling a privacy switch.
        if (privateContent()) { messages.clear(); shown = null; hideCard() }
        refreshViews()
    } }
    private val screen = object : BroadcastReceiver() {
        override fun onReceive(c: Context, i: Intent) {
            if (i.action == Intent.ACTION_SCREEN_OFF) {
                hideCard(); removeBubble(); shown = null; messages.clear()
            } else refreshViews()
        }
    }
    private fun flag(key: String, default: Boolean = true) = settings.getBoolean("flutter.$key", default)
    private fun number(key: String, default: Long) = (settings.all["flutter.$key"] as? Number)?.toLong() ?: default
    private fun privateContent() = flag("appLock", false) || !flag("notifyPreview")
    private fun locked() = getSystemService(KeyguardManager::class.java).isKeyguardLocked ||
        !getSystemService(PowerManager::class.java).isInteractive
    private fun dp(n: Int) = (n * resources.displayMetrics.density).roundToInt()
    private fun tint() = number("notifyAccent", 0xFF087F81).toInt()
    private fun opacity() = ((settings.all["flutter.bannerOpacity"] as? Number)?.toFloat() ?: .9f).coerceIn(.78f, 1f)
    private fun cardStyle() = number("bannerStyle", 0).toInt().coerceIn(0, 2)
    private fun bubbleColor() = prefs(this).getInt("bubbleColor", tint())
    override fun onBind(intent: Intent?): IBinder? = null
    override fun onCreate() {
        super.onCreate()
        wm = getSystemService(WindowManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) getSystemService(NotificationManager::class.java)
            .createNotificationChannel(NotificationChannel(CHANNEL, "کنترل حباب شناور", NotificationManager.IMPORTANCE_LOW))
        val stop = PendingIntent.getService(this, 0, Intent(this, FloatingNotifications::class.java).setAction(STOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val open = PendingIntent.getActivity(this, ID, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val notification = NotificationCompat.Builder(this, CHANNEL).setSmallIcon(R.drawable.ic_stat_payamyar)
            .setContentTitle("اعلان موقت پیام‌یار").setContentText("حباب گفتگو پس از زمان انتخاب‌شده بسته می‌شود")
            .setContentIntent(open).setOngoing(true).setSilent(true)
            .addAction(0, "خاموش کردن", stop).build()
        if (Build.VERSION.SDK_INT >= 34) startForeground(ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        else startForeground(ID, notification)
        instance = this
        settings.registerOnSharedPreferenceChangeListener(changed)
        ContextCompat.registerReceiver(this, screen, IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_OFF); addAction(Intent.ACTION_USER_PRESENT)
        }, ContextCompat.RECEIVER_NOT_EXPORTED)
    }
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == STOP) {
            prefs(this).edit().putBoolean("enabled", false).apply()
            stopSelf()
            return START_NOT_STICKY
        }
        if (!enabled(this) || !allowed(this)) { stopSelf(); return START_NOT_STICKY }
        if (intent?.action == SHOW) {
            val address = intent.getStringExtra("address").orEmpty()
            if (address.isNotBlank()) display(address, intent.getStringExtra("name").orEmpty(),
                intent.getStringExtra("body").orEmpty(), intent.getBooleanExtra("sample", false))
            else stopSelf()
        } else if (messages.isEmpty()) stopSelf()
        return START_NOT_STICKY
    }
    private fun display(address: String, name: String, body: String, sample: Boolean): Boolean {
        if (locked() || !allowed(this) || !enabled(this) ||
            (!sample && MainActivity.foregroundChannel != null)) { stopSelf(); return false }
        val message = if (privateContent()) Message(address, "پیام‌یار", "پیام جدید", sample)
                      else Message(address, name.ifBlank { address }, body, sample)
        if (!sample) {
            messages.remove(address)
            messages[address] = message
            while (messages.size > 10) messages.remove(messages.keys.first())
        }
        shown = message
        main.removeCallbacks(expireBubble)
        if (!sample) {
            renderBubble()
            main.postDelayed(expireBubble, prefs(this).getInt("bubbleSeconds", 18).coerceIn(8, 60) * 1000L)
        }
        val visible = renderCard(message)
        if (sample) main.postDelayed({ if (messages.isEmpty()) stopSelf() }, 17000)
        return visible
    }
    override fun onDestroy() {
        main.removeCallbacksAndMessages(null)
        hideCard(); removeBubble(); messages.clear(); shown = null
        settings.unregisterOnSharedPreferenceChangeListener(changed)
        try { unregisterReceiver(screen) } catch (_: IllegalArgumentException) { }
        if (instance === this) instance = null
        super.onDestroy()
    }
    override fun onConfigurationChanged(newConfig: Configuration) { super.onConfigurationChanged(newConfig); refreshViews() }
    private fun refreshViews() {
        if (!allowed(this) || !enabled(this)) { stopSelf(); return }
        if (locked() || MainActivity.foregroundChannel != null) { hideCard(); removeBubble(); return }
        val hadCard = card != null
        renderBubble()
        if (hadCard) shown?.let { renderCard(it) }
    }
    private fun area(): Rect {
        if (Build.VERSION.SDK_INT >= 30) {
            val m = wm.currentWindowMetrics
            val i = m.windowInsets.getInsetsIgnoringVisibility(WindowInsets.Type.systemBars() or WindowInsets.Type.displayCutout())
            return Rect(i.left, i.top, m.bounds.width() - i.right, m.bounds.height() - i.bottom)
        }
        val m = resources.displayMetrics
        return Rect(dp(8), dp(32), m.widthPixels - dp(8), m.heightPixels - dp(48))
    }
    @Suppress("DEPRECATION")
    private fun params(w: Int, h: Int) = WindowManager.LayoutParams(w, h,
        if (Build.VERSION.SDK_INT >= 26) WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY else WindowManager.LayoutParams.TYPE_PHONE,
        WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
            WindowManager.LayoutParams.FLAG_SECURE,
        PixelFormat.TRANSLUCENT).apply { gravity = Gravity.TOP or Gravity.LEFT }
    private fun removeBubble() { bubble?.let { try { wm.removeView(it) } catch (_: RuntimeException) { } }; bubble = null }
    private fun hideCard() { main.removeCallbacks(hide); card?.let { try { wm.removeView(it) } catch (_: RuntimeException) { } }; card = null }
    private fun renderBubble() {
        removeBubble()
        if (locked() || !allowed(this) || MainActivity.foregroundChannel != null || messages.isEmpty()) return
        val bounds = area()
        val size = dp(prefs(this).getInt("bubbleSize", 56))
        val p = params(size, size)
        val right = prefs(this).getBoolean("right", true)
        p.x = if (right) bounds.right - size else bounds.left
        val fraction = prefs(this).getFloat("y", .35f).coerceIn(0f, 1f)
        p.y = bounds.top + ((bounds.height() - size).coerceAtLeast(0) * fraction).toInt()
        val view = TextView(this).apply {
            val latestName = messages.values.last().name.trim()
            val initial = if (privateContent()) "پ" else latestName.take(1).ifBlank { "پ" }
            text = if (messages.size > 1) "$initial\n${messages.size}" else initial
            textSize = if (messages.size > 1) 15f else 22f
            gravity = Gravity.CENTER
            setTextColor(if (prefs(this@FloatingNotifications).getInt("bubbleStyle", 0) == 0)
                0xFF17383D.toInt() else Color.WHITE)
            typeface = Typeface.DEFAULT_BOLD
            background = GlassSurface(bubbleColor(), prefs(this@FloatingNotifications).getInt("bubbleShape", 0) == 0,
                prefs(this@FloatingNotifications).getInt("bubbleStyle", 0) == 0,
                prefs(this@FloatingNotifications).getFloat("bubbleOpacity", .92f), 0)
            contentDescription = "حباب پیام‌یار، ${messages.size} گفتگو؛ بکشید تا جابه‌جا شود، لمس کنید تا باز شود"
            elevation = dp(4).toFloat()
        }
        var downX = 0f; var downY = 0f; var startX = 0; var startY = 0; var dragged = false
        view.setOnClickListener {
            val msg = messages.values.lastOrNull()
            if (msg == null) open(null) else { shown = msg; renderCard(msg, pinned = true, expanded = true) }
        }
        view.setOnTouchListener { v, event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> { downX = event.rawX; downY = event.rawY; startX = p.x; startY = p.y; dragged = false; true }
                MotionEvent.ACTION_MOVE -> {
                    val dx = event.rawX - downX; val dy = event.rawY - downY
                    if (hypot(dx, dy) > ViewConfiguration.get(this).scaledTouchSlop) dragged = true
                    if (dragged) {
                        p.x = (startX + dx.toInt()).coerceIn(bounds.left, max(bounds.left, bounds.right - size))
                        p.y = (startY + dy.toInt()).coerceIn(bounds.top, max(bounds.top, bounds.bottom - size))
                        try { wm.updateViewLayout(v, p) } catch (_: RuntimeException) { }
                    }; true
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    if (dragged) {
                        val edge = p.x + size / 2 > bounds.centerX()
                        p.x = if (edge) bounds.right - size else bounds.left
                        prefs(this).edit().putBoolean("right", edge)
                            .putFloat("y", (p.y - bounds.top).toFloat() / max(1, bounds.height() - size)).apply()
                        try { wm.updateViewLayout(v, p) } catch (_: RuntimeException) { }
                    } else if (event.actionMasked == MotionEvent.ACTION_UP) v.performClick()
                    true
                }
                else -> false
            }
        }
        try { wm.addView(view, p); bubble = view } catch (_: RuntimeException) { stopSelf() }
    }
    private fun label(text: String, size: Float, bold: Boolean = false) = TextView(this).apply {
        this.text = text; textSize = size
        setTextColor(if (cardStyle() == 2) 0xFF172D33.toInt() else Color.WHITE)
        textDirection = View.TEXT_DIRECTION_FIRST_STRONG; gravity = Gravity.START
        if (bold) typeface = Typeface.DEFAULT_BOLD
        setPadding(dp(3), dp(3), dp(3), dp(3))
    }
    private fun button(text: String, action: () -> Unit) = label(text, 13f, true).apply {
        minHeight = dp(48); gravity = Gravity.CENTER; setPadding(dp(10), dp(4), dp(10), dp(4))
        background = android.graphics.drawable.GradientDrawable().apply {
            cornerRadius = dp(18).toFloat()
            setColor(if (cardStyle() == 2) 0x19087F81 else 0x33FFFFFF)
            setStroke(dp(1), if (cardStyle() == 2) 0x44087F81 else 0x65FFFFFF)
        }
        setOnClickListener { action() }
    }
    /** Teal frosted notification: sender avatar, complete message and accessible scrollable actions. */
    private fun renderCard(message: Message, pinned: Boolean = false,
                           expanded: Boolean = true): Boolean {
        hideCard()
        if (locked() || !allowed(this) || !enabled(this)) return false
        val bounds = area()
        val width = NotificationPolicy.cardWidth(bounds.width(),
            dp(number("bannerMaxWidth", 360).toInt().coerceIn(280, 520)), dp(8))
        val maxHeight = (bounds.height() * .65f).toInt().coerceAtLeast(1)
        val private = privateContent()
        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            layoutDirection = View.LAYOUT_DIRECTION_RTL
            setPadding(dp(14), dp(10), dp(14), dp(11))
            background = GlassSurface(tint(), false, flag("bannerBubbles"), opacity(), cardStyle())
        }
        val header = LinearLayout(this).apply {
            gravity = Gravity.CENTER_VERTICAL
            layoutDirection = View.LAYOUT_DIRECTION_RTL
            minimumHeight = dp(66)
        }
        val avatar = TextView(this).apply {
            text = if (private) "پ" else message.name.trim().take(1).ifBlank { "پ" }
            textSize = 20f
            gravity = Gravity.CENTER
            typeface = Typeface.DEFAULT_BOLD
            setTextColor(Color.WHITE)
            background = android.graphics.drawable.GradientDrawable().apply {
                shape = android.graphics.drawable.GradientDrawable.OVAL
                setColor(tint() or 0xFF000000.toInt())
                setStroke(dp(2), 0xFFCF9B62.toInt())
            }
            contentDescription = "تصویر فرستنده"
        }
        header.addView(avatar, LinearLayout.LayoutParams(dp(42), dp(42)).apply { marginEnd = dp(10) })
        val mainText = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        mainText.addView(label(if (private) "پیام‌یار" else message.name, 15.5f, true))
        val summary = if (private) "پیام جدید؛ برای مشاهده، برنامه را باز کنید"
            else if (message.sample) "پیش‌نمایش اعلان پیام‌یار"
            else message.body.replace("\n", " ")
        mainText.addView(label(summary, 13f).apply {
            maxLines = if (expanded) 3 else 2
            ellipsize = android.text.TextUtils.TruncateAt.END
        })
        header.addView(mainText, LinearLayout.LayoutParams(0, -2, 1f))
        val chevron = TextView(this).apply {
            text = if (expanded) "⌃" else "⌄"
            textSize = 25f; gravity = Gravity.CENTER
            setTextColor(if (cardStyle() == 2) 0xFF1F343B.toInt() else Color.WHITE)
            contentDescription = if (expanded) "جمع کردن اعلان" else "باز کردن متن کامل اعلان"
            minWidth = dp(48); minHeight = dp(48)
            setOnClickListener { renderCard(message, pinned = true, expanded = !expanded) }
        }
        header.addView(chevron, LinearLayout.LayoutParams(dp(48), dp(48)))
        header.setOnClickListener { renderCard(message, pinned = true, expanded = !expanded) }
        layout.addView(header)
        if (expanded) {
            layout.addView(label(if (private) "پیام جدید؛ برای مشاهده برنامه را باز کنید" else message.body,
                prefs(this).getInt("textSize", 15).toFloat()).apply {
                setPadding(dp(4), dp(8), dp(4), dp(12))
            })
            val actions = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
            if (!private && flag("notifyOtpCopy")) Notifier.otp(message.body)?.let { code ->
                actions.addView(button("کپی کد $code") {
                    getSystemService(ClipboardManager::class.java)
                        .setPrimaryClip(ClipData.newPlainText("کد تأیید", code))
                    Toast.makeText(this, "کد کپی شد", Toast.LENGTH_SHORT).show()
                    hideCard()
                })
            }
            actions.addView(button(if (private) "باز کردن برنامه" else "باز کردن گفتگو / پاسخ") {
                open(if (message.sample) null else message.address)
            })
            if (messages.size > 1 && !message.sample) actions.addView(button("گفتگوی بعدی (${messages.size})") {
                val list = messages.values.toList()
                val next = list[(list.indexOf(message) + 1).mod(list.size)]
                shown = next
                renderCard(next, pinned = true, expanded = true)
            })
            layout.addView(actions)
        }
        val scroll = ScrollView(this).apply {
            isFillViewport = false
            isVerticalScrollBarEnabled = expanded
            clipToOutline = true
            background = layout.background
            layout.background = null
            outlineProvider = ViewOutlineProvider.BACKGROUND
            addView(layout, ViewGroup.LayoutParams(-1, -2))
            setOnTouchListener { _, e ->
                if (e.actionMasked == MotionEvent.ACTION_DOWN) main.removeCallbacks(hide)
                false
            }
        }
        scroll.measure(View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(maxHeight, View.MeasureSpec.AT_MOST))
        val p = params(width, NotificationPolicy.cardHeight(bounds.height(), scroll.measuredHeight))
        p.x = bounds.left + (bounds.width() - width) / 2
        p.y = if (flag("bannerTop")) bounds.top + dp(8) else bounds.bottom - p.height - dp(8)
        return try {
            wm.addView(scroll, p)
            card = scroll
            if (!pinned) main.postDelayed(hide, number("bannerSeconds", 6).coerceIn(2, 15) * 1000)
            true
        } catch (_: RuntimeException) { false }
    }
    private fun open(address: String?) {
        hideCard()
        val intent = Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        if (address != null) intent.setAction("ir.honarmardomi.payamyar.OPEN_CONVERSATION")
            .setData(Uri.parse("payamyar:open/" + Uri.encode(address)))
            .putExtra("open_address", address).putExtra("open_token", MainActivity.launchToken(this))
        try { startActivity(intent) } catch (_: RuntimeException) {
            Toast.makeText(this, "برای مشاهده پیام، پیام‌یار را باز کنید", Toast.LENGTH_SHORT).show()
        }
    }
}

/** Theme-aware, high-contrast overlay surface. The OS cannot provide cross-app backdrop blur. */
private class GlassSurface(
    private val tint: Int, private val round: Boolean, private val bubbles: Boolean,
    private val opacity: Float, private val style: Int
) : Drawable() {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    override fun draw(canvas: Canvas) {
        val rect = RectF(bounds)
        val radius = if (round) rect.width() / 2 else min(rect.width(), rect.height()) * .18f
        val path = Path().apply { addRoundRect(rect, radius, radius, Path.Direction.CW) }
        canvas.save(); canvas.clipPath(path)
        // Reference palette: luminous emerald outer edge and deep teal card.
        // A firm alpha floor keeps white typography legible on bright wallpapers.
        val paper = style == 2
        val bright = paper
        val effectiveAlpha = if (paper) 255
            else (opacity.coerceIn(.82f, 1f) * 255).toInt()
        fun shade(f: Float) = Color.argb(effectiveAlpha,
            (Color.red(tint) * f).toInt().coerceIn(0, 255),
            (Color.green(tint) * f).toInt().coerceIn(0, 255),
            (Color.blue(tint) * f).toInt().coerceIn(0, 255))
        val top = if (paper) 0xFFFDFCF8.toInt()
            else if (style == 0) Color.argb(effectiveAlpha, 12, 105, 108)
            else shade(.98f)
        val bottom = if (paper) 0xFFF0F2F0.toInt()
            else if (style == 0) Color.argb(effectiveAlpha, 5, 68, 76)
            else shade(.47f)
        paint.shader = LinearGradient(0f, 0f, rect.width(), rect.height(),
            top, bottom, Shader.TileMode.CLAMP)
        canvas.drawRect(rect, paint); paint.shader = null
        if (!bright) {
            paint.shader = LinearGradient(0f, 0f, 0f, rect.height() * .5f,
                0x38FFFFFF, 0x00FFFFFF, Shader.TileMode.CLAMP)
            canvas.drawRect(rect, paint); paint.shader = null
        }
        if (bubbles && !paper) {
            paint.style = Paint.Style.STROKE
            paint.strokeWidth = 1.5f; paint.color = if (bright) 0x16087F81 else 0x2CFFFFFF
            for (i in 0..5) canvas.drawCircle(rect.width() * ((i * 37 + 9) % 100) / 100f,
                rect.height() * ((i * 29 + 13) % 100) / 100f,
                rect.width() * (.025f + .007f * (i % 3)), paint)
            paint.style = Paint.Style.FILL
        }
        paint.color = if (paper) 0x66087F81 else 0xFF92CFC2.toInt()
        paint.style = Paint.Style.STROKE; paint.strokeWidth = 1.5f
        canvas.drawRoundRect(RectF(rect.left + 1f, rect.top + 1f, rect.right - 1f, rect.bottom - 1f),
            radius, radius, paint)
        paint.style = Paint.Style.FILL
        canvas.restore()
    }
    override fun getOutline(outline: Outline) {
        outline.setRoundRect(bounds, if (round) bounds.width() / 2f
            else min(bounds.width(), bounds.height()) * .18f)
    }
    override fun setAlpha(alpha: Int) { }
    override fun setColorFilter(filter: ColorFilter?) { }
    @Deprecated("Deprecated in Java") override fun getOpacity() = PixelFormat.TRANSLUCENT
}
