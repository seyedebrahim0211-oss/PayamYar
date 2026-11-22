package ir.honarmardomi.payamyar

/**
 * Conservative pacing for user-approved bulk SMS.
 *
 * A radio SENT callback proves only that Android accepted the attempt, not that
 * the recipient received it. Unknown and failed attempts are never re-enqueued
 * automatically: only the untouched recipients continue after a cooldown.
 */
internal object BulkQueuePolicy {
    const val GAP_MS = 4_000L
    const val ACK_TIMEOUT_MS = 45_000L
    const val WINDOW_MS = 60_000L
    const val WINDOW_LIMIT = 12
    const val PREFLIGHT_RECHECK_MS = 60_000L

    fun isAccepted(status: String): Boolean =
        status == "accepted_by_radio" || status == "delivered"

    fun isSettled(status: String): Boolean =
        isAccepted(status) || status == "send_unconfirmed" ||
            status == "queue_unreadable" || status.startsWith("send_failed") ||
            status == "delivery_failed"

    fun afterTimeout(status: String): String =
        if (status == "pending") "send_unconfirmed" else status

    /** Exponential backoff prevents a network outage from draining 500 failed sends. */
    fun nextDelayMs(status: String, consecutiveIssues: Int): Long {
        if (isAccepted(status)) return GAP_MS
        val exponent = (consecutiveIssues - 1).coerceIn(0, 5)
        return (20_000L shl exponent).coerceAtMost(5 * 60_000L)
    }

    /** None of these statuses authorize a retry of the *same* attempted SMS. */
    fun canAutomaticallyRetryAttempted(status: String): Boolean = false
}
