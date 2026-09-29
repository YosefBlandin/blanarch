package com.blanarch.app.vpn

import com.blanarch.app.state.VpnPhase

/** What the "Connection alerts" notification says. */
enum class DropAlert { DROPPED, RECONNECTED, GAVE_UP }

/** Decides when to alert the user about a drop. Pure, so each case is unit-tested. */
object DropAlerts {
    /** [wasUp]: the tunnel was connected earlier in this run (so a drop is news, not a first failure). */
    fun on(previous: VpnPhase, next: VpnPhase, wasUp: Boolean): DropAlert? = when {
        previous == VpnPhase.CONNECTED && next in DROPS -> DropAlert.DROPPED
        next == VpnPhase.CONNECTED && previous != VpnPhase.CONNECTED && wasUp -> DropAlert.RECONNECTED
        next == VpnPhase.ERROR && wasUp -> DropAlert.GAVE_UP
        else -> null
    }

    private val DROPS = setOf(VpnPhase.RECONNECTING, VpnPhase.WAITING_NETWORK)
}
