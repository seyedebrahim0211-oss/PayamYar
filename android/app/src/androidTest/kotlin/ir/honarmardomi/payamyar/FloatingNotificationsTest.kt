package ir.honarmardomi.payamyar

import android.content.Context
import android.content.Intent
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Direction
import androidx.test.uiautomator.Until
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class FloatingNotificationsTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext
    private val device = UiDevice.getInstance(instrumentation)
    private var scenario: ActivityScenario<MainActivity>? = null

    /**
     * UiScrollable's legacy UiSelector cannot reliably match application overlay windows
     * on Android 15, even though UiObject2 resolves their content and class correctly.
     * Use the accessible ScrollView itself, and verify the actions as we scroll.
     */
    private fun scrollToAction(text: String): Boolean {
        val selector = By.text(text)
        for (attempt in 0..14) {
            if (device.hasObject(selector)) return true
            val view = device.wait(
                Until.findObject(By.clazz("android.widget.ScrollView").pkg(context.packageName)), 2000
            ) ?: return false
            try {
                view.scroll(Direction.DOWN, .70f)
            } catch (_: RuntimeException) {
                return false
            }
            device.waitForIdle()
        }
        return device.hasObject(selector)
    }
    /**
     * Android 15 restricts launching FGS from the background. Real SMS notification
     * fallback is separately native; UI overlay scenarios start while visible, then
     * verify the actual off-app overlay after Home.
     */
    private fun displayWhileAppVisible(address: String, name: String, body: String, sample: Boolean) {
        device.executeShellCommand("am start -n ${context.packageName}/.MainActivity")
        assertTrue("App must be visible before starting a test foreground service",
            device.wait(Until.hasObject(By.pkg(context.packageName)), 5000))
        instrumentation.runOnMainSync {
            if (!sample) MainActivity.foregroundChannel = null
            assertTrue(FloatingNotifications.show(context, address, name, body, sample))
        }
        instrumentation.waitForIdleSync()
        device.pressHome()
    }
    private fun expandCard() {
        val toggle = device.wait(Until.findObject(By.desc("نمایش متن کامل")), 5000)
        assertNotNull("Compact card must expose its expansion button", toggle)
        toggle.click()
        device.waitForIdle()
    }

    @Before fun start() {
        device.executeShellCommand("appops set ${context.packageName} SYSTEM_ALERT_WINDOW allow")
        device.executeShellCommand("pm grant ${context.packageName} android.permission.POST_NOTIFICATIONS")
        context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE).edit()
            .putBoolean("flutter.appLock", false).putBoolean("flutter.notifyPreview", true)
            .putBoolean("flutter.bannerTop", true).putLong("flutter.bannerSeconds", 6).commit()
        scenario = ActivityScenario.launch(Intent(context, MainActivity::class.java))
        scenario!!.onActivity { assertTrue(FloatingNotifications.setEnabled(it, true)) }
        device.pressHome()
        // Enabling only records the preference: no idle bubble and no permanent alert.
        assertFalse("The idle app must not display a persistent chat head",
            device.hasObject(By.descContains("حباب پیام‌یار")))
    }
    @After fun stop() {
        instrumentation.runOnMainSync { FloatingNotifications.setEnabled(context, false) }
        device.executeShellCommand("settings put system font_scale 1.0")
        device.unfreezeRotation()
        device.setOrientationNatural()
        scenario?.close()
        context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE).edit()
            .putBoolean("flutter.appLock", false).commit()
    }
    @Test fun longMessageFitsWindowAndCanScrollToActions() {
        val body = (1..40).joinToString("\n") { "خط $it از پیام فارسی بلند برای آزمایش نمایش کامل" } + "\nکد: 12345"
        displayWhileAppVisible("+989000000000", "آزمون اعلان", body, true)
        val header = device.wait(Until.findObject(By.text("آزمون اعلان")), 5000)
        assertNotNull(header)
        val bounds = header.visibleBounds
        assertTrue(bounds.left >= 0 && bounds.right <= device.displayWidth)
        assertTrue(bounds.top >= 0 && bounds.bottom <= device.displayHeight)
        assertTrue("The copy action belongs on the folded card", device.hasObject(By.text("کپی کد ۱۲۳۴۵")))
        assertFalse(device.hasObject(By.text("گفتگو")))
        val toggle = device.findObject(By.desc("نمایش متن کامل"))
        assertTrue("The RTL sender must be to the right of the chevron", bounds.centerX() > toggle.visibleBounds.centerX())
        expandCard()
        assertTrue("Conversation action must be reachable by scrolling", scrollToAction("گفتگو"))
    }
    @Test fun appLockNeverExposesSampleOtpOrSenderInOverlay() {
        context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE).edit()
            .putBoolean("flutter.appLock", true).commit()
        instrumentation.waitForIdleSync()
        displayWhileAppVisible("+989000000000", "PRIVATE_SENDER", "PRIVATE_BODY کد: 12345", true)
        expandCard()
        assertTrue(device.wait(Until.hasObject(By.text("باز کردن برنامه")), 5000))
        assertFalse(device.hasObject(By.textContains("PRIVATE_")))
        assertFalse(device.hasObject(By.textContains("12345")))
    }
    @Test fun landscapeAndLargeFontKeepTheCardInsideDisplay() {
        device.setOrientationLeft()
        device.executeShellCommand("settings put system font_scale 1.8")
        device.waitForIdle()
        displayWhileAppVisible("+989000000000", "متن بزرگ", "پیام آزمایشی\n".repeat(60), true)
        expandCard()
        val scroll = device.wait(Until.findObject(By.clazz("android.widget.ScrollView").pkg(context.packageName)), 5000)
        assertNotNull(scroll)
        val b = scroll.visibleBounds
        assertTrue(b.left >= 0 && b.right <= device.displayWidth)
        assertTrue(b.top >= 0 && b.bottom <= device.displayHeight)
        assertTrue("Conversation action must be reachable by scrolling", scrollToAction("گفتگو"))
    }
    @Test fun senderBubbleAppearsOnlyForIncomingSms() {
        assertFalse(device.hasObject(By.descContains("حباب پیام‌یار")))
        context.getSharedPreferences("payamyar_overlay", Context.MODE_PRIVATE).edit()
            .putInt("bubbleSeconds", 8).commit()
        displayWhileAppVisible("+989120000001", "مریم", "سلام، پیام تازه", false)
        assertTrue(device.wait(Until.hasObject(By.desc("نمایش متن کامل")), 5000))
        assertFalse("Card and chat head must never cover each other", device.hasObject(By.descContains("حباب پیام‌یار")))
        assertTrue("A newly received message must show its sender bubble after the card closes",
            device.wait(Until.hasObject(By.descContains("حباب پیام‌یار")), 15000))
        assertFalse(device.hasObject(By.desc("نمایش متن کامل")))
        assertTrue("The transient bubble must disappear after its configured lifetime",
            device.wait(Until.gone(By.descContains("حباب پیام‌یار")), 12000))
    }
    @Test fun glassOpacityIsStableAcrossRedraws() {
        val glass = GlassSurface(0xff087f81.toInt(), 1f, 26f, true, .78f, .15f, .55f)
        glass.setBounds(0, 0, 300, 140)
        val bitmap = android.graphics.Bitmap.createBitmap(300, 140, android.graphics.Bitmap.Config.ARGB_8888)
        val canvas = android.graphics.Canvas(bitmap)
        glass.draw(canvas)
        val first = bitmap.getPixel(150, 70)
        assertTrue("The center must mask wallpaper lettering", android.graphics.Color.alpha(first) >= 230)
        bitmap.eraseColor(android.graphics.Color.TRANSPARENT)
        glass.draw(canvas)
        assertEquals("A previous translucent ring must never change the face alpha", first, bitmap.getPixel(150, 70))
    }

    @Test fun lightWallpaperAndBrightColorsKeepTheSenderReadable() {
        val bitmap = android.graphics.Bitmap.createBitmap(300, 140, android.graphics.Bitmap.Config.ARGB_8888)
        val canvas = android.graphics.Canvas(bitmap)
        for (tint in MessengerSender.values().map { it.color } + listOf(0xFF919124.toInt(), android.graphics.Color.WHITE)) {
            bitmap.eraseColor(android.graphics.Color.WHITE)
            val glass = GlassSurface(tint, 1f, 26f, false, .78f, .72f, 1f)
            glass.setBounds(0, 0, 300, 140)
            glass.draw(canvas)
            val pixel = bitmap.getPixel(270, 9)
            assertTrue(androidx.core.graphics.ColorUtils.calculateContrast(0xF2FFFFFF.toInt(), pixel) >= 4.5)
        }
    }

    @Test fun stoppingServiceRemovesChatHead() {
        displayWhileAppVisible("+989120000001", "مریم", "پیام", false)
        assertTrue(device.wait(Until.hasObject(By.descContains("حباب پیام‌یار")), 15000))
        instrumentation.runOnMainSync { FloatingNotifications.setEnabled(context, false) }
        assertTrue(device.wait(Until.gone(By.descContains("حباب پیام‌یار")), 5000))
    }
}
