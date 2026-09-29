package com.blanarch.app.sslvpn

import com.blanarch.app.net.SocketFactory
import com.blanarch.app.net.cancellableIo
import com.blanarch.app.net.closeQuietly
import com.blanarch.app.security.PinStore
import com.blanarch.app.security.PinningTrustManager
import com.blanarch.app.security.isPinMismatch
import com.blanarch.app.security.untrustedCertificate
import com.blanarch.app.state.ErrorCode
import com.blanarch.app.state.VpnException
import com.blanarch.app.vpn.PacketLink
import com.blanarch.app.vpn.SecondFactor
import com.blanarch.app.vpn.SecondFactorProvider
import com.blanarch.app.vpn.TunnelConfig
import com.blanarch.app.vpn.VpnGateway
import java.io.BufferedInputStream
import java.io.IOException
import java.net.Socket
import java.net.SocketTimeoutException
import java.util.concurrent.ConcurrentHashMap
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLSocket
import kotlinx.coroutines.CancellationException

/**
 * One FortiGate SSL-VPN endpoint: HTTPS sign-in, tunnel settings and the
 * tunnel connection (spec §2 to §5). Each HTTP exchange uses its own TLS
 * connection. [close] closes every socket still open, including the tunnel.
 */
class SslVpnGateway(
    private val host: String,
    private val port: Int,
    private val realm: String,
    private val mru: Int,
    private val sockets: SocketFactory,
    private val pins: PinStore,
    private val log: (String) -> Unit
) : VpnGateway {
    private val openSockets: MutableSet<Socket> = ConcurrentHashMap.newKeySet()
    private val tls: SSLContext by lazy {
        PinningTrustManager(host, pins).sslContext()
    }

    @Volatile private var cookie: String? = null

    @Volatile private var tlsInfo: String? = null

    override val tlsDescription: String? get() = tlsInfo

    @Volatile private var closed = false

    override suspend fun login(username: String, password: String, secondFactor: SecondFactorProvider) {
        cookie = null // a new sign-in never carries the old session (spec §3.2)
        val step1 = post("/remote/logincheck", LoginProtocol.passwordBody(username, password, realm))
        when (val outcome = LoginProtocol.classifyStep1(step1)) {
            is LoginOutcome.LoggedIn -> cookie = outcome.cookie
            LoginOutcome.Rejected -> throw VpnException(ErrorCode.AUTH_REJECTED)
            LoginOutcome.UnsupportedChallenge -> throw VpnException(ErrorCode.UNSUPPORTED_CHALLENGE)
            is LoginOutcome.HttpError ->
                throw VpnException(ErrorCode.PROTOCOL, "sign-in returned HTTP ${outcome.status}")
            LoginOutcome.Unexpected ->
                throw VpnException(
                    ErrorCode.PROTOCOL,
                    "unexpected sign-in response: ${LoginProtocol.describeUnexpected(step1)}"
                )
            is LoginOutcome.NeedsToken -> cookie = secondStep(username, outcome, secondFactor)
        }
    }

    private suspend fun secondStep(
        username: String,
        challenge: LoginOutcome.NeedsToken,
        provider: SecondFactorProvider
    ): String {
        log(if (challenge.pushOffered) "Second factor needed (push available)" else "Second factor needed")
        val response = when (val answer = provider.provide(challenge.pushOffered)) {
            is SecondFactor.Code ->
                post("/remote/logincheck", LoginProtocol.codeBody(username, realm, challenge.fields, answer.code))
            SecondFactor.Push -> {
                log("Waiting for push approval")
                try {
                    post(
                        "/remote/logincheck",
                        LoginProtocol.pushBody(username, realm, challenge.fields),
                        readTimeoutMillis = PUSH_TIMEOUT_MILLIS
                    )
                } catch (e: VpnException) {
                    if (e.cause is SocketTimeoutException) throw VpnException(ErrorCode.OTP_TIMEOUT, "push", e)
                    throw e
                }
            }
        }
        return response.sessionCookie ?: throw VpnException(ErrorCode.OTP_REJECTED)
    }

    override fun samlStartUrl(listenPort: Int): String = LoginProtocol.samlStartUrl(host, port)

    override suspend fun loginWithSamlId(id: String) {
        val response = get(LoginProtocol.samlAuthPath(id), withCookie = false)
        response.sessionCookie?.let {
            cookie = it
            return
        }
        if (response.status != 200) {
            throw VpnException(ErrorCode.PROTOCOL, "SSO sign-in returned HTTP ${response.status}")
        }
        throw VpnException(ErrorCode.AUTH_REJECTED, "SSO sign-in not accepted")
    }

    override suspend fun fetchTunnelConfig(): TunnelConfig {
        requireCookie()
        get("/remote/index")
        get("/remote/fortisslvpn")
        val xml = get("/remote/fortisslvpn_xml")
        if (xml.status != 200) {
            throw VpnException(ErrorCode.TUNNEL_REFUSED, "no tunnel-mode access (HTTP ${xml.status})")
        }
        return TunnelXml.parse(xml.bodyText)
    }

    override suspend fun openLink(): PacketLink {
        val value = requireCookie()
        val s = connect()
        try {
            s.soTimeout = 0 // the link has its own keepalive
            s.cancellableIo {
                s.outputStream.write(HttpRequests.tunnel(value))
                s.outputStream.flush()
            }
        } catch (e: CancellationException) {
            forget(s)
            throw e
        } catch (e: IOException) {
            forget(s)
            throw VpnException(ErrorCode.GATEWAY_UNREACHABLE, e.javaClass.simpleName, e)
        }
        log("Tunnel connection open")
        return SslVpnLink(s, mru, log)
    }

    override suspend fun logout() {
        if (cookie == null) return
        try {
            get("/remote/logout")
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            // best effort
        } finally {
            cookie = null
        }
    }

    override fun close() {
        closed = true
        openSockets.forEach { it.closeQuietly() }
        openSockets.clear()
    }

    private fun requireCookie(): String = cookie ?: throw VpnException(ErrorCode.PROTOCOL, "not signed in")

    private suspend fun get(path: String, withCookie: Boolean = true): HttpResponse =
        exchange("GET", path, null, if (withCookie) cookie else null, null)

    private suspend fun post(path: String, body: String, readTimeoutMillis: Int? = null): HttpResponse =
        exchange("POST", path, body, cookie, readTimeoutMillis)

    private suspend fun exchange(
        method: String,
        path: String,
        body: String?,
        cookie: String?,
        readTimeoutMillis: Int?
    ): HttpResponse {
        val request = HttpRequests.build(method, path, host, port, cookie, body)
        val s = connect()
        try {
            readTimeoutMillis?.let { s.soTimeout = it }
            return s.cancellableIo {
                s.outputStream.write(request)
                s.outputStream.flush()
                HttpResponseReader.read(BufferedInputStream(s.inputStream))
            }
        } catch (e: IOException) {
            throw VpnException(
                ErrorCode.GATEWAY_UNREACHABLE,
                "${method.lowercase()} failed: ${e.javaClass.simpleName}",
                e
            )
        } finally {
            forget(s)
        }
    }

    /** TLS with the pin check of spec §2; failures become GATEWAY_UNREACHABLE or CERT_MISMATCH. */
    private suspend fun connect(): SSLSocket {
        if (closed) throw VpnException(ErrorCode.GATEWAY_UNREACHABLE, "gateway closed")
        val s = try {
            sockets.tls(host, port, tls)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            if (e.isPinMismatch()) throw VpnException(ErrorCode.CERT_MISMATCH, host, e)
            e.untrustedCertificate()?.let { throw VpnException(ErrorCode.CERT_UNTRUSTED, it.digest, e) }
            throw VpnException(ErrorCode.GATEWAY_UNREACHABLE, e.message ?: e.javaClass.simpleName, e)
        }
        openSockets.removeAll { it.isClosed }
        openSockets += s
        s.session?.let { tlsInfo = "${it.protocol} · ${it.cipherSuite}" }
        if (closed) {
            forget(s)
            throw VpnException(ErrorCode.GATEWAY_UNREACHABLE, "gateway closed")
        }
        return s
    }

    private fun forget(s: Socket) {
        openSockets -= s
        s.closeQuietly()
    }

    private companion object {
        const val PUSH_TIMEOUT_MILLIS = 90_000
    }
}
