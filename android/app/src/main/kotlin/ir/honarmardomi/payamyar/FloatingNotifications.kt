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
        @Volatile private var instance: FloatingNotifications? = null
        private fun prefs(c: Context) = c.getSharedPreferences("payamyar_overlay", MODE_PRIVATE)
        fun allowed(c: Context) = Settings.canDrawOverlays(c)
        fun enabled(c: Context) = prefs(c).getBoolean("enabled", false)
        fun status(c: Context): Map<String, Any> = mapOf(
            "permission" to allowed(c), "enabled" to enabled(c), "running" to (instance != null),
            "bubbleSize" to prefs(c).getInt("bubbleSize", 56),
            "textSize" to prefs(c).getInt("textSize", 15))
        fun setEnabled(c: Context, value: Boolean): Boolean {
            if (value && !allowed(c)) return false
            prefs(c).edit().putBoolean("enabled", value).apply()
            if (!value) { c.stopService(Intent(c, FloatingNotifications::class.java)); return true }
            return try { ContextCompat.startForegroundService(c, Intent(c, FloatingNotifications::class.java)); true }
            catch (_: RuntimeException) { prefs(c).edit().putBoolean("enabled", false).apply(); false }
        }
        fun configure(c: Context, size: Int?, text: Int?) {
            val e = prefs(c).edit()
            size?.let { e.putInt("bubbleSize", it.coerceIn(48, 72)) }
            text?.let { e.putInt("textSize", it.coerceIn(12, 22)) }
            e.apply()
            refresh()
        }
        fun refresh() { instance?.let { service -> service.main.post { service.refreshViews() } } }
        fun clear(address: String) { instance?.let { s -> s.main.post {
            s.messages.remove(address)
            if (s.shown?.address == address) { s.hideCard(); s.shown = null }
            s.renderBubble()
        } } }
        /** Called on the main thread, so success really means a window was attached. */
        fun show(c: Context, address: String, name: String, body: String, sample: Boolean = false): Boolean {
            val s = instance ?: return false
            if (!enabled(c) || !allowed(c) || s.locked() || (!sample && SentSound.quietNow(c))) return false
            if (!sample && MainActivity.foregroundChannel != null) return false
            val message = if (s.privateContent()) Message(address, "پیام‌یار", "پیام جدید", sample) else Message(address, name, body, sample)
            if (!sample) {
                s.messages.remove(address)
                s.messages[address] = message
                while (s.messages.size > 20) s.messages.remove(s.messages.keys.first())
            }
            s.shown = message
            s.renderBubble()
            return s.renderCard(message)
        }
    }
    private data class Message(val address: String, val name: String, val body: String, val sample: Boolean)
    private val main = Handler(Looper.getMainLooper())
    private lateinit var wm: WindowManager
    private val messages = linkedMapOf<String, Message>()
    private var shown: Message? = null
    private var bubble: TextView? = null
    private var card: View? = null
        private val hide = Runnable { hideCard(); if (shown?.sample == true) shown = null }
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
            .setContentTitle("حباب پیام‌یار فعال است").setContentText("برای توقف، خاموش کردن را بزنید")
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
        if (intent?.action == STOP) prefs(this).edit().putBoolean("enabled", false).apply()
        if (!enabled(this) || !allowed(this)) { stopSelf(); return START_NOT_STICKY }
        refreshViews()
        return START_STICKY
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
        if (locked() || !allowed(this) || MainActivity.foregroundChannel != null) return
        val bounds = area()
        val size = dp(prefs(this).getInt("bubbleSize", 56))
        val p = params(size, size)
        val right = prefs(this).getBoolean("right", true)
        p.x = if (right) bounds.right - size else bounds.left
        val fraction = prefs(this).getFloat("y", .35f).coerceIn(0f, 1f)
        p.y = bounds.top + ((bounds.height() - size).coerceAtLeast(0) * fraction).toInt()
        val view = TextView(this).apply {
            text = if (messages.isEmpty()) "پ" else "پ\n${messages.size}"
            textSize = 18f; gravity = Gravity.CENTER; setTextColor(Color.WHITE)
            typeface = Typeface.DEFAULT_BOLD
            background = GlassSurface(tint(), true, true)
            contentDescription = "حباب پیام‌یار، ${messages.size} گفتگو؛ بکشید تا جابه‌جا شود، لمس کنید تا باز شود"
            elevation = dp(4).toFloat()
        }
        var downX = 0f; var downY = 0f; var startX = 0; var startY = 0; var dragged = false
        view.setOnClickListener {
            val msg = messages.values.lastOrNull()
            if (msg == null) open(null) else { shown = msg; renderCard(msg, pinned = true) }
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
        this.text = text; textSize = size; setTextColor(Color.WHITE)
        textDirection = View.TEXT_DIRECTION_FIRST_STRONG; gravity = Gravity.START
        if (bold) typeface = Typeface.DEFAULT_BOLD
        setPadding(dp(3), dp(3), dp(3), dp(3))
    }
    private fun button(text: String, action: () -> Unit) = label(text, 13f, true).apply {
        minHeight = dp(48); gravity = Gravity.CENTER; setPadding(dp(10), dp(4), dp(10), dp(4))
        background = android.graphics.drawable.GradientDrawable().apply {
            cornerRadius = dp(18).toFloat(); setColor(0x22FFFFFF); setStroke(dp(1), 0x33FFFFFF)
        }
        setOnClickListener { action() }
    }
    private fun renderCard(message: Message, pinned: Boolean = false): Boolean {
        hideCard()
        if (locked() || !allowed(this)) return false
        val bounds = area()
        val width = NotificationPolicy.cardWidth(bounds.width(), dp(number("bannerMaxWidth", 360).toInt().coerceIn(280, 520)), dp(8))
        val maxHeight = (bounds.height() * .65f).toInt().coerceAtLeast(1)
        val private = privateContent()
        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL; layoutDirection = View.LAYOUT_DIRECTION_RTL
            setPadding(dp(14), dp(10), dp(14), dp(10))
            background = GlassSurface(tint(), false, flag("bannerBubbles"))
        }
        val header = LinearLayout(this).apply { gravity = Gravity.CENTER_VERTICAL }
        header.addView(label(if (private) "پیام‌یار" else message.name, 17f, true), LinearLayout.LayoutParams(0, -2, 1f))
        header.addView(button("×") { hideCard() }.apply { contentDescription = "بستن اعلان" }, LinearLayout.LayoutParams(dp(48), dp(48)))
        layout.addView(header)
        layout.addView(label(if (message.sample) "پیش‌نمایش؛ پیامی ارسال نمی‌شود" else "پیامک جدید • پیام‌یار", 11f))
        layout.addView(label(if (private) "پیام جدید؛ برای مشاهده برنامه را باز کنید" else message.body,
            prefs(this).getInt("textSize", 15).toFloat()))
        val actions = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        if (!private && flag("notifyOtpCopy")) Notifier.otp(message.body)?.let { code ->
            actions.addView(button("کپی کد $code") {
                getSystemService(ClipboardManager::class.java).setPrimaryClip(ClipData.newPlainText("کد تأیید", code))
                Toast.makeText(this, "کد کپی شد", Toast.LENGTH_SHORT).show()
                hideCard()
            })
        }
        actions.addView(button(if (private) "باز کردن برنامه" else "باز کردن گفتگو / پاسخ") { open(if (message.sample) null else message.address) })
        if (messages.size > 1 && !message.sample) actions.addView(button("گفتگوی بعدی (${messages.size})") {
            val list = messages.values.toList(); val next = list[(list.indexOf(message) + 1).mod(list.size)]
            shown = next; renderCard(next, pinned = true)
        })
        layout.addView(actions)
        val scroll = ScrollView(this).apply {
            isFillViewport = false; isVerticalScrollBarEnabled = true; clipToOutline = true
            background = layout.background; layout.background = null
            outlineProvider = ViewOutlineProvider.BACKGROUND
            addView(layout, ViewGroup.LayoutParams(-1, -2))
            // Reading or scrolling pins the card; it will not disappear under a finger.
            setOnTouchListener { _, e -> if (e.actionMasked == MotionEvent.ACTION_DOWN) main.removeCallbacks(hide); false }
        }
        scroll.measure(View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(maxHeight, View.MeasureSpec.AT_MOST))
        val p = params(width, NotificationPolicy.cardHeight(bounds.height(), scroll.measuredHeight))
        p.x = bounds.left + (bounds.width() - width) / 2
        p.y = if (flag("bannerTop")) bounds.top + dp(8) else bounds.bottom - p.height - dp(8)
        return try {
            wm.addView(scroll, p); card = scroll
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

/** Static frosted glass, with no system-owned outer frame or live background capture. */
private class GlassSurface(private val tint: Int, private val round: Boolean, private val bubbles: Boolean) : Drawable() {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    override fun draw(canvas: Canvas) {
        val rect = RectF(bounds); val radius = if (round) rect.width() / 2 else 26f * (rect.width() / 360f)
        val path = Path().apply { addRoundRect(rect, radius, radius, Path.Direction.CW) }
        canvas.save(); canvas.clipPath(path)
        fun shade(f: Float) = Color.rgb((Color.red(tint) * f).toInt().coerceIn(0,255),
            (Color.green(tint) * f).toInt().coerceIn(0,255), (Color.blue(tint) * f).toInt().coerceIn(0,255))
        paint.shader = LinearGradient(0f, 0f, rect.width(), rect.height(), shade(1.05f), shade(.45f), Shader.TileMode.CLAMP)
        canvas.drawRect(rect, paint)
        paint.shader = LinearGradient(0f, 0f, 0f, rect.height() * .55f, 0x45FFFFFF, 0x00FFFFFF, Shader.TileMode.CLAMP)
        canvas.drawRect(rect, paint); paint.shader = null
        if (bubbles) {
            paint.style = Paint.Style.STROKE; paint.strokeWidth = 1.5f; paint.color = 0x24FFFFFF
            for (i in 0..7) canvas.drawCircle(rect.width() * ((i * 37 + 9) % 100) / 100f,
                rect.height() * ((i * 29 + 13) % 100) / 100f, rect.width() * (.025f + .007f * (i % 3)), paint)
            paint.style = Paint.Style.FILL
        }
        canvas.restore()
    }
    override fun getOutline(outline: Outline) { outline.setRoundRect(bounds, if (round) bounds.width() / 2f else bounds.width() * 26f / 360f) }
    override fun setAlpha(alpha: Int) { }
    override fun setColorFilter(filter: ColorFilter?) { }
    @Deprecated("Deprecated in Java") override fun getOpacity() = PixelFormat.TRANSLUCENT
}
