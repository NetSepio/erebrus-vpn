package com.erebrus.vpn

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.system.OsConstants
import android.util.Log
import io.nekohasekai.libbox.libbox.InterfaceUpdateListener
import io.nekohasekai.libbox.libbox.Libbox
import io.nekohasekai.libbox.libbox.NetworkInterfaceIterator
import io.nekohasekai.libbox.libbox.StringIterator
import java.net.Inet6Address
import java.net.InterfaceAddress
import java.net.NetworkInterface as JavaNetworkInterface

/**
 * sing-box needs live network interface metadata for stealth carriers
 * (VLESS/Hysteria2 detours). Without this, WireGuard-over-stealth fails with
 * "no available network interface" on Android.
 */
internal object AndroidNetworkPlatform {
    private const val TAG = "erebrus-singbox"

    private var connectivity: ConnectivityManager? = null
    private var callback: ConnectivityManager.NetworkCallback? = null
    private var listener: InterfaceUpdateListener? = null
    private var activeNetwork: Network? = null

    fun startMonitor(ctx: Context, updateListener: InterfaceUpdateListener) {
        listener = updateListener
        val cm = ctx.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        if (connectivity == null) {
            connectivity = cm
            registerCallback(cm)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            activeNetwork = cm.activeNetwork
        }
        activeNetwork?.let { notifyNetwork(cm, it) }
    }

    fun stopMonitor() {
        listener = null
        val cm = connectivity ?: return
        callback?.let { runCatching { cm.unregisterNetworkCallback(it) } }
        callback = null
        connectivity = null
        activeNetwork = null
    }

    fun getInterfaces(ctx: Context): NetworkInterfaceIterator {
        val cm = ctx.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val javaIfaces = JavaNetworkInterface.getNetworkInterfaces().toList()
        val out = mutableListOf<io.nekohasekai.libbox.libbox.NetworkInterface>()
        for (network in cm.allNetworks) {
            val link = cm.getLinkProperties(network) ?: continue
            val caps = cm.getNetworkCapabilities(network) ?: continue
            val name = link.interfaceName ?: continue
            val javaIface = javaIfaces.find { it.name == name } ?: continue

            val boxIface = io.nekohasekai.libbox.libbox.NetworkInterface()
            boxIface.name = name
            boxIface.index = javaIface.index
            boxIface.dnsServer = StringArray(link.dnsServers.mapNotNull { it.hostAddress }.iterator())
            boxIface.type = when {
                caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> Libbox.InterfaceTypeWIFI
                caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> Libbox.InterfaceTypeCellular
                caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> Libbox.InterfaceTypeEthernet
                else -> Libbox.InterfaceTypeOther
            }
            runCatching { boxIface.mtu = javaIface.mtu }.onFailure {
                Log.w(TAG, "failed to read mtu for $name", it)
            }
            boxIface.addresses = StringArray(
                javaIface.interfaceAddresses.map { it.toPrefix() }.iterator(),
            )
            var flags = 0
            if (caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) {
                flags = flags or OsConstants.IFF_UP or OsConstants.IFF_RUNNING
            }
            if (javaIface.isLoopback) flags = flags or OsConstants.IFF_LOOPBACK
            if (javaIface.isPointToPoint) flags = flags or OsConstants.IFF_POINTOPOINT
            if (javaIface.supportsMulticast()) flags = flags or OsConstants.IFF_MULTICAST
            boxIface.flags = flags
            boxIface.metered = !caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED)
            out.add(boxIface)
        }
        return InterfaceArray(out.iterator())
    }

    private fun registerCallback(cm: ConnectivityManager) {
        val request = NetworkRequest.Builder()
            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_RESTRICTED)
            .apply {
                if (Build.VERSION.SDK_INT == Build.VERSION_CODES.M) {
                    removeCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
                    removeCapability(NetworkCapabilities.NET_CAPABILITY_CAPTIVE_PORTAL)
                }
            }
            .build()
        val handler = Handler(Looper.getMainLooper())
        callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                activeNetwork = network
                notifyNetwork(cm, network)
            }

            override fun onCapabilitiesChanged(network: Network, networkCapabilities: NetworkCapabilities) {
                if (activeNetwork == network) notifyNetwork(cm, network)
            }

            override fun onLost(network: Network) {
                if (activeNetwork == network) {
                    activeNetwork = null
                    listener?.updateDefaultInterface("", -1, false, false)
                }
            }
        }
        val cb = callback!!
        when {
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.S ->
                cm.registerBestMatchingNetworkCallback(request, cb, handler)
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.P ->
                cm.requestNetwork(request, cb, handler)
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.N ->
                cm.registerDefaultNetworkCallback(cb, handler)
            else -> cm.requestNetwork(request, cb)
        }
    }

    private fun notifyNetwork(cm: ConnectivityManager, network: Network) {
        val l = listener ?: return
        val name = cm.getLinkProperties(network)?.interfaceName ?: return
        repeat(10) {
            try {
                val idx = JavaNetworkInterface.getByName(name)?.index ?: return@repeat
                val caps = cm.getNetworkCapabilities(network)
                val expensive = caps?.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED) == false
                l.updateDefaultInterface(name, idx, expensive, false)
                return
            } catch (_: Exception) {
                Thread.sleep(100)
            }
        }
    }

    private class StringArray(private val iterator: Iterator<String>) : StringIterator {
        override fun hasNext(): Boolean = iterator.hasNext()
        override fun next(): String = iterator.next()
        override fun len(): Int = 0
    }

    private class InterfaceArray(
        private val iterator: Iterator<io.nekohasekai.libbox.libbox.NetworkInterface>,
    ) : NetworkInterfaceIterator {
        override fun hasNext(): Boolean = iterator.hasNext()
        override fun next(): io.nekohasekai.libbox.libbox.NetworkInterface = iterator.next()
    }

    private fun InterfaceAddress.toPrefix(): String = if (address is Inet6Address) {
        "${Inet6Address.getByAddress(address.address).hostAddress}/$networkPrefixLength"
    } else {
        "${address.hostAddress}/$networkPrefixLength"
    }
}