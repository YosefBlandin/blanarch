package com.blanarch.app.vpn

import com.blanarch.app.state.VpnPhase
import org.junit.Assert.assertEquals
import org.junit.Test

class DropAlertsTest {
    @Test fun `a drop while connected alerts, whether it rejoins or waits for a network`() {
        assertEquals(DropAlert.DROPPED, DropAlerts.on(VpnPhase.CONNECTED, VpnPhase.RECONNECTING, wasUp = true))
        assertEquals(DropAlert.DROPPED, DropAlerts.on(VpnPhase.CONNECTED, VpnPhase.WAITING_NETWORK, wasUp = true))
    }

    @Test fun `coming back after a drop says reconnected, but the first connection does not`() {
        assertEquals(DropAlert.RECONNECTED, DropAlerts.on(VpnPhase.NEGOTIATING, VpnPhase.CONNECTED, wasUp = true))
        assertEquals(null, DropAlerts.on(VpnPhase.NEGOTIATING, VpnPhase.CONNECTED, wasUp = false))
    }

    @Test fun `giving up after having been connected alerts, a first failure only shows in the app`() {
        assertEquals(DropAlert.GAVE_UP, DropAlerts.on(VpnPhase.CONNECTING, VpnPhase.ERROR, wasUp = true))
        assertEquals(null, DropAlerts.on(VpnPhase.CONNECTING, VpnPhase.ERROR, wasUp = false))
    }

    @Test fun `disconnecting on purpose is not a drop`() {
        assertEquals(null, DropAlerts.on(VpnPhase.CONNECTED, VpnPhase.DISCONNECTING, wasUp = true))
    }
}
