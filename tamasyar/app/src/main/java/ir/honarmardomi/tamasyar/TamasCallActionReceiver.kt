package ir.honarmardomi.tamasyar

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.telecom.Call
import android.telecom.VideoProfile

/** Private explicit actions for the Android Telecom notification controls. */
class TamasCallActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val call = LiveCalls.current() ?: return
        try {
            when (intent.action) {
                ANSWER -> if (call.state == Call.STATE_RINGING)
                    call.answer(VideoProfile.STATE_AUDIO_ONLY)
                DECLINE -> if (call.state == Call.STATE_RINGING)
                    call.reject(false, null)
                HANGUP -> if (call.state != Call.STATE_DISCONNECTED)
                    call.disconnect()
            }
        } catch (_: Exception) {
            // Telecom may already have disconnected the call.
        }
    }

    companion object {
        const val ANSWER = "ir.honarmardomi.tamasyar.action.ANSWER"
        const val DECLINE = "ir.honarmardomi.tamasyar.action.DECLINE"
        const val HANGUP = "ir.honarmardomi.tamasyar.action.HANGUP"
    }
}
