package com.gtongfa.audifac.dsp

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.audio.DefaultAudioSink
import androidx.media3.exoplayer.audio.DefaultAudioTrackBufferSizeProvider
import com.ryanheise.just_audio.JustAudioHooks
import kotlin.math.max

/**
 * Bluetooth headphones take audio from the AudioTrack in bursts, and the
 * link itself adds jitter; with ExoPlayer's battery-friendly scheduling (the
 * loop sleeps until the buffer is half empty) that left too little margin and
 * gave short dropouts. While media plays to Bluetooth:
 *  - the AudioTrack buffer holds [BT_BUFFER_US] instead of ~0.3 s (taken when
 *    a track starts: on wired / speaker it stays small, so EQ changes are
 *    heard at once);
 *  - the playback loop wakes at least every [BT_MAX_SLEEP_US].
 */
@OptIn(UnstableApi::class)
object BluetoothOutput {
    private const val TAG = "AudifacDsp"
    const val BT_BUFFER_US = 750_000L
    const val BT_MAX_SLEEP_US = 50_000L

    @Volatile
    var active = false
        private set

    private var audioManager: AudioManager? = null

    fun install(context: Context) {
        val am = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        audioManager = am
        JustAudioHooks.audioTrackBufferSizeProvider = BufferSizes
        am.registerAudioDeviceCallback(object : AudioDeviceCallback() {
            override fun onAudioDevicesAdded(addedDevices: Array<out AudioDeviceInfo>) { update() }
            override fun onAudioDevicesRemoved(removedDevices: Array<out AudioDeviceInfo>) { update() }
        }, Handler(Looper.getMainLooper()))
        update()
    }

    /** Re-reads where media plays (also called when a track starts). */
    fun update(): Boolean {
        val am = audioManager ?: return false
        val bt = try {
            isBluetooth(routedType(am))
        } catch (e: Exception) {
            false
        }
        if (bt != active) Log.i(TAG, "media output ${if (bt) "is" else "is no longer"} Bluetooth")
        active = bt
        JustAudioHooks.maxDurationToProgressUs = if (bt) BT_MAX_SLEEP_US else 0
        return bt
    }

    private fun isBluetooth(type: Int?) = type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP ||
        type == 26 /* BLE_HEADSET */ || type == 27 /* BLE_SPEAKER */ || type == 30 /* BLE_BROADCAST */

    /** Type ([AudioDeviceInfo].TYPE_…) of the output media plays to, null if unknown. */
    fun mediaOutputType(): Int? {
        val am = audioManager ?: return null
        return try {
            routedType(am) ?: AudioDeviceInfo.TYPE_BUILTIN_SPEAKER
        } catch (e: Exception) {
            null
        }
    }

    /** Sample rate Android's mixer runs at for the main outputs (speaker, headphone jack). */
    fun mixerRate(): Int? = audioManager?.getProperty(AudioManager.PROPERTY_OUTPUT_SAMPLE_RATE)?.toIntOrNull()

    /** The device media is routed to (Android 13+), else the connected output media would use. */
    private fun routedType(am: AudioManager): Int? {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            try {
                val media = AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA).build()
                am.getAudioDevicesForAttributes(media).firstOrNull()?.let { return it.type }
            } catch (_: SecurityException) {
                // Not allowed on this build: fall back to the connected outputs.
            }
        }
        // Older Android: a connected Bluetooth A2DP / LE output takes media.
        return am.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
            .firstOrNull { isBluetooth(it.type) }?.type
    }

    private object BufferSizes : DefaultAudioSink.AudioTrackBufferSizeProvider {
        private val default = DefaultAudioTrackBufferSizeProvider.Builder().build()

        override fun getBufferSizeInBytes(
            minBufferSizeInBytes: Int,
            encoding: Int,
            outputMode: Int,
            pcmFrameSize: Int,
            sampleRate: Int,
            bitrate: Int,
            maxAudioTrackPlaybackSpeed: Double,
        ): Int {
            val size = default.getBufferSizeInBytes(
                minBufferSizeInBytes, encoding, outputMode, pcmFrameSize, sampleRate, bitrate, maxAudioTrackPlaybackSpeed,
            )
            if (outputMode != DefaultAudioSink.OUTPUT_MODE_PCM || pcmFrameSize <= 0 || !update()) return size
            val bt = (BT_BUFFER_US * sampleRate / C.MICROS_PER_SECOND * pcmFrameSize * maxAudioTrackPlaybackSpeed).toLong()
            return max(size.toLong(), bt).coerceAtMost(Int.MAX_VALUE.toLong()).toInt()
        }
    }
}
