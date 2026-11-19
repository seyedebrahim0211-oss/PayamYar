package ir.honarmardomi.payamyar

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.LruCache
import org.json.JSONObject
import java.util.Locale

internal object BankLogos {
    private const val folder = "flutter_assets/assets/banks"
    private var aliases: JSONObject? = null
    private val pictures = LruCache<String, Bitmap>(10)
    private val separators = Regex("[\\s._‌-]")

    @Synchronized
    fun picture(c: Context, sender: String): Bitmap? {
        val key = sender.lowercase(Locale.ROOT).replace(separators, "")
            .replace('ك', 'ک').replace('ي', 'ی')
        if (key.isEmpty() || key.startsWith("+") || key.startsWith("09")) return null
        return try {
            val catalog = aliases ?: c.assets.open("$folder/senders.json").bufferedReader().use {
                JSONObject(it.readText())
            }.also { aliases = it }
            val bank = catalog.optString(key)
            if (bank.isEmpty()) return null
            pictures.get(bank) ?: c.assets.open("$folder/$bank.png").use {
                BitmapFactory.decodeStream(it)
            }?.also { pictures.put(bank, it) }
        } catch (_: java.io.IOException) { null }
    }
}
