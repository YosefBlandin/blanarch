package com.blanarch.app.sslvpn

import com.blanarch.app.state.ErrorCode
import com.blanarch.app.state.VpnException
import com.blanarch.app.vpn.IpConfig
import com.blanarch.app.vpn.TunDevice
import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.io.OutputStream
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import kotlin.concurrent.thread
import kotlin.time.Duration.Companion.seconds
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

/** Drives [SslVpnLink] over loopback TCP against a small scripted gateway. */
class SslVpnLinkTest {
    private val ipv4In = hex("45 00 00 14 00 01 00 00 40 11 00 00 0A 00 00 01 0A D4 86 07")
    private val ipv4Out = hex("45 00 00 14 00 02 00 00 40 06 00 00 0A D4 86 07 0A 00 00 01")

    private class QueueTun : TunDevice {
        val packets = LinkedBlockingQueue<ByteArray>()
        val written = LinkedBlockingQueue<ByteArray>()

        @Volatile var closed = false

        override val input: InputStream = object : InputStream() {
            override fun read(): Int = throw UnsupportedOperationException()
            override fun read(b: ByteArray, off: Int, len: Int): Int {
                while (!closed) {
                    val p = packets.poll(50, TimeUnit.MILLISECONDS) ?: continue
                    p.copyInto(b, off)
                    return p.size
                }
                return -1
            }
        }
        override val output: OutputStream = object : OutputStream() {
            override fun write(b: Int) = throw UnsupportedOperationException()
            override fun write(b: ByteArray) {
                written += b.copyOf()
            }
        }

        override fun close() {
            closed = true
        }
    }

    private fun control(protocol: Int, code: Int, id: Int, data: ByteArray) =
        FrameCodec.encode(ControlPacket(code, id, data).toPayload(protocol))

    /** A gateway that negotiates per spec §6, sends one IPv4 packet, waits for one, then terminates. */
    private fun scriptedGateway(server: ServerSocket, received: MutableList<ByteArray>) = thread {
        server.accept().use { s ->
            val out = s.getOutputStream()
            val frames = FrameReader(s.getInputStream())
            out.write(control(Ppp.LCP, Ppp.CONF_REQ, 1, PppOption.encodeAll(listOf(PppOption(5, hex("11 22 33 44"))))))
            while (true) {
                val payload = frames.read() ?: break
                received += payload
                val proto = Ppp.protocolOf(payload)
                if (proto == Ppp.IPV4) {
                    out.write(control(Ppp.LCP, Ppp.TERM_REQ, 9, ByteArray(0)))
                    continue
                }
                val p = ControlPacket.parse(payload.copyOfRange(2, payload.size))!!
                when {
                    proto == Ppp.LCP && p.code == Ppp.CONF_REQ -> out.write(
                        control(Ppp.LCP, Ppp.CONF_ACK, p.id, p.data)
                    )
                    proto == Ppp.LCP && p.code == Ppp.TERM_ACK -> break
                    proto == Ppp.IPCP && p.code == Ppp.CONF_REQ -> {
                        val options = PppOption.parseAll(p.data)!!
                        if (options.first { it.type == 3 }.value.all { it.toInt() == 0 }) {
                            out.write(control(Ppp.IPCP, Ppp.CONF_REQ, 1, PppOption(3, hex("0A 00 00 01")).encode()))
                            val nak = listOf(
                                PppOption(3, hex("0A D4 86 07")),
                                PppOption(129, hex("0A 00 00 35")),
                                PppOption(131, hex("0A 00 00 36"))
                            )
                            out.write(control(Ppp.IPCP, Ppp.CONF_NAK, p.id, PppOption.encodeAll(nak)))
                        } else {
                            out.write(control(Ppp.IPCP, Ppp.CONF_ACK, p.id, p.data))
                            out.write(FrameCodec.encode(Ppp.payload(Ppp.IPV4, ipv4In)))
                        }
                    }
                }
                out.flush()
            }
        }
    }

    @Test
    fun `negotiates, forwards packets both ways and ends on terminate`() = runBlocking {
        ServerSocket(0, 1, InetAddress.getLoopbackAddress()).use { server ->
            val received = java.util.Collections.synchronizedList(mutableListOf<ByteArray>())
            val gw = scriptedGateway(server, received)
            val link = SslVpnLink(Socket(server.inetAddress, server.localPort), 1354, {})
            link.use {
                val ip = withTimeout(10_000) { link.negotiate(10.seconds) }
                assertEquals(IpConfig("10.212.134.7", listOf("10.0.0.53", "10.0.0.54")), ip)
                val tun = QueueTun()
                tun.packets += ipv4Out
                val reason = withTimeout(10_000) { link.pump(tun) }
                assertEquals("gateway ended the session", reason)
                assertArrayEquals(ipv4In, tun.written.poll(1, TimeUnit.SECONDS))
            }
            gw.join(5_000)
            val sentIpv4 = received.filter { Ppp.protocolOf(it) == Ppp.IPV4 }
            assertEquals(1, sentIpv4.size)
            assertArrayEquals(ipv4Out, sentIpv4[0].copyOfRange(2, sentIpv4[0].size))
            assertTrue(received.any { Ppp.protocolOf(it) == Ppp.LCP && it[2] == Ppp.TERM_ACK.toByte() })
        }
    }

    @Test
    fun `http response instead of frames is tunnel refused`() {
        ServerSocket(0, 1, InetAddress.getLoopbackAddress()).use { server ->
            val gw = thread {
                server.accept().use { s ->
                    s.getOutputStream().write("HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\n\r\n".toByteArray())
                    s.getInputStream().read(ByteArray(64))
                }
            }
            val link = SslVpnLink(Socket(server.inetAddress, server.localPort), 1354, {})
            val e = assertThrows(VpnException::class.java) {
                runBlocking { withTimeout(10_000) { link.negotiate(10.seconds) } }
            }
            assertEquals(ErrorCode.TUNNEL_REFUSED, e.code)
            link.close()
            gw.join(5_000)
        }
    }

    @Test
    fun `silent gateway makes negotiation time out as a protocol error`() {
        ServerSocket(0, 1, InetAddress.getLoopbackAddress()).use { server ->
            val sink = ByteArrayOutputStream()
            val gw = thread {
                server.accept().use { s -> s.getInputStream().copyTo(sink) }
            }
            val link = SslVpnLink(Socket(server.inetAddress, server.localPort), 1354, {})
            val e = assertThrows(VpnException::class.java) {
                runBlocking { link.negotiate(1.seconds) }
            }
            assertEquals(ErrorCode.PROTOCOL, e.code)
            link.close()
            gw.join(5_000)
        }
    }
}
