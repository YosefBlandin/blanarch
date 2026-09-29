package com.blanarch.app.ipsec

import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer

/**
 * The IKEv2 reachability probe of fortigate-ipsec.md §2: one IKE_SA_INIT request, and a
 * check that a reply comes from an IKEv2 responder. Pure: bytes in, bytes out.
 */
object IkeProbeMessage {
    const val HEADER_LENGTH = 28
    private const val VERSION_2 = 0x20
    private const val IKE_SA_INIT = 34
    private const val FLAG_INITIATOR = 0x08
    private const val FLAG_RESPONSE = 0x20
    private const val SA = 33
    private const val KE = 34
    private const val NONCE = 40
    private const val DH_MODP_2048 = 14

    /** [spi] is the random initiator SPI (8 bytes); [keData] 256 bytes; [nonce] at least 16 bytes. */
    fun request(spi: ByteArray, keData: ByteArray, nonce: ByteArray): ByteArray {
        require(spi.size == 8 && spi.any { it.toInt() != 0 }) { "SPI must be 8 non-zero bytes" }
        require(keData.size == 256) { "MODP 2048 key data is 256 bytes" }
        require(nonce.size in 16..256) { "nonce must be 16 to 256 bytes" }
        val sa = payload(KE, proposal())
        val ke = payload(NONCE, u16(DH_MODP_2048) + u16(0) + keData)
        val nn = payload(0, nonce)
        val body = sa + ke + nn
        val header = ByteBuffer.allocate(HEADER_LENGTH)
            .put(spi)
            .put(ByteArray(8))
            .put(SA.toByte())
            .put(VERSION_2.toByte())
            .put(IKE_SA_INIT.toByte())
            .put(FLAG_INITIATOR.toByte())
            .putInt(0)
            .putInt(HEADER_LENGTH + body.size)
            .array()
        return header + body
    }

    /** True when [reply] is an IKE_SA_INIT response to the request that used [spi] (§2.2). */
    fun isIkeReply(reply: ByteArray, spi: ByteArray): Boolean {
        if (reply.size < HEADER_LENGTH) return false
        if (!reply.copyOfRange(0, 8).contentEquals(spi)) return false
        val exchange = reply[18].toInt() and 0xff
        val flags = reply[19].toInt() and 0xff
        return exchange == IKE_SA_INIT && flags and FLAG_RESPONSE != 0
    }

    private fun proposal(): ByteArray {
        val transforms = listOf(
            transform(more = true, type = 1, id = 12, attrs = u16(14 or 0x8000) + u16(256)), // AES-CBC-256
            transform(more = true, type = 2, id = 5), // PRF_HMAC_SHA2_256
            transform(more = true, type = 3, id = 12), // AUTH_HMAC_SHA2_256_128
            transform(more = false, type = 4, id = DH_MODP_2048)
        ).reduce(ByteArray::plus)
        val length = 8 + transforms.size
        return byteArrayOf(0, 0) + u16(length) + byteArrayOf(1, 1, 0, 4) + transforms
    }

    private fun transform(more: Boolean, type: Int, id: Int, attrs: ByteArray = ByteArray(0)): ByteArray {
        val length = 8 + attrs.size
        return byteArrayOf(if (more) 3 else 0, 0) + u16(length) + byteArrayOf(type.toByte(), 0) + u16(id) + attrs
    }

    private fun payload(next: Int, body: ByteArray): ByteArray = ByteArrayOutputStream().apply {
        write(next)
        write(0)
        write(u16(4 + body.size))
        write(body)
    }.toByteArray()

    private fun u16(v: Int) = byteArrayOf((v ushr 8).toByte(), v.toByte())
}
