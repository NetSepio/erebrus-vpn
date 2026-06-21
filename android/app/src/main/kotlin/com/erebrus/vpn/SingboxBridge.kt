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

    private var statusSink: EventChannel.EventSink? = null
    private var statsSink: EventChannel.EventSink? = null

    fun setStatusSink(sink: EventChannel.EventSink?) {
        statusSink = sink
        if (sink != null) emitStage(stage) // replay current stage on (re)subscribe
    }

    fun setStatsSink(sink: EventChannel.EventSink?) {
        statsSink = sink
    }

    fun emitStage(newStage: String) {
        stage = newStage
        main.post { statusSink?.success(newStage) }
    }

    fun emitStats(rx: Long, tx: Long, uplinkBps: Long, downlinkBps: Long) {
        main.post {
            statsSink?.success(
                mapOf(
                    "rx_bytes" to rx,
                    "tx_bytes" to tx,
                    "uplink_bps" to uplinkBps,
                    "downlink_bps" to downlinkBps,
                )
            )
        }
    }
}
