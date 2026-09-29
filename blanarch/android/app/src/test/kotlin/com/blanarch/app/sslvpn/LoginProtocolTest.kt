package com.blanarch.app.sslvpn

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class LoginProtocolTest {
    private val step1Body =
        "ret=2,actionurl=/remote/logincheck,tokeninfo=,reqid=123456,polid=1-1-2,grp=VPN_USERS," +
            "portal=full-access,magic=1-7a9f3c"

    private fun response(status: Int = 200, body: String = "", vararg setCookies: String) =
        HttpResponse(status, setCookies.map { "Set-Cookie" to it }, body.toByteArray())

    @Test
    fun `parses the spec example ret body`() {
        val v = LoginProtocol.parseRetValues(step1Body)
        assertEquals("2", v["ret"])
        assertEquals("/remote/logincheck", v["actionurl"])
        assertEquals("", v["tokeninfo"])
        assertEquals("123456", v["reqid"])
        assertEquals("1-1-2", v["polid"])
        assertEquals("VPN_USERS", v["grp"])
        assertEquals("full-access", v["portal"])
        assertEquals("1-7a9f3c", v["magic"])
    }

    @Test
    fun `splits on ampersands and line breaks too`() {
        val v = LoginProtocol.parseRetValues("ret=2&tokeninfo=ftm_push\r\nreqid=9\npeer=")
        assertEquals(mapOf("ret" to "2", "tokeninfo" to "ftm_push", "reqid" to "9", "peer" to ""), v)
    }

    @Test
    fun `non-empty cookie means logged in`() {
        val outcome = LoginProtocol.classifyStep1(response(200, "ret=1", "SVPNCOOKIE=abc123; path=/; secure"))
        assertEquals(LoginOutcome.LoggedIn("abc123"), outcome)
    }

    @Test
    fun `empty cookie does not count and the token challenge is detected`() {
        val outcome = LoginProtocol.classifyStep1(response(200, step1Body, "SVPNCOOKIE=; path=/"))
        outcome as LoginOutcome.NeedsToken
        assertEquals("", outcome.tokenInfo)
        assertFalse(outcome.pushOffered)
        assertEquals("123456", outcome.fields["reqid"])
        assertEquals("1-7a9f3c", outcome.fields["magic"])
        assertEquals("", outcome.fields["peer"])
    }

    @Test
    fun `ftm_push token info offers push`() {
        val outcome = LoginProtocol.classifyStep1(response(200, "ret=2,tokeninfo=ftm_push,reqid=1"))
        assertTrue((outcome as LoginOutcome.NeedsToken).pushOffered)
    }

    @Test
    fun `ret 0 is rejected credentials`() {
        assertEquals(LoginOutcome.Rejected, LoginProtocol.classifyStep1(response(200, "ret=0,redir=/remote/login")))
    }

    @Test
    fun `ret 6 is an unsupported challenge`() {
        assertEquals(LoginOutcome.UnsupportedChallenge, LoginProtocol.classifyStep1(response(200, "ret=6")))
    }

    @Test
    fun `non-200 status is an error`() {
        assertEquals(LoginOutcome.HttpError(405), LoginProtocol.classifyStep1(response(405, "ret=0")))
    }

    @Test
    fun `unrecognised body is unexpected`() {
        assertEquals(LoginOutcome.Unexpected, LoginProtocol.classifyStep1(response(200, "status=busy")))
    }

    @Test
    fun `password body is url encoded`() {
        assertEquals(
            "username=j.doe%40corp&credential=p%26ss+w%3Drd&realm=&ajax=1",
            LoginProtocol.passwordBody("j.doe@corp", "p&ss w=rd", "")
        )
    }

    @Test
    fun `code body echoes the step 1 values`() {
        val fields = (LoginProtocol.classifyStep1(response(200, step1Body)) as LoginOutcome.NeedsToken).fields
        assertEquals(
            "username=bob&realm=staff&reqid=123456&polid=1-1-2&grp=VPN_USERS&portal=full-access&peer=" +
                "&code=654321&code2=&magic=1-7a9f3c",
            LoginProtocol.codeBody("bob", "staff", fields, "654321")
        )
    }

    @Test
    fun `push body replaces the code part`() {
        val fields = (LoginProtocol.classifyStep1(response(200, step1Body)) as LoginOutcome.NeedsToken).fields
        assertEquals(
            "username=bob&realm=&reqid=123456&polid=1-1-2&grp=VPN_USERS&portal=full-access&peer=&ftmpush=1",
            LoginProtocol.pushBody("bob", "", fields)
        )
    }

    @Test
    fun `missing echoed keys are sent empty`() {
        assertEquals(
            "username=bob&realm=&reqid=&polid=&grp=&portal=&peer=&code=1&code2=&magic=",
            LoginProtocol.codeBody("bob", "", emptyMap(), "1")
        )
    }

    @Test
    fun `saml start url and auth path`() {
        assertEquals(
            "https://vpn.example.com:10443/remote/saml/start?redirect=1",
            LoginProtocol.samlStartUrl("vpn.example.com", 10443)
        )
        assertEquals("/remote/saml/auth_id?id=a%2Bb%3D", LoginProtocol.samlAuthPath("a+b="))
    }
}
