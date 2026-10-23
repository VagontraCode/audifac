package com.gtongfa.audifac.extract

import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.DataReader
import androidx.media3.common.Format
import androidx.media3.common.Metadata
import androidx.media3.common.util.ParsableByteArray
import androidx.media3.common.util.UnstableApi
import androidx.media3.extractor.Extractor
import androidx.media3.extractor.ExtractorInput
import androidx.media3.extractor.ExtractorOutput
import androidx.media3.extractor.PositionHolder
import androidx.media3.extractor.SeekMap
import androidx.media3.extractor.SniffFailure
import androidx.media3.extractor.TrackOutput
import com.gtongfa.audifac.dsp.SourceUri

/**
 * Passes everything through to [delegate], adding a [SourceUri] entry to each
 * audio track's Format so the DSP sink can tell which file is playing.
 */
@OptIn(UnstableApi::class)
class SourceTaggingExtractor(private val delegate: Extractor, private val key: String) : Extractor {
    override fun sniff(input: ExtractorInput): Boolean = delegate.sniff(input)

    override fun getSniffFailureDetails(): List<SniffFailure> = delegate.sniffFailureDetails

    override fun init(output: ExtractorOutput) = delegate.init(TaggingOutput(output))

    override fun read(input: ExtractorInput, seekPosition: PositionHolder): Int = delegate.read(input, seekPosition)

    override fun seek(position: Long, timeUs: Long) = delegate.seek(position, timeUs)

    override fun release() = delegate.release()

    // ExoPlayer checks the real type (e.g. MP3 seeking flags).
    override fun getUnderlyingImplementation(): Extractor = delegate.underlyingImplementation

    private inner class TaggingOutput(private val output: ExtractorOutput) : ExtractorOutput {
        override fun track(id: Int, type: Int): TrackOutput {
            val track = output.track(id, type)
            return if (type == C.TRACK_TYPE_AUDIO) TaggingTrack(track) else track
        }

        override fun endTracks() = output.endTracks()

        private var durationUs = C.TIME_UNSET

        override fun seekMap(seekMap: SeekMap) {
            // MP3s without a length header get an estimated duration, which
            // the extractor corrects at the end of the file — usually by a few
            // milliseconds. ExoPlayer applies any new duration by restarting
            // the playing song where it is: an audible stutter, ~50 s before
            // its end. A correction that small isn't worth one.
            val new = seekMap.durationUs
            val old = durationUs
            if (old != C.TIME_UNSET && new != C.TIME_UNSET && new != old && kotlin.math.abs(new - old) < MAX_IGNORED_CORRECTION_US) return
            durationUs = new
            output.seekMap(seekMap)
        }
    }

    private inner class TaggingTrack(private val track: TrackOutput) : TrackOutput {
        override fun format(format: Format) {
            val tag = SourceUri(key)
            val metadata = format.metadata?.copyWithAppendedEntries(tag) ?: Metadata(tag)
            track.format(format.buildUpon().setMetadata(metadata).build())
        }

        override fun durationUs(durationUs: Long) = track.durationUs(durationUs)

        override fun sampleData(input: DataReader, length: Int, allowEndOfInput: Boolean, sampleDataPart: Int): Int =
            track.sampleData(input, length, allowEndOfInput, sampleDataPart)

        override fun sampleData(data: ParsableByteArray, length: Int, sampleDataPart: Int) =
            track.sampleData(data, length, sampleDataPart)

        override fun sampleMetadata(timeUs: Long, flags: Int, size: Int, offset: Int, cryptoData: TrackOutput.CryptoData?) =
            track.sampleMetadata(timeUs, flags, size, offset, cryptoData)
    }

    private companion object {
        /** Duration corrections below this are dropped (see TaggingOutput.seekMap). */
        const val MAX_IGNORED_CORRECTION_US = 1_000_000L
    }
}
