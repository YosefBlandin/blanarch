package com.blanarch.app.bridge

import com.blanarch.app.AppGraph
import com.blanarch.app.profile.Address
import com.blanarch.app.profile.AuthMode
import com.blanarch.app.profile.EmailOtpSource
import com.blanarch.app.profile.Profile
import com.blanarch.app.profile.ProfileStore
import com.blanarch.app.profile.SecondFactorPreference
import com.blanarch.app.state.ErrorCode
import com.blanarch.app.state.LogEntry
import com.blanarch.app.state.VpnException
import com.blanarch.app.state.VpnStatus
import io.flutter.plugin.common.BinaryMessenger
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.cancel
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** What the bridge needs from the hosting activity (permissions, browser, starting the service). */
interface VpnHost {
    suspend fun requestVpnConsent(): Boolean
    suspend fun requestNotificationPermission(): Boolean
    fun startVpn(profileId: String)
    fun stopVpn()
    fun restartVpnWithCode()
    fun openBrowser(url: String)
    fun shareText(subject: String, text: String)

    /** Fingerprint, face or screen lock. False if the user cancelled. */
    suspend fun authenticate(): Boolean
    fun deviceSecure(): Boolean
    fun requestAddTile(always: Boolean)
    fun canAddTile(): Boolean
    fun openVpnSettings()

    /** A setup link the activity was opened with; cleared once read. */
    fun takeSetupLink(): String?
}

/** Implements the Pigeon [VpnHostApi] and streams status, log and profiles back over [VpnEventsApi]. */
class VpnBridge(private val graph: AppGraph, private val host: VpnHost, messenger: BinaryMessenger) : VpnHostApi {
    private val events = VpnEventsApi(messenger)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    init {
        VpnHostApi.setUp(messenger, this)
        scope.launch { graph.status.status.collect { runCatching { events.onStatus(it.toMsg(graph.pins::pin)) } } }
        scope.launch { graph.status.log.collect { runCatching { events.onLog(it.toMsg()) } } }
        scope.launch { graph.profiles.profiles.collect { runCatching { events.onProfilesChanged(profiles()) } } }
    }

    fun dispose(messenger: BinaryMessenger) {
        scope.cancel()
        VpnHostApi.setUp(messenger, null)
    }

    override fun profiles(): List<ProfileMsg> = graph.profiles.profiles.value.map { it.toMsg() }

    override suspend fun saveProfile(profile: ProfileMsg, vpnPassword: String?): ProfileMsg {
        if (vpnPassword != null && graph.credentials.locked && !host.authenticate()) {
            throw FlutterError("unlock_cancelled", "The user didn't unlock", null)
        }
        val existing = profile.id.takeIf { it.isNotEmpty() }?.let(graph.profiles::get)
        val saved = graph.profiles.save(
            Profile(
                id = existing?.id ?: ProfileStore.newId(),
                name = profile.name.trim().ifEmpty { profile.hosts.first() },
                hosts = profile.hosts.map { it.trim() }.filter { it.isNotEmpty() },
                port = profile.port.toInt(),
                realm = profile.realm.trim(),
                authMode = AuthMode.valueOf(profile.authMode.name),
                username = profile.username.trim(),
                secondFactor = SecondFactorPreference.valueOf(profile.secondFactor.name),
                // The mailbox source only changes through saveEmailOtp/removeEmailOtp.
                emailOtp = existing?.emailOtp
            )
        )
        if (vpnPassword != null) graph.credentials.setVpnPassword(saved.id, vpnPassword.ifEmpty { null })
        if (graph.prefs.activeProfileId == null) graph.prefs.activeProfileId = saved.id
        return saved.toMsg()
    }

    override fun deleteProfile(id: String) {
        graph.profiles.delete(id)
        graph.credentials.forget(id)
        if (graph.prefs.activeProfileId ==
            id
        ) {
            graph.prefs.activeProfileId = graph.profiles.profiles.value.firstOrNull()?.id
        }
    }

    override suspend fun probe(address: String): ProbeResultMsg {
        val parsed = Address.parse(address)
            ?: return ProbeResultMsg("", 0, "", false, false, false, ErrorCodeMsg.INVALID_ADDRESS)
        // The IKEv2 probe runs alongside: it only matters when SSL-VPN is missing (spec §3.7).
        return coroutineScope {
            val ike = async(Dispatchers.IO) { graph.ikeProber.answers(parsed.host) }
            try {
                val p = withContext(Dispatchers.IO) { graph.prober.probe(parsed.host, parsed.port) }
                ProbeResultMsg(
                    host = parsed.host,
                    port = parsed.port.toLong(),
                    certSha256 = p.certSha256,
                    trustedBySystem = p.trustedBySystem,
                    pinned = graph.pins.pin(parsed.host).equals(p.certSha256, ignoreCase = true),
                    ssoOffered = p.samlOffered,
                    sslVpnPortal = p.sslVpnPortal,
                    ikeAnswers = if (p.sslVpnPortal) false else ike.await(),
                    clientCertRequested = p.clientCertRequested
                )
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                // No SSL-VPN on this address at all, but it answers IPsec: say so instead of "unreachable".
                val code = (e as? VpnException)?.code ?: ErrorCode.GATEWAY_UNREACHABLE
                val ipsecOnly = code == ErrorCode.GATEWAY_UNREACHABLE && ike.await()
                ProbeResultMsg(
                    parsed.host,
                    parsed.port.toLong(),
                    "",
                    false,
                    false,
                    false,
                    (if (ipsecOnly) ErrorCode.SSL_VPN_OFF else code).toMsg(),
                    e.message,
                    sslVpnPortal = false,
                    ikeAnswers = ipsecOnly
                )
            } finally {
                ike.cancel()
            }
        }
    }

    override fun trustCertificate(host: String, sha256: String) = graph.pins.savePin(host, sha256.lowercase())

    override suspend fun saveEmailOtp(profileId: String, source: EmailOtpMsg, password: String): ErrorCodeMsg? {
        val profile = graph.profiles.get(profileId) ?: return ErrorCodeMsg.NO_PROFILE
        val src = EmailOtpSource(
            account = source.account.trim(),
            imapHost = source.imapHost.trim(),
            imapPort = source.imapPort.toInt(),
            mailbox = source.mailbox.trim().ifEmpty { "INBOX" },
            from = source.from.trim()
        )
        if (graph.credentials.locked && !host.authenticate()) return ErrorCodeMsg.LOCKED
        val error = withContext(Dispatchers.IO) { graph.checkEmailPassword(src, password) }
        if (error != null) return error.toMsg()
        graph.profiles.save(profile.copy(emailOtp = src))
        graph.credentials.setEmailPassword(profileId, password)
        return null
    }

    override fun removeEmailOtp(profileId: String) {
        graph.profiles.get(profileId)?.let { graph.profiles.save(it.copy(emailOtp = null)) }
        graph.credentials.setEmailPassword(profileId, null)
    }

    override fun prefs() = PrefsMsg(
        themeMode = ThemeModeMsg.entries.firstOrNull { it.name.equals(graph.prefs.themeMode, ignoreCase = true) }
            ?: ThemeModeMsg.SYSTEM,
        onboarded = graph.prefs.onboarded,
        activeProfileId = graph.prefs.activeProfileId
    )

    override fun status() = graph.status.status.value.toMsg(graph.pins::pin)
    override fun log() = graph.status.logSnapshot().map { it.toMsg() }

    override suspend fun connect(profileId: String): ConnectResultMsg {
        host.requestNotificationPermission()
        if (graph.credentials.locked && !host.authenticate()) return ConnectResultMsg.UNLOCK_CANCELLED
        if (!host.requestVpnConsent()) return ConnectResultMsg.VPN_DENIED
        graph.prefs.activeProfileId = profileId
        host.startVpn(profileId)
        return ConnectResultMsg.STARTED
    }

    override fun shareText(subject: String, text: String) = host.shareText(subject, text)

    override fun useCodeThisTime() = host.restartVpnWithCode()

    override fun appLockAvailable() = host.deviceSecure()
    override fun appLockEnabled() = graph.credentials.locked

    override suspend fun setAppLock(enabled: Boolean): Boolean {
        if (enabled == graph.credentials.locked) return true
        if (!host.authenticate()) return false
        withContext(Dispatchers.IO) { graph.credentials.setLocked(enabled) }
        return true
    }

    override fun requestAddTile(always: Boolean) = host.requestAddTile(always)
    override fun canAddTile() = host.canAddTile()
    override fun openVpnSettings() = host.openVpnSettings()
    override fun takeSetupLink(): String? = host.takeSetupLink()

    /** Called by the activity when a setup link arrives while the app is running. */
    fun deliverSetupLink(url: String) {
        scope.launch { runCatching { events.onSetupLink(url) } }
    }

    override fun disconnect() = host.stopVpn()
    override fun submitOtp(code: String) = graph.manualOtp.submit(code)
    override fun openSso(url: String) = host.openBrowser(url)
    override suspend fun prepareVpn() = host.requestVpnConsent()
    override suspend fun requestNotifications() = host.requestNotificationPermission()

    override fun setThemeMode(mode: ThemeModeMsg) {
        graph.prefs.themeMode = mode.name.lowercase()
    }

    override fun setOnboarded(onboarded: Boolean) {
        graph.prefs.onboarded = onboarded
    }

    override fun setActiveProfile(profileId: String) {
        graph.prefs.activeProfileId = profileId
    }

    private fun Profile.toMsg() = ProfileMsg(
        id = id,
        name = name,
        hosts = hosts,
        port = port.toLong(),
        realm = realm,
        authMode = AuthModeMsg.valueOf(authMode.name),
        username = username,
        secondFactor = SecondFactorMsg.valueOf(secondFactor.name),
        emailOtp = emailOtp?.let { EmailOtpMsg(it.account, it.imapHost, it.imapPort.toLong(), it.mailbox, it.from) },
        hasPassword = graph.credentials.hasVpnPassword(id),
        hasEmailPassword = graph.credentials.hasEmailPassword(id),
        pinSha256 = graph.pins.pin(mainHost)
    )
}

private fun ErrorCode.toMsg() = ErrorCodeMsg.valueOf(name)

private fun VpnStatus.toMsg(pinOf: (String) -> String?) = VpnStatusMsg(
    phase = VpnPhaseMsg.valueOf(phase.name),
    profileId = connectionId,
    host = host,
    attempt = attempt.toLong(),
    maxAttempts = maxAttempts.toLong(),
    ip = ip,
    otpMasked = otpMasked,
    connectedSinceMillis = connectedSinceMillis,
    emailWatching = emailWatching,
    emailIssue = emailIssue?.toMsg(),
    error = error?.toMsg(),
    errorDetail = errorDetail,
    ssoUrl = ssoUrl,
    deadlineMillis = deadlineMillis,
    startedMillis = startedMillis,
    retryReason = retryReason?.toMsg(),
    port = port?.toLong(),
    bytesIn = bytesIn,
    bytesOut = bytesOut,
    latencyMillis = latencyMillis,
    dns = dns,
    dnsSuffix = dnsSuffix,
    routes = routes,
    mtu = mtu?.toLong(),
    tls = tls,
    signIn = signIn?.name,
    reconnects = reconnects.toLong(),
    triedHosts = triedHosts,
    certSha256 = host?.let(pinOf)
)

private fun LogEntry.toMsg() =
    LogEntryMsg(timeMillis, LogLevelMsg.valueOf(level.name), message, event?.let { LogEventMsg.valueOf(it.name) }, args)
