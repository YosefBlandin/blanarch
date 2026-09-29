package com.blanarch.app.profile

import org.json.JSONArray
import org.json.JSONObject

enum class AuthMode {
    /** Username and password, then a code or push if the gateway asks. */
    PASSWORD,

    /** Single sign-on in the browser (SAML). */
    SSO
}

enum class SecondFactorPreference {
    /** Push approval when the gateway offers it, otherwise a code. */
    AUTO,

    /** Always a typed or emailed code. */
    CODE
}

/** Where to read emailed codes from, if the user enabled it. The password is stored separately. */
data class EmailOtpSource(
    val account: String,
    val imapHost: String,
    val imapPort: Int = 993,
    val mailbox: String = "INBOX",
    /** Only mail from this sender counts (empty means any sender). */
    val from: String = ""
)

/** One company VPN the user set up. No secrets live here. */
data class Profile(
    val id: String,
    val name: String,
    /** Gateway addresses tried in order; the first is the main one. */
    val hosts: List<String>,
    val port: Int,
    val realm: String = "",
    val authMode: AuthMode = AuthMode.PASSWORD,
    val username: String = "",
    val secondFactor: SecondFactorPreference = SecondFactorPreference.AUTO,
    val emailOtp: EmailOtpSource? = null
) {
    val mainHost: String get() = hosts.first()

    fun toJson(): JSONObject = JSONObject()
        .put("id", id)
        .put("name", name)
        .put("hosts", JSONArray(hosts))
        .put("port", port)
        .put("realm", realm)
        .put("authMode", authMode.name)
        .put("username", username)
        .put("secondFactor", secondFactor.name)
        .put(
            "emailOtp",
            emailOtp?.let {
                JSONObject()
                    .put("account", it.account)
                    .put("imapHost", it.imapHost)
                    .put("imapPort", it.imapPort)
                    .put("mailbox", it.mailbox)
                    .put("from", it.from)
            } ?: JSONObject.NULL
        )

    companion object {
        fun fromJson(o: JSONObject): Profile {
            val hosts = o.getJSONArray("hosts")
            val email = o.optJSONObject("emailOtp")
            return Profile(
                id = o.getString("id"),
                name = o.getString("name"),
                hosts = (0 until hosts.length()).map { hosts.getString(it) },
                port = o.getInt("port"),
                realm = o.optString("realm", ""),
                authMode = AuthMode.valueOf(o.optString("authMode", AuthMode.PASSWORD.name)),
                username = o.optString("username", ""),
                secondFactor = SecondFactorPreference.valueOf(
                    o.optString("secondFactor", SecondFactorPreference.AUTO.name)
                ),
                emailOtp = email?.let {
                    EmailOtpSource(
                        account = it.getString("account"),
                        imapHost = it.getString("imapHost"),
                        imapPort = it.optInt("imapPort", 993),
                        mailbox = it.optString("mailbox", "INBOX"),
                        from = it.optString("from", "")
                    )
                }
            )
        }
    }
}

/** Parses what the user typed as a VPN address: `vpn.co.com`, `vpn.co.com:10443`, `https://vpn.co.com/remote/login`. */
object Address {
    data class Parsed(val host: String, val port: Int)

    fun parse(input: String, defaultPort: Int = 443): Parsed? {
        var s = input.trim()
        s = s.removePrefix("https://").removePrefix("http://")
        s = s.substringBefore('/').substringBefore('?').substringBefore('#')
        if (s.isEmpty() || s.any { it.isWhitespace() }) return null
        val host: String
        val port: Int
        if (s.startsWith("[")) { // IPv6 literal
            val end = s.indexOf(']')
            if (end < 0) return null
            host = s.substring(1, end)
            port = s.substring(end + 1).removePrefix(":").ifEmpty { "$defaultPort" }.toIntOrNull() ?: return null
        } else if (s.count { it == ':' } == 1) {
            host = s.substringBefore(':')
            port = s.substringAfter(':').toIntOrNull() ?: return null
        } else {
            host = s
            port = defaultPort
        }
        if (host.isEmpty() || port !in 1..65535) return null
        return Parsed(host.lowercase(), port)
    }
}
