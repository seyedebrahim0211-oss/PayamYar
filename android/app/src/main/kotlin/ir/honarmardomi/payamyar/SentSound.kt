package ir.honarmardomi.payamyar

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.os.Handler
import android.os.Looper
import java.util.Calendar
import kotlin.math.PI
import kotlin.math.exp
import kotlin.math.sin

/**
 * A short, soft "sent" chime played when the network accepts an SMS — sound only,
 * no notification card. Generated in code (no audio asset), respects silent/vibrate
 * mode and the user's quiet hours.
 */
object SentSound {
    private const val RATE = 44100
    @Volatile private var lastPlay = 0L

    private fun prefs(c: Context) = c.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

    /** 0 = sound only (default), 1 = notification card, 2 = silent. */
    fun mode(c: Context): Int = try {
        prefs(c).getLong("flutter.sentFeedback", 0L).toInt()
    } catch (_: ClassCastException) {
        try { prefs(c).getInt("flutter.sentFeedback", 0) } catch (_: Exception) { 0 }
    }

    private fun intPref(c: Context, key: String, def: Int): Int = try {
        prefs(c).getLong("flutter.$key", def.toLong()).toInt()
    } catch (_: ClassCastException) {
        try { prefs(c).getInt("flutter.$key", def) } catch (_: Exception) { def }
    }

    /** True inside the user's "do not disturb" window (e.g. 23:00–07:00). */
    fun quietNow(c: Context): Boolean {
        if (!prefs(c).getBoolean("flutter.quietHours", false)) return false
        val start = intPref(c, "quietStart", 23 * 60)
        val end = intPref(c, "quietEnd", 7 * 60)
        val now = Calendar.getInstance().let { it.get(Calendar.HOUR_OF_DAY) * 60 + it.get(Calendar.MINUTE) }
        return if (start <= end) now in start until end else now >= start || now < end
    }

    fun play(c: Context) {
        val audio = c.getSystemService(AudioManager::class.java)
        if (audio.ringerMode != AudioManager.RINGER_MODE_NORMAL || quietNow(c)) return
        val now = System.currentTimeMillis()
        if (now - lastPlay < 1200) return // a batch to many recipients plays once
        lastPlay = now
        try {
            val pcm = chime()
            val track = AudioTrack.Builder()
                .setAudioAttributes(AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build())
                .setAudioFormat(AudioFormat.Builder().setSampleRate(RATE)
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO).build())
                .setTransferMode(AudioTrack.MODE_STATIC)
                .setBufferSizeInBytes(pcm.size * 2)
                .build()
            track.write(pcm, 0, pcm.size)
            track.play()
            Handler(Looper.getMainLooper()).postDelayed({ runCatching { track.stop(); track.release() } }, 900)
        } catch (_: Exception) {
            // Audio is a nicety; never break the send receipt.
        }
    }

    /** Rising two-note "whoop" with a soft attack and exponential decay (~330 ms). */
    private fun chime(): ShortArray {
        val notes = listOf(Triple(0.0, 0.13, 987.77), Triple(0.09, 0.24, 1479.98))
        val total = (RATE * 0.34).toInt()
        val out = DoubleArray(total)
        for ((start, length, freq) in notes) {
            val s0 = (start * RATE).toInt()
            val n = (length * RATE).toInt()
            for (i in 0 until n) {
                val t = i.toDouble() / RATE
                val attack = (t / 0.008).coerceAtMost(1.0)
                val env = attack * exp(-t * 14.0)
                val glide = freq * (1 + 0.04 * (1 - exp(-t * 30)))
                val v = env * (sin(2 * PI * glide * t) + 0.25 * sin(4 * PI * glide * t))
                if (s0 + i < total) out[s0 + i] += v
            }
        }
        return ShortArray(total) { (out[it] * 0.32 * Short.MAX_VALUE).toInt().coerceIn(-32767, 32767).toShort() }
    }
}
