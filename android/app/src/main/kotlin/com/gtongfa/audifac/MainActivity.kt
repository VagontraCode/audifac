package com.gtongfa.audifac

import android.content.Intent
import com.gtongfa.audifac.dsp.DspChannel
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine

// AudioServiceActivity (instead of FlutterActivity) lets audio_service share
// the Flutter engine with the background playback service.
class MainActivity : AudioServiceActivity() {
    private var mediaLibrary: MediaLibraryChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        mediaLibrary = MediaLibraryChannel(applicationContext) { this }.also {
            it.register(flutterEngine.dartExecutor.binaryMessenger)
        }
        DspChannel(applicationContext).register(flutterEngine.dartExecutor.binaryMessenger)
        PlayerWidget.register(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
    }

    @Deprecated("Needed for the system folder picker result")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (mediaLibrary?.onActivityResult(requestCode, resultCode, data) != true) {
            @Suppress("DEPRECATION")
            super.onActivityResult(requestCode, resultCode, data)
        }
    }
}
