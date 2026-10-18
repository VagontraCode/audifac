package com.gtongfa.audifac.extract

import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.sin

/**
 * Converts 1-bit DSD (2.8224 MHz and multiples) to 176.4 kHz float PCM.
 *
 * One linear-phase low-pass FIR (Blackman-windowed sinc, 512 taps at DSD64,
 * scaled with the rate) evaluated **without multiplications**: every DSD byte
 * (8 one-bit samples) indexes a 256-entry table of pre-summed coefficients
 * for its position in the window, so one output sample costs one table read
 * per byte of the window. Flat to ~55 kHz, ~−74 dB from ~85 kHz (everything
 * that would alias into the 0–88 kHz output band).
 *
 * Levels are unchanged: 0 dB SACD (50 % modulation) ≈ −6 dBFS, as most
 * converters do.
 */
class DsdToPcm(
    val dsdRate: Int,
    private val channels: Int,
    /** DSF stores the earliest bit in the LSB; DFF in the MSB. */
    private val lsbFirst: Boolean,
) {
    val outputRate: Int = OUTPUT_RATE

    /** DSD bytes consumed per PCM output sample (2 for DSD64, 4 for DSD128…). */
    val decimation2: Int = max(1, dsdRate / 8 / OUTPUT_RATE)

    /** DSD samples (bits) per PCM output sample. */
    val totalDecimation: Int get() = 8 * decimation2

    /** Window length in bytes (64 at DSD64: 512 taps). */
    private val windowBytes = WINDOW_BYTES_DSD64 * max(1, dsdRate / DSD64)

    /** table[k * 256 + byte] = Σ taps of byte position k for that bit pattern. */
    private val table: FloatArray = buildTable()

    private class ChannelState(window: Int) {
        /** Byte history, written twice so the window is always contiguous. */
        val hist = IntArray(window * 2)
        var pos = 0
        var phase = 0
    }

    private val states = Array(channels) { ChannelState(windowBytes) }

    init {
        reset()
    }

    fun reset() {
        for (s in states) {
            s.hist.fill(SILENCE)
            s.pos = 0
            s.phase = 0
        }
    }

    /**
     * Feeds [count] DSD bytes of one [channel] (bytes [offset]…, every [stride]-th
     * byte) and writes PCM samples to [out] at [outOffset] + k·[outStride].
     * Returns how many PCM samples were written.
     */
    fun process(
        channel: Int,
        src: ByteArray,
        offset: Int,
        count: Int,
        stride: Int,
        out: FloatArray,
        outOffset: Int,
        outStride: Int,
    ): Int {
        val s = states[channel]
        val hist = s.hist
        val w = windowBytes
        val tab = table
        val reverse = lsbFirst
        val every = decimation2
        var pos = s.pos
        var phase = s.phase
        var written = 0
        var o = outOffset
        var i = offset
        for (n in 0 until count) {
            var b = src[i].toInt() and 0xFF
            if (reverse) b = REVERSE[b]
            i += stride
            hist[pos] = b
            hist[pos + w] = b
            pos = if (pos + 1 == w) 0 else pos + 1

            if (++phase == every) {
                phase = 0
                // Oldest byte is at hist[pos]; window = hist[pos until pos + w].
                var acc = 0f
                var t = 0
                var h = pos
                val end = pos + w
                while (h < end) {
                    acc += tab[t + hist[h]]
                    t += 256
                    h++
                }
                out[o] = acc
                o += outStride
                written++
            }
        }
        s.pos = pos
        s.phase = phase
        return written
    }

    private fun buildTable(): FloatArray {
        val taps = windowedSinc(windowBytes * 8, cutoff = CUTOFF_HZ.toDouble() / dsdRate)
        val t = FloatArray(windowBytes * 256)
        for (k in 0 until windowBytes) {
            for (byte in 0 until 256) {
                var sum = 0f
                for (bit in 0 until 8) {
                    // MSB = earliest sample within the byte (after LSB→MSB reversal).
                    val one = (byte shr (7 - bit)) and 1 == 1
                    sum += taps[k * 8 + bit] * (if (one) 1f else -1f)
                }
                t[k * 256 + byte] = sum
            }
        }
        return t
    }

    companion object {
        const val OUTPUT_RATE = 176_400
        private const val DSD64 = 2_822_400
        private const val WINDOW_BYTES_DSD64 = 64     // 512 taps
        private const val CUTOFF_HZ = 70_000
        /** DSD "digital silence" pattern (alternating bits). */
        private const val SILENCE = 0x69

        private val REVERSE = IntArray(256) { b -> Integer.reverse(b) ushr 24 }

        /** Blackman-windowed sinc low-pass, unity DC gain. [cutoff] in cycles/sample. */
        fun windowedSinc(length: Int, cutoff: Double): FloatArray {
            val m = length - 1
            val h = DoubleArray(length) { n ->
                val x = n - m / 2.0
                val sinc = if (x == 0.0) 2 * cutoff else sin(2 * PI * cutoff * x) / (PI * x)
                val w = 0.42 - 0.5 * cos(2 * PI * n / m) + 0.08 * cos(4 * PI * n / m)
                sinc * w
            }
            val sum = h.sum()
            return FloatArray(length) { (h[it] / sum).toFloat() }
        }
    }
}
