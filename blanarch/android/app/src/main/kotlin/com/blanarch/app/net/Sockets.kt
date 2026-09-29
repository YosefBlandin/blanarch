package com.blanarch.app.net

import java.net.InetSocketAddress
import java.net.Socket
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLSocket
import javax.net.ssl.SSLSocketFactory
import kotlin.time.Duration

/** Keeps a socket out of our own tunnel (VpnService.protect). */
fun interface SocketProtector {
    fun protect(socket: Socket): Boolean
}

/** Opens TCP then TLS sockets, cancellably, with the VPN bypass applied first. */
class SocketFactory(
    private val protector: SocketProtector,
    private val connectTimeout: Duration,
    private val readTimeout: Duration
) {
    suspend fun tcp(host: String, port: Int): Socket {
        val s = Socket()
        protector.protect(s)
        s.cancellableIo { s.connect(InetSocketAddress(host, port), connectTimeout.inWholeMilliseconds.toInt()) }
        s.soTimeout = readTimeout.inWholeMilliseconds.toInt()
        return s
    }

    /** TLS over a fresh TCP socket. [context] null means normal CA validation. */
    suspend fun tls(host: String, port: Int, context: SSLContext? = null): SSLSocket {
        val raw = tcp(host, port)
        try {
            val factory = context?.socketFactory ?: (SSLSocketFactory.getDefault() as SSLSocketFactory)
            val s = factory.createSocket(raw, host, port, true) as SSLSocket
            s.cancellableIo { s.startHandshake() }
            return s
        } catch (e: Exception) {
            raw.closeQuietly()
            throw e
        }
    }
}
