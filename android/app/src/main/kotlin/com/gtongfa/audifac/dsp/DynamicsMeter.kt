package com.gtongfa.audifac.dsp

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.roundToInt
import kotlin.math.sqrt

/**
 * Measures, while a song is decoded for its loudness:
 *  - its dynamic range, DR14-style (Pleasurize Music Foundation): 3 s
 *    blocks; per channel, the second-highest block peak over the RMS (×√2)
 *    of the loudest 20 % of blocks, in dB; channels averaged, rounded;
 *  - the highest frequency with real content (average spectrum of 4096-point
 *    windows, one every second) and whether it ends in a brick wall — a
 *    lossless file cut sharply below 20 kHz was most likely made from an
 *    MP3 / AAC ("fake lossless"). Old recordings roll off gently instead.
 */
class DynamicsMeter(private val sampleRate: Int, private val channels: Int) {
    private val blockFrames = sampleRate * 3
    private var inBlock = 0
    private val sumSq = DoubleArray(channels)
    private val peak = DoubleArray(channels)
    private val blockRms = Array(channels) { ArrayList<Double>() }
    private val blockPeak = Array(channels) { ArrayList<Double>() }

    // Spectrum: a window of the mono mix every second.
    private val window = DoubleArray(FFT)
    private var filled = 0
    private var sinceWindow = 0
    private val power = DoubleArray(FFT / 2 + 1)
    private var windows = 0
    private val hann = DoubleArray(FFT) { 0.5 - 0.5 * cos(2 * PI * it / (FFT - 1)) }

    fun add(samples: FloatArray, frames: Int) {
        var i = 0
        for (f in 0 until frames) {
            var mono = 0.0
            for (c in 0 until channels) {
                val x = samples[i + c].toDouble()
                sumSq[c] += x * x
                val a = abs(x)
                if (a > peak[c]) peak[c] = a
                mono += x
            }
            i += channels
            if (++inBlock == blockFrames) endBlock()
            // Spectrum windows: FFT consecutive frames, once a second.
            if (sinceWindow >= sampleRate - FFT) {
                window[filled++] = mono / channels
                if (filled == FFT) {
                    addWindow()
                    filled = 0
                    sinceWindow = 0
                }
            } else {
                sinceWindow++
            }
        }
    }

    private fun endBlock() {
        for (c in 0 until channels) {
            blockRms[c] += sqrt(2 * sumSq[c] / inBlock)
            blockPeak[c] += peak[c]
            sumSq[c] = 0.0
            peak[c] = 0.0
        }
        inBlock = 0
    }

    private fun addWindow() {
        val re = DoubleArray(FFT) { window[it] * hann[it] }
        val im = DoubleArray(FFT)
        fft.transform(re, im, inverse = false)
        for (k in power.indices) power[k] += re[k] * re[k] + im[k] * im[k]
        windows++
    }

    /** DR value (e.g. 12), or null for songs under two blocks or silence. */
    fun dr(): Int? {
        if (blockRms[0].size < 2) return null
        var sum = 0.0
        for (c in 0 until channels) {
            val rms = blockRms[c].sortedDescending()
            val top = rms.take(max(1, (rms.size * 0.2).roundToInt()))
            val loud = sqrt(top.sumOf { it * it } / top.size)
            val peaks = blockPeak[c].sortedDescending()
            val second = peaks[1]
            if (loud <= 1e-9 || second <= 1e-9) return null
            sum += 20 * log10(second / loud)
        }
        return (sum / channels).roundToInt()
    }

    /** Spectrum in dB per bin (average over the windows), smoothed over about 200 Hz. */
    private fun spectrumDb(): DoubleArray? {
        if (windows == 0) return null
        val hzPerBin = sampleRate.toDouble() / FFT
        val half = max(1, (100 / hzPerBin).roundToInt())
        val db = DoubleArray(power.size) { k -> 10 * log10(power[k] / windows + 1e-30) }
        return DoubleArray(db.size) { k ->
            var s = 0.0
            var n = 0
            for (j in max(0, k - half)..minOf(db.size - 1, k + half)) {
                s += db[j]
                n++
            }
            s / n
        }
    }

    /** (highest frequency with content in Hz, ends in a brick wall), or null without a spectrum. */
    fun cutoff(): Pair<Int, Boolean>? {
        val s = spectrumDb() ?: return null
        val hzPerBin = sampleRate.toDouble() / FFT
        // Reference: the music's level between 1 and 10 kHz.
        val lo = (1000 / hzPerBin).toInt()
        val hi = minOf(s.size - 1, (10_000 / hzPerBin).toInt())
        val ref = (lo..hi).map { s[it] }.sorted()[(hi - lo) / 2]
        // A lowpass brick wall: the steepest drop (about 1 kHz either side)
        // above 8 kHz, if it is steep enough.
        val step = (1000 / hzPerBin).roundToInt()
        val gap = (200 / hzPerBin).roundToInt()
        var bestK = -1
        var bestDrop = 0.0
        for (k in (8000 / hzPerBin).toInt() until s.size - step - 1) {
            var below = 0.0
            var above = 0.0
            for (j in gap..step) {
                below += s[k - j]
                above += s[k + j]
            }
            val drop = (below - above) / (step - gap + 1)
            if (drop > bestDrop) {
                bestDrop = drop
                bestK = k
            }
        }
        if (bestK >= 0 && bestDrop >= WALL_DB) return (bestK * hzPerBin).roundToInt() to true
        // No wall: the highest frequency clearly above both the music's
        // level − 75 dB and the noise floor (quiet songs reach the latter).
        val noise = (lo until s.size).map { s[it] }.sorted()[(s.size - lo) / 10]
        val floor = max(ref - CONTENT_BELOW_DB, noise + 6)
        var k = s.size - 1
        while (k > lo && s[k] < floor) k--
        return (k * hzPerBin).roundToInt() to false
    }

    companion object {
        private const val FFT = 4096
        private val fft = Fft(FFT)

        /** Content counts down to this far below the music's mid-band level. */
        private const val CONTENT_BELOW_DB = 75.0

        /** A drop at least this steep (average over about a kHz either side) is a lowpass brick wall. */
        private const val WALL_DB = 20.0

        /** Lossless files cut below this (with a brick wall) were likely made from a lossy file. */
        const val SUSPICIOUS_BELOW_HZ = 20_000
    }
}
