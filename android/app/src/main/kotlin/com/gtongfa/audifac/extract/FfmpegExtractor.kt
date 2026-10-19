package com.gtongfa.audifac.extract

import android.content.Context
import android.net.Uri
import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.ParsableByteArray
import androidx.media3.common.util.UnstableApi
import androidx.media3.extractor.Extractor
import androidx.media3.extractor.ExtractorInput
import androidx.media3.extractor.ExtractorOutput
import androidx.media3.extractor.PositionHolder
import androidx.media3.extractor.SeekMap
import androidx.media3.extractor.SeekPoint
import androidx.media3.extractor.TrackOutput

/**
 * WMA (ASF), Monkey's Audio (APE), WavPack and TTA, which ExoPlayer can't
 * parse. The file is demuxed and decoded by our FFmpeg ([FfmpegReader]) and
 * reaches the player as raw PCM, so the DSP sink (EQ, volume matching,
 * crossfade) works on it like on any other file.
 *
 * ExoPlayer's own input is only advanced alongside FFmpeg's read position:
 * the loader pauses when the buffer is full based on how far the input has
 * moved, so decoding stays a little ahead of playback instead of decoding the
 * whole file into memory.
 */
@OptIn(UnstableApi::class)
class FfmpegExtractor(private val context: Context, private val uri: Uri?) : Extractor {
    private lateinit var output: ExtractorOutput
    private var track: TrackOutput? = null
    private var reader: FfmpegReader? = null
    private var failed = false
    private var pendingSeekUs = C.TIME_UNSET
    private val scratch = ParsableByteArray()

    override fun sniff(input: ExtractorInput): Boolean = sniffFormat(input) != null

    override fun init(output: ExtractorOutput) {
        this.output = output
    }

    override fun read(input: ExtractorInput, seekPosition: PositionHolder): Int {
        val r = reader ?: open() ?: return Extractor.RESULT_END_OF_INPUT
        val t = track ?: return Extractor.RESULT_END_OF_INPUT
        if (pendingSeekUs != C.TIME_UNSET) {
            r.seek(pendingSeekUs)
            pendingSeekUs = C.TIME_UNSET
        }
        if (!r.decode()) return Extractor.RESULT_END_OF_INPUT

        // Hand the frame over in chunks (APE frames can be several seconds long).
        val bytesPerFrame = r.bytesPerFrame
        val frames = r.size / bytesPerFrame
        val data = r.data()
        var done = 0
        while (done < frames) {
            val n = minOf(MAX_FRAMES_PER_SAMPLE, frames - done)
            scratch.reset(data, (done + n) * bytesPerFrame)
            scratch.position = done * bytesPerFrame
            t.sampleData(scratch, n * bytesPerFrame)
            val timeUs = r.frameTimeUs + done * C.MICROS_PER_SECOND / r.sampleRate
            t.sampleMetadata(timeUs, C.BUFFER_FLAG_KEY_FRAME, n * bytesPerFrame, 0, null)
            done += n
        }

        // Keep ExoPlayer's input level with what FFmpeg has read.
        val behind = r.bytePosition - input.position
        if (behind > 0) {
            val length = input.length
            val skip = if (length != C.LENGTH_UNSET.toLong()) minOf(behind, length - input.position) else behind
            if (skip > 0 && !input.skipFully(skip.toInt().coerceAtMost(Int.MAX_VALUE), true)) {
                // The input ended (the file shrank?): FFmpeg still decides when to stop.
            }
        }
        return Extractor.RESULT_CONTINUE
    }

    private fun open(): FfmpegReader? {
        if (failed || uri == null) return null
        val r = FfmpegReader.open(context, uri)
        if (r == null) {
            failed = true
            return null
        }
        reader = r
        val t = output.track(0, C.TRACK_TYPE_AUDIO)
        t.format(
            Format.Builder()
                .setSampleMimeType(MimeTypes.AUDIO_RAW)
                .setCodecs(r.codec)
                .setSampleRate(r.sampleRate)
                .setChannelCount(r.channels)
                .setPcmEncoding(if (r.float) C.ENCODING_PCM_FLOAT else C.ENCODING_PCM_16BIT)
                .setAverageBitrate(if (r.bitrate > 0) r.bitrate.toInt() else Format.NO_VALUE)
                .build(),
        )
        track = t
        output.endTracks()
        val durationUs = if (r.durationUs > 0) r.durationUs else C.TIME_UNSET
        val bitrate = r.bitrate
        output.seekMap(object : SeekMap {
            override fun isSeekable() = durationUs != C.TIME_UNSET
            override fun getDurationUs() = durationUs

            // FFmpeg seeks by time itself; the byte position only reopens
            // ExoPlayer's input a little before where FFmpeg will read, so
            // it isn't read through from the start on every seek.
            override fun getSeekPoints(timeUs: Long): SeekMap.SeekPoints {
                val estimate = if (bitrate > 0) (timeUs / 1e6 * bitrate / 8 * 0.9).toLong() else 0L
                return SeekMap.SeekPoints(SeekPoint(timeUs, estimate))
            }
        })
        return r
    }

    override fun seek(position: Long, timeUs: Long) {
        pendingSeekUs = timeUs
    }

    override fun release() {
        reader?.close()
        reader = null
    }

    enum class Kind { ASF, APE, WAVPACK, TTA }

    companion object {
        /** About 0.19 s at 44.1 kHz: keeps the sample queue fine-grained. */
        private const val MAX_FRAMES_PER_SAMPLE = 8192

        private val ASF_GUID = byteArrayOf(
            0x30, 0x26, 0xB2.toByte(), 0x75, 0x8E.toByte(), 0x66, 0xCF.toByte(), 0x11,
            0xA6.toByte(), 0xD9.toByte(), 0x00, 0xAA.toByte(), 0x00, 0x62, 0xCE.toByte(), 0x6C,
        )

        /** File extensions these formats use (for folder scans). */
        val EXTENSIONS = setOf("wma", "asf", "ape", "wv", "tta")

        fun sniffFormat(input: ExtractorInput): Kind? = try {
            sniff(input)
        } catch (_: java.io.EOFException) {
            null // Shorter than any header.
        }

        private fun sniff(input: ExtractorInput): Kind? {
            val head = ByteArray(16)
            if (!input.peekFully(head, 0, 16, true)) return null
            if (head.contentEquals(ASF_GUID)) return Kind.ASF
            var offset = 0
            // APE / WavPack / TTA files may start with an ID3v2 tag.
            if (head[0] == 'I'.code.toByte() && head[1] == 'D'.code.toByte() && head[2] == '3'.code.toByte()) {
                val size = ((head[6].toInt() and 0x7F) shl 21) or ((head[7].toInt() and 0x7F) shl 14) or
                    ((head[8].toInt() and 0x7F) shl 7) or (head[9].toInt() and 0x7F)
                val footer = if (head[5].toInt() and 0x10 != 0) 10 else 0
                offset = 10 + size + footer
                if (offset > 4 * 1024 * 1024) return null
                input.resetPeekPosition()
                if (!input.advancePeekPosition(offset, true)) return null
                if (!input.peekFully(head, 0, 4, true)) return null
            }
            return when (String(head, 0, 4, Charsets.ISO_8859_1)) {
                "MAC " -> Kind.APE
                "wvpk" -> Kind.WAVPACK
                "TTA1" -> Kind.TTA
                else -> null
            }
        }
    }
}
