package xyz.meshnotes.meshnotes

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
  private var widgetChannel: MethodChannel? = null
  private var widgetReady = false

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    widgetChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "xyz.meshnotes/recent_notes").also { channel ->
      channel.setMethodCallHandler { call, result ->
        when(call.method) {
          "takePendingLink" -> {
            widgetReady = true
            val link = intent.getStringExtra("widget_link")
            intent.removeExtra("widget_link")
            result.success(link)
          }
          "updateNotes" -> {
            getSharedPreferences("recent_notes_widget", MODE_PRIVATE).edit().putString("notes", call.arguments as String).apply()
            RecentNotesWidget.updateAll(this)
            result.success(null)
          }
          else -> result.notImplemented()
        }
      }
    }
  }

  override fun onNewIntent(intent: Intent) {
    super.onNewIntent(intent)
    setIntent(intent)
    val link = intent.getStringExtra("widget_link") ?: return
    if(widgetReady) {
      widgetChannel?.invokeMethod("openLink", link)
      intent.removeExtra("widget_link")
    }
  }

  override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
    widgetReady = false
    widgetChannel?.setMethodCallHandler(null)
    widgetChannel = null
    super.cleanUpFlutterEngine(flutterEngine)
  }
}
