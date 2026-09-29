package com.blanarch.app.sslvpn

import java.net.URLEncoder

/** What a login response means (spec §3.2 and §3.3). */
sealed interface LoginOutcome {
    data class LoggedIn(val cookie: String) : LoginOutcome

    data object Rejected : LoginOutcome

    data object UnsupportedChallenge : LoginOutcome

    /** A second factor is needed; [fields] are the step-1 values to echo back. */
    data class NeedsToken(val tokenInfo: String, val fields: Map<String, String>) : LoginOutcome {
        val pushOffered: Boolean get() = tokenInfo.startsWith("ftm_push")
    }

    data class HttpError(val status: Int) : LoginOutcome

    data object Unexpected : LoginOutcome
}

/** Pure helpers for the HTTPS sign-in: body parsing, outcome classification and form bodies. */
object LoginProtocol {
    /** Keys echoed back unchanged in step 2 (spec §3.3). */
    val ECHOED_KEYS = listOf("reqid", "polid", "grp", "portal", "magic", "peer")

    /** Splits a "ret" body on `&`, `,`, CR and LF into key/value pairs (spec §3.1). First value wins. */
    fun parseRetValues(body: String): Map<String, String> {
        val out = LinkedHashMap<String, String>()
        body.split('&', ',', '\r', '\n').forEach { piece ->
            val eq = piece.indexOf('=')
            if (eq <= 0) return@forEach
            val key = piece.substring(0, eq).trim()
            if (key.isNotEmpty() && key !in out) out[key] = piece.substring(eq + 1)
        }
        return out
    }

    /** Step-1 outcome. A non-empty cookie wins; then HTTP status; then the "ret" body. */
    fun classifyStep1(response: HttpResponse): LoginOutcome {
        response.sessionCookie?.let { return LoginOutcome.LoggedIn(it) }
        if (response.status != 200) return LoginOutcome.HttpError(response.status)
        val values = parseRetValues(response.bodyText)
        val tokenInfo = values["tokeninfo"]
        return when {
            values["ret"] == "0" -> LoginOutcome.Rejected
            values["ret"] == "6" -> LoginOutcome.UnsupportedChallenge
            tokenInfo != null -> LoginOutcome.NeedsToken(tokenInfo, ECHOED_KEYS.associateWith { values[it] ?: "" })
            // Some gateways answer a wrong password with their HTML login page, not ret=0 (spec §3.2).
            values["ret"] == null && isHtml(response) -> LoginOutcome.Rejected
            else -> LoginOutcome.Unexpected
        }
    }

    private fun isHtml(response: HttpResponse): Boolean =
        response.header("Content-Type")?.contains("text/html", ignoreCase = true) == true ||
            response.bodyText.trimStart().startsWith("<")

    /**
     * A reply the app didn't recognise, described without any values (no cookies,
     * ids or text), so it can go in the activity log and be shared with IT.
     */
    fun describeUnexpected(response: HttpResponse): String {
        val type = response.header("Content-Type")?.substringBefore(';')?.trim() ?: "no type"
        val text = response.bodyText.trim()
        val shape = when {
            text.isEmpty() -> "empty body"
            text.startsWith("<") -> "HTML page"
            else -> "fields: " + parseRetValues(text).keys.joinToString(",").ifEmpty { "none" }
        }
        val cookie = if (response.headerValues("Set-Cookie").any { it.contains(HttpResponse.COOKIE_NAME) }) {
            ", cookie cleared"
        } else {
            ""
        }
        return "HTTP ${response.status}, $type, $shape$cookie"
    }

    fun encode(value: String): String = URLEncoder.encode(value, "UTF-8")

    fun passwordBody(username: String, password: String, realm: String): String =
        "username=${encode(username)}&credential=${encode(password)}&realm=${encode(realm)}&ajax=1"

    /** Step-2 body for a typed code, echoing [fields] verbatim (spec §3.3). */
    fun codeBody(username: String, realm: String, fields: Map<String, String>, code: String): String =
        commonTokenBody(username, realm, fields) + "&code=${encode(code)}&code2=&magic=${fields["magic"] ?: ""}"

    /** Step-2 body asking for a FortiToken Mobile push approval (spec §3.3). */
    fun pushBody(username: String, realm: String, fields: Map<String, String>): String =
        commonTokenBody(username, realm, fields) + "&ftmpush=1"

    private fun commonTokenBody(username: String, realm: String, fields: Map<String, String>): String {
        fun f(key: String) = fields[key] ?: ""
        return "username=${encode(username)}&realm=${encode(realm)}&reqid=${f("reqid")}&polid=${f("polid")}" +
            "&grp=${f("grp")}&portal=${f("portal")}&peer=${f("peer")}"
    }

    /** Browser URL that starts SAML sign-in (spec §3.4 step 2). */
    fun samlStartUrl(host: String, port: Int): String = "https://${hostForUrl(host)}:$port/remote/saml/start?redirect=1"

    fun samlAuthPath(id: String): String = "/remote/saml/auth_id?id=${encode(id)}"

    private fun hostForUrl(host: String) = if (host.contains(':') && !host.startsWith("[")) "[$host]" else host
}
