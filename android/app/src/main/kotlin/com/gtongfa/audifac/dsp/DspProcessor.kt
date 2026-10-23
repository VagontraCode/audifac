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
    val sampleRate: Int,
    val channels: Int,
    private val source: () -> Pair<DspConfig, Long> = { (if (DspEngine.bypass) DspConfig.OFF else DspEngine.config) to DspEngine.version * 2 + (if (DspEngine.bypass) 1 else 0) },
) {
    private class Chain(val config: DspConfig, sampleRate: Int, val channels: Int) {
        val transparent = config.isTransparent
        val preamp = 10.0.pow(config.preampDb / 20.0)
        /** Bands that change something (a 0 dB peak or shelf is skipped: e.g. Flat's ten). */
        // Linear phase: the bands run as one FIR after the chain, not here.
        val bandIndex = if (config.linearPhase) emptyList() else config.bands.indices.filterNot { i ->
            val b = config.bands[i]
            b.gainDb == 0.0 && (b.type == FilterType.PEAKING || b.type == FilterType.LOW_SHELF || b.type == FilterType.HIGH_SHELF)
        }
        val bands = bandIndex.map { config.bands[it] }
        val coefficients = bands.map { Coefficients.of(it, sampleRate) }
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

        // Stereo width (mid / side), polarity, channel delay.
        val width = config.width
        val signLeft = if (config.invertLeft) -1.0 else 1.0
        val signRight = if (config.invertRight) -1.0 else 1.0
        val delayFrames = Math.round(kotlin.math.abs(config.delayMs) * sampleRate / 1000.0).toInt()
        val delayChannel = if (config.delayMs > 0) 1 else 0
        /** Ring of the delayed channel's past samples (room for the longest delay). */
        var delayLine = DoubleArray((DspConfig.MAX_DELAY_MS * sampleRate / 1000.0).toInt() + 2)
        var delayPos = 0

        fun inheritState(old: Chain) {
            // Same band (by its place in the settings) and type: keep its state.
            val oldPos = HashMap<Int, Int>().apply { old.bandIndex.forEachIndexed { pos, band -> put(band, pos) } }
            for (ch in filters.indices) {
                val mine = filters[ch]
                val theirs = old.filters.getOrNull(ch) ?: continue
                for (i in mine.indices) {
                    val j = oldPos[bandIndex[i]] ?: continue
                    if (bands[i].type == old.bands[j].type) mine[i].copyStateFrom(theirs[j])
                }
            }
            lpLeft = old.lpLeft
            lpRight = old.lpRight
            // Keep the delay line (no click when settings change).
            if (old.delayLine.size == delayLine.size) {
                delayLine = old.delayLine.copyOf()
                delayPos = old.delayPos
            }
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
                if (width != 1.0) {
                    val m = (outBuf[0] + outBuf[1]) * 0.5
                    val s = (outBuf[0] - outBuf[1]) * 0.5 * width
                    outBuf[0] = m + s
                    outBuf[1] = m - s
                }
                outBuf[0] *= signLeft
                outBuf[1] *= signRight
                // The line always runs (so a later delay change starts from real audio).
                val line = delayLine
                line[delayPos] = outBuf[delayChannel]
                if (delayFrames > 0) {
                    var read = delayPos - delayFrames
                    if (read < 0) read += line.size
                    outBuf[delayChannel] = line[read]
                }
                delayPos = if (delayPos + 1 == line.size) 0 else delayPos + 1
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

    /** Gain below which the limiter counts as working (−0.01 dB). */
    private val limiting = 0.999
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
    fun isPassThrough(): Boolean = isGainPassThrough() && isEffectsPassThrough()

    /** No volume matching gain: [applyGain] may be skipped. */
    fun isGainPassThrough(): Boolean = gain == 1.0 && gainTarget == 1.0

    /** EQ and limiter leave audio untouched: [processEffects] may be skipped. */
    fun isEffectsPassThrough(): Boolean {
        refresh()
        val c = current
        return c != null && c.transparent && previous == null && limiterGain == 1.0 &&
            gain <= 1.0 && gainTarget <= 1.0
    }

    /** Volume matching gain, then EQ and limiter, on [frameCount] interleaved frames from sample [offset]. */
    fun process(samples: FloatArray, frameCount: Int, offset: Int = 0) {
        if (!isGainPassThrough()) applyGain(samples, frameCount, offset)
        processEffects(samples, frameCount, offset)
    }

    /**
     * Volume matching gain alone. The sink applies it as each song is decoded
     * (a crossfade mixes two songs, each with its own gain).
     */
    fun applyGain(samples: FloatArray, frameCount: Int, offset: Int = 0) {
        var idx = offset
        for (frame in 0 until frameCount) {
            if (gain != gainTarget) {
                gain += (gainTarget - gain) * gainGlide
                if (abs(gainTarget - gain) < 1e-6) gain = gainTarget
            }
            val g = gain
            for (ch in 0 until channels) samples[idx + ch] = (samples[idx + ch] * g).toFloat()
            idx += channels
        }
    }

    /**
     * EQ, mono / balance, crossfeed and limiter. The sink applies them as
     * audio leaves for the AudioTrack, after any crossfade reserve, so
     * settings changes are heard without that delay.
     */
    fun processEffects(samples: FloatArray, frameCount: Int, offset: Int = 0) {
        refresh()
        val chain = current ?: return
        // Never limit untouched audio: keeps pass-through bit-exact.
        // A volume boost can clip even with the EQ off.
        val useLimiter = chain.config.limiter &&
            ((chain.config.enabled && !chain.transparent) || gainTarget > 1.0 || gain > 1.0)
        compressor = chain.config.compressor.takeIf { chain.config.enabled && it > 0 }?.let { s ->
            compressor?.takeIf { it.strength == s } ?: Compressor(sampleRate, s)
        }
        val conv = convolverFor(chain.config.ir)
        val eq = eqConvolverFor(chain.config)
        if (conv != null || eq != null) {
            // Convolution works on blocks: EQ for the whole chunk, then the
            // impulse response, then the limiter.
            var idx = offset
            for (frame in 0 until frameCount) {
                eqFrame(chain, samples, idx)
                for (ch in 0 until channels) samples[idx + ch] = outCurrent[ch].toFloat()
                idx += channels
            }
            eq?.process(samples, frameCount, offset)
            conv?.process(samples, frameCount, offset)
            idx = offset
            for (frame in 0 until frameCount) {
                for (ch in 0 until channels) outCurrent[ch] = samples[idx + ch].toDouble()
                limitFrame(useLimiter)
                for (ch in 0 until channels) samples[idx + ch] = outCurrent[ch].toFloat()
                idx += channels
            }
            return
        }
        var idx = offset
        for (frame in 0 until frameCount) {
            eqFrame(chain, samples, idx)
            limitFrame(useLimiter)
            for (ch in 0 until channels) samples[idx + ch] = outCurrent[ch].toFloat()
            idx += channels
        }
    }

    /** One frame from [samples] at [idx] through the chain (cross-fading from the previous one) into outCurrent. */
    private fun eqFrame(chain: Chain, samples: FloatArray, idx: Int) {
        for (ch in 0 until channels) inFrame[ch] = samples[idx + ch].toDouble()
        chain.frame(inFrame, outCurrent)
        val prev = previous
        if (prev != null) {
            prev.frame(inFrame, outPrevious)
            val t = fadePos.toDouble() / fadeLength
            for (ch in 0 until channels) outCurrent[ch] = outPrevious[ch] * (1 - t) + outCurrent[ch] * t
            if (++fadePos >= fadeLength) previous = null
        }
    }

    /** Level statistics and the peak limiter on outCurrent. */
    private fun limitFrame(useLimiter: Boolean) {
        compressor?.let { c ->
            var p = 0.0
            for (ch in 0 until channels) p = max(p, abs(outCurrent[ch]))
            val g = c.gain(p)
            for (ch in 0 until channels) outCurrent[ch] *= g
        }
        var framePeak = 0.0
        for (ch in 0 until channels) framePeak = max(framePeak, abs(outCurrent[ch]))
        if (framePeak > statPeak) statPeak = framePeak
        if (useLimiter || limiterGain < 1.0) {
            // Release towards unity first, then clamp: never above the ceiling.
            val released = min(1.0, 1.0 - (1.0 - limiterGain) * release)
            limiterGain = if (useLimiter && framePeak * released > ceiling) ceiling / framePeak else released
            for (ch in 0 until channels) outCurrent[ch] *= limiterGain
            if (limiterGain < limiting) statLimited++
        } else if (framePeak > 1.0) {
            statClipped++
        }
        statFrames++
    }

    /** Dynamic range compression (before the limiter), kept while its strength doesn't change. */
    private var compressor: Compressor? = null

    // Linear-phase EQ: the bands as one FIR, updated (cross-faded) when they change.
    private var eqConvolver: Convolver? = null
    private var eqBands: List<Band>? = null

    private fun eqConvolverFor(config: DspConfig): Convolver? {
        val active = if (config.enabled && config.linearPhase && channels <= 2) {
            config.bands.filterNot { b ->
                b.gainDb == 0.0 && (b.type == FilterType.PEAKING || b.type == FilterType.LOW_SHELF || b.type == FilterType.HIGH_SHELF)
            }
        } else {
            emptyList()
        }
        if (active.isEmpty()) {
            eqConvolver?.close()
            eqConvolver = null
            eqBands = null
            return null
        }
        val c = eqConvolver
        if (c != null && active == eqBands) return c
        val fir = LinearPhaseEq.fir(active, sampleRate)
        eqBands = active
        if (c != null) {
            c.update(listOf(fir))
            return c
        }
        return Convolver(ImpulseResponse("eq", sampleRate, listOf(fir)), sampleRate, channels, normalise = false).also { eqConvolver = it }
    }

    // Convolution with the configured impulse response (kept while it doesn't change).
    private var convolver: Convolver? = null

    private fun convolverFor(ir: ImpulseResponse?): Convolver? {
        if (ir == null || channels > 2) {
            convolver?.close()
            convolver = null
            return null
        }
        val c = convolver
        if (c != null && c.ir === ir) return c
        c?.close()
        return Convolver(ir, sampleRate, channels).also { convolver = it }
    }

    // Level statistics since the last takeStats (the sink publishes them per song).
    private var statPeak = 0.0
    private var statLimited = 0L
    private var statClipped = 0L
    private var statFrames = 0L

    /** Peak before the limiter, frames limited, frames clipped (limiter off), frames seen; then starts over. */
    fun takeStats(): LevelStats = LevelStats(statPeak, statLimited, statClipped, statFrames).also {
        statPeak = 0.0
        statLimited = 0
        statClipped = 0
        statFrames = 0
    }

    fun reset() {
        current?.filters?.forEach { ch -> ch.forEach { it.reset() } }
        current?.lpLeft = 0.0
        current?.lpRight = 0.0
        convolver?.reset()
        eqConvolver?.reset()
        compressor?.reset()
        previous = null
        limiterGain = 1.0
    }
}

/** Levels the EQ produced: [peak] (linear, before the limiter), frames the limiter worked on, frames clipped. */
data class LevelStats(val peak: Double, val limited: Long, val clipped: Long, val frames: Long)
