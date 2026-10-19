package com.gtongfa.audifac.extract

import android.content.Context
import android.net.Uri
import android.os.ParcelFileDescriptor
import java.io.FileInputStream
import java.nio.ByteBuffer
import java.nio.channels.FileChannel

/**
 * Technical info + tags for formats Android's MediaExtractor /
 * MediaMetadataRetriever can't read: AIFF / AIFC and DSD (DSF, DFF).
 * Tags come from the ID3v2 block these formats carry (DSF: at the metadata
 * pointer; AIFF / DFF: an "ID3 " chunk).
 */
object AudioHeaders {
    data class Info(
        val codecMime: String,
        val sampleRate: Int,
        val channels: Int,
        val bitDepth: Int,
        val durationMs: Long,
        val bitrate: Int,
        val tags: Map<String, String>,
    )

    private val extensions = setOf("aif", "aiff", "aifc", "dsf", "dff") + FfmpegExtractor.EXTENSIONS

    /** AIFF / DSD / WMA / APE / WavPack / TTA by file extension. */
    fun isOwnFormat(path: String) = path.substringAfterLast('.', "").lowercase() in extensions

    /** Returns null when the file isn't one of the formats above. */
    fun probe(context: Context, location: String): Info? = try {
        open(context, location).use { ch ->
            val head = read(ch, 0, 16) ?: return null
            when {
                ascii(head, 0, 4) == "FORM" && (ascii(head, 8, 4) == "AIFF" || ascii(head, 8, 4) == "AIFC") -> aiff(ch)
                ascii(head, 0, 4) == "DSD " -> dsf(ch)
                ascii(head, 0, 4) == "FRM8" && ascii(head, 12, 4) == "DSD " -> dff(ch)
                else -> null
            }
        } ?: ffmpeg(context, location)
    } catch (e: Exception) {
        null
    }

    /** FFmpeg codec name → the MIME type the app labels it by. */
    fun mimeForFfmpegCodec(codec: String): String? = when (codec) {
        "wmav1", "wmav2" -> "audio/x-ms-wma"
        "wmapro" -> "audio/x-ms-wma-pro"
        "wmalossless" -> "audio/x-ms-wma-lossless"
        "ape" -> "audio/x-ape"
        "wavpack" -> "audio/x-wavpack"
        "tta" -> "audio/x-tta"
        else -> null
    }

    /** WMA / APE / WavPack / TTA through our FFmpeg (tags: ASF, APEv2, ID3). */
    private fun ffmpeg(context: Context, location: String): Info? {
        if (location.substringAfterLast('.', "").lowercase() !in FfmpegExtractor.EXTENSIONS &&
            !location.startsWith("content://")
        ) return null
        val uri = if (location.startsWith("content://")) Uri.parse(location) else Uri.fromFile(java.io.File(location))
        return FfmpegReader.open(context, uri)?.use { r ->
            val mime = mimeForFfmpegCodec(r.codec) ?: return null
            val t = r.tags()
            val tags = HashMap<String, String>()
            fun take(key: String, vararg names: String) {
                names.firstNotNullOfOrNull { t[it]?.trim()?.takeIf { v -> v.isNotEmpty() } }?.let { tags[key] = it }
            }
            take("title", "title")
            take("artist", "artist", "author")
            take("album", "album")
            take("albumArtist", "album_artist", "album artist", "albumartist")
            take("track", "track", "tracknumber")
            take("disc", "disc", "discnumber")
            take("genre", "genre")
            take("year", "date", "year")
            take("composer", "composer")
            Info(
                codecMime = mime,
                sampleRate = r.sampleRate,
                channels = r.channels,
                bitDepth = r.sourceBits,
                durationMs = if (r.durationUs > 0) r.durationUs / 1000 else 0,
                bitrate = r.bitrate.toInt(),
                tags = tags,
            )
        }
    }

    private fun open(context: Context, location: String): FileChannel =
        if (location.startsWith("content://")) {
            val pfd = context.contentResolver.openFileDescriptor(Uri.parse(location), "r")
                ?: throw IllegalStateException("Cannot open $location")
            // Closing the channel closes the stream, which closes the descriptor.
            ParcelFileDescriptor.AutoCloseInputStream(pfd).channel
        } else {
            FileInputStream(location).channel
        }

    private fun read(ch: FileChannel, position: Long, length: Int): ByteArray? {
        if (length <= 0 || position < 0) return null
        val buf = ByteBuffer.allocate(length)
        var p = position
        while (buf.hasRemaining()) {
            val n = ch.read(buf, p)
            if (n <= 0) break
            p += n
        }
        return if (buf.position() == length) buf.array() else null
    }

    // --- AIFF ---------------------------------------------------------------

    private fun aiff(ch: FileChannel): Info? {
        val isAifc = ascii(read(ch, 8, 4)!!, 0, 4) == "AIFC"
        var pos = 12L
        var channels = 0
        var frames = 0L
        var bits = 0
        var rate = 0.0
        var compression = "NONE"
        var tags = emptyMap<String, String>()
        val size = ch.size()
        while (pos + 8 <= size) {
            val h = read(ch, pos, 8) ?: break
            val id = ascii(h, 0, 4)
            val len = be32(h, 4).toLong() and 0xFFFFFFFFL
            when (id) {
                "COMM" -> read(ch, pos + 8, len.toInt())?.let { c ->
                    channels = be16(c, 0)
                    frames = be32(c, 2).toLong() and 0xFFFFFFFFL
                    bits = be16(c, 6)
                    rate = AiffInfo.extended(c, 8)
                    if (isAifc && c.size >= 22) compression = ascii(c, 18, 4)
                }
                "ID3 ", "id3 " -> read(ch, pos + 8, minOf(len, MAX_TAG).toInt())?.let { tags = Id3.parse(it) }
            }
            pos += 8 + len + (len and 1)
        }
        if (channels == 0 || rate <= 0) return null
        val float = compression.equals("fl32", true) || compression.equals("fl64", true)
        val depth = if (compression.equals("fl64", true)) 64 else if (float) 32 else bits
        return Info(
            codecMime = "audio/x-aiff",
            sampleRate = rate.toInt(),
            channels = channels,
            bitDepth = depth,
            durationMs = frames * 1000 / rate.toLong(),
            bitrate = (rate * channels * depth).toInt(),
            tags = tags,
        )
    }

    // --- DSD --------------------------------------------------------------------

    private fun dsf(ch: FileChannel): Info? {
        val dsd = read(ch, 0, 28) ?: return null
        val metadataPointer = le64(dsd, 20)
        val fmt = read(ch, 28, 52) ?: return null
        if (ascii(fmt, 0, 4) != "fmt ") return null
        val channels = le32(fmt, 24)
        val rate = le32(fmt, 28)
        val samples = le64(fmt, 36)
        val tags = if (metadataPointer > 0 && metadataPointer < ch.size()) {
            read(ch, metadataPointer, minOf(ch.size() - metadataPointer, MAX_TAG).toInt())?.let(Id3::parse).orEmpty()
        } else {
            emptyMap()
        }
        return Info("audio/x-dsd", rate, channels, 1, samples * 1000 / rate, rate * channels, tags)
    }

    private fun dff(ch: FileChannel): Info? {
        var pos = 16L
        var channels = 0
        var rate = 0
        var dataSize = 0L
        var tags = emptyMap<String, String>()
        val size = ch.size()
        while (pos + 12 <= size) {
            val h = read(ch, pos, 12) ?: break
            val id = ascii(h, 0, 4)
            val len = be64(h, 4)
            when (id) {
                "PROP" -> read(ch, pos + 12, len.toInt())?.let { prop ->
                    var p = 4
                    while (p + 12 <= prop.size) {
                        val sid = ascii(prop, p, 4)
                        val slen = be64(prop, p + 4).toInt()
                        if (sid == "FS  ") rate = be32(prop, p + 12)
                        if (sid == "CHNL") channels = be16(prop, p + 12)
                        p += 12 + slen + (slen and 1)
                    }
                }
                "DSD " -> dataSize = len
                "ID3 " -> read(ch, pos + 12, minOf(len, MAX_TAG).toInt())?.let { tags = Id3.parse(it) }
            }
            pos += 12 + len + (len and 1)
        }
        if (channels == 0 || rate == 0) return null
        val samples = dataSize / channels * 8
        return Info("audio/x-dsd", rate, channels, 1, samples * 1000 / rate, rate * channels, tags)
    }

    private const val MAX_TAG = 4L * 1024 * 1024

    private fun ascii(b: ByteArray, o: Int, n: Int) = String(b, o, n, Charsets.US_ASCII)
    private fun be16(b: ByteArray, o: Int) = ((b[o].toInt() and 0xFF) shl 8) or (b[o + 1].toInt() and 0xFF)
    private fun be32(b: ByteArray, o: Int) =
        ((b[o].toInt() and 0xFF) shl 24) or ((b[o + 1].toInt() and 0xFF) shl 16) or
            ((b[o + 2].toInt() and 0xFF) shl 8) or (b[o + 3].toInt() and 0xFF)
    private fun be64(b: ByteArray, o: Int) = (be32(b, o).toLong() shl 32) or (be32(b, o + 4).toLong() and 0xFFFFFFFFL)
    private fun le32(b: ByteArray, o: Int) =
        (b[o].toInt() and 0xFF) or ((b[o + 1].toInt() and 0xFF) shl 8) or
            ((b[o + 2].toInt() and 0xFF) shl 16) or ((b[o + 3].toInt() and 0xFF) shl 24)
    private fun le64(b: ByteArray, o: Int) = (le32(b, o).toLong() and 0xFFFFFFFFL) or (le32(b, o + 4).toLong() shl 32)
}

/** Minimal ID3v2.2 / 2.3 / 2.4 text-frame reader. */
object Id3 {
    /** Keys: title, artist, album, albumArtist, track, disc, genre, year, composer. */
    fun parse(tag: ByteArray): Map<String, String> {
        if (tag.size < 10 || String(tag, 0, 3, Charsets.ISO_8859_1) != "ID3") return emptyMap()
        val major = tag[3].toInt()
        val size = syncsafe(tag, 6)
        val end = minOf(tag.size, 10 + size)
        val out = HashMap<String, String>()
        var p = 10
        if (tag[5].toInt() and 0x40 != 0 && major >= 3) {
            // Extended header: skip it.
            val ext = if (major == 4) syncsafe(tag, p) else be32(tag, p) + 4
            p += ext
        }
        val idLen = if (major == 2) 3 else 4
        val headerLen = if (major == 2) 6 else 10
        while (p + headerLen <= end) {
            val id = String(tag, p, idLen, Charsets.ISO_8859_1)
            if (id[0] == '\u0000') break
            val frameSize = when (major) {
                2 -> ((tag[p + 3].toInt() and 0xFF) shl 16) or ((tag[p + 4].toInt() and 0xFF) shl 8) or (tag[p + 5].toInt() and 0xFF)
                4 -> syncsafe(tag, p + 4)
                else -> be32(tag, p + 4)
            }
            val body = p + headerLen
            if (frameSize <= 0 || body + frameSize > end) break
            val key = KEYS[id]
            if (key != null && id[0] == 'T') {
                text(tag, body, frameSize)?.let { value ->
                    out[key] = if (key == "genre") genre(value) else value
                }
            }
            p = body + frameSize
        }
        return out
    }

    private val KEYS = mapOf(
        "TIT2" to "title", "TT2" to "title",
        "TPE1" to "artist", "TP1" to "artist",
        "TALB" to "album", "TAL" to "album",
        "TPE2" to "albumArtist", "TP2" to "albumArtist",
        "TRCK" to "track", "TRK" to "track",
        "TPOS" to "disc", "TPA" to "disc",
        "TCON" to "genre", "TCO" to "genre",
        "TYER" to "year", "TDRC" to "year", "TYE" to "year",
        "TCOM" to "composer", "TCM" to "composer",
    )

    private fun text(b: ByteArray, o: Int, len: Int): String? {
        if (len < 2) return null
        val charset = when (b[o].toInt()) {
            1 -> Charsets.UTF_16
            2 -> Charsets.UTF_16BE
            3 -> Charsets.UTF_8
            else -> Charsets.ISO_8859_1
        }
        // v2.4 allows several NUL-separated values: keep the first.
        return String(b, o + 1, len - 1, charset).split('\u0000').firstOrNull()?.trim()?.takeIf { it.isNotEmpty() }
    }

    /** "(17)" / "(17)Rock" / "17" → genre name from ID3v1 numbering (common ones). */
    private fun genre(value: String): String {
        val m = Regex("^\\(?(\\d+)\\)?(.*)$").find(value) ?: return value
        val rest = m.groupValues[2].trim()
        if (rest.isNotEmpty()) return rest
        return GENRES.getOrNull(m.groupValues[1].toInt()) ?: value
    }

    private val GENRES = listOf(
        "Blues", "Classic Rock", "Country", "Dance", "Disco", "Funk", "Grunge", "Hip-Hop", "Jazz", "Metal",
        "New Age", "Oldies", "Other", "Pop", "R&B", "Rap", "Reggae", "Rock", "Techno", "Industrial",
        "Alternative", "Ska", "Death Metal", "Pranks", "Soundtrack", "Euro-Techno", "Ambient", "Trip-Hop",
        "Vocal", "Jazz+Funk", "Fusion", "Trance", "Classical", "Instrumental", "Acid", "House", "Game",
        "Sound Clip", "Gospel", "Noise", "Alternative Rock", "Bass", "Soul", "Punk", "Space", "Meditative",
        "Instrumental Pop", "Instrumental Rock", "Ethnic", "Gothic", "Darkwave", "Techno-Industrial",
        "Electronic", "Pop-Folk", "Eurodance", "Dream", "Southern Rock", "Comedy", "Cult", "Gangsta",
        "Top 40", "Christian Rap", "Pop/Funk", "Jungle", "Native American", "Cabaret", "New Wave",
        "Psychedelic", "Rave", "Showtunes", "Trailer", "Lo-Fi", "Tribal", "Acid Punk", "Acid Jazz", "Polka",
        "Retro", "Musical", "Rock & Roll", "Hard Rock",
    )

    private fun syncsafe(b: ByteArray, o: Int) =
        ((b[o].toInt() and 0x7F) shl 21) or ((b[o + 1].toInt() and 0x7F) shl 14) or
            ((b[o + 2].toInt() and 0x7F) shl 7) or (b[o + 3].toInt() and 0x7F)

    private fun be32(b: ByteArray, o: Int) =
        ((b[o].toInt() and 0xFF) shl 24) or ((b[o + 1].toInt() and 0xFF) shl 16) or
            ((b[o + 2].toInt() and 0xFF) shl 8) or (b[o + 3].toInt() and 0xFF)
}
