package com.gtongfa.audifac.dsp

import kotlin.math.floor

/**
 * Reduces float samples to 16-bit with TPDF dither (triangular, ±1 LSB).
 * Plain rounding turns the rounding error into distortion that follows the
 * music (audible in fades and quiet passages); dither makes it a constant,
 * signal-independent noise floor near −96 dBFS, and keeps detail below one
 * LSB audible on average.
 */
class Dither {
    private var state = 0x9E3779B9.toInt()

    /** Uniform in [0, 1) (xorshift32: cheap, plenty for dither). */
    private fun uniform(): Float {
        var x = state
        x = x xor (x shl 13)
        x = x xor (x ushr 17)
        x = x xor (x shl 5)
        state = x
        return (x ushr 8) * (1f / (1 shl 24))
    }

    /** [x] in −1…1 → 16-bit, dithered. */
    fun toPcm16(x: Float): Short {
        val scaled = x.coerceIn(-1f, 1f) * 32767f + (uniform() + uniform() - 1f)
        return floor(scaled + 0.5f).toInt().coerceIn(-32768, 32767).toShort()
    }
}
