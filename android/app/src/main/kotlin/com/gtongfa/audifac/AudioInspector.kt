package com.gtongfa.audifac

import android.content.Context
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import com.gtongfa.audifac.extract.AudioHeaders
import com.gtongfa.audifac.extract.FfmpegExtractor
import java.io.FileInputStream
import java.io.InputStream

/**
 * Reads the technical details of an audio file: the real codec (from the
 * stream, not the extension — an .m4a can be AAC or ALAC), sample rate,
 * channels, bitrate, bit depth, plus extra tags.
 *
 * `location` is an absolute path or a content:// URI.
 */
class AudioInspector(private val context: Context) {

    fun inspect(location: String): Map<String, Any?> {
        val info = HashMap<String, Any?>()
        info["location"] = location
        try {
            readStream(location, info)
            readTags(location, info)
            readHeaderBitDepth(location, info)
        } catch (e: Exception) {
            // Android can't open it — maybe AIFF / DSD, handled below.
        }
        // Our parsers also run for WMA / APE / WavPack / TTA even when Android
        // read something: a phone's ASF parser says "WMA" for WMA Pro and
        // WMA Lossless alike.
        if (info["codecMime"] == null || isFfmpegFormat(location, info["codecMime"] as? String)) {
            readOwnFormats(location, info)
        }
        info["ok"] = info["codecMime"] != null
        return info
    }

    /** By extension, or (MediaStore content:// URIs have none) by what Android reported. */
    private fun isFfmpegFormat(location: String, androidMime: String?): Boolean {
        if (location.substringAfterLast('.', "").lowercase() in FfmpegExtractor.EXTENSIONS) return true
        val m = androidMime?.lowercase() ?: return false
        return "wma" in m || "asf" in m || "ape" in m || "wavpack" in m || "tta" in m
    }

    /** AIFF / DSD / WMA / APE / WavPack / TTA: formats Android can't (fully) read. */
    private fun readOwnFormats(location: String, info: MutableMap<String, Any?>) {
        val h = AudioHeaders.probe(context, location) ?: return
        info["codecMime"] = h.codecMime
        info["containerMime"] = h.codecMime
        info["sampleRate"] = h.sampleRate
        info["channels"] = h.channels
        info["bitDepth"] = h.bitDepth.takeIf { it > 0 }
        if (h.bitrate > 0) info["bitrate"] = h.bitrate
        if (h.durationMs > 0) info["durationMs"] = h.durationMs
        // Keep tags Android already found when ours has none.
        h.tags["genre"]?.let { info["genre"] = it }
        h.tags["year"]?.let { info["year"] = it.take(4) }
        h.tags["composer"]?.let { info["composer"] = it }
        h.tags["albumArtist"]?.let { info["albumArtist"] = it }
        h.tags["disc"]?.let { info["disc"] = it }
    }

    private fun isContent(location: String) = location.startsWith("content://")

    private fun open(location: String): InputStream? =
        if (isContent(location)) context.contentResolver.openInputStream(Uri.parse(location))
        else FileInputStream(location)

    /** Codec, sample rate, channels and (sometimes) bitrate from the first audio track. */
    private fun readStream(location: String, info: MutableMap<String, Any?>) {
        val extractor = MediaExtractor()
        try {
            if (isContent(location)) extractor.setDataSource(context, Uri.parse(location), null)
            else extractor.setDataSource(location)
            for (i in 0 until extractor.trackCount) {
                val format = extractor.getTrackFormat(i)
                val mime = format.getString(MediaFormat.KEY_MIME) ?: continue
                if (!mime.startsWith("audio/")) continue
                info["codecMime"] = mime
                format.intOrNull(MediaFormat.KEY_SAMPLE_RATE)?.let { info["sampleRate"] = it }
                format.intOrNull(MediaFormat.KEY_CHANNEL_COUNT)?.let { info["channels"] = it }
                format.intOrNull(MediaFormat.KEY_BIT_RATE)?.let { info["bitrate"] = it }
                format.intOrNull(MediaFormat.KEY_AAC_PROFILE)?.let { info["aacProfile"] = it }
                // Raw PCM (WAV): encoding tells the bit depth.
                format.intOrNull(MediaFormat.KEY_PCM_ENCODING)?.let { enc ->
                    pcmBits(enc)?.let { info["bitDepth"] = it }
                }
                format.intOrNull("bits-per-sample")?.let { info["bitDepth"] = it }
                if (format.containsKey(MediaFormat.KEY_DURATION)) {
                    info["durationMs"] = format.getLong(MediaFormat.KEY_DURATION) / 1000
                }
                break
            }
        } finally {
            extractor.release()
        }
    }

    private fun MediaFormat.intOrNull(key: String): Int? = try {
        if (containsKey(key)) getInteger(key) else null
    } catch (e: Exception) {
        null
    }

    private fun pcmBits(encoding: Int): Int? = when (encoding) {
        2 -> 16 // ENCODING_PCM_16BIT
        3 -> 8 // ENCODING_PCM_8BIT
        4 -> 32 // ENCODING_PCM_FLOAT
        21 -> 24 // ENCODING_PCM_24BIT_PACKED
        22 -> 32 // ENCODING_PCM_32BIT
        else -> null
    }

    /** Container, average bitrate and tags. */
    private fun readTags(location: String, info: MutableMap<String, Any?>) {
        val retriever = MediaMetadataRetriever()
        try {
            if (isContent(location)) retriever.setDataSource(context, Uri.parse(location))
            else retriever.setDataSource(location)
            fun meta(key: Int) = retriever.extractMetadata(key)?.trim()?.takeIf { it.isNotEmpty() }

            info["containerMime"] = meta(MediaMetadataRetriever.METADATA_KEY_MIMETYPE)
            meta(MediaMetadataRetriever.METADATA_KEY_BITRATE)?.toIntOrNull()?.let { info["bitrate"] = it }
            if (info["durationMs"] == null) {
                meta(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull()?.let { info["durationMs"] = it }
            }
            info["genre"] = meta(MediaMetadataRetriever.METADATA_KEY_GENRE)
            info["year"] = meta(MediaMetadataRetriever.METADATA_KEY_YEAR)
                ?: meta(MediaMetadataRetriever.METADATA_KEY_DATE)?.take(4)
            info["composer"] = meta(MediaMetadataRetriever.METADATA_KEY_COMPOSER)
            info["albumArtist"] = meta(MediaMetadataRetriever.METADATA_KEY_ALBUMARTIST)
            info["disc"] = meta(MediaMetadataRetriever.METADATA_KEY_DISC_NUMBER)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                if (info["sampleRate"] == null) {
                    meta(MediaMetadataRetriever.METADATA_KEY_SAMPLERATE)?.toIntOrNull()?.let { info["sampleRate"] = it }
                }
                if (info["bitDepth"] == null) {
                    meta(MediaMetadataRetriever.METADATA_KEY_BITS_PER_SAMPLE)?.toIntOrNull()
                        ?.takeIf { it > 0 }?.let { info["bitDepth"] = it }
                }
            }
        } catch (e: Exception) {
            // Tags are optional.
        } finally {
            retriever.release()
        }
    }

    /**
     * Bit depth straight from FLAC / WAV headers — Android only reports it on
     * newer versions, and it's what separates "Hi-Res" from CD quality.
     */
    private fun readHeaderBitDepth(location: String, info: MutableMap<String, Any?>) {
        val mime = info["codecMime"] as? String ?: return
        if (info["bitDepth"] != null) return
        if (mime != "audio/flac" && mime != "audio/raw" && !mime.contains("wav")) return
        val header = ByteArray(HEADER_BYTES)
        val read = open(location)?.use { it.readUpTo(header) } ?: return
        val bits = when {
            mime == "audio/flac" -> flacBits(header, read)
            else -> wavBits(header, read)
        }
        bits?.let { info["bitDepth"] = it }
    }

    private fun InputStream.readUpTo(buffer: ByteArray): Int {
        var total = 0
        while (total < buffer.size) {
            val n = read(buffer, total, buffer.size - total)
            if (n <= 0) break
            total += n
        }
        return total
    }

    private fun u8(b: ByteArray, i: Int) = b[i].toInt() and 0xFF

    /** STREAMINFO: 20 bits sample rate, 3 bits channels-1, 5 bits bits-per-sample-1. */
    private fun flacBits(b: ByteArray, len: Int): Int? {
        var start = 0
        // Some FLAC files carry an ID3v2 tag before "fLaC".
        if (len > 10 && b[0] == 'I'.code.toByte() && b[1] == 'D'.code.toByte() && b[2] == '3'.code.toByte()) {
            val size = (u8(b, 6) shl 21) or (u8(b, 7) shl 14) or (u8(b, 8) shl 7) or u8(b, 9)
            start = 10 + size
        }
        if (start + 26 > len) return null
        if (String(b, start, 4, Charsets.US_ASCII) != "fLaC") return null
        val si = start + 8 // after "fLaC" + metadata block header
        return (((u8(b, si + 12) and 0x01) shl 4) or (u8(b, si + 13) shr 4)) + 1
    }

    /** RIFF/WAVE "fmt " chunk: bitsPerSample at offset 14 of the chunk body. */
    private fun wavBits(b: ByteArray, len: Int): Int? {
        if (len < 12 || String(b, 0, 4, Charsets.US_ASCII) != "RIFF" || String(b, 8, 4, Charsets.US_ASCII) != "WAVE") {
            return null
        }
        var pos = 12
        while (pos + 8 <= len) {
            val id = String(b, pos, 4, Charsets.US_ASCII)
            val size = u8(b, pos + 4) or (u8(b, pos + 5) shl 8) or (u8(b, pos + 6) shl 16) or (u8(b, pos + 7) shl 24)
            if (id == "fmt " && pos + 8 + 16 <= len) {
                return u8(b, pos + 8 + 14) or (u8(b, pos + 8 + 15) shl 8)
            }
            pos += 8 + size + (size and 1)
        }
        return null
    }

    companion object {
        private const val HEADER_BYTES = 64 * 1024
    }
}
