package com.blanarch.app.vpn

data class Route(val address: String, val prefix: Int)

/** Route and DNS planning for the TUN interface. Pure. */
object Routes {
    fun prefixLength(mask: String): Int = mask.split('.').sumOf { Integer.bitCount(it.trim().toInt()) }

    fun network(ip: String, mask: String): String =
        ip.split('.').map { it.trim().toInt() }.zip(mask.split('.').map { it.trim().toInt() }) { a, m -> a and m }
            .joinToString(".")

    /**
     * No split routes means the gateway wants all traffic. With split routes,
     * the DNS servers get /32 routes too, since Android sends every query to them.
     */
    fun plan(config: TunnelConfig, dns: List<String>): List<Route> {
        if (isFullTunnel(config)) return listOf(Route("0.0.0.0", 0))
        val split = config.routes.mapNotNull { (ip, mask) ->
            runCatching { Route(network(ip, mask), prefixLength(mask)) }.getOrNull()
        }
        return (split + dns.map { Route(it, 32) }).distinct()
    }

    /** The DNS servers the tunnel will use, and whether they are the app's fallback ones. */
    data class DnsChoice(val servers: List<String>, val fallback: Boolean)

    /**
     * Prefer what the link negotiated, then the tunnel settings. When the gateway
     * gives neither, a full tunnel uses the app's [fallback] resolvers: Android
     * would otherwise ask the phone network's DNS servers outside the tunnel (a leak).
     * A split tunnel keeps the phone's DNS, since its public traffic goes outside
     * anyway and the gateway may not let the fallback resolvers through.
     */
    fun dnsFor(
        fromLink: List<String>,
        fromSettings: List<String>,
        fallback: List<String>,
        fullTunnel: Boolean
    ): DnsChoice {
        fun usable(list: List<String>) = list.map { it.trim() }.filter(::isIpv4).distinct()
        usable(fromLink).ifEmpty { usable(fromSettings) }.ifEmpty { null }?.let { return DnsChoice(it, false) }
        return if (fullTunnel) DnsChoice(usable(fallback), true) else DnsChoice(emptyList(), false)
    }

    /** A dotted IPv4 unicast-looking address (not 0.0.0.0). */
    fun isIpv4(s: String): Boolean {
        val parts = s.split('.')
        val valid = parts.size == 4 && parts.all { p -> p.length in 1..3 && p.all(Char::isDigit) && p.toInt() <= 255 }
        return valid && s != "0.0.0.0"
    }

    /** No split routes: every packet, DNS included, goes through the tunnel. */
    fun isFullTunnel(config: TunnelConfig): Boolean = config.routes.isEmpty()

    fun searchDomains(suffix: String?): List<String> =
        suffix?.split(';', ',', ' ')?.map { it.trim() }?.filter { it.isNotEmpty() } ?: emptyList()
}
