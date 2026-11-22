package ir.honarmardomi.payamyar

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.Telephony
import android.widget.RemoteViews

class InboxWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        val pending = goAsync()
        Thread { try { refresh(context) } finally { pending.finish() } }.start()
    }

    companion object {
        const val OPEN_RECENT = "ir.honarmardomi.payamyar.OPEN_RECENT"
        // Called on the SMS worker or provider thread. The launcher never gets message text.
        fun refresh(c: Context) {
            val manager = AppWidgetManager.getInstance(c) ?: return
            val ids = manager.getAppWidgetIds(ComponentName(c, InboxWidget::class.java))
            if (ids.isEmpty()) return
            val prefs = c.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val unread = if (SmsCore.isDefault(c) && !prefs.getBoolean("flutter.appLock", false)) runCatching {
                c.contentResolver.query(Telephony.Sms.Inbox.CONTENT_URI, arrayOf("_id"), "read=0", null, null)?.use { it.count }
            }.getOrNull() else null
            val views = RemoteViews(c.packageName, R.layout.payamyar_widget)
            val title = unread?.let { java.text.NumberFormat.getInstance(java.util.Locale.forLanguageTag("fa")).format(it) + " پیام خوانده‌نشده" }
            views.setTextViewText(R.id.inbox, title ?: c.getString(R.string.widget_title))
            fun open(id: Int, action: String) {
                val intent = Intent(c, MainActivity::class.java).setAction(action)
                if (action == Intent.ACTION_SENDTO) intent.data = Uri.parse("smsto:")
                views.setOnClickPendingIntent(id, PendingIntent.getActivity(c, id, intent,
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT))
            }
            open(R.id.inbox, Intent.ACTION_MAIN)
            open(R.id.new_sms, Intent.ACTION_SENDTO)
            open(R.id.recent_sms, OPEN_RECENT)
            manager.updateAppWidget(ids, views)
        }
    }
}
