package com.gtongfa.audifac.dsp

import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.sqrt

enum class FilterType { PEAKING, LOW_SHELF, HIGH_SHELF, LOW_PASS, HIGH_PASS, NOTCH }

/** One EQ band as configured by the user. */
data class Band(
    val type: FilterType,
    val frequency: Double,
    val gainDb: Double,
    val q: Double,
)

/**
 * Normalised biquad coefficients (a0 = 1), from Robert Bristow-Johnson's
 * "Audio EQ Cookbook". The Dart side uses the exact same formulas to draw the
 * frequency-response curve.
 */
data class Coefficients(val b0: Double, val b1: Double, val b2: Double, val a1: Double, val a2: Double) {
    companion object {
        val IDENTITY = Coefficients(1.0, 0.0, 0.0, 0.0, 0.0)

        fun of(band: Band, sampleRate: Int): Coefficients {
            val f0 = band.frequency.coerceIn(10.0, sampleRate * 0.49)
            val q = band.q.coerceIn(0.05, 30.0)
            val a = 10.0.pow(band.gainDb / 40.0)
            val w0 = 2.0 * PI * f0 / sampleRate
            val cosW = cos(w0)
            val alpha = sin(w0) / (2.0 * q)
            val sqrtA2Alpha = 2.0 * sqrt(a) * alpha

            val (b0, b1, b2, a0, a1, a2) = when (band.type) {
                FilterType.PEAKING -> Six(
                    1 + alpha * a, -2 * cosW, 1 - alpha * a,
                    1 + alpha / a, -2 * cosW, 1 - alpha / a,
                )
                FilterType.LOW_SHELF -> Six(
                    a * ((a + 1) - (a - 1) * cosW + sqrtA2Alpha),
                    2 * a * ((a - 1) - (a + 1) * cosW),
                    a * ((a + 1) - (a - 1) * cosW - sqrtA2Alpha),
                    (a + 1) + (a - 1) * cosW + sqrtA2Alpha,
                    -2 * ((a - 1) + (a + 1) * cosW),
                    (a + 1) + (a - 1) * cosW - sqrtA2Alpha,
                )
                FilterType.HIGH_SHELF -> Six(
                    a * ((a + 1) + (a - 1) * cosW + sqrtA2Alpha),
                    -2 * a * ((a - 1) + (a + 1) * cosW),
                    a * ((a + 1) + (a - 1) * cosW - sqrtA2Alpha),
                    (a + 1) - (a - 1) * cosW + sqrtA2Alpha,
                    2 * ((a - 1) - (a + 1) * cosW),
                    (a + 1) - (a - 1) * cosW - sqrtA2Alpha,
                )
                FilterType.LOW_PASS -> Six(
                    (1 - cosW) / 2, 1 - cosW, (1 - cosW) / 2,
                    1 + alpha, -2 * cosW, 1 - alpha,
                )
                FilterType.HIGH_PASS -> Six(
                    (1 + cosW) / 2, -(1 + cosW), (1 + cosW) / 2,
                    1 + alpha, -2 * cosW, 1 - alpha,
                )
                FilterType.NOTCH -> Six(
                    1.0, -2 * cosW, 1.0,
                    1 + alpha, -2 * cosW, 1 - alpha,
                )
            }
            return Coefficients(b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0)
        }
    }

    private data class Six(
        val b0: Double, val b1: Double, val b2: Double,
        val a0: Double, val a1: Double, val a2: Double,
    )
}

/** Transposed direct form II biquad, double precision state, one channel. */
class Biquad(var c: Coefficients) {
    private var z1 = 0.0
    private var z2 = 0.0

    fun process(x: Double): Double {
        val y = c.b0 * x + z1
        z1 = c.b1 * x - c.a1 * y + z2
        z2 = c.b2 * x - c.a2 * y
        return y
    }

    fun copyStateFrom(other: Biquad) {
        z1 = other.z1
        z2 = other.z2
    }

    fun reset() {
        z1 = 0.0
        z2 = 0.0
    }
}
