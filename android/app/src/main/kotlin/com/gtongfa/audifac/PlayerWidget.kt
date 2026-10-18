package com.gtongfa.audifac

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.BitmapShader
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Shader
import android.view.KeyEvent
import android.widget.RemoteViews
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Home-screen widget: artwork, title, artist, previous / play-pause / next.
 * The app pushes the state (channel `audifac/widget`); the buttons send media
 * keys to audio_service, so they work even when the app isn't open.
 */
class PlayerWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) = render(context)

    companion object {
        private const val PREFS = "audifac_widget"

        fun register(context: Context, messenger: BinaryMessenger) {
            MethodChannel(messenger, "audifac/widget").setMethodCallHandler { call, result ->
                if (call.method == "update") {
                    context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                        .putString("title", call.argument<String>("title"))
                        .putString("artist", call.argument<String>("artist"))
                        .putBoolean("playing", call.argument<Boolean>("playing") ?: false)
                        .putString("art", call.argument<String>("art"))
                        .apply()
                    render(context)
                    result.success(null)
                } else if (call.method == "pin") {
                    val manager = AppWidgetManager.getInstance(context)
                    val ok = android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O &&
                        manager.isRequestPinAppWidgetSupported &&
                        manager.requestPinAppWidget(ComponentName(context, PlayerWidget::class.java), null, null)
                    result.success(ok)
                } else {
                    result.notImplemented()
                }
            }
        }

        fun render(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, PlayerWidget::class.java))
            if (ids.isEmpty()) return
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val views = RemoteViews(context.packageName, R.layout.audifac_widget)
            val title = prefs.getString("title", null)
            views.setTextViewText(R.id.widget_title, title ?: context.getString(R.string.widget_idle))
            views.setTextViewText(R.id.widget_artist, prefs.getString("artist", null) ?: "")
            val playing = prefs.getBoolean("playing", false)
            views.setImageViewResource(R.id.widget_play, if (playing) R.drawable.widget_pause else R.drawable.widget_play)
            val art = prefs.getString("art", null)?.let { artwork(it) }
            if (art != null) views.setImageViewBitmap(R.id.widget_art, art)
            else views.setImageViewResource(R.id.widget_art, R.drawable.widget_art_placeholder)

            views.setOnClickPendingIntent(R.id.widget_prev, mediaKey(context, KeyEvent.KEYCODE_MEDIA_PREVIOUS))
            views.setOnClickPendingIntent(R.id.widget_play, mediaKey(context, KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE))
            views.setOnClickPendingIntent(R.id.widget_next, mediaKey(context, KeyEvent.KEYCODE_MEDIA_NEXT))
            val open = context.packageManager.getLaunchIntentForPackage(context.packageName)
            if (open != null) {
                views.setOnClickPendingIntent(
                    R.id.widget_root,
                    PendingIntent.getActivity(context, 0, open, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT),
                )
            }
            manager.updateAppWidget(ids, views)
        }

        private fun mediaKey(context: Context, keyCode: Int): PendingIntent {
            val intent = Intent(Intent.ACTION_MEDIA_BUTTON)
                .setComponent(ComponentName(context, "com.ryanheise.audioservice.MediaButtonReceiver"))
                .putExtra(Intent.EXTRA_KEY_EVENT, KeyEvent(KeyEvent.ACTION_DOWN, keyCode))
            return PendingIntent.getBroadcast(context, keyCode, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        }

        /** The cached artwork file, small and with rounded corners (RemoteViews can't clip). */
        private fun artwork(uriOrPath: String): Bitmap? {
            val path = uriOrPath.removePrefix("file://")
            val file = File(android.net.Uri.decode(path))
            if (!file.isFile) return null
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(file.path, bounds)
            val size = 168
            var sample = 1
            while (bounds.outWidth / (sample * 2) >= size && bounds.outHeight / (sample * 2) >= size) sample *= 2
            val src = BitmapFactory.decodeFile(file.path, BitmapFactory.Options().apply { inSampleSize = sample }) ?: return null
            val scaled = Bitmap.createScaledBitmap(src, size, size, true)
            val out = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
            val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { shader = BitmapShader(scaled, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP) }
            Canvas(out).drawRoundRect(RectF(0f, 0f, size.toFloat(), size.toFloat()), 36f, 36f, paint)
            return out
        }
    }
}
