package com.gtongfa.audifac.extract

import android.content.Context
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.util.Log
import java.io.Closeable
import java.io.File

/**
 * WMA / APE / WavPack / TTA through our own minimal FFmpeg
 * (android/app/src/main/cpp): opens a file by descriptor, decodes it frame by
 * frame to interleaved 16-bit or float PCM, seeks by time.
 */
class FfmpegReader private constructor(private var handle: Long) : Closeable {
    val sampleRate: Int
    val channels: Int
    /** Output PCM: true = 32-bit float, false = 16-bit. */
    val float: Boolean
    /** -1 when unknown. */
    val durationUs: Long
    /** Source bit depth for lossless codecs, 0 for lossy / unknown. */
    val sourceBits: Int
    /** Bits per second, 0 when unknown. */
    val bitrate: Long
    /** FFmpeg codec name: wmav2, wmapro, wmalossless, ape, wavpack, tta… */
    val codec: String

    init {
        val info = nativeInfo(handle)
        sampleRate = info[0].toInt()
        channels = info[1].toInt()
        float = info[2].toInt() == 32
        durationUs = info[3]
        sourceBits = info[4].toInt()
        bitrate = info[5]
        codec = nativeCodec(handle)
    }

    val bytesPerFrame get() = channels * (if (float) 4 else 2)

    /** Container + stream tags, keys lower-cased (title, artist, album, wm/…). */
    fun tags(): Map<String, String> {
        val kv = nativeTags(handle)
        val out = LinkedHashMap<String, String>()
        for (i in 0 until kv.size - 1 step 2) out.putIfAbsent(kv[i].lowercase(), kv[i + 1])
        return out
    }

    private var pcm = ByteArray(0)

    /** Bytes of PCM in [pcm] after a successful [decode]. */
    var size = 0
        private set

    /** Timestamp of the last decoded frame. */
    val frameTimeUs: Long get() = nativeFrameTimeUs(handle)

    /** How far the demuxer has read into the file. */
    val bytePosition: Long get() = nativeBytePosition(handle)

    /** Decodes the next frame. False at the end of the stream (or on an error). */
    fun decode(): Boolean {
        val n = nativeDecode(handle)
        if (n < 0) {
            if (n == -2) Log.w(TAG, "decoding stopped on an error")
            size = 0
            return false
        }
        if (pcm.size < n) pcm = ByteArray(n)
        nativeCopy(handle, pcm)
        size = n
        return true
    }

    /** The last decoded frame's PCM (valid up to [size]). */
    fun data(): ByteArray = pcm

    fun seek(timeUs: Long): Boolean = nativeSeek(handle, timeUs)

    override fun close() {
        if (handle != 0L) {
            nativeClose(handle)
            handle = 0
        }
    }

    companion object {
        private const val TAG = "AudifacFfmpeg"

        val available: Boolean = try {
            System.loadLibrary("audifac_ffmpeg")
            true
        } catch (e: Throwable) {
            Log.w(TAG, "native FFmpeg reader unavailable: $e")
            false
        }

        /** Opens [uri] (content://, file:// or a plain path); null if FFmpeg can't read it. */
        fun open(context: Context, uri: Uri): FfmpegReader? {
            if (!available) return null
            val pfd = try {
                when (uri.scheme) {
                    null, "", "file" -> ParcelFileDescriptor.open(File(uri.path ?: return null), ParcelFileDescriptor.MODE_READ_ONLY)
                    else -> context.contentResolver.openFileDescriptor(uri, "r")
                }
            } catch (e: Exception) {
                Log.w(TAG, "can't open $uri: $e")
                null
            } ?: return null
            // The native side dup()s the descriptor; ours can close now.
            return pfd.use { open(it.fd) }
        }

        fun open(fd: Int): FfmpegReader? {
            if (!available) return null
            val h = nativeOpen(fd)
            return if (h == 0L) null else FfmpegReader(h)
        }

        @JvmStatic private external fun nativeOpen(fd: Int): Long
        @JvmStatic private external fun nativeInfo(handle: Long): LongArray
        @JvmStatic private external fun nativeCodec(handle: Long): String
        @JvmStatic private external fun nativeTags(handle: Long): Array<String>
        @JvmStatic private external fun nativeDecode(handle: Long): Int
        @JvmStatic private external fun nativeCopy(handle: Long, dst: ByteArray)
        @JvmStatic private external fun nativeFrameTimeUs(handle: Long): Long
        @JvmStatic private external fun nativeBytePosition(handle: Long): Long
        @JvmStatic private external fun nativeSeek(handle: Long, timeUs: Long): Boolean
        @JvmStatic private external fun nativeClose(handle: Long)
    }
}
