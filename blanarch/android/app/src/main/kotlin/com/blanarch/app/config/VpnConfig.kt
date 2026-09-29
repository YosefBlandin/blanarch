package com.blanarch.app.config

import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds
import org.json.JSONObject

/** Defaults for recognising an emailed one-time code. A profile may narrow sender and subject. */
data class OtpRules(
    val codePattern: Regex,
    val timeout: Duration,
    val manualTimeout: Duration,
    val pollInterval: Duration
)

data class RetryPolicy(
    val maxAttempts: Int,
    val attemptTimeout: Duration,
    val connectTimeout: Duration,
    val delayBetween: Duration,
    val maxCookieReuses: Int
)

/** Single sign-on: where the browser hands the session id back, and how long to wait. */
data class SsoSettings(val listenPort: Int, val timeout: Duration)

/**
 * Engine defaults bundled with the app (res/raw/vpn_config.json). Nothing user-specific.
 * [fallbackDns] is used, through the tunnel, only when the gateway gives no DNS server:
 * a tunnel without DNS lets Android send queries outside it.
 */
data class VpnConfig(
    val otp: OtpRules,
    val retry: RetryPolicy,
    val sso: SsoSettings,
    val mru: Int,
    val fallbackDns: List<String> = emptyList()
) {
    companion object {
        fun parse(json: String): VpnConfig {
            val root = JSONObject(json)
            val otp = root.getJSONObject("otp")
            val retry = root.getJSONObject("retry")
            val sso = root.getJSONObject("sso")
            return VpnConfig(
                otp = OtpRules(
                    codePattern = Regex(otp.getString("regex")),
                    timeout = otp.getInt("timeoutSeconds").seconds,
                    manualTimeout = otp.getInt("manualTimeoutSeconds").seconds,
                    pollInterval = otp.getInt("pollSeconds").seconds
                ),
                retry = RetryPolicy(
                    maxAttempts = retry.getInt("maxAttempts"),
                    attemptTimeout = retry.getInt("attemptTimeoutSeconds").seconds,
                    connectTimeout = retry.getInt("connectTimeoutSeconds").seconds,
                    delayBetween = retry.getInt("delayBetweenSeconds").seconds,
                    maxCookieReuses = retry.getInt("maxCookieReuses")
                ),
                sso = SsoSettings(sso.getInt("listenPort"), sso.getInt("timeoutSeconds").seconds),
                mru = root.getInt("mru"),
                fallbackDns = root.optJSONArray("fallbackDns")
                    ?.let { a -> List(a.length()) { a.getString(it) } }
                    .orEmpty()
            )
        }
    }
}
