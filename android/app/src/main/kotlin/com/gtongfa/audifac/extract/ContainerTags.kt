package com.gtongfa.audifac.extract

import android.content.Context
import android.net.Uri
import java.io.FileInputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.channels.FileChannel

/**
 * Tags Android's metadata reader leaves out: Matroska / WebM audio (`.mka`,
 * `.webm`) and, for phones that miss them, Ogg Opus / Vorbis comments.
 * Keys: title, artist, albumArtist, album, track, genre, year.
 */
object ContainerTags {
    private val extensions = setOf("mka", "mkv", "webm", "weba", "opus", "ogg", "oga")

    fun handles(path: String) = path.substringAfterLast('.', "").lowercase() in extensions

    fun read(context: Context, location: String): Map<String, String> = try {
        val ch = if (location.startsWith("content://")) {
            val fd = context.contentResolver.openFileDescriptor(Uri.parse(location), "r")!!
            FileInputStream(fd.fileDescriptor).channel
        } else {
            FileInputStream(location).channel
        }
        ch.use { read(it) }
    } catch (e: Exception) {
        emptyMap()
    }

    fun read(ch: FileChannel): Map<String, String> {
        val head = bytes(ch, 0, 4) ?: return emptyMap()
        return when {
            head.contentEquals(byteArrayOf(0x1A, 0x45, 0xDF.toByte(), 0xA3.toByte())) -> matroska(ch)
            String(head, Charsets.US_ASCII) == "OggS" -> ogg(ch)
            else -> emptyMap()
        }
    }

    // --- Ogg -----------------------------------------------------------------------

    /** The comment header: the stream's second packet (pages may carry cover art: up to [MAX_PACKET]). */
    private fun ogg(ch: FileChannel): Map<String, String> {
        var pos = 0L
        var packet = java.io.ByteArrayOutputStream()
        var packets = 0
        var serial: Int? = null
        while (pos + 27 <= ch.size()) {
            val h = bytes(ch, pos, 27) ?: break
            if (String(h, 0, 4, Charsets.US_ASCII) != "OggS") break
            val pageSerial = le32(h, 14)
            val segments = h[26].toInt() and 0xFF
            val lacing = bytes(ch, pos + 27, segments) ?: break
            var data = pos + 27 + segments
            pos = data + lacing.sumOf { it.toInt() and 0xFF }
            if (serial == null) serial = pageSerial
            if (pageSerial != serial) continue // Another stream (e.g. a picture track).
            for (lace in lacing) {
                val n = lace.toInt() and 0xFF
                bytes(ch, data, n)?.let { packet.write(it) }
                data += n
                if (packet.size() > MAX_PACKET) return emptyMap()
                if (n < 255) {
                    // End of a packet.
                    if (++packets == 2) return comments(packet.toByteArray())
                    packet = java.io.ByteArrayOutputStream()
                }
            }
        }
        return emptyMap()
    }

    /** `OpusTags` / `\u0003vorbis` header + vendor + `KEY=value` list. */
    fun comments(p: ByteArray): Map<String, String> {
        val start = when {
            p.size >= 8 && String(p, 0, 8, Charsets.US_ASCII) == "OpusTags" -> 8
            p.size >= 7 && p[0].toInt() == 3 && String(p, 1, 6, Charsets.US_ASCII) == "vorbis" -> 7
            else -> return emptyMap()
        }
        val b = ByteBuffer.wrap(p).order(ByteOrder.LITTLE_ENDIAN)
        b.position(start)
        val vendor = b.int
        if (vendor < 0 || vendor > b.remaining()) return emptyMap()
        b.position(b.position() + vendor)
        if (b.remaining() < 4) return emptyMap()
        val count = b.int
        val raw = LinkedHashMap<String, String>()
        repeat(count) {
            if (b.remaining() < 4) return@repeat
            val len = b.int
            if (len < 0 || len > b.remaining()) return@repeat
            val s = String(p, b.position(), len, Charsets.UTF_8)
            b.position(b.position() + len)
            val eq = s.indexOf('=')
            if (eq > 0) raw.putIfAbsent(s.substring(0, eq).uppercase(), s.substring(eq + 1).trim())
        }
        return mapOf(
            "title" to raw["TITLE"],
            "artist" to raw["ARTIST"],
            "albumArtist" to (raw["ALBUMARTIST"] ?: raw["ALBUM ARTIST"]),
            "album" to raw["ALBUM"],
            "track" to raw["TRACKNUMBER"],
            "genre" to raw["GENRE"],
            "year" to raw["DATE"]?.take(4),
        ).filterValues { !it.isNullOrBlank() }.mapValues { it.value!! }
    }

    // --- Matroska --------------------------------------------------------------------

    private const val SEGMENT = 0x18538067L
    private const val SEEK_HEAD = 0x114D9B74L
    private const val SEEK = 0x4DBBL
    private const val SEEK_ID = 0x53ABL
    private const val SEEK_POSITION = 0x53ACL
    private const val INFO = 0x1549A966L
    private const val TITLE = 0x7BA9L
    private const val TAGS = 0x1254C367L
    private const val TAG = 0x7373L
    private const val TARGETS = 0x63C0L
    private const val TARGET_TYPE_VALUE = 0x68CAL
    private const val SIMPLE_TAG = 0x67C8L
    private const val TAG_NAME = 0x45A3L
    private const val TAG_STRING = 0x4487L
    private const val CLUSTER = 0x1F43B675L

    private class Element(val id: Long, val start: Long, val dataStart: Long, val size: Long) {
        val end get() = if (size < 0) Long.MAX_VALUE else dataStart + size
    }

    /** EBML element header at [pos] (null at the end or when broken). */
    private fun element(ch: FileChannel, pos: Long): Element? {
        val h = bytes(ch, pos, minOf(12L, ch.size() - pos).toInt()) ?: return null
        val idLen = vintLength(h[0]) ?: return null
        if (idLen > 4 || idLen >= h.size) return null
        var id = 0L
        for (i in 0 until idLen) id = (id shl 8) or (h[i].toLong() and 0xFF)
        val sizeLen = vintLength(h[idLen]) ?: return null
        if (idLen + sizeLen > h.size) return null
        var size = (h[idLen].toLong() and (0xFFL shr sizeLen))
        var allOnes = size == (0xFFL shr sizeLen)
        for (i in 1 until sizeLen) {
            val v = h[idLen + i].toLong() and 0xFF
            size = (size shl 8) or v
            if (v != 0xFFL) allOnes = false
        }
        return Element(id, pos, pos + idLen + sizeLen, if (allOnes) -1 else size)
    }

    private fun vintLength(first: Byte): Int? {
        val b = first.toInt() and 0xFF
        for (n in 1..8) if (b and (0x80 shr (n - 1)) != 0) return n
        return null
    }

    private fun children(ch: FileChannel, parent: Element, limit: Long = ch.size()): Sequence<Element> = sequence {
        var pos = parent.dataStart
        val end = minOf(parent.end, limit)
        while (pos < end) {
            val e = element(ch, pos) ?: break
            yield(e)
            if (e.size < 0) break
            pos = e.end
        }
    }

    private fun uint(ch: FileChannel, e: Element): Long {
        val b = bytes(ch, e.dataStart, e.size.toInt().coerceIn(0, 8)) ?: return 0
        return b.fold(0L) { acc, x -> (acc shl 8) or (x.toLong() and 0xFF) }
    }

    private fun string(ch: FileChannel, e: Element): String? =
        bytes(ch, e.dataStart, e.size.toInt().coerceIn(0, 4096))?.toString(Charsets.UTF_8)?.trimEnd('\u0000')?.trim()

    private fun matroska(ch: FileChannel): Map<String, String> {
        val ebml = element(ch, 0) ?: return emptyMap()
        val segment = element(ch, ebml.end).takeIf { it?.id == SEGMENT } ?: return emptyMap()
        // Top-level elements before the first cluster, plus whatever the
        // SeekHead points at (Tags usually sit after the audio).
        val found = HashMap<Long, Long>() // id → position
        for (e in children(ch, segment)) {
            if (e.id == CLUSTER) break
            found.putIfAbsent(e.id, e.start)
            if (e.id == SEEK_HEAD) {
                for (seek in children(ch, e).filter { it.id == SEEK }) {
                    var id = 0L
                    var at = -1L
                    for (f in children(ch, seek)) {
                        when (f.id) {
                            SEEK_ID -> id = uint(ch, f)
                            SEEK_POSITION -> at = uint(ch, f)
                        }
                    }
                    if (at >= 0) found.putIfAbsent(id, segment.dataStart + at)
                }
            }
        }
        val title = found[INFO]?.let { element(ch, it) }?.takeIf { it.id == INFO }
            ?.let { info -> children(ch, info).firstOrNull { it.id == TITLE }?.let { string(ch, it) } }
        // Tag name → value, by target level (50 album, 30 track).
        val byLevel = HashMap<Long, HashMap<String, String>>()
        found[TAGS]?.let { element(ch, it) }?.takeIf { it.id == TAGS }?.let { tags ->
            for (tag in children(ch, tags).filter { it.id == TAG }) {
                var level = 50L
                val values = HashMap<String, String>()
                for (f in children(ch, tag)) {
                    when (f.id) {
                        TARGETS -> children(ch, f).firstOrNull { it.id == TARGET_TYPE_VALUE }?.let { level = uint(ch, it) }
                        SIMPLE_TAG -> {
                            var name: String? = null
                            var value: String? = null
                            for (g in children(ch, f)) {
                                when (g.id) {
                                    TAG_NAME -> name = string(ch, g)?.uppercase()
                                    TAG_STRING -> value = string(ch, g)
                                }
                            }
                            if (name != null && !value.isNullOrBlank()) values.putIfAbsent(name, value)
                        }
                    }
                }
                byLevel.getOrPut(level) { HashMap() }.putAll(values)
            }
        }
        val track = byLevel[30] ?: emptyMap()
        val album = byLevel[50] ?: emptyMap()
        return mapOf(
            "title" to (track["TITLE"] ?: title),
            "artist" to (track["ARTIST"] ?: album["ARTIST"]),
            "albumArtist" to album["ARTIST"],
            "album" to album["TITLE"],
            "track" to track["PART_NUMBER"],
            "genre" to (track["GENRE"] ?: album["GENRE"]),
            "year" to (track["DATE_RELEASED"] ?: album["DATE_RELEASED"])?.take(4),
        ).filterValues { !it.isNullOrBlank() }.mapValues { it.value!! }
    }

    // --- Bytes ---------------------------------------------------------------------------

    private const val MAX_PACKET = 16 * 1024 * 1024

    private fun bytes(ch: FileChannel, position: Long, length: Int): ByteArray? {
        if (length < 0 || position < 0 || position + length > ch.size()) return null
        val buf = ByteBuffer.allocate(length)
        while (buf.hasRemaining()) if (ch.read(buf, position + buf.position()) < 0) return null
        return buf.array()
    }

    private fun le32(b: ByteArray, o: Int) =
        (b[o].toInt() and 0xFF) or ((b[o + 1].toInt() and 0xFF) shl 8) or
            ((b[o + 2].toInt() and 0xFF) shl 16) or ((b[o + 3].toInt() and 0xFF) shl 24)
}
