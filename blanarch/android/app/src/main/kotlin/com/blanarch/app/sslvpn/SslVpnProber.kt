package com.blanarch.app.sslvpn

import com.blanarch.app.net.SocketFactory
import com.blanarch.app.net.cancellableIo
import com.blanarch.app.net.closeQuietly
import com.blanarch.app.security.sha256Hex
import com.blanarch.app.state.ErrorCode
import com.blanarch.app.state.VpnException
import com.blanarch.app.vpn.GatewayProbe
import com.blanarch.app.vpn.GatewayProber
import java.io.BufferedInputStream
import java.io.IOException
import java.net.Socket
import java.security.KeyStore
import java.security.Principal
import java.security.PrivateKey
import java.security.cert.X509Certificate
import javax.net.ssl.HttpsURLConnection
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLEngine
import javax.net.ssl.TrustManagerFactory
import javax.net.ssl.X509ExtendedKeyManager
import javax.net.ssl.X509TrustManager
import kotlinx.coroutines.CancellationException

/**
 * Learns what a gateway offers before the first sign-in (spec §3.7): the leaf
 * certificate digest, whether the system trusts it for this host, and whether
 * the login page offers SSO. Any certificate is accepted here; the caller decides.
 */
class SslVpnProber(private val sockets: SocketFactory) : GatewayProber {
    override suspend fun probe(host: String, port: Int): GatewayProbe {
        val capture = CapturingTrustManager()
        val clientCert = RecordingKeyManager()
        val context = SSLContext.getInstance("TLS").apply { init(arrayOf(clientCert), arrayOf(capture), null) }
        val s = try {
            sockets.tls(host, port, context)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            throw VpnException(ErrorCode.GATEWAY_UNREACHABLE, e.message ?: e.javaClass.simpleName, e)
        }
        try {
            val digest = capture.leafDigest ?: throw VpnException(ErrorCode.PROTOCOL, "no server certificate")
            val trusted =
                capture.chainTrusted && HttpsURLConnection.getDefaultHostnameVerifier().verify(host, s.session)
            var response = fetch(s, "/remote/login", host, port)
            // The login page may sit behind a redirect on the same gateway (spec §3.7).
            repeat(MAX_REDIRECTS) {
                val next = sameGatewayRedirect(response) ?: return@repeat
                val again = sockets.tls(host, port, context)
                try {
                    response = fetch(again, next, host, port)
                } finally {
                    again.closeQuietly()
                }
            }
            return GatewayProbe(
                certSha256 = digest,
                trustedBySystem = trusted,
                samlOffered = offersSaml(response.bodyText),
                sslVpnPortal = hasSslVpnPortal(response),
                clientCertRequested = clientCert.requested
            )
        } catch (e: IOException) {
            throw VpnException(ErrorCode.GATEWAY_UNREACHABLE, e.javaClass.simpleName, e)
        } finally {
            s.closeQuietly()
        }
    }

    private suspend fun fetch(s: java.net.Socket, path: String, host: String, port: Int): HttpResponse =
        s.cancellableIo {
            s.outputStream.write(HttpRequests.build("GET", path, host, port))
            s.outputStream.flush()
            HttpResponseReader.read(BufferedInputStream(s.inputStream))
        }

    companion object {
        private const val MAX_REDIRECTS = 2

        /** A redirect to a path on the same gateway, or null (spec §3.7). */
        fun sameGatewayRedirect(response: HttpResponse): String? {
            if (response.status !in 300..399) return null
            val location = response.header("Location")?.trim() ?: return null
            return location.takeIf { it.startsWith("/") && !it.startsWith("//") }
        }

        fun offersSaml(loginPage: String): Boolean = loginPage.contains("/remote/saml/start")

        /** Spec §3.7: a 200 page that mentions logincheck or "SSL VPN". */
        fun hasSslVpnPortal(response: HttpResponse): Boolean {
            if (response.status != 200) return false
            val page = response.bodyText
            return page.contains("logincheck", ignoreCase = true) || page.contains("SSL VPN", ignoreCase = true)
        }
    }

    /** Never offers a certificate; only notes that the server asked for one. */
    private class RecordingKeyManager : X509ExtendedKeyManager() {
        @Volatile var requested = false

        override fun chooseClientAlias(
            keyType: Array<out String>?,
            issuers: Array<out Principal>?,
            socket: Socket?
        ): String? {
            requested = true
            return null
        }

        override fun chooseEngineClientAlias(
            keyType: Array<out String>?,
            issuers: Array<out Principal>?,
            engine: SSLEngine?
        ): String? {
            requested = true
            return null
        }

        override fun getClientAliases(keyType: String?, issuers: Array<out Principal>?): Array<String>? = null
        override fun getServerAliases(keyType: String?, issuers: Array<out Principal>?): Array<String>? = null
        override fun chooseServerAlias(keyType: String?, issuers: Array<out Principal>?, socket: Socket?): String? =
            null
        override fun getCertificateChain(alias: String?): Array<X509Certificate>? = null
        override fun getPrivateKey(alias: String?): PrivateKey? = null
    }

    /** Records the leaf digest and the system's verdict without ever failing the handshake. */
    private class CapturingTrustManager : X509TrustManager {
        private val system: X509TrustManager? = try {
            TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm())
                .apply { init(null as KeyStore?) }
                .trustManagers.filterIsInstance<X509TrustManager>().firstOrNull()
        } catch (_: Exception) {
            null
        }

        @Volatile var leafDigest: String? = null

        @Volatile var chainTrusted = false

        override fun checkClientTrusted(chain: Array<out X509Certificate>?, authType: String?) = Unit
        override fun getAcceptedIssuers(): Array<X509Certificate> = emptyArray()

        override fun checkServerTrusted(chain: Array<out X509Certificate>, authType: String) {
            leafDigest = chain.firstOrNull()?.encoded?.let(::sha256Hex)
            chainTrusted = try {
                system?.checkServerTrusted(chain, authType)
                system != null
            } catch (_: Exception) {
                false
            }
        }
    }
}
