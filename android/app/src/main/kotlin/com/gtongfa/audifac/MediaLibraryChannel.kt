package com.gtongfa.audifac

import android.app.Activity
import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.database.ContentObserver
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaMetadataRetriever
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.util.Size
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executor
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/**
 * Exposes the device's audio files to Dart.
 *
 * A file's *location* is either an absolute path or a `content://` document
 * URI (for folders the user granted through the system folder picker).
 *
 * Methods:
 *  - sdkInt() -> Int                      Android API level (picks the right storage permission)
 *  - getSongs() -> List<Map>              every audio file in MediaStore, with type flags
 *  - scanStorage(excluded) -> Map         walks all storage volumes and granted folders for
 *                                         audio, asks Android's media scanner to index files
 *                                         MediaStore is missing, and returns the files it
 *                                         cannot index
 *  - readMetadata(locations) -> List<Map> tags of files that are not in MediaStore
 *  - inspectAudio(locations) -> List<Map> codec, sample rate, bit depth… (see AudioInspector)
 *  - getArtwork(id | location, size)      embedded artwork as JPEG bytes
 *  - cacheArtwork(id | location, key)     same, written to a cache file (for the notification)
 *  - pickFolder() / grantedFolders() / removeFolder(uri)   system folder picker grants
 *
 * Calls Dart's "mediaChanged" when the MediaStore audio collection changes.
 */
class MediaLibraryChannel(
    private val context: Context,
    private val activity: () -> Activity?,
) : MethodChannel.MethodCallHandler {
    private val executor = Executors.newFixedThreadPool(3)
    private val scanExecutor = Executors.newSingleThreadExecutor()
    private val inspectExecutor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private lateinit var channel: MethodChannel
    private var pendingPick: MethodChannel.Result? = null

    private val notifyChanged = Runnable { channel.invokeMethod("mediaChanged", null) }
    private val observer = object : ContentObserver(mainHandler) {
        override fun onChange(selfChange: Boolean) {
            // Debounce: a copy of 100 files fires 100 changes.
            mainHandler.removeCallbacks(notifyChanged)
            mainHandler.postDelayed(notifyChanged, 2000)
        }
    }

    fun register(messenger: BinaryMessenger) {
        channel = MethodChannel(messenger, CHANNEL)
        channel.setMethodCallHandler(this)
        context.contentResolver.registerContentObserver(
            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, true, observer,
        )
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "sdkInt" -> result.success(Build.VERSION.SDK_INT)
            "getSongs" -> runIn(executor, result) { querySongs() }
            "scanStorage" -> {
                val excluded = call.argument<List<String>>("excluded") ?: emptyList()
                runIn(scanExecutor, result) { scanStorage(excluded) }
            }
            "readMetadata" -> {
                val locations = call.argument<List<String>>("paths") ?: emptyList()
                runIn(scanExecutor, result) { locations.map(::readMetadata) }
            }
            "inspectAudio" -> {
                val locations = call.argument<List<String>>("locations") ?: emptyList()
                runIn(inspectExecutor, result) { locations.map(AudioInspector(context)::inspect) }
            }
            "getArtwork" -> {
                val size = call.argument<Int>("size") ?: 300
                runIn(executor, result) { artworkBitmap(call, size)?.let(::toJpeg) }
            }
            "cacheArtwork" -> {
                val key = call.argument<String>("key") ?: return result.error("bad_args", "Missing key", null)
                runIn(executor, result) { cacheArtwork(call, key) }
            }
            "pickFolder" -> pickFolder(result)
            "openTextDocument" -> openTextDocument(result)
            "grantedFolders" -> runIn(executor, result) { grantedFolders() }
            "removeFolder" -> {
                val uri = call.argument<String>("uri") ?: return result.error("bad_args", "Missing uri", null)
                runIn(executor, result) {
                    context.contentResolver.releasePersistableUriPermission(
                        Uri.parse(uri), Intent.FLAG_GRANT_READ_URI_PERMISSION,
                    )
                    true
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun runIn(pool: Executor, result: MethodChannel.Result, block: () -> Any?) {
        pool.execute {
            try {
                val value = block()
                mainHandler.post { result.success(value) }
            } catch (e: Exception) {
                mainHandler.post { result.error("media_library", e.message, null) }
            }
        }
    }

    // --- MediaStore ----------------------------------------------------------

    private fun querySongs(): List<Map<String, Any?>> {
        val collection = MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
        val columns = mutableListOf(
            MediaStore.Audio.Media._ID,
            MediaStore.Audio.Media.DATA,
            MediaStore.Audio.Media.TITLE,
            MediaStore.Audio.Media.ARTIST,
            MediaStore.Audio.Media.ARTIST_ID,
            MediaStore.Audio.Media.ALBUM,
            MediaStore.Audio.Media.ALBUM_ID,
            MediaStore.Audio.Media.DURATION,
            MediaStore.Audio.Media.TRACK,
            MediaStore.Audio.Media.DATE_ADDED,
            MediaStore.Audio.Media.MIME_TYPE,
            MediaStore.Audio.Media.SIZE,
            MediaStore.Audio.Media.DATE_MODIFIED,
            MediaStore.Audio.Media.IS_MUSIC,
            MediaStore.Audio.Media.IS_RINGTONE,
            MediaStore.Audio.Media.IS_NOTIFICATION,
            MediaStore.Audio.Media.IS_ALARM,
            MediaStore.Audio.Media.IS_PODCAST,
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) columns += MediaStore.Audio.Media.IS_RECORDING

        val songs = mutableListOf<Map<String, Any?>>()
        context.contentResolver.query(collection, columns.toTypedArray(), null, null, null)?.use { c ->
            fun idx(name: String) = c.getColumnIndexOrThrow(name)
            val idCol = idx(MediaStore.Audio.Media._ID)
            val dataCol = idx(MediaStore.Audio.Media.DATA)
            val titleCol = idx(MediaStore.Audio.Media.TITLE)
            val artistCol = idx(MediaStore.Audio.Media.ARTIST)
            val artistIdCol = idx(MediaStore.Audio.Media.ARTIST_ID)
            val albumCol = idx(MediaStore.Audio.Media.ALBUM)
            val albumIdCol = idx(MediaStore.Audio.Media.ALBUM_ID)
            val durationCol = idx(MediaStore.Audio.Media.DURATION)
            val trackCol = idx(MediaStore.Audio.Media.TRACK)
            val dateAddedCol = idx(MediaStore.Audio.Media.DATE_ADDED)
            val mimeCol = idx(MediaStore.Audio.Media.MIME_TYPE)
            val sizeCol = idx(MediaStore.Audio.Media.SIZE)
            val modifiedCol = idx(MediaStore.Audio.Media.DATE_MODIFIED)
            val musicCol = idx(MediaStore.Audio.Media.IS_MUSIC)
            val ringtoneCol = idx(MediaStore.Audio.Media.IS_RINGTONE)
            val notificationCol = idx(MediaStore.Audio.Media.IS_NOTIFICATION)
            val alarmCol = idx(MediaStore.Audio.Media.IS_ALARM)
            val podcastCol = idx(MediaStore.Audio.Media.IS_PODCAST)
            val recordingCol = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                idx(MediaStore.Audio.Media.IS_RECORDING)
            } else {
                -1
            }

            while (c.moveToNext()) {
                val id = c.getLong(idCol)
                songs.add(
                    mapOf(
                        "id" to id,
                        "uri" to ContentUris.withAppendedId(collection, id).toString(),
                        "path" to c.getString(dataCol),
                        "title" to c.getString(titleCol),
                        "artist" to c.getString(artistCol),
                        "artistId" to c.getLong(artistIdCol),
                        "album" to c.getString(albumCol),
                        "albumId" to c.getLong(albumIdCol),
                        "durationMs" to c.getLong(durationCol),
                        "track" to c.getInt(trackCol),
                        "dateAdded" to c.getLong(dateAddedCol),
                        "mimeType" to c.getString(mimeCol),
                        "size" to c.getLong(sizeCol),
                        "dateModified" to c.getLong(modifiedCol),
                        "isMusic" to (c.getInt(musicCol) != 0),
                        "isSystemSound" to (c.getInt(ringtoneCol) != 0 ||
                            c.getInt(notificationCol) != 0 || c.getInt(alarmCol) != 0),
                        "isPodcast" to (c.getInt(podcastCol) != 0),
                        "isRecording" to (recordingCol >= 0 && c.getInt(recordingCol) != 0),
                    )
                )
            }
        }
        return songs
    }

    private fun indexedPaths(): Set<String> {
        val paths = HashSet<String>()
        context.contentResolver.query(
            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
            arrayOf(MediaStore.Audio.Media.DATA), null, null, null,
        )?.use { c ->
            while (c.moveToNext()) c.getString(0)?.let(paths::add)
        }
        return paths
    }

    // --- Storage scan ----------------------------------------------------------

    /** Internal storage plus every mounted SD card / USB volume. */
    private fun storageRoots(): List<File> {
        val roots = LinkedHashSet<String>()
        @Suppress("DEPRECATION")
        roots += Environment.getExternalStorageDirectory().absolutePath
        context.getExternalFilesDirs(null).filterNotNull().forEach { dir ->
            // .../<volume>/Android/data/<package>/files -> .../<volume>
            val path = dir.absolutePath
            val cut = path.indexOf("/Android/data/")
            if (cut > 0) roots += path.substring(0, cut)
        }
        return roots.map(::File).filter { it.canRead() }
    }

    private fun isExcluded(path: String, excluded: List<String>) =
        excluded.any { path == it || path.startsWith("$it/") }

    private fun isAudioName(name: String) = name.substringAfterLast('.', "").lowercase() in AUDIO_EXTENSIONS

    private fun scanStorage(excluded: List<String>): Map<String, Any?> {
        val started = System.currentTimeMillis()
        val found = mutableListOf<Pair<File, Boolean>>() // file, inside a .nomedia folder

        for (root in storageRoots()) {
            val stack = ArrayDeque<Triple<File, Int, Boolean>>()
            stack.addLast(Triple(root, 0, false))
            while (stack.isNotEmpty()) {
                val (dir, depth, parentHidden) = stack.removeLast()
                if (isExcluded(dir.absolutePath, excluded)) continue
                val children = dir.listFiles() ?: continue
                val hidden = parentHidden || children.any { it.name == ".nomedia" }
                for (child in children) {
                    if (child.isDirectory) {
                        // Android/data & obb are app-private; dot-folders are caches/thumbnails.
                        val skip = child.name.startsWith(".") ||
                            (depth == 0 && child.name == "Android") ||
                            depth > MAX_DEPTH
                        if (!skip) stack.addLast(Triple(child, depth + 1, hidden))
                    } else if (isAudioName(child.name) && child.length() > 0) {
                        found += child to hidden
                    }
                }
            }
        }

        val indexed = indexedPaths()
        val missing = found.filter { (file, _) -> file.absolutePath !in indexed }
        val toIndex = missing.filter { (_, hidden) -> !hidden }.map { it.first.absolutePath }

        // Ask Android to index the files it missed. Paths it rejects come back
        // with a null uri and are handled like ".nomedia" files below.
        val rejected = mutableSetOf<String>()
        if (toIndex.isNotEmpty()) {
            val latch = CountDownLatch(toIndex.size)
            MediaScannerConnection.scanFile(context, toIndex.toTypedArray(), null) { path, uri ->
                if (uri == null) synchronized(rejected) { rejected += path }
                latch.countDown()
            }
            latch.await(SCAN_TIMEOUT_SECONDS, TimeUnit.SECONDS)
        }

        val unindexed: MutableList<Map<String, Any?>> = missing
            .filter { (file, hidden) -> hidden || file.absolutePath in rejected }
            .map { (file, _) ->
                mapOf<String, Any?>(
                    "location" to file.absolutePath,
                    "path" to file.absolutePath,
                    "size" to file.length(),
                    "modified" to file.lastModified(),
                )
            }
            .toMutableList()

        // Folders granted through the system picker (e.g. hidden ".nomedia"
        // folders, which apps can't even list on Android 11+).
        val seen = found.mapTo(HashSet()) { it.first.absolutePath } + indexed
        var granted = 0
        for (permission in context.contentResolver.persistedUriPermissions) {
            if (!permission.isReadPermission) continue
            for (entry in walkTree(permission.uri, excluded)) {
                if (entry["path"] in seen) continue
                unindexed += entry
                granted++
            }
        }

        return mapOf(
            "found" to found.size + granted,
            "newlyIndexed" to toIndex.size - rejected.size,
            "unindexed" to unindexed,
            "elapsedMs" to System.currentTimeMillis() - started,
        )
    }

    /** Readable path for a picker document id, e.g. "primary:Music" -> /storage/emulated/0/Music. */
    private fun displayPathFor(documentId: String): String {
        val volume = documentId.substringBefore(':')
        val relative = documentId.substringAfter(':', "")
        val root = if (volume == "primary") "/storage/emulated/0" else "/storage/$volume"
        return if (relative.isEmpty()) root else "$root/$relative"
    }

    private fun walkTree(treeUri: Uri, excluded: List<String>): List<Map<String, Any?>> {
        val out = mutableListOf<Map<String, Any?>>()
        val rootId = try {
            DocumentsContract.getTreeDocumentId(treeUri)
        } catch (e: Exception) {
            return out
        }
        val projection = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
            DocumentsContract.Document.COLUMN_SIZE,
            DocumentsContract.Document.COLUMN_LAST_MODIFIED,
        )
        val stack = ArrayDeque<Triple<String, String, Int>>() // documentId, display path, depth
        stack.addLast(Triple(rootId, displayPathFor(rootId), 0))
        while (stack.isNotEmpty()) {
            val (docId, dirPath, depth) = stack.removeLast()
            if (isExcluded(dirPath, excluded)) continue
            val children = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, docId)
            try {
                context.contentResolver.query(children, projection, null, null, null)?.use { c ->
                    while (c.moveToNext()) {
                        val childId = c.getString(0) ?: continue
                        val name = c.getString(1) ?: continue
                        val mime = c.getString(2) ?: ""
                        val path = "$dirPath/$name"
                        if (mime == DocumentsContract.Document.MIME_TYPE_DIR) {
                            if (!name.startsWith(".") && depth < MAX_DEPTH) {
                                stack.addLast(Triple(childId, path, depth + 1))
                            }
                        } else if (isAudioName(name) || mime.startsWith("audio/")) {
                            out += mapOf(
                                "location" to DocumentsContract.buildDocumentUriUsingTree(treeUri, childId).toString(),
                                "path" to path,
                                "size" to c.getLong(3),
                                "modified" to c.getLong(4),
                            )
                        }
                    }
                }
            } catch (e: Exception) {
                // Folder vanished or grant revoked: skip it.
            }
        }
        return out
    }

    private fun MediaMetadataRetriever.open(location: String) {
        if (location.startsWith("content://")) setDataSource(context, Uri.parse(location)) else setDataSource(location)
    }

    private fun readMetadata(location: String): Map<String, Any?> {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.open(location)
            fun meta(key: Int) = retriever.extractMetadata(key)?.trim()?.takeIf { it.isNotEmpty() }
            mapOf(
                "path" to location,
                "title" to meta(MediaMetadataRetriever.METADATA_KEY_TITLE),
                "artist" to (meta(MediaMetadataRetriever.METADATA_KEY_ARTIST)
                    ?: meta(MediaMetadataRetriever.METADATA_KEY_ALBUMARTIST)),
                "album" to meta(MediaMetadataRetriever.METADATA_KEY_ALBUM),
                "durationMs" to meta(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull(),
                "track" to meta(MediaMetadataRetriever.METADATA_KEY_CD_TRACK_NUMBER)
                    ?.substringBefore('/')?.toIntOrNull(),
                "mimeType" to meta(MediaMetadataRetriever.METADATA_KEY_MIMETYPE),
                "readable" to true,
            )
        } catch (e: Exception) {
            mapOf("path" to location, "readable" to false)
        } finally {
            retriever.release()
        }
    }

    // --- Folder picker -------------------------------------------------------

    private fun pickFolder(result: MethodChannel.Result) {
        val host = activity() ?: return result.error("no_activity", "No foreground activity", null)
        if (pendingPick != null) return result.error("busy", "Picker already open", null)
        pendingPick = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).addFlags(
            Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION,
        )
        @Suppress("DEPRECATION")
        host.startActivityForResult(intent, PICK_FOLDER_REQUEST)
    }

    /** Lets the user pick a text file (e.g. an AutoEQ ParametricEQ.txt) and returns its content. */
    private fun openTextDocument(result: MethodChannel.Result) {
        val host = activity() ?: return result.error("no_activity", "No foreground activity", null)
        if (pendingDocument != null) return result.error("busy", "Picker already open", null)
        pendingDocument = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT)
            .addCategory(Intent.CATEGORY_OPENABLE)
            .setType("*/*")
            .putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("text/plain", "application/octet-stream", "text/*"))
        @Suppress("DEPRECATION")
        host.startActivityForResult(intent, OPEN_DOCUMENT_REQUEST)
    }

    private var pendingDocument: MethodChannel.Result? = null

    private fun onDocumentResult(resultCode: Int, data: Intent?) {
        val result = pendingDocument ?: return
        pendingDocument = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) return result.success(null)
        executor.execute {
            try {
                val text = context.contentResolver.openInputStream(uri)?.use { input ->
                    val bytes = input.readBytes()
                    if (bytes.size > MAX_TEXT_BYTES) null else String(bytes, Charsets.UTF_8)
                }
                val name = uri.lastPathSegment?.substringAfterLast('/')?.substringBeforeLast('.')
                mainHandler.post {
                    if (text == null) result.error("too_large", "File is not a small text file", null)
                    else result.success(mapOf("name" to name, "text" to text))
                }
            } catch (e: Exception) {
                mainHandler.post { result.error("read_failed", e.message, null) }
            }
        }
    }

    /** Forwarded from [MainActivity.onActivityResult]; true if handled. */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode == OPEN_DOCUMENT_REQUEST) {
            onDocumentResult(resultCode, data)
            return true
        }
        if (requestCode != PICK_FOLDER_REQUEST) return false
        val result = pendingPick ?: return true
        pendingPick = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return true
        }
        try {
            context.contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
            result.success(folderInfo(uri))
        } catch (e: Exception) {
            result.error("grant_failed", e.message, null)
        }
        return true
    }

    private fun folderInfo(uri: Uri): Map<String, Any?> {
        val docId = try {
            DocumentsContract.getTreeDocumentId(uri)
        } catch (e: Exception) {
            null
        }
        return mapOf("uri" to uri.toString(), "path" to docId?.let(::displayPathFor))
    }

    private fun grantedFolders(): List<Map<String, Any?>> =
        context.contentResolver.persistedUriPermissions
            .filter { it.isReadPermission }
            .map { folderInfo(it.uri) }

    // --- Artwork ---------------------------------------------------------------

    private fun artworkBitmap(call: MethodCall, size: Int): Bitmap? {
        val location = call.argument<String>("path")
        val id = call.argument<Number>("id")?.toLong()
        return when {
            location != null -> embeddedArtwork(size) { open(location) }
            id != null -> mediaStoreArtwork(id, size)
            else -> null
        }
    }

    private fun mediaStoreArtwork(songId: Long, size: Int): Bitmap? {
        val uri = ContentUris.withAppendedId(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, songId)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            try {
                return context.contentResolver.loadThumbnail(uri, Size(size, size), null)
            } catch (e: Exception) {
                // No embedded artwork, or Android refuses (it won't thumbnail
                // files in Download): read the embedded picture ourselves.
            }
        }
        return embeddedArtwork(size) { setDataSource(context, uri) }
    }

    private fun embeddedArtwork(size: Int, open: MediaMetadataRetriever.() -> Unit): Bitmap? {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.open()
            retriever.embeddedPicture?.let { decodeScaled(it, size) }
        } catch (e: Exception) {
            null
        } finally {
            retriever.release()
        }
    }

    /** Writes artwork to `cache/artwork/<key>.jpg` and returns its path (or null). */
    private fun cacheArtwork(call: MethodCall, key: String): String? {
        val dir = File(context.cacheDir, "artwork").apply { mkdirs() }
        val file = File(dir, "${key.replace(Regex("[^A-Za-z0-9_-]"), "_")}.jpg")
        if (file.exists() && file.length() > 0) return file.absolutePath
        val bitmap = artworkBitmap(call, 512) ?: return null
        file.writeBytes(toJpeg(bitmap))
        return file.absolutePath
    }

    private fun decodeScaled(bytes: ByteArray, size: Int): Bitmap? {
        val decoded = BitmapFactory.decodeByteArray(bytes, 0, bytes.size) ?: return null
        return Bitmap.createScaledBitmap(decoded, size, size, true)
    }

    private fun toJpeg(bitmap: Bitmap): ByteArray {
        val out = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.JPEG, 90, out)
        return out.toByteArray()
    }

    companion object {
        const val CHANNEL = "audifac/media_library"
        private const val PICK_FOLDER_REQUEST = 4711
        private const val OPEN_DOCUMENT_REQUEST = 4712
        private const val MAX_TEXT_BYTES = 1 shl 20
        private const val MAX_DEPTH = 14
        private const val SCAN_TIMEOUT_SECONDS = 120L

        // Formats ExoPlayer (just_audio) can play. WMA/APE/DSD would need another engine.
        private val AUDIO_EXTENSIONS = setOf(
            "mp3", "m4a", "m4b", "aac", "flac", "ogg", "oga", "opus", "wav", "wave",
            "amr", "awb", "3gp", "3ga", "mka", "weba",
        )
    }
}
