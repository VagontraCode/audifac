package com.gtongfa.audifac.extract

import org.junit.Assert.assertEquals
import org.junit.Test
import java.io.ByteArrayOutputStream
import java.io.DataOutputStream
import java.io.File
import java.io.RandomAccessFile

class Mp4ChaptersTest {
    private fun box(type: String, vararg parts: ByteArray): ByteArray {
        val body = parts.fold(ByteArray(0)) { a, b -> a + b }
        val out = ByteArrayOutputStream()
        DataOutputStream(out).apply { writeInt(8 + body.size); writeBytes(type); write(body) }
        return out.toByteArray()
    }

    private fun ints(vararg v: Int): ByteArray {
        val out = ByteArrayOutputStream()
        DataOutputStream(out).apply { v.forEach { writeInt(it) } }
        return out.toByteArray()
    }

    private fun parse(bytes: ByteArray): List<Mp4Chapters.Chapter> {
        val f = File.createTempFile("chapters", ".m4b")
        try {
            f.writeBytes(bytes)
            return RandomAccessFile(f, "r").use { Mp4Chapters.parse(it.channel) }
        } finally {
            f.delete()
        }
    }

    @Test
    fun neroChpl() {
        fun entry(ms: Long, title: String): ByteArray {
            val out = ByteArrayOutputStream()
            DataOutputStream(out).apply { writeLong(ms * 10_000); writeByte(title.length); writeBytes(title) }
            return out.toByteArray()
        }
        val chpl = box("chpl", byteArrayOf(1, 0, 0, 0), ints(0), byteArrayOf(2), entry(0, "Intro"), entry(65_500, "Chapter 1"))
        val file = box("ftyp", "M4B ".toByteArray()) + box("moov", box("udta", chpl))
        assertEquals(listOf(Mp4Chapters.Chapter(0, "Intro"), Mp4Chapters.Chapter(65_500, "Chapter 1")), parse(file))
    }

    @Test
    fun quickTimeChapterTrack() {
        fun sample(t: String) = byteArrayOf(0, t.length.toByte()) + t.toByteArray()
        val s1 = sample("Opening")
        val s2 = sample("Part Two")
        val ftyp = box("ftyp", "M4B ".toByteArray())
        val mdat = box("mdat", s1, s2)
        val firstSample = ftyp.size + 8 // after the mdat header
        fun tkhd(id: Int) = box("tkhd", ints(0, 0, 0, id, 0, 0))
        val audio = box("trak", tkhd(1), box("tref", box("chap", ints(2))))
        val stbl = box(
            "stbl",
            box("stts", ints(0, 2, 1, 90_000, 1, 30_000)), // 2 entries: 90 s, then 30 s
            box("stsz", ints(0, 0, 2, s1.size, s2.size)),
            box("stsc", ints(0, 1, 1, 2, 1)), // one chunk holding both samples
            box("stco", ints(0, 1, firstSample)),
        )
        val mdhd = box("mdhd", ints(0, 0, 0, 1000, 120_000))
        val text = box("trak", tkhd(2), box("mdia", mdhd, box("minf", stbl)))
        val file = ftyp + mdat + box("moov", audio, text)
        assertEquals(listOf(Mp4Chapters.Chapter(0, "Opening"), Mp4Chapters.Chapter(90_000, "Part Two")), parse(file))
    }

    @Test
    fun noChapters() {
        assertEquals(emptyList<Mp4Chapters.Chapter>(), parse(box("ftyp", "M4A ".toByteArray()) + box("moov", box("trak", ints(0)))))
        assertEquals(emptyList<Mp4Chapters.Chapter>(), parse("ID3 not an mp4 at all".toByteArray()))
    }
}
