package com.gtongfa.audifac.dsp

import kotlin.math.exp
import kotlin.math.log10
import kotlin.math.pow

/**
 * Gentle feed-forward compressor for noisy places and night listening:
 * soft knee, both channels linked (the stereo image doesn't shift), peak
 * envelope with 10 ms attack / 250 ms release, make-up gain for about half
 * the reduction at full scale so the average level stays similar.
 */
class Compressor(sampleRate: Int, val strength: Int) {
    private val thresholdDb: Double
    private val ratio: Double
    private val kneeDb = 6.0
    private val makeupDb: Double
    private val attack = exp(-1.0 / (0.010 * sampleRate))
    private val release = exp(-1.0 / (0.250 * sampleRate))
    private var envDb = -120.0

    init {
        when (strength) {
            1 -> { thresholdDb = -20.0; ratio = 2.0 }
            2 -> { thresholdDb = -24.0; ratio = 3.0 }
            else -> { thresholdDb = -30.0; ratio = 4.0 }
        }
        makeupDb = -thresholdDb * (1 - 1 / ratio) * 0.5
    }

    /** Gain reduction (dB, ≥ 0) for a level of [db] above or near the threshold. */
    fun reductionDb(db: Double): Double {
        val over = db - thresholdDb
        val slope = 1 - 1 / ratio
        return when {
            over <= -kneeDb / 2 -> 0.0
            over >= kneeDb / 2 -> over * slope
            else -> (over + kneeDb / 2).pow(2) / (2 * kneeDb) * slope
        }
    }

    /** Linear gain for a frame whose peak (both channels) is [peak]. */
    fun gain(peak: Double): Double {
        val db = if (peak > 1e-6) 20 * log10(peak) else -120.0
        envDb = if (db > envDb) db + (envDb - db) * attack else db + (envDb - db) * release
        return 10.0.pow((makeupDb - reductionDb(envDb)) / 20)
    }

    fun reset() {
        envDb = -120.0
    }
}
