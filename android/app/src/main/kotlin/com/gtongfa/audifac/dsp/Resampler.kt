package com.gtongfa.audifac.dsp

import kotlin.math.PI
import kotlin.math.ceil
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * High-quality sample-rate converter: polyphase windowed-sinc (Kaiser), the
 * rational ratio [outRate] / [inRate] exactly, linear phase. Passband flat to
 * ~95 % of the lower rate's Nyquist (21 kHz at 44.1 kHz), stopband ≈ −90 dB.
 *
 * Streaming: [process] takes interleaved frames and leaves the output in
 * [out]; state carries over between calls (and between songs at the same
 * rates, so gapless stays gapless). The filter's delay is compensated: output
 * frame k is input time k / outRate, and [flush] delivers the last real
 * frames (feeding silence through the filter).
 */
class Resampler(
    val inRate: Int,
    val outRate: Int,
    private val channels: Int,
    /** Use the NEON loop for stereo (verified against this Kotlin code on first use). */
    private val native: Boolean = channels == 2 && nativeVerified,
) {
    private val up: Int // L: phases
    private val down: Int // M
    private val taps: Int // per phase
    private val table: FloatArray // [phase * taps + j], j = 0 is the newest input
    private val tableRev: FloatArray // the same, oldest input first (native loop)
    private val delay: Long // filter delay, in high-rate samples

    init {
        val g = gcd(inRate, outRate)
        up = outRate / g
        down = inRate / g
        // Downsampling narrows the passband relative to the input: more taps.
        taps = min(MAX_TAPS, ceil(BASE_TAPS * maxOf(1.0, down.toDouble() / up)).toInt())
        val length = taps * up
        // Cutoff (cycles per high-rate sample) between the passband edge and
        // the lower rate's Nyquist.
        val nyquist = 0.5 / maxOf(up, down)
        val cutoff = nyquist * CUTOFF
        // Centred on a whole high-rate sample, so the delay is exact (an even
        // length leaves the last tap at zero).
        val half = (length - 1) / 2
        val center = half.toDouble()
        val i0Beta = besselI0(BETA)
        val h = DoubleArray(length) { n ->
            val t = n - center
            val sinc = if (t == 0.0) 2 * cutoff else sin(2 * PI * cutoff * t) / (PI * t)
            val r = t / half
            val window = besselI0(BETA * sqrt(maxOf(0.0, 1 - r * r))) / i0Beta
            sinc * window * up // × L: zero-stuffing lowered the level by L
        }
        table = FloatArray(length)
        for (p in 0 until up) for (j in 0 until taps) table[p * taps + j] = h[j * up + p].toFloat()
        tableRev = FloatArray(length)
        for (p in 0 until up) for (j in 0 until taps) tableRev[p * taps + j] = table[p * taps + taps - 1 - j]
        delay = half.toLong()
    }

    /** Interleaved output of the last [process] / [flush] call. */
    var out = FloatArray(0)
        private set

    // Input history per channel; global input index of hist[0] is histStart.
    private val hist = Array(channels) { FloatArray(0) }
    private var histStart = 0L
    private var histLen = 0
    private var inCount = 0L // real input frames taken
    private var outCount = 0L // output frames produced

    /** Real input frames taken since the last reset / flush. */
    val taken: Long get() = inCount

    /** Output frames produced since the last reset / flush. */
    val produced: Long get() = outCount

    init {
        reset()
    }

    /** Back to silence (after a seek). */
    fun reset() {
        // taps − 1 zeros before input frame 0.
        histStart = -(taps - 1).toLong()
        histLen = taps - 1
        for (c in 0 until channels) {
            if (hist[c].size < taps * 4) hist[c] = FloatArray(taps * 4)
            hist[c].fill(0f, 0, histLen)
        }
        inCount = 0
        outCount = 0
    }

    /** Resamples [frames] interleaved frames of [input] from sample [offset]; returns the output frame count (in [out]). */
    fun process(input: FloatArray, frames: Int, offset: Int = 0): Int {
        append(frames) { c, i -> input[offset + i * channels + c] }
        inCount += frames
        return produce(Long.MAX_VALUE)
    }

    /** Ends the stream: the output for every input frame taken, then back to silence. */
    fun flush(): Int {
        val total = ceilDiv(inCount * up, down.toLong())
        append(taps) { _, _ -> 0f }
        val n = produce(total - outCount)
        reset()
        return n
    }

    private inline fun append(frames: Int, sample: (channel: Int, frame: Int) -> Float) {
        // Drop history no longer needed by the next output.
        val nextIn = Math.floorDiv(outCount * down + delay, up.toLong())
        val keepFrom = nextIn - taps + 1
        val drop = (keepFrom - histStart).coerceIn(0, histLen.toLong()).toInt()
        if (drop > 0) {
            for (c in 0 until channels) System.arraycopy(hist[c], drop, hist[c], 0, histLen - drop)
            histStart += drop
            histLen -= drop
        }
        if (histLen + frames > hist[0].size) {
            for (c in 0 until channels) hist[c] = hist[c].copyOf(maxOf(histLen + frames, hist[c].size * 2))
        }
        for (c in 0 until channels) {
            val h = hist[c]
            for (i in 0 until frames) h[histLen + i] = sample(c, i)
        }
        histLen += frames
    }

    private fun produce(limit: Long): Int {
        val lastIn = histStart + histLen - 1
        var n = 0
        // Capacity: outputs this input can yield.
        val possible = (((lastIn + 1) * up - delay) / down - outCount + 1).coerceAtLeast(0)
        val max = min(possible, limit).toInt()
        if (out.size < max * channels) out = FloatArray(max * channels)
        if (native && max > 0) {
            val made = NativeDsp.produceStereo(tableRev, taps, up, down, delay, hist[0], hist[1], histStart, lastIn, outCount, max, out)
            outCount += made
            return made
        }
        while (n < max) {
            val pos = outCount * down + delay
            val i = Math.floorDiv(pos, up.toLong())
            if (i > lastIn) break
            val phase = (pos - i * up).toInt()
            val base = (i - histStart).toInt() // index of x[i] in hist
            val t0 = phase * taps
            if (channels == 2) {
                // Stereo (nearly every song): both channels in one pass.
                val l = hist[0]
                val r = hist[1]
                var accL = 0f
                var accR = 0f
                var k = base
                for (j in t0 until t0 + taps) {
                    val w = table[j]
                    accL += w * l[k]
                    accR += w * r[k]
                    k--
                }
                out[n * 2] = accL
                out[n * 2 + 1] = accR
                n++
                outCount++
                continue
            }
            for (c in 0 until channels) {
                val h = hist[c]
                var acc = 0f
                var k = base
                for (j in 0 until taps) {
                    acc += table[t0 + j] * h[k]
                    k--
                }
                out[n * channels + c] = acc
            }
            n++
            outCount++
        }
        return n
    }

    companion object {
        private const val BASE_TAPS = 128
        private const val MAX_TAPS = 512
        private const val BETA = 9.0 // Kaiser: ≈ −90 dB stopband
        private const val CUTOFF = 0.955 // centre of the transition band, × Nyquist

        /** The NEON loop gives the Kotlin loop's output (checked once, on first use). */
        val nativeVerified: Boolean by lazy {
            if (!NativeDsp.loaded) return@lazy false
            try {
                val rnd = java.util.Random(1)
                val input = FloatArray(4096 * 2) { rnd.nextFloat() * 2 - 1 }
                val a = Resampler(44_100, 48_000, 2, native = true)
                val b = Resampler(44_100, 48_000, 2, native = false)
                val na = a.process(input, 4096)
                val nb = b.process(input, 4096)
                val same = na == nb && (0 until na * 2).all { kotlin.math.abs(a.out[it] - b.out[it]) < 1e-4f }
                if (same) NativeDsp.info("native resampler (NEON) verified, in use") else NativeDsp.warn("native resampler disagrees with the Kotlin one: not used")
                same
            } catch (t: Throwable) {
                NativeDsp.warn("native resampler failed ($t): not used")
                false
            }
        }

        /** Ratios whose phase table would be unreasonably large aren't resampled. */
        fun supports(inRate: Int, outRate: Int): Boolean {
            if (inRate <= 0 || outRate <= 0) return false
            return outRate / gcd(inRate, outRate) <= 1024
        }

        private fun gcd(a: Int, b: Int): Int = if (b == 0) a else gcd(b, a % b)

        private fun ceilDiv(a: Long, b: Long) = -Math.floorDiv(-a, b)

        private fun besselI0(x: Double): Double {
            var sum = 1.0
            var term = 1.0
            val q = x * x / 4
            var k = 1
            while (term > 1e-12 * sum) {
                term *= q / (k.toDouble() * k)
                sum += term
                k++
            }
            return sum
        }
    }
}

/**
 * The app's resampler setting. When on, songs are converted here to the rate
 * Android's mixer runs at, instead of by Android's own resampler. Only where
 * that rate is known — the phone speaker and headphone jack: Bluetooth runs at
 * its codec's rate and USB DACs at their own, so converting there would make
 * Android convert again. Every song then reaches the AudioTrack at one rate,
 * so songs of different rates also follow each other gaplessly.
 */
object Resampling {
    @Volatile
    var enabled = false

    private val mainOutputs = setOf(
        android.media.AudioDeviceInfo.TYPE_BUILTIN_SPEAKER,
        android.media.AudioDeviceInfo.TYPE_BUILTIN_EARPIECE,
        android.media.AudioDeviceInfo.TYPE_WIRED_HEADSET,
        android.media.AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
        android.media.AudioDeviceInfo.TYPE_LINE_ANALOG,
    )

    /** Rate to convert songs to, or null to leave them at their own rate. */
    fun targetRate(): Int? = if (enabled) mixerRate() else null

    /** The mixer rate of the current output, where known (tests replace it). */
    @Volatile
    var mixerRate: () -> Int? = {
        BluetoothOutput.mediaOutputType()?.takeIf { it in mainOutputs }?.let {
            BluetoothOutput.mixerRate()?.takeIf { rate -> rate in 8_000..384_000 }
        }
    }
}
