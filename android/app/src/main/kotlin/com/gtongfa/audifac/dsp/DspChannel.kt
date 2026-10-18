package com.gtongfa.audifac.dsp

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * Dart ⇄ DSP bridge.
 *
 * Methods: setConfig(map), setBypass(bool), outputDevice() -> map,
 * setVolumeMatching(map), setGains({gains: {uriKey: map}, replace: bool}),
 * analyseLoudness({locations}) -> list of maps
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

    fun register(messenger: BinaryMessenger) {
        channel = MethodChannel(messenger, "audifac/dsp")
        channel.setMethodCallHandler(this)
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
