package it.italic.italicapp

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var gnss: GnssCapture? = null
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        gnss = GnssCapture(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "it.italic.italicapp/gnss")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "capture" -> gnss!!.capture(result)
                    "cancel" -> { gnss?.cancel(); result.success(null) }
                    else -> result.notImplemented()
                }
            }
    }
    override fun onDestroy() { gnss?.close(); super.onDestroy() }
}
