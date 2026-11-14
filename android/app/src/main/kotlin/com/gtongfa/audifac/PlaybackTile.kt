package com.gtongfa.audifac

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.drawable.Icon
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import android.view.KeyEvent

/**
 * Quick Settings tile: play / pause audifac from the notification shade.
 * Shows the current song (Android 10+) and whether it's playing, from the
 * state the app pushes for the home-screen widget ([PlayerWidget]).
 * Like the widget, a tap sends a media key to audio_service, so it also
 * resumes the last queue when the app isn't open.
 */
class PlaybackTile : TileService() {
    override fun onStartListening() = refresh()

    override fun onClick() {
        val prefs = getSharedPreferences(PlayerWidget.PREFS, Context.MODE_PRIVATE)
        val playing = !prefs.getBoolean("playing", false)
        for (action in intArrayOf(KeyEvent.ACTION_DOWN, KeyEvent.ACTION_UP)) {
            sendBroadcast(
                Intent(Intent.ACTION_MEDIA_BUTTON)
                    .setComponent(ComponentName(this, "com.ryanheise.audioservice.MediaButtonReceiver"))
                    .putExtra(Intent.EXTRA_KEY_EVENT, KeyEvent(action, KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE)),
            )
        }
        // Shown right away; the app confirms it with the next widget update.
        show(playing, prefs.getString("title", null))
    }

    private fun refresh() {
        val prefs = getSharedPreferences(PlayerWidget.PREFS, Context.MODE_PRIVATE)
        show(prefs.getBoolean("playing", false), prefs.getString("title", null))
    }

    private fun show(playing: Boolean, title: String?) {
        val tile = qsTile ?: return
        tile.state = if (playing) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        tile.label = getString(R.string.tile_label)
        tile.icon = Icon.createWithResource(this, R.drawable.tile_note)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) tile.subtitle = title
        tile.updateTile()
    }

    companion object {
        /** Asks the system to refresh the tile (if the user added it). */
        fun requestUpdate(context: Context) {
            try {
                requestListeningState(context, ComponentName(context, PlaybackTile::class.java))
            } catch (_: Exception) {
                // Some launchers / OEM builds refuse while the tile isn't added.
            }
        }
    }
}
