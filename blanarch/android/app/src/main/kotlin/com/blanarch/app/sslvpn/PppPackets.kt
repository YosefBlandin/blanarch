package com.blanarch.app.sslvpn

/** PPP protocol numbers and control codes (RFC 1661, 1332, 1877; spec §5 and §6). */
object Ppp {
    const val LCP = 0xC021
    const val IPCP = 0x8021
    const val IPV4 = 0x0021
    const val IPV6 = 0x0057

    const val CONF_REQ = 1
    const val CONF_ACK = 2
    const val CONF_NAK = 3
    const val CONF_REJ = 4
    const val TERM_REQ = 5
    const val TERM_ACK = 6
    const val CODE_REJ = 7
    const val PROTO_REJ = 8
    const val ECHO_REQ = 9
    const val ECHO_REPLY = 10
    const val DISCARD_REQ = 11

    const val LCP_MRU = 1
    const val LCP_ACCM = 2
    const val LCP_MAGIC = 5

    const val IPCP_ADDRESS = 3
    const val IPCP_DNS1 = 129
    const val IPCP_DNS2 = 131

    fun protocolOf(payload: ByteArray): Int = u16(payload, 0)

    /** A PPP payload: 2-byte protocol followed by [info]. */
    fun payload(protocol: Int, info: ByteArray): ByteArray =
        byteArrayOf((protocol ushr 8).toByte(), protocol.toByte()) + info

    fun u16(b: ByteArray, at: Int) = ((b[at].toInt() and 0xFF) shl 8) or (b[at + 1].toInt() and 0xFF)

    fun ipv4ToString(b: ByteArray): String = b.joinToString(".") { (it.toInt() and 0xFF).toString() }

    fun codeName(code: Int): String = when (code) {
        CONF_REQ -> "Configure-Request"
        CONF_ACK -> "Configure-Ack"
        CONF_NAK -> "Configure-Nak"
        CONF_REJ -> "Configure-Reject"
        TERM_REQ -> "Terminate-Request"
        TERM_ACK -> "Terminate-Ack"
        CODE_REJ -> "Code-Reject"
        PROTO_REJ -> "Protocol-Reject"
        ECHO_REQ -> "Echo-Request"
        ECHO_REPLY -> "Echo-Reply"
        DISCARD_REQ -> "Discard-Request"
        else -> "code $code"
    }
}

/** code (1) | identifier (1) | length (2) | data. Shared by LCP and IPCP. */
class ControlPacket(val code: Int, val id: Int, val data: ByteArray) {
    fun encode(): ByteArray {
        val len = data.size + 4
        return byteArrayOf(code.toByte(), id.toByte(), (len ushr 8).toByte(), len.toByte()) + data
    }

    fun toPayload(protocol: Int): ByteArray = Ppp.payload(protocol, encode())

    companion object {
        /** Parses the information field after the protocol number; null when malformed. */
        fun parse(info: ByteArray): ControlPacket? {
            if (info.size < 4) return null
            val len = Ppp.u16(info, 2)
            if (len < 4 || len > info.size) return null
            return ControlPacket(info[0].toInt() and 0xFF, info[1].toInt() and 0xFF, info.copyOfRange(4, len))
        }
    }
}

/** type (1) | length (1, includes these 2 bytes) | value. */
class PppOption(val type: Int, val value: ByteArray) {
    fun encode(): ByteArray = byteArrayOf(type.toByte(), (value.size + 2).toByte()) + value

    companion object {
        fun parseAll(data: ByteArray): List<PppOption>? {
            val out = mutableListOf<PppOption>()
            var i = 0
            while (i < data.size) {
                if (i + 2 > data.size) return null
                val len = data[i + 1].toInt() and 0xFF
                if (len < 2 || i + len > data.size) return null
                out += PppOption(data[i].toInt() and 0xFF, data.copyOfRange(i + 2, i + len))
                i += len
            }
            return out
        }

        fun encodeAll(options: List<PppOption>): ByteArray = options.fold(ByteArray(0)) { acc, o -> acc + o.encode() }
    }
}
