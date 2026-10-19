package si.mox.mux_pod

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import si.mox.mux_pod.updater.UpdaterPlugin

class MainActivity : FlutterActivity() {
    private val channelName = "com.muxpod.app/deeplink"
    private var methodChannel: MethodChannel? = null
    private var initialLink: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(UpdaterPlugin())

        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        methodChannel?.setMethodCallHandler { call, result ->
            if (call.method == "getInitialLink") {
                result.success(initialLink)
                initialLink = null
            } else {
                result.notImplemented()
            }
        }

        // コールドスタート時のインテントを処理
        initialLink = intent?.data?.toString()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // ホットリンク（アプリが既に起動中）
        val uri = intent.data?.toString()
        if (uri != null) {
            methodChannel?.invokeMethod("onDeepLink", uri)
        }
    }
}
