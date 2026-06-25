package com.erebrus.vpn

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

/**
 * Shared state between [ErebrusVpnService] and the Flutter channels in
 * [MainActivity]. The service runs in its own process-lifecycle; this singleton
 * holds the active event sinks and the latest stage so both sides stay in sync.
 */
object SingboxBridge {
    const val METHOD_CHANNEL = "dev.erebrus/singbox"
    const val STATUS_CHANNEL = "dev.erebrus/singbox/status"
    const val STATS_CHANNEL = "dev.erebrus/singbox/stats"

    private val main = Handler(Looper.getMainLooper())

    @Volatile var stage: String = "disconnected"
        private set

    @Volatile var splitTunnelEnabled: Boolean = false
        private set

    /** "include" = VPN only for selected apps; "exclude" = selected apps bypass VPN. */
    @Volatile var splitTunnelMode: String = "exclude"
        private set

    @Volatile var splitTunnelPackages: List<String> = emptyList()
        private set

    fun setSplitTunnel(enabled: Boolean, mode: String?, packages: List<String>?) {
        splitTunnelEnabled = enabled
        splitTunnelMode = if (mode == "include") "include" else "exclude"
        splitTunnelPackages = packages?.filter { it.isNotBlank() }?.distinct() ?: emptyList()
    }

    private var statusSink: EventChannel.EventSink? = null
    private var statsSink: EventChannel.EventSink? = null
    private var lastStats: Map<String, Long>? = null

    fun setStatusSink(sink: EventChannel.EventSink?) {
        statusSink = sink
        if (sink != null) emitStage(stage) // replay current stage on (re)subscribe
    }

    fun setStatsSink(sink: EventChannel.EventSink?) {
        statsSink = sink
        val cached = lastStats
        if (sink != null && cached != null) {
            main.post { statsSink?.success(cached) }
        }
    }

    fun emitStage(newStage: String) {
        stage = newStage
        main.post { statusSink?.success(newStage) }
    }

    fun emitStats(rx: Long, tx: Long, uplinkBps: Long, downlinkBps: Long) {
        lastStats = mapOf(
            "rx_bytes" to rx,
            "tx_bytes" to tx,
            "uplink_bps" to uplinkBps,
            "downlink_bps" to downlinkBps,
        )
        main.post { statsSink?.success(lastStats) }
    }
}