package com.gtongfa.audifac.dsp

import android.content.Context
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.ln
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sqrt

/**
 * What makes a song danceable, from a few excerpts of it (soirée builder):
 *  - tempo (BPM) and how sure we are: spectral-flux onsets, autocorrelation
 *    between 60 and 200 BPM, the half / double-time ambiguity settled
 *    towards the dance range (afrobeats / amapiano ≈ 100–115, coupé-décalé /
 *    ndombolo / makossa ≈ 120–140);
 *  - groove: how strong and regular the beat is (pulse clarity);
 *  - bass punch: kick / bass hits locked to the beat, and low-end share;
 *  - energy: loudness, how busy (onset density), brightness.
 *
 * Feed it excerpt by excerpt: [startExcerpt], then [format] / [add].
 */
class RhythmAnalyser {
    // Decimated mono at ≈ 11 kHz, analysed in [FRAME]-sample frames every [HOP].
    private var factor = 4
    private var rate = 11_025.0
    private var channels = 2
    private var acc = 0.0
    private var accCount = 0
    private val ring = DoubleArray(FRAME)
    private var filled = 0
    private var sinceHop = 0

    private val window = DoubleArray(FRAME) { 0.5 - 0.5 * cos(2 * PI * it / (FRAME - 1)) }
    private val fft = Fft(FRAME)
    private val re = DoubleArray(FRAME)
    private val im = DoubleArray(FRAME)
    private var previous: DoubleArray? = null

    /** Per excerpt: onset strength (all bands, bass band) per frame. */
    private val onsets = ArrayList<ArrayList<Double>>()
    private val bassOnsets = ArrayList<ArrayList<Double>>()

    // Energy measures, summed over frames.
    private val excerptRms = ArrayList<ArrayList<Double>>()
    private var bassShare = 0.0
    private var brightShare = 0.0
    private var spectralFrames = 0

    fun startExcerpt() {
        onsets.add(ArrayList())
        bassOnsets.add(ArrayList())
        excerptRms.add(ArrayList())
        previous = null
        filled = 0
        sinceHop = 0
        acc = 0.0
        accCount = 0
    }

    fun format(sampleRate: Int, channelCount: Int) {
        factor = max(1, (sampleRate / 11_025.0).roundToInt())
        rate = sampleRate.toDouble() / factor
        channels = max(1, channelCount)
    }

    fun add(samples: FloatArray, frames: Int) {
        if (onsets.isEmpty()) startExcerpt()
        var i = 0
        for (f in 0 until frames) {
            var m = 0.0
            for (c in 0 until channels) m += samples[i + c]
            i += channels
            // Boxcar decimation: crude but enough below ≈ 3 kHz.
            acc += m / channels
            if (++accCount < factor) continue
            push(acc / factor)
            acc = 0.0
            accCount = 0
        }
    }

    private fun push(x: Double) {
        ring[filled % FRAME] = x
        filled++
        if (filled < FRAME) return
        if (++sinceHop < HOP) return
        sinceHop = 0
        frame()
    }

    private fun frame() {
        val start = filled % FRAME
        var sq = 0.0
        for (k in 0 until FRAME) {
            val x = ring[(start + k) % FRAME]
            sq += x * x
            re[k] = x * window[k]
            im[k] = 0.0
        }
        excerptRms.last().add(sqrt(sq / FRAME))
        fft.transform(re, im, false)
        val bins = FRAME / 2
        val hzPerBin = rate / FRAME
        val bassTop = (150 / hzPerBin).toInt()
        val brightFrom = (2500 / hzPerBin).toInt()
        val mag = DoubleArray(bins)
        var total = 0.0
        var bass = 0.0
        var bright = 0.0
        for (k in 1 until bins) {
            val p = re[k] * re[k] + im[k] * im[k]
            mag[k] = ln(1 + 1000 * sqrt(p))
            total += p
            if (k <= bassTop) bass += p
            if (k >= brightFrom) bright += p
        }
        if (total > 1e-9) {
            bassShare += bass / total
            brightShare += bright / total
            spectralFrames++
        }
        val prev = previous
        var flux = 0.0
        var bassFlux = 0.0
        if (prev != null) {
            for (k in 1 until bins) {
                val d = mag[k] - prev[k]
                if (d > 0) {
                    flux += d
                    if (k <= bassTop) bassFlux += d
                }
            }
        }
        previous = mag
        onsets.last().add(flux)
        bassOnsets.last().add(bassFlux)
    }

    /** Frames per second of the onset envelope. */
    private val fps get() = rate / HOP

    class Result(
        val bpm: Double,
        /** 0…1: how clearly one tempo stands out. */
        val confidence: Double,
        val groove: Int,
        val bassPunch: Int,
        val energy: Int,
        val danceability: Int,
        /** Energy (0–100) of each excerpt, in order. */
        val excerptEnergy: List<Int>,
    ) {
        fun toMap(): Map<String, Any> = mapOf(
            "bpm" to bpm,
            "confidence" to confidence,
            "groove" to groove,
            "bassPunch" to bassPunch,
            "energy" to energy,
            "danceability" to danceability,
            "excerptEnergy" to excerptEnergy,
        )
    }

    /** Null without enough sound (silence, a few seconds). */
    fun result(): Result? {
        val envelopes = onsets.map { normalise(it) }.filter { it.size > MIN_FRAMES }
        if (envelopes.isEmpty()) return null
        val rms = excerptRms.flatten()
        val meanDb = 20 * log10(max(1e-9, sqrt(rms.sumOf { it * it } / max(1, rms.size))))
        if (meanDb < -60) return null

        val minLag = (fps * 60 / MAX_BPM).toInt()
        val maxLag = (fps * 60 / MIN_BPM).toInt() + 1
        val ac = autocorrelation(envelopes, maxLag * 4 + 2)
        if (ac[0] <= 1e-12) return null
        // Comb: a true beat also lines up 2, 3 and 4 beats later; a lag of
        // 1½ beats (3 eighths) doesn't at 4½ beats.
        fun at(x: Double): Double {
            val i = x.toInt().coerceIn(0, ac.size - 2)
            val f = (x - i).coerceIn(0.0, 1.0)
            return ac[i] * (1 - f) + ac[i + 1] * f
        }
        fun comb(lag: Double) = (at(lag) + 0.75 * at(2 * lag) + 0.5 * at(3 * lag) + 0.4 * at(4 * lag)) / (2.65 * ac[0])
        val score = DoubleArray(maxLag + 1) { lag -> if (lag < minLag) 0.0 else comb(lag.toDouble()) }
        val strongest = (minLag..maxLag).maxByOrNull { score[it] } ?: return null
        val rawBpm = 60 * fps / refine(score, strongest)
        // Metrical relatives (half / double, 2:3, 3:4): the one that scores
        // well and sits closest to dance tempo.
        val candidates = listOf(0.5, 2.0 / 3, 0.75, 1.0, 4.0 / 3, 1.5, 2.0).map { rawBpm * it }.filter { it in MIN_BPM..MAX_BPM }
        val bpm = candidates.maxByOrNull { b -> max(0.0, comb(60 * fps / b)) * prior(b) } ?: rawBpm
        val beatLag = (60 * fps / bpm).roundToInt().coerceIn(minLag, maxLag)

        // Pulse clarity: the beat's correlation against the typical one.
        val mean = (minLag..maxLag).map { score[it] }.average()
        val clarity = ((score[beatLag] - mean) / max(1e-9, 1 - mean)).coerceIn(0.0, 1.0)
        // Steadiness: does every excerpt agree on that beat?
        val perExcerpt = envelopes.map { env ->
            val a = autocorrelation(listOf(env), beatLag + 1)
            if (a[0] <= 1e-12) 0.0 else max(0.0, a[beatLag] / a[0])
        }
        val steadiness = perExcerpt.average() * (1 - (perExcerpt.max() - perExcerpt.min()))
        val groove = (100 * min(1.0, (0.6 * clarity + 0.4 * steadiness) / 0.55)).roundToInt()

        val bassEnv = bassOnsets.map { normalise(it) }.filter { it.size > MIN_FRAMES }
        val bassAc = autocorrelation(bassEnv, beatLag + 1)
        val bassLock = if (bassAc[0] <= 1e-12) 0.0 else max(0.0, bassAc[beatLag] / bassAc[0])
        val lowShare = if (spectralFrames == 0) 0.0 else bassShare / spectralFrames
        val bassPunch = (100 * min(1.0, 0.6 * min(1.0, bassLock / 0.5) + 0.4 * min(1.0, lowShare / 0.5))).roundToInt()

        // Energy: loudness (−30…−8 dBFS RMS), busy-ness, brightness.
        val loud = ((meanDb + 30) / 22).coerceIn(0.0, 1.0)
        val density = onsetDensity(envelopes)
        val brightness = if (spectralFrames == 0) 0.0 else min(1.0, brightShare / spectralFrames / 0.15)
        val energy = (100 * (0.55 * loud + 0.3 * density + 0.15 * brightness)).roundToInt()
        val excerptEnergy = excerptRms.filter { it.isNotEmpty() }.map { e ->
            val db = 20 * log10(max(1e-9, sqrt(e.sumOf { it * it } / e.size)))
            (100 * ((db + 30) / 22).coerceIn(0.0, 1.0)).roundToInt()
        }

        val tempoFit = danceTempoFit(bpm)
        val dance = 100 * (0.45 * groove / 100.0 + 0.25 * tempoFit + 0.2 * bassPunch / 100.0 + 0.1 * loud)
        return Result(
            bpm = (bpm * 10).roundToInt() / 10.0,
            confidence = clarity,
            groove = groove,
            bassPunch = bassPunch,
            energy = energy.coerceIn(0, 100),
            danceability = dance.roundToInt().coerceIn(0, 100),
            excerptEnergy = excerptEnergy,
        )
    }

    /** Mean-removed, half-wave rectified against a local average (onset peaks only). */
    private fun normalise(raw: List<Double>): DoubleArray {
        val n = raw.size
        val out = DoubleArray(n)
        val half = 8
        var sum = 0.0
        var count = 0
        var lo = 0
        var hi = 0
        for (i in 0 until n) {
            while (hi < n && hi <= i + half) {
                sum += raw[hi]
                count++
                hi++
            }
            while (lo < i - half) {
                sum -= raw[lo]
                count--
                lo++
            }
            out[i] = max(0.0, raw[i] - sum / count)
        }
        return out
    }

    private fun autocorrelation(envelopes: List<DoubleArray>, lags: Int): DoubleArray {
        val ac = DoubleArray(lags)
        for (env in envelopes) {
            for (lag in 0 until min(lags, env.size)) {
                var s = 0.0
                for (i in 0 until env.size - lag) s += env[i] * env[i + lag]
                // Unbiased: shorter overlaps count as much as longer ones.
                ac[lag] += s / (env.size - lag)
            }
        }
        return ac
    }

    /** Peak position with a parabola through its neighbours. */
    private fun refine(s: DoubleArray, i: Int): Double {
        if (i <= 0 || i >= s.size - 1) return i.toDouble()
        val a = s[i - 1]
        val b = s[i]
        val c = s[i + 1]
        val d = a - 2 * b + c
        return if (abs(d) < 1e-12) i.toDouble() else i + 0.5 * (a - c) / d
    }

    /** Onsets per second, as 0…1 (≈ 8 a second is busy). */
    private fun onsetDensity(envelopes: List<DoubleArray>): Double {
        var peaks = 0
        var frames = 0
        for (env in envelopes) {
            val threshold = env.average() + env.standardDeviation()
            for (i in 1 until env.size - 1) {
                if (env[i] > threshold && env[i] >= env[i - 1] && env[i] > env[i + 1]) peaks++
            }
            frames += env.size
        }
        val perSecond = peaks / max(1.0, frames / fps)
        return min(1.0, perSecond / 8)
    }

    private fun DoubleArray.standardDeviation(): Double {
        val m = average()
        return sqrt(sumOf { (it - m) * (it - m) } / max(1, size))
    }

    companion object {
        private const val FRAME = 1024
        private const val HOP = 256
        private const val MIN_FRAMES = 100 // ≈ 2 s
        const val MIN_BPM = 60.0
        const val MAX_BPM = 200.0

        /** Weight for the half / double-time choice: 1 across 95–140 BPM, falling off an octave away. */
        fun prior(bpm: Double): Double = when {
            bpm in 95.0..140.0 -> 1.0
            bpm < 95 -> exp(-sq(log2(95 / bpm)) / (2 * 0.35 * 0.35))
            else -> exp(-sq(log2(bpm / 140)) / (2 * 0.35 * 0.35))
        }

        /**
         * How well a tempo suits the dance floor, 0…1: full for
         * afrobeats / amapiano (100–115) and coupé-décalé / ndombolo /
         * makossa (120–140) and the step between, softer outside.
         */
        fun danceTempoFit(bpm: Double): Double = when {
            bpm in 98.0..142.0 -> 1.0
            bpm < 98 -> exp(-sq(98 - bpm) / (2 * 12.0 * 12.0))
            else -> exp(-sq(bpm - 142) / (2 * 15.0 * 15.0))
        }

        private fun sq(x: Double) = x * x
        private fun log2(x: Double) = ln(x) / ln(2.0)

        /** Excerpts: 30 s around 25 %, 50 % and 75 % of a [durationMs] song (fewer for short ones). */
        fun excerpts(durationMs: Long): List<Pair<Long, Long>> {
            val length = 30_000L
            if (durationMs <= length * 2) return listOf(0L to durationMs)
            return listOf(0.25, 0.5, 0.75).map { at ->
                val start = (durationMs * at).toLong() - length / 2
                start.coerceIn(0, durationMs - length) to start.coerceIn(0, durationMs - length) + length
            }
        }

        /** Analyses [location] from its excerpts, relative to [startMs] (CUE tracks). */
        fun of(context: Context, location: String, startMs: Long, durationMs: Long): Result? {
            val analyser = RhythmAnalyser()
            for ((from, to) in excerpts(durationMs)) {
                analyser.startExcerpt()
                PcmDecoder.decode(context, location, object : PcmDecoder.Sink {
                    override fun format(rate: Int, channels: Int) = analyser.format(rate, channels)
                    override fun samples(samples: FloatArray, frames: Int) = analyser.add(samples, frames)
                }, startUs = (startMs + from) * 1000, endUs = (startMs + to) * 1000)
            }
            return analyser.result()
        }
    }
}
