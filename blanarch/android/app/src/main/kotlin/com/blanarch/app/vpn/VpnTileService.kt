package com.blanarch.app.vpn

import android.annotation.SuppressLint
import android.app.PendingIntent
import android.content.Intent
import android.graphics.drawable.Icon
import android.net.VpnService
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import com.blanarch.app.BlanarchApplication
import com.blanarch.app.MainActivity
import com.blanarch.app.R
import com.blanarch.app.profile.AuthMode
import com.blanarch.app.state.VpnPhase
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.launch

/**
 * Quick Settings toggle. Connects in one tap when nothing needs the user
 * (password saved, no app lock, VPN permission granted); otherwise it opens
 * the app. While connected, a tap disconnects.
 */
class VpnTileService : TileService() {
    private val graph get() = (application as BlanarchApplication).graph
    private var watcher: Job? = null

    override fun onStartListening() {
        super.onStartListening()
        watcher = CoroutineScope(Dispatchers.Main.immediate).launch {
            combine(graph.status.status, graph.profiles.profiles) { s, p -> s to p }.collect { render() }
        }
    }

    override fun onStopListening() {
        watcher?.cancel()
        watcher = null
        super.onStopListening()
    }

    override fun onClick() {
        super.onClick()
        val status = graph.status.status.value
        if (status.phase != VpnPhase.IDLE && status.phase != VpnPhase.ERROR) {
            startService(Intent(this, VpnTunnelService::class.java).setAction(VpnTunnelService.ACTION_DISCONNECT))
            return
        }
        val profile =
            graph.prefs.activeProfileId?.let(graph.profiles::get) ?: graph.profiles.profiles.value.firstOrNull()
        val needsApp = profile == null ||
            VpnService.prepare(this) != null ||
            graph.credentials.locked ||
            (profile.authMode == AuthMode.PASSWORD && !graph.credentials.hasVpnPassword(profile.id))
        if (needsApp) {
            openApp()
        } else {
            startForegroundService(
                Intent(this, VpnTunnelService::class.java)
                    .setAction(VpnTunnelService.ACTION_CONNECT)
                    .putExtra(VpnTunnelService.EXTRA_PROFILE, profile!!.id)
            )
        }
    }

    @SuppressLint("StartActivityAndCollapseDeprecated")
    private fun openApp() {
        val intent = Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        if (Build.VERSION.SDK_INT >= 34) {
            startActivityAndCollapse(PendingIntent.getActivity(this, 0, intent, PendingIntent.FLAG_IMMUTABLE))
        } else {
            @Suppress("DEPRECATION")
            startActivityAndCollapse(intent)
        }
    }

    private fun render() {
        val tile = qsTile ?: return
        val status = graph.status.status.value
        val profiles = graph.profiles.profiles.value
        val active = graph.prefs.activeProfileId?.let(graph.profiles::get) ?: profiles.firstOrNull()
        tile.icon = Icon.createWithResource(this, R.drawable.ic_vpn)
        tile.label = active?.name ?: getString(R.string.tile_label)
        when {
            profiles.isEmpty() -> {
                tile.state = Tile.STATE_UNAVAILABLE
                tile.subtitle = getString(R.string.tile_no_connection)
            }
            status.phase == VpnPhase.CONNECTED -> {
                tile.state = Tile.STATE_ACTIVE
                tile.subtitle = getString(R.string.tile_connected)
            }
            status.phase != VpnPhase.IDLE && status.phase != VpnPhase.ERROR -> {
                tile.state = Tile.STATE_ACTIVE
                tile.subtitle = getString(R.string.tile_connecting)
            }
            else -> {
                tile.state = Tile.STATE_INACTIVE
                tile.subtitle = getString(R.string.tile_off)
            }
        }
        tile.updateTile()
    }
}
