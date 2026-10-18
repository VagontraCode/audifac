package com.gtongfa.audifac

import android.content.Context
import android.net.wifi.WifiManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * `audifac/net`: Wi-Fi multicast lock for finding Cast / DLNA devices (many
 * phones drop multicast packets without it).
 */
object NetChannel {
    private var lock: WifiManager.MulticastLock? = null

    fun register(context: Context, messenger: BinaryMessenger) {
        MethodChannel(messenger, "audifac/net").setMethodCallHandler { call, result ->
            when (call.method) {
                "multicastLock" -> {
                    val on = call.arguments as? Boolean ?: false
                    val wifi = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                    if (on) {
                        if (lock == null) lock = wifi.createMulticastLock("audifac-cast").apply { setReferenceCounted(false) }
                        lock?.acquire()
                    } else {
                        lock?.release()
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}
