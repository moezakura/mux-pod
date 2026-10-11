package si.mox.mux_pod.updater

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageInfo
import android.content.pm.PackageInstaller
import android.content.pm.PackageManager
import android.content.pm.Signature
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest

/**
 * Native half of the in-app updater (lib/features/updater/).
 *
 * - Reads package name / versionCode / signing-certificate digests of the
 *   installed app and of a downloaded APK, so Dart can verify the download.
 * - Installs through PackageInstaller sessions. Android shows its own
 *   confirmation screen and re-checks the signature before replacing the app.
 */
class UpdaterPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var context: Context
    private lateinit var channel: MethodChannel
    private var receiver: BroadcastReceiver? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
        registerStatusReceiver()
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        receiver?.let { context.unregisterReceiver(it) }
        receiver = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "installedApp" -> result.success(identity(installedInfo()))
            "inspectApk" -> {
                val path = call.argument<String>("path")
                    ?: return result.error("bad_args", "path required", null)
                result.success(archiveInfo(path)?.let { identity(it) })
            }
            "canRequestInstalls" -> result.success(
                Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
                    context.packageManager.canRequestPackageInstalls()
            )
            "openInstallPermissionSettings" -> {
                openInstallPermissionSettings()
                result.success(null)
            }
            "install" -> {
                val path = call.argument<String>("path")
                    ?: return result.error("bad_args", "path required", null)
                install(path, result)
            }
            else -> result.notImplemented()
        }
    }

    // ---- Package identity -------------------------------------------------

    private val signatureFlag: Int
        @Suppress("DEPRECATION")
        get() = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            PackageManager.GET_SIGNING_CERTIFICATES
        } else {
            PackageManager.GET_SIGNATURES
        }

    @Suppress("DEPRECATION")
    private fun installedInfo(): PackageInfo =
        context.packageManager.getPackageInfo(context.packageName, signatureFlag)

    @Suppress("DEPRECATION")
    private fun archiveInfo(path: String): PackageInfo? =
        context.packageManager.getPackageArchiveInfo(path, signatureFlag)

    @Suppress("DEPRECATION")
    private fun identity(info: PackageInfo): Map<String, Any> {
        val versionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.longVersionCode
        } else {
            info.versionCode.toLong()
        }
        val signatures: Array<Signature>
        // Past certificates this APK proves it may replace (v3 key rotation),
        // oldest first, current last. Empty with multiple signers / pre-P.
        var history: Array<Signature> = emptyArray()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val signing = info.signingInfo
            signatures = signing?.apkContentsSigners ?: emptyArray()
            if (signing != null && !signing.hasMultipleSigners()) {
                history = signing.signingCertificateHistory ?: emptyArray()
            }
        } else {
            signatures = info.signatures ?: emptyArray()
        }
        return mapOf(
            "packageName" to info.packageName,
            "versionCode" to versionCode,
            "signers" to signatures.map { sha256(it.toByteArray()) },
            "signerHistory" to history.map { sha256(it.toByteArray()) },
        )
    }

    private fun sha256(bytes: ByteArray): String =
        MessageDigest.getInstance("SHA-256").digest(bytes)
            .joinToString("") { "%02x".format(it) }

    // ---- Install ----------------------------------------------------------

    private fun openInstallPermissionSettings() {
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Intent(
                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:${context.packageName}"),
            )
        } else {
            Intent(Settings.ACTION_SECURITY_SETTINGS)
        }
        context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    private fun install(path: String, result: MethodChannel.Result) {
        Thread {
            try {
                val file = File(path)
                val installer = context.packageManager.packageInstaller
                val params = PackageInstaller.SessionParams(
                    PackageInstaller.SessionParams.MODE_FULL_INSTALL,
                ).apply {
                    setAppPackageName(context.packageName)
                    setSize(file.length())
                }
                val sessionId = installer.createSession(params)
                installer.openSession(sessionId).use { session ->
                    session.openWrite("update.apk", 0, file.length()).use { out ->
                        file.inputStream().use { it.copyTo(out) }
                        session.fsync(out)
                    }
                    val statusIntent = Intent(ACTION_STATUS).setPackage(context.packageName)
                    val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                            PendingIntent.FLAG_MUTABLE
                        } else {
                            0
                        }
                    val pending = PendingIntent.getBroadcast(context, sessionId, statusIntent, flags)
                    session.commit(pending.intentSender)
                }
                mainHandler.post { result.success(null) }
            } catch (e: Exception) {
                mainHandler.post { result.error("install_failed", e.message, null) }
            }
        }.start()
    }

    private fun registerStatusReceiver() {
        val r = object : BroadcastReceiver() {
            override fun onReceive(ctx: Context, intent: Intent) = onInstallStatus(intent)
        }
        val filter = IntentFilter(ACTION_STATUS)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(r, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            context.registerReceiver(r, filter)
        }
        receiver = r
    }

    private fun onInstallStatus(intent: Intent) {
        when (val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)) {
            PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                val confirm: Intent? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra(Intent.EXTRA_INTENT)
                }
                confirm?.let { context.startActivity(it.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
            }
            // On success the app process is replaced; nothing to report.
            PackageInstaller.STATUS_SUCCESS -> Unit
            else -> channel.invokeMethod(
                "installStatus",
                mapOf(
                    "aborted" to (status == PackageInstaller.STATUS_FAILURE_ABORTED),
                    "message" to intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE),
                ),
            )
        }
    }

    companion object {
        private const val CHANNEL = "si.mox.mux_pod/updater"
        private const val ACTION_STATUS = "si.mox.mux_pod.updater.INSTALL_STATUS"
    }
}
