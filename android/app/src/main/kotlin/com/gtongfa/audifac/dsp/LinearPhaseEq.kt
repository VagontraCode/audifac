package com.gtongfa.audifac.dsp

import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * The EQ as one linear-phase FIR: the combined magnitude of all bands, no
 * phase shift (every frequency delayed alike, by half the filter). Built on
 * a [TAPS]-point grid (≈ 5.9 Hz apart at 48 kHz), windowed (Kaiser) and run
 * by a [Convolver].
 */
object LinearPhaseEq {
    const val TAPS = 8192

    /** Delay the filter adds (frames), on top of the convolver's block. */
    const val DELAY = TAPS / 2

    /** The FIR for [bands] at [sampleRate] (length [TAPS], centred). */
    fun fir(bands: List<Band>, sampleRate: Int): FloatArray {
        val n = TAPS
        val coefficients = bands.map { Coefficients.of(it, sampleRate) }
        val re = DoubleArray(n)
        val im = DoubleArray(n)
        for (k in 0..n / 2) {
            val w = 2 * PI * k / n
            var mag = 1.0
            for (c in coefficients) mag *= magnitude(c, w)
            // Zero phase, shifted by n/2 (linear phase): × e^(−iwn/2) = (−1)^k.
            re[k] = if (k % 2 == 0) mag else -mag
            if (k in 1 until n / 2) re[n - k] = re[k]
        }
        Fft(n).transform(re, im, inverse = true)
        val beta = 8.0
        val i0Beta = besselI0(beta)
        return FloatArray(n) { t ->
            val x = 2.0 * t / n - 1
            val window = besselI0(beta * sqrt(maxOf(0.0, 1 - x * x))) / i0Beta
            (re[t] / n * window).toFloat()
        }
    }

    /** |H(e^jw)| of one biquad. */
    fun magnitude(c: Coefficients, w: Double): Double {
        val c1 = cos(w)
        val s1 = sin(w)
        val c2 = cos(2 * w)
        val s2 = sin(2 * w)
        val nr = c.b0 + c.b1 * c1 + c.b2 * c2
        val ni = -(c.b1 * s1 + c.b2 * s2)
        val dr = 1 + c.a1 * c1 + c.a2 * c2
        val di = -(c.a1 * s1 + c.a2 * s2)
        return sqrt((nr * nr + ni * ni) / (dr * dr + di * di))
    }

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
