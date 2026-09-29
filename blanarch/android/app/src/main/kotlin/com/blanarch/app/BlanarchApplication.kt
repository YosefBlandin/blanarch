package com.blanarch.app

import android.app.Application
import android.content.Context
import com.blanarch.app.config.VpnConfig
import com.blanarch.app.ipsec.IkeProber
import com.blanarch.app.mail.ImapClient
import com.blanarch.app.net.SocketFactory
import com.blanarch.app.net.closeQuietly
import com.blanarch.app.otp.ManualOtpInbox
import com.blanarch.app.profile.EmailOtpSource
import com.blanarch.app.profile.PrefsProfileStore
import com.blanarch.app.profile.ProfileStore
import com.blanarch.app.security.CredentialStore
import com.blanarch.app.security.CredentialsLockedException
import com.blanarch.app.security.KeystoreCredentialStore
import com.blanarch.app.security.PinStore
import com.blanarch.app.security.PrefsPinStore
import com.blanarch.app.sslvpn.SslVpnProber
import com.blanarch.app.state.ErrorCode
import com.blanarch.app.state.StatusStore
import com.blanarch.app.state.VpnException
import com.blanarch.app.vpn.Credentials
import com.blanarch.app.vpn.GatewayProber

/** Composition root: the process-wide objects shared by the activity and the VPN service. */
class AppGraph(context: Context) {
    val config: VpnConfig = VpnConfig.parse(
        context.resources.openRawResource(R.raw.vpn_config).bufferedReader().use { it.readText() }
    )
    val status = StatusStore()
    val manualOtp = ManualOtpInbox()
    val profiles: ProfileStore = PrefsProfileStore(context)
    val credentials: CredentialStore = KeystoreCredentialStore(context)
    val pins: PinStore = PrefsPinStore(context)
    val prefs = UiPrefs(context)

    /** Sockets for work done outside the tunnel before it exists (probe, mailbox check). */
    private val directSockets = SocketFactory({ true }, config.retry.connectTimeout, config.retry.attemptTimeout)
    val prober: GatewayProber = SslVpnProber(directSockets)
    val ikeProber = IkeProber()

    /** The saved passwords for a profile, or null when the app lock needs the user to unlock first. */
    fun credentialsFor(profileId: String): Credentials? = try {
        Credentials(credentials.vpnPassword(profileId), credentials.emailPassword(profileId))
    } catch (_: CredentialsLockedException) {
        null
    }

    /** Logs in to the mailbox once to check a password. Null means it worked. */
    suspend fun checkEmailPassword(source: EmailOtpSource, password: String): ErrorCode? = try {
        ImapClient.open(directSockets, source, password).closeQuietly()
        null
    } catch (e: VpnException) {
        e.code
    }
}

/** Small UI preferences the Flutter side reads and writes. */
class UiPrefs(context: Context) {
    private val prefs = context.getSharedPreferences("ui", Context.MODE_PRIVATE)

    var themeMode: String
        get() = prefs.getString("themeMode", "system") ?: "system"
        set(v) = prefs.edit().putString("themeMode", v).apply()

    var onboarded: Boolean
        get() = prefs.getBoolean("onboarded", false)
        set(v) = prefs.edit().putBoolean("onboarded", v).apply()

    /** The Quick Settings tile was already offered once. */
    var tileOffered: Boolean
        get() = prefs.getBoolean("tileOffered", false)
        set(v) = prefs.edit().putBoolean("tileOffered", v).apply()

    var activeProfileId: String?
        get() = prefs.getString("activeProfile", null)
        set(v) = prefs.edit().putString("activeProfile", v).apply()
}

class BlanarchApplication : Application() {
    lateinit var graph: AppGraph
        private set

    override fun onCreate() {
        super.onCreate()
        graph = AppGraph(this)
    }
}
