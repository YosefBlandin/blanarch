package com.blanarch.app.sslvpn

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Shape of a real FortiGate step-1 reply (values replaced), as observed from our own client. */
class RealGatewayReplyTest {
    @Test fun `code challenge with an expired cookie and padded chunk size`() {
        val body = "ret=3,reqid=1234,polid=1-1-5,grp=,portal=,magic=1-99,tokeninfo=anxxxxxx%40xxxxxxx.com,chal_msg=\n"
        val raw = "HTTP/1.1 200 OK\r\n" +
            "Set-Cookie:  SVPNCOOKIE=; path=/; expires=Sun, 11 Mar 1984 12:00:00 GMT; secure; httponly;\r\n" +
            "Transfer-Encoding: chunked\r\n" +
            "Content-Type: text/plain\r\n\r\n" +
            Integer.toHexString(body.length) + "    \r\n" + body + "\r\n0\r\n\r\n"
        val r = HttpResponseReader.read(raw.byteInputStream())
        val outcome = LoginProtocol.classifyStep1(r)
        assertTrue(outcome.toString(), outcome is LoginOutcome.NeedsToken)
    }

    @Test fun `a wrong password comes back as the HTML login page and counts as rejected`() {
        val html = "<!DOCTYPE html><html><head><title>SSL VPN Remote Access Web Portal</title></head></html>"
        val raw = "HTTP/1.1 200 OK\r\n" +
            "Set-Cookie:  SVPNCOOKIE=; path=/; expires=Sun, 11 Mar 1984 12:00:00 GMT; secure; httponly;\r\n" +
            "Content-Type: text/html; charset=utf-8\r\n" +
            "Content-Length: ${html.length}\r\n\r\n" + html
        val r = HttpResponseReader.read(raw.byteInputStream())
        assertEquals(LoginOutcome.Rejected, LoginProtocol.classifyStep1(r))
    }

    @Test fun `an unknown reply is described without any values`() {
        val raw = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 20\r\n\r\nfoo=secret,bar=token"
        val r = HttpResponseReader.read(raw.byteInputStream())
        assertEquals(LoginOutcome.Unexpected, LoginProtocol.classifyStep1(r))
        assertEquals("HTTP 200, text/plain, fields: foo,bar", LoginProtocol.describeUnexpected(r))
    }
}
