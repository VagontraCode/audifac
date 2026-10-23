package com.gtongfa.audifac.extract

import androidx.media3.extractor.Extractor
import androidx.media3.extractor.ExtractorInput
import androidx.media3.extractor.ExtractorOutput
import androidx.media3.extractor.PositionHolder
import androidx.media3.extractor.SeekMap
import androidx.media3.extractor.TrackOutput
import org.junit.Assert.assertEquals
import org.junit.Test

class SourceTaggingExtractorTest {
    /** Announces each of [durationsUs] as a seek map, as an extractor refining its duration does. */
    private class Announcing(private val durationsUs: List<Long>) : Extractor {
        override fun sniff(input: ExtractorInput) = true
        override fun init(output: ExtractorOutput) = durationsUs.forEach { output.seekMap(SeekMap.Unseekable(it)) }
        override fun read(input: ExtractorInput, seekPosition: PositionHolder) = Extractor.RESULT_END_OF_INPUT
        override fun seek(position: Long, timeUs: Long) = Unit
        override fun release() = Unit
    }

    private fun forwarded(vararg durationsUs: Long): List<Long> {
        val seen = ArrayList<Long>()
        val output = object : ExtractorOutput {
            override fun track(id: Int, type: Int): TrackOutput = throw UnsupportedOperationException()
            override fun endTracks() = Unit
            override fun seekMap(seekMap: SeekMap) {
                seen += seekMap.durationUs
            }
        }
        SourceTaggingExtractor(Announcing(durationsUs.toList()), "k").init(output)
        return seen
    }

    @Test
    fun aTinyDurationCorrectionIsDropped() {
        // An MP3's estimated length, corrected by 4 ms at the end of the file.
        assertEquals(listOf(248_924_000L), forwarded(248_924_000L, 248_920_000L))
    }

    @Test
    fun aRealCorrectionGoesThrough() {
        assertEquals(listOf(297_000_000L, 286_000_000L), forwarded(297_000_000L, 286_000_000L))
    }

    @Test
    fun anUnchangedDurationGoesThrough() {
        // Same length, better seeking data: nothing restarts, keep it.
        assertEquals(listOf(10_000_000L, 10_000_000L), forwarded(10_000_000L, 10_000_000L))
    }
}
