package com.gtongfa.audifac

import android.app.Activity
import android.app.RecoverableSecurityException
import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executor

/**
 * Song menu → Share / Delete file.
 *
 * Share: a file we can read is offered through our [FileProvider] (works for
 * any receiving app, whatever its permissions); a folder-picker document is
 * shared by its URI (our read grant is passed on).
 *
 * Delete: only through Android's own confirmation (Android 10+), on the
 * song's MediaStore entry (found by path for files from our own scan).
 */
class SongFileActions(
    private val context: Context,
    private val activity: () -> Activity?,
    private val executor: Executor,
) {
    private val mainHandler = Handler(Looper.getMainLooper())
    private var pendingDelete: Pair<MethodChannel.Result, Uri>? = null

    fun share(call: MethodCall, result: MethodChannel.Result) {
        val host = activity() ?: return result.error("no_activity", "Not in the foreground", null)
        val uri = shareUri(call.argument<String>("path"), call.argument<String>("uri"))
            ?: return result.error("not_found", "File not found", null)
        val send = Intent(Intent.ACTION_SEND)
            .setType(call.argument<String>("mime") ?: "audio/*")
            .putExtra(Intent.EXTRA_STREAM, uri)
            .putExtra(Intent.EXTRA_TITLE, call.argument<String>("title"))
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        host.startActivity(Intent.createChooser(send, call.argument<String>("title")))
        result.success(true)
    }

    private fun shareUri(path: String?, uri: String?): Uri? {
        if (path != null) {
            val file = File(path)
            if (file.canRead()) {
                return try {
                    FileProvider.getUriForFile(context, "${context.packageName}.files", file)
                } catch (_: IllegalArgumentException) {
                    null
                }
            }
        }
        return uri?.takeIf { it.startsWith("content://") }?.let(Uri::parse)
    }

    /** Whether this Android can delete through the system confirmation. */
    val canDelete get() = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q

    fun delete(call: MethodCall, result: MethodChannel.Result) {
        val host = activity() ?: return result.error("no_activity", "Not in the foreground", null)
        if (!canDelete) return result.success(false)
        val path = call.argument<String>("path")
        val uri = call.argument<String>("uri")
        executor.execute {
            val target = mediaStoreUri(uri, path)
            mainHandler.post {
                if (target == null) result.error("not_indexed", "Android has no entry for this file", null)
                else requestDelete(host, target, result)
            }
        }
    }

    private fun requestDelete(host: Activity, target: Uri, result: MethodChannel.Result) {
        pendingDelete?.first?.success(false)
        pendingDelete = result to target
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                val request = MediaStore.createDeleteRequest(context.contentResolver, listOf(target))
                host.startIntentSenderForResult(request.intentSender, DELETE_REQUEST, null, 0, 0, 0)
            } else {
                // Android 10: try, and ask for consent when refused.
                try {
                    val deleted = context.contentResolver.delete(target, null, null) > 0
                    pendingDelete = null
                    result.success(deleted)
                } catch (e: RecoverableSecurityException) {
                    host.startIntentSenderForResult(e.userAction.actionIntent.intentSender, DELETE_REQUEST, null, 0, 0, 0)
                }
            }
        } catch (e: Exception) {
            pendingDelete = null
            result.error("delete_failed", e.message, null)
        }
    }

    /** Forwarded from [MainActivity.onActivityResult]; true if handled. */
    fun onActivityResult(requestCode: Int, resultCode: Int): Boolean {
        if (requestCode != DELETE_REQUEST) return false
        val (result, target) = pendingDelete ?: return true
        pendingDelete = null
        if (resultCode != Activity.RESULT_OK) {
            result.success(false)
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            result.success(true) // The system deleted it.
        } else {
            // Android 10: consent given, delete now.
            executor.execute {
                val deleted = try {
                    context.contentResolver.delete(target, null, null) > 0
                } catch (_: Exception) {
                    false
                }
                mainHandler.post { result.success(deleted) }
            }
        }
        return true
    }

    /** The MediaStore entry for a song: its own URI, or looked up by path. */
    private fun mediaStoreUri(uri: String?, path: String?): Uri? {
        if (uri != null && uri.startsWith("content://media/")) return Uri.parse(uri)
        if (path == null) return null
        val collection = MediaStore.Files.getContentUri("external")
        return context.contentResolver.query(
            collection, arrayOf(MediaStore.Files.FileColumns._ID),
            "${MediaStore.Files.FileColumns.DATA} = ?", arrayOf(path), null,
        )?.use { c -> if (c.moveToFirst()) ContentUris.withAppendedId(collection, c.getLong(0)) else null }
    }

    companion object {
        private const val DELETE_REQUEST = 4715
    }
}
