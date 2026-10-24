package com.gtongfa.audifac.dsp

import kotlin.math.sqrt

/**
 * Folds surround files (3 to 8 channels) to stereo before any processing,
 * so the EQ, stereo tools, crossfeed and convolution work on what is heard.
 * ITU-R BS.775 coefficients: front left / right at 0 dB, centre and
 * surrounds at −3 dB into each side, a back centre split between both, LFE
 * left out. Power-normalised (the limiter catches peaks that add up).
 *
 * Channel orders as Android decoders deliver them:
 * 3 FL FR FC · 4 FL FR BL BR · 5 FL FR FC BL BR · 6 FL FR FC LFE BL BR ·
 * 7 FL FR FC LFE BC SL SR · 8 FL FR FC LFE BL BR SL SR.
 */
object Downmix {
    /** The app's setting (on: fold to stereo; off: Android gets every channel). */
    @Volatile
    var enabled = true

    private const val M3 = 0.70710678

    fun applies(channels: Int) = enabled && channels in 3..8

    /** [left][input channel] and [right][input channel] gains for a layout of [channels]. */
    fun matrix(channels: Int): Array<DoubleArray> {
        val l = DoubleArray(channels)
        val r = DoubleArray(channels)
        l[0] = 1.0
        r[1] = 1.0
        when (channels) {
            3 -> { l[2] = M3; r[2] = M3 }
            4 -> { l[2] = M3; r[3] = M3 }
            5 -> { l[2] = M3; r[2] = M3; l[3] = M3; r[4] = M3 }
            6 -> { l[2] = M3; r[2] = M3; l[4] = M3; r[5] = M3 }
            7 -> { l[2] = M3; r[2] = M3; l[4] = 0.5; r[4] = 0.5; l[5] = M3; r[6] = M3 }
            8 -> { l[2] = M3; r[2] = M3; l[4] = M3; r[5] = M3; l[6] = M3; r[7] = M3 }
        }
        // Power-normalised: a sound in every channel keeps its loudness.
        val norm = 1 / sqrt(l.sumOf { it * it })
        for (i in 0 until channels) {
            l[i] *= norm
            r[i] *= norm
        }
        return arrayOf(l, r)
    }

    private var cached: Pair<Int, Array<DoubleArray>>? = null

    /** [frames] interleaved frames of [inChannels] from [src] → stereo into [dst] at sample [dstOffset]. */
    fun mix(src: FloatArray, inChannels: Int, dst: FloatArray, dstOffset: Int, frames: Int) {
        val m = cached?.takeIf { it.first == inChannels }?.second ?: matrix(inChannels).also { cached = inChannels to it }
        val l = m[0]
        val r = m[1]
        var s = 0
        var d = dstOffset
        for (f in 0 until frames) {
            var a = 0.0
            var b = 0.0
            for (c in 0 until inChannels) {
                val x = src[s + c].toDouble()
                a += l[c] * x
                b += r[c] * x
            }
            dst[d] = a.toFloat()
            dst[d + 1] = b.toFloat()
            s += inChannels
            d += 2
        }
    }
}
