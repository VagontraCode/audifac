package com.gtongfa.audifac.dsp

import kotlin.math.abs
import kotlin.math.exp
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow

/**
 * Processes interleaved float PCM in place:
 * volume matching → preamp → parametric EQ → mono / balance → crossfeed → limiter.
 *
 * Settings changes cross-fade from the old to the new filter chain so moving a
 * slider never clicks. When the settings are transparent the samples are left
 * untouched (bit-exact pass-through in the float domain).
 */
class DspProcessor(
    private val sampleRate: Int,
    private val channels: Int,
    private val source: () -> Pair<DspConfig, Long> = { (if (DspEngine.bypass) DspConfig.OFF else DspEngine.config) to DspEngine.version * 2 + (if (DspEngine.bypass) 1 else 0) },
) {
    private class Chain(val config: DspConfig, sampleRate: Int, val channels: Int) {
        val transparent = config.isTransparent
        val preamp = 10.0.pow(config.preampDb / 20.0)
        val coefficients = config.bands.map { Coefficients.of(it, sampleRate) }
        /** filters[channel][band] */
        val filters = Array(channels) { coefficients.map { Biquad(it) }.toTypedArray() }

        // Balance: attenuate the opposite side linearly.
        val leftGain = if (config.balance > 0) 1.0 - config.balance else 1.0
        val rightGain = if (config.balance < 0) 1.0 + config.balance else 1.0

        // Crossfeed: low-passed opposite channel mixed in (bs2b-style), level
        // from about -16 dB (0.15) to -6 dB (0.5), loudness-compensated.
        val crossfeedLevel = if (config.crossfeed > 0) 0.15 + 0.35 * config.crossfeed else 0.0
        val crossfeedPole = exp(-2.0 * Math.PI * 700.0 / sampleRate)
        var lpLeft = 0.0
        var lpRight = 0.0

        fun inheritState(old: Chain) {
            for (ch in filters.indices) {
                val mine = filters[ch]
                val theirs = old.filters.getOrNull(ch) ?: continue
                for (i in mine.indices) {
                    if (i < theirs.size && config.bands[i].type == old.config.bands[i].type) {
                        mine[i].copyStateFrom(theirs[i])
                    }
                }
            }
            lpLeft = old.lpLeft
            lpRight = old.lpRight
        }

        /** Processes one frame from [inBuf] into [outBuf] (both [channels] long). */
        fun frame(inBuf: DoubleArray, outBuf: DoubleArray) {
            if (transparent) {
                for (ch in 0 until channels) outBuf[ch] = inBuf[ch]
                return
            }
            for (ch in 0 until channels) {
                var x = inBuf[ch] * preamp
                for (f in filters[ch]) x = f.process(x)
                outBuf[ch] = x
            }
            if (channels == 2) {
                if (config.mono) {
                    val m = (outBuf[0] + outBuf[1]) * 0.5
                    outBuf[0] = m
                    outBuf[1] = m
                }
                outBuf[0] *= leftGain
                outBuf[1] *= rightGain
                if (crossfeedLevel > 0) {
                    lpLeft = outBuf[0] + crossfeedPole * (lpLeft - outBuf[0])
                    lpRight = outBuf[1] + crossfeedPole * (lpRight - outBuf[1])
                    val norm = 1.0 / (1.0 + crossfeedLevel)
                    val l = (outBuf[0] + crossfeedLevel * lpRight) * norm
                    val r = (outBuf[1] + crossfeedLevel * lpLeft) * norm
                    outBuf[0] = l
                    outBuf[1] = r
                }
            }
        }
    }

    private var version = Long.MIN_VALUE
    private var current: Chain? = null
    private var previous: Chain? = null
    private var fadePos = 0
    private val fadeLength = max(256, sampleRate / 50) // ~20 ms

    // Peak limiter (linked across channels): instant attack, ~80 ms release.
    private val ceiling = 0.989 // -0.1 dBFS
    private val release = exp(-1.0 / (0.08 * sampleRate))
    private var limiterGain = 1.0

    // Volume matching gain (linear): glides ~5 ms to its target.
    private var gain = 1.0
    private var gainTarget = 1.0
    private val gainGlide = 1.0 - exp(-1.0 / (0.005 * sampleRate))

    /** Sets the track's volume matching gain; [immediate] skips the glide (new playback). */
    fun setGain(linear: Double, immediate: Boolean) {
        gainTarget = linear
        if (immediate) gain = linear
    }

    private val inFrame = DoubleArray(channels)
    private val outCurrent = DoubleArray(channels)
    private val outPrevious = DoubleArray(channels)

    private fun refresh() {
        val (config, v) = source()
        if (v == version) return
        version = v
        val next = Chain(config, sampleRate, channels)
        current?.let { next.inheritState(it) }
        previous = current
        current = next
        fadePos = if (previous == null) fadeLength else 0
    }

    /** True when the current settings leave audio untouched (caller may skip work). */
    fun isPassThrough(): Boolean {
        refresh()
        val c = current
        return c != null && c.transparent && previous == null && limiterGain == 1.0 &&
            gain == 1.0 && gainTarget == 1.0
    }

    /** Processes [frameCount] interleaved frames starting at sample [offset]. */
    fun process(samples: FloatArray, frameCount: Int, offset: Int = 0) {
        refresh()
        val chain = current ?: return
        // Never limit untouched audio: keeps pass-through bit-exact.
        // A volume boost can clip even with the EQ off.
        val useLimiter = chain.config.limiter &&
            ((chain.config.enabled && !chain.transparent) || gainTarget > 1.0 || gain > 1.0)
        var idx = offset
        for (frame in 0 until frameCount) {
            if (gain != gainTarget) {
                gain += (gainTarget - gain) * gainGlide
                if (abs(gainTarget - gain) < 1e-6) gain = gainTarget
            }
            val g = gain
            for (ch in 0 until channels) inFrame[ch] = samples[idx + ch] * g

            chain.frame(inFrame, outCurrent)
            val prev = previous
            if (prev != null) {
                prev.frame(inFrame, outPrevious)
                val t = fadePos.toDouble() / fadeLength
                for (ch in 0 until channels) outCurrent[ch] = outPrevious[ch] * (1 - t) + outCurrent[ch] * t
                if (++fadePos >= fadeLength) previous = null
            }

            if (useLimiter || limiterGain < 1.0) {
                var peak = 0.0
                for (ch in 0 until channels) peak = max(peak, abs(outCurrent[ch]))
                // Release towards unity first, then clamp: never above the ceiling.
                val released = min(1.0, 1.0 - (1.0 - limiterGain) * release)
                limiterGain = if (useLimiter && peak * released > ceiling) ceiling / peak else released
                for (ch in 0 until channels) outCurrent[ch] *= limiterGain
            }

            for (ch in 0 until channels) samples[idx + ch] = outCurrent[ch].toFloat()
            idx += channels
        }
    }

    fun reset() {
        current?.filters?.forEach { ch -> ch.forEach { it.reset() } }
        current?.lpLeft = 0.0
        current?.lpRight = 0.0
        previous = null
        limiterGain = 1.0
    }
}
