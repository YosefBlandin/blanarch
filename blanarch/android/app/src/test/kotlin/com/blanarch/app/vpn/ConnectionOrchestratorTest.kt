package com.blanarch.app.vpn

import com.blanarch.app.config.VpnConfig
import com.blanarch.app.profile.AuthMode
import com.blanarch.app.profile.EmailOtpSource
import com.blanarch.app.profile.Profile
import com.blanarch.app.profile.SecondFactorPreference
import com.blanarch.app.sso.SsoCallback
import com.blanarch.app.state.ErrorCode
import com.blanarch.app.state.LogEvent
import com.blanarch.app.state.SignInMethod
import com.blanarch.app.state.StatusStore
import com.blanarch.app.state.VpnException
import com.blanarch.app.state.VpnPhase
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class ConnectionOrchestratorTest {
    private val config = VpnConfig.parse(File("src/main/res/raw/vpn_config.json").readText())
    private val madrid = Profile(
        id = "madrid",
        name = "Madrid",
        hosts = listOf("203.0.113.46", "203.0.113.42", "203.0.113.45"),
        port = 10443,
        username = "ana",
        emailOtp = EmailOtpSource("ana@example.com", "mail.example.com")
    )
    private val lima =
        Profile(id = "lima", name = "Lima", hosts = listOf("198.51.100.18"), port = 4443, username = "ana")
    private val creds = Credentials("vpn-pass", "mail-pass")

    /** Scripted behaviour per host. */
    private class Script(
        val login: suspend (SecondFactorProvider) -> Unit = {},
        val samlLogin: suspend (String) -> Unit = {},
        val pumpResults: ArrayDeque<suspend () -> String> = ArrayDeque(listOf({ awaitCancellation() })),
        /** Tunnel-settings calls (1-based) that fail as a refused session would. */
        val refuseConfigOnCalls: Set<Int> = emptySet(),
        val tunnel: TunnelConfig = TunnelConfig(),
        val linkDns: List<String> = listOf("10.0.0.53")
    )

    private inner class Fakes(val scripts: Map<String, Script>) {
        val created = mutableListOf<String>()
        val loggedOut = mutableListOf<String>()
        var tunsOpened = 0
        var tunIp: IpConfig? = null
        var logins = 0
        var configCalls = 0
        var tunsClosed = 0
        val codes = ArrayDeque(listOf("123456"))
        var ssoId: CompletableDeferred<String> = CompletableDeferred("sso-session")
        var emailSourceSeen: EmailOtpSource? = null

        /** Runs while the orchestrator waits for a code, to look at the status then. */
        var whileWaiting: () -> Unit = {}

        val gateways = GatewayFactory { host, _ ->
            created += host
            val script = scripts[host] ?: Script(login = { throw VpnException(ErrorCode.GATEWAY_UNREACHABLE, host) })
            object : VpnGateway {
                override suspend fun login(username: String, password: String, secondFactor: SecondFactorProvider) {
                    logins++
                    script.login(secondFactor)
                }
                override fun samlStartUrl(listenPort: Int) = "https://$host/remote/saml/start?redirect=1"
                override suspend fun loginWithSamlId(id: String) = script.samlLogin(id)
                override suspend fun fetchTunnelConfig(): TunnelConfig {
                    if (++configCalls in script.refuseConfigOnCalls) {
                        throw VpnException(ErrorCode.TUNNEL_REFUSED, "HTTP 403")
                    }
                    return script.tunnel
                }
                override suspend fun openLink(): PacketLink = object : PacketLink {
                    override suspend fun negotiate(timeout: Duration) = IpConfig("10.212.134.7", script.linkDns)
                    override suspend fun pump(tun: TunDevice): String = script.pumpResults.removeFirst().invoke()
                    override fun close() = Unit
                }
                override suspend fun logout() {
                    loggedOut += host
                }
                override fun close() = Unit
            }
        }

        val otp = OtpSessionFactory { source, password ->
            emailSourceSeen = source
            object : OtpSession {
                override val watchingEmail = source != null && password != null
                override val emailIssue: ErrorCode? = if (watchingEmail) null else ErrorCode.EMAIL_NOT_CONFIGURED
                override val timeout = 90.seconds
                override suspend fun awaitCode(): String? {
                    whileWaiting()
                    return codes.removeFirstOrNull()
                }
                override fun close() = Unit
            }
        }

        val tun = TunFactory { ip, _, _ ->
            tunIp = ip
            tunsOpened++
            object : TunDevice {
                override val input = ByteArrayInputStream(ByteArray(0))
                override val output = ByteArrayOutputStream()
                override fun close() {
                    tunsClosed++
                }
            }
        }

        val sso = SsoCallback { ssoId.await() }
    }

    private class FakeNetwork(initial: String? = "wifi") : NetworkWatch {
        override val current = MutableStateFlow(initial)
    }

    private fun orchestrator(f: Fakes, status: StatusStore, network: NetworkWatch = AlwaysOnline) =
        ConnectionOrchestrator(config, f.gateways, f.otp, f.tun, f.sso, status, network, statsInterval = null) {
            1_000L
        }

    @Test fun `offline at the start it waits for a network without using up attempts`() = runTest {
        val status = StatusStore()
        val net = FakeNetwork(initial = null)
        val f = Fakes(mapOf("198.51.100.18" to Script(login = code)))
        val job = launch { orchestrator(f, status, net).run(lima, creds) }
        runCurrent()
        assertEquals(VpnPhase.WAITING_NETWORK, status.status.value.phase)
        assertEquals(0, f.created.size)
        net.current.value = "wifi"
        advanceUntilIdle()
        assertEquals(VpnPhase.CONNECTED, status.status.value.phase)
        assertEquals(1, status.status.value.triedHosts.size)
        job.cancel()
    }

    @Test fun `switching networks rejoins at once with the same session`() = runTest {
        val status = StatusStore()
        val net = FakeNetwork("wifi")
        val script =
            Script(login = code, pumpResults = ArrayDeque(listOf({ awaitCancellation() }, { awaitCancellation() })))
        val f = Fakes(mapOf("198.51.100.18" to script))
        f.codes.addLast("654321")
        val job = launch { orchestrator(f, status, net).run(lima, creds) }
        advanceUntilIdle()
        assertEquals(VpnPhase.CONNECTED, status.status.value.phase)
        net.current.value = "mobile"
        advanceUntilIdle()
        assertEquals(VpnPhase.CONNECTED, status.status.value.phase)
        assertEquals(1, f.logins) // no new sign-in, just a new tunnel
        assertEquals(2, f.tunsOpened)
        assertTrue(status.logSnapshot().any { it.event == LogEvent.NETWORK_CHANGED })
        job.cancel()
    }

    @Test fun `losing the network while connected waits, then rejoins`() = runTest {
        val status = StatusStore()
        val net = FakeNetwork("wifi")
        val script =
            Script(login = code, pumpResults = ArrayDeque(listOf({ awaitCancellation() }, { awaitCancellation() })))
        val f = Fakes(mapOf("198.51.100.18" to script))
        val job = launch { orchestrator(f, status, net).run(lima, creds) }
        advanceUntilIdle()
        net.current.value = null
        advanceUntilIdle()
        assertEquals(VpnPhase.WAITING_NETWORK, status.status.value.phase)
        net.current.value = "wifi-2"
        advanceUntilIdle()
        assertEquals(VpnPhase.CONNECTED, status.status.value.phase)
        assertEquals(1, f.logins)
        job.cancel()
    }

    @Test fun `a rejoin refused after a network change also signs in again, not a new attempt`() = runTest {
        val status = StatusStore()
        val net = FakeNetwork("wifi")
        val script = Script(
            login = { provider -> provider.provide(false) },
            pumpResults = ArrayDeque(listOf({ awaitCancellation() }, { awaitCancellation() })),
            refuseConfigOnCalls = setOf(2)
        )
        val f = Fakes(mapOf("198.51.100.18" to script))
        f.codes.addLast("654321")
        val job = launch { orchestrator(f, status, net).run(lima, creds) }
        advanceUntilIdle()
        net.current.value = "mobile"
        advanceUntilIdle()
        assertEquals(VpnPhase.CONNECTED, status.status.value.phase)
        assertEquals(2, f.logins)
        assertEquals(1, f.created.size) // same gateway, no new attempt
        assertTrue(status.logSnapshot().any { it.event == LogEvent.SESSION_EXPIRED })
        job.cancel()
    }

    @Test fun `a refused rejoin means the session expired, so it signs in again`() = runTest {
        val status = StatusStore()
        val script = Script(
            login = { provider -> provider.provide(false) },
            pumpResults = ArrayDeque(listOf({ "gateway ended the session" }, { awaitCancellation() })),
            refuseConfigOnCalls = setOf(2)
        )
        val f = Fakes(mapOf("198.51.100.18" to script))
        f.codes.addLast("654321")
        val job = launch { orchestrator(f, status).run(lima, creds) }
        advanceUntilIdle()
        assertEquals(VpnPhase.CONNECTED, status.status.value.phase)
        assertEquals(2, f.logins)
        assertTrue(status.logSnapshot().any { it.event == LogEvent.SESSION_EXPIRED })
        job.cancel()
    }

    private val code: suspend (SecondFactorProvider) -> Unit = { provider ->
        assertEquals(SecondFactor.Code("123456"), provider.provide(false))
    }

    @Test fun `connects with the emailed code and stays up until cancelled`() = runTest {
        val status = StatusStore()
        val f = Fakes(mapOf("203.0.113.46" to Script(login = code)))
        val job = launch { orchestrator(f, status).run(madrid, creds) }
        runCurrent()
        val s = status.status.value
        assertEquals(VpnPhase.CONNECTED, s.phase)
        assertEquals("10.212.134.7", s.ip)
        assertEquals("1••••6", s.otpMasked)
        assertEquals(madrid.emailOtp, f.emailSourceSeen)

        job.cancel()
        advanceUntilIdle()
        assertEquals(listOf("203.0.113.46"), f.loggedOut)
        assertEquals(1, f.tunsClosed)
    }

    @Test fun `fails over through the profile's gateways in order`() = runTest {
        val status = StatusStore()
        val f = Fakes(mapOf("203.0.113.45" to Script(login = code)))
        val job = launch { orchestrator(f, status).run(madrid, creds) }
        advanceUntilIdle()
        assertEquals(listOf("203.0.113.46", "203.0.113.42", "203.0.113.45"), f.created)
        assertEquals(VpnPhase.CONNECTED, status.status.value.phase)
        job.cancel()
    }

    @Test fun `while retrying the UI knows why the last attempt failed, and since when it has been trying`() = runTest {
        val status = StatusStore()
        var seen: Pair<ErrorCode?, Long?>? = null
        val f = Fakes(
            mapOf(
                "203.0.113.45" to Script(login = { provider ->
                    seen = status.status.value.retryReason to status.status.value.startedMillis
                    provider.provide(false)
                })
            )
        )
        val job = launch { orchestrator(f, status).run(madrid, creds) }
        advanceUntilIdle()
        assertEquals(ErrorCode.GATEWAY_UNREACHABLE to 1_000L, seen)
        assertEquals(null, status.status.value.retryReason)
        assertEquals(null, status.status.value.startedMillis)
        job.cancel()
    }

    @Test fun `once connected the status carries the details IT asks for`() = runTest {
        val status = StatusStore()
        val f = Fakes(mapOf("203.0.113.42" to Script(login = code)))
        val job = launch { orchestrator(f, status).run(madrid, creds) }
        advanceUntilIdle()
        val s = status.status.value
        assertEquals(VpnPhase.CONNECTED, s.phase)
        assertEquals(listOf("203.0.113.46", "203.0.113.42"), s.triedHosts)
        assertEquals(SignInMethod.CODE, s.signIn)
        assertEquals(listOf("10.0.0.53"), s.dns)
        assertEquals(emptyList<String>(), s.routes) // the fake gateway routes all traffic
        assertEquals(10443, s.port)
        assertEquals(0, s.reconnects)
        job.cancel()
    }

    @Test fun `a full tunnel without gateway DNS uses the fallback resolvers, never none`() = runTest {
        val status = StatusStore()
        val f = Fakes(mapOf("203.0.113.42" to Script(login = code, linkDns = emptyList())))
        val job = launch { orchestrator(f, status).run(madrid, creds) }
        advanceUntilIdle()
        assertEquals(VpnPhase.CONNECTED, status.status.value.phase)
        assertEquals(config.fallbackDns, f.tunIp?.dns)
        assertEquals(config.fallbackDns, status.status.value.dns)
        val logged = status.logSnapshot().single { it.event == LogEvent.DNS_FALLBACK }
        assertEquals(listOf(config.fallbackDns.joinToString(", ")), logged.args)
        job.cancel()
    }

    @Test fun `DNS from the tunnel settings is used when the link gives none`() = runTest {
        val status = StatusStore()
        val script = Script(login = code, linkDns = emptyList(), tunnel = TunnelConfig(dns = listOf("10.9.9.9")))
        val job = launch { orchestrator(Fakes(mapOf("203.0.113.42" to script)), status).run(madrid, creds) }
        advanceUntilIdle()
        assertEquals(listOf("10.9.9.9"), status.status.value.dns)
        assertTrue(status.logSnapshot().none { it.event == LogEvent.DNS_FALLBACK })
        job.cancel()
    }

    @Test fun `a split tunnel without gateway DNS keeps the phone's DNS`() = runTest {
        val status = StatusStore()
        val split = TunnelConfig(routes = listOf("10.10.0.0" to "255.255.0.0"))
        val f = Fakes(mapOf("203.0.113.42" to Script(login = code, linkDns = emptyList(), tunnel = split)))
        val job = launch { orchestrator(f, status).run(madrid, creds) }
        advanceUntilIdle()
        assertEquals(VpnPhase.CONNECTED, status.status.value.phase)
        assertEquals(emptyList<String>(), f.tunIp?.dns)
        job.cancel()
    }

    @Test fun `main steps are logged as events the app can translate`() = runTest {
        val status = StatusStore()
        val f = Fakes(mapOf("203.0.113.42" to Script(login = code)))
        val job = launch { orchestrator(f, status).run(madrid, creds) }
        advanceUntilIdle()
        val events = status.logSnapshot().mapNotNull { e -> e.event?.let { it to e.args } }
        assertEquals(LogEvent.STARTING to listOf("Madrid"), events.first())
        assertTrue(events.contains(LogEvent.ATTEMPT to listOf("2", "10", "203.0.113.42:10443")))
        assertTrue(events.contains(LogEvent.FAILED to listOf("GATEWAY_UNREACHABLE", "203.0.113.46")))
        assertEquals(LogEvent.CONNECTED to listOf("10.212.134.7"), events.last())
        job.cancel()
    }

    @Test fun `push is used when offered and the profile allows it`() = runTest {
        val status = StatusStore()
        var phaseDuringPush: VpnPhase? = null
        val f = Fakes(
            mapOf(
                "198.51.100.18" to Script(login = { provider ->
                    assertEquals(SecondFactor.Push, provider.provide(true))
                    phaseDuringPush = status.status.value.phase
                })
            )
        )
        val job = launch { orchestrator(f, status).run(lima, creds) }
        advanceUntilIdle()
        assertEquals(VpnPhase.WAITING_PUSH, phaseDuringPush)
        assertEquals(VpnPhase.CONNECTED, status.status.value.phase)
        job.cancel()
    }

    @Test fun `a profile set to codes never asks for push`() = runTest {
        val status = StatusStore()
        val f = Fakes(mapOf("198.51.100.18" to Script(login = { assertTrue(it.provide(true) is SecondFactor.Code) })))
        val job = launch {
            orchestrator(f, status).run(lima.copy(secondFactor = SecondFactorPreference.CODE), creds)
        }
        advanceUntilIdle()
        assertEquals(VpnPhase.CONNECTED, status.status.value.phase)
        job.cancel()
    }

    @Test fun `single sign-on shows the browser page, then signs in with the returned id`() = runTest {
        val status = StatusStore()
        var usedId: String? = null
        val f = Fakes(mapOf("198.51.100.18" to Script(samlLogin = { usedId = it })))
        f.ssoId = CompletableDeferred()
        val job = launch { orchestrator(f, status).run(lima.copy(authMode = AuthMode.SSO), Credentials(null, null)) }
        runCurrent()
        assertEquals(VpnPhase.WAITING_SSO, status.status.value.phase)
        assertEquals("https://198.51.100.18/remote/saml/start?redirect=1", status.status.value.ssoUrl)
        assertEquals(1_000L + config.sso.timeout.inWholeMilliseconds, status.status.value.deadlineMillis)

        f.ssoId.complete("abc")
        advanceUntilIdle()
        assertEquals("abc", usedId)
        assertEquals(VpnPhase.CONNECTED, status.status.value.phase)
        assertEquals(null, status.status.value.ssoUrl)
        assertEquals(null, status.status.value.deadlineMillis)
        job.cancel()
    }

    @Test fun `while waiting for a code the UI gets the moment the app stops waiting`() = runTest {
        val status = StatusStore()
        val f = Fakes(mapOf("203.0.113.46" to Script(login = code)))
        var seen: Long? = null
        f.whileWaiting = { seen = status.status.value.deadlineMillis }
        val job = launch { orchestrator(f, status).run(madrid, creds) }
        runCurrent()
        assertEquals(1_000L + 90_000L, seen)
        assertEquals(VpnPhase.CONNECTED, status.status.value.phase)
        assertEquals(null, status.status.value.deadlineMillis)
        job.cancel()
    }

    @Test fun `single sign-on gives up after the timeout`() = runTest {
        val status = StatusStore()
        val f = Fakes(mapOf("198.51.100.18" to Script()))
        f.ssoId = CompletableDeferred()
        orchestrator(f, status).run(lima.copy(authMode = AuthMode.SSO), Credentials(null, null))
        assertEquals(ErrorCode.SSO_TIMEOUT, status.status.value.error)
    }

    @Test fun `wrong password, or a certificate problem with one address, stops at once`() = runTest {
        val status = StatusStore()
        val f = Fakes(mapOf("203.0.113.46" to Script(login = { throw VpnException(ErrorCode.AUTH_REJECTED) })))
        orchestrator(f, status).run(madrid, creds)
        assertEquals(listOf("203.0.113.46"), f.created)
        assertEquals(ErrorCode.AUTH_REJECTED, status.status.value.error)

        for (err in listOf(ErrorCode.CERT_UNTRUSTED, ErrorCode.CERT_MISMATCH)) {
            val s2 = StatusStore()
            val g = Fakes(mapOf("198.51.100.18" to Script(login = { throw VpnException(err) })))
            orchestrator(g, s2).run(lima, creds)
            assertEquals(listOf("198.51.100.18"), g.created)
            assertEquals(err, s2.status.value.error)
        }
    }

    @Test fun `a certificate problem is reported rather than running out of attempts`() = runTest {
        val status = StatusStore()
        val f = Fakes(mapOf("203.0.113.46" to Script(login = { throw VpnException(ErrorCode.CERT_UNTRUSTED, "aa") })))
        orchestrator(f, status).run(madrid, creds)
        assertEquals(ErrorCode.CERT_UNTRUSTED, status.status.value.error)
    }

    @Test fun `a certificate problem on one address skips it and a backup still connects`() = runTest {
        val status = StatusStore()
        val f = Fakes(
            mapOf(
                "203.0.113.46" to Script(login = { throw VpnException(ErrorCode.CERT_UNTRUSTED, "aa") }),
                "203.0.113.42" to Script(login = code)
            )
        )
        val job = launch { orchestrator(f, status).run(madrid, creds) }
        advanceUntilIdle()
        assertEquals(VpnPhase.CONNECTED, status.status.value.phase)
        assertEquals(listOf("203.0.113.46", "203.0.113.42"), f.created)
        job.cancel()
    }

    @Test fun `certificate problems on every address stop with that error`() = runTest {
        val status = StatusStore()
        val bad = Script(login = { throw VpnException(ErrorCode.CERT_MISMATCH) })
        val f = Fakes(mapOf("203.0.113.46" to bad, "203.0.113.42" to bad, "203.0.113.45" to bad))
        orchestrator(f, status).run(madrid, creds)
        assertEquals(ErrorCode.CERT_MISMATCH, status.status.value.error)
        assertEquals(3, f.created.size)
    }

    @Test fun `gives up after the configured number of attempts`() = runTest {
        val status = StatusStore()
        val f = Fakes(emptyMap())
        orchestrator(f, status).run(madrid, creds)
        assertEquals(config.retry.maxAttempts, f.created.size)
        assertEquals(ErrorCode.OUT_OF_ATTEMPTS, status.status.value.error)
    }

    @Test fun `after a drop it reuses the session before signing in again`() = runTest {
        val status = StatusStore()
        val secondUp = CompletableDeferred<Unit>()
        var logins = 0
        val script = Script(
            login = {
                logins++
                code(it)
            },
            pumpResults = ArrayDeque(
                listOf(
                    { "gateway stopped responding" },
                    {
                        secondUp.complete(Unit)
                        awaitCancellation()
                    }
                )
            )
        )
        val f = Fakes(mapOf("198.51.100.18" to script))
        val job = launch { orchestrator(f, status).run(lima, creds) }
        advanceUntilIdle()
        assertTrue(secondUp.isCompleted)
        assertEquals(1, logins)
        assertEquals(2, f.tunsOpened)
        job.cancel()
    }

    @Test fun `missing VPN password fails before touching the network`() = runTest {
        val status = StatusStore()
        val f = Fakes(emptyMap())
        orchestrator(f, status).run(lima, Credentials(null, null))
        assertTrue(f.created.isEmpty())
        assertEquals(ErrorCode.NO_VPN_PASSWORD, status.status.value.error)
    }

    @Test fun `without an email source the UI is told to expect a typed code`() = runTest {
        val status = StatusStore()
        var watching = true
        var issue: ErrorCode? = null
        val script = Script(login = { provider ->
            watching = status.status.value.emailWatching
            issue = status.status.value.emailIssue
            provider.provide(false)
        })
        val job = launch { orchestrator(Fakes(mapOf("198.51.100.18" to script)), status).run(lima, creds) }
        advanceUntilIdle()
        assertFalse(watching)
        assertEquals(ErrorCode.EMAIL_NOT_CONFIGURED, issue)
        job.cancel()
    }
}
