package com.blanarch.app.vpn

import com.blanarch.app.config.VpnConfig
import com.blanarch.app.profile.AuthMode
import com.blanarch.app.profile.Profile
import com.blanarch.app.profile.SecondFactorPreference
import com.blanarch.app.sso.SsoCallback
import com.blanarch.app.state.ErrorCode
import com.blanarch.app.state.LogEvent
import com.blanarch.app.state.LogLevel
import com.blanarch.app.state.SignInMethod
import com.blanarch.app.state.StatusStore
import com.blanarch.app.state.VpnException
import com.blanarch.app.state.VpnPhase
import com.blanarch.app.state.VpnStatus
import com.blanarch.app.state.maskCode
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.selects.select
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull

data class Credentials(val vpnPassword: String?, val emailPassword: String?)

/**
 * The connection sequence: sign in (password with code or push, or single
 * sign-on), open the tunnel, and keep cycling through the profile's gateways
 * until it connects. After a drop it rejoins with the same session cookie
 * before signing in again.
 *
 * Network aware: while the phone is offline it waits ([VpnPhase.WAITING_NETWORK])
 * without using up attempts; when the phone switches networks it rejoins at once
 * instead of waiting for keepalives to time out; when a rejoin is refused the
 * session has expired, so it signs in again with the saved credentials.
 *
 * Cancel the calling coroutine to disconnect. Every dependency is injected,
 * so each branch is unit-tested with fakes.
 */
class ConnectionOrchestrator(
    private val config: VpnConfig,
    private val gateways: GatewayFactory,
    private val otp: OtpSessionFactory,
    private val tun: TunFactory,
    private val sso: SsoCallback,
    private val status: StatusStore,
    private val network: NetworkWatch = AlwaysOnline,
    /** How often traffic and latency are refreshed while connected; null turns it off (tests). */
    private val statsInterval: Duration? = 1.seconds,
    private val clock: () -> Long = System::currentTimeMillis
) {
    private val retry = config.retry

    suspend fun run(profile: Profile, credentials: Credentials) {
        status.update {
            it.copy(
                phase = VpnPhase.CONNECTING, connectionId = profile.id, host = null, attempt = 0,
                maxAttempts = retry.maxAttempts, ip = null, otpMasked = null, connectedSinceMillis = null,
                emailWatching = false, emailIssue = null, error = null, errorDetail = null, ssoUrl = null,
                deadlineMillis = null, startedMillis = clock(), retryReason = null
            ).clearedDetails(profile.port)
        }
        status.log("Starting ${profile.name}", event = LogEvent.STARTING, args = listOf(profile.name))
        if (profile.authMode == AuthMode.PASSWORD && credentials.vpnPassword == null) {
            return fail(VpnException(ErrorCode.NO_VPN_PASSWORD))
        }

        var attempt = 0
        var hostIndex = 0
        var gateway: VpnGateway? = null
        val certRefused = mutableSetOf<String>()
        var lastCertError: VpnException? = null
        try {
            while (attempt < retry.maxAttempts) {
                awaitNetwork()
                attempt++
                val host = profile.hosts[hostIndex % profile.hosts.size]
                status.update {
                    it.copy(
                        phase = VpnPhase.CONNECTING,
                        attempt = attempt,
                        host = host,
                        triedHosts = if (host in it.triedHosts) it.triedHosts else it.triedHosts + host,
                        otpMasked = null,
                        ssoUrl = null,
                        deadlineMillis = null
                    )
                }
                status.log(
                    "Attempt $attempt of ${retry.maxAttempts} · $host:${profile.port}",
                    event = LogEvent.ATTEMPT,
                    args = listOf("$attempt", "${retry.maxAttempts}", "$host:${profile.port}")
                )
                gateway?.close()
                val gw = gateways.create(host, profile.port).also { gateway = it }
                try {
                    authenticate(gw, profile, credentials)
                    var reuses = 0
                    var rejoining = false
                    while (true) {
                        val end = try {
                            runTunnel(gw, profile, reuses)
                        } catch (e: VpnException) {
                            // A refused rejoin means the gateway dropped the session: sign in again.
                            if (!rejoining || e.code !in SESSION_GONE) throw e
                            sessionExpired(e)
                            awaitNetwork()
                            authenticate(gw, profile, credentials)
                            reuses = 0
                            rejoining = false
                            continue
                        }
                        rejoining = true
                        attempt = 0 // it was up, so count afresh
                        // Network moves don't use up rejoins: the session is still good.
                        if (end.code == ErrorCode.LINK_LOST && reuses++ >= retry.maxCookieReuses) {
                            throw VpnException(ErrorCode.LINK_LOST, end.detail)
                        }
                        status.update {
                            it.copy(
                                phase = VpnPhase.RECONNECTING,
                                ip = null,
                                connectedSinceMillis = null,
                                startedMillis = clock(),
                                retryReason = end.code
                            )
                        }
                        when (end.code) {
                            ErrorCode.NETWORK_CHANGED ->
                                status.log("Network changed. Rejoining", LogLevel.INFO, LogEvent.NETWORK_CHANGED)
                            ErrorCode.NO_NETWORK -> awaitNetwork()
                            else -> {
                                status.log(
                                    "Connection lost (${end.detail}). Reconnecting",
                                    LogLevel.ERROR,
                                    LogEvent.CONNECTION_LOST
                                )
                                delay(retry.delayBetween)
                            }
                        }
                    }
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    val error = e as? VpnException ?: VpnException(ErrorCode.GATEWAY_UNREACHABLE, e.message, e)
                    if (network.current.value == null && !error.code.fatal) {
                        // Failed because the phone went offline: not the gateway's fault, try again once back.
                        attempt--
                        continue
                    }
                    if (error.code in CERT_ERRORS && profile.hosts.size > 1) {
                        // Never use that address, but a backup with a trusted certificate may still work.
                        certRefused += host
                        lastCertError = error
                        if (certRefused.size < profile.hosts.size) {
                            logFailure(error, host, " · skipping $host")
                            status.update { it.copy(retryReason = error.code) }
                            hostIndex++
                            continue
                        }
                    }
                    if (error.code.fatal) return fail(error)
                    logFailure(error, host)
                    status.update { it.copy(retryReason = error.code) }
                    hostIndex++
                    delay(retry.delayBetween)
                }
            }
            // A certificate problem is more useful to show than "out of attempts": the user can act on it.
            fail(lastCertError ?: VpnException(ErrorCode.OUT_OF_ATTEMPTS))
        } finally {
            withContext(NonCancellable) {
                gateway?.let { gw ->
                    withTimeoutOrNull(LOGOUT_TIMEOUT) { gw.logout() }
                    gw.close()
                }
            }
        }
    }

    /** Returns at once when online; otherwise shows WAITING_NETWORK until a network is back. */
    private suspend fun awaitNetwork() {
        if (network.current.value != null) return
        status.update { it.copy(phase = VpnPhase.WAITING_NETWORK, retryReason = ErrorCode.NO_NETWORK, ip = null) }
        status.log("No network. Waiting", LogLevel.ERROR, LogEvent.NETWORK_LOST)
        network.current.first { it != null }
        status.log("Network back", LogLevel.INFO, LogEvent.NETWORK_BACK)
    }

    private fun sessionExpired(cause: VpnException) {
        status.update {
            it.copy(
                phase = VpnPhase.RECONNECTING,
                retryReason = ErrorCode.SESSION_EXPIRED,
                ip = null,
                connectedSinceMillis = null
            )
        }
        status.log(
            "Session expired (${describe(cause)}). Signing in again",
            LogLevel.ERROR,
            LogEvent.SESSION_EXPIRED
        )
    }

    private suspend fun authenticate(gw: VpnGateway, profile: Profile, credentials: Credentials) {
        when (profile.authMode) {
            AuthMode.SSO -> {
                status.update { it.copy(signIn = SignInMethod.SSO) }
                signInWithSso(gw)
            }
            AuthMode.PASSWORD -> signInWithPassword(gw, profile, credentials)
        }
        status.update { it.copy(emailWatching = false, ssoUrl = null, deadlineMillis = null) }
        status.log("Signed in", LogLevel.OK, LogEvent.SIGNED_IN)
    }

    private suspend fun signInWithSso(gw: VpnGateway) {
        val port = config.sso.listenPort
        val url = gw.samlStartUrl(port)
        val deadline = clock() + config.sso.timeout.inWholeMilliseconds
        status.update { it.copy(phase = VpnPhase.WAITING_SSO, ssoUrl = url, deadlineMillis = deadline) }
        status.log("Waiting for sign-in in the browser", event = LogEvent.WAITING_SSO)
        val id = withTimeoutOrNull(config.sso.timeout) { sso.awaitId(port) }
            ?: throw VpnException(ErrorCode.SSO_TIMEOUT)
        status.update { it.copy(phase = VpnPhase.AUTHENTICATING, ssoUrl = null, deadlineMillis = null) }
        gw.loginWithSamlId(id)
    }

    private suspend fun signInWithPassword(gw: VpnGateway, profile: Profile, credentials: Credentials) {
        status.update { it.copy(phase = VpnPhase.AUTHENTICATING) }
        status.log("Signing in as ${profile.username}", event = LogEvent.SIGNING_IN, args = listOf(profile.username))
        otp.open(profile.emailOtp, credentials.emailPassword).use { session ->
            status.update { it.copy(emailWatching = session.watchingEmail, emailIssue = session.emailIssue) }
            gw.login(profile.username, credentials.vpnPassword!!) { pushOffered ->
                if (pushOffered && profile.secondFactor == SecondFactorPreference.AUTO) {
                    status.update { it.copy(phase = VpnPhase.WAITING_PUSH, deadlineMillis = null) }
                    status.log("Approve the sign-in on your phone", event = LogEvent.APPROVE_PUSH)
                    status.update { it.copy(signIn = SignInMethod.PUSH) }
                    return@login SecondFactor.Push
                }
                status.update {
                    it.copy(
                        phase = VpnPhase.WAITING_OTP,
                        deadlineMillis = clock() + session.timeout.inWholeMilliseconds
                    )
                }
                val code = session.awaitCode() ?: throw VpnException(ErrorCode.OTP_TIMEOUT)
                status.update {
                    it.copy(phase = VpnPhase.AUTHENTICATING, otpMasked = maskCode(code), deadlineMillis = null)
                }
                status.log(
                    "Got code ${maskCode(code)}. Verifying",
                    event = LogEvent.CODE_RECEIVED,
                    args = listOf(maskCode(code))
                )
                status.update { it.copy(signIn = SignInMethod.CODE) }
                SecondFactor.Code(code)
            }
        }
    }

    /** Brings the tunnel up and suspends until it drops; returns why. */
    /** Why a tunnel that was up ended: a lost link (with the reason), or a network change. */
    private data class TunnelEnd(val code: ErrorCode, val detail: String)

    private suspend fun runTunnel(gw: VpnGateway, profile: Profile, reconnects: Int): TunnelEnd {
        status.update { it.copy(phase = VpnPhase.NEGOTIATING) }
        val tunnelConfig = gw.fetchTunnelConfig()
        gw.openLink().use { link ->
            val negotiated = link.negotiate(retry.attemptTimeout)
            val fullTunnel = Routes.isFullTunnel(tunnelConfig)
            val dnsChoice = Routes.dnsFor(negotiated.dns, tunnelConfig.dns, config.fallbackDns, fullTunnel)
            if (fullTunnel && dnsChoice.servers.isEmpty()) {
                throw VpnException(ErrorCode.PROTOCOL, "no DNS server for a full tunnel")
            }
            if (dnsChoice.fallback) {
                val servers = dnsChoice.servers.joinToString(", ")
                status.log(
                    "The gateway gave no DNS server. Using $servers through the tunnel",
                    event = LogEvent.DNS_FALLBACK,
                    args = listOf(servers)
                )
            }
            val ip = negotiated.copy(dns = dnsChoice.servers)
            tun.establish(ip, tunnelConfig, profile.name).use { device ->
                val dns = ip.dns
                val routes = Routes.plan(tunnelConfig, emptyList()).filterNot { it.prefix == 0 }
                status.update {
                    it.copy(
                        phase = VpnPhase.CONNECTED,
                        ip = ip.ip,
                        connectedSinceMillis = clock(),
                        startedMillis = null,
                        retryReason = null,
                        dns = dns,
                        dnsSuffix = tunnelConfig.dnsSuffix,
                        routes = routes.map { r -> "${r.address}/${r.prefix}" },
                        mtu = config.mru,
                        tls = gw.tlsDescription,
                        signIn = it.signIn ?: SignInMethod.PASSWORD,
                        reconnects = reconnects,
                        bytesIn = 0,
                        bytesOut = 0,
                        latencyMillis = null
                    )
                }
                val scope = if (tunnelConfig.routes.isEmpty()) "all traffic" else "${tunnelConfig.routes.size} routes"
                status.log(
                    "Connected to ${profile.name} · IP ${ip.ip} · $scope",
                    LogLevel.OK,
                    LogEvent.CONNECTED,
                    listOf(ip.ip)
                )
                return coroutineScope {
                    // Traffic and latency for the connected screen, once a second.
                    val stats = statsInterval?.let { every ->
                        launch {
                            while (true) {
                                delay(every)
                                val st = link.stats
                                status.update {
                                    it.copy(bytesIn = st.bytesIn, bytesOut = st.bytesOut, latencyMillis = st.rttMillis)
                                }
                            }
                        }
                    }
                    // Whichever comes first ends this tunnel: the link dropping, or the phone's network changing.
                    val startNetwork = network.current.value
                    val pump = async { TunnelEnd(ErrorCode.LINK_LOST, link.pump(device)) }
                    val moved = async {
                        val now = network.current.first { it != startNetwork }
                        if (now ==
                            null
                        ) {
                            TunnelEnd(ErrorCode.NO_NETWORK, "no network")
                        } else {
                            TunnelEnd(ErrorCode.NETWORK_CHANGED, "network changed")
                        }
                    }
                    try {
                        select {
                            pump.onAwait { it }
                            moved.onAwait { it }
                        }
                    } finally {
                        stats?.cancel()
                        pump.cancel()
                        moved.cancel()
                    }
                }
            }
        }
    }

    private fun logFailure(error: VpnException, host: String, suffix: String = "") =
        status.log(describe(error) + suffix, LogLevel.ERROR, LogEvent.FAILED, listOf(error.code.name, host))

    private fun fail(error: VpnException) {
        logFailure(error, "")
        status.update {
            it.copy(
                phase = VpnPhase.ERROR,
                error = error.code,
                errorDetail = error.detail,
                ip = null,
                connectedSinceMillis = null,
                emailWatching = false,
                ssoUrl = null,
                deadlineMillis = null,
                startedMillis = null,
                retryReason = null
            )
        }
    }

    private fun describe(e: VpnException) =
        e.code.name.lowercase().replace('_', ' ') + (e.detail?.let { " ($it)" } ?: "")

    private companion object {
        val LOGOUT_TIMEOUT = 5.seconds
        val CERT_ERRORS = setOf(ErrorCode.CERT_MISMATCH, ErrorCode.CERT_UNTRUSTED)

        /** A rejoin failing like this means the session is gone (spec §3.5, confirm by trace). */
        val SESSION_GONE = setOf(ErrorCode.TUNNEL_REFUSED, ErrorCode.PROTOCOL)
    }
}

/** A fresh run starts with no details from the last one. */
private fun VpnStatus.clearedDetails(port: Int) = copy(
    port = port,
    bytesIn = 0,
    bytesOut = 0,
    latencyMillis = null,
    dns = emptyList(),
    dnsSuffix = null,
    routes = emptyList(),
    mtu = null,
    tls = null,
    signIn = null,
    reconnects = 0,
    triedHosts = emptyList()
)
