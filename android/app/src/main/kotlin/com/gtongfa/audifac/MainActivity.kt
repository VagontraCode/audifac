package com.gtongfa.audifac

import android.content.Intent
import android.os.Bundle
import com.gtongfa.audifac.dsp.DspChannel
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// AudioServiceActivity (instead of FlutterActivity) lets audio_service share
// the Flutter engine with the background playback service.
class MainActivity : AudioServiceActivity() {
    private var mediaLibrary: MediaLibraryChannel? = null

    // Launcher shortcuts (res/xml/shortcuts.xml) → Dart, channel `audifac/launch`.
    // Each launch gets an id so Dart handles it once, whichever way it arrives:
    // pushed ("action", when the engine already runs) or pulled ("take", at start).
    private var launchChannel: MethodChannel? = null
    private var pendingLaunch: Map<String, Any>? = null
    private var launchCount = 0

    override fun onCreate(savedInstanceState: Bundle?) {
        // Not on re-creation (rotation, theme…): the intent was already handled.
        if (savedInstanceState == null) queueLaunch(intent)
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        queueLaunch(intent)
        pushLaunch()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        mediaLibrary = MediaLibraryChannel(applicationContext) { this }.also { it.register(messenger) }
        DspChannel(applicationContext).register(messenger)
        PlayerWidget.register(applicationContext, messenger)
        NetChannel.register(applicationContext, messenger)
        launchChannel = MethodChannel(messenger, "audifac/launch").apply {
            setMethodCallHandler { call, result ->
                if (call.method == "take") {
                    result.success(pendingLaunch)
                    pendingLaunch = null
                } else {
                    result.notImplemented()
                }
            }
        }
        // The engine may already be running (kept alive by playback): tell it now.
        pushLaunch()
    }

    private fun queueLaunch(intent: Intent?) {
        val action = intent?.getStringExtra("shortcut") ?: return
        pendingLaunch = mapOf("id" to ++launchCount, "action" to action)
    }

    private fun pushLaunch() {
        val launch = pendingLaunch ?: return
        launchChannel?.invokeMethod("action", launch, object : MethodChannel.Result {
            override fun success(result: Any?) {
                if (pendingLaunch == launch) pendingLaunch = null
            }
            override fun error(code: String, message: String?, details: Any?) {}
            override fun notImplemented() {} // Dart not listening yet: it will "take" it.
        })
    }

    @Deprecated("Needed for the system folder picker result")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (mediaLibrary?.onActivityResult(requestCode, resultCode, data) != true) {
            @Suppress("DEPRECATION")
            super.onActivityResult(requestCode, resultCode, data)
        }
    }
}
