package ir.honarmardomi.tamasyar

import android.Manifest
import android.app.Activity
import android.app.AlertDialog
import android.widget.Toast
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.ContactsContract
import java.util.Locale
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.telecom.Call
import android.telecom.CallAudioState
import android.telecom.VideoProfile
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.TextView

/** Incoming and ongoing call UI. Works only when user grants default dialer role. */
class CallScreenActivity : Activity() {
    private val dark = TamasStyle.tealDeep
    private val gold = TamasStyle.goldLight
    private val handler = Handler(Looper.getMainLooper())
    private val observer: () -> Unit = { if (!isFinishing) draw() }
    private val recordingObserver: () -> Unit = { runOnUiThread {
        if (!isFinishing && !isDestroyed) draw()
    } }
    private val callerNames = mutableMapOf<String, String>()
    private val pendingNames = mutableSetOf<String>()
    private var durationView: TextView? = null
    private val ticker = object : Runnable {
        override fun run() {
            val call = LiveCalls.current()
            if (call != null && call.state == Call.STATE_ACTIVE) {
                val connected = call.details.connectTimeMillis
                if (connected > 0) {
                    val seconds = ((System.currentTimeMillis() - connected) / 1000).coerceAtLeast(0)
                    durationView?.text = String.format(Locale.US, "%02d:%02d",
                        seconds / 60, seconds % 60)
                }
            }
            handler.postDelayed(this, 1000)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.statusBarColor = dark
        window.navigationBarColor = dark
        if (Build.VERSION.SDK_INT >= 27) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON)
        }
        draw()
    }
    override fun onResume() {
        super.onResume()
        LiveCalls.subscribe(observer)
        TamasRecordings.subscribe(recordingObserver)
        draw()
        handler.post(ticker)
    }
    override fun onPause() {
        handler.removeCallbacks(ticker)
        LiveCalls.unsubscribe(observer)
        TamasRecordings.unsubscribe(recordingObserver)
        super.onPause()
    }
    private fun dp(n: Int) = (n * resources.displayMetrics.density).toInt()
    private fun label(value: String, size: Float, color: Int = Color.WHITE): TextView =
        TextView(this).apply {
            text = value
            textSize = size
            setTextColor(color)
            gravity = Gravity.CENTER
            setPadding(dp(8), dp(12), dp(8), dp(12))
            typeface = Typeface.create(TamasStyle.font(this@CallScreenActivity), Typeface.BOLD)
        }
    private fun button(value: String, bg: Int, click: () -> Unit): TextView =
        label(value, 16f).apply {
            background = GradientDrawable().apply {
                setColor(bg)
                cornerRadius = dp(20).toFloat()
            }
            setOnClickListener { click() }
        }

    private fun draw() {
        val call = LiveCalls.current()
        if (call == null || call.state == Call.STATE_DISCONNECTED) { finish(); return }
        val incoming = call.state == Call.STATE_RINGING
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            layoutDirection = View.LAYOUT_DIRECTION_RTL
            gravity = Gravity.CENTER
            setBackgroundColor(dark)
            setPadding(dp(20), dp(32), dp(20), dp(26))
        }
        root.addView(label("تماس‌یار", 18f, gold))
        val status = when {
            incoming -> "تماس ورودی"
            call.state == Call.STATE_ACTIVE -> "تماس برقرار است"
            call.state == Call.STATE_HOLDING -> "تماس در انتظار"
            else -> "در حال برقراری تماس…"
        }
        root.addView(label(status, 20f))
        val number = call.details.handle?.schemeSpecificPart.orEmpty()
        if (number.isNotBlank()) lookupCaller(number)
        val name = callerNames[number]
        if (!name.isNullOrBlank()) {
            root.addView(label(name, 27f))
            root.addView(label(number, 17f, Color.rgb(193, 218, 212)))
        } else {
            root.addView(label(if (number.isBlank()) "شماره ناشناس" else number, 27f))
        }
        durationView = label("", 19f, gold).also { root.addView(it) }
        root.addView(View(this), LinearLayout.LayoutParams(1, 0, 1f))
        if (incoming) {
            root.addView(button("پاسخ  ✓", Color.rgb(35, 142, 106)) {
                try { call.answer(VideoProfile.STATE_AUDIO_ONLY) } catch (_: Exception) { }
            }, LinearLayout.LayoutParams(-1, dp(64)).apply { bottomMargin = dp(14) })
            root.addView(button("رد تماس", Color.rgb(171, 51, 69)) {
                try { call.reject(false, null) } catch (_: Exception) { }
            }, LinearLayout.LayoutParams(-1, dp(64)))
        } else {
            val service = LiveCalls.service
            val controls = LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                layoutDirection = View.LAYOUT_DIRECTION_RTL
            }
            val muted = service?.callAudioState?.isMuted == true
            controls.addView(button(if (muted) "با صدا" else "بی‌صدا", Color.rgb(50, 87, 92)) {
                service?.setMuted(!muted)
                handler.postDelayed({ draw() }, 120)
            }, LinearLayout.LayoutParams(0, dp(64), 1f).apply { marginEnd = dp(5) })
            @Suppress("DEPRECATION")
            val speaker = service?.callAudioState?.route == CallAudioState.ROUTE_SPEAKER
            controls.addView(button(if (speaker) "گوشی" else "بلندگو", Color.rgb(50, 87, 92)) {
                @Suppress("DEPRECATION")
                service?.setAudioRoute(if (speaker) CallAudioState.ROUTE_EARPIECE
                    else CallAudioState.ROUTE_SPEAKER)
                handler.postDelayed({ draw() }, 120)
            }, LinearLayout.LayoutParams(0, dp(64), 1f).apply { marginStart = dp(5) })
            root.addView(controls)
            if (call.state == Call.STATE_ACTIVE || TamasRecordings.active) {
                root.addView(button(
                    if (TamasRecordings.active) "● توقف ضبط میکروفون"
                    else "● ضبط دستی میکروفون",
                    if (TamasRecordings.active) Color.rgb(163, 52, 68)
                    else TamasStyle.teal
                ) {
                    if (TamasRecordings.active) TamasRecordings.stop(this)
                    else askRecordingPermissionAndConsent()
                }, LinearLayout.LayoutParams(-1, dp(62)).apply {
                    topMargin = dp(12)
                })
                root.addView(label(
                    if (TamasRecordings.active) "ضبط روشن است · فقط صدایی که میکروفون دستگاه دریافت می‌کند."
                    else "ضبط فقط با تأیید شما؛ صدای طرف مقابل ممکن است ضبط نشود.",
                    12f, Color.rgb(204, 223, 222)
                ))
            }
            if (TamasRecordings.lastError.isNotBlank()) {
                root.addView(label(TamasRecordings.lastError, 12f, gold))
            }
            root.addView(button("شماره‌گیر حین تماس", Color.rgb(50, 87, 92)) {
                showDtmf(call)
            }, LinearLayout.LayoutParams(-1, dp(62)).apply { topMargin = dp(12) })
            val holding = call.state == Call.STATE_HOLDING
            if (holding || (call.details.callCapabilities and Call.Details.CAPABILITY_HOLD) != 0) {
                root.addView(button(if (holding) "ادامه تماس" else "انتظار تماس",
                    Color.rgb(50, 87, 92)) {
                    try { if (holding) call.unhold() else call.hold() } catch (_: Exception) { }
                }, LinearLayout.LayoutParams(-1, dp(62)).apply { topMargin = dp(12) })
            }
            root.addView(button("پایان تماس", Color.rgb(171, 51, 69)) {
                try { call.disconnect() } catch (_: Exception) { }
            }, LinearLayout.LayoutParams(-1, dp(68)).apply { topMargin = dp(16) })
        }
        setContentView(root)
    }

    /** Local caller ID; never sends the phone number to a remote service. */
    private fun lookupCaller(number: String) {
        if (number in callerNames || number in pendingNames ||
            checkSelfPermission(Manifest.permission.READ_CONTACTS) !=
                PackageManager.PERMISSION_GRANTED) return
        pendingNames.add(number)
        Thread {
            var resolved: String? = null
            try {
                val uri = Uri.withAppendedPath(ContactsContract.PhoneLookup.CONTENT_FILTER_URI,
                    Uri.encode(number))
                contentResolver.query(uri,
                    arrayOf(ContactsContract.PhoneLookup.DISPLAY_NAME),
                    null, null, null)?.use { c ->
                    if (c.moveToFirst()) resolved = c.getString(0)
                }
            } catch (_: Exception) { /* caller ID is optional */ }
            runOnUiThread {
                pendingNames.remove(number)
                callerNames[number] = resolved.orEmpty()
                if (!isFinishing && !isDestroyed &&
                    LiveCalls.current()?.details?.handle?.schemeSpecificPart == number) draw()
            }
        }.start()
    }

    private fun askRecordingPermissionAndConsent() {
        if (LiveCalls.current()?.state != Call.STATE_ACTIVE) {
            Toast.makeText(this, "ضبط فقط در تماس فعال قابل شروع است.", Toast.LENGTH_LONG).show()
            return
        }
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) !=
            PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), 420)
            return
        }
        AlertDialog.Builder(this)
            .setTitle("ضبط دستی با میکروفون")
            .setMessage(
                "این ابزار فقط ورودی میکروفون را ذخیره می‌کند. اندروید دسترسی عمومی " +
                "به صدای تماس دوطرفه را نمی‌دهد؛ بنابراین صدای طرف مقابل ممکن است در فایل نباشد.\n\n" +
                "پیش از ضبط، رضایت افراد مکالمه را کسب کنید. ضبط به‌صورت مخفی یا خودکار " +
                "انجام نمی‌شود و با قطع تماس متوقف می‌شود. فایل روی همین گوشی باقی می‌ماند."
            )
            .setNegativeButton("انصراف", null)
            .setPositiveButton("شروع ضبط") { _, _ ->
                try {
                    TamasRecordings.start(this)
                } catch (_: Exception) {
                    Toast.makeText(this,
                        "ضبط ممکن نشد. مجوز میکروفون و محدودیت باتری را بررسی کنید.",
                        Toast.LENGTH_LONG).show()
                }
            }
            .show()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int, permissions: Array<out String>, grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 420) {
            if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
                askRecordingPermissionAndConsent()
            } else Toast.makeText(this,
                "بدون دسترسی به میکروفون امکان ضبط وجود ندارد.",
                Toast.LENGTH_LONG).show()
        }
    }

    private fun showDtmf(call: Call) {
        val layout = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        TamasPhone.KEYPAD_ROWS.forEach { digits ->
            val row = LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                layoutDirection = View.LAYOUT_DIRECTION_LTR
            }
            digits.forEach { digit ->
                val cell = label(digit, 23f, dark)
                cell.setOnClickListener {
                    try {
                        call.playDtmfTone(digit[0])
                        handler.postDelayed({ try { call.stopDtmfTone() } catch (_: Exception) { } }, 160)
                    } catch (_: Exception) { }
                }
                row.addView(cell, LinearLayout.LayoutParams(0, dp(62), 1f))
            }
            layout.addView(row)
        }
        android.app.AlertDialog.Builder(this).setTitle("صفحه کلید تماس")
            .setView(layout).setPositiveButton("بستن", null).show()
    }
}
