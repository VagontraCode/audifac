package com.gtongfa.audifac.extract

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.ByteArrayOutputStream

class HeadersTest {
    @Test
    fun aiffSampleRateIs80BitExtended() {
        // 44100 Hz and 96000 Hz as stored in AIFF COMM chunks.
        val r44 = byteArrayOf(0x40, 0x0E, 0xAC.toByte(), 0x44, 0, 0, 0, 0, 0, 0)
        val r96 = byteArrayOf(0x40, 0x0F, 0xBB.toByte(), 0x80.toByte(), 0, 0, 0, 0, 0, 0)
        assertEquals(44100.0, AiffInfo.extended(r44, 0), 0.0)
        assertEquals(96000.0, AiffInfo.extended(r96, 0), 0.0)
    }

    private fun id3v23(vararg frames: Pair<String, String>): ByteArray {
        val body = ByteArrayOutputStream()
        for ((id, text) in frames) {
            val data = byteArrayOf(3) + text.toByteArray(Charsets.UTF_8) // UTF-8
            body.write(id.toByteArray(Charsets.ISO_8859_1))
            body.write(byteArrayOf((data.size ushr 24).toByte(), (data.size ushr 16).toByte(), (data.size ushr 8).toByte(), data.size.toByte()))
            body.write(byteArrayOf(0, 0))
            body.write(data)
        }
        val b = body.toByteArray()
        val n = b.size
        val size = byteArrayOf(((n shr 21) and 0x7F).toByte(), ((n shr 14) and 0x7F).toByte(), ((n shr 7) and 0x7F).toByte(), (n and 0x7F).toByte())
        return "ID3".toByteArray() + byteArrayOf(3, 0, 0) + size + b
    }

    @Test
    fun readsId3TextFrames() {
        val tags = Id3.parse(
            id3v23(
                "TIT2" to "Kind of Blue",
                "TPE1" to "Miles Davis",
                "TALB" to "Kind of Blue (DSD)",
                "TRCK" to "2/5",
                "TCON" to "(8)",
                "TYER" to "1959",
            ),
        )
        assertEquals("Kind of Blue", tags["title"])
        assertEquals("Miles Davis", tags["artist"])
        assertEquals("Kind of Blue (DSD)", tags["album"])
        assertEquals("2/5", tags["track"])
        assertEquals("Jazz", tags["genre"]) // ID3v1 genre number 8
        assertEquals("1959", tags["year"])
    }

    @Test
    fun ignoresGarbage() {
        assertTrue(Id3.parse(ByteArray(40)).isEmpty())
        assertTrue(Id3.parse("ID3".toByteArray()).isEmpty())
    }
}
