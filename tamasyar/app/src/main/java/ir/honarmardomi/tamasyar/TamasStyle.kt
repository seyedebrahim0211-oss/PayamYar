package ir.honarmardomi.tamasyar

import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.view.View
import android.widget.TextView

/** Visual identity shared with PayamYar: turquoise, deep teal, parchment and gold. */
object TamasStyle {
    val teal = Color.rgb(8, 127, 129)       // PayamYar brand teal
    val tealLight = Color.rgb(18, 167, 162)
    val tealDeep = Color.rgb(5, 84, 90)
    val ink = Color.rgb(18, 62, 68)
    val paper = Color.rgb(250, 248, 243)
    val white = Color.WHITE
    val gold = Color.rgb(184, 134, 43)
    val goldLight = Color.rgb(255, 210, 122)
    val muted = Color.rgb(91, 112, 112)
    val line = Color.rgb(224, 232, 226)
    val mist = Color.rgb(235, 246, 241)
    val red = Color.rgb(177, 55, 72)
    val green = Color.rgb(24, 136, 102)

    private var font: Typeface? = null
    private var fontAttempted = false
    fun font(context: Context): Typeface {
        if (!fontAttempted) {
            fontAttempted = true
            font = try {
                Typeface.createFromAsset(context.assets, "Vazirmatn.ttf")
            } catch (_: Exception) { Typeface.DEFAULT }
        }
        return font ?: Typeface.DEFAULT
    }

    fun dp(context: Context, size: Int): Int =
        (context.resources.displayMetrics.density * size).toInt()

    fun panel(context: Context, color: Int = white, radius: Int = 18,
        border: Int = line, thickness: Int = 1): GradientDrawable =
        GradientDrawable().apply {
            cornerRadius = dp(context, radius).toFloat()
            setColor(color)
            setStroke(dp(context, thickness).coerceAtLeast(1), border)
        }

    fun tile(context: Context, radius: Int = 18): GradientDrawable =
        GradientDrawable(GradientDrawable.Orientation.TL_BR,
            intArrayOf(tealLight, teal, tealDeep)).apply {
            cornerRadius = dp(context, radius).toFloat()
        }

    fun apply(text: TextView, context: Context, bold: Boolean = false) {
        val family = font(context)
        text.typeface = Typeface.create(family, if (bold) Typeface.BOLD else Typeface.NORMAL)
        text.includeFontPadding = false
        text.textDirection = View.TEXT_DIRECTION_FIRST_STRONG
    }
}
