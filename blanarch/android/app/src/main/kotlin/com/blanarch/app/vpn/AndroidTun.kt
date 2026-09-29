package com.blanarch.app.vpn

import android.app.PendingIntent
import android.content.Intent
import android.net.VpnService
import android.os.ParcelFileDescriptor
import com.blanarch.app.MainActivity
import com.blanarch.app.state.ErrorCode
import com.blanarch.app.state.VpnException
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.InputStream
import java.io.OutputStream

/** Creates the real TUN interface through VpnService.Builder. */
class AndroidTunFactory(private val service: VpnService, private val mtu: Int, private val log: (String) -> Unit) :
    TunFactory {
    override fun establish(ip: IpConfig, config: TunnelConfig, sessionName: String): TunDevice {
        val dns = ip.dns
        val builder = service.Builder()
            .setSession(sessionName)
            .setMtu(mtu)
            .addAddress(ip.ip, 32)
            .setBlocking(true)
            .setConfigureIntent(
                PendingIntent.getActivity(
                    service,
                    0,
                    Intent(service, MainActivity::class.java),
                    PendingIntent.FLAG_IMMUTABLE
                )
            )
        // A full tunnel without DNS would leak queries to the phone network's servers.
        val added = dns.count { runCatching { builder.addDnsServer(it) }.isSuccess }
        if (added == 0 && Routes.isFullTunnel(config)) throw VpnException(ErrorCode.PROTOCOL, "no usable DNS server")
        Routes.searchDomains(config.dnsSuffix).forEach { runCatching { builder.addSearchDomain(it) } }
        Routes.plan(config, dns).forEach { r ->
            runCatching {
                builder.addRoute(r.address, r.prefix)
            }.onFailure { log("Skipped route ${r.address}/${r.prefix}") }
        }
        val fd = builder.establish() ?: throw VpnException(ErrorCode.PERMISSION_REVOKED)
        return FdTunDevice(fd)
    }
}

private class FdTunDevice(private val fd: ParcelFileDescriptor) : TunDevice {
    override val input: InputStream = FileInputStream(fd.fileDescriptor)
    override val output: OutputStream = FileOutputStream(fd.fileDescriptor)
    override fun close() = fd.close()
}
