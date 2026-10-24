package com.gtongfa.audifac.extract

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder

class ContainerTagsTest {
    private fun channel(bytes: ByteArray) = File.createTempFile("tags", ".bin").apply {
        deleteOnExit()
        writeBytes(bytes)
    }.let { RandomAccessFile(it, "r").channel }

    private fun le32(v: Int) = ByteBuffer.allocate(4).order(ByteOrder.LITTLE_ENDIAN).putInt(v).array()

    private fun vorbisComment(header: ByteArray, vararg entries: String): ByteArray {
        val out = ByteArrayOutputStream()
        out.write(header)
        val vendor = "libopus 1.4".toByteArray()
        out.write(le32(vendor.size))
        out.write(vendor)
        out.write(le32(entries.size))
        for (e in entries) {
            val b = e.toByteArray(Charsets.UTF_8)
            out.write(le32(b.size))
            out.write(b)
        }
        return out.toByteArray()
    }

    /** One Ogg page holding [packets] (whole), for stream [serial]. */
    private fun page(serial: Int, vararg packets: ByteArray): ByteArray {
        val lacing = ByteArrayOutputStream()
        val body = ByteArrayOutputStream()
        for (p in packets) {
            var n = p.size
            while (n >= 255) {
                lacing.write(255)
                n -= 255
            }
            lacing.write(n)
            body.write(p)
        }
        val h = ByteArray(27)
        "OggS".toByteArray().copyInto(h)
        le32(serial).copyInto(h, 14)
        h[26] = lacing.size().toByte()
        return h + lacing.toByteArray() + body.toByteArray()
    }

    @Test
    fun opusTagsAcrossSegmentsSkippingOtherStreams() {
        val head = "OpusHead".toByteArray() + ByteArray(11)
        // A long comment (real files carry cover art here): many 255-byte laces.
        val tags = vorbisComment(
            "OpusTags".toByteArray(),
            "TITLE=Été", "artist=Zaz", "ALBUM=Recto Verso", "TRACKNUMBER=3/12", "DATE=2013-05-13",
            "METADATA_BLOCK_PICTURE=" + "A".repeat(2000),
        )
        val t = ContainerTags.read(channel(page(7, head) + page(9, ByteArray(30)) + page(7, tags)))
        assertEquals("Été", t["title"])
        assertEquals("Zaz", t["artist"])
        assertEquals("Recto Verso", t["album"])
        assertEquals("3/12", t["track"])
        assertEquals("2013", t["year"])
    }

    @Test
    fun vorbisCommentHeader() {
        val t = ContainerTags.comments(vorbisComment(byteArrayOf(3) + "vorbis".toByteArray(), "ALBUMARTIST=Various", "GENRE=Jazz"))
        assertEquals("Various", t["albumArtist"])
        assertEquals("Jazz", t["genre"])
        assertTrue(ContainerTags.comments("nope".toByteArray()).isEmpty())
    }

    // --- Matroska ---

    private fun id(v: Long): ByteArray {
        val n = when {
            v > 0xFFFFFF -> 4
            v > 0xFFFF -> 3
            v > 0xFF -> 2
            else -> 1
        }
        return ByteArray(n) { ((v shr (8 * (n - 1 - it))) and 0xFF).toByte() }
    }

    /** Element with an 8-byte size. */
    private fun el(idValue: Long, vararg children: ByteArray): ByteArray {
        val payload = children.fold(ByteArray(0)) { a, b -> a + b }
        val size = ByteArray(8) { if (it == 0) 0x01 else ((payload.size.toLong() shr (8 * (7 - it))) and 0xFF).toByte() }
        return id(idValue) + size + payload
    }

    private fun str(idValue: Long, s: String) = el(idValue, s.toByteArray())

    private fun uint(idValue: Long, v: Long) =
        el(idValue, byteArrayOf(((v shr 24) and 0xFF).toByte(), ((v shr 16) and 0xFF).toByte(), ((v shr 8) and 0xFF).toByte(), (v and 0xFF).toByte()))

    private fun simple(name: String, value: String) = el(0x67C8, str(0x45A3, name), str(0x4487, value))

    @Test
    fun matroskaTagsAfterTheClustersViaSeekHead() {
        val ebml = el(0x1A45DFA3, str(0x4282, "matroska"))
        val info = el(0x1549A966, str(0x7BA9, "Segment title"))
        val cluster = el(0x1F43B675, ByteArray(5000))
        val tags = el(
            0x1254C367,
            el(0x7373, el(0x63C0, uint(0x68CA, 50)), simple("TITLE", "Kind of Blue"), simple("ARTIST", "Miles Davis"), simple("DATE_RELEASED", "1959")),
            el(0x7373, el(0x63C0, uint(0x68CA, 30)), simple("TITLE", "So What"), simple("PART_NUMBER", "1")),
        )
        // Positions are relative to the segment's data; the SeekHead has a fixed size.
        fun seekHead(tagsAt: Long) = el(0x114D9B74, el(0x4DBB, el(0x53AB, id(0x1254C367)), uint(0x53AC, tagsAt)))
        val tagsAt = (seekHead(0).size + info.size + cluster.size).toLong()
        val segment = el(0x18538067, seekHead(tagsAt), info, cluster, tags)
        val t = ContainerTags.read(channel(ebml + segment))
        assertEquals("So What", t["title"])
        assertEquals("Miles Davis", t["artist"])
        assertEquals("Miles Davis", t["albumArtist"])
        assertEquals("Kind of Blue", t["album"])
        assertEquals("1", t["track"])
        assertEquals("1959", t["year"])
    }

    @Test
    fun matroskaWithoutTagsFallsBackToTheSegmentTitle() {
        val ebml = el(0x1A45DFA3, str(0x4282, "webm"))
        val segment = el(0x18538067, el(0x1549A966, str(0x7BA9, "Live set")), el(0x1F43B675, ByteArray(10)))
        assertEquals(mapOf("title" to "Live set"), ContainerTags.read(channel(ebml + segment)))
    }

    @Test
    fun dffNativeTitleAndArtist() {
        fun chunk(name: String, payload: ByteArray): ByteArray =
            name.toByteArray() + ByteBuffer.allocate(8).putLong(payload.size.toLong()).array() + payload +
                (if (payload.size % 2 == 1) byteArrayOf(0) else ByteArray(0))
        fun text(s: String) = ByteBuffer.allocate(4).putInt(s.length).array() + s.toByteArray()
        val prop = chunk(
            "PROP",
            "SND ".toByteArray() +
                chunk("FS  ", ByteBuffer.allocate(4).putInt(2822400).array()) +
                chunk("CHNL", byteArrayOf(0, 2) + "SLFTSRGT".toByteArray()),
        )
        val diin = chunk("DIIN", chunk("DIAR", text("Miles Davis")) + chunk("DITI", text("So What")))
        val dsd = chunk("DSD ", ByteArray(2822400 / 8 * 2)) // one second, stereo
        val body = "DSD ".toByteArray() + prop + diin + dsd
        val file = "FRM8".toByteArray() + ByteBuffer.allocate(8).putLong(body.size.toLong()).array() + body
        val info = AudioHeaders.probe(channel(file))!!
        assertEquals("So What", info.tags["title"])
        assertEquals("Miles Davis", info.tags["artist"])
        assertEquals(1000L, info.durationMs)
    }
}
