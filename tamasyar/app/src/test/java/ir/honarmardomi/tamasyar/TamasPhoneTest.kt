package ir.honarmardomi.tamasyar

import org.junit.Assert.assertEquals
import org.junit.Test

class TamasPhoneTest {
    @Test fun physicalKeypadNeverMirrorsInRtl() {
        assertEquals(listOf("1", "2", "3"), TamasPhone.KEYPAD_ROWS[0])
        assertEquals(listOf("4", "5", "6"), TamasPhone.KEYPAD_ROWS[1])
        assertEquals(listOf("7", "8", "9"), TamasPhone.KEYPAD_ROWS[2])
        assertEquals(listOf("*", "0", "#"), TamasPhone.KEYPAD_ROWS[3])
    }
    @Test fun persianAndArabicDigits() {
        assertEquals("09123456789", TamasPhone.dial("۰۹۱۲ ٣٤٥ ۶۷۸۹"))
    }
    @Test fun equivalentIranianNumbers() {
        assertEquals("09123456789", TamasPhone.normalize("+98 (912) 345-6789"))
        assertEquals("09123456789", TamasPhone.normalize("00989123456789"))
        assertEquals("09123456789", TamasPhone.normalize("989123456789"))
    }
    @Test fun serviceCodesAndSanitization() {
        assertEquals("*#06#", TamasPhone.dial("*#۰۶#"))
        assertEquals("+12345", TamasPhone.dial("+1 (234) 5"))
        assertEquals("0911", TamasPhone.dial("۰۹۱۱;DROP TABLE"))
    }
    @Test fun shortNames() {
        assertEquals("عح", TamasPhone.initials("علی حسینی"))
        assertEquals("☎", TamasPhone.initials("  "))
    }
}
