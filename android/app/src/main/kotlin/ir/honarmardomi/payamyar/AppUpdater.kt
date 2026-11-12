package ir.honarmardomi.payamyar

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.util.zip.ZipFile

/**
 * Downloads a new PayamYar release from honarmardomi.ir and hands it to Android's installer.
 * Accepts a direct .apk or a .zip that contains the .apk (WordPress accepts .zip uploads).
 * Android itself refuses an APK signed with a different key, so only genuine updates install.
 */
object AppUpdater {
    private const val HOST = "honarmardomi.ir"
    private const val MAX_APK_BYTES = 140L * 1024 * 1024

    fun canInstall(activity: Activity): Boolean =
        Build.VERSION.SDK_INT < 26 || activity.packageManager.canRequestPackageInstalls()

    fun openInstallPermission(activity: Activity) {
        if (Build.VERSION.SDK_INT >= 26) {
            activity.startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:${activity.packageName}")))
        }
    }

    /** Blocking; call on a worker thread. Returns the ready-to-install APK file. */
    fun download(activity: Activity, url: String, progress: (Int) -> Unit): File {
        val uri = Uri.parse(url)
        require(uri.scheme == "https" && (uri.host == HOST || uri.host == "www.$HOST")) { "نشانی به‌روزرسانی معتبر نیست." }
        val dir = File(activity.cacheDir, "updates").apply { mkdirs() }
        dir.listFiles()?.forEach { it.delete() }
        val download = File(dir, "download.tmp")
        var connection: HttpURLConnection? = null
        try {
            connection = (URL(url).openConnection() as HttpURLConnection).apply {
                connectTimeout = 15000
                readTimeout = 30000
                instanceFollowRedirects = true
            }
            check(connection.responseCode == 200) { "دریافت فایل انجام نشد (${connection.responseCode})." }
            val total = connection.contentLengthLong
            check(total <= MAX_APK_BYTES) { "حجم فایل به‌روزرسانی بیش از حد مجاز است." }
            val finalUrl = connection.url
            check(finalUrl.protocol == "https" &&
                (finalUrl.host == HOST || finalUrl.host == "www.$HOST")) {
                "فایل به‌روزرسانی از نشانی غیرمجاز هدایت شده است."
            }
            connection.inputStream.use { input ->
                download.outputStream().use { output ->
                    val buffer = ByteArray(64 * 1024)
                    var done = 0L
                    var last = -1
                    while (true) {
                        val n = input.read(buffer)
                        if (n < 0) break
                        output.write(buffer, 0, n)
                        done += n
                        check(done <= MAX_APK_BYTES) { "حجم فایل به‌روزرسانی بیش از حد مجاز است." }
                        if (total > 0) {
                            val p = (done * 100 / total).toInt()
                            if (p != last) { last = p; progress(p) }
                        }
                    }
                }
            }
        } finally {
            connection?.disconnect()
        }
        val apk = File(dir, "PayamYar-update.apk")
        ZipFile(download).use { zip ->
            if (zip.getEntry("AndroidManifest.xml") != null) {
                // The download is the APK itself.
                check(download.renameTo(apk)) { "ذخیره فایل نصبی ممکن نشد." }
            } else {
                val entry = zip.entries().asSequence().firstOrNull { !it.isDirectory && it.name.endsWith(".apk", true) }
                    ?: throw IllegalStateException("فایل نصبی داخل بسته پیدا نشد.")
                check(entry.size in 1L..MAX_APK_BYTES) { "حجم فایل نصبی داخل بسته معتبر نیست." }
                zip.getInputStream(entry).use { input ->
                    apk.outputStream().use { output ->
                        val buffer = ByteArray(64 * 1024)
                        var extracted = 0L
                        while (true) {
                            val n = input.read(buffer)
                            if (n < 0) break
                            extracted += n
                            check(extracted <= MAX_APK_BYTES) { "حجم فایل نصبی از حد مجاز بیشتر است." }
                            output.write(buffer, 0, n)
                        }
                    }
                }
            }
        }
        download.delete()
        return apk
    }

    /**
     * Android rejects upgrades signed with a different certificate. Detect the mismatch
     * before opening Package Installer, so users do not uninstall an app with local drafts.
     * This cannot repair a lost legacy signing key.
     */
    @Suppress("DEPRECATION")
    fun validateUpgrade(activity: Activity, apk: File) {
        val pm = activity.packageManager
        val flags = if (Build.VERSION.SDK_INT >= 28)
            android.content.pm.PackageManager.GET_SIGNING_CERTIFICATES
        else android.content.pm.PackageManager.GET_SIGNATURES
        val current = pm.getPackageInfo(activity.packageName, flags)
        val incoming = pm.getPackageArchiveInfo(apk.absolutePath, flags)
            ?: error("فایل دانلودشده بسته نصب اندروید معتبری نیست.")
        check(incoming.packageName == activity.packageName) {
            "شناسه برنامه با پیامیار نصب‌شده متفاوت است. نصب متوقف شد."
        }
        val currentCode = if (Build.VERSION.SDK_INT >= 28) current.longVersionCode else current.versionCode.toLong()
        val incomingCode = if (Build.VERSION.SDK_INT >= 28) incoming.longVersionCode else incoming.versionCode.toLong()
        check(incomingCode >= currentCode) {
            "این بسته از نسخه نصب‌شده قدیمی‌تر است؛ نصب نسخه قدیمی مجاز نیست."
        }
        val existingCerts = if (Build.VERSION.SDK_INT >= 28)
            current.signingInfo?.apkContentsSigners?.map { it.toByteArray() }.orEmpty()
        else current.signatures?.map { it.toByteArray() }.orEmpty()
        val incomingCerts = if (Build.VERSION.SDK_INT >= 28)
            incoming.signingInfo?.apkContentsSigners?.map { it.toByteArray() }.orEmpty()
        else incoming.signatures?.map { it.toByteArray() }.orEmpty()
        check(existingCerts.isNotEmpty() && incomingCerts.isNotEmpty()
            && existingCerts.size == incomingCerts.size
            && existingCerts.all { old -> incomingCerts.any { new -> old.contentEquals(new) } }) {
            "امضای این نسخه با نسخه نصب‌شده یکسان نیست. برای حفظ پیام‌ها و تنظیمات، برنامه قبلی را حذف نکنید؛ باید نسخه‌ای با امضای معتبر قبلی منتشر شود."
        }
    }

    fun install(activity: Activity, apk: File) {
        val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.updates", apk)
        activity.startActivity(Intent(Intent.ACTION_VIEW)
            .setDataAndType(uri, "application/vnd.android.package-archive")
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK))
    }
}
