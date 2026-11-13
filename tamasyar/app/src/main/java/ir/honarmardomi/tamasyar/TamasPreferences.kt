package ir.honarmardomi.tamasyar

import android.content.Context
import android.content.SharedPreferences

/**
 * Private, local-only appearance and update preferences; no contacts/calls or
 * identifiers are synchronized to the website or the SMS companion app.
 */
class TamasPreferences(context: Context) {
    private val appContext = context.applicationContext
    private val values: SharedPreferences = appContext.getSharedPreferences(
        "tamasyar_preferences", Context.MODE_PRIVATE
    )
    var autoUpdates: Boolean
        get() = values.getBoolean("auto_updates", true)
        set(v) = values.edit().putBoolean("auto_updates", v).apply()

    /** 0 = light; 1 = dark. */
    var dark: Boolean
        get() = isDark()
        set(v) { themeMode = if (v) 2 else 1 }

    /** 0 = compact; 1 = normal; 2 = large. */
    var textSize: Int
        get() = values.getInt("text_size", 1).coerceIn(0, 2)
        set(v) = values.edit().putInt("text_size", v.coerceIn(0, 2)).apply()

    var lastChecked: Long
        get() = values.getLong("last_checked", 0L)
        set(v) = values.edit().putLong("last_checked", v).apply()

    var lastNotifiedCode: Long
        get() = values.getLong("last_notified", 0L)
        set(v) = values.edit().putLong("last_notified", v).apply()

    var pendingApk: String
        get() = values.getString("pending_apk", "").orEmpty()
        set(v) = values.edit().putString("pending_apk", v).apply()

    /** Use the system's SIM chooser when multiple outgoing accounts exist. */
    var chooseSim: Boolean
        get() = values.getBoolean("choose_sim", true)
        set(v) = values.edit().putBoolean("choose_sim", v).apply()

    /** A local shortcut list, stored separately from the phone's contacts database. */
    fun favorites(): Set<String> = values.getStringSet("favorite_numbers", emptySet())
        .orEmpty().toSet()

    fun isFavorite(number: String): Boolean =
        favorites().contains(TamasPhone.normalize(number))

    fun toggleFavorite(number: String): Boolean {
        val id = TamasPhone.normalize(number)
        if (id.isEmpty()) return false
        val modified = favorites().toMutableSet()
        val added = if (id in modified) { modified.remove(id); false }
                    else { modified.add(id); true }
        values.edit().putStringSet("favorite_numbers", modified).apply()
        return added
    }

    /** 0=system, 1=light, 2=dark. Retains migration from earlier theme toggle. */
    var themeMode: Int
        get() = values.getInt("theme_mode",
            if (values.getBoolean("dark", false)) 2 else 1).coerceIn(0, 2)
        set(v) = values.edit().putInt("theme_mode", v.coerceIn(0, 2)).apply()

    fun isDark(): Boolean = when (themeMode) {
        2 -> true
        1 -> false
        else -> (appContext.resources.configuration.uiMode and
            android.content.res.Configuration.UI_MODE_NIGHT_MASK) ==
            android.content.res.Configuration.UI_MODE_NIGHT_YES
    }

    var favoritesFirst: Boolean
        get() = values.getBoolean("favorites_first", true)
        set(v) = values.edit().putBoolean("favorites_first", v).apply()

    var dialHaptics: Boolean
        get() = values.getBoolean("dial_haptics", true)
        set(v) = values.edit().putBoolean("dial_haptics", v).apply()

    var dialTones: Boolean
        get() = values.getBoolean("dial_tones", false)
        set(v) = values.edit().putBoolean("dial_tones", v).apply()

    var latinKeycaps: Boolean
        get() = values.getBoolean("latin_keycaps", false)
        set(v) = values.edit().putBoolean("latin_keycaps", v).apply()

    var confirmOutgoing: Boolean
        get() = values.getBoolean("confirm_outgoing", false)
        set(v) = values.edit().putBoolean("confirm_outgoing", v).apply()

    var startTab: Int
        get() = values.getInt("start_tab", 1).coerceIn(0, 2)
        set(v) = values.edit().putInt("start_tab", v.coerceIn(0, 2)).apply()

    var screenshotProtection: Boolean
        get() = values.getBoolean("protect_screenshots", false)
        set(v) = values.edit().putBoolean("protect_screenshots", v).apply()

    var showQuickContacts: Boolean
        get() = values.getBoolean("quick_contacts", true)
        set(v) = values.edit().putBoolean("quick_contacts", v).apply()

    fun scale(): Float = when (textSize) {
        0 -> 0.92f
        2 -> 1.16f
        else -> 1f
    }
}
