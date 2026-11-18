package ir.honarmardomi.payamyar

import android.app.*
import android.content.*
import android.content.res.Configuration
import android.content.pm.ServiceInfo
import android.graphics.*
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.RippleDrawable
import android.content.res.ColorStateList
import android.text.TextUtils
import androidx.core.graphics.ColorUtils
import android.net.Uri
import android.os.*
import android.provider.Settings
import android.view.*
import android.view.accessibility.AccessibilityManager
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
            "sources" to MessengerSender.values().map { mapOf("key" to it.name, "title" to it.title,
                "color" to (it.color.toLong() and 0xffffffffL)) },
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
            if (service.shown?.address == address) service.dismissCard()
            else if (service.messages.isEmpty() && service.shown == null) service.stopSelf()
            else if (service.card == null) service.renderBubble()
        } } }
        /**
         * Start a *short-lived* foreground service only for an actual arriving message.
         * Every SMS still gets a regular system notification as the delivery fallback.
         */
        fun show(c: Context, address: String, name: String, body: String, sample: Boolean = false,
                 time: Long = System.currentTimeMillis(), sampleSource: String? = null, onDisplayed: (Boolean) -> Unit = {}): Boolean {
            val eligible = enabled(c) && allowed(c) &&
                !c.getSystemService(KeyguardManager::class.java).isKeyguardLocked &&
                c.getSystemService(PowerManager::class.java).isInteractive &&
                (sample || (MainActivity.foregroundChannel == null && !SentSound.quietNow(c)))
            if (!eligible) { onDisplayed(false); return false }
            instance?.let { service ->
                val visible = service.display(address, name, body, sample, time, sampleSource)
                onDisplayed(visible)
                return visible
            }
            val handler = Handler(Looper.getMainLooper())
            var completed = false
            fun finish(visible: Boolean) {
                if (completed) return
                completed = true
                onDisplayed(visible)
            }
            val timeout = Runnable { finish(false) }
            val receiver = object : ResultReceiver(handler) {
                override fun onReceiveResult(resultCode: Int, resultData: Bundle?) {
                    handler.removeCallbacks(timeout)
                    finish(resultCode == 1)
                }
            }
            return try {
                val deadline = SystemClock.elapsedRealtime() + 2000L
                ContextCompat.startForegroundService(c, Intent(c, FloatingNotifications::class.java)
                    .setAction(SHOW).putExtra("address", address).putExtra("name", name)
                    .putExtra("body", body).putExtra("sample", sample).putExtra("time", time)
                    .putExtra("sampleSource", sampleSource).putExtra("deadline", deadline).putExtra("result", receiver))
                handler.postDelayed(timeout, 2000L)
                true
            } catch (_: RuntimeException) {
                finish(false)
                false
            }
        }
    }
    private data class Message(val address: String, val name: String, val body: String, val sample: Boolean, val time: Long, val source: MessengerSender?)
    private val main = Handler(Looper.getMainLooper())
    private lateinit var wm: WindowManager
    private val messages = linkedMapOf<String, Message>()
    private var shown: Message? = null
    private var bubble: TextView? = null
    private var card: View? = null
    private var expandedCard = false
    private var replyField: EditText? = null
    private val hide = Runnable { dismissCard() }
    private val expireBubble = Runnable {
        hideCard(); removeBubble(); messages.clear(); shown = null; stopSelf()
    }
    private val settings by lazy { getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE) }
    private val redraw = Runnable { refreshViews() }
    private val changed = SharedPreferences.OnSharedPreferenceChangeListener { _, key ->
        if (key == "flutter.appLock" || key == "flutter.notifyPreview") {
            if (privateContent()) {
                messages.clear()
                shown = null
                hideCard()
                removeBubble()
                stopSelf()
            }
        } else if (key?.startsWith("flutter.banner") == true || key?.startsWith("flutter.notify") == true ||
            key == "flutter.reduceEffects") {
            main.removeCallbacks(redraw)
            main.post(redraw)
        }
    }
    private val screen = object : BroadcastReceiver() {
        override fun onReceive(c: Context, i: Intent) {
            if (i.action == Intent.ACTION_SCREEN_OFF) {
                hideCard(); removeBubble(); shown = null; messages.clear(); stopSelf()
            } else refreshViews()
        }
    }
    private fun flag(key: String, default: Boolean = true) = settings.getBoolean("flutter.$key", default)
    private fun number(key: String, default: Long) = (settings.all["flutter.$key"] as? Number)?.toLong() ?: default
    private fun privateContent() = flag("appLock", false) || !flag("notifyPreview", false)
    private fun locked() = getSystemService(KeyguardManager::class.java).isKeyguardLocked ||
        !getSystemService(PowerManager::class.java).isInteractive
    private fun dp(n: Int) = (n * resources.displayMetrics.density).roundToInt()
    private val cardFont by lazy {
        try { Typeface.createFromAsset(assets, "flutter_assets/assets/fonts/Vazirmatn.ttf") }
        catch (_: RuntimeException) { Typeface.DEFAULT }
    }
    private val boldCardFont by lazy { Typeface.create(cardFont, Typeface.BOLD) }
    private fun cardTimeout(pinned: Boolean): Long {
        val base = if (pinned) 60000 else number("bannerSeconds", 6).coerceIn(2, 15).toInt() * 1000
        if (Build.VERSION.SDK_INT < 29) return base.toLong()
        return getSystemService(AccessibilityManager::class.java).getRecommendedTimeoutMillis(base,
            AccessibilityManager.FLAG_CONTENT_TEXT or AccessibilityManager.FLAG_CONTENT_ICONS or
                AccessibilityManager.FLAG_CONTENT_CONTROLS).toLong()
    }

    private fun tint() = number("notifyAccent", 0xFF087F81).toInt()
    private fun surfaceFloat(key: String, default: Float) =
        NotificationPolicy.flutterFloat(settings.all["flutter.$key"], default)
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
        if (intent?.action == SHOW) {
            @Suppress("DEPRECATION")
            val result = intent.getParcelableExtra<ResultReceiver>("result")
            val address = intent.getStringExtra("address").orEmpty()
            val timely = SystemClock.elapsedRealtime() < intent.getLongExtra("deadline", 0)
            val visible = timely && address.isNotBlank() &&
                display(address, intent.getStringExtra("name").orEmpty(),
                    intent.getStringExtra("body").orEmpty(), intent.getBooleanExtra("sample", false),
                    intent.getLongExtra("time", System.currentTimeMillis()), intent.getStringExtra("sampleSource"))
            result?.send(if (visible) 1 else 0, null)
            if (!visible && messages.isEmpty() && card == null) stopSelf(startId)
        } else if (messages.isEmpty()) stopSelf(startId)
        return START_NOT_STICKY
    }
    private fun display(address: String, name: String, body: String, sample: Boolean, time: Long, sampleSource: String?): Boolean {
        if (locked() || !allowed(this) || !enabled(this) ||
            (!sample && MainActivity.foregroundChannel != null)) { stopSelf(); return false }
        val source = if (sample) MessengerSender.fromKey(sampleSource) else MessengerSender.fromAddress(address)
        val message = if (privateContent()) Message(address, "پیام‌یار", "پیام جدید", sample, time, null)
                      else Message(address, name.ifBlank { address }, body, sample, time, source)
        if (!sample) {
            messages.remove(address)
            messages[address] = message
            while (messages.size > 10) messages.remove(messages.keys.first())
        }
        shown = message
        main.removeCallbacks(expireBubble)
        val visible = renderCard(message)
        if (!visible) dismissCard()
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
        if (locked() || (MainActivity.foregroundChannel != null && shown?.sample != true)) {
            hideCard(); removeBubble()
            if (messages.isEmpty()) stopSelf() else scheduleBubbleExpiry()
            return
        }
        if (card != null) {
            // Keep the editor, selection and undo callback intact while the keyboard is open.
            if (replyField == null) shown?.let { renderCard(it, pinned = expandedCard, expanded = expandedCard) }
        } else renderBubble()
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
    private fun params(w: Int, h: Int, focusable: Boolean = false) = WindowManager.LayoutParams(w, h,
        if (Build.VERSION.SDK_INT >= 26) WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY else WindowManager.LayoutParams.TYPE_PHONE,
        WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
            WindowManager.LayoutParams.FLAG_SECURE,
        PixelFormat.TRANSLUCENT).apply {
            gravity = Gravity.TOP or Gravity.LEFT
            if (focusable) {
                flags = flags and WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE.inv()
                softInputMode = WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE
            }
        }
    private fun removeBubble() { bubble?.let { try { wm.removeView(it) } catch (_: RuntimeException) { } }; bubble = null }
    private fun hideCard() { main.removeCallbacks(hide); card?.let { try { wm.removeView(it) } catch (_: RuntimeException) { } }; card = null; replyField = null }
    private fun scheduleBubbleExpiry() {
        main.removeCallbacks(expireBubble)
        main.postDelayed(expireBubble, prefs(this).getInt("bubbleSeconds", 18).coerceIn(8, 60) * 1000L)
    }
    private fun dismissCard() {
        hideCard()
        shown = null
        if (messages.isEmpty()) stopSelf() else {
            renderBubble()
            scheduleBubbleExpiry()
        }
    }
    private fun renderBubble() {
        removeBubble()
        if (card != null || locked() || !allowed(this) || MainActivity.foregroundChannel != null || messages.isEmpty()) return
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
            setTextColor(Color.WHITE)
            typeface = boldCardFont
            background = GlassSurface(bubbleColor(), resources.displayMetrics.density, 16f,
                prefs(this@FloatingNotifications).getInt("bubbleStyle", 0) == 0,
                prefs(this@FloatingNotifications).getFloat("bubbleOpacity", .92f), .72f, .55f,
                avatar = true, round = prefs(this@FloatingNotifications).getInt("bubbleShape", 0) == 0)
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
    private fun label(value: String, size: Float, bold: Boolean = false) = TextView(this).apply {
        text = value
        textSize = size
        setTextColor(Color.WHITE)
        textDirection = View.TEXT_DIRECTION_FIRST_STRONG_RTL
        gravity = Gravity.RIGHT or Gravity.CENTER_VERTICAL
        includeFontPadding = false
        typeface = if (bold) boldCardFont else cardFont
    }
    private fun button(text: String, icon: Int = 0, action: () -> Unit) = label(text, 13f, true).apply {
        minHeight = dp(48)
        gravity = Gravity.CENTER
        maxLines = 2
        ellipsize = TextUtils.TruncateAt.END
        setPadding(dp(12), dp(4), dp(12), dp(4))
        background = RippleDrawable(ColorStateList.valueOf(0x32FFFFFF), GradientDrawable().apply {
            cornerRadius = dp(24).toFloat()
            setColor(0x28FFFFFF)
            setStroke(dp(1), 0x66FFFFFF)
        }, null)
        if (icon != 0) {
            setCompoundDrawablesRelativeWithIntrinsicBounds(icon, 0, 0, 0)
            compoundDrawablePadding = dp(6)
        }
        setOnClickListener { action() }
    }
    /** Fit actions at their measured text size, wrapping before the edge in RTL. */
    private fun addActionRows(parent: LinearLayout, chips: List<View>, available: Int) {
        val limit = available.coerceAtLeast(1)
        var row: LinearLayout? = null
        var used = 0
        for (chip in chips) {
            chip.measure(View.MeasureSpec.makeMeasureSpec(limit, View.MeasureSpec.AT_MOST),
                View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED))
            val width = chip.measuredWidth.coerceAtMost(limit)
            if (row == null || used + dp(6) + width > limit) {
                row = LinearLayout(this).apply { gravity = Gravity.RIGHT; layoutDirection = View.LAYOUT_DIRECTION_RTL }
                parent.addView(row, LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(6) })
                used = 0
            }
            val gap = if (used == 0) 0 else dp(6)
            row.addView(chip, LinearLayout.LayoutParams(width, -2).apply { marginStart = gap })
            used += gap + width
        }
    }
    private fun String.codePointsCompatInitial(): String? {
        val clean = trim()
        if (clean.isEmpty()) return null
        val code = clean.codePointAt(0)
        return if (Character.isLetter(code)) String(Character.toChars(code)) else null
    }
    private fun persianDigits(value: String) = value.map { if (it in '0'..'9') '۰' + (it - '0') else it }.joinToString("")

    private fun renderCard(message: Message, pinned: Boolean = false,
                           expanded: Boolean = false, replying: Boolean = false): Boolean {
        hideCard()
        removeBubble()
        main.removeCallbacks(expireBubble)
        if (locked() || !allowed(this) || !enabled(this)) return false
        expandedCard = expanded
        val bounds = area()
        val width = NotificationPolicy.cardWidth(bounds.width(),
            dp(surfaceFloat("bannerMaxWidth", 360f).coerceIn(280f, 520f).roundToInt()), dp(8))
        val maxHeight = NotificationPolicy.cardHeight(bounds.height(), Int.MAX_VALUE)
        val private = privateContent()
        val source = if (private) null else message.source
        val accent = if (flag("bannerSourceColors")) source?.selectedColor(settings) ?: tint() else tint()
        val name = if (message.name == message.address && source != null) source.title else message.name
        val phone = message.address.replace(Regex("""[\s()-]"""), "")
        val dialable = !private && !message.sample && Regex("""^\+?[0-9]{7,15}$""").matches(phone)
        val canReplyHere = dialable && flag("notifyQuickReply") && SmsCore.isDefault(this)
        val density = resources.displayMetrics.density
        val reduce = flag("reduceEffects", false)
        val edge = surfaceFloat("bannerEdge", .72f).coerceIn(.15f, 1f)
        val shine = surfaceFloat("bannerShine", .55f).coerceIn(0f, 1f)
        val corner = surfaceFloat("bannerCorner", 26f).coerceIn(16f, 36f)
        val surface = GlassSurface(accent, density, corner, flag("bannerBubbles"),
            surfaceFloat("bannerOpacity", .9f).coerceIn(.78f, 1f), edge, shine)
        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            layoutDirection = View.LAYOUT_DIRECTION_RTL
            setPadding(dp(18), dp(12), dp(18), dp(12))
        }
        val header = LinearLayout(this).apply {
            gravity = Gravity.CENTER_VERTICAL
            layoutDirection = View.LAYOUT_DIRECTION_RTL
        }
        val badge = GradientDrawable(GradientDrawable.Orientation.TOP_BOTTOM, intArrayOf(
            ColorUtils.blendARGB(accent, Color.WHITE, if (flag("notifyGlassAvatar")) .32f else .04f),
            ColorUtils.blendARGB(accent, Color.BLACK, .30f))).apply {
            cornerRadius = dp(if (number("notifyAvatarShape", 0) == 0L) 23 else 12).toFloat()
            setStroke(dp(1), 0xCBFFFFFF.toInt())
        }
        val initial = name.codePointsCompatInitial()
        val avatar = if (initial == null) ImageView(this).apply {
            setImageResource(R.drawable.ic_glass_chat)
            scaleType = ImageView.ScaleType.CENTER
        } else label(initial, 19f, true).apply {
            gravity = Gravity.CENTER
            setTextSize(android.util.TypedValue.COMPLEX_UNIT_DIP, 19f)
        }
        avatar.background = badge
        avatar.importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        header.addView(avatar, LinearLayout.LayoutParams(dp(42), dp(42)).apply { marginEnd = dp(9) })
        val title = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        title.addView(label(name, 15.5f, true).apply { maxLines = 1; ellipsize = TextUtils.TruncateAt.END })
        val clock = java.text.SimpleDateFormat("HH:mm", java.util.Locale.ROOT).format(java.util.Date(message.time))
        title.addView(label("پیام‌یار · ${persianDigits(clock)}", 12f).apply { setTextColor(0xF2FFFFFF.toInt()) })
        header.addView(title, LinearLayout.LayoutParams(0, -2, 1f))
        val toggle = ImageButton(this).apply {
            setImageResource(R.drawable.ic_glass_expand)
            rotation = if (expanded) 180f else 0f
            background = RippleDrawable(ColorStateList.valueOf(0x38FFFFFF), null, GradientDrawable().apply {
                shape = GradientDrawable.OVAL; setColor(Color.WHITE)
            })
            contentDescription = if (expanded) "جمع کردن اعلان" else "نمایش متن کامل"
            setOnClickListener { renderCard(message, pinned = !expanded, expanded = !expanded) }
        }
        header.addView(toggle, LinearLayout.LayoutParams(dp(48), dp(48)))
        layout.addView(header)
        val body = label(if (private) "یک پیام جدید دارید" else message.body, prefs(this).getInt("textSize", 15).toFloat()).apply {
            if (!expanded) { maxLines = 2; ellipsize = TextUtils.TruncateAt.END }
            setPadding(0, dp(6), 0, dp(3))
            setLineSpacing(dp(2).toFloat(), 1f)
        }
        if (!expanded) layout.addView(body)
        layout.setOnClickListener { open(if (private || message.sample) null else message.address) }
        val actions = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        val chips = mutableListOf<View>()
        if (!private && flag("notifyOtpCopy")) Notifier.otp(message.body)?.let { code ->
            chips.add(button("کپی کد ${persianDigits(code)}", R.drawable.ic_glass_copy) {
                getSystemService(ClipboardManager::class.java).setPrimaryClip(ClipData.newPlainText("کد تأیید", code))
                Toast.makeText(this, "کد کپی شد", Toast.LENGTH_SHORT).show()
                dismissCard()
            })
        }
        if (expanded) {
            if (canReplyHere) {
                if (replying) {
                    val input = EditText(this).apply {
                        typeface = cardFont
                        hint = "پاسخ به ${message.name}…"
                        textSize = 15f
                        setTextColor(Color.WHITE)
                        setHintTextColor(0xB8E8F6F0.toInt())
                        inputType = android.text.InputType.TYPE_CLASS_TEXT or
                            android.text.InputType.TYPE_TEXT_FLAG_MULTI_LINE
                        minLines = 1
                        maxLines = 3
                        setSingleLine(false)
                        isFocusableInTouchMode = true
                        setPadding(dp(14), dp(8), dp(14), dp(8))
                        background = android.graphics.drawable.GradientDrawable().apply {
                            cornerRadius = dp(16).toFloat()
                            setColor(0x350B353A)
                            setStroke(dp(1), 0x88B3E7DA.toInt())
                        }
                    }
                    replyField = input
                    actions.addView(input, LinearLayout.LayoutParams(-1, -2))
                    val rawSims = try { SmsCore.subscriptions(this) }
                                  catch (_: RuntimeException) { emptyList() }
                    val active = rawSims.filter { ((it["id"] as? Number)?.toInt() ?: -1) >= 0 }
                    val sims = active.ifEmpty {
                        listOf(mapOf<String, Any>("id" to -1, "label" to "سیم‌کارت پیش‌فرض"))
                    }
                    var selection = 0
                    val chooseSim = button("سیم‌کارت: ${sims.first()["label"]}") { }
                    chooseSim.setOnClickListener {
                        selection = (selection + 1) % sims.size
                        chooseSim.text = "سیم‌کارت: ${sims[selection]["label"]}"
                    }
                    if (sims.size > 1) chips.add(chooseSim)
                    val send = button("ارسال با فرصت لغو ۵ ثانیه") { }
                    send.setOnClickListener {
                        val typed = input.text.toString().trim()
                        if (typed.isBlank() || typed.length > 2000) {
                            Toast.makeText(this, "متن پاسخ باید بین ۱ تا ۲۰۰۰ نویسه باشد", Toast.LENGTH_SHORT).show()
                        } else {
                            try {
                                // The same durable queue and undo window used throughout PayamYar.
                                val id = SmsCore.queue(this, phone, typed,
                                    (sims[selection]["id"] as Number).toInt(), 5000)
                                input.isEnabled = false
                                chooseSim.isEnabled = false
                                send.text = "لغو ارسال (تا ۵ ثانیه)"
                                send.setOnClickListener {
                                    val cancelled = SmsCore.cancel(this, id)
                                    Toast.makeText(this, if (cancelled) "ارسال لغو شد"
                                        else "مهلت لغو تمام شده است", Toast.LENGTH_SHORT).show()
                                    if (cancelled) dismissCard()
                                }
                                main.postDelayed({
                                    if (card != null) {
                                        send.text = "ارسال در شبکه انجام می‌شود"
                                        send.isEnabled = false
                                    }
                                }, 5500)
                            } catch (e: Exception) {
                                Toast.makeText(this, "ارسال ممکن نیست؛ سیم‌کارت و مجوز پیامک را بررسی کنید",
                                    Toast.LENGTH_LONG).show()
                            }
                        }
                    }
                    chips.add(send)
                } else {
                    chips.add(button("پاسخ") {
                        renderCard(message, pinned = true, expanded = true, replying = true)
                    })
                }
            }
            if (!private && !message.sample && SmsCore.isDefault(this)) chips.add(button("خواندم") {
                try {
                    SmsCore.markAddressRead(this, message.address)
                    Notifier.cancel(this, message.address)
                } catch (_: SecurityException) {
                    Toast.makeText(this, "مجوز تغییر وضعیت پیام در دسترس نیست", Toast.LENGTH_SHORT).show()
                }
            })
            if (dialable) {
                chips.add(button("تماس") {
                    val intent = Intent(Intent.ACTION_DIAL, Uri.parse("tel:" + Uri.encode(phone)))
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    try { startActivity(intent) }
                    catch (_: RuntimeException) {
                        Toast.makeText(this, "شماره‌گیر گوشی در دسترس نیست", Toast.LENGTH_SHORT).show()
                    }
                })
            }
            chips.add(button(if (private) "باز کردن برنامه" else "گفتگو") {
                open(if (private || message.sample) null else message.address)
            })
            if (messages.size > 1 && !message.sample) chips.add(button("گفتگوی بعدی (${messages.size})") {
                val list = messages.values.toList()
                val next = list[(list.indexOf(message) + 1).mod(list.size)]
                shown = next
                renderCard(next, pinned = true, expanded = true)
            })
            chips.add(button("بستن") { dismissCard() })
        }
        addActionRows(actions, chips, width - dp(8) - layout.paddingLeft - layout.paddingRight)
        layout.addView(actions)
        if (expanded) layout.addView(body)
        val detector = GestureDetector(this, object : GestureDetector.SimpleOnGestureListener() {
            override fun onDown(e: MotionEvent): Boolean = true
            override fun onFling(e1: MotionEvent?, e2: MotionEvent, velocityX: Float,
                                 velocityY: Float): Boolean {
                if (e1 == null || messages.size < 2 || abs(velocityX) < 450 ||
                    abs(e2.x - e1.x) < dp(70) || abs(velocityY) > abs(velocityX)) return false
                val all = messages.values.toList()
                val i = all.indexOfFirst { it.address == message.address }
                val next = all[(i + (if (velocityX < 0) 1 else all.size - 1)).mod(all.size)]
                main.post { shown = next; renderCard(next, pinned = true, expanded = true) }
                return true
            }
        })
        val scroll = ScrollView(this).apply {
            isFillViewport = false
            isVerticalScrollBarEnabled = expanded
            clipToOutline = true
            background = surface
            elevation = if (reduce) 0f else dp(3).toFloat()
            outlineProvider = ViewOutlineProvider.BACKGROUND
            addView(layout, ViewGroup.LayoutParams(-1, -2))
        }
        val window = object : FrameLayout(this) {
            override fun dispatchTouchEvent(event: MotionEvent): Boolean {
                if (event.actionMasked == MotionEvent.ACTION_DOWN) main.removeCallbacks(hide)
                if (!replying) detector.onTouchEvent(event)
                val handled = super.dispatchTouchEvent(event)
                if (card === this && (event.actionMasked == MotionEvent.ACTION_UP ||
                    event.actionMasked == MotionEvent.ACTION_CANCEL)) {
                    main.removeCallbacks(hide)
                    main.postDelayed(hide, cardTimeout(pinned || replying))
                }
                return handled
            }
        }.apply {
            setPadding(dp(4), dp(2), dp(4), dp(6))
            clipChildren = false
            clipToPadding = false
            addView(scroll, FrameLayout.LayoutParams(-1, -2))
        }
        window.measure(View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(maxHeight, View.MeasureSpec.AT_MOST))
        val p = params(width, NotificationPolicy.cardHeight(bounds.height(), window.measuredHeight), replying)
        p.x = bounds.left + (bounds.width() - width) / 2
        p.y = if (flag("bannerTop")) bounds.top + dp(4) else bounds.bottom - p.height - dp(4)
        return try {
            wm.addView(window, p)
            card = window
            if (expanded && !replying) scroll.post { if (card === window) scroll.scrollTo(0, 0) }
            if (!pinned && !reduce && (Build.VERSION.SDK_INT < 26 || android.animation.ValueAnimator.areAnimatorsEnabled())) {
                scroll.cameraDistance = 1600f * density
                scroll.rotationX = if (flag("bannerTop")) -2.5f else 2.5f
                scroll.alpha = .86f
                scroll.translationY = dp(if (flag("bannerTop")) -4 else 4).toFloat()
                scroll.animate().alpha(1f).translationY(0f).rotationX(0f).setDuration(140L).start()
            }
            if (replying) {
                val field = replyField
                main.postDelayed({
                    if (card === window && field != null) {
                        field.requestFocus()
                        getSystemService(android.view.inputmethod.InputMethodManager::class.java)
                            .showSoftInput(field, android.view.inputmethod.InputMethodManager.SHOW_IMPLICIT)
                    }
                }, 180)
            }
            main.postDelayed(hide, cardTimeout(pinned || replying))
            true
        } catch (_: RuntimeException) { false }
    }
    private fun open(address: String?) {
        dismissCard()
        val intent = Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        if (address != null) intent.setAction("ir.honarmardomi.payamyar.OPEN_CONVERSATION")
            .setData(Uri.parse("payamyar:open/" + Uri.encode(address)))
            .putExtra("open_address", address).putExtra("open_token", MainActivity.launchToken(this))
        try { startActivity(intent) } catch (_: RuntimeException) {
            Toast.makeText(this, "برای مشاهده پیام، پیام‌یار را باز کنید", Toast.LENGTH_SHORT).show()
        }
    }
}
