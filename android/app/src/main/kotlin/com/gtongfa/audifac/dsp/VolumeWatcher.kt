package com.gtongfa.audifac.dsp

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import androidx.core.content.ContextCompat

/**
 * Keeps [DspEngine.attenuationDb] at the media volume's level in dB (for
 * loudness compensation): Android broadcasts every volume change.
 */
object VolumeWatcher {
    private var audioManager: AudioManager? = null

    fun install(context: Context) {
        val am = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        audioManager = am
        ContextCompat.registerReceiver(
            context,
            object : BroadcastReceiver() {
                override fun onReceive(c: Context?, intent: Intent?) = update()
            },
            IntentFilter("android.media.VOLUME_CHANGED_ACTION"),
            ContextCompat.RECEIVER_NOT_EXPORTED,
        )
        update()
    }

    /** Re-reads the volume (also after the output changes). */
    fun update() {
        val am = audioManager ?: return
        try {
            val index = am.getStreamVolume(AudioManager.STREAM_MUSIC)
            val db = if (Build.VERSION.SDK_INT >= 28) {
                val type = BluetoothOutput.mediaOutputType() ?: AudioDeviceInfo.TYPE_BUILTIN_SPEAKER
                am.getStreamVolumeDb(AudioManager.STREAM_MUSIC, index, type).toDouble()
            } else {
                // Rough: Android's default curve spans about 60 dB.
                val max = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC).coerceAtLeast(1)
                -60.0 * (1 - index.toDouble() / max)
            }
            DspEngine.setAttenuation(if (db.isFinite()) -db else 100.0)
        } catch (_: Exception) {
        }
    }
}
