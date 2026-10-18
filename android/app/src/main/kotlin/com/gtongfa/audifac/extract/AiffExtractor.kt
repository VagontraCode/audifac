package com.gtongfa.audifac.extract

import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.MimeTypes
import androidx.media3.common.ParserException
import androidx.media3.common.util.ParsableByteArray
import androidx.media3.common.util.UnstableApi
import androidx.media3.extractor.Extractor
import androidx.media3.extractor.ExtractorInput
import androidx.media3.extractor.ExtractorOutput
import androidx.media3.extractor.PositionHolder
import androidx.media3.extractor.SeekMap
import androidx.media3.extractor.SeekPoint
import androidx.media3.extractor.TrackOutput
import java.io.EOFException
import kotlin.math.pow

/** Parsed AIFF / AIFC header. */
data class AiffInfo(
    val channels: Int,
    val sampleRate: Int,
    val bitsPerSample: Int,
    val frames: Long,
    /** NONE / twos = big-endian PCM, sowt = little-endian PCM, fl32 / fl64 = float. */
    val compression: String,
    val dataStart: Long,
) {
    val bytesPerSample: Int
        get() = when (compression) {
            "fl32", "FL32" -> 4
            "fl64", "FL64" -> 8
            else -> (bitsPerSample + 7) / 8
        }
    val inputFrameSize: Int get() = bytesPerSample * channels
    val durationUs: Long get() = frames * C.MICROS_PER_SECOND / sampleRate

    /** PCM encoding handed to the player after conversion. */
    val outputEncoding: Int
        get() = when {
            compression.equals("fl32", true) || compression.equals("fl64", true) -> C.ENCODING_PCM_FLOAT
            bytesPerSample == 1 -> C.ENCODING_PCM_8BIT
            bytesPerSample == 2 -> C.ENCODING_PCM_16BIT
            bytesPerSample == 3 -> C.ENCODING_PCM_24BIT
            else -> C.ENCODING_PCM_32BIT
        }
    val outputBytesPerSample: Int get() = if (compression.equals("fl64", true)) 4 else bytesPerSample

    companion object {
        /** IEEE 754 80-bit extended (AIFF sample rate) → double. */
        fun extended(b: ByteArray, o: Int): Double {
            val sign = if (b[o].toInt() and 0x80 != 0) -1 else 1
            val exponent = ((b[o].toInt() and 0x7F) shl 8) or (b[o + 1].toInt() and 0xFF)
            var mantissa = 0.0
            for (i in 0 until 8) mantissa = mantissa * 256 + (b[o + 2 + i].toInt() and 0xFF)
            if (exponent == 0 && mantissa == 0.0) return 0.0
            return sign * mantissa * 2.0.pow(exponent - 16383 - 63)
        }
    }
}

/** Plays AIFF / AIFC (uncompressed PCM, `sowt`, 32/64-bit float), which ExoPlayer can't open. */
@OptIn(UnstableApi::class)
class AiffExtractor : Extractor {
    private lateinit var output: ExtractorOutput
    private lateinit var track: TrackOutput
    private var info: AiffInfo? = null
    private var dataEnd = 0L
    private var framesOut = 0L
    private var inBuf = ByteArray(0)
    private var outBuf = ByteArray(0)

    override fun sniff(input: ExtractorInput): Boolean {
        val h = ByteArray(12)
        if (!input.peekFully(h, 0, 12, true)) return false
        return String(h, 0, 4, Charsets.US_ASCII) == "FORM" &&
            String(h, 8, 4, Charsets.US_ASCII).let { it == "AIFF" || it == "AIFC" }
    }

    override fun init(output: ExtractorOutput) {
        this.output = output
        track = output.track(0, C.TRACK_TYPE_AUDIO)
        output.endTracks()
    }

    override fun read(input: ExtractorInput, seekPosition: PositionHolder): Int {
        val info = info ?: return parseHeader(input)
        if (input.position < info.dataStart) {
            seekPosition.position = info.dataStart
            return Extractor.RESULT_SEEK
        }
        val remaining = dataEnd - input.position
        if (remaining < info.inputFrameSize) return Extractor.RESULT_END_OF_INPUT

        val frames = minOf(remaining / info.inputFrameSize, FRAMES_PER_READ.toLong()).toInt()
        val inBytes = frames * info.inputFrameSize
        if (inBuf.size < inBytes) inBuf = ByteArray(inBytes)
        try {
            if (!input.readFully(inBuf, 0, inBytes, true)) return Extractor.RESULT_END_OF_INPUT
        } catch (e: EOFException) {
            return Extractor.RESULT_END_OF_INPUT // Truncated file: play what we have.
        }
        val outBytes = convert(info, inBuf, frames * info.channels)
        track.sampleData(ParsableByteArray(outBuf, outBytes), outBytes)
        track.sampleMetadata(framesOut * C.MICROS_PER_SECOND / info.sampleRate, C.BUFFER_FLAG_KEY_FRAME, outBytes, 0, null)
        framesOut += frames
        return Extractor.RESULT_CONTINUE
    }

    private fun parseHeader(input: ExtractorInput): Int {
        val head = ByteArray(12)
        input.readFully(head, 0, 12)
        val isAifc = String(head, 8, 4, Charsets.US_ASCII) == "AIFC"
        var channels = 0
        var bits = 0
        var frames = 0L
        var rate = 0.0
        var compression = "NONE"
        val chunk = ByteArray(8)
        while (true) {
            input.readFully(chunk, 0, 8)
            val id = String(chunk, 0, 4, Charsets.US_ASCII)
            val size = be32(chunk, 4).toLong() and 0xFFFFFFFFL
            when (id) {
                "COMM" -> {
                    val c = ByteArray(size.toInt())
                    input.readFully(c, 0, c.size)
                    channels = be16(c, 0)
                    frames = be32(c, 2).toLong() and 0xFFFFFFFFL
                    bits = be16(c, 6)
                    rate = AiffInfo.extended(c, 8)
                    if (isAifc && c.size >= 22) compression = String(c, 18, 4, Charsets.US_ASCII)
                    if (size % 2 == 1L) input.skipFully(1)
                }
                "SSND" -> {
                    val s = ByteArray(8)
                    input.readFully(s, 0, 8)
                    val offset = be32(s, 0).toLong() and 0xFFFFFFFFL
                    if (offset > 0) input.skipFully(offset.toInt())
                    val supported = setOf("NONE", "twos", "sowt", "fl32", "FL32", "fl64", "FL64")
                    if (compression !in supported || channels <= 0 || rate <= 0) {
                        throw ParserException.createForUnsupportedContainerFeature("AIFF compression $compression")
                    }
                    val parsed = AiffInfo(channels, rate.toInt(), bits, frames, compression, input.position)
                    info = parsed
                    // Size from the chunk; fall back to the frame count if it lies.
                    dataEnd = minOf(
                        input.position + size - 8 - offset,
                        input.position + frames * parsed.inputFrameSize,
                    ).let { end -> if (input.length > 0) minOf(end, input.length) else end }
                    framesOut = 0
                    publish(parsed)
                    return Extractor.RESULT_CONTINUE
                }
                else -> input.skipFully((size + (size and 1)).toInt())
            }
        }
    }

    private fun publish(info: AiffInfo) {
        track.format(
            Format.Builder()
                .setSampleMimeType(MimeTypes.AUDIO_RAW)
                .setChannelCount(info.channels)
                .setSampleRate(info.sampleRate)
                .setPcmEncoding(info.outputEncoding)
                .setAverageBitrate(info.sampleRate * info.channels * info.outputBytesPerSample * 8)
                .build(),
        )
        output.seekMap(object : SeekMap {
            override fun isSeekable() = true
            override fun getDurationUs() = info.durationUs
            override fun getSeekPoints(timeUs: Long): SeekMap.SeekPoints {
                val frame = (timeUs * info.sampleRate / C.MICROS_PER_SECOND).coerceIn(0, maxOf(0, info.frames - 1))
                return SeekMap.SeekPoints(
                    SeekPoint(frame * C.MICROS_PER_SECOND / info.sampleRate, info.dataStart + frame * info.inputFrameSize),
                )
            }
        })
    }

    /** Big-endian (or sowt / float) samples in [inBuf] → little-endian PCM in [outBuf]. */
    private fun convert(info: AiffInfo, src: ByteArray, samples: Int): Int {
        val outSize = samples * info.outputBytesPerSample
        if (outBuf.size < outSize) outBuf = ByteArray(outSize)
        val dst = outBuf
        val bps = info.bytesPerSample
        when {
            info.compression == "sowt" -> System.arraycopy(src, 0, dst, 0, outSize)
            info.compression.equals("fl64", true) -> for (i in 0 until samples) {
                var bitsL = 0L
                for (k in 0 until 8) bitsL = (bitsL shl 8) or (src[i * 8 + k].toLong() and 0xFF)
                val f = java.lang.Float.floatToRawIntBits(java.lang.Double.longBitsToDouble(bitsL).toFloat())
                dst[i * 4] = f.toByte()
                dst[i * 4 + 1] = (f shr 8).toByte()
                dst[i * 4 + 2] = (f shr 16).toByte()
                dst[i * 4 + 3] = (f shr 24).toByte()
            }
            bps == 1 -> for (i in 0 until samples) dst[i] = (src[i] + 128).toByte() // signed → unsigned 8-bit
            else -> for (i in 0 until samples) {
                val o = i * bps
                for (k in 0 until bps) dst[o + k] = src[o + bps - 1 - k] // byte swap
            }
        }
        return outSize
    }

    override fun seek(position: Long, timeUs: Long) {
        val info = info
        if (position == 0L || info == null) {
            this.info = null // Re-read the header from the start.
            framesOut = 0
            return
        }
        framesOut = ((position - info.dataStart) / info.inputFrameSize).coerceAtLeast(0)
    }

    override fun release() {}

    private fun be16(b: ByteArray, o: Int) = ((b[o].toInt() and 0xFF) shl 8) or (b[o + 1].toInt() and 0xFF)

    private fun be32(b: ByteArray, o: Int) =
        ((b[o].toInt() and 0xFF) shl 24) or ((b[o + 1].toInt() and 0xFF) shl 16) or
            ((b[o + 2].toInt() and 0xFF) shl 8) or (b[o + 3].toInt() and 0xFF)

    companion object {
        private const val FRAMES_PER_READ = 4096
    }
}
