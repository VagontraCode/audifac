package com.gtongfa.audifac.extract

import androidx.media3.common.C
import androidx.media3.common.DataReader
import androidx.media3.extractor.DefaultExtractorInput
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** Which files the FFmpeg extractor claims (the rest go to ExoPlayer's parsers). */
class FfmpegSniffTest {
    private fun input(bytes: ByteArray): DefaultExtractorInput {
        var pos = 0
        val reader = object : DataReader {
            override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
                if (pos >= bytes.size) return C.RESULT_END_OF_INPUT
                val n = minOf(length, bytes.size - pos)
                System.arraycopy(bytes, pos, buffer, offset, n)
                pos += n
                return n
            }
        }
        return DefaultExtractorInput(reader, 0, bytes.size.toLong())
    }

    private fun file(head: ByteArray) = head + ByteArray(64)

    private fun ascii(s: String) = s.toByteArray(Charsets.ISO_8859_1)

    @Test
    fun asfHeaderGuidIsWma() {
        val guid = byteArrayOf(
            0x30, 0x26, 0xB2.toByte(), 0x75, 0x8E.toByte(), 0x66, 0xCF.toByte(), 0x11,
            0xA6.toByte(), 0xD9.toByte(), 0x00, 0xAA.toByte(), 0x00, 0x62, 0xCE.toByte(), 0x6C,
        )
        assertEquals(FfmpegExtractor.Kind.ASF, FfmpegExtractor.sniffFormat(input(file(guid))))
    }

    @Test
    fun losslessSignatures() {
        assertEquals(FfmpegExtractor.Kind.APE, FfmpegExtractor.sniffFormat(input(file(ascii("MAC ")))))
        assertEquals(FfmpegExtractor.Kind.WAVPACK, FfmpegExtractor.sniffFormat(input(file(ascii("wvpk")))))
        assertEquals(FfmpegExtractor.Kind.TTA, FfmpegExtractor.sniffFormat(input(file(ascii("TTA1")))))
    }

    @Test
    fun apeAfterAnId3Tag() {
        // ID3v2.4, no flags, 100-byte body (syncsafe), then the APE header.
        val id3 = ascii("ID3") + byteArrayOf(4, 0, 0, 0, 0, 0, 100) + ByteArray(100)
        assertEquals(FfmpegExtractor.Kind.APE, FfmpegExtractor.sniffFormat(input(file(id3 + ascii("MAC ")))))
    }

    @Test
    fun otherFilesAreLeftToExoPlayer() {
        assertNull(FfmpegExtractor.sniffFormat(input(file(ascii("fLaC")))))
        assertNull(FfmpegExtractor.sniffFormat(input(file(ascii("RIFF")))))
        // An MP3 with an ID3 tag.
        val id3 = ascii("ID3") + byteArrayOf(3, 0, 0, 0, 0, 0, 20) + ByteArray(20)
        assertNull(FfmpegExtractor.sniffFormat(input(file(id3 + byteArrayOf(0xFF.toByte(), 0xFB.toByte(), 0x90.toByte(), 0x64)))))
        assertNull(FfmpegExtractor.sniffFormat(input(ByteArray(3))))
    }
}
