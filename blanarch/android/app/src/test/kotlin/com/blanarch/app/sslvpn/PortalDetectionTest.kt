package com.blanarch.app.sslvpn

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Spec §3.7: is there an SSL-VPN login page at /remote/login? */
class PortalDetectionTest {
    private fun reply(status: Int, body: String) =
        HttpResponseReader.read("HTTP/1.1 $status X\r\nContent-Length: ${body.length}\r\n\r\n$body".byteInputStream())

    @Test fun `the user's gateway login page counts as a portal`() {
        assertTrue(SslVpnProber.hasSslVpnPortal(reply(200, "<title>SSL VPN Remote Access Web Portal</title>")))
        assertTrue(SslVpnProber.hasSslVpnPortal(reply(200, "<form action=\"/remote/logincheck\">")))
    }

    @Test fun `a missing page or some other site does not`() {
        assertFalse(SslVpnProber.hasSslVpnPortal(reply(404, "Not Found")))
        assertFalse(SslVpnProber.hasSslVpnPortal(reply(200, "<title>Admin login</title>")))
    }

    @Test fun `the login page redirect is followed only within the same gateway`() {
        fun redirect(location: String) = HttpResponseReader.read(
            "HTTP/1.1 303 See Other\r\nLocation: $location\r\nContent-Length: 0\r\n\r\n".byteInputStream()
        )
        assertEquals("/remote/login?lang=en", SslVpnProber.sameGatewayRedirect(redirect("/remote/login?lang=en")))
        assertEquals(null, SslVpnProber.sameGatewayRedirect(redirect("https://evil.example/login")))
        assertEquals(null, SslVpnProber.sameGatewayRedirect(redirect("//evil.example/login")))
        assertEquals(null, SslVpnProber.sameGatewayRedirect(reply(200, "ok")))
    }
}
