package com.gtongfa.audifac.extract

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.log10
import kotlin.math.sin
import kotlin.math.sqrt

class DsdToPcmTest {
    /** 2nd-order sigma-delta modulator: PCM sine → 1-bit DSD bytes (MSB first). */
    private fun dsd(freq: Double, seconds: Double, amp: Double, rate: Int = 2_822_400): ByteArray {
        val samples = (seconds * rate).toInt() / 8 * 8
        val out = ByteArray(samples / 8)
        var v1 = 0.0
        var v2 = 0.0
        var y = 1.0
        for (n in 0 until samples) {
            val x = amp * sin(2 * PI * freq * n / rate)
            v1 += x - y
            v2 += v1 - y
            y = if (v2 >= 0) 1.0 else -1.0
            if (y > 0) out[n / 8] = (out[n / 8].toInt() or (0x80 ushr (n % 8))).toByte()
        }
        return out
    }

    private fun convert(bytes: ByteArray, rate: Int = 2_822_400, lsbFirst: Boolean = false): FloatArray {
        val c = DsdToPcm(rate, 1, lsbFirst)
        val out = FloatArray(bytes.size / c.decimation2 + 1)
        val n = c.process(0, bytes, 0, bytes.size, 1, out, 0, 1)
        return out.copyOf(n)
    }

    /** Amplitude of [freq] (Goertzel-style projection) over the settled second half. */
    private fun amplitude(pcm: FloatArray, freq: Double, rate: Int = DsdToPcm.OUTPUT_RATE): Double {
        val from = pcm.size / 2
        var re = 0.0
        var im = 0.0
        for (i in from until pcm.size) {
            re += pcm[i] * cos(2 * PI * freq * i / rate)
            im += pcm[i] * sin(2 * PI * freq * i / rate)
        }
        return 2 * sqrt(re * re + im * im) / (pcm.size - from)
    }

    private fun rms(pcm: FloatArray): Double {
        val from = pcm.size / 2
        var s = 0.0
        for (i in from until pcm.size) s += pcm[i].toDouble() * pcm[i]
        return sqrt(s / (pcm.size - from))
    }

    @Test
    fun outputRateAndDecimation() {
        assertEquals(176_400, DsdToPcm(2_822_400, 2, true).outputRate)
        assertEquals(2, DsdToPcm(2_822_400, 2, true).decimation2) // DSD64
        assertEquals(4, DsdToPcm(5_644_800, 2, true).decimation2) // DSD128
        assertEquals(8, DsdToPcm(11_289_600, 2, true).decimation2) // DSD256
    }

    @Test
    fun recoversA1kHzSineAtTheRightLevel() {
        val pcm = convert(dsd(1000.0, 0.5, amp = 0.5))
        assertEquals(176_400 / 2.0, pcm.size.toDouble(), 2.0)
        assertEquals(0.5, amplitude(pcm, 1000.0), 0.02)
        // Noise + distortion in the audible band (0–20 kHz) must be far below
        // the sine. (DSD's own noise rises above ~30 kHz by design.) The limit
        // here (~72 dB) is this test's simple undithered 2nd-order modulator —
        // the converter itself is exact to ~−120 dB; real DSD masters use
        // 5th–7th order modulators.
        val snrDb = audibleSnrDb(pcm, 1000.0)
        assertTrue("audible-band SNR $snrDb dB", snrDb > 65)
    }

    /**
     * DFT of 8192 settled samples with a 4-term Blackman-Harris window (−92 dB
     * side lobes, so the tone's own leakage doesn't count as noise): sine bins
     * vs everything else up to 20 kHz.
     */
    private fun audibleSnrDb(pcm: FloatArray, freq: Double, rate: Int = DsdToPcm.OUTPUT_RATE): Double {
        val n = 8192
        val from = pcm.size - n
        val x = DoubleArray(n) { i ->
            val a = 2 * PI * i / (n - 1)
            pcm[from + i] * (0.35875 - 0.48829 * cos(a) + 0.14128 * cos(2 * a) - 0.01168 * cos(3 * a))
        }
        val binHz = rate.toDouble() / n
        val signalBin = (freq / binHz).toInt()
        var signal = 0.0
        var noise = 0.0
        for (k in 1..(20_000 / binHz).toInt()) {
            var re = 0.0
            var im = 0.0
            for (i in 0 until n) {
                re += x[i] * cos(2 * PI * k * i / n)
                im -= x[i] * sin(2 * PI * k * i / n)
            }
            val p = re * re + im * im
            if (kotlin.math.abs(k - signalBin) <= 6) signal += p else noise += p
        }
        return 10 * log10(signal / noise)
    }

    @Test
    fun audioBandIsFlat() {
        val ref = amplitude(convert(dsd(1000.0, 0.3, 0.4)), 1000.0)
        for (f in listOf(10_000.0, 20_000.0)) {
            val a = amplitude(convert(dsd(f, 0.3, 0.4)), f)
            val db = 20 * log10(a / ref)
            assertTrue("$f Hz: $db dB", db > -0.5 && db < 0.5)
        }
    }

    @Test
    fun dsd128WorksToo() {
        val pcm = convert(dsd(1000.0, 0.3, 0.5, rate = 5_644_800), rate = 5_644_800)
        assertEquals(0.5, amplitude(pcm, 1000.0), 0.02)
    }

    @Test
    fun lsbFirstMatchesMsbFirst() {
        val msb = dsd(440.0, 0.05, 0.3)
        val lsb = ByteArray(msb.size) { (Integer.reverse(msb[it].toInt() and 0xFF) ushr 24).toByte() }
        assertArrayEquals(convert(msb), convert(lsb, lsbFirst = true), 0f)
    }

    @Test
    fun silencePatternGivesSilence() {
        val pcm = convert(ByteArray(100_000) { 0x69 })
        assertTrue(pcm.drop(1000).all { kotlin.math.abs(it) < 1e-3f })
    }
}

class DsdToPcmBenchmark {
    @Test
    fun throughput() {
        val seconds = 10
        val bytesPerCh = 2_822_400 / 8 * seconds
        val rnd = java.util.Random(1)
        val left = ByteArray(bytesPerCh).also { rnd.nextBytes(it) }
        val right = ByteArray(bytesPerCh).also { rnd.nextBytes(it) }
        val out = FloatArray(bytesPerCh / 2 + 16)
        repeat(2) { // warm-up + measured run
            val c = DsdToPcm(2_822_400, 2, true)
            val t = System.nanoTime()
            c.process(0, left, 0, bytesPerCh, 1, out, 0, 1)
            c.process(1, right, 0, bytesPerCh, 1, out, 0, 1)
            val ms = (System.nanoTime() - t) / 1e6
            println("DSD64 stereo ${seconds}s converted in ${"%.0f".format(ms)} ms → ${"%.1f".format(seconds * 1000 / ms)}× real time")
        }
    }
}
