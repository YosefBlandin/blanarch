package com.blanarch.app.sslvpn

import com.blanarch.app.state.ErrorCode
import com.blanarch.app.state.VpnException
import java.io.ByteArrayInputStream
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Test

class HttpTest {
    private fun read(raw: String) = HttpResponseReader.read(ByteArrayInputStream(raw.toByteArray()))

    @Test
    fun `reads a content-length body and cookies`() {
        val r = read(
            "HTTP/1.1 200 OK\r\nSet-Cookie: other=1\r\nSet-Cookie: SVPNCOOKIE=xyz; path=/\r\n" +
                "Content-Length: 5\r\n\r\nret=1trailing"
        )
        assertEquals(200, r.status)
        assertEquals("ret=1", r.bodyText)
        assertEquals("xyz", r.sessionCookie)
    }

    @Test
    fun `reads a chunked body`() {
        val r = read("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n4\r\nret=\r\n1\r\n2\r\n0\r\n\r\n")
        assertEquals("ret=2", r.bodyText)
    }

    @Test
    fun `reads a close-delimited body`() {
        val r = read("HTTP/1.1 403 Forbidden\r\nConnection: close\r\n\r\n<html>no</html>")
        assertEquals(403, r.status)
        assertEquals("<html>no</html>", r.bodyText)
    }

    @Test
    fun `empty cookie value is no cookie`() {
        assertNull(
            read("HTTP/1.1 200 OK\r\nSet-Cookie: SVPNCOOKIE=; path=/\r\nContent-Length: 0\r\n\r\n").sessionCookie
        )
    }

    @Test
    fun `garbage status line is a protocol error`() {
        val e = assertThrows(VpnException::class.java) { read("hello\r\n\r\n") }
        assertEquals(ErrorCode.PROTOCOL, e.code)
    }

    @Test
    fun `builds a post with the spec headers`() {
        val req = String(HttpRequests.build("POST", "/remote/logincheck", "gw", 10443, "c1", "a=1"))
        assertEquals(
            "POST /remote/logincheck HTTP/1.1\r\nHost: gw:10443\r\nUser-Agent: Mozilla/5.0 SV1\r\nAccept: */*\r\n" +
                "Content-Type: application/x-www-form-urlencoded\r\nCookie: SVPNCOOKIE=c1\r\nConnection: close\r\n" +
                "Content-Length: 3\r\n\r\na=1",
            req
        )
    }

    @Test
    fun `builds the tunnel request exactly`() {
        assertEquals(
            "GET /remote/sslvpn-tunnel HTTP/1.1\r\nHost: sslvpn\r\nCookie: SVPNCOOKIE=abc\r\n\r\n",
            String(HttpRequests.tunnel("abc"))
        )
    }
}
