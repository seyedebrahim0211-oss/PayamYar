package ir.honarmardomi.tamasyar

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.media.MediaRecorder
import android.os.Build
import android.os.Environment
import android.os.IBinder
import android.telecom.Call
import android.util.Log
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.CopyOnWriteArraySet

/**
 * Explicit user-initiated microphone-only recording.
 * This CANNOT capture privileged telephony uplink/downlink audio.
 * No auto-record, background microphone start or Accessibility abuse.
 */
object TamasRecordings {
    private val observers = CopyOnWriteArraySet<() -> Unit>()
    @Volatile var active: Boolean = false
        private set
    @Volatile var lastError: String = ""
        private set
    @Volatile var currentFilename: String = ""
        private set

    internal fun started(file: File) {
        currentFilename = file.name
        active = true
        lastError = ""
        notifyObservers()
    }
    internal fun stopped() {
        active = false
        currentFilename = ""
        notifyObservers()
    }
    internal fun failed(message: String) {
        active = false
        currentFilename = ""
        lastError = message
        notifyObservers()
    }
    fun subscribe(callback: () -> Unit) { observers.add(callback) }
    fun unsubscribe(callback: () -> Unit) { observers.remove(callback) }
    private fun notifyObservers() {
        observers.forEach { try { it() } catch (_: Exception) { } }
    }
    fun folder(context: Context): File = File(context.filesDir, "recordings").apply { mkdirs() }
    fun list(context: Context): List<File> =
        folder(context).listFiles()?.filter { it.isFile && it.extension == "m4a" }
            ?.sortedByDescending { it.lastModified() }.orEmpty()
    fun start(context: Context) {
        val intent = Intent(context, TamasRecordingService::class.java)
            .setAction(TamasRecordingService.ACTION_START)
        if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(intent)
        else context.startService(intent)
    }
    fun stop(context: Context) {
        context.startService(Intent(context, TamasRecordingService::class.java)
            .setAction(TamasRecordingService.ACTION_STOP))
    }
}

class TamasRecordingService : Service() {
    companion object {
        const val ACTION_START = "ir.honarmardomi.tamasyar.recorder.START"
        const val ACTION_STOP = "ir.honarmardomi.tamasyar.recorder.STOP"
        private const val CHANNEL = "tamasyar_recording"
        private const val ID = 6819
        private const val TAG = "TamasRecorder"
    }

    private var recorder: MediaRecorder? = null
    private var file: File? = null
    private var listening = false
    private val callObserver: () -> Unit = {
        if (TamasRecordings.active && LiveCalls.current()?.state != Call.STATE_ACTIVE) {
            stopRecording()
            stopSelf()
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> { stopRecording(); stopSelf() }
            ACTION_START -> {
                if (recorder != null) return START_NOT_STICKY
                if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) !=
                    PackageManager.PERMISSION_GRANTED ||
                    LiveCalls.current()?.state != Call.STATE_ACTIVE) {
                    TamasRecordings.failed("ضبط تنها هنگام تماس فعال و با مجوز میکروفون ممکن است.")
                    stopSelf()
                    return START_NOT_STICKY
                }
                try {
                    startRecording()
                } catch (e: Exception) {
                    Log.w(TAG, "Recording start failed", e)
                    TamasRecordings.failed("میکروفون در دسترس نیست یا اندروید هنگام تماس ضبط را محدود کرده است.")
                    stopRecording()
                    stopSelf()
                }
            }
            else -> stopSelf()
        }
        return START_NOT_STICKY
    }

    private fun notification(): Notification {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(NotificationChannel(CHANNEL,
                "ضبط دستی تماس‌یار", NotificationManager.IMPORTANCE_LOW).apply {
                description = "نشانگر دائمی ضبط دستی از میکروفون"
                setSound(null, null)
                enableVibration(false)
                lockscreenVisibility = Notification.VISIBILITY_PRIVATE
            })
        }
        val open = PendingIntent.getActivity(this, 281,
            Intent(this, CallScreenActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            }, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val stop = PendingIntent.getService(this, 282,
            Intent(this, TamasRecordingService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= 26)
            Notification.Builder(this, CHANNEL) else Notification.Builder(this)
        return builder
            .setSmallIcon(android.R.drawable.presence_audio_online)
            .setContentTitle("ضبط میکروفون تماس‌یار فعال است")
            .setContentText("ممکن است صدای طرف مقابل ضبط نشود. برای توقف لمس کنید.")
            .setContentIntent(open)
            .addAction(android.R.drawable.ic_media_pause, "توقف ضبط", stop)
            .setOngoing(true)
            .setCategory(Notification.CATEGORY_SERVICE)
            .build()
    }

    private fun startRecording() {
        val notice = notification()
        if (Build.VERSION.SDK_INT >= 30) {
            startForeground(ID, notice, ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
        } else {
            startForeground(ID, notice)
        }
        val stamp = SimpleDateFormat("yyyyMMdd-HHmmss-SSS", Locale.US).format(Date())
        val target = File(TamasRecordings.folder(this), "TamasYar-" + stamp + ".m4a")
        @Suppress("DEPRECATION")
        val media = if (Build.VERSION.SDK_INT >= 31) MediaRecorder(this)
            else MediaRecorder()
        try {
            media.setAudioSource(MediaRecorder.AudioSource.MIC)
            media.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            media.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            media.setAudioEncodingBitRate(64000)
            media.setAudioSamplingRate(44100)
            media.setOutputFile(target.absolutePath)
            media.prepare()
            media.start()
            recorder = media
            file = target
            TamasRecordings.started(target)
            if (!listening) { LiveCalls.subscribe(callObserver); listening = true }
        } catch (e: Exception) {
            media.release()
            target.delete()
            throw e
        }
    }

    private fun stopRecording() {
        if (listening) { LiveCalls.unsubscribe(callObserver); listening = false }
        val media = recorder
        recorder = null
        val output = file
        file = null
        if (media != null) {
            var valid = true
            try { media.stop() } catch (_: RuntimeException) { valid = false }
            try { media.reset(); media.release() } catch (_: Exception) { }
            if (!valid || output == null || !output.exists() || output.length() < 512) {
                output?.delete()
                TamasRecordings.failed("ضبط قابل استفاده‌ای ذخیره نشد؛ محدودیت میکروفون دستگاه را بررسی کنید.")
            } else TamasRecordings.stopped()
        } else TamasRecordings.stopped()
        @Suppress("DEPRECATION")
        if (Build.VERSION.SDK_INT >= 24) stopForeground(STOP_FOREGROUND_REMOVE)
        else stopForeground(true)
    }

    override fun onDestroy() {
        stopRecording()
        super.onDestroy()
    }
}
