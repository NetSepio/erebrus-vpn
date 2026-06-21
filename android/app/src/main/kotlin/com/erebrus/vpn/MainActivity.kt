package com.erebrus.vpn

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import android.util.Base64
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import org.bouncycastle.crypto.params.X25519PrivateKeyParameters
import java.security.SecureRandom

/**
 * Hosts the Flutter UI and bridges the `dev.erebrus/singbox` channels to the
 * native sing-box tunnel ([ErebrusVpnService]). One engine serves WireGuard and
 * the stealth carriers — protocol selection happens entirely in the sing-box
 * config the Dart layer hands us.
 */
class MainActivity : FlutterActivity() {

    private val vpnRequestCode = 0x5713
    private var pendingPrepare: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        MethodChannel(messenger, SingboxBridge.METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "prepare" -> prepareVpn(result)
                "start" -> {
                    val config = call.argument<String>("config") ?: ""
                    val name = call.argument<String>("name") ?: "Erebrus"
                    ErebrusVpnService.start(this, config, name)
                    result.success(null)
                }
                "stop" -> {
                    ErebrusVpnService.stop(this)
                    result.success(null)
                }
                "stage" -> result.success(SingboxBridge.stage)
                "genWgKeys" -> result.success(generateWireGuardKeyPair())
                else -> result.notImplemented()
            }
        }

        EventChannel(messenger, SingboxBridge.STATUS_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, sink: EventChannel.EventSink?) = SingboxBridge.setStatusSink(sink)
                override fun onCancel(args: Any?) = SingboxBridge.setStatusSink(null)
            }
        )
        EventChannel(messenger, SingboxBridge.STATS_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, sink: EventChannel.EventSink?) = SingboxBridge.setStatsSink(sink)
                override fun onCancel(args: Any?) = SingboxBridge.setStatsSink(null)
            }
        )
    }

    /** Requests the OS VPN consent; resolves true once granted/already held. */
    private fun prepareVpn(result: MethodChannel.Result) {
        val intent = VpnService.prepare(this)
        if (intent == null) {
            result.success(true)
            return
        }
        pendingPrepare = result
        startActivityForResult(intent, vpnRequestCode)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == vpnRequestCode) {
            pendingPrepare?.success(resultCode == Activity.RESULT_OK)
            pendingPrepare = null
        }
    }

    /** Generates a WireGuard (x25519) keypair; the private key never leaves device. */
    private fun generateWireGuardKeyPair(): Map<String, String> {
        val priv = X25519PrivateKeyParameters(SecureRandom())
        val pub = priv.generatePublicKey()
        return mapOf(
            "private" to Base64.encodeToString(priv.encoded, Base64.NO_WRAP),
            "public" to Base64.encodeToString(pub.encoded, Base64.NO_WRAP),
        )
    }
}
