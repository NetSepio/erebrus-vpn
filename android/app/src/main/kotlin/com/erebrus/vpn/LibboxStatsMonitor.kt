package com.erebrus.vpn

import io.nekohasekai.libbox.libbox.BoxService
import io.nekohasekai.libbox.libbox.CommandClient
import io.nekohasekai.libbox.libbox.CommandClientHandler
import io.nekohasekai.libbox.libbox.CommandClientOptions
import io.nekohasekai.libbox.libbox.CommandServer
import io.nekohasekai.libbox.libbox.CommandServerHandler
import io.nekohasekai.libbox.libbox.ConnectionIterator
import io.nekohasekai.libbox.libbox.Connections
import io.nekohasekai.libbox.libbox.DeprecatedNoteIterator
import io.nekohasekai.libbox.libbox.Libbox
import io.nekohasekai.libbox.libbox.OutboundGroupIterator
import io.nekohasekai.libbox.libbox.StatusMessage
import io.nekohasekai.libbox.libbox.StringIterator
import io.nekohasekai.libbox.libbox.SystemProxyStatus

/**
 * Bridges libbox traffic counters to Flutter via [SingboxBridge.emitStats].
 * Requires [CommandServer] alongside the running [BoxService].
 */
internal class LibboxStatsMonitor : CommandClientHandler, CommandServerHandler {
    private var commandServer: CommandServer? = null
    private var commandClient: CommandClient? = null

    fun start(service: BoxService) {
        stop()
        val server = Libbox.newCommandServer(this, 300)
        server.setService(service)
        server.start()
        commandServer = server

        val options = CommandClientOptions()
        options.command = Libbox.CommandStatus
        options.statusInterval = 1_000_000_000L // 1s in nanoseconds

        val client = Libbox.newCommandClient(this, options)
        client.connect()
        commandClient = client
    }

    fun stop() {
        runCatching { commandClient?.disconnect() }
        runCatching { commandClient?.serviceClose() }
        commandClient = null
        runCatching { commandServer?.close() }
        commandServer = null
    }

    override fun writeStatus(message: StatusMessage) {
        if (!message.trafficAvailable) return
        SingboxBridge.emitStats(
            rx = message.downlinkTotal,
            tx = message.uplinkTotal,
            uplinkBps = message.uplink,
            downlinkBps = message.downlink,
        )
    }

    override fun getSystemProxyStatus(): SystemProxyStatus =
        SystemProxyStatus().apply {
            setAvailable(false)
            setEnabled(false)
        }

    override fun postServiceClose() {}

    override fun serviceReload() {}

    override fun setSystemProxyEnabled(isEnabled: Boolean) {}

    override fun clearLogs() {}

    override fun connected() {}

    override fun disconnected(message: String) {}

    override fun initializeClashMode(modeList: StringIterator, currentMode: String) {}

    override fun updateClashMode(newMode: String) {}

    override fun writeConnections(message: Connections) {}

    override fun writeGroups(message: OutboundGroupIterator) {}

    override fun writeLogs(messageList: StringIterator) {}
}