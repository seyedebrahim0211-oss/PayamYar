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
    @Before fun start() {
        device.executeShellCommand("appops set ${context.packageName} SYSTEM_ALERT_WINDOW allow")
        device.executeShellCommand("pm grant ${context.packageName} android.permission.POST_NOTIFICATIONS")
        context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE).edit()
            .putBoolean("flutter.appLock", false).putBoolean("flutter.notifyPreview", true)
            .putBoolean("flutter.bannerTop", true).putLong("flutter.bannerSeconds", 15).commit()
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
        assertTrue("Code action must be reachable by scrolling long text", scrollToAction("کپی کد 12345"))
        assertNotNull(device.findObject(By.text("کپی کد 12345")))
        assertTrue("Conversation action must be reachable by scrolling", scrollToAction("باز کردن گفتگو / پاسخ"))
    }
    @Test fun appLockNeverExposesSampleOtpOrSenderInOverlay() {
        context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE).edit()
            .putBoolean("flutter.appLock", true).commit()
        instrumentation.waitForIdleSync()
        displayWhileAppVisible("+989000000000", "PRIVATE_SENDER", "PRIVATE_BODY کد: 12345", true)
        assertTrue(device.wait(Until.hasObject(By.text("باز کردن برنامه")), 5000))
        assertFalse(device.hasObject(By.textContains("PRIVATE_")))
        assertFalse(device.hasObject(By.textContains("12345")))
    }
    @Test fun landscapeAndLargeFontKeepTheCardInsideDisplay() {
        device.setOrientationLeft()
        device.executeShellCommand("settings put system font_scale 1.8")
        device.waitForIdle()
        displayWhileAppVisible("+989000000000", "متن بزرگ", "پیام آزمایشی\n".repeat(60), true)
        val scroll = device.wait(Until.findObject(By.clazz("android.widget.ScrollView").pkg(context.packageName)), 5000)
        assertNotNull(scroll)
        val b = scroll.visibleBounds
        assertTrue(b.left >= 0 && b.right <= device.displayWidth)
        assertTrue(b.top >= 0 && b.bottom <= device.displayHeight)
        assertTrue("Conversation action must be reachable by scrolling", scrollToAction("باز کردن گفتگو / پاسخ"))
    }
    @Test fun senderBubbleAppearsOnlyForIncomingSms() {
        assertFalse(device.hasObject(By.descContains("حباب پیام‌یار")))
        context.getSharedPreferences("payamyar_overlay", Context.MODE_PRIVATE).edit()
            .putInt("bubbleSeconds", 8).commit()
        displayWhileAppVisible("+989120000001", "مریم", "سلام، پیام تازه", false)
        assertTrue("A newly received message must show its sender bubble",
            device.wait(Until.hasObject(By.descContains("حباب پیام‌یار")), 15000))
        assertTrue("The transient bubble must disappear after its configured lifetime",
            device.wait(Until.gone(By.descContains("حباب پیام‌یار")), 12000))
    }
    @Test fun stoppingServiceRemovesChatHead() {
        displayWhileAppVisible("+989120000001", "مریم", "پیام", false)
        assertTrue(device.wait(Until.hasObject(By.descContains("حباب پیام‌یار")), 15000))
        instrumentation.runOnMainSync { FloatingNotifications.setEnabled(context, false) }
        assertTrue(device.wait(Until.gone(By.descContains("حباب پیام‌یار")), 5000))
    }
}
