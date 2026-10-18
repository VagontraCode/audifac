package com.gtongfa.audifac.extract

import android.content.Context
import android.net.Uri
import java.io.FileInputStream
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.channels.FileChannel

/**
 * Chapters of an MP4 / M4B / M4A audiobook: QuickTime chapter tracks (what
 * iTunes and most tools write) or Nero `chpl` lists.
 */
object Mp4Chapters {
    data class Chapter(val startMs: Long, val title: String)

    fun read(context: Context, location: String): List<Chapter> {
        val ext = location.substringAfterLast('.', "").lowercase()
        if (location.startsWith("content://")) {
            val pfd = context.contentResolver.openFileDescriptor(Uri.parse(location), "r") ?: return emptyList()
            return pfd.use { FileInputStream(it.fileDescriptor).channel.use(::parse) }
        }
        if (ext !in setOf("m4b", "m4a", "mp4", "aac", "m4p")) return emptyList()
        return RandomAccessFile(location, "r").use { parse(it.channel) }
    }

    /** One box: where its payload starts and ends. */
    private class Box(val type: String, val start: Long, val end: Long)

    private fun boxes(ch: FileChannel, from: Long, to: Long): List<Box> {
        val out = ArrayList<Box>()
        var pos = from
        val head = ByteBuffer.allocate(16)
        while (pos + 8 <= to) {
            head.clear().limit(8)
            if (ch.read(head, pos) < 8) break
            head.flip()
            var size = head.int.toLong() and 0xFFFFFFFFL
            val type = String(ByteArray(4).also { head.get(it) }, Charsets.ISO_8859_1)
            var header = 8L
            if (size == 1L) {
                head.clear().limit(8)
                ch.read(head, pos + 8)
                head.flip()
                size = head.long
                header = 16
            } else if (size == 0L) {
                size = to - pos
            }
            if (size < header || pos + size > to) break
            out += Box(type, pos + header, pos + size)
            pos += size
        }
        return out
    }

    private fun child(ch: FileChannel, box: Box, type: String, skip: Int = 0) =
        boxes(ch, box.start + skip, box.end).firstOrNull { it.type == type }

    private fun bytes(ch: FileChannel, box: Box, max: Int = 1 shl 20): ByteBuffer {
        val n = minOf(box.end - box.start, max.toLong()).toInt()
        val buf = ByteBuffer.allocate(n)
        ch.read(buf, box.start)
        buf.flip()
        return buf
    }

    fun parse(ch: FileChannel): List<Chapter> {
        val moov = boxes(ch, 0, ch.size()).firstOrNull { it.type == "moov" } ?: return emptyList()
        val tracks = boxes(ch, moov.start, moov.end).filter { it.type == "trak" }
        quickTime(ch, tracks)?.takeIf { it.isNotEmpty() }?.let { return it }
        val chpl = child(ch, moov, "udta")?.let { child(ch, it, "chpl") }
        return chpl?.let { nero(bytes(ch, it)) } ?: emptyList()
    }

    /** Nero: version, flags, [reserved], count, then (start in 100 ns, length, title). */
    fun nero(b: ByteBuffer): List<Chapter> {
        val version = b.get().toInt()
        b.position(b.position() + 3)
        if (version != 0) b.int
        val count = b.get().toInt() and 0xFF
        val out = ArrayList<Chapter>(count)
        repeat(count) {
            if (b.remaining() < 9) return out
            val start = b.long / 10_000
            val len = b.get().toInt() and 0xFF
            if (b.remaining() < len) return out
            val title = String(ByteArray(len).also { b.get(it) }, Charsets.UTF_8)
            out += Chapter(start, title.trim())
        }
        return out
    }

    private fun quickTime(ch: FileChannel, tracks: List<Box>): List<Chapter>? {
        // Track ids referenced as chapters by any track ('tref' → 'chap').
        val chapterIds = HashSet<Int>()
        val byId = HashMap<Int, Box>()
        for (t in tracks) {
            val tkhd = child(ch, t, "tkhd") ?: continue
            val h = bytes(ch, tkhd, 32)
            val version = h.get().toInt()
            h.position(if (version == 1) 4 + 16 else 4 + 8)
            byId[h.int] = t
            child(ch, t, "tref")?.let { tref ->
                child(ch, tref, "chap")?.let { chap ->
                    val b = bytes(ch, chap, 4096)
                    while (b.remaining() >= 4) chapterIds += b.int
                }
            }
        }
        val track = chapterIds.firstNotNullOfOrNull { byId[it] } ?: return null
        val mdia = child(ch, track, "mdia") ?: return null
        val mdhd = bytes(ch, child(ch, mdia, "mdhd") ?: return null, 32)
        val v = mdhd.get().toInt()
        mdhd.position(if (v == 1) 4 + 16 else 4 + 8)
        val timescale = (mdhd.int.toLong() and 0xFFFFFFFFL).takeIf { it > 0 } ?: return null
        val stbl = child(ch, mdia, "minf")?.let { child(ch, it, "stbl") } ?: return null

        // Sample start times (stts).
        val stts = bytes(ch, child(ch, stbl, "stts") ?: return null)
        stts.position(4)
        val starts = ArrayList<Long>()
        var t = 0L
        repeat(stts.int) {
            val count = stts.int
            val delta = stts.int.toLong() and 0xFFFFFFFFL
            repeat(count) { starts += t; t += delta }
        }
        // Sample sizes (stsz).
        val stsz = bytes(ch, child(ch, stbl, "stsz") ?: return null)
        stsz.position(4)
        val fixed = stsz.int
        val n = stsz.int
        val sizes = IntArray(n) { if (fixed != 0) fixed else stsz.int }
        // Chunk offsets (stco / co64) and samples per chunk (stsc).
        val offsets = ArrayList<Long>()
        child(ch, stbl, "stco")?.let { box ->
            val b = bytes(ch, box); b.position(4); repeat(b.int) { offsets += b.int.toLong() and 0xFFFFFFFFL }
        } ?: child(ch, stbl, "co64")?.let { box ->
            val b = bytes(ch, box); b.position(4); repeat(b.int) { offsets += b.long }
        } ?: return null
        val stsc = bytes(ch, child(ch, stbl, "stsc") ?: return null)
        stsc.position(4)
        val runs = List(stsc.int) { Triple(stsc.int, stsc.int, stsc.int) } // firstChunk, samplesPerChunk, desc

        val out = ArrayList<Chapter>()
        var sample = 0
        for ((ri, run) in runs.withIndex()) {
            val lastChunk = if (ri + 1 < runs.size) runs[ri + 1].first - 1 else offsets.size
            for (chunk in run.first..lastChunk) {
                var pos = offsets.getOrNull(chunk - 1) ?: break
                repeat(run.second) {
                    if (sample >= n || sample >= starts.size) return@repeat
                    val size = sizes[sample]
                    if (size >= 2) {
                        val b = ByteBuffer.allocate(minOf(size, 1024))
                        ch.read(b, pos)
                        b.flip()
                        val len = minOf(b.short.toInt() and 0xFFFF, b.remaining())
                        val raw = ByteArray(len).also { b.get(it) }
                        val title = if (len >= 2 && raw[0] == 0xFE.toByte() && raw[1] == 0xFF.toByte()) {
                            String(raw, Charsets.UTF_16)
                        } else {
                            String(raw, Charsets.UTF_8)
                        }
                        out += Chapter(starts[sample] * 1000 / timescale, title.trim())
                    }
                    pos += size
                    sample++
                }
            }
        }
        return out
    }
}
