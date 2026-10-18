package com.gtongfa.audifac.dsp

import android.content.Context
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Dart ⇄ DSP bridge.
 *
 * Methods: setConfig(map), setBypass(bool), outputDevice() -> map
 * Calls Dart: outputChanged(map)
 */
class DspChannel(context: Context) : MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private val monitor = OutputDeviceMonitor(context) { device ->
        if (::channel.isInitialized) channel.invokeMethod("outputChanged", device)
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
            else -> result.notImplemented()
        }
    }
}
