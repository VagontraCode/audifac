package com.gtongfa.audifac.extract

import androidx.media3.common.Metadata
import androidx.media3.extractor.metadata.flac.VorbisComment
import androidx.media3.extractor.metadata.id3.BinaryFrame
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class LyricsTest {
    @Test
    fun usltLatin1AndUtf8() {
        val latin = byteArrayOf(0) + "eng".toByteArray() + "desc".toByteArray() + 0 + "Café line\nTwo".toByteArray(Charsets.ISO_8859_1)
        assertEquals("Café line\nTwo", Lyrics.parseUslt(latin))
        val utf8 = byteArrayOf(3) + "eng".toByteArray() + 0 + "[00:01.00]Ça va".toByteArray(Charsets.UTF_8) + 0
        assertEquals("[00:01.00]Ça va", Lyrics.parseUslt(utf8))
    }

    @Test
    fun usltUtf16WithBom() {
        val desc = byteArrayOf(0xFF.toByte(), 0xFE.toByte(), 0, 0) // empty descriptor with BOM + terminator
        val text = "Hello".toByteArray(Charsets.UTF_16) // BOM + big-endian
        val data = byteArrayOf(1) + "eng".toByteArray() + desc + text
        assertEquals("Hello", Lyrics.parseUslt(data))
    }

    @Test
    fun fromMetadataPrefersSyncedTags() {
        val m = Metadata(VorbisComment("UNSYNCEDLYRICS", "plain"), VorbisComment("LYRICS", "[00:01]timed"))
        assertEquals("[00:01]timed", Lyrics.fromMetadata(m))
        assertEquals("plain", Lyrics.fromMetadata(Metadata(VorbisComment("UNSYNCEDLYRICS", "plain"))))
        val uslt = BinaryFrame("USLT", byteArrayOf(3) + "eng".toByteArray() + 0 + "words".toByteArray())
        assertEquals("words", Lyrics.fromMetadata(Metadata(uslt)))
        assertNull(Lyrics.fromMetadata(Metadata(VorbisComment("ARTIST", "x"))))
    }
}
