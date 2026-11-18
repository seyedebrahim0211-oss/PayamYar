package ir.honarmardomi.payamyar

import android.content.SharedPreferences
import android.graphics.*
import android.graphics.drawable.Drawable
import androidx.core.graphics.ColorUtils
import java.util.Locale
import kotlin.math.min

/** SMS sender IDs are the only source identifier available to this app. */
internal enum class MessengerSender(val title: String, val color: Int) {
    EITAA("ایتا", 0xFFD56A21.toInt()),
    BALE("بله", 0xFF209476.toInt()),
    TELEGRAM("تلگرام", 0xFF2388BD.toInt()),
    WHATSAPP("واتساپ", 0xFF398653.toInt());

    fun selectedColor(settings: SharedPreferences): Int {
        val saved = settings.getString("flutter.bannerSenderTints", null) ?: return color
        return try {
            org.json.JSONObject(saved).optLong(name, color.toLong()).toInt() or android.graphics.Color.BLACK
        } catch (_: org.json.JSONException) { color }
    }

    companion object {
        fun fromKey(key: String?) = values().firstOrNull { it.name == key }
        fun fromAddress(address: String): MessengerSender? = when (address.trim().lowercase(Locale.ROOT)) {
            "eitaa", "eita", "ایتا" -> EITAA
            "bale", "بله" -> BALE
            "telegram", "تلگرام" -> TELEGRAM
            "whatsapp", "واتساپ", "واتس‌اپ" -> WHATSAPP
            else -> null
        }
    }
}

/** Gradients are cached until the view changes size. Paint opacity is reset for every layer. */
internal class GlassSurface(
    private val tint: Int, private val density: Float, private val corner: Float,
    private val bubbles: Boolean, private val opacity: Float, private val edge: Float,
    private val shine: Float, private val avatar: Boolean = false, private val round: Boolean = false
) : Drawable() {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val outer = RectF()
    private val inner = RectF()
    private val clip = Path()
    private val rimPath = Path()
    private var outerRadius = 0f
    private var radius = 0f
    private var rim: Shader? = null
    private var face: Shader? = null
    private var gloss: Shader? = null
    private fun mix(to: Int, amount: Float) = ColorUtils.blendARGB(tint, to, amount)

    override fun onBoundsChange(bounds: Rect) {
        super.onBoundsChange(bounds)
        outer.set(bounds)
        if (outer.isEmpty) return
        outerRadius = if (round) min(outer.width(), outer.height()) / 2f
            else min(corner * density, outer.height() / 2f)
        val inset = if (avatar) density * 1.5f else density * (2f + 4f * edge)
        inner.set(outer)
        inner.inset(inset, inset)
        if (inner.isEmpty) return
        radius = (outerRadius - inset).coerceAtLeast(0f)
        clip.reset()
        clip.addRoundRect(inner, radius, radius, Path.Direction.CW)
        rimPath.reset()
        rimPath.fillType = Path.FillType.EVEN_ODD
        rimPath.addRoundRect(outer, outerRadius, outerRadius, Path.Direction.CW)
        rimPath.addPath(clip)
        rim = LinearGradient(outer.left, outer.top, outer.right, outer.bottom,
            intArrayOf(mix(Color.WHITE, .59f), mix(0xFFF5E8C8.toInt(), .83f), mix(Color.WHITE, .34f)),
            null, Shader.TileMode.CLAMP)
        // Keep text legible over busy wallpaper, even at the lowest glass setting.
        val alpha = if (avatar) (255f * opacity).toInt() else (255f * (.65f + .35f * opacity)).toInt()
        face = LinearGradient(inner.right, inner.top, inner.left, inner.bottom,
            ColorUtils.setAlphaComponent(mix(Color.BLACK, .18f), alpha),
            ColorUtils.setAlphaComponent(mix(Color.BLACK, .47f), alpha), Shader.TileMode.CLAMP)
        gloss = LinearGradient(0f, inner.top, 0f, inner.top + min(inner.height(), 36 * density),
            Color.argb((shine * 56).toInt(), 255, 255, 255), Color.TRANSPARENT, Shader.TileMode.CLAMP)
    }
    override fun draw(canvas: Canvas) {
        if (inner.isEmpty) return
        paint.color = Color.WHITE
        paint.style = Paint.Style.FILL
        paint.shader = rim
        // Draw only the rim so the face can transmit a little of the actual backdrop.
        canvas.drawPath(rimPath, paint)
        paint.shader = face
        canvas.drawRoundRect(inner, radius, radius, paint)
        paint.shader = gloss
        canvas.drawRoundRect(inner, radius, radius, paint)
        paint.shader = null
        if (bubbles) {
            val layer = canvas.save()
            canvas.clipPath(clip)
            paint.style = Paint.Style.STROKE
            paint.strokeWidth = density
            paint.color = 0x33FFFFFF
            for (i in 0 until 7) {
                val x = inner.left + inner.width() * ((i * 37 + 9) % 100) / 100f
                val y = inner.top + inner.height() * ((i * 29 + 13) % 100) / 100f
                canvas.drawCircle(x, y, (5 + (i % 3) * 2) * density, paint)
            }
            canvas.restoreToCount(layer)
        }
    }
    override fun getOutline(outline: Outline) = outline.setRoundRect(bounds, outerRadius)
    override fun setAlpha(alpha: Int) {}
    override fun setColorFilter(filter: ColorFilter?) {}
    @Deprecated("Deprecated in Java") override fun getOpacity() = PixelFormat.TRANSLUCENT
}
