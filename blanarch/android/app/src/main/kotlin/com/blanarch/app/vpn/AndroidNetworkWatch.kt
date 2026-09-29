package com.blanarch.app.vpn

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Build
import android.os.Handler
import android.os.Looper
import java.io.Closeable
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

/**
 * The phone's real network (Wi-Fi, mobile data, ethernet), never a VPN.
 *
 * A VPN app's own default network becomes its VPN once the tunnel is up, so the
 * default-network callback can't be used. Instead we ask for internet networks;
 * a [NetworkRequest] excludes VPNs by default (NET_CAPABILITY_NOT_VPN).
 * - Android 12+: the system reports the single best such network.
 * - Android 10 and 11: we get every such network and follow the most recent one.
 */
class AndroidNetworkWatch(
    context: Context,
    private val log: (String) -> Unit = {},
    private val onChange: (Network?) -> Unit = {}
) : NetworkWatch,
    Closeable {
    private val connectivity = context.getSystemService(ConnectivityManager::class.java)
    private val request = NetworkRequest.Builder().addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET).build()

    /** Android 10/11: networks currently up, oldest first. */
    private val available = LinkedHashSet<Network>()

    @Volatile private var network: Network? = connectivity.activeNetwork?.takeUnless(::isVpn)
    private val state = MutableStateFlow(network?.let(::idOf))
    override val current: StateFlow<String?> = state

    private val callback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(n: Network) {
            if (isVpn(n)) return
            synchronized(available) { available.add(n) }
            set(n)
        }

        override fun onLost(n: Network) {
            val next = synchronized(available) {
                available.remove(n)
                available.lastOrNull()
            }
            // Only the network we were using matters; on 12+ a switch reports the new one via onAvailable.
            if (n == network) set(next)
        }
    }

    init {
        if (Build.VERSION.SDK_INT >= 31) {
            connectivity.registerBestMatchingNetworkCallback(request, callback, Handler(Looper.getMainLooper()))
        } else {
            connectivity.registerNetworkCallback(request, callback)
        }
    }

    private fun set(n: Network?) {
        if (n == network && state.value != null) return
        log("Network: " + (n?.let { "${kind(it)} #${idOf(it)}" } ?: "none"))
        network = n
        state.value = n?.let(::idOf)
        onChange(n)
    }

    override fun close() {
        runCatching { connectivity.unregisterNetworkCallback(callback) }
    }

    private fun isVpn(n: Network) =
        connectivity.getNetworkCapabilities(n)?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == true

    private fun idOf(n: Network) = n.networkHandle.toString()

    private fun kind(n: Network): String {
        val caps = connectivity.getNetworkCapabilities(n) ?: return "unknown"
        return listOfNotNull(
            "wifi".takeIf { caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) },
            "mobile".takeIf { caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) },
            "ethernet".takeIf { caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) }
        ).joinToString("+").ifEmpty { "other" }
    }
}
