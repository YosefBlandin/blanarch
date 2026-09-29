package com.blanarch.app

import android.Manifest
import android.app.KeyguardManager
import android.app.StatusBarManager
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.drawable.Icon
import android.net.Uri
import android.net.VpnService
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import androidx.biometric.BiometricManager.Authenticators.BIOMETRIC_STRONG
import androidx.biometric.BiometricManager.Authenticators.DEVICE_CREDENTIAL
import androidx.biometric.BiometricPrompt
import androidx.browser.customtabs.CustomTabsIntent
import androidx.core.content.ContextCompat
import com.blanarch.app.bridge.VpnBridge
import com.blanarch.app.bridge.VpnHost
import com.blanarch.app.vpn.VpnTileService
import com.blanarch.app.vpn.VpnTunnelService
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import kotlinx.coroutines.CompletableDeferred

/**
 * Hosts the Flutter UI and answers the bridge's platform requests: permissions,
 * unlocking, the browser, the Quick Settings tile and setup links.
 * A FragmentActivity so it can show the system biometric prompt.
 */
class MainActivity :
    FlutterFragmentActivity(),
    VpnHost {
    private val graph get() = (application as BlanarchApplication).graph
    private var bridge: VpnBridge? = null
    private var vpnConsent: CompletableDeferred<Boolean>? = null
    private var notificationGrant: CompletableDeferred<Boolean>? = null
    private var pendingLink: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        pendingLink = setupLinkFrom(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setupLinkFrom(intent)?.let { link ->
            pendingLink = link
            bridge?.deliverSetupLink(link)
        }
    }

    private fun setupLinkFrom(intent: Intent?): String? =
        intent?.data?.takeIf { it.scheme == SETUP_SCHEME && it.host == "add" }?.toString()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        bridge = VpnBridge(graph, this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        bridge?.dispose(flutterEngine.dartExecutor.binaryMessenger)
        bridge = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun takeSetupLink(): String? = pendingLink.also { pendingLink = null }

    override suspend fun requestVpnConsent(): Boolean {
        val intent = VpnService.prepare(this) ?: return true
        val result = CompletableDeferred<Boolean>().also { vpnConsent = it }
        @Suppress("DEPRECATION")
        startActivityForResult(intent, REQUEST_VPN)
        return result.await()
    }

    override suspend fun requestNotificationPermission(): Boolean {
        if (Build.VERSION.SDK_INT < 33 ||
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        ) {
            return true
        }
        val result = CompletableDeferred<Boolean>().also { notificationGrant = it }
        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQUEST_NOTIFICATIONS)
        return result.await()
    }

    override fun deviceSecure(): Boolean = getSystemService(KeyguardManager::class.java).isDeviceSecure

    override suspend fun authenticate(): Boolean {
        val result = CompletableDeferred<Boolean>()
        val prompt = BiometricPrompt(
            this,
            ContextCompat.getMainExecutor(this),
            object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(r: BiometricPrompt.AuthenticationResult) {
                    result.complete(true)
                }

                override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                    result.complete(false)
                }
            }
        )
        val info = BiometricPrompt.PromptInfo.Builder()
            .setTitle(getString(R.string.unlock_title))
            .setSubtitle(getString(R.string.unlock_subtitle))
            .apply {
                if (Build.VERSION.SDK_INT >= 30) {
                    setAllowedAuthenticators(BIOMETRIC_STRONG or DEVICE_CREDENTIAL)
                } else {
                    @Suppress("DEPRECATION")
                    setDeviceCredentialAllowed(true)
                }
            }
            .build()
        prompt.authenticate(info)
        return result.await()
    }

    override fun canAddTile() = Build.VERSION.SDK_INT >= 33

    override fun requestAddTile(always: Boolean) {
        if (Build.VERSION.SDK_INT < 33 || (graph.prefs.tileOffered && !always)) return
        graph.prefs.tileOffered = true
        getSystemService(StatusBarManager::class.java).requestAddTileService(
            ComponentName(this, VpnTileService::class.java),
            getString(R.string.tile_label),
            Icon.createWithResource(this, R.drawable.ic_vpn),
            mainExecutor
        ) { }
    }

    override fun openVpnSettings() {
        startActivity(Intent(Settings.ACTION_VPN_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    override fun startVpn(profileId: String) {
        startForegroundService(
            Intent(this, VpnTunnelService::class.java)
                .setAction(VpnTunnelService.ACTION_CONNECT)
                .putExtra(VpnTunnelService.EXTRA_PROFILE, profileId)
        )
    }

    override fun restartVpnWithCode() {
        startService(
            Intent(this, VpnTunnelService::class.java)
                .setAction(VpnTunnelService.ACTION_RECONNECT)
                .putExtra(VpnTunnelService.EXTRA_USE_CODE, true)
        )
    }

    override fun stopVpn() {
        startService(Intent(this, VpnTunnelService::class.java).setAction(VpnTunnelService.ACTION_DISCONNECT))
    }

    override fun openBrowser(url: String) {
        CustomTabsIntent.Builder().setShowTitle(true).build().launchUrl(this, Uri.parse(url))
    }

    override fun shareText(subject: String, text: String) {
        val send = Intent(Intent.ACTION_SEND)
            .setType("text/plain")
            .putExtra(Intent.EXTRA_SUBJECT, subject)
            .putExtra(Intent.EXTRA_TEXT, text)
        startActivity(Intent.createChooser(send, subject))
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_VPN) {
            vpnConsent?.complete(resultCode == RESULT_OK)
            vpnConsent = null
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_NOTIFICATIONS) {
            notificationGrant?.complete(grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED)
            notificationGrant = null
        }
    }

    private companion object {
        const val REQUEST_VPN = 1
        const val REQUEST_NOTIFICATIONS = 2
        const val SETUP_SCHEME = "blanarch"
    }
}
