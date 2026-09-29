package com.blanarch.app.mail

import com.blanarch.app.config.VpnConfig
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class OtpMatcherTest {
    private val rules = VpnConfig.parse(java.io.File("src/main/res/raw/vpn_config.json").readText()).otp
    private val sender = "noreply@vpn.example.com"

    @Test fun `code in the subject`() {
        val msg = "From: \"VPN Gateway\" <noreply@vpn.example.com>\r\nSubject: AuthCode: 482913\r\n\r\nhello"
        assertEquals("482913", OtpMatcher.codeIn(msg, rules, sender))
    }

    @Test fun `code in a quoted-printable body with an encoded subject`() {
        val msg = """
            From: noreply@vpn.example.com
            Subject: =?UTF-8?B?QXV0aENvZGUgbm90aWZpY2F0aW9u?=
            Content-Type: text/plain; charset=utf-8
            Content-Transfer-Encoding: quoted-printable

            Your token code is 7=
            71234 and expires soon.
        """.trimIndent()
        assertEquals("771234", OtpMatcher.codeIn(msg, rules, sender))
    }

    @Test fun `code in a base64 html part of a multipart message`() {
        val html = java.util.Base64.getEncoder().encodeToString("<p>AuthCode: <b>5566</b></p>".toByteArray())
        val msg = """
            From: noreply@vpn.example.com
            Subject: AuthCode
            Content-Type: multipart/alternative; boundary="b1"

            --b1
            Content-Type: text/html; charset=utf-8
            Content-Transfer-Encoding: base64

            $html
            --b1--
        """.trimIndent()
        // Tags are stripped to spaces, and the pattern allows whitespace after "AuthCode:".
        assertEquals("5566", OtpMatcher.codeIn(msg, rules, sender))
    }

    @Test fun `other senders are ignored`() {
        assertNull(OtpMatcher.codeIn("From: someone@else.com\r\nSubject: AuthCode: 123456\r\n\r\n", rules, sender))
    }
}

class GenericCodePatternTest {
    private val rules = VpnConfig.parse(java.io.File("src/main/res/raw/vpn_config.json").readText()).otp

    @Test fun `common code wordings in English and Spanish`() {
        // IMAP hands over raw bytes as Latin-1 text, so encode the way a real UTF-8 mail arrives.
        fun code(subject: String, body: String = "") = OtpMatcher.codeIn(
            String("From: a@b.c\r\nSubject: $subject\r\n\r\n$body".toByteArray(), Charsets.ISO_8859_1),
            rules
        )
        assertEquals("123456", code("AuthCode: 123456"))
        assertEquals("654321", code("Login", "Your token code is 654321"))
        assertEquals("112233", code("Verification", "Your verification code: 112233"))
        assertEquals("998877", code("Acceso", "Tu código es 998877"))
        assertNull(code("Invoice 2026", "Total 450"))
    }

    @Test fun `any sender counts when no sender filter is set`() {
        assertEquals("123456", OtpMatcher.codeIn("From: x@y.z\r\nSubject: AuthCode: 123456\r\n\r\n", rules))
    }
}

class ImapResponsesTest {
    @Test fun `reads untagged lines with an inlined literal until the tag`() {
        val server = "* 3 FETCH (UID 41 BODY[] {13}\r\nSubject: hi\r\n)\r\nA7 OK done\r\n"
        val lines = ImapResponses.readUntilTagged(server.byteInputStream(), "A7")
        assertEquals("Subject: hi\r\n)", ImapResponses.fetchedBody(lines))
    }

    @Test fun `failed login surfaces the server status`() {
        val e = runCatching {
            ImapResponses.readUntilTagged(
                "A1 NO [AUTHENTICATIONFAILED] Authentication failed.\r\n".byteInputStream(),
                "A1"
            )
        }.exceptionOrNull() as ImapException
        assertEquals("NO [AUTHENTICATIONFAILED] Authentication failed.", e.status)
    }

    @Test fun `search results become UIDs`() {
        assertEquals(listOf(4L, 9L, 12L), ImapResponses.searchUids(listOf("* SEARCH 4 9 12")))
    }
}
