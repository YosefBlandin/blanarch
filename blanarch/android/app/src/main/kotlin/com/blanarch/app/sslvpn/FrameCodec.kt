package com.blanarch.app.sslvpn

import com.blanarch.app.state.ErrorCode
import com.blanarch.app.state.VpnException
import java.io.EOFException
import java.io.InputStream

/**
 * The tunnel envelope around each PPP packet (spec §5):
 * total length (2) | magic 0x5050 (2) | payload length (2) | payload.
 */
object FrameCodec {
    const val HEADER_SIZE = 6
    const val MAX_PAYLOAD = 0xFFFF - HEADER_SIZE
    private val HTTP_PREFIX = "HTTP/1".toByteArray(Charsets.US_ASCII)

    fun encode(payload: ByteArray): ByteArray {
        require(payload.size in 2..MAX_PAYLOAD) { "payload size ${payload.size}" }
        val total = payload.size + HEADER_SIZE
        val out = ByteArray(total)
        out[0] = (total ushr 8).toByte()
        out[1] = total.toByte()
        out[2] = 0x50
        out[3] = 0x50
        out[4] = (payload.size ushr 8).toByte()
        out[5] = payload.size.toByte()
        payload.copyInto(out, HEADER_SIZE)
        return out
    }

    fun isHttpRefusal(header: ByteArray): Boolean =
        header.size >= HTTP_PREFIX.size && HTTP_PREFIX.indices.all { header[it] == HTTP_PREFIX[it] }

    /** Validates a 6-byte header and returns the payload length; a bad header is a protocol error. */
    fun payloadLength(header: ByteArray): Int {
        val total = u16(header, 0)
        val payload = u16(header, 4)
        if (header[2] != 0x50.toByte() || header[3] != 0x50.toByte()) throw protocol("bad frame magic")
        if (total - HEADER_SIZE != payload) throw protocol("frame lengths disagree")
        if (payload < 2) throw protocol("frame payload too short")
        return payload
    }

    private fun u16(b: ByteArray, at: Int) = ((b[at].toInt() and 0xFF) shl 8) or (b[at + 1].toInt() and 0xFF)

    private fun protocol(detail: String) = VpnException(ErrorCode.PROTOCOL, detail)
}

/** Reads frames from the tunnel stream. The very first header is checked for an HTTP refusal. */
class FrameReader(private val input: InputStream) {
    private var first = true
    private val header = ByteArray(FrameCodec.HEADER_SIZE)

    /** The next payload, or null when the gateway closed the stream. */
    fun read(): ByteArray? {
        if (!readOrEof(header)) return null
        if (first) {
            first = false
            if (FrameCodec.isHttpRefusal(header)) {
                throw VpnException(ErrorCode.TUNNEL_REFUSED, "tunnel mode not allowed")
            }
        }
        val payload = ByteArray(FrameCodec.payloadLength(header))
        return if (readOrEof(payload)) payload else null
    }

    private fun readOrEof(buf: ByteArray): Boolean {
        var n = 0
        while (n < buf.size) {
            val r = try {
                input.read(buf, n, buf.size - n)
            } catch (_: EOFException) {
                -1
            }
            if (r < 0) return false
            n += r
        }
        return true
    }
}
