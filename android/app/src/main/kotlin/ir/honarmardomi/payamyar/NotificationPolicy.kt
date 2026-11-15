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
