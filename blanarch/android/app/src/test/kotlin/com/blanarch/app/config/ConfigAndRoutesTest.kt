package com.blanarch.app.config

import com.blanarch.app.profile.Address
import com.blanarch.app.profile.AuthMode
import com.blanarch.app.profile.EmailOtpSource
import com.blanarch.app.profile.Profile
import com.blanarch.app.profile.SecondFactorPreference
import com.blanarch.app.security.PinMismatchException
import com.blanarch.app.security.PinStore
import com.blanarch.app.security.PinningTrustManager
import com.blanarch.app.security.UntrustedCertificateException
import com.blanarch.app.sso.SsoRedirect
import com.blanarch.app.vpn.Route
import com.blanarch.app.vpn.Routes
import com.blanarch.app.vpn.TunnelConfig
import java.io.File
import java.math.BigInteger
import java.security.Principal
import java.security.PublicKey
import java.security.cert.CertificateException
import java.security.cert.X509Certificate
import java.util.Date
import javax.net.ssl.X509TrustManager
import kotlin.time.Duration.Companion.seconds
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class VpnConfigTest {
    @Test fun `bundled config holds only generic defaults`() {
        val text = File("src/main/res/raw/vpn_config.json").readText()
        val config = VpnConfig.parse(text)
        assertEquals(10, config.retry.maxAttempts)
        assertEquals(90.seconds, config.otp.timeout)
        assertEquals(8020, config.sso.listenPort)
        assertEquals(1354, config.mru)
        assertTrue(config.fallbackDns.isNotEmpty() && config.fallbackDns.all(Routes::isIpv4))
        // Nothing specific to one company ships with the app: no addresses but the public
        // fallback resolvers, and no email addresses.
        val addresses = Regex("""\b\d{1,3}(\.\d{1,3}){3}\b""").findAll(text).map { it.value }.toSet()
        assertEquals(config.fallbackDns.toSet(), addresses)
        assertTrue(!text.contains('@'))
        // Plus any strings listed in the git-ignored private/company-strings.txt, when it exists.
        privateStrings().forEach { assertTrue(it, !text.contains(it, ignoreCase = true)) }
    }

    private fun privateStrings(): List<String> =
        File("../../../private/company-strings.txt").takeIf { it.exists() }?.readLines().orEmpty()
            .map { it.trim() }.filter { it.isNotEmpty() && !it.startsWith("#") }
}

class AddressTest {
    @Test fun `accepts what people paste`() {
        assertEquals(Address.Parsed("vpn.example.com", 443), Address.parse("vpn.example.com"))
        assertEquals(Address.Parsed("vpn.example.com", 10443), Address.parse(" VPN.example.com:10443 "))
        assertEquals(
            Address.Parsed("vpn.example.com", 8443),
            Address.parse("https://vpn.example.com:8443/remote/login?lang=en")
        )
        assertEquals(Address.Parsed("198.51.100.18", 4443), Address.parse("198.51.100.18:4443"))
        assertEquals(Address.Parsed("fe80::1", 443), Address.parse("[fe80::1]"))
    }

    @Test fun `rejects junk`() {
        assertNull(Address.parse(""))
        assertNull(Address.parse("vpn corp"))
        assertNull(Address.parse("vpn.example.com:99999"))
        assertNull(Address.parse("vpn.example.com:abc"))
    }
}

class ProfileJsonTest {
    @Test fun `profile survives a save and load`() {
        val p = Profile(
            id = "1", name = "Madrid", hosts = listOf("203.0.113.46", "203.0.113.42"), port = 10443,
            realm = "staff", authMode = AuthMode.PASSWORD, username = "ana",
            secondFactor = SecondFactorPreference.CODE,
            emailOtp = EmailOtpSource("ana@example.com", "mail.example.com", from = "noreply@example.com")
        )
        assertEquals(p, Profile.fromJson(org.json.JSONObject(p.toJson().toString())))
        val sso = p.copy(authMode = AuthMode.SSO, emailOtp = null)
        assertEquals(sso, Profile.fromJson(org.json.JSONObject(sso.toJson().toString())))
    }
}

class SsoRedirectTest {
    @Test fun `reads the session id from the browser redirect`() {
        assertEquals("abc123", SsoRedirect.idFrom("GET /?id=abc123 HTTP/1.1"))
        assertEquals("a b", SsoRedirect.idFrom("GET /?x=1&id=a%20b HTTP/1.1"))
        assertNull(SsoRedirect.idFrom("GET /favicon.ico HTTP/1.1"))
        assertNull(SsoRedirect.idFrom("GET /?id= HTTP/1.1"))
    }
}

class PinningTrustManagerTest {
    private class Pins(var value: String? = null) : PinStore {
        override fun pin(host: String) = value
        override fun savePin(host: String, digest: String) {
            value = digest
        }
    }

    private val trusting = object : X509TrustManager {
        override fun checkClientTrusted(chain: Array<out X509Certificate>?, authType: String?) = Unit
        override fun checkServerTrusted(chain: Array<out X509Certificate>?, authType: String?) = Unit
        override fun getAcceptedIssuers(): Array<X509Certificate> = emptyArray()
    }
    private val refusing = object : X509TrustManager {
        override fun checkClientTrusted(chain: Array<out X509Certificate>?, authType: String?) = Unit
        override fun checkServerTrusted(chain: Array<out X509Certificate>?, authType: String?): Unit =
            throw CertificateException("self-signed")
        override fun getAcceptedIssuers(): Array<X509Certificate> = emptyArray()
    }

    private val cert = FakeCert(byteArrayOf(1, 2, 3))
    private val digest = "039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81"

    @Test fun `unknown self-signed certificate is refused, never silently pinned`() {
        val pins = Pins()
        val e = runCatching { PinningTrustManager("h", pins, refusing).checkServerTrusted(arrayOf(cert), "RSA") }
            .exceptionOrNull() as UntrustedCertificateException
        assertEquals(digest, e.digest)
        assertNull(pins.value)
    }

    @Test fun `system-trusted certificate passes without a pin`() {
        PinningTrustManager("h", Pins(), trusting).checkServerTrusted(arrayOf(cert), "RSA")
    }

    @Test fun `pinned certificate must match exactly, even if the system trusts another`() {
        PinningTrustManager("h", Pins(digest), refusing).checkServerTrusted(arrayOf(cert), "RSA")
        val other = runCatching {
            PinningTrustManager("h", Pins("00".repeat(32)), trusting).checkServerTrusted(arrayOf(cert), "RSA")
        }.exceptionOrNull()
        assertTrue(other is PinMismatchException)
    }
}

/** Minimal certificate whose DER encoding is fixed bytes. */
private class FakeCert(private val der: ByteArray) : X509Certificate() {
    override fun getEncoded() = der
    override fun checkValidity() = Unit
    override fun checkValidity(date: Date?) = Unit
    override fun getVersion() = 3
    override fun getSerialNumber(): BigInteger = BigInteger.ONE
    override fun getIssuerDN(): Principal = Principal { "CN=test" }
    override fun getSubjectDN(): Principal = Principal { "CN=test" }
    override fun getNotBefore() = Date(0)
    override fun getNotAfter() = Date(0)
    override fun getTBSCertificate() = der
    override fun getSignature() = der
    override fun getSigAlgName() = "none"
    override fun getSigAlgOID() = "0"
    override fun getSigAlgParams(): ByteArray? = null
    override fun getIssuerUniqueID(): BooleanArray? = null
    override fun getSubjectUniqueID(): BooleanArray? = null
    override fun getKeyUsage(): BooleanArray? = null
    override fun getBasicConstraints() = -1
    override fun verify(key: PublicKey?) = Unit
    override fun verify(key: PublicKey?, sigProvider: String?) = Unit
    override fun toString() = "FakeCert"
    override fun getPublicKey(): PublicKey? = null
    override fun hasUnsupportedCriticalExtension() = false
    override fun getCriticalExtensionOIDs(): MutableSet<String>? = null
    override fun getNonCriticalExtensionOIDs(): MutableSet<String>? = null
    override fun getExtensionValue(oid: String?): ByteArray? = null
}

class RoutesTest {
    @Test fun `masks become prefixes and network addresses`() {
        assertEquals(16, Routes.prefixLength("255.255.0.0"))
        assertEquals("10.10.0.0", Routes.network("10.10.3.7", "255.255.0.0"))
    }

    @Test fun `no split routes sends all traffic through the tunnel`() {
        assertEquals(listOf(Route("0.0.0.0", 0)), Routes.plan(TunnelConfig(), listOf("10.0.0.53")))
    }

    @Test fun `split routes also route the DNS servers`() {
        val plan = Routes.plan(TunnelConfig(routes = listOf("10.10.3.7" to "255.255.0.0")), listOf("10.0.0.53"))
        assertEquals(listOf(Route("10.10.0.0", 16), Route("10.0.0.53", 32)), plan)
    }

    @Test fun `DNS comes from the link, then the tunnel settings`() {
        assertEquals(
            Routes.DnsChoice(listOf("10.0.0.53"), false),
            Routes.dnsFor(listOf("10.0.0.53", "10.0.0.53"), listOf("10.9.9.9"), listOf("1.1.1.1"), fullTunnel = true)
        )
        assertEquals(
            Routes.DnsChoice(listOf("10.9.9.9"), false),
            Routes.dnsFor(listOf("0.0.0.0", "junk"), listOf(" 10.9.9.9 "), listOf("1.1.1.1"), fullTunnel = true)
        )
    }

    @Test fun `a full tunnel never goes without DNS, a split tunnel keeps the phone's`() {
        val none = emptyList<String>()
        assertEquals(Routes.DnsChoice(listOf("1.1.1.1"), true), Routes.dnsFor(none, none, listOf("1.1.1.1"), true))
        assertEquals(Routes.DnsChoice(none, false), Routes.dnsFor(none, none, listOf("1.1.1.1"), false))
    }

    @Test fun `only dotted IPv4 addresses count as DNS servers`() {
        listOf("1.1.1.1", "10.0.0.53", "255.255.255.255").forEach { assertTrue(it, Routes.isIpv4(it)) }
        listOf("", "0.0.0.0", "1.1.1", "1.1.1.1.1", "256.1.1.1", "fd00::1", "a.b.c.d", "1..1.1").forEach {
            assertTrue(it, !Routes.isIpv4(it))
        }
    }

    @Test fun `search domains split on separators`() {
        assertEquals(listOf("a.local", "b.local"), Routes.searchDomains("a.local; b.local"))
    }
}
