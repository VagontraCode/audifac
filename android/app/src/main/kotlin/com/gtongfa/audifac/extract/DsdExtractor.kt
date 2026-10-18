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

/** Parsed DSF / DFF header. */
data class DsdInfo(
    val dff: Boolean,
    val channels: Int,
    val dsdRate: Int,
    /** DSD samples (bits) per channel. */
    val samplesPerChannel: Long,
    val dataStart: Long,
    val dataSize: Long,
    /** DSF: bytes per channel per block (4096); DFF: 1 (byte-interleaved). */
    val blockSize: Int,
) {
    val lsbFirst: Boolean get() = !dff
    val durationUs: Long get() = samplesPerChannel * C.MICROS_PER_SECOND / dsdRate

    /** "DSD64", "DSD128"… */
    val label: String get() = "DSD${dsdRate / 44_100}"
}

/**
 * Plays DSD: Sony DSF (block-interleaved, LSB first) and Philips DSDIFF / DFF
 * (byte-interleaved, MSB first, uncompressed only — DST is not supported).
 * The 1-bit stream is converted to 176.4 kHz float PCM by [DsdToPcm].
 */
@OptIn(UnstableApi::class)
class DsdExtractor : Extractor {
    private lateinit var output: ExtractorOutput
    private lateinit var track: TrackOutput
    private var info: DsdInfo? = null
    private var converter: DsdToPcm? = null
    private var framesOut = 0L
    /** DSD bytes per channel already consumed (to stop at the real sample count). */
    private var bytesPerChannelRead = 0L
    private var inBuf = ByteArray(0)
    private var pcm = FloatArray(0)
    private var outBytes = ByteArray(0)

    override fun sniff(input: ExtractorInput): Boolean {
        val h = ByteArray(16)
        if (!input.peekFully(h, 0, 16, true)) return false
        val id = String(h, 0, 4, Charsets.US_ASCII)
        return id == "DSD " || (id == "FRM8" && String(h, 12, 4, Charsets.US_ASCII) == "DSD ")
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
        val conv = converter!!
        val totalBytesPerChannel = (info.samplesPerChannel + 7) / 8
        val leftPerChannel = totalBytesPerChannel - bytesPerChannelRead
        if (leftPerChannel <= 0 || input.position >= info.dataStart + info.dataSize) return Extractor.RESULT_END_OF_INPUT

        // DSF reads whole blocks (channel after channel); DFF reads interleaved bytes.
        val bytesPerChannel = if (info.dff) minOf(DFF_BYTES_PER_READ.toLong(), leftPerChannel).toInt() else info.blockSize
        val readSize = bytesPerChannel * info.channels
        if (inBuf.size < readSize) inBuf = ByteArray(readSize)
        try {
            if (!input.readFully(inBuf, 0, readSize, true)) return Extractor.RESULT_END_OF_INPUT
        } catch (e: EOFException) {
            return Extractor.RESULT_END_OF_INPUT
        }
        // The last DSF block is zero-padded: use only the real samples.
        val useful = minOf(bytesPerChannel.toLong(), leftPerChannel).toInt()
        bytesPerChannelRead += bytesPerChannel

        val maxOut = useful / conv.decimation2 + 2
        if (pcm.size < maxOut * info.channels) pcm = FloatArray(maxOut * info.channels)
        var frames = 0
        for (ch in 0 until info.channels) {
            frames = if (info.dff) {
                conv.process(ch, inBuf, ch, useful, info.channels, pcm, ch, info.channels)
            } else {
                conv.process(ch, inBuf, ch * info.blockSize, useful, 1, pcm, ch, info.channels)
            }
        }
        if (frames == 0) return Extractor.RESULT_CONTINUE

        val size = frames * info.channels * 4
        if (outBytes.size < size) outBytes = ByteArray(size)
        var o = 0
        for (i in 0 until frames * info.channels) {
            val bits = java.lang.Float.floatToRawIntBits(pcm[i])
            outBytes[o++] = bits.toByte()
            outBytes[o++] = (bits shr 8).toByte()
            outBytes[o++] = (bits shr 16).toByte()
            outBytes[o++] = (bits shr 24).toByte()
        }
        track.sampleData(ParsableByteArray(outBytes, size), size)
        track.sampleMetadata(framesOut * C.MICROS_PER_SECOND / conv.outputRate, C.BUFFER_FLAG_KEY_FRAME, size, 0, null)
        framesOut += frames
        return Extractor.RESULT_CONTINUE
    }

    private fun parseHeader(input: ExtractorInput): Int {
        val head = ByteArray(4)
        input.peekFully(head, 0, 4)
        val parsed = if (String(head, Charsets.US_ASCII) == "DSD ") parseDsf(input) else parseDff(input)
        if (parsed.channels !in 1..8 || parsed.dsdRate < 2_822_400) {
            throw ParserException.createForMalformedContainer("DSD: ${parsed.channels} ch @ ${parsed.dsdRate}", null)
        }
        info = parsed
        converter = DsdToPcm(parsed.dsdRate, parsed.channels, parsed.lsbFirst)
        framesOut = 0
        bytesPerChannelRead = 0
        publish(parsed)
        return Extractor.RESULT_CONTINUE
    }

    /** Sony DSF: little-endian chunks "DSD ", "fmt ", "data". */
    private fun parseDsf(input: ExtractorInput): DsdInfo {
        val dsd = ByteArray(28)
        input.readFully(dsd, 0, 28)
        val fmtHead = ByteArray(12)
        input.readFully(fmtHead, 0, 12)
        if (String(fmtHead, 0, 4, Charsets.US_ASCII) != "fmt ") throw ParserException.createForMalformedContainer("DSF: no fmt", null)
        val fmtSize = le64(fmtHead, 4)
        val fmt = ByteArray((fmtSize - 12).toInt())
        input.readFully(fmt, 0, fmt.size)
        // fmt body: version, format id, channel type, channel num, sampling freq,
        // bits per sample, sample count (8), block size per channel, reserved.
        val formatId = le32(fmt, 4)
        if (formatId != 0) throw ParserException.createForUnsupportedContainerFeature("DSF format $formatId")
        val channels = le32(fmt, 12)
        val rate = le32(fmt, 16)
        val bitsPerSample = le32(fmt, 20)
        val sampleCount = le64(fmt, 24)
        val blockSize = le32(fmt, 32)
        if (bitsPerSample != 1) throw ParserException.createForUnsupportedContainerFeature("DSF MSB-first")

        val dataHead = ByteArray(12)
        input.readFully(dataHead, 0, 12)
        if (String(dataHead, 0, 4, Charsets.US_ASCII) != "data") throw ParserException.createForMalformedContainer("DSF: no data", null)
        val dataSize = le64(dataHead, 4) - 12
        return DsdInfo(false, channels, rate, sampleCount, input.position, dataSize, blockSize)
    }

    /** Philips DSDIFF: big-endian "FRM8" form with PROP/SND and a "DSD " data chunk. */
    private fun parseDff(input: ExtractorInput): DsdInfo {
        val head = ByteArray(16)
        input.readFully(head, 0, 16)
        var channels = 0
        var rate = 0
        val chunk = ByteArray(12)
        while (true) {
            input.readFully(chunk, 0, 12)
            val id = String(chunk, 0, 4, Charsets.US_ASCII)
            val size = be64(chunk, 4)
            when (id) {
                "PROP" -> {
                    val prop = ByteArray(size.toInt())
                    input.readFully(prop, 0, prop.size)
                    var p = 4 // "SND "
                    while (p + 12 <= prop.size) {
                        val sid = String(prop, p, 4, Charsets.US_ASCII)
                        val ssize = be64(prop, p + 4).toInt()
                        val body = p + 12
                        when (sid) {
                            "FS  " -> rate = be32(prop, body)
                            "CHNL" -> channels = ((prop[body].toInt() and 0xFF) shl 8) or (prop[body + 1].toInt() and 0xFF)
                            "CMPR" -> {
                                val type = String(prop, body, 4, Charsets.US_ASCII)
                                if (type != "DSD ") throw ParserException.createForUnsupportedContainerFeature("DFF compression $type")
                            }
                        }
                        p = body + ssize + (ssize and 1)
                    }
                }
                "DSD " -> {
                    if (channels == 0) throw ParserException.createForMalformedContainer("DFF: no channels", null)
                    return DsdInfo(true, channels, rate, size / channels * 8, input.position, size, 1)
                }
                "DST " -> throw ParserException.createForUnsupportedContainerFeature("DFF DST-compressed")
                else -> input.skipFully((size + (size and 1)).toInt())
            }
        }
    }

    private fun publish(info: DsdInfo) {
        val conv = converter!!
        track.format(
            Format.Builder()
                .setSampleMimeType(MimeTypes.AUDIO_RAW)
                .setChannelCount(info.channels)
                .setSampleRate(conv.outputRate)
                .setPcmEncoding(C.ENCODING_PCM_FLOAT)
                .setLabel(info.label)
                .setAverageBitrate(info.dsdRate * info.channels)
                .build(),
        )
        output.seekMap(object : SeekMap {
            override fun isSeekable() = true
            override fun getDurationUs() = info.durationUs
            override fun getSeekPoints(timeUs: Long): SeekMap.SeekPoints {
                val sample = (timeUs * info.dsdRate / C.MICROS_PER_SECOND).coerceIn(0, maxOf(0, info.samplesPerChannel - 1))
                // Seek to a block (DSF) or byte (DFF) boundary.
                val bytesPerChannel = sample / 8 / info.blockSize * info.blockSize
                val position = info.dataStart + bytesPerChannel * info.channels
                val actualTimeUs = bytesPerChannel * 8 * C.MICROS_PER_SECOND / info.dsdRate
                return SeekMap.SeekPoints(SeekPoint(actualTimeUs, position))
            }
        })
    }

    override fun seek(position: Long, timeUs: Long) {
        val info = info
        if (position == 0L || info == null) {
            this.info = null // Re-read the header from the start.
            return
        }
        bytesPerChannelRead = ((position - info.dataStart) / info.channels).coerceAtLeast(0)
        framesOut = bytesPerChannelRead * 8 / (converter?.totalDecimation ?: 16)
        converter?.reset()
    }

    override fun release() {}

    private fun le32(b: ByteArray, o: Int) =
        (b[o].toInt() and 0xFF) or ((b[o + 1].toInt() and 0xFF) shl 8) or
            ((b[o + 2].toInt() and 0xFF) shl 16) or ((b[o + 3].toInt() and 0xFF) shl 24)

    private fun le64(b: ByteArray, o: Int) =
        (le32(b, o).toLong() and 0xFFFFFFFFL) or (le32(b, o + 4).toLong() shl 32)

    private fun be32(b: ByteArray, o: Int) =
        ((b[o].toInt() and 0xFF) shl 24) or ((b[o + 1].toInt() and 0xFF) shl 16) or
            ((b[o + 2].toInt() and 0xFF) shl 8) or (b[o + 3].toInt() and 0xFF)

    private fun be64(b: ByteArray, o: Int) =
        (be32(b, o).toLong() shl 32) or (be32(b, o + 4).toLong() and 0xFFFFFFFFL)

    companion object {
        private const val DFF_BYTES_PER_READ = 4096
    }
}
