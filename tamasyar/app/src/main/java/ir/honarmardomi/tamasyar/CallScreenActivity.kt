package ir.honarmardomi.tamasyar

import android.app.Activity
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
    override fun onResume() { super.onResume(); LiveCalls.subscribe(observer); draw() }
    override fun onPause() { LiveCalls.unsubscribe(observer); super.onPause() }
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
        root.addView(label(call.details.handle?.schemeSpecificPart ?: "شماره ناشناس", 27f))
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

    private fun showDtmf(call: Call) {
        val layout = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        listOf(listOf("1", "2", "3"), listOf("4", "5", "6"),
            listOf("7", "8", "9"), listOf("*", "0", "#")).forEach { digits ->
            val row = LinearLayout(this)
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
