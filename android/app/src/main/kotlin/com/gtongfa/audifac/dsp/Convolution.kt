package com.gtongfa.audifac.dsp

import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.sin

/**
 * An impulse response (room or headphone correction, a reverb…) as read from
 * a WAV file: 1 channel (both sides), 2 (left / right) or 4 (true stereo:
 * L→L, L→R, R→L, R→R).
 */
class ImpulseResponse(val name: String, val rate: Int, val channels: List<FloatArray>) {
    val frames get() = channels.firstOrNull()?.size ?: 0

    companion object {
        /** Longest accepted (≈ 2.7 s at 48 kHz). */
        const val MAX_FRAMES = 1 shl 17

        /** Reads a PCM (16 / 24 / 32-bit) or float WAV; null if it isn't one we can use. */
        fun readWav(file: File, name: String = file.nameWithoutExtension): ImpulseResponse? =
            try {
                parseWav(file.readBytes(), name)
            } catch (e: Exception) {
                null
            }

        fun parseWav(bytes: ByteArray, name: String): ImpulseResponse? {
            val b = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
            if (bytes.size < 12 || String(bytes, 0, 4) != "RIFF" || String(bytes, 8, 4) != "WAVE") return null
            var pos = 12
            var format = 0
            var channels = 0
            var rate = 0
            var bits = 0
            while (pos + 8 <= bytes.size) {
                val id = String(bytes, pos, 4)
                val size = b.getInt(pos + 4)
                val body = pos + 8
                if (size < 0 || body + size > bytes.size && id != "data") return null
                when (id) {
                    "fmt " -> {
                        format = b.getShort(body).toInt() and 0xFFFF
                        channels = b.getShort(body + 2).toInt()
                        rate = b.getInt(body + 4)
                        bits = b.getShort(body + 14).toInt()
                        // WAVE_FORMAT_EXTENSIBLE: the real format is the sub-format GUID's first word.
                        if (format == 0xFFFE && size >= 26) format = b.getShort(body + 24).toInt() and 0xFFFF
                    }
                    "data" -> {
                        if (channels !in listOf(1, 2, 4) || rate !in 8_000..384_000) return null
                        val bytesPer = bits / 8
                        val available = minOf(size, bytes.size - body)
                        val frames = minOf(available / (bytesPer * channels), MAX_FRAMES)
                        if (frames <= 0) return null
                        val out = List(channels) { FloatArray(frames) }
                        var p = body
                        for (f in 0 until frames) for (c in 0 until channels) {
                            out[c][f] = when {
                                format == 3 && bits == 32 -> b.getFloat(p)
                                format == 3 && bits == 64 -> b.getDouble(p).toFloat()
                                format == 1 && bits == 16 -> b.getShort(p) / 32768f
                                format == 1 && bits == 24 ->
                                    ((bytes[p].toInt() and 0xFF) or ((bytes[p + 1].toInt() and 0xFF) shl 8) or (bytes[p + 2].toInt() shl 16)) / 8388608f
                                format == 1 && bits == 32 -> (b.getInt(p) / 2147483648.0).toFloat()
                                else -> return null
                            }
                            p += bytesPer
                        }
                        return ImpulseResponse(name, rate, out)
                    }
                }
                pos = body + size + (size and 1)
            }
            return null
        }

        private val cache = HashMap<String, ImpulseResponse>()

        /** The response in [path], read once (by path and modification time). */
        @Synchronized
        fun load(path: String): ImpulseResponse? {
            val file = File(path)
            if (!file.isFile) return null
            val key = "$path@${file.lastModified()}"
            cache[key]?.let { return it }
            // The app's copies are named "<time>_<original name>.wav".
            return readWav(file, file.nameWithoutExtension.replaceFirst(Regex("^\\d+_"), ""))?.also {
                cache.clear() // one response in use at a time: don't keep old ones
                cache[key] = it
            }
        }
    }
}

/** In-place radix-2 complex FFT of size [n] (a power of two), with precomputed tables. */
class Fft(val n: Int) {
    private val cosT = DoubleArray(n / 2) { cos(2 * PI * it / n) }
    private val sinT = DoubleArray(n / 2) { sin(2 * PI * it / n) }
    private val rev = IntArray(n).also { r ->
        val bits = Integer.numberOfTrailingZeros(n)
        for (i in 0 until n) r[i] = Integer.reverse(i) ushr (32 - bits)
    }

    /** Forward ([inverse] false: e^-i) or inverse (unscaled) transform. */
    fun transform(re: DoubleArray, im: DoubleArray, inverse: Boolean) {
        for (i in 0 until n) {
            val j = rev[i]
            if (i < j) {
                var t = re[i]; re[i] = re[j]; re[j] = t
                t = im[i]; im[i] = im[j]; im[j] = t
            }
        }
        val sign = if (inverse) 1.0 else -1.0
        var len = 2
        while (len <= n) {
            val half = len / 2
            val step = n / len
            var i = 0
            while (i < n) {
                var k = 0
                for (j in i until i + half) {
                    val wr = cosT[k]
                    val wi = sign * sinT[k]
                    val a = j + half
                    val xr = re[a] * wr - im[a] * wi
                    val xi = re[a] * wi + im[a] * wr
                    re[a] = re[j] - xr; im[a] = im[j] - xi
                    re[j] += xr; im[j] += xi
                    k += step
                }
                i += len
            }
            len = len shl 1
        }
    }
}

/**
 * Convolves a stereo (or mono) stream with an [ImpulseResponse]: uniformly
 * partitioned overlap-save in [block]-frame blocks (that much latency; longer
 * for longer responses, which cuts the work per sample), both
 * channels through one complex FFT. The response is converted to
 * [sampleRate] and normalised so its loudest frequency is at 0 dB.
 */
class Convolver(
    val ir: ImpulseResponse,
    private val sampleRate: Int,
    private val channels: Int,
    /** Run the C++ engine (verified against this Kotlin code on first use). */
    native: Boolean = nativeVerified,
    /** Scale so the loudest frequency is at 0 dB (off for an EQ, whose level matters). */
    private val normalise: Boolean = true,
) {
    /** The response at the stream's rate, per channel. */
    private val responses: List<FloatArray> = ir.channels.map { if (ir.rate == sampleRate) it else resample(it, ir.rate, sampleRate) }

    /** Block (and latency) in frames. */
    val block = blockFor(responses.maxOf { it.size })

    private val n = block * 2
    private val bins = block + 1 // 0 … n/2
    private val fft = Fft(n)

    /** paths[out][in]: half spectra per partition (re, im), or null when that path is silent. */
    private var paths: Array<Array<Array<DoubleArray>?>>

    /** Spectra taking over at the next block (see [update]). */
    private var pending: Array<Array<Array<DoubleArray>?>>? = null
    private val partitions: Int

    /** The native engine, 0 when the Kotlin code runs. */
    private var handle = 0L

    /** Applied to the response so its loudest frequency is at 0 dB. */
    val gain: Double

    // Frequency-domain delay line of input spectra: [slot][channel] (re, im interleaved per bin).
    private val fdlRe: Array<Array<DoubleArray>>
    private val fdlIm: Array<Array<DoubleArray>>
    private var slot = 0

    // Time domain: last n input samples per channel, and the block being filled / played.
    private val window = Array(2) { DoubleArray(n) }
    private val outBlock = Array(2) { DoubleArray(block) }
    private val fadeBlock = Array(2) { DoubleArray(block) }
    private var fill = 0

    private val re = DoubleArray(n)
    private val im = DoubleArray(n)
    private val accRe = Array(2) { DoubleArray(bins) }
    private val accIm = Array(2) { DoubleArray(bins) }

    init {
        val length = responses.maxOf { it.size }
        partitions = maxOf(1, (length + block - 1) / block)
        val matrix = matrixOf(responses)
        gain = if (normalise) normalisation(matrix, length) else 1.0
        paths = pathsOf(matrix)
        fdlRe = Array(partitions) { Array(2) { DoubleArray(bins) } }
        fdlIm = Array(partitions) { Array(2) { DoubleArray(bins) } }
        handle = if (native) {
            NativeDsp.convCreate(block, partitions, flat(paths, 0, 0), flat(paths, 0, 1), flat(paths, 1, 0), flat(paths, 1, 1))
        } else {
            0L
        }
    }

    /** Which response goes from input channel i to output channel o: [out][in]. */
    private fun matrixOf(h: List<FloatArray>): Array<Array<FloatArray?>> = when (h.size) {
        1 -> arrayOf(arrayOf(h[0], null), arrayOf(null, h[0]))
        2 -> arrayOf(arrayOf(h[0], null), arrayOf(null, h[1]))
        else -> arrayOf(arrayOf(h[0], h[2]), arrayOf(h[1], h[3])) // LL, RL / LR, RR
    }

    private fun pathsOf(matrix: Array<Array<FloatArray?>>) = Array(2) { o ->
        Array(2) { i -> matrix[o][i]?.let { response -> spectra(response, gain) } }
    }

    private fun flat(with: Array<Array<Array<DoubleArray>?>>, o: Int, i: Int): FloatArray? = with[o][i]?.let { parts ->
        FloatArray(partitions * bins * 2).also { f ->
            for (p in 0 until partitions) for (k in 0 until bins * 2) f[p * bins * 2 + k] = parts[p][k].toFloat()
        }
    }

    /**
     * Switches to [responses] (at the stream's rate, the same layout and at
     * most as long): from the next block, cross-faded over it, keeping the
     * input history — no gap, no click. The gain stays as it was.
     */
    fun update(responses: List<FloatArray>) {
        val next = pathsOf(matrixOf(responses))
        if (handle != 0L) {
            NativeDsp.convUpdate(handle, flat(next, 0, 0), flat(next, 0, 1), flat(next, 1, 0), flat(next, 1, 1))
        } else {
            pending = next
        }
    }

    /** Partition p of [response] × [gain], transformed: [p] = re (bins) followed by im (bins). */
    private fun spectra(response: FloatArray, gain: Double): Array<DoubleArray> = Array(partitions) { p ->
        re.fill(0.0)
        im.fill(0.0)
        val start = p * block
        for (j in 0 until block) {
            val k = start + j
            if (k < response.size) re[j] = response[k] * gain
        }
        fft.transform(re, im, false)
        DoubleArray(bins * 2).also { s ->
            for (k in 0 until bins) {
                s[k] = re[k]
                s[bins + k] = im[k]
            }
        }
    }

    /** 1 / the loudest output frequency (all paths into one output added), so peaks sit at 0 dB. */
    private fun normalisation(matrix: Array<Array<FloatArray?>>, length: Int): Double {
        var size = 1
        while (size < length * 2) size = size shl 1
        val f = Fft(size)
        var peak = 0.0
        for (o in 0 until 2) {
            val mag = DoubleArray(size / 2 + 1)
            for (i in 0 until 2) {
                val r = matrix[o][i] ?: continue
                val a = DoubleArray(size)
                val b = DoubleArray(size)
                for (k in r.indices) a[k] = r[k].toDouble()
                f.transform(a, b, false)
                for (k in mag.indices) mag[k] += hypot(a[k], b[k])
            }
            for (m in mag) peak = max(peak, m)
        }
        return if (peak > 1e-9) 1.0 / peak else 1.0
    }

    /** Processes [frames] interleaved frames of [samples] in place (delayed by [block]). */
    fun process(samples: FloatArray, frames: Int, offset: Int = 0) {
        if (handle != 0L) return NativeDsp.convProcess(handle, samples, frames, offset, channels)
        var idx = offset
        val stereo = channels >= 2
        for (f in 0 until frames) {
            val l = samples[idx].toDouble()
            val r = if (stereo) samples[idx + 1].toDouble() else 0.0
            window[0][block + fill] = l
            window[1][block + fill] = r
            samples[idx] = outBlock[0][fill].toFloat()
            if (stereo) samples[idx + 1] = outBlock[1][fill].toFloat()
            idx += channels
            if (++fill == block) {
                runBlock()
                fill = 0
            }
        }
    }

    private fun runBlock() {
        // Both channels in one transform: x = l + i·r.
        for (k in 0 until n) {
            re[k] = window[0][k]
            im[k] = window[1][k]
        }
        fft.transform(re, im, false)
        val inRe = fdlRe[slot]
        val inIm = fdlIm[slot]
        for (k in 0 until bins) {
            val m = (n - k) and (n - 1)
            // L = (X[k] + conj X[n−k]) / 2, R = (X[k] − conj X[n−k]) / 2i
            inRe[0][k] = (re[k] + re[m]) * 0.5
            inIm[0][k] = (im[k] - im[m]) * 0.5
            inRe[1][k] = (im[k] + im[m]) * 0.5
            inIm[1][k] = (re[m] - re[k]) * 0.5
        }
        filter(paths, outBlock)
        val next = pending
        if (next != null) {
            // A new response: this block cross-fades from the old one's output
            // to the new one's (same input history, so no gap and no click).
            filter(next, fadeBlock)
            for (j in 0 until block) {
                val t = (j + 0.5) / block
                for (c in 0 until 2) outBlock[c][j] = outBlock[c][j] * (1 - t) + fadeBlock[c][j] * t
            }
            paths = next
            pending = null
        }
        slot = (slot + 1) % partitions
        // Slide: the new half becomes the old half.
        for (c in 0 until 2) System.arraycopy(window[c], block, window[c], 0, block)
    }

    /** The current block through [with] (input spectra already in the delay line) into [out]. */
    private fun filter(with: Array<Array<Array<DoubleArray>?>>, out: Array<DoubleArray>) {
        for (o in 0 until 2) {
            accRe[o].fill(0.0)
            accIm[o].fill(0.0)
        }
        for (p in 0 until partitions) {
            val s = (slot - p + partitions) % partitions
            for (o in 0 until 2) for (i in 0 until 2) {
                val h = with[o][i]?.get(p) ?: continue
                val xr = fdlRe[s][i]
                val xi = fdlIm[s][i]
                val ar = accRe[o]
                val ai = accIm[o]
                for (k in 0 until bins) {
                    val hr = h[k]
                    val hi = h[bins + k]
                    ar[k] += xr[k] * hr - xi[k] * hi
                    ai[k] += xr[k] * hi + xi[k] * hr
                }
            }
        }
        // Z = Y_L + i·Y_R (full spectrum from the halves), one inverse transform.
        for (k in 0 until n) {
            if (k < bins) {
                re[k] = accRe[0][k] - accIm[1][k]
                im[k] = accIm[0][k] + accRe[1][k]
            } else {
                val m = n - k
                // conj(Y_L[m]) + i·conj(Y_R[m])
                re[k] = accRe[0][m] + accIm[1][m]
                im[k] = -accIm[0][m] + accRe[1][m]
            }
        }
        fft.transform(re, im, true)
        val scale = 1.0 / n
        for (j in 0 until block) {
            out[0][j] = re[block + j] * scale
            out[1][j] = im[block + j] * scale
        }
    }

    /** Frees the native engine (also done when garbage-collected). */
    fun close() {
        if (handle != 0L) NativeDsp.convDestroy(handle)
        handle = 0L
    }

    protected fun finalize() = close()

    fun reset() {
        if (handle != 0L) NativeDsp.convReset(handle)
        for (c in 0 until 2) {
            window[c].fill(0.0)
            outBlock[c].fill(0.0)
        }
        for (s in 0 until partitions) for (c in 0 until 2) {
            fdlRe[s][c].fill(0.0)
            fdlIm[s][c].fill(0.0)
        }
        fill = 0
    }

    companion object {
        /** The C++ engine gives the Kotlin engine's output (checked once, on first use). */
        val nativeVerified: Boolean by lazy {
            if (!NativeDsp.loaded) return@lazy false
            try {
                val r = java.util.Random(11)
                val ir = ImpulseResponse("check", 48_000, listOf(FloatArray(3000) { r.nextFloat() - 0.5f }, FloatArray(3000) { r.nextFloat() - 0.5f }))
                val input = FloatArray(6000 * 2) { r.nextFloat() - 0.5f }
                val a = input.copyOf()
                val b = input.copyOf()
                Convolver(ir, 48_000, 2, native = true).also { it.process(a, 6000) }.close()
                Convolver(ir, 48_000, 2, native = false).process(b, 6000)
                val same = a.indices.all { kotlin.math.abs(a[it] - b[it]) < 1e-4f }
                if (same) NativeDsp.info("native convolution verified, in use") else NativeDsp.warn("native convolution disagrees with the Kotlin one: not used")
                same
            } catch (t: Throwable) {
                NativeDsp.warn("native convolution failed ($t): not used")
                false
            }
        }

        /** Block (and latency) in frames. */
        private const val MIN_BLOCK = 1024
        private const val MAX_BLOCK = 8192

        /** About an eighth of the response, as a power of two (1024 … 8192 frames). */
        fun blockFor(length: Int): Int {
            var b = MIN_BLOCK
            while (b < length / 8 && b < MAX_BLOCK) b = b shl 1
            return b
        }

        private const val RESAMPLE_PAD = 256

        private fun resample(x: FloatArray, from: Int, to: Int): FloatArray {
            if (!Resampler.supports(from, to)) return x
            val r = Resampler(from, to, 1, native = false)
            val out = ArrayList<Float>(x.size * to / from + 16)
            // Leading silence: a response that starts at its first sample would
            // otherwise lose the filter's ringing before time zero.
            val padded = FloatArray(x.size + RESAMPLE_PAD).also { System.arraycopy(x, 0, it, RESAMPLE_PAD, x.size) }
            val n = r.process(padded, padded.size)
            for (i in 0 until n) out += r.out[i]
            val m = r.flush()
            for (i in 0 until m) out += r.out[i]
            return out.toFloatArray()
        }
    }
}
