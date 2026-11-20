package com.erebrus.vpn

import android.annotation.SuppressLint
import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.os.Bundle
import android.util.Base64
import android.view.WindowManager
import androidx.webkit.ProxyConfig
import androidx.webkit.ProxyController
import androidx.webkit.WebViewFeature
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
    private val deeplinkEventsChannel = "com.erebrus.vpn/events"
    private val deeplinkMethodsChannel = "com.erebrus.vpn/methods"

    private var pendingPrepare: MethodChannel.Result? = null
    private var initialLink: String? = null
    private var linksReceiver: BroadcastReceiver? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Blank the recents thumbnail and refuse screenshots and screen
        // recording. This matters more with a launcher disguise, not less: a
        // calculator icon whose recents preview shows a node list defeats
        // itself. iOS has no equivalent flag; RootView covers it with an opaque
        // overlay while the app is inactive.
        window.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE)
        initialLink = intent?.data?.toString()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        EventChannel(messenger, deeplinkEventsChannel).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, events: EventChannel.EventSink) {
                    linksReceiver = createChangeReceiver(events)
                    initialLink?.let { link ->
                        events.success(link)
                        initialLink = null
                    }
                }

                override fun onCancel(args: Any?) {
                    linksReceiver = null
                }
            }
        )

        MethodChannel(messenger, deeplinkMethodsChannel).setMethodCallHandler { call, result ->
            when (call.method) {
                "initialLink" -> {
                    if (initialLink != null) {
                        result.success(initialLink)
                        initialLink = null
                    } else {
                        result.success(null)
                    }
                }
                "moveTaskToBack" -> result.success(moveTaskToBack(true))
                // Launcher disguise. Dart owns the alias list (it is the same
                // list the manifest declares and a test compares the two), so
                // this layer only flips components.
                "disguise.current" -> {
                    @Suppress("UNCHECKED_CAST")
                    val all = call.argument<List<String>>("aliases") ?: emptyList()
                    result.success(AppDisguise.current(this, all))
                }
                "disguise.set" -> {
                    val alias = call.argument<String>("alias") ?: ""
                    @Suppress("UNCHECKED_CAST")
                    val all = call.argument<List<String>>("aliases") ?: emptyList()
                    if (AppDisguise.set(this, alias, all)) {
                        result.success(true)
                    } else {
                        result.error("UNKNOWN_DISGUISE", "No launcher alias named $alias", null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(messenger, SingboxBridge.METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "prepare" -> prepareVpn(result)
                "start" -> {
                    val config = call.argument<String>("config") ?: ""
                    val name = call.argument<String>("name") ?: "Erebrus"
                    @Suppress("UNCHECKED_CAST")
                    val packages = call.argument<List<String>>("splitTunnelPackages") ?: emptyList()
                    ErebrusVpnService.start(
                        this,
                        config,
                        name,
                        splitTunnelEnabled = call.argument<Boolean>("splitTunnelEnabled") ?: false,
                        splitTunnelMode = call.argument<String>("splitTunnelMode") ?: "exclude",
                        splitTunnelPackages = packages,
                        // Notification copy follows the active disguise: an icon
                        // called Notes whose ongoing notification says "Erebrus"
                        // has hidden nothing.
                        notificationTitle = call.argument<String>("notificationTitle"),
                        notificationText = call.argument<String>("notificationText"),
                    )
                    result.success(null)
                }
                "listApps" -> result.success(SplitTunnelApps.listUserApps(this))
                "stop" -> {
                    ErebrusVpnService.stop(this)
                    result.success(null)
                }
                "stage" -> {
                    val stage = when {
                        ErebrusVpnService.tunnelActive -> "connected"
                        else -> SingboxBridge.stage
                    }
                    result.success(stage)
                }
                "lastError" -> result.success(SingboxBridge.lastError)
                "genWgKeys" -> result.success(generateWireGuardKeyPair())
                "setAppProxy" -> {
                    val host = call.argument<String>("host") ?: "127.0.0.1"
                    val port = call.argument<Int>("port") ?: 10808
                    setAppProxy(host, port, result)
                }
                "clearAppProxy" -> clearAppProxy(result)
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

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (intent.action == Intent.ACTION_VIEW) {
            val receiver = linksReceiver
            if (receiver == null) {
                intent.dataString?.let { initialLink = it }
            } else {
                receiver.onReceive(applicationContext, intent)
            }
        }
    }

    private fun createChangeReceiver(events: EventChannel.EventSink): BroadcastReceiver {
        return object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                val dataString = intent.dataString
                if (dataString == null) {
                    events.error("UNAVAILABLE", "Link unavailable", null)
                } else {
                    events.success(dataString)
                }
            }
        }
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

    @SuppressLint("RequiresFeature")
    private fun setAppProxy(host: String, port: Int, result: MethodChannel.Result) {
        if (!WebViewFeature.isFeatureSupported(WebViewFeature.PROXY_OVERRIDE)) {
            result.success(false)
            return
        }
        val config = ProxyConfig.Builder()
            .addProxyRule("$host:$port")
            .addDirect()
            .build()
        ProxyController.getInstance().setProxyOverride(config, Runnable::run) {
            result.success(true)
        }
    }

    @SuppressLint("RequiresFeature")
    private fun clearAppProxy(result: MethodChannel.Result) {
        if (!WebViewFeature.isFeatureSupported(WebViewFeature.PROXY_OVERRIDE)) {
            result.success(false)
            return
        }
        ProxyController.getInstance().clearProxyOverride(Runnable::run) {
            result.success(true)
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
