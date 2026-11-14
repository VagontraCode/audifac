package com.gtongfa.audifac

import android.content.ContentValues
import android.content.Context
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import java.io.File

/**
 * Wi-Fi transfer: puts a received file into the shared music library
 * (`Music/audifac`), through MediaStore so it's indexed at once and needs no
 * storage permission (Android 10+).
 */
object AudioImporter {
    private const val FOLDER = "audifac"

    val supported get() = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q

    /** Copies [temp] in as [name]; returns null on success, else why not. */
    fun import(context: Context, temp: File, name: String): String? {
        if (!supported) return "Android 10 or later is needed"
        val ext = name.substringAfterLast('.', "").lowercase()
        val sidecar = ext == "lrc" || ext == "cue"
        val resolver = context.contentResolver
        // Lyrics / CUE sheets go beside the songs, as plain files in Music/audifac.
        val collection = if (sidecar) MediaStore.Files.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        else MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, name)
            put(MediaStore.MediaColumns.MIME_TYPE, mimeFor(ext))
            put(MediaStore.MediaColumns.RELATIVE_PATH, "${Environment.DIRECTORY_MUSIC}/$FOLDER")
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val uri = try {
            resolver.insert(collection, values)
        } catch (e: Exception) {
            null
        } ?: return "Android refused the file"
        return try {
            resolver.openOutputStream(uri)?.use { out -> temp.inputStream().use { it.copyTo(out, 1 shl 16) } }
                ?: throw IllegalStateException("No output")
            // Visible (and indexed: tags, duration) only once complete.
            resolver.update(uri, ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }, null, null)
            null
        } catch (e: Exception) {
            resolver.delete(uri, null, null)
            e.message ?: "Copy failed"
        }
    }

    private fun mimeFor(ext: String) = when (ext) {
        "mp3" -> "audio/mpeg"
        "m4a", "m4b", "alac" -> "audio/mp4"
        "aac" -> "audio/aac"
        "flac" -> "audio/flac"
        "wav" -> "audio/x-wav"
        "ogg", "oga" -> "audio/ogg"
        "opus" -> "audio/opus"
        "aif", "aiff", "aifc" -> "audio/x-aiff"
        "wma" -> "audio/x-ms-wma"
        "ape" -> "audio/x-ape"
        "wv" -> "audio/x-wavpack"
        "tta" -> "audio/x-tta"
        "mka" -> "audio/x-matroska"
        "dsf", "dff" -> "audio/x-dsf"
        "mp2" -> "audio/mpeg"
        "ac3" -> "audio/ac3"
        "amr" -> "audio/amr"
        "weba" -> "audio/webm"
        "lrc", "cue" -> "text/plain"
        else -> "audio/*"
    }
}
