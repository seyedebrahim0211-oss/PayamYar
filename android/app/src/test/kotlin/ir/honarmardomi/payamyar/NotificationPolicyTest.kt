package ir.honarmardomi.payamyar

import org.junit.Assert.*
import org.junit.Test

class NotificationPolicyTest {
    @Test fun callRelatedCarrierFailuresHaveSpecificDiagnostic() {
        for (code in listOf(121, 123)) {
            assertTrue(SmsSendDiagnostic.describe(code).contains("تماس"))
            assertTrue(SmsSendDiagnostic.describe(code).contains("دستی"))
        }
        assertTrue(SmsSendDiagnostic.describe(4).contains("شبکه"))
        assertTrue(SmsSendDiagnostic.describe(120).contains("سیم‌کارت"))
        assertTrue(SmsSendDiagnostic.describe(999).contains("999"))
    }
    @Test fun floatingSettingsReadPersistedFlutterDoublesAndNumericLegacyValues() {
        assertEquals(420f, NotificationPolicy.flutterFloat("VGhpcyBpcyB0aGUgcHJlZml4IGZvciBEb3VibGUu420.0", 360f), 0f)
        assertEquals(.81f, NotificationPolicy.flutterFloat(.81f, .9f), .0001f)
        assertEquals(26f, NotificationPolicy.flutterFloat("invalid", 26f), 0f)
        assertEquals(26f, NotificationPolicy.flutterFloat(Double.NaN, 26f), 0f)
    }
    @Test fun onlyExactMessagingSenderIdsSelectAServiceColor() {
        assertEquals(MessengerSender.TELEGRAM, MessengerSender.fromAddress(" Telegram "))
        assertEquals(MessengerSender.BALE, MessengerSender.fromAddress("بله"))
        assertEquals(MessengerSender.EITAA, MessengerSender.fromAddress("eitaa"))
        assertEquals(MessengerSender.WHATSAPP, MessengerSender.fromAddress("WhatsApp"))
        assertEquals(4, MessengerSender.values().map { it.color }.toSet().size)
        assertNull(MessengerSender.fromAddress("Telegram Support"))
        assertNull(MessengerSender.fromAddress("+989000000000"))
    }
    @Test fun cardsFitPhoneTabletLandscapeAndSplitScreen() {
        for (width in listOf(160, 240, 320, 360, 1080, 2400)) {
            for (desired in listOf(280, 360, 520, 1560)) {
                val card = NotificationPolicy.cardWidth(width, desired, 8)
                assertTrue(card > 0)
                assertTrue(card <= width - 16)
                assertTrue(card <= desired)
            }
        }
    }
    @Test fun longTextScrollsWithinAvailableHeightInsteadOfGrowingOffScreen() {
        for (height in listOf(120, 240, 640, 2200)) {
            assertEquals((height * .65f).toInt(), NotificationPolicy.cardHeight(height, 10000))
            assertEquals(40, NotificationPolicy.cardHeight(height, 40))
        }
    }
    @Test fun tinyTransientWindowBoundsCannotCauseInvalidLayoutDimensions() {
        assertEquals(1, NotificationPolicy.cardWidth(0, 360, 8))
        assertEquals(1, NotificationPolicy.cardHeight(0, 0))
    }
    @Test fun cooldownDoesNotUnlockInLastPartialSecond() {
        assertEquals(1L, NotificationPolicy.remainingSeconds(60000, 59999))
        assertEquals(60L, NotificationPolicy.remainingSeconds(60000, 0))
        assertEquals(0L, NotificationPolicy.remainingSeconds(60000, 60000))
        assertEquals(0L, NotificationPolicy.remainingSeconds(60000, 99999))
    }
    @Test fun cooldownEscalatesButIsBounded() {
        assertEquals(60000L, NotificationPolicy.lockoutMillis(5))
        assertEquals(300000L, NotificationPolicy.lockoutMillis(6))
        assertEquals(900000L, NotificationPolicy.lockoutMillis(7))
        assertEquals(3600000L, NotificationPolicy.lockoutMillis(8))
        assertEquals(3600000L, NotificationPolicy.lockoutMillis(Int.MAX_VALUE))
    }
}
