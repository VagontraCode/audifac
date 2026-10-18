package com.gtongfa.audifac.dsp

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper

/**
 * Tracks where audio is going (phone speaker, wired headphones, a specific
 * Bluetooth or USB device) so the app can apply that device's correction.
 */
class OutputDeviceMonitor(context: Context, private val onChange: (Map<String, Any?>) -> Unit) {
    private val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val handler = Handler(Looper.getMainLooper())
    private var last: Map<String, Any?>? = null

    private val callback = object : AudioDeviceCallback() {
        override fun onAudioDevicesAdded(addedDevices: Array<out AudioDeviceInfo>) = check()
        override fun onAudioDevicesRemoved(removedDevices: Array<out AudioDeviceInfo>) = check()
    }

    fun start() {
        audioManager.registerAudioDeviceCallback(callback, handler)
        check()
    }

    fun current(): Map<String, Any?> = describe(activeDevice())

    private fun check() {
        val now = current()
        if (now != last) {
            last = now
            onChange(now)
        }
    }

    private fun activeDevice(): AudioDeviceInfo? {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val media = AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA).build()
            audioManager.getAudioDevicesForAttributes(media).firstOrNull()?.let { routed ->
                return audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
                    .firstOrNull { it.type == routed.type && it.address == routed.address }
                    ?: audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS).firstOrNull { it.type == routed.type }
            }
        }
        // Older Android: the most "personal" connected output wins, which is
        // what the system routes media to.
        val outputs = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
        return outputs.maxByOrNull { priority(it.type) }?.takeIf { priority(it.type) > 0 }
    }

    private fun priority(type: Int): Int = when (type) {
        AudioDeviceInfo.TYPE_BLUETOOTH_A2DP, 26 /* BLE_HEADSET */, 27 /* BLE_SPEAKER */ -> 5
        AudioDeviceInfo.TYPE_USB_HEADSET, AudioDeviceInfo.TYPE_USB_DEVICE -> 4
        AudioDeviceInfo.TYPE_WIRED_HEADPHONES, AudioDeviceInfo.TYPE_WIRED_HEADSET -> 3
        AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> 1
        else -> 0
    }

    private fun describe(device: AudioDeviceInfo?): Map<String, Any?> {
        if (device == null) return mapOf("key" to "speaker", "kind" to "speaker", "name" to "Phone speaker")
        val product = device.productName?.toString()?.trim().orEmpty()
        val (kind, key, name) = when (device.type) {
            AudioDeviceInfo.TYPE_BLUETOOTH_A2DP, 26, 27 ->
                Triple("bluetooth", "bt:$product", product.ifEmpty { "Bluetooth" })
            AudioDeviceInfo.TYPE_USB_HEADSET, AudioDeviceInfo.TYPE_USB_DEVICE ->
                Triple("usb", "usb:$product", product.ifEmpty { "USB audio" })
            AudioDeviceInfo.TYPE_WIRED_HEADPHONES, AudioDeviceInfo.TYPE_WIRED_HEADSET ->
                Triple("wired", "wired", "Wired headphones")
            else -> Triple("speaker", "speaker", "Phone speaker")
        }
        return mapOf("key" to key, "kind" to kind, "name" to name)
    }
}
