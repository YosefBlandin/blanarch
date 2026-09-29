package com.blanarch.app.vpn

import com.blanarch.app.profile.EmailOtpSource
import com.blanarch.app.state.ErrorCode
import java.io.Closeable
import java.io.InputStream
import java.io.OutputStream
import kotlin.time.Duration
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

/** Settings the gateway pushes in /remote/fortisslvpn_xml. */
data class TunnelConfig(
    val assignedIp: String? = null,
    val dns: List<String> = emptyList(),
    val dnsSuffix: String? = null,
    /** (network, dotted mask). Empty means route all traffic. */
    val routes: List<Pair<String, String>> = emptyList()
)

/** What IPCP negotiated for this end of the link. */
data class IpConfig(val ip: String, val dns: List<String>)

/** How the user answers the gateway's second-factor challenge. */
sealed interface SecondFactor {
    /** A typed or emailed one-time code. */
    data class Code(val code: String) : SecondFactor

    /** Approve a FortiToken Mobile push notification instead of typing a code. */
    data object Push : SecondFactor
}

/**
 * Asked only when the gateway requires a second factor.
 * [pushOffered] is true when the gateway allows FortiToken push for this login.
 */
fun interface SecondFactorProvider {
    suspend fun provide(pushOffered: Boolean): SecondFactor
}

/** What a gateway supports, learned before the first login (spec §3.7). */
data class GatewayProbe(
    /** SHA-256 of the leaf certificate (DER), 64 lowercase hex characters. */
    val certSha256: String,
    /** True when the certificate chains to a CA the system trusts for this host. */
    val trustedBySystem: Boolean,
    /** True when the login page offers single sign-on (SAML). */
    val samlOffered: Boolean,
    /** The SSL-VPN login page is there (spec §3.7). False looks like FortiOS 7.6.3+ without tunnel mode. */
    val sslVpnPortal: Boolean = true,
    /** The server asked for a client certificate during the TLS handshake. */
    val clientCertRequested: Boolean = false
)

/** One FortiGate endpoint (host:port) for the length of one attempt. */
interface VpnGateway : Closeable {
    /** TLS version and cipher of the last connection, for the details screen, e.g. "TLSv1.3 · TLS_AES_256_GCM_SHA384". */
    val tlsDescription: String? get() = null

    /** Username/password login (spec §3.2 and §3.3). */
    suspend fun login(username: String, password: String, secondFactor: SecondFactorProvider)

    /** URL the browser opens to start SAML sign-in, redirecting to 127.0.0.1:[listenPort] (spec §3.4). */
    fun samlStartUrl(listenPort: Int): String

    /** Finishes SAML sign-in with the id the browser delivered to the loopback listener. */
    suspend fun loginWithSamlId(id: String)

    suspend fun fetchTunnelConfig(): TunnelConfig
    suspend fun openLink(): PacketLink
    suspend fun logout()
}

fun interface GatewayProber {
    suspend fun probe(host: String, port: Int): GatewayProbe
}

fun interface GatewayFactory {
    fun create(host: String, port: Int): VpnGateway
}

/**
 * The phone's own network (Wi-Fi or mobile data), never the VPN itself.
 * [current] is an id per network, or null while offline; a new id means the phone switched networks.
 */
interface NetworkWatch {
    val current: StateFlow<String?>
}

/** For tests and callers without a real network monitor: always online, never changes. */
object AlwaysOnline : NetworkWatch {
    override val current: StateFlow<String?> = MutableStateFlow("online")
}

/** Counters for the connected screen. [rttMillis] comes from the keepalive echo; null until the first reply. */
data class LinkStats(val bytesIn: Long = 0, val bytesOut: Long = 0, val rttMillis: Long? = null)

/** The PPP link inside the TLS tunnel. */
interface PacketLink : Closeable {
    val stats: LinkStats get() = LinkStats()

    suspend fun negotiate(timeout: Duration): IpConfig

    /** Moves packets between [tun] and the gateway until the link ends; returns why it ended. */
    suspend fun pump(tun: TunDevice): String
}

/** The Android TUN interface, or a fake in tests. */
interface TunDevice : Closeable {
    val input: InputStream
    val output: OutputStream
}

fun interface TunFactory {
    fun establish(ip: IpConfig, config: TunnelConfig, sessionName: String): TunDevice
}

/** Where one-time codes come from during one login: the inbox, the keyboard, or both. */
interface OtpSession : Closeable {
    val watchingEmail: Boolean
    val emailIssue: ErrorCode?

    /** How long [awaitCode] waits before giving up. */
    val timeout: Duration

    /** The next code, or null on timeout. */
    suspend fun awaitCode(): String?
}

fun interface OtpSessionFactory {
    /** Opened before login so only emails that arrive afterwards count. */
    suspend fun open(source: EmailOtpSource?, emailPassword: String?): OtpSession
}
