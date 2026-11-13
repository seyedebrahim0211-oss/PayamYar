package ir.honarmardomi.tamasyar

import android.content.Context
import android.content.SharedPreferences

/**
 * Private, local-only appearance and update preferences; no contacts/calls or
 * identifiers are synchronized to the website or the SMS companion app.
 */
class TamasPreferences(context: Context) {
    private val values: SharedPreferences = context.getSharedPreferences(
        "tamasyar_preferences", Context.MODE_PRIVATE
    )
    var autoUpdates: Boolean
        get() = values.getBoolean("auto_updates", true)
        set(v) = values.edit().putBoolean("auto_updates", v).apply()

    /** 0 = light; 1 = dark. */
    var dark: Boolean
        get() = values.getBoolean("dark", false)
        set(v) = values.edit().putBoolean("dark", v).apply()

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

    fun scale(): Float = when (textSize) {
        0 -> 0.92f
        2 -> 1.16f
        else -> 1f
    }
}
