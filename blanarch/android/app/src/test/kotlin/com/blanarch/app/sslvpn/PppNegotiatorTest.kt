package com.blanarch.app.sslvpn

import com.blanarch.app.vpn.IpConfig
import kotlin.random.Random
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PppNegotiatorTest {
    private val peerMagic = hex("11 22 33 44")

    private fun n() = PppNegotiator(1354, Random(42))

    private fun packet(protocol: Int, code: Int, id: Int, data: ByteArray = ByteArray(0)) =
        ControlPacket(code, id, data).toPayload(protocol)

    private fun opt(type: Int, value: String = "") = PppOption(type, hex(value))

    private fun opts(vararg o: PppOption) = PppOption.encodeAll(o.toList())

    /** Splits a sent payload into protocol and control packet. */
    private fun decode(payload: ByteArray): Pair<Int, ControlPacket> =
        Ppp.protocolOf(payload) to ControlPacket.parse(payload.copyOfRange(2, payload.size))!!

    private fun optionMap(p: ControlPacket) = PppOption.parseAll(p.data)!!.associate { it.type to it.value.toList() }

    private fun single(sent: List<ByteArray>): Pair<Int, ControlPacket> {
        assertEquals(1, sent.size)
        return decode(sent[0])
    }

    /** Brings LCP up; returns the IPCP Configure-Request it triggers. */
    private fun openLcp(n: PppNegotiator): ControlPacket {
        val (_, req) = single(n.start(0))
        n.receive(packet(Ppp.LCP, Ppp.CONF_REQ, 1, opts(opt(1, "05 4A"), opt(5, "11 22 33 44"))), 0)
        val (proto, ipcpReq) = single(n.receive(packet(Ppp.LCP, Ppp.CONF_ACK, req.id, req.data), 0).send)
        assertTrue(n.lcpOpen)
        assertEquals(Ppp.IPCP, proto)
        return ipcpReq
    }

    /** Full negotiation of spec §6.2: Nak with real values, re-request, Ack. */
    private fun openAll(n: PppNegotiator): IpConfig {
        val first = openLcp(n)
        n.receive(packet(Ppp.IPCP, Ppp.CONF_REQ, 1, opts(opt(3, "0A 00 00 01"))), 0)
        val nak = opts(opt(3, "0A D4 86 07"), opt(129, "0A 00 00 35"), opt(131, "0A 00 00 36"))
        val (_, second) = single(n.receive(packet(Ppp.IPCP, Ppp.CONF_NAK, first.id, nak), 0).send)
        n.receive(packet(Ppp.IPCP, Ppp.CONF_ACK, second.id, second.data), 0)
        return n.ipConfig!!
    }

    @Test
    fun `lcp request carries mru 1354 and a magic number`() {
        val (proto, p) = single(n().start(0))
        assertEquals(Ppp.LCP, proto)
        assertEquals(Ppp.CONF_REQ, p.code)
        val o = optionMap(p)
        assertEquals(hex("05 4A").toList(), o[1])
        assertEquals(4, o[5]!!.size)
        assertEquals(setOf(1, 5), o.keys)
    }

    @Test
    fun `lcp request is resent every 3 s with a new identifier`() {
        val n = n()
        val (_, first) = single(n.start(0))
        assertTrue(n.tick(2_999).isEmpty())
        val (_, again) = single(n.tick(3_000))
        assertEquals(Ppp.CONF_REQ, again.code)
        assertNotEquals(first.id, again.id)
    }

    @Test
    fun `peer request with mru accm and magic is acked verbatim`() {
        val n = n()
        n.start(0)
        val data = opts(opt(1, "05 DC"), opt(2, "00 00 00 00"), opt(5, "11 22 33 44"))
        val (proto, ack) = single(n.receive(packet(Ppp.LCP, Ppp.CONF_REQ, 9, data), 0).send)
        assertEquals(Ppp.LCP, proto)
        assertEquals(Ppp.CONF_ACK, ack.code)
        assertEquals(9, ack.id)
        assertArrayEquals(data, ack.data)
    }

    @Test
    fun `peer request with auth pfc and acfc gets exactly those rejected`() {
        val n = n()
        n.start(0)
        val data = opts(opt(1, "05 DC"), opt(3, "C0 23"), opt(5, "11 22 33 44"), opt(7), opt(8))
        val (_, rej) = single(n.receive(packet(Ppp.LCP, Ppp.CONF_REQ, 4, data), 0).send)
        assertEquals(Ppp.CONF_REJ, rej.code)
        assertEquals(4, rej.id)
        assertArrayEquals(opts(opt(3, "C0 23"), opt(7), opt(8)), rej.data)
        assertFalse(n.lcpOpen)
    }

    @Test
    fun `lcp nak adopts the mru and picks a new magic`() {
        val n = n()
        val (_, first) = single(n.start(0))
        val oldMagic = optionMap(first)[5]
        val nak = opts(opt(1, "05 78"), opt(5, "00 00 00 01"))
        val (_, second) = single(n.receive(packet(Ppp.LCP, Ppp.CONF_NAK, first.id, nak), 0).send)
        assertNotEquals(first.id, second.id)
        val o = optionMap(second)
        assertEquals(hex("05 78").toList(), o[1])
        assertNotEquals(oldMagic, o[5])
    }

    @Test
    fun `lcp reject drops the rejected option`() {
        val n = n()
        val (_, first) = single(n.start(0))
        val (_, second) = single(
            n.receive(packet(Ppp.LCP, Ppp.CONF_REJ, first.id, opts(opt(5, "00 00 00 00"))), 0).send
        )
        assertEquals(setOf(1), optionMap(second).keys)
    }

    @Test
    fun `lcp opens only when both sides acked`() {
        val n = n()
        val (_, req) = single(n.start(0))
        assertTrue(n.receive(packet(Ppp.LCP, Ppp.CONF_ACK, req.id, req.data), 0).send.isEmpty())
        assertFalse(n.lcpOpen)
        val sent = n.receive(packet(Ppp.LCP, Ppp.CONF_REQ, 1, opts(opt(5, "11 22 33 44"))), 0).send
        assertEquals(2, sent.size) // our Ack, then the IPCP request
        assertEquals(Ppp.CONF_ACK, decode(sent[0]).second.code)
        assertEquals(Ppp.IPCP, decode(sent[1]).first)
        assertTrue(n.lcpOpen)
    }

    @Test
    fun `ipcp starts with zero address and dns`() {
        val req = openLcp(n())
        assertEquals(Ppp.CONF_REQ, req.code)
        assertArrayEquals(opts(opt(3, "00 00 00 00"), opt(129, "00 00 00 00"), opt(131, "00 00 00 00")), req.data)
    }

    @Test
    fun `ipcp nak then ack brings the link up with address and dns`() {
        val n = n()
        assertEquals(IpConfig("10.212.134.7", listOf("10.0.0.53", "10.0.0.54")), openAll(n))
        assertTrue(n.ipcpOpen)
    }

    @Test
    fun `ipcp re-request carries the nak values with a new identifier`() {
        val n = n()
        val first = openLcp(n)
        val nak = opts(opt(3, "0A D4 86 07"), opt(129, "0A 00 00 35"), opt(131, "0A 00 00 36"))
        val (_, second) = single(n.receive(packet(Ppp.IPCP, Ppp.CONF_NAK, first.id, nak), 0).send)
        assertNotEquals(first.id, second.id)
        assertArrayEquals(nak, second.data)
    }

    @Test
    fun `ipcp dns reject is dropped and the link comes up without dns`() {
        val n = n()
        val first = openLcp(n)
        n.receive(packet(Ppp.IPCP, Ppp.CONF_REQ, 1, opts(opt(3, "0A 00 00 01"))), 0)
        val rej = opts(opt(129, "00 00 00 00"), opt(131, "00 00 00 00"))
        val (_, second) = single(n.receive(packet(Ppp.IPCP, Ppp.CONF_REJ, first.id, rej), 0).send)
        assertArrayEquals(opts(opt(3, "00 00 00 00")), second.data)
        val (_, third) = single(
            n.receive(packet(Ppp.IPCP, Ppp.CONF_NAK, second.id, opts(opt(3, "0A 01 02 03"))), 0).send
        )
        n.receive(packet(Ppp.IPCP, Ppp.CONF_ACK, third.id, third.data), 0)
        assertEquals(IpConfig("10.1.2.3", emptyList()), n.ipConfig)
    }

    @Test
    fun `gateway ipcp request with compression is rejected`() {
        val n = n()
        openLcp(n)
        val data = opts(opt(2, "00 2D 0F 01"), opt(3, "0A 00 00 01"))
        val (proto, rej) = single(n.receive(packet(Ppp.IPCP, Ppp.CONF_REQ, 6, data), 0).send)
        assertEquals(Ppp.IPCP, proto)
        assertEquals(Ppp.CONF_REJ, rej.code)
        assertEquals(6, rej.id)
        assertArrayEquals(opts(opt(2, "00 2D 0F 01")), rej.data)
    }

    @Test
    fun `echo request is answered with our magic and the rest of its data`() {
        val n = n()
        openLcp(n)
        val (proto, reply) = single(n.receive(packet(Ppp.LCP, Ppp.ECHO_REQ, 7, peerMagic + hex("AA BB")), 0).send)
        assertEquals(Ppp.LCP, proto)
        assertEquals(Ppp.ECHO_REPLY, reply.code)
        assertEquals(7, reply.id)
        assertArrayEquals(n.magic + hex("AA BB"), reply.data)
    }

    @Test
    fun `echo request before lcp opens is ignored`() {
        val n = n()
        n.start(0)
        assertTrue(n.receive(packet(Ppp.LCP, Ppp.ECHO_REQ, 7, peerMagic), 0).send.isEmpty())
    }

    @Test
    fun `terminate request is acked and ends the session`() {
        val n = n()
        openAll(n)
        val (proto, ack) = single(n.receive(packet(Ppp.LCP, Ppp.TERM_REQ, 3, hex("41")), 0).send)
        assertEquals(Ppp.LCP, proto)
        assertEquals(Ppp.TERM_ACK, ack.code)
        assertEquals(3, ack.id)
        assertNotNull(n.ended)
    }

    @Test
    fun `unknown protocol after lcp opens gets a protocol reject`() {
        val n = n()
        openLcp(n)
        val ccp = hex("80 FD 01 05 00 06 12 02")
        val (proto, rej) = single(n.receive(ccp, 0).send)
        assertEquals(Ppp.LCP, proto)
        assertEquals(Ppp.PROTO_REJ, rej.code)
        assertArrayEquals(ccp, rej.data)
    }

    @Test
    fun `unknown protocol before lcp opens is dropped`() {
        val n = n()
        n.start(0)
        assertTrue(n.receive(hex("80 57 01 01 00 04"), 0).send.isEmpty())
    }

    @Test
    fun `ipv4 flows only after ipcp opens and ipv6 is dropped`() {
        val n = n()
        openLcp(n)
        assertNull(n.receive(hex("00 21 45 00"), 0).ipv4)
        assertNull(n.ipv4Payload(hex("45 00")))
        val m = n()
        openAll(m)
        assertArrayEquals(hex("45 00"), m.receive(hex("00 21 45 00"), 0).ipv4)
        assertArrayEquals(hex("00 21 45 00"), m.ipv4Payload(hex("45 00")))
        val v6 = m.receive(hex("00 57 60 00"), 0)
        assertNull(v6.ipv4)
        assertTrue(v6.send.isEmpty())
    }

    @Test
    fun `echo is sent every 20 s and silence for 90 s ends the link`() {
        val n = n()
        openAll(n)
        assertTrue(n.tick(19_999).isEmpty())
        val (_, echo) = single(n.tick(20_000))
        assertEquals(Ppp.ECHO_REQ, echo.code)
        assertArrayEquals(n.magic, echo.data)
        n.receive(packet(Ppp.LCP, Ppp.ECHO_REPLY, echo.id, peerMagic), 21_000)
        assertNull(n.ended)
        n.tick(40_000)
        n.tick(60_000)
        n.tick(80_000)
        n.tick(100_000)
        assertNull(n.ended)
        n.tick(111_000)
        assertNotNull(n.ended)
    }

    @Test
    fun `lcp magic rejected means echo replies carry zero magic`() {
        val n = n()
        val (_, first) = single(n.start(0))
        val (_, second) = single(
            n.receive(packet(Ppp.LCP, Ppp.CONF_REJ, first.id, opts(opt(5, "00 00 00 00"))), 0).send
        )
        n.receive(packet(Ppp.LCP, Ppp.CONF_REQ, 1, opts(opt(1, "05 4A"))), 0)
        n.receive(packet(Ppp.LCP, Ppp.CONF_ACK, second.id, second.data), 0)
        val (_, reply) = single(n.receive(packet(Ppp.LCP, Ppp.ECHO_REQ, 2, peerMagic), 0).send)
        assertArrayEquals(hex("00 00 00 00"), reply.data)
    }
}
