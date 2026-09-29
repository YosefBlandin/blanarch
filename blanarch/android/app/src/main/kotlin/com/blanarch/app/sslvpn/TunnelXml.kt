package com.blanarch.app.sslvpn

import com.blanarch.app.vpn.TunnelConfig

/**
 * Reads the tunnel settings document from /remote/fortisslvpn_xml (spec §4).
 * A small tag scanner rather than a full XML parser: the document is flat, and
 * Android's XML pull parser is not available in local unit tests.
 */
object TunnelXml {
    private val COMMENT = Regex("<!--.*?-->", RegexOption.DOT_MATCHES_ALL)
    private val TAG = Regex("<(/?)([A-Za-z_][A-Za-z0-9_:.-]*)([^>]*?)(/?)>")
    private val ATTR = Regex("([A-Za-z_][A-Za-z0-9_:.-]*)\\s*=\\s*(?:'([^']*)'|\"([^\"]*)\")")

    fun parse(xml: String): TunnelConfig {
        val stack = ArrayDeque<String>()
        val dns = mutableListOf<String>()
        val domains = mutableListOf<String>()
        val routes = mutableListOf<Pair<String, String>>()
        var assigned: String? = null
        for (m in TAG.findAll(COMMENT.replace(xml, ""))) {
            val closing = m.groupValues[1] == "/"
            val name = m.groupValues[2].lowercase()
            if (closing) {
                val at = stack.lastIndexOf(name)
                if (at >= 0) while (stack.size > at) stack.removeLast()
                continue
            }
            val attrs = attributes(m.groupValues[3])
            if ("ipv6" !in stack) {
                when (name) {
                    "dns" -> {
                        attrs["ip"]?.takeIf { it.isNotBlank() }?.let { dns += it.trim() }
                        attrs["domain"]?.takeIf { it.isNotBlank() }?.let { domains += it.trim() }
                    }
                    "assigned-addr" -> attrs["ipv4"]?.takeIf { it.isNotBlank() }?.let { assigned = it.trim() }
                    "addr" -> if ("split-tunnel-info" in stack) {
                        val ip = attrs["ip"]?.trim()
                        val mask = attrs["mask"]?.trim()
                        if (!ip.isNullOrEmpty() && !mask.isNullOrEmpty()) routes += ip to mask
                    }
                }
            }
            val selfClosing = m.groupValues[4] == "/"
            if (!selfClosing) stack.addLast(name)
        }
        return TunnelConfig(
            assignedIp = assigned,
            dns = dns.distinct(),
            dnsSuffix = domains.takeIf { it.isNotEmpty() }?.joinToString(";"),
            routes = routes
        )
    }

    private fun attributes(text: String): Map<String, String> = ATTR.findAll(text).associate { a ->
        val raw = a.groups[2]?.value ?: a.groups[3]?.value ?: ""
        a.groupValues[1].lowercase() to unescape(raw)
    }

    private fun unescape(s: String): String = if ('&' !in s) {
        s
    } else {
        s.replace("&lt;", "<").replace("&gt;", ">").replace("&quot;", "\"").replace("&apos;", "'")
            .replace("&amp;", "&")
    }
}
