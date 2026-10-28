package xyz.meshnotes.meshnotes

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import org.json.JSONArray

class RecentNotesWidget: AppWidgetProvider() {
  override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
    ids.forEach { update(context, manager, it) }
  }

  companion object {
    fun updateAll(context: Context) {
      val manager = AppWidgetManager.getInstance(context)
      manager.getAppWidgetIds(ComponentName(context, RecentNotesWidget::class.java)).forEach { update(context, manager, it) }
    }

    private fun action(context: Context, link: String): PendingIntent {
      val intent = Intent(context, MainActivity::class.java)
        .setAction(Intent.ACTION_VIEW).setData(Uri.parse(link))
        .putExtra("widget_link", link)
        .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
      return PendingIntent.getActivity(context, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }

    private fun update(context: Context, manager: AppWidgetManager, id: Int) {
      val views = RemoteViews(context.packageName, R.layout.recent_notes_widget)
      val raw = context.getSharedPreferences("recent_notes_widget", Context.MODE_PRIVATE).getString("notes", "[]")
      val notes = try { JSONArray(raw) } catch(_: Exception) { JSONArray() }
      val rows = intArrayOf(R.id.note_1, R.id.note_2, R.id.note_3)
      for(i in rows.indices) {
        val note = notes.optJSONObject(i)
        views.setViewVisibility(rows[i], if(note == null) View.GONE else View.VISIBLE)
        if(note != null) {
          views.setTextViewText(rows[i], note.optString("title", "Untitled note"))
          val link = Uri.Builder().scheme("meshnotes").authority("widget").appendPath("open").appendPath(note.getString("id")).build().toString()
          views.setOnClickPendingIntent(rows[i], action(context, link))
        }
      }
      views.setViewVisibility(R.id.empty_notes, if(notes.length() == 0) View.VISIBLE else View.GONE)
      views.setOnClickPendingIntent(R.id.new_note, action(context, "meshnotes://widget/new"))
      manager.updateAppWidget(id, views)
    }
  }
}
