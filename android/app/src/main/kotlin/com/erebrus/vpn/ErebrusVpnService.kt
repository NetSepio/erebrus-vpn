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
import io.nekohasekai.libbox.BoxService
import io.nekohasekai.libbox.Libbox
import io.nekohasekai.libbox.PlatformInterface
import io.nekohasekai.libbox.TunOptions

/**
 * The single on-device tunnel for every Erebrus protocol. It runs sing-box via
 * libbox; WireGuard and the stealth carriers (VLESS+REALITY / Hysteria2) are
 * just outbounds/endpoints inside the config we are handed — there is no
 * separate WireGuard service anymore.
 *
 * ── REQUIRES the libbox AAR ──────────────────────────────────────────────
 * This file imports `io.nekohasekai.libbox.*`, which comes from a gomobile
 * build of sing-box (see scripts/build-libbox.sh + android/app/libs/README.md).
 * Without `android/app/libs/libbox.aar` present it will not compile — that is
 * expected; the AAR is a build prerequisite. The PlatformInterface surface is
 * version-specific: pin the sing-box version used to build the AAR and verify
 * the overridden method signatures against it (copying sing-box-for-android's
 * `PlatformInterfaceWrapper` is the fastest way to cover the long tail).
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
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) ctx.startForegroundService(i) else ctx.startService(i)
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
            Libbox.setup(filesDir.absolutePath, filesDir.absolutePath, cacheDir.absolutePath, false)
            val service = Libbox.newService(config, this)
            service.start()
            box = service
            SingboxBridge.emitStage("connected")
        } catch (e: Exception) {
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

    // ── PlatformInterface (libbox) ───────────────────────────────────────

    /** Builds the tun device from sing-box's resolved options and returns its fd. */
    override fun openTun(options: TunOptions): Int {
        val builder = Builder()
            .setSession("Erebrus")
            .setMtu(options.mtu)

        val inet4 = options.inet4Address
        while (inet4.hasNext()) {
            val p = inet4.next()
            builder.addAddress(p.address, p.prefix)
        }
        val inet6 = options.inet6Address
        while (inet6.hasNext()) {
            val p = inet6.next()
            builder.addAddress(p.address, p.prefix)
        }
        if (options.autoRoute) {
            builder.addRoute("0.0.0.0", 0)
            builder.addRoute("::", 0)
            val dns = options.dnsServerAddress
            if (dns.isNotEmpty()) builder.addDnsServer(dns)
        }
        // Keep our own sockets (and the OS UI) out of the tunnel.
        runCatching { builder.addDisallowedApplication(packageName) }

        val pfd: ParcelFileDescriptor = builder.establish()
            ?: throw IllegalStateException("VpnService.Builder.establish() returned null")
        return pfd.detachFd()
    }

    /** Lets sing-box protect its outbound sockets from the VPN route loop. */
    override fun autoDetectInterfaceControl(fd: Int) {
        protect(fd)
    }

    override fun usePlatformAutoDetectInterfaceControl(): Boolean = true

    override fun useProcFS(): Boolean = false

    override fun writeLog(message: String) {
        // Forwarded to logcat; surface to Flutter later if useful.
        android.util.Log.i("erebrus-singbox", message)
    }

    // NOTE: depending on the pinned libbox version, additional PlatformInterface
    // members may be required (default interface monitor, network interface
    // getter, findConnectionOwner, package/uid lookups, readWIFIState,
    // systemCertificates, underNetworkExtension, includeAllNetworks…). Implement
    // them per that version — sing-box-for-android's PlatformInterfaceWrapper is
    // the reference. Sensible defaults: underNetworkExtension=false,
    // includeAllNetworks=false, useProcFS=false.

    private fun buildNotification(name: String): Notification {
        val mgr = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            mgr.createNotificationChannel(
                NotificationChannel(NOTIF_CHANNEL, "Erebrus VPN", NotificationManager.IMPORTANCE_LOW)
            )
        }
        val tap = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java),
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
