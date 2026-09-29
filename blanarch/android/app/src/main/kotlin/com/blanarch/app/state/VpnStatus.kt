package com.blanarch.app.state

enum class VpnPhase {
    IDLE,
    CONNECTING,
    AUTHENTICATING,
    WAITING_OTP,
    WAITING_PUSH,
    WAITING_SSO,
    NEGOTIATING,
    CONNECTED,
    RECONNECTING,

    /** Offline: waiting for Wi-Fi or mobile data before trying again. Attempts are not used up. */
    WAITING_NETWORK,
    DISCONNECTING,
    ERROR
}

/** Machine-readable failure reasons. The UI turns them into localized text. */
enum class ErrorCode(val fatal: Boolean = false) {
    NO_VPN_PASSWORD(fatal = true),
    AUTH_REJECTED(fatal = true),
    UNSUPPORTED_CHALLENGE(fatal = true),
    CERT_MISMATCH(fatal = true),

    /** No pin and not trusted by the system; errorDetail carries the SHA-256 digest. */
    CERT_UNTRUSTED(fatal = true),
    SSO_TIMEOUT(fatal = true),
    SSO_FAILED(fatal = true),
    NO_PROFILE(fatal = true),
    INVALID_ADDRESS(fatal = true),

    /** Saved passwords need the user to unlock the app first. */
    LOCKED(fatal = true),
    PERMISSION_REVOKED(fatal = true),
    OUT_OF_ATTEMPTS(fatal = true),
    OTP_TIMEOUT,
    OTP_REJECTED,
    GATEWAY_UNREACHABLE,
    TUNNEL_REFUSED,
    PROTOCOL,
    LINK_LOST,
    EMAIL_AUTH_FAILED,
    EMAIL_UNREACHABLE,
    EMAIL_NOT_CONFIGURED,

    /** The phone switched networks (for example Wi-Fi to mobile data); the tunnel is rejoined. */
    NETWORK_CHANGED,

    /** No Wi-Fi or mobile data. */
    NO_NETWORK,

    /** The gateway no longer accepts the session (for example after its hard timeout); signing in again. */
    SESSION_EXPIRED,

    /** The address doesn't offer SSL-VPN (spec §3.7); it may use IPsec. */
    SSL_VPN_OFF(fatal = true),

    /** The server asks for a client certificate, which Blanarch doesn't have yet. */
    CLIENT_CERT_REQUIRED(fatal = true)
}

class VpnException(val code: ErrorCode, val detail: String? = null, cause: Throwable? = null) :
    Exception(detail?.let { "$code: $it" } ?: code.name, cause)

/** Immutable snapshot of the connection, published through [StatusStore]. */
data class VpnStatus(
    val phase: VpnPhase = VpnPhase.IDLE,
    val connectionId: String? = null,
    val host: String? = null,
    val attempt: Int = 0,
    val maxAttempts: Int = 0,
    val ip: String? = null,
    val otpMasked: String? = null,
    val connectedSinceMillis: Long? = null,
    val emailWatching: Boolean = false,
    val emailIssue: ErrorCode? = null,
    val error: ErrorCode? = null,
    val errorDetail: String? = null,
    /** While WAITING_SSO: the page the user must open in the browser. */
    val ssoUrl: String? = null,
    /** While WAITING_OTP or WAITING_SSO: when the app stops waiting (epoch millis). */
    val deadlineMillis: Long? = null,
    /** When this connection run started (epoch millis); null when idle or connected. */
    val startedMillis: Long? = null,
    /** Why the previous attempt failed, while the next one runs. */
    val retryReason: ErrorCode? = null,
    // While connected, for the details screen (no secrets).
    val port: Int? = null,
    val bytesIn: Long = 0,
    val bytesOut: Long = 0,
    val latencyMillis: Long? = null,
    val dns: List<String> = emptyList(),
    val dnsSuffix: String? = null,
    /** "network/prefix"; empty while connected means all traffic goes through the tunnel. */
    val routes: List<String> = emptyList(),
    val mtu: Int? = null,
    val tls: String? = null,
    val signIn: SignInMethod? = null,
    /** Times the tunnel was rejoined with the same session. */
    val reconnects: Int = 0,
    /** Addresses tried in this run, in order. */
    val triedHosts: List<String> = emptyList()
)

/** How the user got in, for the details screen. */
enum class SignInMethod { PASSWORD, CODE, PUSH, SSO }

enum class LogLevel { INFO, OK, ERROR }

/**
 * Main steps of a connection, so the app can show them in the user's language.
 * [LogEntry.message] stays English for sharing with IT; [LogEntry.args] fill the translation.
 */
enum class LogEvent {
    /** args: connection name */
    STARTING,

    /** args: attempt, max attempts, host:port */
    ATTEMPT,

    /** args: ErrorCode name, host (may be empty) */
    FAILED,

    /** args: username */
    SIGNING_IN,
    SIGNED_IN,
    WAITING_SSO,
    APPROVE_PUSH,

    /** args: masked code */
    CODE_RECEIVED,

    /** args: tunnel IP */
    CONNECTED,
    CONNECTION_LOST,
    RECONNECTING,
    DISCONNECTED,
    NETWORK_LOST,
    NETWORK_BACK,
    NETWORK_CHANGED,
    SESSION_EXPIRED,

    /** args: the fallback DNS servers, comma separated */
    DNS_FALLBACK
}

data class LogEntry(
    val timeMillis: Long,
    val level: LogLevel,
    val message: String,
    val event: LogEvent? = null,
    val args: List<String> = emptyList()
)

fun maskCode(code: String): String =
    if (code.length <= 2) "•".repeat(code.length) else code.first() + "•".repeat(code.length - 2) + code.last()
