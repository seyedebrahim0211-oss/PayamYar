package ir.honarmardomi.payamyar

import android.content.Context
import android.content.Intent
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.UiScrollable
import androidx.test.uiautomator.UiSelector
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
    @Before fun start() {
        device.executeShellCommand("appops set ${context.packageName} SYSTEM_ALERT_WINDOW allow")
        device.executeShellCommand("pm grant ${context.packageName} android.permission.POST_NOTIFICATIONS")
        context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE).edit()
            .putBoolean("flutter.appLock", false).putBoolean("flutter.notifyPreview", true)
            .putBoolean("flutter.bannerTop", true).putLong("flutter.bannerSeconds", 15).commit()
        scenario = ActivityScenario.launch(Intent(context, MainActivity::class.java))
        scenario!!.onActivity { assertTrue(FloatingNotifications.setEnabled(it, true)) }
        device.pressHome()
        assertTrue("The opted-in edge chat head must appear outside the app",
            device.wait(Until.hasObject(By.descContains("حباب پیام‌یار")), 15000))
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
        instrumentation.runOnMainSync {
            assertTrue(FloatingNotifications.show(context, "+989000000000", "آزمون اعلان", body, true))
        }
        val header = device.wait(Until.findObject(By.text("آزمون اعلان")), 5000)
        assertNotNull(header)
        val bounds = header.visibleBounds
        assertTrue(bounds.left >= 0 && bounds.right <= device.displayWidth)
        assertTrue(bounds.top >= 0 && bounds.bottom <= device.displayHeight)
        assertTrue(UiScrollable(UiSelector().className("android.widget.ScrollView").packageName(context.packageName))
            .scrollTextIntoView("کپی کد 12345"))
        assertNotNull(device.findObject(By.text("کپی کد 12345")))
        assertTrue(UiScrollable(UiSelector().className("android.widget.ScrollView").packageName(context.packageName))
            .scrollTextIntoView("باز کردن گفتگو / پاسخ"))
    }
    @Test fun appLockNeverExposesSampleOtpOrSenderInOverlay() {
        context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE).edit()
            .putBoolean("flutter.appLock", true).commit()
        instrumentation.waitForIdleSync()
        instrumentation.runOnMainSync {
            assertTrue(FloatingNotifications.show(context, "+989000000000", "PRIVATE_SENDER", "PRIVATE_BODY کد: 12345", true))
        }
        assertTrue(device.wait(Until.hasObject(By.text("باز کردن برنامه")), 5000))
        assertFalse(device.hasObject(By.textContains("PRIVATE_")))
        assertFalse(device.hasObject(By.textContains("12345")))
    }
    @Test fun landscapeAndLargeFontKeepTheCardInsideDisplay() {
        device.setOrientationLeft()
        device.executeShellCommand("settings put system font_scale 1.8")
        device.waitForIdle()
        instrumentation.runOnMainSync {
            assertTrue(FloatingNotifications.show(context, "+989000000000", "متن بزرگ", "پیام آزمایشی\n".repeat(60), true))
        }
        val scroll = device.wait(Until.findObject(By.clazz("android.widget.ScrollView").pkg(context.packageName)), 5000)
        assertNotNull(scroll)
        val b = scroll.visibleBounds
        assertTrue(b.left >= 0 && b.right <= device.displayWidth)
        assertTrue(b.top >= 0 && b.bottom <= device.displayHeight)
        assertTrue(UiScrollable(UiSelector().className("android.widget.ScrollView").packageName(context.packageName))
            .scrollTextIntoView("باز کردن گفتگو / پاسخ"))
    }
    @Test fun stoppingServiceRemovesChatHead() {
        instrumentation.runOnMainSync { FloatingNotifications.setEnabled(context, false) }
        assertTrue(device.wait(Until.gone(By.descContains("حباب پیام‌یار")), 5000))
    }
}
