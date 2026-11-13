package ir.honarmardomi.tamasyar

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class TamasContactsTest {
    private val all = listOf(
        TamasContact(1, "علی رضایی", listOf("۰۹۱۲ ۱۲۳۴۵۶۷", "02144444444"), false),
        TamasContact(2, "زهرا موسوی", listOf("+98 915 222 3333"), true),
        TamasContact(3, "مخاطب بدون شماره", emptyList(), false)
    )

    @Test fun includesContactsWithoutNumbers() {
        assertEquals(3, TamasContactRepository.search(all, "", false, emptySet(), false).size)
    }

    @Test fun nameSearchDoesNotMatchAllPhoneNumbers() {
        val result = TamasContactRepository.search(all, "علی", false, emptySet(), false)
        assertEquals(1, result.size)
        assertEquals(1L, result[0].id)
    }

    @Test fun persianAndInternationalNumberSearch() {
        val a = TamasContactRepository.search(all, "۱۲۳۴۵۶۷", false, emptySet(), false)
        assertEquals(1L, a.single().id)
        val b = TamasContactRepository.search(all, "۰۹۱۵۲۲۲۳۳۳۳", false, emptySet(), false)
        assertEquals(2L, b.single().id)
    }

    @Test fun favoritesRecognizeSystemAndLocalStars() {
        val result = TamasContactRepository.search(
            all, "", true, setOf("09121234567"), true)
        assertEquals(2, result.size)
        assertTrue(result.any { it.id == 1L })
        assertTrue(result.any { it.id == 2L })
    }

    @Test fun noHardCodedOneHundredFiftyLimit() {
        val large = (0 until 1200).map { TamasContact(it.toLong(),
            "مخاطب " + it, listOf("09" + it.toString().padStart(9, '0')), false) }
        val result = TamasContactRepository.search(large, "", false, emptySet(), true)
        assertEquals(1200, result.size)
    }
}
