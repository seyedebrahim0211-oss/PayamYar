package ir.honarmardomi.tamasyar

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Person
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.telecom.Call
import android.telecom.InCallService
import android.telecom.CallAudioState
import java.util.concurrent.CopyOnWriteArraySet

/** All calls stay in Telecom on this device; no call data is sent to PayamYar. */
object LiveCalls {
    private val handler = Handler(Looper.getMainLooper())
    private val calls = mutableListOf<Call>()
    private val observers = CopyOnWriteArraySet<() -> Unit>()
    var service: TamasInCallService? = null
        private set
    private val callback = object : Call.Callback() {
        override fun onStateChanged(call: Call, state: Int) {
            publish()
            service?.let { CallAlert.update(it, current()) }
        }
        override fun onDetailsChanged(call: Call, details: Call.Details) {
            publish()
            service?.let { CallAlert.update(it, current()) }
        }
    }
    fun refresh() { publish() }
    fun subscribe(observer: () -> Unit) { observers.add(observer) }
    fun unsubscribe(observer: () -> Unit) { observers.remove(observer) }
    fun current(): Call? =
        calls.firstOrNull { it.state == Call.STATE_RINGING } ?:
        calls.firstOrNull { it.state != Call.STATE_DISCONNECTED }
    fun connect(instance: TamasInCallService) { service = instance; publish() }
    fun disconnect(instance: TamasInCallService) {
        if (service === instance) service = null
        publish()
    }
    fun add(call: Call) {
        if (!calls.contains(call)) {
            calls.add(call)
            call.registerCallback(callback)
        }
        publish()
        service?.let { CallAlert.update(it, current()) }
    }
    fun remove(call: Call) {
        call.unregisterCallback(callback)
        calls.remove(call)
        publish()
        service?.let { CallAlert.update(it, current()) }
    }
    private fun publish() {
        handler.post {
            observers.forEach { observer ->
                try { observer() } catch (_: Exception) { /* activity might be closing */ }
            }
        }
    }
}

class TamasInCallService : InCallService() {
    override fun onCreate() { super.onCreate(); LiveCalls.connect(this) }
    override fun onCallAdded(call: Call) { super.onCallAdded(call); LiveCalls.add(call) }
    override fun onCallRemoved(call: Call) { LiveCalls.remove(call); super.onCallRemoved(call) }
    override fun onCallAudioStateChanged(audioState: CallAudioState) {
        super.onCallAudioStateChanged(audioState)
        LiveCalls.refresh()
    }
    override fun onBringToForeground(showDialpad: Boolean) {
        super.onBringToForeground(showDialpad)
        if (LiveCalls.current() != null) {
            startActivity(Intent(this, CallScreenActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                putExtra("show_keypad", showDialpad)
            })
        }
    }
    override fun onDestroy() {
        CallAlert.update(this, null)
        LiveCalls.disconnect(this)
        super.onDestroy()
    }
}

object CallAlert {
    private const val CHANNEL = "tamasyar_calls"
    private const val ID = 4331
    fun update(context: Context, call: Call?) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (call == null || call.state == Call.STATE_DISCONNECTED) {
            manager.cancel(ID)
            return
        }
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(NotificationChannel(CHANNEL,
                "تماس‌های تلفنی", NotificationManager.IMPORTANCE_HIGH).apply {
                lockscreenVisibility = Notification.VISIBILITY_PRIVATE
            })
        }
        val incoming = call.state == Call.STATE_RINGING
        val open = Intent(context, CallScreenActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val pending = PendingIntent.getActivity(context, 0, open,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        fun callAction(action: String, request: Int): PendingIntent =
            PendingIntent.getBroadcast(context, request,
                Intent(context, TamasCallActionReceiver::class.java).setAction(action),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

        val answer = callAction(TamasCallActionReceiver.ANSWER, 431)
        val decline = callAction(TamasCallActionReceiver.DECLINE, 432)
        val hangup = callAction(TamasCallActionReceiver.HANGUP, 433)
        val builder = if (Build.VERSION.SDK_INT >= 26)
            Notification.Builder(context, CHANNEL) else Notification.Builder(context)
        builder.setSmallIcon(android.R.drawable.sym_action_call)
            .setContentTitle(if (incoming) "تماس ورودی" else "تماس جاری")
            .setContentText("برای مدیریت تماس لمس کنید")
            .setContentIntent(pending)
            .setCategory(Notification.CATEGORY_CALL)
            .setPriority(Notification.PRIORITY_HIGH)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .setOngoing(true)
        if (Build.VERSION.SDK_INT >= 31) {
            val caller = Person.Builder()
                .setName("تماس تلفنی")
                .setImportant(true)
                .build()
            builder.setStyle(if (incoming)
                Notification.CallStyle.forIncomingCall(caller, decline, answer)
                else Notification.CallStyle.forOngoingCall(caller, hangup))
        } else {
            if (incoming) {
                builder.addAction(android.R.drawable.ic_menu_call, "پاسخ", answer)
                builder.addAction(android.R.drawable.ic_menu_close_clear_cancel, "رد", decline)
            } else {
                builder.addAction(android.R.drawable.ic_menu_close_clear_cancel, "قطع تماس", hangup)
            }
        }
        if (incoming) builder.setFullScreenIntent(pending, true)
        val notification = builder.build()
        try { manager.notify(ID, notification) } catch (_: SecurityException) { }
    }
}
