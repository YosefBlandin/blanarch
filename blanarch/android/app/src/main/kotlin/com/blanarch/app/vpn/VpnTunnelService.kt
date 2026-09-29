package com.blanarch.app.vpn

import android.app.RemoteInput
import android.content.Intent
import android.net.VpnService
import com.blanarch.app.BlanarchApplication
import com.blanarch.app.R
import com.blanarch.app.net.SocketFactory
import com.blanarch.app.otp.DefaultOtpSessionFactory
import com.blanarch.app.profile.Profile
import com.blanarch.app.profile.SecondFactorPreference
import com.blanarch.app.sslvpn.SslVpnGateway
import com.blanarch.app.sso.LoopbackSsoCallback
import com.blanarch.app.state.ErrorCode
import com.blanarch.app.state.LogEvent
import com.blanarch.app.state.VpnPhase
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Thin Android shell: foreground notification, lifecycle, and wiring the
 * [ConnectionOrchestrator] to real sockets. Disconnecting cancels its job.
 *
 * Also started by the system for always-on VPN (no action, or the
 * [VpnService.SERVICE_INTERFACE] action): then it connects the active profile.
 */
class VpnTunnelService : VpnService() {
    private val graph get() = (application as BlanarchApplication).graph
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var job: Job? = null

    /** Set by Reconnect: start this profile again once the current run has ended. */
    private var restartWith: Profile? = null

    /** The tunnel was up at some point in this run, so a drop or a final failure is worth an alert. */
    private var wasUp = false
    private lateinit var notifications: VpnNotifications

    override fun onCreate() {
        super.onCreate()
        notifications = VpnNotifications(this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_DISCONNECT -> disconnect()
            ACTION_RECONNECT -> reconnect(useCode = intent.getBooleanExtra(EXTRA_USE_CODE, false))
            ACTION_SUBMIT_CODE -> submitCode(intent)
            ACTION_CONNECT -> intent.getStringExtra(EXTRA_PROFILE)?.let(graph.profiles::get)?.let(::connect)
            null, SERVICE_INTERFACE -> activeProfile()?.let {
                graph.status.log("Started by Android (always-on VPN)")
                connect(it)
            } ?: stopSelf()
        }
        return START_NOT_STICKY
    }

    private fun activeProfile(): Profile? =
        graph.prefs.activeProfileId?.let(graph.profiles::get) ?: graph.profiles.profiles.value.firstOrNull()

    private fun connect(profile: Profile) {
        if (job?.isActive == true) return
        notifications.startForeground(notifications.forPhase(profile.name, VpnPhase.CONNECTING))
        notifications.clearAlert()
        wasUp = false
        job = scope.launch {
            val notifier = launch { mirrorToNotification(profile) }
            val network = AndroidNetworkWatch(this@VpnTunnelService, log = { graph.status.log(it) }) { n ->
                // Tell Android which real network carries the tunnel, for traffic accounting and metering.
                runCatching { setUnderlyingNetworks(n?.let { arrayOf(it) }) }
            }
            try {
                val credentials = graph.credentialsFor(profile.id)
                if (credentials == null) {
                    graph.status.update {
                        it.copy(phase = VpnPhase.ERROR, connectionId = profile.id, error = ErrorCode.LOCKED)
                    }
                    graph.status.log("Unlock the app to use the saved password")
                    return@launch
                }
                withContext(Dispatchers.IO) { orchestrator(profile, network).run(profile, credentials) }
            } finally {
                notifier.cancel()
                network.close()
                if (wasUp && graph.status.status.value.phase == VpnPhase.ERROR) {
                    notifications.alert(DropAlert.GAVE_UP, profile.name)
                }
                val again = restartWith
                restartWith = null
                if (again != null) {
                    graph.status.log("Reconnecting", event = LogEvent.RECONNECTING)
                    job = null
                    connect(again)
                } else {
                    if (graph.status.status.value.phase != VpnPhase.ERROR) {
                        graph.status.update {
                            it.copy(
                                phase = VpnPhase.IDLE,
                                ip = null,
                                connectedSinceMillis = null,
                                startedMillis = null,
                                retryReason = null
                            )
                        }
                        graph.status.log("Disconnected", event = LogEvent.DISCONNECTED)
                    }
                    stopForeground(STOP_FOREGROUND_REMOVE)
                    stopSelf()
                }
            }
        }
    }

    private fun orchestrator(profile: Profile, network: NetworkWatch): ConnectionOrchestrator {
        val config = graph.config
        val log: (String) -> Unit = { graph.status.log(it) }
        val sockets = SocketFactory({ protect(it) }, config.retry.connectTimeout, config.retry.attemptTimeout)
        return ConnectionOrchestrator(
            config = config,
            gateways = { host, port -> SslVpnGateway(host, port, profile.realm, config.mru, sockets, graph.pins, log) },
            otp = DefaultOtpSessionFactory(sockets, config.otp, graph.manualOtp, log),
            tun = AndroidTunFactory(this, config.mru, log),
            sso = LoopbackSsoCallback(),
            status = graph.status,
            network = network
        )
    }

    private suspend fun mirrorToNotification(profile: Profile) {
        var previous = graph.status.status.value.phase
        graph.status.status
            .distinctUntilChanged { a, b -> a.phase == b.phase && a.ip == b.ip && a.ssoUrl == b.ssoUrl }
            .collect { s ->
                notifications.show(notifications.forStatus(profile.name, s))
                DropAlerts.on(previous, s.phase, wasUp)?.let { notifications.alert(it, profile.name) }
                if (s.phase == VpnPhase.CONNECTED) wasUp = true
                previous = s.phase
            }
    }

    /** A code typed into the notification's reply field goes to the same place as one typed in the app. */
    private fun submitCode(intent: Intent) {
        val code = RemoteInput.getResultsFromIntent(intent)?.getCharSequence(VpnNotifications.KEY_CODE)?.toString()
        if (!code.isNullOrBlank()) graph.manualOtp.submit(code)
        // Re-post so the reply field stops spinning.
        val s = graph.status.status.value
        val name = s.connectionId?.let(graph.profiles::get)?.name ?: getString(R.string.app_name)
        notifications.show(notifications.forStatus(name, s))
    }

    private fun disconnect() {
        restartWith = null
        val running = job
        if (running?.isActive == true) {
            graph.status.update { it.copy(phase = VpnPhase.DISCONNECTING) }
            running.cancel()
        } else {
            stopSelf()
        }
    }

    /** [useCode] answers this sign-in with a code instead of a push, without changing the saved profile. */
    private fun reconnect(useCode: Boolean = false) {
        val running = job
        val saved = graph.status.status.value.connectionId?.let(graph.profiles::get) ?: activeProfile() ?: return
        val profile = if (useCode) saved.copy(secondFactor = SecondFactorPreference.CODE) else saved
        if (running?.isActive == true) {
            restartWith = profile
            running.cancel()
        } else {
            connect(profile)
        }
    }

    override fun onRevoke() = disconnect()

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }

    companion object {
        const val ACTION_CONNECT = "com.blanarch.app.CONNECT"
        const val ACTION_DISCONNECT = "com.blanarch.app.DISCONNECT"
        const val ACTION_RECONNECT = "com.blanarch.app.RECONNECT"
        const val ACTION_SUBMIT_CODE = "com.blanarch.app.SUBMIT_CODE"
        const val EXTRA_PROFILE = "profile"
        const val EXTRA_USE_CODE = "useCode"
    }
}
