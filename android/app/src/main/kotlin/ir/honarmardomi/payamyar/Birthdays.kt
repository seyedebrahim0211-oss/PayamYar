package ir.honarmardomi.payamyar

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar

/**
 * Automatic birthday SMS and day-before reminders.
 *
 * Dart (lib/birthdays.dart) stores the list as JSON in FlutterSharedPreferences under
 * "flutter.birthdays_v1". Native code owns the timing, so greetings go out even when PayamYar is
 * closed or the phone restarted. Each greeting is sent at most once per Jalali day.
 */
object Birthdays {
    private const val KEY = "flutter.birthdays_v1"
    private const val STATE = "birthday_state_v1"
    const val ACTION = "ir.honarmardomi.payamyar.BIRTHDAYS"

    /** Gregorian → [year, month, day] in the Jalali calendar (same algorithm as lib/jalali.dart). */
    fun jalali(gy: Int, gm: Int, gd: Int): IntArray {
        val gdm = intArrayOf(0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334)
        val gy2 = if (gm > 2) gy + 1 else gy
        var days = 355666 + 365 * gy + (gy2 + 3) / 4 - (gy2 + 99) / 100 + (gy2 + 399) / 400 + gd + gdm[gm - 1]
        var jy = -1595 + 33 * (days / 12053)
        days %= 12053
        jy += 4 * (days / 1461)
        days %= 1461
        if (days > 365) {
            jy += (days - 1) / 365
            days = (days - 1) % 365
        }
        val jm: Int
        val jd: Int
        if (days < 186) {
            jm = 1 + days / 31
            jd = 1 + days % 31
        } else {
            jm = 7 + (days - 186) / 30
            jd = 1 + (days - 186) % 30
        }
        return intArrayOf(jy, jm, jd)
    }

    private fun jalaliOf(cal: Calendar) =
        jalali(cal.get(Calendar.YEAR), cal.get(Calendar.MONTH) + 1, cal.get(Calendar.DAY_OF_MONTH))

    private fun shifted(base: Calendar, days: Int): Calendar =
        (base.clone() as Calendar).apply { add(Calendar.DAY_OF_YEAR, days) }

    /** A 30 Esfand birthday is celebrated on 29 Esfand in common (non-leap) years. */
    private fun matches(b: JSONObject, day: IntArray, next: IntArray): Boolean {
        val m = b.optInt("month")
        val d = b.optInt("day")
        if (m == day[1] && d == day[2]) return true
        return m == 12 && d == 30 && day[1] == 12 && day[2] == 29 && next[1] == 1
    }

    private fun load(c: Context): List<JSONObject> = try {
        val raw = c.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE).getString(KEY, null)
        if (raw.isNullOrBlank()) emptyList()
        else JSONArray(raw).let { a -> (0 until a.length()).mapNotNull { a.optJSONObject(it) } }
    } catch (_: Exception) { emptyList() }

    private fun render(b: JSONObject, jalaliYear: Int): String {
        val name = b.optString("name").trim()
        val first = name.split(' ').firstOrNull { it.isNotBlank() } ?: name
        val year = b.optInt("year", 0)
        val age = if (year in 1200..jalaliYear) (jalaliYear - year).toString() else ""
        val template = b.optString("message").ifBlank { "{نام} عزیز، تولدت مبارک! 🎂" }
        return template.replace("{نام کامل}", name).replace("{نام}", first).replace("{سن}", age)
            .replace(Regex("[ \\t]+"), " ").trim()
    }

    private fun dueMinutes(b: JSONObject) =
        b.optInt("hour", 9).coerceIn(0, 23) * 60 + b.optInt("minute", 0).coerceIn(0, 59)

    /** Sends today's greetings whose time has come, shows reminders, then arms the next alarm. */
    @Synchronized fun run(c: Context) {
        val now = Calendar.getInstance()
        val today = jalaliOf(now)
        val tomorrow = jalaliOf(shifted(now, 1))
        val after = jalaliOf(shifted(now, 2))
        val minutes = now.get(Calendar.HOUR_OF_DAY) * 60 + now.get(Calendar.MINUTE)
        val dayKey = today[0].toString() + "-" + today[1] + "-" + today[2]
        val state = c.getSharedPreferences(STATE, Context.MODE_PRIVATE)
        for (b in load(c)) {
            if (!b.optBoolean("enabled", true)) continue
            val id = b.optString("id")
            if (id.isBlank() || minutes < dueMinutes(b)) continue
            val name = b.optString("name").ifBlank { b.optString("number") }
            val tag = 7000 + (id.hashCode() and 0x3FF)
            if (b.optBoolean("autoSend", true) && matches(b, today, tomorrow) && state.getString("sent:$id", "") != dayKey) {
                state.edit().putString("sent:$id", dayKey).commit()
                try {
                    val queued = SmsCore.queue(c, b.optString("number"), render(b, today[0]), b.optInt("sim", -1), 0)
                    SmsCore.dispatch(c, queued)
                    SmsCore.notify(c, tag, "🎂 تبریک تولد فرستاده شد", "پیامک تولد برای $name ارسال شد.")
                } catch (e: Exception) {
                    SmsCore.notify(c, tag, "ارسال تبریک تولد انجام نشد", name + ": " + (e.message ?: "خطای ناشناخته"))
                }
            }
            if (b.optBoolean("remind", true) && matches(b, tomorrow, after) && state.getString("rem:$id", "") != dayKey) {
                state.edit().putString("rem:$id", dayKey).commit()
                val auto = if (b.optBoolean("autoSend", true)) " پیامک تبریک خودکار فرستاده می‌شود." else ""
                SmsCore.notify(c, tag + 1024, "🎈 فردا تولد $name است", "یادتان نرود تبریک بگویید.$auto")
            }
        }
        schedule(c)
    }

    /** Arms one alarm: the next greeting/reminder time today, otherwise just after midnight. */
    fun schedule(c: Context) {
        val list = load(c).filter { it.optBoolean("enabled", true) }
        val alarms = c.getSystemService(AlarmManager::class.java)
        val pending = PendingIntent.getBroadcast(c, 7007,
            Intent(c, BirthdayReceiver::class.java).setAction(ACTION),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        if (list.isEmpty()) { alarms.cancel(pending); return }
        val now = Calendar.getInstance()
        val today = jalaliOf(now)
        val tomorrow = jalaliOf(shifted(now, 1))
        val after = jalaliOf(shifted(now, 2))
        var next = shifted(now, 1).apply {
            set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 1); set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
        }.timeInMillis
        for (b in list) {
            val wanted = matches(b, today, tomorrow) || (b.optBoolean("remind", true) && matches(b, tomorrow, after))
            if (!wanted) continue
            val due = (now.clone() as Calendar).apply {
                set(Calendar.HOUR_OF_DAY, dueMinutes(b) / 60); set(Calendar.MINUTE, dueMinutes(b) % 60)
                set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
            }.timeInMillis
            if (due > now.timeInMillis && due < next) next = due
        }
        try {
            if (Build.VERSION.SDK_INT < 31 || alarms.canScheduleExactAlarms())
                alarms.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, next, pending)
            else alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, next, pending)
        } catch (_: SecurityException) {
            alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, next, pending)
        }
    }

    /** "Send now" from the birthday screen, e.g. for a birthday added after its time today. */
    fun sendNow(c: Context, id: String): Boolean {
        val b = load(c).firstOrNull { it.optString("id") == id } ?: return false
        val queued = SmsCore.queue(c, b.optString("number"), render(b, jalaliOf(Calendar.getInstance())[0]), b.optInt("sim", -1), 0)
        SmsCore.dispatch(c, queued)
        return true
    }
}

class BirthdayReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val pending = goAsync()
        Thread {
            try { Birthdays.run(context) } catch (_: Exception) { } finally { pending.finish() }
        }.start()
    }
}
