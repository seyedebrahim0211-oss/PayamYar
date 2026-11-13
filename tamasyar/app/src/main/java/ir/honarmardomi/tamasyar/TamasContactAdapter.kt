package ir.honarmardomi.tamasyar

import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.BaseAdapter
import android.widget.LinearLayout
import android.widget.TextView

/** Recycles views: only the visible contacts are drawn even for very large books. */
class TamasContactAdapter(
    private val context: Context,
    private val onOpen: (TamasContact) -> Unit,
    private val isFavorite: (TamasContact) -> Boolean
) : BaseAdapter() {
    private val items = mutableListOf<TamasContact>()
    private val prefs = TamasPreferences(context)

    fun submit(list: List<TamasContact>) {
        items.clear()
        items.addAll(list)
        notifyDataSetChanged()
    }
    override fun getCount(): Int = items.size
    override fun getItem(position: Int): TamasContact = items[position]
    override fun getItemId(position: Int): Long = items[position].id
    override fun hasStableIds(): Boolean = true

    private data class Holder(
        val avatar: TextView,
        val name: TextView,
        val detail: TextView,
        val favorite: TextView
    )
    private fun dp(value: Int) = TamasStyle.dp(context, value)
    private fun styledText(size: Float, weight: Boolean, color: Int): TextView =
        TextView(context).apply {
            textSize = size * prefs.scale()
            setTextColor(color)
            gravity = Gravity.CENTER_VERTICAL
            TamasStyle.apply(this, context, weight)
            maxLines = 1
            ellipsize = android.text.TextUtils.TruncateAt.END
        }

    override fun getView(position: Int, convertView: View?, parent: ViewGroup): View {
        val row: LinearLayout
        val h: Holder
        if (convertView is LinearLayout && convertView.tag is Holder) {
            row = convertView
            h = row.tag as Holder
        } else {
            val ink = if (prefs.dark) Color.WHITE else TamasStyle.ink
            val muted = if (prefs.dark) Color.rgb(176, 199, 200) else TamasStyle.muted
            row = LinearLayout(context).apply {
                orientation = LinearLayout.HORIZONTAL
                layoutDirection = View.LAYOUT_DIRECTION_RTL
                gravity = Gravity.CENTER_VERTICAL
                setPadding(dp(12), dp(7), dp(12), dp(7))
                minimumHeight = dp(76)
            }
            val avatar = styledText(18f, true, TamasStyle.teal).apply {
                gravity = Gravity.CENTER
                background = TamasStyle.panel(context, TamasStyle.mist, 16,
                    TamasStyle.mist)
            }
            row.addView(avatar, LinearLayout.LayoutParams(dp(48), dp(48)))
            val labels = LinearLayout(context).apply {
                orientation = LinearLayout.VERTICAL
                layoutDirection = View.LAYOUT_DIRECTION_RTL
                setPadding(dp(10), 0, dp(10), 0)
            }
            val name = styledText(15.5f, true, ink)
            val detail = styledText(12.5f, false, muted)
            labels.addView(name)
            labels.addView(detail)
            row.addView(labels, LinearLayout.LayoutParams(0, -2, 1f))
            val favorite = styledText(20f, false, TamasStyle.gold).apply {
                gravity = Gravity.CENTER
            }
            row.addView(favorite, LinearLayout.LayoutParams(dp(36), dp(45)))
            h = Holder(avatar, name, detail, favorite)
            row.tag = h
            row.background = TamasStyle.panel(context,
                if (prefs.dark) Color.rgb(27, 46, 50) else Color.WHITE,
                14, if (prefs.dark) Color.rgb(49, 75, 77) else TamasStyle.line)
        }
        val contact = items[position]
        h.avatar.text = TamasPhone.initials(contact.name)
        h.name.text = contact.name
        h.detail.text = when (contact.phones.size) {
            0 -> "بدون شماره · نمایش جزئیات"
            1 -> contact.phones[0]
            else -> contact.phones[0] + "  ·  " + contact.phones.size + " شماره"
        }
        h.favorite.text = if (isFavorite(contact)) "★" else " "
        row.contentDescription = contact.name + "، " + h.detail.text
        row.setOnClickListener { onOpen(contact) }
        row.setPadding(dp(12), dp(8), dp(12), dp(8))
        return row
    }
}
