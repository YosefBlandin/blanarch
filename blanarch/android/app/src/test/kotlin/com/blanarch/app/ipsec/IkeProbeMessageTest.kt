package com.blanarch.app.ipsec

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Checks the probe against fortigate-ipsec.md §2 (RFC 7296 §3). */
class IkeProbeMessageTest {
    private val spi = byteArrayOf(1, 2, 3, 4, 5, 6, 7, 8)
    private val msg = IkeProbeMessage.request(spi, ByteArray(256) { 7 }, ByteArray(32) { 9 })

    private fun u16(at: Int) = ((msg[at].toInt() and 0xff) shl 8) or (msg[at + 1].toInt() and 0xff)
    private fun u32(at: Int) = (u16(at) shl 16) or u16(at + 2)

    @Test fun `header is an IKEv2 IKE_SA_INIT from the initiator with the right length`() {
        assertArrayEquals(spi, msg.copyOfRange(0, 8))
        assertArrayEquals(ByteArray(8), msg.copyOfRange(8, 16))
        assertEquals(33, msg[16].toInt()) // SA first
        assertEquals(0x20, msg[17].toInt()) // version 2.0
        assertEquals(34, msg[18].toInt()) // IKE_SA_INIT
        assertEquals(0x08, msg[19].toInt()) // initiator
        assertEquals(0, u32(20)) // message id
        assertEquals(msg.size, u32(24))
    }

    @Test fun `payloads chain SA to KE to Nonce and their lengths add up`() {
        var at = 28
        val seen = mutableListOf<Int>()
        var next = msg[16].toInt()
        while (next != 0) {
            seen += next
            next = msg[at].toInt()
            at += u16(at + 2)
        }
        assertEquals(listOf(33, 34, 40), seen)
        assertEquals(msg.size, at)
    }

    @Test fun `the proposal offers four transforms ending in DH group 14`() {
        val sa = 28
        assertEquals(1, msg[sa + 4 + 5].toInt()) // protocol IKE
        assertEquals(4, msg[sa + 4 + 7].toInt()) // four transforms
        val ke = sa + u16(sa + 2)
        assertEquals(14, u16(ke + 4)) // KE group matches the DH transform
        assertEquals(4 + 4 + 256, u16(ke + 2))
    }

    @Test fun `a response to our SPI counts, anything else does not`() {
        val reply = msg.copyOf().also { it[19] = 0x20 }
        assertTrue(IkeProbeMessage.isIkeReply(reply, spi))
        assertFalse(IkeProbeMessage.isIkeReply(msg, spi)) // our own request, not a response
        assertFalse(IkeProbeMessage.isIkeReply(reply, byteArrayOf(9, 9, 9, 9, 9, 9, 9, 9)))
        assertFalse(IkeProbeMessage.isIkeReply(ByteArray(10), spi))
    }
}
