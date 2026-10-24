package com.gtongfa.audifac.dsp

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * Dart ⇄ DSP bridge.
 *
 * Methods: setConfig(map), setBypass(bool), outputDevice() -> map,
 * setVolumeMatching(map), setGains({gains: {uriKey: map}, replace: bool}),
 * waveform({location, startMs, endMs?, durationMs}) -> bytes (see Waveform),
 * analyseLoudness({locations}) -> list of maps
 * setCrossfade({seconds, albums: {uriKey: albumId}})
 * Calls Dart: outputChanged(map)
 */
class DspChannel(private val context: Context) : MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private val monitor = OutputDeviceMonitor(context) { device ->
        if (::channel.isInitialized) channel.invokeMethod("outputChanged", device)
    }
    private val mainHandler = Handler(Looper.getMainLooper())

    // Decoding for loudness is heavy: one low-priority thread (playback runs at
    // audio priority). 9, not BACKGROUND (10): that would also confine it to
    // the background cgroup's little cores and make scans several times slower.
    private val loudnessExecutor = Executors.newSingleThreadExecutor { r ->
        Thread({
            Process.setThreadPriority(Process.THREAD_PRIORITY_BACKGROUND + Process.THREAD_PRIORITY_MORE_FAVORABLE)
            r.run()
        }, "AudifacLoudness")
    }

    // Waveforms on their own thread, so the playing song's doesn't wait for a
    // library scan.
    private val waveformExecutor = Executors.newSingleThreadExecutor { r ->
        Thread({
            Process.setThreadPriority(Process.THREAD_PRIORITY_BACKGROUND + Process.THREAD_PRIORITY_MORE_FAVORABLE)
            r.run()
        }, "AudifacWaveform")
    }

    fun register(messenger: BinaryMessenger) {
        channel = MethodChannel(messenger, "audifac/dsp")
        channel.setMethodCallHandler(this)
        EventChannel(messenger, "audifac/visualizer").setStreamHandler(object : EventChannel.StreamHandler {
            private val tick = object : Runnable {
                override fun run() {
                    val sink = events ?: return
                    Visualizer.snapshot()?.let { s ->
                        sink.success(
                            mapOf(
                                "bands" to s.bands.map { it.toDouble() },
                                "peakL" to s.peakL.toDouble(), "peakR" to s.peakR.toDouble(),
                                "rmsL" to s.rmsL.toDouble(), "rmsR" to s.rmsR.toDouble(),
                                "fine" to s.fine, "scope" to s.scope, "correlation" to s.correlation.toDouble(),
                            ),
                        )
                    }
                    mainHandler.postDelayed(this, 33)
                }
            }
            private var events: EventChannel.EventSink? = null

            override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
                events = sink
                Visualizer.enabled = true
                mainHandler.post(tick)
            }

            override fun onCancel(arguments: Any?) {
                events = null
                Visualizer.enabled = false
                Visualizer.reset()
                mainHandler.removeCallbacks(tick)
            }
        })
        monitor.start()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "setConfig" -> {
                @Suppress("UNCHECKED_CAST")
                val map = call.arguments as? Map<String, Any?> ?: emptyMap()
                val config = DspConfig.fromMap(map)
                DspEngine.update(config)
                Log.d("AudifacDsp", "config: enabled=${config.enabled} bands=${config.bands.size} preamp=${"%.1f".format(config.preampDb)} dB crossfeed=${config.crossfeed} transparent=${config.isTransparent}")
                result.success(null)
            }
            "setBypass" -> {
                DspEngine.bypass = call.arguments as? Boolean ?: false
                result.success(null)
            }
            "outputDevice" -> result.success(monitor.current())
            "signalPath" -> result.success(SignalPath.toMap() + mapOf("output" to monitor.details()))
            "setVolumeMatching" -> {
                Loudness.update(VolumeMatching.fromMap(call.arguments as? Map<*, *> ?: emptyMap<String, Any?>()))
                result.success(null)
            }
            "setGains" -> {
                val gains = (call.argument<Map<String, Map<*, *>>>("gains") ?: emptyMap())
                    .mapValues { Gains.fromMap(it.value) }
                Loudness.putGains(gains, replace = call.argument<Boolean>("replace") ?: false)
                result.success(null)
            }
            "setBitPerfect" -> {
                BitPerfect.enabled = call.arguments as? Boolean ?: false
                if (!BitPerfect.enabled) BitPerfect.release("off")
                result.success(BitPerfect.supported)
            }
            "setDownmix" -> {
                Downmix.enabled = call.arguments as? Boolean ?: true
                result.success(null)
            }
            "setResampler" -> {
                Resampling.enabled = call.arguments as? Boolean ?: false
                result.success(null)
            }
            "setCrossfade" -> {
                Crossfade.seconds = ((call.argument<Number>("seconds"))?.toDouble() ?: 0.0).coerceIn(0.0, 12.0)
                @Suppress("UNCHECKED_CAST")
                val albums = (call.argument<Map<String, Number>>("albums") ?: emptyMap()).mapValues { it.value.toLong() }
                Crossfade.setAlbums(albums)
                result.success(null)
            }
            "waveform" -> {
                val location = call.argument<String>("location") ?: return result.error("bad_args", "Missing location", null)
                val startMs = call.argument<Number>("startMs")?.toLong() ?: 0L
                val endMs = call.argument<Number>("endMs")?.toLong()
                val durationMs = call.argument<Number>("durationMs")?.toLong() ?: 0L
                waveformExecutor.execute {
                    val started = System.nanoTime()
                    val levels = try {
                        Waveform.of(context, location, startMs, endMs, durationMs)
                    } catch (e: Exception) {
                        null
                    }
                    Log.d("AudifacDsp", "waveform: ${levels?.size ?: "failed"} in ${(System.nanoTime() - started) / 1_000_000} ms")
                    mainHandler.post { result.success(levels) }
                }
            }
            "analyseLoudness" -> {
                val locations = call.argument<List<String>>("locations") ?: emptyList()
                loudnessExecutor.execute {
                    val scanner = LoudnessScanner(context)
                    val out = try {
                        locations.map(scanner::analyse)
                    } catch (e: Exception) {
                        mainHandler.post { result.error("loudness_failed", e.message, null) }
                        return@execute
                    }
                    mainHandler.post { result.success(out) }
                }
            }
            else -> result.notImplemented()
        }
    }
}
