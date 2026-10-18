package com.gtongfa.audifac.dsp

import android.annotation.SuppressLint
import android.content.Context
import android.media.AudioAttributes
import android.media.AudioDeviceInfo
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioMixerAttributes
import android.os.Build
import android.util.Log
import androidx.annotation.RequiresApi
import androidx.media3.common.C

/**
 * Bit-perfect USB output (Android 14+): asks the system mixer to pass our
 * samples to a USB DAC untouched — no resampling, no mixing, no volume — at
 * the track's own rate and format.
 *
 * The DSP sink only uses it when its own processing is transparent (EQ off or
 * flat, no volume matching gain, no crossfade): then it hands the decoder's
 * original PCM straight to the AudioTrack.
 */
object BitPerfect {
    @Volatile
    var enabled = false

    @Volatile
    var context: Context? = null

    /** The bit-perfect mixer is set for the current track's format. */
    @Volatile
    var active = false
        private set

    /** Why it isn't active (shown in the signal path). */
    @Volatile
    var reason: String = "off"
        private set

    val supported: Boolean get() = Build.VERSION.SDK_INT >= 34

    private val media: AudioAttributes =
        AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA).setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build()

    private var lastDevice: AudioDeviceInfo? = null

    /**
     * Prepares the mixer for a track of [sampleRate] Hz, [channels] channels
     * and media3 [pcmEncoding]. Returns true when bit-perfect output is set.
     */
    fun prepare(sampleRate: Int, channels: Int, pcmEncoding: Int): Boolean {
        val ctx = context
        if (!enabled || ctx == null) return deactivate(if (!enabled) "off" else "no context")
        if (!supported) return deactivate("needs Android 14")
        return try {
            prepare34(ctx, sampleRate, channels, pcmEncoding)
        } catch (e: Exception) {
            Log.w(TAG, "bit-perfect failed: $e")
            deactivate("refused by the system")
        }
    }

    /// Back to the normal mixer (processing needed, or turned off).
    fun release(why: String) {
        deactivate(why)
    }

    @SuppressLint("NewApi")
    private fun deactivate(why: String): Boolean {
        reason = why
        if (active && supported) {
            try {
                val am = context?.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
                lastDevice?.let { am?.clearPreferredMixerAttributes(media, it) }
            } catch (_: Exception) {
            }
        }
        active = false
        return false
    }

    @RequiresApi(34)
    private fun prepare34(ctx: Context, sampleRate: Int, channels: Int, pcmEncoding: Int): Boolean {
        val am = ctx.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val usb = am.getDevices(AudioManager.GET_DEVICES_OUTPUTS).firstOrNull {
            it.type == AudioDeviceInfo.TYPE_USB_DEVICE || it.type == AudioDeviceInfo.TYPE_USB_HEADSET
        } ?: return deactivate("no USB DAC")
        // What the AudioTrack will receive: ExoPlayer's sink (float output on)
        // turns 24- and 32-bit integer PCM into float — which holds them exactly.
        val encodings = when (pcmEncoding) {
            C.ENCODING_PCM_16BIT -> listOf(AudioFormat.ENCODING_PCM_16BIT)
            C.ENCODING_PCM_24BIT, C.ENCODING_PCM_32BIT, C.ENCODING_PCM_FLOAT -> listOf(AudioFormat.ENCODING_PCM_FLOAT)
            else -> return deactivate("format not supported")
        }
        val candidates = am.getSupportedMixerAttributes(usb).filter { it.mixerBehavior == AudioMixerAttributes.MIXER_BEHAVIOR_BIT_PERFECT }
        val match = candidates.firstOrNull {
            it.format.sampleRate == sampleRate && it.format.encoding in encodings && it.format.channelCount == channels
        } ?: return deactivate(if (candidates.isEmpty()) "DAC has no bit-perfect mode" else "DAC can't do $sampleRate Hz in this format")
        val ok = am.setPreferredMixerAttributes(media, usb, match)
        if (!ok) return deactivate("refused by the system")
        lastDevice = usb
        active = true
        reason = "on"
        Log.i(TAG, "bit-perfect: $sampleRate Hz, encoding ${match.format.encoding}, ${usb.productName}")
        return true
    }

    private const val TAG = "AudifacDsp"
}
