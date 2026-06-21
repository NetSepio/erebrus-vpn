package com.erebrus.vpn

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import io.nekohasekai.libbox.libbox.BoxService
import io.nekohasekai.libbox.libbox.InterfaceUpdateListener
import io.nekohasekai.libbox.libbox.Libbox
import io.nekohasekai.libbox.libbox.NetworkInterface
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
        private const val NOTIF_CHANNEL = "erebrus_vpn"
        private const val NOTIF_ID = 0x5713

        fun start(ctx: Context, config: String, name: String) {
            val i = Intent(ctx, ErebrusVpnService::class.java).apply {
                action = ACTION_START
                putExtra(EXTRA_CONFIG, config)
                putExtra(EXTRA_NAME, name)
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

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopTunnel()
                return START_NOT_STICKY
            }
            ACTION_START -> {
                val config = intent.getStringExtra(EXTRA_CONFIG).orEmpty()
                val name = intent.getStringExtra(EXTRA_NAME) ?: "Erebrus"
                startTunnel(config, name)
            }
        }
        return START_STICKY
    }

    private fun startTunnel(config: String, name: String) {
        SingboxBridge.emitStage("connecting")
        startForeground(NOTIF_ID, buildNotification(name))
        try {
            val setup = SetupOptions().apply {
                basePath = filesDir.absolutePath
                workingPath = filesDir.absolutePath
                tempPath = cacheDir.absolutePath
                fixAndroidStack = true
            }
            Libbox.setup(setup)
            val service = Libbox.newService(config, this)
            service.start()
            box = service
            SingboxBridge.emitStage("connected")
        } catch (e: Exception) {
            android.util.Log.e("erebrus-singbox", "startTunnel failed", e)
            SingboxBridge.emitStage("error")
            stopTunnel()
        }
    }

    private fun stopTunnel() {
        SingboxBridge.emitStage("disconnecting")
        try {
            box?.close()
        } catch (_: Exception) {
        } finally {
            box = null
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            SingboxBridge.emitStage("disconnected")
        }
    }

    override fun onDestroy() {
        stopTunnel()
        super.onDestroy()
    }

    // ── PlatformInterface (libbox v1.11.x) ───────────────────────────────

    override fun openTun(options: TunOptions): Int {
        val builder = Builder()
            .setSession("Erebrus")
            .setMtu(options.mtu)

        addAddresses(builder, options.inet4Address)
        addAddresses(builder, options.inet6Address)

        if (options.autoRoute) {
            builder.addRoute("0.0.0.0", 0)
            builder.addRoute("::", 0)
            val dns = options.dnsServerAddress?.value.orEmpty()
            if (dns.isNotEmpty()) builder.addDnsServer(dns)
        }

        runCatching { builder.addDisallowedApplication(packageName) }

        val pfd: ParcelFileDescriptor = builder.establish()
            ?: throw IllegalStateException("VpnService.Builder.establish() returned null")
        return pfd.detachFd()
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

    override fun includeAllNetworks(): Boolean = false

    override fun clearDNSCache() {}

    override fun startDefaultInterfaceMonitor(listener: InterfaceUpdateListener) {}

    override fun closeDefaultInterfaceMonitor(listener: InterfaceUpdateListener) {}

    override fun getInterfaces(): NetworkInterfaceIterator = EmptyNetworkInterfaceIterator

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

    private object EmptyNetworkInterfaceIterator : NetworkInterfaceIterator {
        override fun hasNext(): Boolean = false
        override fun next(): NetworkInterface {
            throw NoSuchElementException()
        }
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