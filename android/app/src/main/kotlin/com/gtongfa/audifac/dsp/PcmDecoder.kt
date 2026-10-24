package com.gtongfa.audifac.dsp

import android.content.Context
import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.net.Uri
import java.nio.ByteOrder

/**
 * Decodes a file's first audio track to float samples, as fast as the codec
 * goes (for analysis, not playback). Shared by the loudness scanner and the
 * waveform.
 */
object PcmDecoder {
    interface Sink {
        /** The stream's format (again if it changes mid-stream). */
        fun format(rate: Int, channels: Int)

        /** [frames] interleaved frames in [samples]. */
        fun samples(samples: FloatArray, frames: Int)
    }

    private const val TIMEOUT_US = 10_000L

    /**
     * Decodes [location] from [startUs] to [endUs] (whole file by default).
     * Returns false if there is no audio track.
     */
    fun decode(context: Context, location: String, sink: Sink, startUs: Long = 0, endUs: Long = Long.MAX_VALUE): Boolean {
        val extractor = MediaExtractor()
        var codec: MediaCodec? = null
        try {
            if (location.startsWith("content://")) extractor.setDataSource(context, Uri.parse(location), null)
            else extractor.setDataSource(location)
            val track = (0 until extractor.trackCount).firstOrNull {
                extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true
            } ?: return false
            extractor.selectTrack(track)
            if (startUs > 0) extractor.seekTo(startUs, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
            val format = extractor.getTrackFormat(track)
            val mime = format.getString(MediaFormat.KEY_MIME)!!
            // No float request: 16-bit is plenty for analysis, and Samsung's
            // decoders write 16-bit while reporting float when asked for it
            // (which measured garbage).
            codec = MediaCodec.createDecoderByType(mime).apply {
                configure(format, null, null, 0)
                start()
            }

            val info = MediaCodec.BufferInfo()
            var channels = 0
            var float = false
            var started = false
            var samples = FloatArray(0)
            var shorts = ShortArray(0)
            var inputDone = false

            fun start(f: MediaFormat) {
                channels = f.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                float = f.containsKey(MediaFormat.KEY_PCM_ENCODING) &&
                    f.getInteger(MediaFormat.KEY_PCM_ENCODING) == AudioFormat.ENCODING_PCM_FLOAT
                sink.format(f.getInteger(MediaFormat.KEY_SAMPLE_RATE), channels)
                started = true
            }

            /** Takes one output buffer; true at the end (of the stream or the range). */
            fun drain(index: Int): Boolean {
                if (!started) start(codec.outputFormat)
                val end = info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                // Before the range (the seek lands on an earlier sync point) or past it.
                if (info.presentationTimeUs < startUs || info.presentationTimeUs >= endUs) {
                    codec.releaseOutputBuffer(index, false)
                    return end || info.presentationTimeUs >= endUs
                }
                val buffer = codec.getOutputBuffer(index)!!
                buffer.position(info.offset)
                buffer.limit(info.offset + info.size)
                buffer.order(ByteOrder.nativeOrder())
                val count = if (float) info.size / 4 else info.size / 2
                if (samples.size < count) {
                    samples = FloatArray(count)
                    shorts = ShortArray(count)
                }
                if (float) {
                    buffer.asFloatBuffer().get(samples, 0, count)
                } else {
                    buffer.asShortBuffer().get(shorts, 0, count)
                    for (i in 0 until count) samples[i] = shorts[i] / 32768f
                }
                if (channels > 0) sink.samples(samples, count / channels)
                codec.releaseOutputBuffer(index, false)
                return end
            }

            // Keep every input slot full and take every ready output; only
            // wait when the codec has nothing for us (a lock-step loop with
            // timeouts spends most of its time waiting).
            var ended = false
            while (!ended) {
                var progressed = false
                while (!inputDone) {
                    val index = codec.dequeueInputBuffer(0)
                    if (index < 0) break
                    val buffer = codec.getInputBuffer(index)!!
                    val size = extractor.readSampleData(buffer, 0)
                    if (size < 0 || extractor.sampleTime >= endUs) {
                        codec.queueInputBuffer(index, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                        inputDone = true
                    } else {
                        codec.queueInputBuffer(index, 0, size, extractor.sampleTime, 0)
                        extractor.advance()
                    }
                    progressed = true
                }
                while (!ended) {
                    val index = codec.dequeueOutputBuffer(info, if (progressed) 0 else TIMEOUT_US)
                    when {
                        index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> start(codec.outputFormat)
                        index >= 0 -> ended = drain(index)
                        else -> break // Nothing ready.
                    }
                    progressed = true
                }
            }
            return true
        } finally {
            try {
                codec?.stop()
            } catch (_: Exception) {
            }
            codec?.release()
            extractor.release()
        }
    }
}
