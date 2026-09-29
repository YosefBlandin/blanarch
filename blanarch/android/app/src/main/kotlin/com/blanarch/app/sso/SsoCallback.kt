package com.blanarch.app.sso

import com.blanarch.app.net.cancellableIo
import com.blanarch.app.net.readAsciiLine
import com.blanarch.app.state.ErrorCode
import com.blanarch.app.state.VpnException
import java.net.BindException
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.URLDecoder

/** Waits for the browser's redirect to `http://127.0.0.1:<port>/?id=<session>` (spec §3.4). */
fun interface SsoCallback {
    /** Suspends until the browser delivers the id. Cancel to stop listening. */
    suspend fun awaitId(port: Int): String
}

/** Pure parsing of the redirect request line. */
object SsoRedirect {
    /** `GET /?id=abc&x=1 HTTP/1.1` → `abc`; null if there is no id. */
    fun idFrom(requestLine: String): String? {
        val target = requestLine.split(' ').getOrNull(1) ?: return null
        val query = target.substringAfter('?', "")
        return query.split('&').firstNotNullOfOrNull { pair ->
            val (k, v) = pair.split('=', limit = 2).let { it[0] to it.getOrElse(1) { "" } }
            if (k == "id" && v.isNotEmpty()) URLDecoder.decode(v, "UTF-8") else null
        }
    }

    fun page(title: String, body: String): ByteArray {
        val html = "<!doctype html><meta name=viewport content='width=device-width'>" +
            "<body style='font-family:sans-serif;background:#F3ECE1;color:#2A241E;padding:48px 24px'>" +
            "<h2>$title</h2><p>$body</p></body>"
        val bytes = html.toByteArray(Charsets.UTF_8)
        return (
            "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\n" +
                "Content-Length: ${bytes.size}\r\nConnection: close\r\n\r\n"
            ).toByteArray(Charsets.ISO_8859_1) + bytes
    }
}

/** Real listener on the loopback interface only. */
class LoopbackSsoCallback : SsoCallback {
    override suspend fun awaitId(port: Int): String {
        val server = try {
            ServerSocket().apply {
                reuseAddress = true
                bind(InetSocketAddress(InetAddress.getByName("127.0.0.1"), port))
            }
        } catch (e: BindException) {
            throw VpnException(ErrorCode.SSO_FAILED, "port $port is busy", e)
        }
        return server.use { srv ->
            srv.cancellableIo {
                while (true) {
                    val client = srv.accept()
                    val id = client.use {
                        val line = it.getInputStream().readAsciiLine() ?: ""
                        val found = SsoRedirect.idFrom(line)
                        val reply = if (found != null) {
                            SsoRedirect.page("Signed in", "You can go back to the app now.")
                        } else {
                            SsoRedirect.page("Still waiting", "This page didn't include a sign-in result.")
                        }
                        it.getOutputStream().apply {
                            write(reply)
                            flush()
                        }
                        found
                    }
                    if (id != null) return@cancellableIo id
                }
                @Suppress("UNREACHABLE_CODE")
                error("unreachable")
            }
        }
    }
}
