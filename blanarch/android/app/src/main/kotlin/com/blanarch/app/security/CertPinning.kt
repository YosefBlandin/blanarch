package com.blanarch.app.security

import java.security.KeyStore
import java.security.MessageDigest
import java.security.cert.CertificateException
import java.security.cert.X509Certificate
import javax.net.ssl.SSLContext
import javax.net.ssl.TrustManagerFactory
import javax.net.ssl.X509TrustManager

fun sha256Hex(bytes: ByteArray): String =
    MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }

/** The gateway presented a different certificate from the one the user trusted. */
class PinMismatchException(host: String) : CertificateException("certificate for $host does not match its pin")

/** No pin yet and the system doesn't trust the certificate: the user must decide first. */
class UntrustedCertificateException(host: String, val digest: String) :
    CertificateException("certificate for $host is not trusted")

/**
 * Trust rules for a gateway (spec §2):
 * - pinned host: accept exactly the pinned SHA-256 (DER) digest, nothing else;
 * - no pin: accept only what the system trust store accepts.
 * Nothing is trusted silently; pins are saved by the setup flow after the user agrees.
 */
class PinningTrustManager(
    private val host: String,
    private val pins: PinStore,
    private val system: X509TrustManager? = defaultTrustManager()
) : X509TrustManager {
    override fun checkClientTrusted(chain: Array<out X509Certificate>?, authType: String?) = Unit
    override fun getAcceptedIssuers(): Array<X509Certificate> = emptyArray()

    override fun checkServerTrusted(chain: Array<out X509Certificate>, authType: String?) {
        val digest = sha256Hex(chain[0].encoded)
        val pinned = pins.pin(host)
        if (pinned != null) {
            if (!pinned.equals(digest, ignoreCase = true)) throw PinMismatchException(host)
            return
        }
        try {
            system?.checkServerTrusted(chain, authType) ?: throw CertificateException("no system trust")
        } catch (e: CertificateException) {
            throw UntrustedCertificateException(host, digest).apply { initCause(e) }
        }
    }

    fun sslContext(): SSLContext = SSLContext.getInstance("TLS").apply {
        init(null, arrayOf(this@PinningTrustManager), null)
    }

    companion object {
        fun defaultTrustManager(): X509TrustManager? = runCatching {
            TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm())
                .apply { init(null as KeyStore?) }
                .trustManagers.filterIsInstance<X509TrustManager>().firstOrNull()
        }.getOrNull()
    }
}

fun Throwable.isPinMismatch(): Boolean = generateSequence(this) { it.cause }.any { it is PinMismatchException }

fun Throwable.untrustedCertificate(): UntrustedCertificateException? =
    generateSequence(this) { it.cause }.filterIsInstance<UntrustedCertificateException>().firstOrNull()
