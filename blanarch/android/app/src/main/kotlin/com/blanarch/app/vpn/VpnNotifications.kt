package com.blanarch.app.vpn

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.RemoteInput
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.Uri
import android.os.Build
import com.blanarch.app.MainActivity
import com.blanarch.app.R
import com.blanarch.app.state.VpnPhase
import com.blanarch.app.state.VpnStatus

/**
 * Two notifications:
 * - the ongoing status one, whose text says what the user has to do. While a code is
 *   needed it has an inline reply field; during single sign-on it opens the sign-in
 *   page. Actions: Disconnect, plus Reconnect while connected.
 * - "Connection alerts" for drops: dropped, reconnected, or gave up (tap to reconnect).
 */
class VpnNotifications(private val service: Service) {
    private val manager = service.getSystemService(NotificationManager::class.java)

    init {
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL, service.getString(R.string.notif_channel), NotificationManager.IMPORTANCE_LOW)
        )
        manager.createNotificationChannel(
            NotificationChannel(
                ALERTS,
                service.getString(R.string.notif_alert_channel),
                NotificationManager.IMPORTANCE_HIGH
            )
        )
    }

    fun forStatus(profileName: String, status: VpnStatus): Notification {
        val text = when (status.phase) {
            VpnPhase.CONNECTED -> service.getString(R.string.notif_connected, profileName, status.ip ?: "")
            VpnPhase.WAITING_OTP -> service.getString(R.string.notif_enter_code)
            VpnPhase.WAITING_PUSH -> service.getString(R.string.notif_approve_push)
            VpnPhase.WAITING_SSO -> service.getString(R.string.notif_finish_sso)
            VpnPhase.RECONNECTING -> service.getString(R.string.notif_reconnecting, profileName)
            VpnPhase.WAITING_NETWORK -> service.getString(R.string.notif_waiting_network)
            else -> service.getString(R.string.notif_connecting, profileName)
        }
        return build(text) {
            when (status.phase) {
                VpnPhase.CONNECTED -> addAction(action(2, VpnTunnelService.ACTION_RECONNECT, R.string.notif_reconnect))
                VpnPhase.WAITING_OTP -> addAction(codeReply())
                VpnPhase.WAITING_SSO -> status.ssoUrl?.let { addAction(openPage(it)) }
                else -> Unit
            }
        }
    }

    fun forPhase(profileName: String, phase: VpnPhase): Notification = forStatus(profileName, VpnStatus(phase = phase))

    fun startForeground(notification: Notification) {
        if (Build.VERSION.SDK_INT >= 34) {
            service.startForeground(ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SYSTEM_EXEMPTED)
        } else {
            service.startForeground(ID, notification)
        }
    }

    fun show(notification: Notification) = manager.notify(ID, notification)

    /** Posts or updates the alert. Updates don't buzz again, and "Reconnected" clears itself. */
    fun alert(kind: DropAlert, profileName: String) {
        val builder = Notification.Builder(service, ALERTS)
            .setSmallIcon(R.drawable.ic_vpn)
            .setContentTitle(service.getString(R.string.app_name))
            .setOnlyAlertOnce(true)
            .setAutoCancel(true)
            .setContentIntent(openApp())
        when (kind) {
            DropAlert.DROPPED -> builder.setContentText(service.getString(R.string.notif_dropped, profileName))
            DropAlert.RECONNECTED ->
                builder
                    .setContentText(service.getString(R.string.notif_reconnected, profileName))
                    .setTimeoutAfter(RECONNECTED_VISIBLE_MILLIS)
            DropAlert.GAVE_UP ->
                builder
                    .setContentText(service.getString(R.string.notif_gave_up, profileName))
                    .setContentIntent(reconnectFromStopped())
                    .addAction(
                        Notification.Action.Builder(
                            null,
                            service.getString(R.string.notif_reconnect),
                            reconnectFromStopped()
                        ).build()
                    )
        }
        manager.notify(ALERT_ID, builder.build())
    }

    fun clearAlert() = manager.cancel(ALERT_ID)

    private fun action(requestCode: Int, action: String, label: Int): Notification.Action {
        val intent = PendingIntent.getService(
            service,
            requestCode,
            Intent(service, VpnTunnelService::class.java).setAction(action),
            PendingIntent.FLAG_IMMUTABLE
        )
        return Notification.Action.Builder(null, service.getString(label), intent).build()
    }

    /** Type the code right in the notification. Mutable, so Android can attach the typed text. */
    private fun codeReply(): Notification.Action {
        val input = RemoteInput.Builder(KEY_CODE).setLabel(service.getString(R.string.notif_code_hint)).build()
        val intent = PendingIntent.getService(
            service,
            3,
            Intent(service, VpnTunnelService::class.java).setAction(VpnTunnelService.ACTION_SUBMIT_CODE),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
        )
        return Notification.Action.Builder(null, service.getString(R.string.notif_enter_code_action), intent)
            .addRemoteInput(input)
            .build()
    }

    private fun openPage(url: String): Notification.Action {
        val intent = PendingIntent.getActivity(
            service,
            4,
            Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_IMMUTABLE
        )
        return Notification.Action.Builder(null, service.getString(R.string.notif_open_sign_in), intent).build()
    }

    /** The service has stopped by then, so it must be started again as a foreground service. */
    private fun reconnectFromStopped(): PendingIntent = PendingIntent.getForegroundService(
        service,
        5,
        Intent(service, VpnTunnelService::class.java).setAction(VpnTunnelService.ACTION_RECONNECT),
        PendingIntent.FLAG_IMMUTABLE
    )

    private fun openApp() = PendingIntent.getActivity(
        service,
        0,
        Intent(service, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
        PendingIntent.FLAG_IMMUTABLE
    )

    private fun build(text: String, extra: Notification.Builder.() -> Unit): Notification =
        Notification.Builder(service, CHANNEL)
            .setSmallIcon(R.drawable.ic_vpn)
            .setContentTitle(service.getString(R.string.app_name))
            .setContentText(text)
            .setStyle(Notification.BigTextStyle().bigText(text))
            .setContentIntent(openApp())
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .apply(extra)
            .addAction(action(1, VpnTunnelService.ACTION_DISCONNECT, R.string.notif_disconnect))
            .build()

    companion object {
        const val KEY_CODE = "code"
        private const val ID = 1
        private const val ALERT_ID = 2
        private const val CHANNEL = "vpn"
        private const val ALERTS = "alerts"
        private const val RECONNECTED_VISIBLE_MILLIS = 5_000L
    }
}
