package ir.honarmardomi.payamyar

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import java.io.File
import java.io.RandomAccessFile
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.util.concurrent.atomic.AtomicBoolean
import java.util.zip.ZipFile

/**
 * Downloads a new PayamYar release from honarmardomi.ir and hands it to Android's installer.
 *
 * Security model (defence in depth, Android itself is the final authority):
 *  1. Only HTTPS URLs on honarmardomi.ir (also after redirects).
 *  2. SHA-256 of the served file must equal the value published by the site.
 *  3. Package name of the downloaded APK must equal the installed package.
 *  4. The APK's signing certificate must be the pinned official PayamYar certificate
 *     AND the certificate of the installed app; legacy preview builds are refused with
 *     a clear message instead of an installer error.
 *  5. versionCode must be strictly newer (no downgrade, no reinstall loops).
 *  6. The system Package Installer always asks the user; nothing is installed silently.
 */
object AppUpdater {
    private const val HOST = "honarmardomi.ir"
    private const val MAX_APK_BYTES = 140L * 1024 * 1024

    /** Public SHA-256 of the permanent PayamYar release certificate (see .github/payamyar-release-cert.sha256). */
    const val OFFICIAL_SIGNER = "C800225A42B292F1B9C2E1578E6B9F2B3921D6A50378B5C9D074D38B443DF48F"

    private val busy = AtomicBoolean(false)

    private fun hex(bytes: ByteArray) = bytes.joinToString("") { "%02X".format(it.toInt() and 0xff) }

    @Suppress("DEPRECATION")
    private fun signers(info: PackageInfo?): List<ByteArray> {
        if (info == null) return emptyList()
        return if (Build.VERSION.SDK_INT >= 28) {
            val signing = info.signingInfo ?: return emptyList()
            (if (signing.hasMultipleSigners()) signing.apkContentsSigners else signing.signingCertificateHistory)
                ?.map { it.toByteArray() }.orEmpty()
        } else info.signatures?.map { it.toByteArray() }.orEmpty()
    }

    @Suppress("DEPRECATION")
    private val signFlags: Int
        get() = if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES else PackageManager.GET_SIGNATURES

    /** SHA-256 of the current signing certificate of the installed APK (last entry of a rotation history). */
    fun installedSignerSha256(activity: Activity): String {
        val certs = signers(activity.packageManager.getPackageInfo(activity.packageName, signFlags))
        val cert = certs.lastOrNull() ?: return ""
        return hex(MessageDigest.getInstance("SHA-256").digest(cert))
    }

    fun canInstall(activity: Activity): Boolean =
        Build.VERSION.SDK_INT < 26 || activity.packageManager.canRequestPackageInstalls()

    fun openInstallPermission(activity: Activity) {
        if (Build.VERSION.SDK_INT >= 26) {
            activity.startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:${activity.packageName}")))
        }
    }

    private fun allowed(url: URL) = url.protocol == "https" && (url.host == HOST || url.host == "www.$HOST") &&
        (url.port == -1 || url.port == 443) && url.userInfo == null

    /**
     * Blocking; call on a worker thread. Returns the ready-to-install APK file.
     * A partial download is kept and resumed with an HTTP Range request when the same
     * release (same SHA-256) is retried after a network interruption.
     */
    fun download(activity: Activity, url: String, expectedSha256: String, expectedSize: Long,
                 progress: (Int, Long, Long) -> Unit): File {
        check(busy.compareAndSet(false, true)) { "دریافت به‌روزرسانی در حال انجام است." }
        try {
            return downloadLocked(activity, url, expectedSha256, expectedSize, progress)
        } finally {
            busy.set(false)
        }
    }

    private fun downloadLocked(activity: Activity, url: String, expectedSha256: String, expectedSize: Long,
                               progress: (Int, Long, Long) -> Unit): File {
        require(allowed(URL(url))) { "نشانی به‌روزرسانی معتبر نیست." }
        require(expectedSha256.matches(Regex("[a-fA-F0-9]{64}"))) { "اثر انگشت فایل انتشار نامعتبر است." }
        val sha = expectedSha256.lowercase()
        val dir = File(activity.cacheDir, "updates").apply { mkdirs() }
        val download = File(dir, "$sha.part")
        // Drop leftovers of other releases, keep a partial file of this one for resume.
        dir.listFiles()?.forEach { if (it.name != download.name) it.delete() }

        var attempt = 0
        while (true) {
            attempt++
            val have = if (download.exists()) download.length() else 0L
            var connection: HttpURLConnection? = null
            try {
                connection = (URL(url).openConnection() as HttpURLConnection).apply {
                    connectTimeout = 15000
                    readTimeout = 30000
                    instanceFollowRedirects = true
                    useCaches = false
                    setRequestProperty("Accept-Encoding", "identity")
                    if (have > 0) setRequestProperty("Range", "bytes=$have-")
                }
                val code = connection.responseCode
                check(allowed(connection.url)) { "فایل به‌روزرسانی از نشانی غیرمجاز هدایت شده است." }
                if (code == 416 && have > 0) { download.delete(); continue }
                check(code == 200 || code == 206) { "دریافت فایل انجام نشد (کد $code)." }
                val append = code == 206 && have > 0
                if (!append && download.exists()) download.delete()
                val start = if (append) have else 0L
                val total = when {
                    connection.contentLengthLong > 0 -> start + connection.contentLengthLong
                    expectedSize > 0 -> expectedSize
                    else -> -1L
                }
                check(total <= MAX_APK_BYTES) { "حجم فایل به‌روزرسانی بیش از حد مجاز است." }
                if (expectedSize > 0 && total > 0) check(total == expectedSize) { "حجم فایل با اطلاعات انتشار یکسان نیست." }
                connection.inputStream.use { input ->
                    RandomAccessFile(download, "rw").use { output ->
                        output.setLength(start)
                        output.seek(start)
                        val buffer = ByteArray(64 * 1024)
                        var done = start
                        var last = -2
                        while (true) {
                            val n = input.read(buffer)
                            if (n < 0) break
                            output.write(buffer, 0, n)
                            done += n
                            check(done <= MAX_APK_BYTES) { "حجم فایل به‌روزرسانی بیش از حد مجاز است." }
                            val p = if (total > 0) (done * 100 / total).toInt().coerceIn(0, 100) else -1
                            if (p != last) { last = p; progress(p, done, total) }
                        }
                    }
                }
                if (total > 0) check(download.length() == total) { "دریافت فایل کامل نشد؛ دوباره تلاش کنید." }
                break
            } catch (e: java.io.IOException) {
                // Network hiccup: retry twice automatically, keeping the partial file.
                if (attempt >= 3) throw IllegalStateException(
                    "اتصال اینترنت قطع شد. «تلاش دوباره» دانلود را از همان نقطه ادامه می‌دهد.", e)
                Thread.sleep(1500L * attempt)
            } finally {
                connection?.disconnect()
            }
        }

        val digest = MessageDigest.getInstance("SHA-256")
        download.inputStream().buffered().use { stream ->
            val buffer = ByteArray(64 * 1024)
            while (true) {
                val length = stream.read(buffer)
                if (length < 0) break
                digest.update(buffer, 0, length)
            }
        }
        if (!hex(digest.digest()).equals(sha, ignoreCase = true)) {
            download.delete()
            throw IllegalStateException("فایل دریافت‌شده سالم نیست (اثر انگشت SHA-256 تطبیق نکرد). دوباره تلاش کنید.")
        }

        val apk = File(dir, "PayamYar-update.apk")
        apk.delete()
        ZipFile(download).use { zip ->
            if (zip.getEntry("AndroidManifest.xml") == null) {
                val entries = zip.entries().asSequence()
                    .filter { !it.isDirectory && it.name.endsWith(".apk", true) }.toList()
                check(entries.size == 1) { "بسته باید دقیقاً یک فایل نصبی داشته باشد." }
                zip.getInputStream(entries.first()).use { input ->
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
        if (apk.exists()) download.delete() else check(download.renameTo(apk)) { "ذخیره فایل نصبی ممکن نشد." }
        return apk
    }

    /**
     * Android rejects upgrades signed with a different certificate. Detect the mismatch
     * before opening Package Installer, so users do not uninstall an app with local drafts.
     */
    fun validateUpgrade(activity: Activity, apk: File) {
        val pm = activity.packageManager
        val current = pm.getPackageInfo(activity.packageName, signFlags)
        val incoming = pm.getPackageArchiveInfo(apk.absolutePath, signFlags)
            ?: error("فایل دانلودشده بسته نصب اندروید معتبری نیست.")
        check(incoming.packageName == activity.packageName) {
            "شناسه برنامه با پیامیار نصب‌شده متفاوت است. نصب متوقف شد."
        }
        @Suppress("DEPRECATION")
        val currentCode = if (Build.VERSION.SDK_INT >= 28) current.longVersionCode else current.versionCode.toLong()
        @Suppress("DEPRECATION")
        val incomingCode = if (Build.VERSION.SDK_INT >= 28) incoming.longVersionCode else incoming.versionCode.toLong()
        check(incomingCode > currentCode) { "این بسته از نسخه نصب‌شده جدیدتر نیست؛ نصب متوقف شد." }
        fun digest(cert: ByteArray) = hex(MessageDigest.getInstance("SHA-256").digest(cert))
        val incomingSigner = signers(incoming).lastOrNull()?.let(::digest)
        val currentSigner = signers(current).lastOrNull()?.let(::digest)
        check(incomingSigner == OFFICIAL_SIGNER) { "فایل دریافت‌شده امضای رسمی پیامیار را ندارد. نصب متوقف شد." }
        check(currentSigner == OFFICIAL_SIGNER) {
            "این پیامیار یک نسخه آزمایشی با امضای قدیمی است و نمی‌تواند بدون حذف به نسخه رسمی ارتقا یابد. " +
                "ابتدا از مخاطبان و پیش‌نویس‌ها پشتیبان بگیرید، سپس نسخه رسمی را از honarmardomi.ir/payamyar نصب کنید."
        }
    }

    fun install(activity: Activity, apk: File) {
        val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.updates", apk)
        activity.startActivity(Intent(Intent.ACTION_VIEW)
            .setDataAndType(uri, "application/vnd.android.package-archive")
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK))
    }
}
