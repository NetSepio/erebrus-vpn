package com.erebrus.vpn

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import java.util.concurrent.Executors
import io.nekohasekai.libbox.libbox.BoxService
import io.nekohasekai.libbox.libbox.InterfaceUpdateListener
import io.nekohasekai.libbox.libbox.Libbox
import io.nekohasekai.libbox.libbox.NetworkInterfaceIterator
import io.nekohasekai.libbox.libbox.Notification as LibboxNotification
import io.nekohasekai.libbox.libbox.PlatformInterface
import io.nekohasekai.libbox.libbox.RoutePrefixIterator
import io.nekohasekai.libbox.libbox.SetupOptions
import io.nekohasekai.libbox.libbox.TunOptions
import io.nekohasekai.libbox.libbox.WIFIState

/**
 * The single on-device tunnel for every Erebrus protocol. It runs sing-box via
 * libbox; WireGuard and the stealth carriers (VLESS+REALITY / Hysteria2) are
 * just outbounds/endpoints inside the config we are handed.
 */
class ErebrusVpnService : VpnService(), PlatformInterface {

    companion object {
        private const val ACTION_START = "com.erebrus.app.START"
        private const val ACTION_STOP = "com.erebrus.app.STOP"
        private const val EXTRA_CONFIG = "config"
        private const val EXTRA_NAME = "name"
        private const val EXTRA_SPLIT_ENABLED = "split_tunnel_enabled"
        private const val EXTRA_SPLIT_MODE = "split_tunnel_mode"
        private const val EXTRA_SPLIT_PACKAGES = "split_tunnel_packages"
        private const val NOTIF_CHANNEL = "erebrus_vpn"
        private const val NOTIF_ID = 0x5713
        /** Tunnel DNS — must match SingboxConfigBuilder.tunDnsAddress in Dart. */
        private const val TUN_DNS = "172.19.0.2"

        /** True while libbox holds an open TUN — survives Flutter engine restarts. */
        @Volatile
        var tunnelActive: Boolean = false
            private set

        fun start(
            ctx: Context,
            config: String,
            name: String,
            splitTunnelEnabled: Boolean = false,
            splitTunnelMode: String = "exclude",
            splitTunnelPackages: List<String> = emptyList(),
        ) {
            SingboxBridge.setSplitTunnel(splitTunnelEnabled, splitTunnelMode, splitTunnelPackages)
            val i = Intent(ctx, ErebrusVpnService::class.java).apply {
                action = ACTION_START
                putExtra(EXTRA_CONFIG, config)
                putExtra(EXTRA_NAME, name)
                putExtra(EXTRA_SPLIT_ENABLED, splitTunnelEnabled)
                putExtra(EXTRA_SPLIT_MODE, splitTunnelMode)
                putStringArrayListExtra(EXTRA_SPLIT_PACKAGES, ArrayList(splitTunnelPackages))
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                ctx.startForegroundService(i)
            } else {
                ctx.startService(i)
            }
        }

        fun stop(ctx: Context) {
            ctx.startService(Intent(ctx, ErebrusVpnService::class.java).apply { action = ACTION_STOP })
        }
    }

    private var box: BoxService? = null
    private var tunInterface: ParcelFileDescriptor? = null
    private val statsMonitor = LibboxStatsMonitor()
    private val mainHandler = Handler(Looper.getMainLooper())
    /** libbox start/stop is blocking — never run it on the main looper (ANR + frozen Flutter). */
    private val tunnelExecutor = Executors.newSingleThreadExecutor()
    @Volatile
    private var stopping = false
    /** Bumps on every start/stop so in-flight tunnel work can be abandoned safely. */
    @Volatile
    private var tunnelGeneration = 0

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                tunnelGeneration += 1
                tunnelExecutor.execute { stopTunnel() }
                return START_NOT_STICKY
            }
            ACTION_START -> {
                val config = intent.getStringExtra(EXTRA_CONFIG).orEmpty()
                val name = intent.getStringExtra(EXTRA_NAME) ?: "Erebrus"
                val splitEnabled = intent.getBooleanExtra(EXTRA_SPLIT_ENABLED, false)
                val splitMode = intent.getStringExtra(EXTRA_SPLIT_MODE) ?: "exclude"
                val splitPackages = intent.getStringArrayListExtra(EXTRA_SPLIT_PACKAGES) ?: arrayListOf()
                SingboxBridge.setSplitTunnel(splitEnabled, splitMode, splitPackages)
                // Android requires startForeground within seconds of startForegroundService().
                startForeground(NOTIF_ID, buildNotification(name))
                val generation = ++tunnelGeneration
                tunnelExecutor.execute {
                    if (generation != tunnelGeneration) return@execute
                    startTunnel(config, name, generation)
                }
            }
        }
        return START_NOT_STICKY
    }

    override fun onRevoke() {
        stopTunnel()
        super.onRevoke()
    }

    private fun startTunnel(config: String, name: String, generation: Int) {
        if (generation != tunnelGeneration) return
        stopping = false
        startForeground(NOTIF_ID, buildNotification(name))
        releaseTunnelResources()
        if (generation != tunnelGeneration) return
        SingboxBridge.setLastError(null)
        SingboxBridge.emitStage("connecting")
        android.util.Log.i("erebrus-singbox", "startTunnel name=$name bytes=${config.length}")
        try {
            val setup = SetupOptions().apply {
                basePath = filesDir.absolutePath
                workingPath = filesDir.absolutePath
                tempPath = cacheDir.absolutePath
                fixAndroidStack = true
            }
            Libbox.setup(setup)
            if (generation != tunnelGeneration) return
            val service = Libbox.newService(config, this)
            if (generation != tunnelGeneration) {
                try {
                    service.close()
                } catch (_: Exception) {
                }
                return
            }
            // Hold the service before start() so stop/retry can close it while start blocks.
            box = service
            // service.start() blocks until outbounds initialise (WG handshake, etc.).
            // openTun() marks connected as soon as the OS VPN iface is up; run start on a
            // side thread so the tunnel executor stays free for stop/transport retries.
            Thread {
                try {
                    if (generation != tunnelGeneration) return@Thread
                    service.start()
                    if (generation != tunnelGeneration) return@Thread
                    statsMonitor.start(service)
                    android.util.Log.i("erebrus-singbox", "libbox service.start() returned")
                } catch (e: Exception) {
                    if (generation != tunnelGeneration) return@Thread
                    android.util.Log.e("erebrus-singbox", "service.start failed", e)
                    mainHandler.post {
                        SingboxBridge.setLastError(e.message ?: e.toString())
                        releaseTunnelResources()
                        SingboxBridge.emitStage("error")
                    }
                }
            }.start()
        } catch (e: Exception) {
            if (generation != tunnelGeneration) return
            android.util.Log.e("erebrus-singbox", "startTunnel failed", e)
            SingboxBridge.setLastError(e.message ?: e.toString())
            releaseTunnelResources()
            // Keep the foreground service alive so transport retries can ACTION_START
            // in-place — stopSelf here races startForegroundService and crashes the app.
            SingboxBridge.emitStage("error")
        }
    }

    private fun releaseTunnelResources() {
        statsMonitor.stop()
        AndroidNetworkPlatform.stopMonitor()

        // Close libbox before the OS TUN fd — closing TUN first can auto-close libbox
        // and make a second service.close() log a spurious "file already closed".
        val service = box
        box = null
        if (service != null) {
            try {
                service.close()
                android.util.Log.i("erebrus-singbox", "libbox service closed")
            } catch (e: Exception) {
                if (isBenignCloseError(e)) {
                    android.util.Log.d("erebrus-singbox", "libbox already closed")
                } else {
                    android.util.Log.e("erebrus-singbox", "libbox close failed", e)
                }
            }
        }

        val tun = tunInterface
        tunInterface = null
        if (tun != null) {
            try {
                tun.close()
                android.util.Log.i("erebrus-singbox", "TUN interface closed")
            } catch (e: Exception) {
                if (isBenignCloseError(e)) {
                    android.util.Log.d("erebrus-singbox", "TUN already closed")
                } else {
                    android.util.Log.e("erebrus-singbox", "TUN close failed", e)
                }
            }
        }

        tunnelActive = false
    }

    private fun isBenignCloseError(e: Exception): Boolean {
        val msg = (e.message ?: "").lowercase()
        return msg.contains("already closed") || msg.contains("file already closed")
    }

    private fun stopTunnel() {
        if (stopping) return
        stopping = true
        SingboxBridge.emitStage("disconnecting")
        stopForeground(STOP_FOREGROUND_REMOVE)
        releaseTunnelResources()
        stopping = false
        stopSelf()
        SingboxBridge.emitStage("disconnected")
        android.util.Log.i("erebrus-singbox", "tunnel stopped")
    }

    override fun onDestroy() {
        tunnelGeneration += 1
        tunnelExecutor.execute {
            if (box != null || tunInterface != null) {
                releaseTunnelResources()
            }
        }
        tunnelExecutor.shutdown()
        super.onDestroy()
    }

    // ── PlatformInterface (libbox v1.11.x) ───────────────────────────────

    override fun openTun(options: TunOptions): Int {
        val builder = Builder()
            .setSession("Erebrus")
            .setMtu(options.mtu)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            builder.setMetered(false)
        }

        addAddresses(builder, options.inet4Address)
        addAddresses(builder, options.inet6Address)

        if (options.autoRoute) {
            addRoutes(builder, options)
            val dns = options.dnsServerAddress?.value.orEmpty().ifEmpty { TUN_DNS }
            builder.addDnsServer(dns)
        }

        applySplitTunnel(builder)

        val pfd: ParcelFileDescriptor = builder.establish()
            ?: throw IllegalStateException("VpnService.Builder.establish() returned null")
        tunInterface?.close()
        tunInterface = pfd
        // TUN is up — report connected immediately. service.start() may still be
        // waiting on WireGuard handshake; Flutter must not spin until that returns.
        tunnelActive = true
        SingboxBridge.emitStage("connected")
        android.util.Log.i("erebrus-singbox", "TUN established fd=${pfd.fd}")
        return pfd.fd
    }

    private fun addRoutes(builder: Builder, options: TunOptions) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val inet4Route = options.inet4RouteAddress
            if (inet4Route.hasNext()) {
                while (inet4Route.hasNext()) {
                    val p = inet4Route.next()
                    builder.addRoute(p.address(), p.prefix())
                }
            } else if (options.inet4Address.hasNext()) {
                builder.addRoute("0.0.0.0", 0)
            }

            val inet6Route = options.inet6RouteAddress
            if (inet6Route.hasNext()) {
                while (inet6Route.hasNext()) {
                    val p = inet6Route.next()
                    builder.addRoute(p.address(), p.prefix())
                }
            } else if (options.inet6Address.hasNext()) {
                builder.addRoute("::", 0)
            }
            return
        }

        val inet4Range = options.inet4RouteRange
        if (inet4Range.hasNext()) {
            while (inet4Range.hasNext()) {
                val p = inet4Range.next()
                builder.addRoute(p.address(), p.prefix())
            }
        } else {
            builder.addRoute("0.0.0.0", 0)
        }

        val inet6Range = options.inet6RouteRange
        if (inet6Range.hasNext()) {
            while (inet6Range.hasNext()) {
                val p = inet6Range.next()
                builder.addRoute(p.address(), p.prefix())
            }
        } else {
            builder.addRoute("::", 0)
        }
    }

    private fun applySplitTunnel(builder: Builder) {
        val enabled = SingboxBridge.splitTunnelEnabled
        val mode = SingboxBridge.splitTunnelMode
        val packages = SingboxBridge.splitTunnelPackages.filter { it != packageName }

        when {
            enabled && mode == "include" && packages.isNotEmpty() -> {
                // Erebrus itself must remain in the tunnel so its WebView and
                // HTTP clients use the VPN even when only selected apps are included.
                runCatching { builder.addAllowedApplication(packageName) }
                for (pkg in packages) {
                    runCatching { builder.addAllowedApplication(pkg) }
                }
            }
            enabled && mode == "exclude" -> {
                for (pkg in packages) {
                    runCatching { builder.addDisallowedApplication(pkg) }
                }
            }
            else -> {
                // No app filter: all apps, including Erebrus WebView, use the TUN.
                // sing-box carrier sockets avoid recursion via protect(fd) in
                // autoDetectInterfaceControl().
            }
        }
    }

    private fun addAddresses(builder: Builder, prefixes: RoutePrefixIterator) {
        while (prefixes.hasNext()) {
            val p = prefixes.next()
            builder.addAddress(p.address(), p.prefix())
        }
    }

    override fun autoDetectInterfaceControl(fd: Int) {
        protect(fd)
    }

    override fun usePlatformAutoDetectInterfaceControl(): Boolean = true

    override fun useProcFS(): Boolean = false

    override fun underNetworkExtension(): Boolean = false

    /** Route all apps (incl. Chrome) through the VPN on Android 12+. */
    override fun includeAllNetworks(): Boolean = true

    override fun clearDNSCache() {}

    override fun startDefaultInterfaceMonitor(listener: InterfaceUpdateListener) {
        AndroidNetworkPlatform.startMonitor(this, listener)
    }

    override fun closeDefaultInterfaceMonitor(listener: InterfaceUpdateListener) {
        AndroidNetworkPlatform.stopMonitor()
    }

    override fun getInterfaces(): NetworkInterfaceIterator = AndroidNetworkPlatform.getInterfaces(this)

    override fun findConnectionOwner(
        ipProtocol: Int,
        sourceAddress: String,
        sourcePort: Int,
        destinationAddress: String,
        destinationPort: Int,
    ): Int = -1

    override fun packageNameByUid(uid: Int): String = ""

    override fun uidByPackageName(packageName: String): Int = -1

    override fun readWIFIState(): WIFIState = Libbox.newWIFIState("", "")

    override fun sendNotification(notification: LibboxNotification) {}

    override fun writeLog(message: String) {
        android.util.Log.i("erebrus-singbox", message)
    }

    private fun buildNotification(name: String): Notification {
        val mgr = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            mgr.createNotificationChannel(
                NotificationChannel(NOTIF_CHANNEL, "Erebrus VPN", NotificationManager.IMPORTANCE_LOW)
            )
        }
        val tap = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        return Notification.Builder(this, NOTIF_CHANNEL)
            .setContentTitle("Erebrus")
            .setContentText("Protected · $name")
            .setSmallIcon(applicationInfo.icon)
            .setOngoing(true)
            .setContentIntent(tap)
            .build()
    }
}
