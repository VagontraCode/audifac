package com.gtongfa.audifac.dsp

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.pow
import kotlin.math.tan

/**
 * EBU R128 / ITU-R BS.1770-4 integrated loudness and sample peak.
 *
 * K-weighting (shelf + high-pass, coefficients derived for any sample rate as
 * in libebur128), 400 ms blocks every 100 ms, absolute gate −70 LUFS,
 * relative gate −10 LU.
 */
class LoudnessMeter(sampleRate: Int, private val channels: Int) {
    private class Filter(val b0: Double, val b1: Double, val b2: Double, val a1: Double, val a2: Double) {
        var z1 = 0.0
        var z2 = 0.0
    }

    private val shelf = Array(channels) { shelfFilter(sampleRate) }
    private val highPass = Array(channels) { highPassFilter(sampleRate) }

    /** BS.1770 channel weights: surround ×1.41, LFE ignored (5.1 = L R C LFE Ls Rs). */
    private val weights = DoubleArray(channels) { ch ->
        when {
            channels == 6 && ch == 3 -> 0.0
            channels >= 5 && ch >= 3 -> 1.41
            else -> 1.0
        }
    }

    private val quarter = max(1, sampleRate / 10) // 100 ms
    private val quarterEnergy = DoubleArray(channels)
    private var quarterFrames = 0

    /** The last 4 quarters' weighted energy (a 400 ms block). */
    private val recent = DoubleArray(4)
    private var quarters = 0

    /** Mean square of every 400 ms block (75 % overlap). */
    private var blocks = DoubleArray(1024)
    private var blockCount = 0

    var peak = 0.0
        private set

    /** Interleaved float frames. */
    fun add(samples: FloatArray, frames: Int, offset: Int = 0) {
        var done = 0
        while (done < frames) {
            // Up to the end of the current 100 ms quarter, one channel at a
            // time: a tight loop with the filter state in locals.
            val n = minOf(frames - done, quarter - quarterFrames)
            val start = offset + done * channels
            for (ch in 0 until channels) runChannel(ch, samples, start + ch, n)
            done += n
            quarterFrames += n
            if (quarterFrames == quarter) endQuarter()
        }
    }

    private fun runChannel(ch: Int, samples: FloatArray, first: Int, n: Int) {
        val s = shelf[ch]
        val h = highPass[ch]
        val sb0 = s.b0; val sb1 = s.b1; val sb2 = s.b2; val sa1 = s.a1; val sa2 = s.a2
        val ha1 = h.a1; val ha2 = h.a2
        var s1 = s.z1; var s2 = s.z2
        var h1 = h.z1; var h2 = h.z2
        var energy = 0.0
        var pk = peak
        var i = first
        val step = channels
        repeat(n) {
            val x = samples[i].toDouble()
            i += step
            val a = abs(x)
            if (a > pk) pk = a
            val y = sb0 * x + s1
            s1 = sb1 * x - sa1 * y + s2
            s2 = sb2 * x - sa2 * y
            // High-pass: b = (1, −2, 1).
            val z = y + h1
            h1 = -2 * y - ha1 * z + h2
            h2 = y - ha2 * z
            energy += z * z
        }
        s.z1 = s1; s.z2 = s2
        h.z1 = h1; h.z2 = h2
        quarterEnergy[ch] += energy
        peak = pk
    }

    private fun endQuarter() {
        var e = 0.0
        for (ch in 0 until channels) {
            e += weights[ch] * quarterEnergy[ch] / quarter
            quarterEnergy[ch] = 0.0
        }
        quarterFrames = 0
        recent[quarters % 4] = e
        quarters++
        if (quarters >= 4) {
            if (blockCount == blocks.size) blocks = blocks.copyOf(blocks.size * 2)
            blocks[blockCount++] = recent.sum() / 4
        }
    }

    /** Integrated loudness in LUFS; null when the audio is silent or shorter than 400 ms. */
    fun integratedLufs(): Double? {
        val absGate = energyOf(-70.0)
        var sum = 0.0
        var n = 0
        for (i in 0 until blockCount) if (blocks[i] > absGate) { sum += blocks[i]; n++ }
        if (n == 0) return null
        val relGate = sum / n * 10.0.pow(-10.0 / 10)
        sum = 0.0
        n = 0
        for (i in 0 until blockCount) if (blocks[i] > absGate && blocks[i] > relGate) { sum += blocks[i]; n++ }
        if (n == 0) return null
        return loudnessOf(sum / n)
    }

    companion object {
        /** ReplayGain 2.0 reference level. */
        const val REFERENCE_LUFS = -18.0

        fun loudnessOf(energy: Double) = -0.691 + 10 * log10(energy)
        fun energyOf(lufs: Double) = 10.0.pow((lufs + 0.691) / 10)

        private fun shelfFilter(rate: Int): Filter {
            val f0 = 1681.974450955533
            val g = 3.999843853973347
            val q = 0.7071752369554196
            val k = tan(PI * f0 / rate)
            val vh = 10.0.pow(g / 20)
            val vb = vh.pow(0.4996667741545416)
            val a0 = 1 + k / q + k * k
            return Filter(
                b0 = (vh + vb * k / q + k * k) / a0,
                b1 = 2 * (k * k - vh) / a0,
                b2 = (vh - vb * k / q + k * k) / a0,
                a1 = 2 * (k * k - 1) / a0,
                a2 = (1 - k / q + k * k) / a0,
            )
        }

        private fun highPassFilter(rate: Int): Filter {
            val f0 = 38.13547087602444
            val q = 0.5003270373238773
            val k = tan(PI * f0 / rate)
            val a0 = 1 + k / q + k * k
            return Filter(1.0, -2.0, 1.0, a1 = 2 * (k * k - 1) / a0, a2 = (1 - k / q + k * k) / a0)
        }
    }
}
