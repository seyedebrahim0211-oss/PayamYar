package ir.honarmardomi.payamyar

/** Pure calculations shared by Android delivery, geometry and PIN cooldowns. */
object NotificationPolicy {
    fun lockoutMillis(failures: Int): Long = when {
        failures <= 5 -> 60_000L
        failures == 6 -> 300_000L
        failures == 7 -> 900_000L
        else -> 3_600_000L
    }
    fun remainingSeconds(deadline: Long, elapsed: Long): Long =
        ((deadline - elapsed).coerceAtLeast(0L) + 999L) / 1000L
    fun cardWidth(available: Int, desired: Int, margin: Int): Int =
        minOf(desired, (available - 2 * margin).coerceAtLeast(1)).coerceAtLeast(1)
    fun cardHeight(available: Int, measured: Int): Int =
        measured.coerceIn(1, (available * .65f).toInt().coerceAtLeast(1))
}

/** Human-readable diagnostics for Android sent-intent result codes.
 *  In particular, modem errors 121 and 123 identify SMS blocked by an active call.
 *  Do not automatically retry these: the radio outcome can be ambiguous on OEM devices
 *  and a blind retry can send duplicate messages.
 */
object SmsSendDiagnostic {
    fun describe(code: Int): String = when (code) {
        2 -> "رادیوی سیم‌کارت خاموش است؛ حالت پرواز و وضعیت سیم‌کارت را بررسی کنید."
        4, 100, 110, 111 -> "شبکه پیامک در دسترس نیست؛ آنتن و سرویس سیم‌کارت را بررسی کنید."
        121, 123 -> "شبکه هم‌زمان با تماس اجازه ارسال پیامک نداد؛ پس از پایان تماس، ارسال مجدد را دستی انجام دهید."
        120, 134 -> "سیم‌کارت برای ارسال پیامک در دسترس نیست؛ سیم‌کارت ارسال را بررسی کنید."
        5, 106 -> "محدودیت تعداد ارسال فعال شده است؛ بعداً دوباره امتحان کنید."
        8, 9 -> "ارسال به این شماره توسط تنظیمات مجوز پیامک محدود شده است."
        3, 109 -> "خطا در ساخت یا کدگذاری پیامک رخ داد؛ متن را بررسی کنید."
        1 -> "شبکه ارسال پیامک را رد کرد؛ سیم‌کارت و اعتبار را بررسی کنید."
        else -> "ارسال از سوی شبکه تأیید نشد (کد $code). از ارسال تکراری بدون بررسی سابقه خودداری کنید."
    }
}
