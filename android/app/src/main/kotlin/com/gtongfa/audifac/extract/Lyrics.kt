package com.gtongfa.audifac.extract

import android.content.Context
import android.net.Uri
import androidx.annotation.OptIn
import androidx.media3.common.MediaItem
import androidx.media3.common.Metadata
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.MetadataRetriever
import androidx.media3.extractor.metadata.flac.VorbisComment
import androidx.media3.extractor.metadata.id3.BinaryFrame
import androidx.media3.extractor.metadata.id3.TextInformationFrame
import java.io.File
import java.nio.charset.Charset
import java.util.concurrent.TimeUnit

/**
 * Finds a song's lyrics: an `.lrc` / `.txt` file beside it, else lyrics
 * embedded in its tags (ID3 USLT, Vorbis LYRICS / UNSYNCEDLYRICS, MP4 ©lyr).
 * The text is returned as-is; the app parses LRC timestamps.
 */
object Lyrics {
    fun read(context: Context, location: String, path: String?): Map<String, Any?>? {
        sidecar(path)?.let { return mapOf("text" to it, "source" to "file") }
        val embedded = try {
            embedded(context, location)
        } catch (e: Exception) {
            null
        }
        return embedded?.let { mapOf("text" to it, "source" to "tags") }
    }

    /** `Song.lrc` (or `.txt`) next to `Song.flac`. Readable on Android ≤ 10 and in app-granted folders. */
    private fun sidecar(path: String?): String? {
        if (path == null) return null
        val base = path.substringBeforeLast('.', path)
        for (ext in listOf("lrc", "LRC", "txt")) {
            val f = File("$base.$ext")
            try {
                if (f.isFile && f.length() in 1..512 * 1024) return decode(f.readBytes())
            } catch (_: Exception) {
                // Not readable (scoped storage): fall through to tags.
            }
        }
        return null
    }

    @OptIn(UnstableApi::class)
    private fun embedded(context: Context, location: String): String? {
        val uri = if (location.startsWith("content://")) Uri.parse(location) else Uri.fromFile(File(location))
        MetadataRetriever.Builder(context, MediaItem.fromUri(uri)).build().use { retriever ->
            val groups = retriever.retrieveTrackGroups().get(15, TimeUnit.SECONDS)
            for (g in 0 until groups.length) {
                val group = groups[g]
                for (t in 0 until group.length) {
                    fromMetadata(group.getFormat(t).metadata)?.let { return it }
                }
            }
        }
        return null
    }

    @OptIn(UnstableApi::class)
    fun fromMetadata(metadata: Metadata?): String? {
        if (metadata == null) return null
        var unsynced: String? = null
        for (i in 0 until metadata.length()) {
            val text = when (val e = metadata[i]) {
                is BinaryFrame -> if (e.id == "USLT") parseUslt(e.data) else null
                is TextInformationFrame -> if (e.id == "USLT") e.values.joinToString("\n") else null
                is VorbisComment -> when (e.key.uppercase()) {
                    "LYRICS" -> e.value
                    "UNSYNCEDLYRICS" -> { unsynced = unsynced ?: e.value; null }
                    else -> null
                }
                else -> null
            }
            if (!text.isNullOrBlank()) return text
        }
        return unsynced?.takeIf { it.isNotBlank() }
    }

    /** USLT: encoding, 3-byte language, descriptor (terminated), lyrics. */
    fun parseUslt(data: ByteArray): String? {
        if (data.size < 5) return null
        val encoding = data[0].toInt()
        val charset: Charset = when (encoding) {
            1 -> Charsets.UTF_16
            2 -> Charsets.UTF_16BE
            3 -> Charsets.UTF_8
            else -> Charsets.ISO_8859_1
        }
        val wide = encoding == 1 || encoding == 2
        var pos = 4
        // Skip the content descriptor up to its terminator.
        if (wide) {
            while (pos + 1 < data.size && !(data[pos].toInt() == 0 && data[pos + 1].toInt() == 0)) pos += 2
            pos += 2
        } else {
            while (pos < data.size && data[pos].toInt() != 0) pos++
            pos += 1
        }
        if (pos >= data.size) return null
        var end = data.size
        while (end > pos && data[end - 1].toInt() == 0) end--
        if (wide && (end - pos) % 2 == 1) end++
        // A UTF-16 text after the descriptor carries its own BOM.
        return String(data, pos, end - pos, charset).trim().takeIf { it.isNotEmpty() }
    }

    private fun decode(bytes: ByteArray): String {
        val utf8 = String(bytes, Charsets.UTF_8)
        // Mostly-invalid UTF-8 → probably Latin-1 (old LRC files).
        return if (utf8.count { it == '�' } > 3) String(bytes, Charsets.ISO_8859_1) else utf8.removePrefix("﻿")
    }
}
