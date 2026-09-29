package com.blanarch.app.sslvpn

import com.blanarch.app.state.ErrorCode
import com.blanarch.app.state.VpnException
import java.io.ByteArrayInputStream
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Test

fun hex(s: String): ByteArray = s.split(' ').filter { it.isNotEmpty() }.map { it.toInt(16).toByte() }.toByteArray()

class FrameCodecTest {
    private val echoPayload = hex("C0 21 09 07 00 08 01 02 03 04")
    private val echoFrame = hex("00 10 50 50 00 0A C0 21 09 07 00 08 01 02 03 04")

    @Test
    fun `encodes the spec worked example`() {
        assertArrayEquals(echoFrame, FrameCodec.encode(echoPayload))
    }

    @Test
    fun `decodes the spec worked example`() {
        val reader = FrameReader(ByteArrayInputStream(echoFrame + echoFrame))
        assertArrayEquals(echoPayload, reader.read())
        assertArrayEquals(echoPayload, reader.read())
        assertNull(reader.read())
    }

    private fun rejects(frame: ByteArray) {
        val e = assertThrows(VpnException::class.java) { FrameReader(ByteArrayInputStream(frame)).read() }
        assertEquals(ErrorCode.PROTOCOL, e.code)
    }

    @Test
    fun `rejects disagreeing lengths`() = rejects(hex("00 11 50 50 00 0A C0 21 09 07 00 08 01 02 03 04"))

    @Test
    fun `rejects a wrong magic`() = rejects(hex("00 10 50 51 00 0A C0 21 09 07 00 08 01 02 03 04"))

    @Test
    fun `rejects a payload shorter than a protocol number`() = rejects(hex("00 07 50 50 00 01 C0"))

    @Test
    fun `an http response instead of a frame is a refusal`() {
        val raw = "HTTP/1.1 403 Forbidden\r\n\r\n".toByteArray()
        val e = assertThrows(VpnException::class.java) { FrameReader(ByteArrayInputStream(raw)).read() }
        assertEquals(ErrorCode.TUNNEL_REFUSED, e.code)
    }

    @Test
    fun `end of stream mid frame is a closed link`() {
        assertNull(FrameReader(ByteArrayInputStream(echoFrame.copyOf(9))).read())
    }
}
