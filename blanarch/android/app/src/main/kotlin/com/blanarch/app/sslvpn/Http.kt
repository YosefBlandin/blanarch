package com.blanarch.app.sslvpn

import com.blanarch.app.net.readAsciiLine
import com.blanarch.app.state.ErrorCode
import com.blanarch.app.state.VpnException
import java.io.ByteArrayOutputStream
import java.io.InputStream

/** A parsed HTTP/1.1 response (spec §3). Header names are kept as sent; lookups ignore case. */
class HttpResponse(val status: Int, val headers: List<Pair<String, String>>, val body: ByteArray) {
    fun headerValues(name: String): List<String> = headers.filter { it.first.equals(name, ignoreCase = true) }
        .map { it.second }

    fun header(name: String): String? = headerValues(name).firstOrNull()

    val bodyText: String get() = String(body, Charsets.UTF_8)

    /** The SVPNCOOKIE value from Set-Cookie, or null when missing or empty (spec §3.2). */
    val sessionCookie: String? get() = headerValues("Set-Cookie").firstNotNullOfOrNull(::svpnCookieIn)

    companion object {
        const val COOKIE_NAME = "SVPNCOOKIE"

        fun svpnCookieIn(setCookie: String): String? {
            val first = setCookie.substringBefore(';').trim()
            val name = first.substringBefore('=', "").trim()
            if (name != COOKIE_NAME) return null
            return first.substringAfter('=').trim().takeIf { it.isNotEmpty() }
        }
    }
}

/** Builds the request bytes described in spec §3. Pure, so it can be tested without a socket. */
object HttpRequests {
    const val USER_AGENT = "Mozilla/5.0 SV1"

    fun build(
        method: String,
        path: String,
        host: String,
        port: Int,
        cookie: String? = null,
        body: String? = null
    ): ByteArray {
        val sb = StringBuilder()
        sb.append(method).append(' ').append(path).append(" HTTP/1.1\r\n")
        sb.append("Host: ").append(host).append(':').append(port).append("\r\n")
        sb.append("User-Agent: ").append(USER_AGENT).append("\r\n")
        sb.append("Accept: */*\r\n")
        sb.append("Content-Type: application/x-www-form-urlencoded\r\n")
        if (cookie !=
            null
        ) {
            sb.append("Cookie: ").append(HttpResponse.COOKIE_NAME).append('=').append(cookie).append("\r\n")
        }
        sb.append("Connection: close\r\n")
        val bodyBytes = body?.toByteArray(Charsets.UTF_8)
        if (bodyBytes != null) sb.append("Content-Length: ").append(bodyBytes.size).append("\r\n")
        sb.append("\r\n")
        val head = sb.toString().toByteArray(Charsets.ISO_8859_1)
        return if (bodyBytes == null) head else head + bodyBytes
    }

    /** The one request that switches a fresh connection to tunnel mode (spec §5). */
    fun tunnel(cookie: String): ByteArray = (
        "GET /remote/sslvpn-tunnel HTTP/1.1\r\n" +
            "Host: sslvpn\r\n" +
            "Cookie: ${HttpResponse.COOKIE_NAME}=$cookie\r\n" +
            "\r\n"
        ).toByteArray(Charsets.ISO_8859_1)
}

/** Reads one HTTP/1.1 response: Content-Length, chunked, or close-delimited bodies. */
object HttpResponseReader {
    const val MAX_BODY = 4 * 1024 * 1024

    fun read(input: InputStream): HttpResponse {
        val statusLine = input.readAsciiLine() ?: throw protocol("empty HTTP response")
        val parts = statusLine.split(' ', limit = 3)
        if (parts.size < 2 || !parts[0].startsWith("HTTP/")) throw protocol("bad HTTP status line")
        val status = parts[1].toIntOrNull() ?: throw protocol("bad HTTP status line")
        val headers = mutableListOf<Pair<String, String>>()
        while (true) {
            val line = input.readAsciiLine() ?: break
            if (line.isEmpty()) break
            val colon = line.indexOf(':')
            if (colon <= 0) continue
            headers += line.substring(0, colon).trim() to line.substring(colon + 1).trim()
        }
        val response = HttpResponse(status, headers, ByteArray(0))
        val chunked = response.headerValues("Transfer-Encoding").any { it.contains("chunked", ignoreCase = true) }
        val length = response.header("Content-Length")?.toLongOrNull()
        val body = when {
            status in 100..199 || status == 204 || status == 304 -> ByteArray(0)
            chunked -> readChunked(input)
            length != null -> readExactly(input, length)
            else -> readToEnd(input)
        }
        return HttpResponse(status, headers, body)
    }

    private fun readExactly(input: InputStream, length: Long): ByteArray {
        if (length < 0 || length > MAX_BODY) throw protocol("HTTP body too large")
        val out = ByteArrayOutputStream(length.toInt())
        copy(input, out, length.toInt())
        if (out.size() < length) throw protocol("HTTP body truncated")
        return out.toByteArray()
    }

    private fun readChunked(input: InputStream): ByteArray {
        val out = ByteArrayOutputStream()
        while (true) {
            val sizeLine = input.readAsciiLine() ?: throw protocol("HTTP chunk truncated")
            val size = sizeLine.substringBefore(';').trim().toIntOrNull(16) ?: throw protocol("bad HTTP chunk size")
            if (size == 0) {
                // Trailers, then the empty line that ends the message.
                while (true) {
                    val line = input.readAsciiLine() ?: break
                    if (line.isEmpty()) break
                }
                return out.toByteArray()
            }
            if (out.size() + size > MAX_BODY) throw protocol("HTTP body too large")
            val before = out.size()
            copy(input, out, size)
            if (out.size() - before < size) throw protocol("HTTP chunk truncated")
            input.readAsciiLine() // CRLF after the chunk data
        }
    }

    private fun readToEnd(input: InputStream): ByteArray {
        val out = ByteArrayOutputStream()
        copy(input, out, MAX_BODY)
        return out.toByteArray()
    }

    private fun copy(input: InputStream, out: ByteArrayOutputStream, max: Int) {
        val buf = ByteArray(8192)
        var left = max
        while (left > 0) {
            val n = input.read(buf, 0, minOf(buf.size, left))
            if (n < 0) return
            out.write(buf, 0, n)
            left -= n
        }
    }

    private fun protocol(detail: String) = VpnException(ErrorCode.PROTOCOL, detail)
}
