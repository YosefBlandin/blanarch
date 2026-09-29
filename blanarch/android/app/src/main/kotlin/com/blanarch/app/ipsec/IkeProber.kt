package com.blanarch.app.ipsec

import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.SocketTimeoutException
import java.security.SecureRandom
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** Sends the IKEv2 probe (fortigate-ipsec.md §2) and waits briefly for any IKEv2 reply. */
class IkeProber(private val timeoutMillis: Int = 3_000, private val port: Int = 500) {
    private val random = SecureRandom()

    suspend fun answers(host: String): Boolean = withContext(Dispatchers.IO) {
        val spi = ByteArray(8).also { do random.nextBytes(it) while (it.all { b -> b.toInt() == 0 }) }
        val request = IkeProbeMessage.request(
            spi,
            ByteArray(256).also(random::nextBytes),
            ByteArray(32).also(random::nextBytes)
        )
        runCatching {
            DatagramSocket().use { socket ->
                socket.soTimeout = timeoutMillis
                socket.send(DatagramPacket(request, request.size, InetAddress.getByName(host), port))
                val buffer = ByteArray(2048)
                val deadline = System.currentTimeMillis() + timeoutMillis
                while (System.currentTimeMillis() < deadline) {
                    val packet = DatagramPacket(buffer, buffer.size)
                    try {
                        socket.receive(packet)
                    } catch (_: SocketTimeoutException) {
                        break
                    }
                    if (IkeProbeMessage.isIkeReply(buffer.copyOf(packet.length), spi)) return@use true
                }
                false
            }
        }.getOrDefault(false)
    }
}
