package ir.honarmardomi.payamyar

import org.junit.Assert.*
import org.junit.Test

class BulkQueuePolicyTest {
    @Test fun successesContinueWithRadioPacingNotDeliveryWait() {
        repeat(3) {
            assertTrue(BulkQueuePolicy.isAccepted("accepted_by_radio"))
            assertEquals(4_000L, BulkQueuePolicy.nextDelayMs("accepted_by_radio", 0))
        }
        assertTrue(BulkQueuePolicy.isAccepted("delivered"))
        assertFalse(BulkQueuePolicy.isAccepted("pending"))
    }

    @Test fun networkFailureDoesNotRepeatItsRecipientAndSlowsLaterRecipients() {
        val delays = (1..6).map { BulkQueuePolicy.nextDelayMs("send_failed:no_service", it) }
        assertEquals(listOf(20_000L, 40_000L, 80_000L,
            160_000L, 300_000L, 300_000L), delays)
        repeat(3) {
            assertTrue(BulkQueuePolicy.isSettled("send_failed:no_service"))
            assertFalse(BulkQueuePolicy.canAutomaticallyRetryAttempted("send_failed:no_service"))
        }
    }

    @Test fun threeAmbiguousCallbacksOrTimeoutsAreNeverClaimedSentOrRetried() {
        repeat(3) { attempt ->
            assertEquals("send_unconfirmed", BulkQueuePolicy.afterTimeout("pending"))
            assertFalse(BulkQueuePolicy.isAccepted("send_unconfirmed"))
            assertTrue(BulkQueuePolicy.isSettled("send_unconfirmed"))
            assertFalse(BulkQueuePolicy.canAutomaticallyRetryAttempted("send_unconfirmed"))
            assertTrue(BulkQueuePolicy.nextDelayMs("send_unconfirmed", attempt + 1) >= 20_000L)
        }
        assertEquals("queued", BulkQueuePolicy.afterTimeout("queued"))
        assertEquals("accepted_by_radio", BulkQueuePolicy.afterTimeout("accepted_by_radio"))
    }

    @Test fun repeatedSuccessfulSingleSegmentModemReceiptsAdvanceExactlyOnce() {
        repeat(3) {
            assertEquals("accepted_by_radio",
                BulkQueuePolicy.sentStatus("pending", -1, 1, 1, 1, ""))
            assertEquals(4_000L, BulkQueuePolicy.nextDelayMs("accepted_by_radio", 0))
        }
    }

    @Test fun partialMultipartAcknowledgementNeverClaimsWholeMessageWasSent() {
        repeat(3) {
            assertEquals("pending",
                BulkQueuePolicy.sentStatus("pending", -1, 1, 1, 2, ""))
            assertEquals("accepted_by_radio",
                BulkQueuePolicy.sentStatus("pending", -1, 2, 2, 2, ""))
            assertEquals("send_unconfirmed",
                BulkQueuePolicy.sentStatus("pending", 0, 1, 0, 2, ""))
            assertEquals("send_unconfirmed",
                BulkQueuePolicy.sentStatus("send_unconfirmed", -1, 2, 1, 2, ""))
            assertEquals("accepted_by_radio",
                BulkQueuePolicy.sentStatus("send_unconfirmed", -1, 2, 2, 2, ""))
        }
    }

    @Test fun repeatedRadioErrorsDoNotFabricateDeliveryOrAuthorizeRetries() {
        repeat(3) {
            assertEquals("send_failed:no_service",
                BulkQueuePolicy.sentStatus("pending", 4, 1, 0, 1, "no_service"))
            assertEquals("send_unconfirmed",
                BulkQueuePolicy.sentStatus("pending", 0, 1, 0, 1, ""))
            assertFalse(BulkQueuePolicy.canAutomaticallyRetryAttempted("send_unconfirmed"))
        }
    }

    @Test fun offlineGuardAndWindowLimitRemainConservative() {
        assertEquals(60_000L, BulkQueuePolicy.PREFLIGHT_RECHECK_MS)
        assertEquals(12, BulkQueuePolicy.WINDOW_LIMIT)
        assertEquals(60_000L, BulkQueuePolicy.WINDOW_MS)
        assertEquals(45_000L, BulkQueuePolicy.ACK_TIMEOUT_MS)
        assertFalse(BulkQueuePolicy.canAutomaticallyRetryAttempted("delivery_failed"))
    }
}
