package ir.honarmardomi.tamasyar

import android.app.Activity
import android.app.AlertDialog
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.core.content.FileProvider
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest

data class TamasRelease(
    val version: String,
    val code: Long,
    val url: String,
    val sha256: String,
    val notes: String
)

/** Opt-in periodic release checks. No silent installation or upload of call data. */
object TamasUpdater {
    const val PAGE_URL = "https://honarmardomi.ir/tamasyar/"
    private const val API_URL =
        "https://honarmardomi.ir/wp-json/wp/v2/pages?slug=tamasyar-release&_fields=content"
    private const val CHECK_INTERVAL = 12L * 60 * 60 * 1000
    private const val MAX_BYTES = 120L * 1024 * 1024
    private const val CHANNEL_ID = "tamasyar_updates"
    private val main = Handler(Looper.getMainLooper())

    private fun validUrl(input: String, apk: Boolean = false): URL {
        val url = URL(input)
        require(url.protocol == "https" && url.host.equals("honarmardomi.ir", true) &&
            url.port == -1 && url.userInfo == null && url.ref == null) {
            "نشانی انتشار معتبر نیست."
        }
        if (apk) require(url.path.lowercase().endsWith(".apk")) {
            "نشانی فایل APK معتبر نیست."
        }
        return url
    }

    private fun connect(urlString: String): HttpURLConnection {
        var target = urlString
        repeat(4) {
            val url = validUrl(target)
            val c = (url.openConnection() as HttpURLConnection).apply {
                connectTimeout = 12000
                readTimeout = 20000
                instanceFollowRedirects = false
                setRequestProperty("Accept", "application/json, application/octet-stream")
                setRequestProperty("User-Agent", "TamasYar-Android/0.2")
            }
            if (c.responseCode in 300..399) {
                val location = c.getHeaderField("Location")
                c.disconnect()
                require(!location.isNullOrBlank()) { "انتقال نامعتبر از سایت." }
                target = URL(url, location).toString()
            } else {
                require(c.responseCode == 200) {
                    "سایت انتشار پاسخ معتبر نداد (HTTP " + c.responseCode + ")."
                }
                return c
            }
        }
        throw IllegalStateException("تعداد انتقال‌های سایت بیش از حد است.")
    }

    private fun localCode(context: Context): Long {
        @Suppress("DEPRECATION")
        val info = context.packageManager.getPackageInfo(context.packageName, 0)
        @Suppress("DEPRECATION")
        return if (Build.VERSION.SDK_INT >= 28) info.longVersionCode
            else info.versionCode.toLong()
    }

    private fun readRelease(context: Context): TamasRelease? {
        val c = connect(API_URL)
        val response = try {
            c.inputStream.bufferedReader(Charsets.UTF_8).use { reader ->
                // Read only a bounded response; avoid untrusted oversized metadata.
                reader.readText().also { value ->
                    require(value.length < 150000) { "پاسخ انتشار بیش از حد بزرگ است." }
                }
            }
        } finally {
            c.disconnect()
        }
        val pages = JSONArray(response)
        if (pages.length() == 0) return null
        val html = pages.getJSONObject(0).getJSONObject("content").getString("rendered")
        val match = Regex("<pre[^>]*>([\\s\\S]*?)</pre>",
            RegexOption.IGNORE_CASE).find(html) ?: return null
        val raw = android.text.Html.fromHtml(match.groupValues[1],
            android.text.Html.FROM_HTML_MODE_LEGACY).toString().trim()
        val data = JSONObject(raw)
        if (!data.optBoolean("published", false)) return null
        val url = data.optString("android_url", "")
        validUrl(url, apk = true)
        val code = data.optLong("version_code", 0)
        val digest = data.optString("sha256", "").lowercase()
        require(digest.matches(Regex("[0-9a-f]{64}"))) {
            "اثر انگشت SHA-256 نسخه منتشرشده معتبر نیست."
        }
        if (code <= localCode(context)) return null
        return TamasRelease(
            version = data.optString("version", "?").take(40),
            code = code,
            url = url,
            sha256 = digest,
            notes = data.optString("notes", "").take(1200)
        )
    }

    fun check(context: Context, automatic: Boolean = false,
        callback: (TamasRelease?, String?) -> Unit
    ) {
        if (automatic) {
            val prefs = TamasPreferences(context)
            if (!prefs.autoUpdates) return
            val now = System.currentTimeMillis()
            if (now - prefs.lastChecked < CHECK_INTERVAL) return
            prefs.lastChecked = now
        }
        val app = context.applicationContext
        Thread {
            try {
                val release = readRelease(app)
                if (automatic && release != null) alert(app, release)
                main.post {
                    callback(release, if (release == null) "نسخه جدیدی برای انتشار عمومی موجود نیست." else null)
                }
            } catch (e: Exception) {
                main.post {
                    callback(null, "بررسی نسخه انجام نشد: " + (e.message ?: "خطای ارتباطی"))
                }
            }
        }.start()
    }

    /** Synchronous worker entry point; called only by WorkManager off the UI thread. */
    internal fun backgroundCheck(context: Context): Boolean {
        if (!TamasPreferences(context).autoUpdates) return true
        return try {
            val release = readRelease(context)
            TamasPreferences(context).lastChecked = System.currentTimeMillis()
            if (release != null) alert(context, release)
            true
        } catch (_: Exception) { false }
    }

    private fun alert(context: Context, release: TamasRelease) {
        val prefs = TamasPreferences(context)
        if (prefs.lastNotifiedCode >= release.code) return
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) {
            nm.createNotificationChannel(NotificationChannel(CHANNEL_ID,
                "به‌روزرسانی تماس‌یار", NotificationManager.IMPORTANCE_DEFAULT))
        }
        val intent = Intent(context, MainActivity::class.java).apply {
            putExtra("open_updates", true)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pending = PendingIntent.getActivity(context, 512, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= 26)
            Notification.Builder(context, CHANNEL_ID) else Notification.Builder(context)
        val notification = builder
            .setSmallIcon(android.R.drawable.stat_sys_download_done)
            .setContentTitle("نسخه جدید تماس‌یار " + release.version)
            .setContentText("برای بررسی و نصب به‌روزرسانی لمس کنید.")
            .setContentIntent(pending)
            .setAutoCancel(true)
            .build()
        try {
            nm.notify(512, notification)
            prefs.lastNotifiedCode = release.code
        } catch (_: SecurityException) { /* notification permission not granted */ }
    }

    fun confirmInstall(activity: Activity, release: TamasRelease,
        callback: (String) -> Unit
    ) {
        AlertDialog.Builder(activity)
            .setTitle("به‌روزرسانی تماس‌یار " + release.version)
            .setMessage("نسخه جدید از سایت رسمی هنر مردمی دریافت می‌شود. " +
                "اثر انگشت فایل پیش از نصب بررسی خواهد شد. " +
                "نصب تنها با تأیید شما انجام می‌شود.\n\n" + release.notes)
            .setNegativeButton("انصراف", null)
            .setPositiveButton("دریافت و نصب") { _, _ ->
                download(activity, release, callback)
            }.show()
    }

    private fun download(activity: Activity, release: TamasRelease,
        callback: (String) -> Unit
    ) {
        callback("در حال دریافت نسخه " + release.version + "…")
        Thread {
            val directory = File(activity.cacheDir, "verified-updates").apply { mkdirs() }
            val staging = File(directory, "incoming.tmp")
            try {
                val source = connect(release.url)
                val digest = MessageDigest.getInstance("SHA-256")
                var total = 0L
                source.inputStream.use { input ->
                    FileOutputStream(staging).use { output ->
                        val buffer = ByteArray(32768)
                        while (true) {
                            val length = input.read(buffer)
                            if (length == -1) break
                            total += length
                            require(total <= MAX_BYTES) { "فایل بیش از اندازه مجاز است." }
                            digest.update(buffer, 0, length)
                            output.write(buffer, 0, length)
                        }
                    }
                }
                source.disconnect()
                val actual = digest.digest().joinToString("") {
                    "%02x".format(it.toInt() and 0xff)
                }
                require(actual.equals(release.sha256, true)) { "اثر انگشت فایل مطابقت ندارد." }
                @Suppress("DEPRECATION")
                val apk = activity.packageManager.getPackageArchiveInfo(staging.absolutePath, 0)
                    ?: error("فایل APK قابل شناسایی نیست.")
                require(apk.packageName == activity.packageName) {
                    "شناسه برنامه با تماس‌یار تطابق ندارد."
                }
                @Suppress("DEPRECATION")
                val apkCode = if (Build.VERSION.SDK_INT >= 28) apk.longVersionCode
                    else apk.versionCode.toLong()
                require(apkCode == release.code) { "کد نسخه فایل با اطلاعات سایت یکسان نیست." }
                val file = File(directory, "TamasYar-" + release.code + ".apk")
                require(staging.renameTo(file)) { "ثبت فایل دریافت‌شده انجام نشد." }
                main.post {
                    callback("فایل معتبر است؛ در حال بازکردن نصب‌کننده اندروید.")
                    install(activity, file)
                }
            } catch (e: Exception) {
                staging.delete()
                main.post { callback("دانلود انجام نشد: " + (e.message ?: "خطا")) }
            }
        }.start()
    }

    private fun install(activity: Activity, file: File) {
        if (Build.VERSION.SDK_INT >= 26 &&
            !activity.packageManager.canRequestPackageInstalls()) {
            TamasPreferences(activity).pendingApk = file.absolutePath
            AlertDialog.Builder(activity)
                .setTitle("اجازه نصب نسخه جدید")
                .setMessage("برای نصب مستقیم نسخه‌های تأییدشده از سایت، " +
                    "اجازه «نصب از این منبع» را در تنظیمات اندروید فعال کنید.")
                .setPositiveButton("تنظیمات") { _, _ ->
                    activity.startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                        Uri.parse("package:" + activity.packageName)))
                }
                .setNegativeButton("بعداً", null).show()
            return
        }
        try {
            val uri = FileProvider.getUriForFile(activity,
                activity.packageName + ".updates", file)
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                flags = Intent.FLAG_GRANT_READ_URI_PERMISSION
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            activity.startActivity(intent)
            TamasPreferences(activity).pendingApk = ""
        } catch (e: Exception) {
            AlertDialog.Builder(activity).setTitle("نصب انجام نشد")
                .setMessage(e.message ?: "خطا در نصب نسخه")
                .setPositiveButton("باشه", null).show()
        }
    }

    fun resumePendingInstall(activity: Activity) {
        val prefs = TamasPreferences(activity)
        val path = prefs.pendingApk
        if (path.isBlank()) return
        val file = File(path)
        if (!file.exists() || file.parentFile?.canonicalFile !=
            File(activity.cacheDir, "verified-updates").canonicalFile) {
            prefs.pendingApk = ""
            return
        }
        if (Build.VERSION.SDK_INT < 26 || activity.packageManager.canRequestPackageInstalls()) {
            prefs.pendingApk = ""
            install(activity, file)
        }
    }
}
