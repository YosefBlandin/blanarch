package com.blanarch.app.sslvpn

import com.blanarch.app.vpn.IpConfig
import kotlin.random.Random

/**
 * The PPP state machine of spec §6: LCP, then IPCP, then keepalive. No sockets,
 * no threads and no clock of its own: it consumes received payloads and the
 * current time, and returns the payloads to send (each starting with its
 * 2-byte protocol number). One caller at a time.
 */
class PppNegotiator(
    mru: Int,
    private val random: Random = Random.Default,
    private val retryMillis: Long = 3_000,
    private val echoIntervalMillis: Long = 20_000,
    private val deadAfterMillis: Long = 90_000,
    private val trace: (String) -> Unit = {}
) {
    /** What one received payload produced: packets to send, and an IPv4 packet for the device if any. */
    class Result(val send: List<ByteArray> = emptyList(), val ipv4: ByteArray? = null)

    private val lcpOptions = linkedMapOf(
        Ppp.LCP_MRU to u16Bytes(mru),
        Ppp.LCP_MAGIC to newMagic()
    )
    private val ipcpOptions = linkedMapOf(
        Ppp.IPCP_ADDRESS to ByteArray(4),
        Ppp.IPCP_DNS1 to ByteArray(4),
        Ppp.IPCP_DNS2 to ByteArray(4)
    )

    private var lcpId = random.nextInt(256)
    private var ipcpId = random.nextInt(256)
    private var lcpReqId = -1
    private var ipcpReqId = -1
    private var lcpSentAt = 0L
    private var ipcpSentAt = 0L
    private var ourLcpAcked = false
    private var peerLcpAcked = false
    private var ourIpcpAcked = false
    private var peerIpcpAcked = false
    private var lastEchoSent = 0L
    private var lastEchoReply = 0L

    /** Round trip of the latest keepalive echo, for display. */
    var lastRttMillis: Long? = null
        private set

    val lcpOpen: Boolean get() = ourLcpAcked && peerLcpAcked
    val ipcpOpen: Boolean get() = lcpOpen && ourIpcpAcked && peerIpcpAcked

    /** The negotiated address and DNS once IPCP is open. */
    var ipConfig: IpConfig? = null
        private set

    /** Why the link ended, once it has. */
    var ended: String? = null
        private set

    /** Current magic number, zero when the gateway rejected the option. */
    val magic: ByteArray get() = lcpOptions[Ppp.LCP_MAGIC] ?: ByteArray(4)

    /** Our current MRU as sent in LCP. */
    val mru: Int? get() = lcpOptions[Ppp.LCP_MRU]?.let { Ppp.u16(it, 0) }

    fun start(now: Long): List<ByteArray> = listOf(lcpRequest(now))

    /** Retransmissions and keepalive; call about once a second. */
    fun tick(now: Long): List<ByteArray> {
        if (ended != null) return emptyList()
        if (!ourLcpAcked) {
            return if (now - lcpSentAt >= retryMillis) listOf(lcpRequest(now)) else emptyList()
        }
        if (!lcpOpen) return emptyList()
        if (!ourIpcpAcked) {
            return if (now - ipcpSentAt >= retryMillis) listOf(ipcpRequest(now)) else emptyList()
        }
        if (!ipcpOpen) return emptyList()
        if (now - lastEchoReply >= deadAfterMillis) {
            ended = "no keepalive reply for ${deadAfterMillis / 1000} s"
            return emptyList()
        }
        if (now - lastEchoSent >= echoIntervalMillis) {
            lastEchoSent = now
            val echo = ControlPacket(Ppp.ECHO_REQ, nextLcpId(), magic.copyOf())
            trace("LCP sent Echo-Request id ${echo.id}")
            return listOf(echo.toPayload(Ppp.LCP))
        }
        return emptyList()
    }

    fun receive(payload: ByteArray, now: Long): Result {
        if (ended != null || payload.size < 2) return Result()
        val protocol = Ppp.protocolOf(payload)
        val info = payload.copyOfRange(2, payload.size)
        return when (protocol) {
            Ppp.LCP -> Result(onLcp(info, now))
            Ppp.IPCP -> if (lcpOpen) Result(onIpcp(info, now)) else Result()
            Ppp.IPV4 -> if (ipcpOpen) Result(ipv4 = info) else Result()
            Ppp.IPV6 -> Result()
            else -> if (lcpOpen) Result(listOf(protocolReject(protocol, info))) else Result()
        }
    }

    /** Wraps an IPv4 packet from the device; null until IPCP is open. */
    fun ipv4Payload(packet: ByteArray): ByteArray? = if (ipcpOpen && ended == null) {
        Ppp.payload(Ppp.IPV4, packet)
    } else {
        null
    }

    private fun onLcp(info: ByteArray, now: Long): List<ByteArray> {
        val p = ControlPacket.parse(info) ?: return emptyList()
        if (p.code != Ppp.ECHO_REQ && p.code != Ppp.ECHO_REPLY) trace("LCP got ${Ppp.codeName(p.code)} id ${p.id}")
        val wasOpen = lcpOpen
        val out = mutableListOf<ByteArray>()
        when (p.code) {
            Ppp.CONF_REQ -> {
                val options = PppOption.parseAll(p.data) ?: return emptyList()
                val rejected = options.filter { it.type !in LCP_ACCEPTED }
                out += if (rejected.isEmpty()) {
                    peerLcpAcked = true
                    ControlPacket(Ppp.CONF_ACK, p.id, p.data).toPayload(Ppp.LCP)
                } else {
                    ControlPacket(Ppp.CONF_REJ, p.id, PppOption.encodeAll(rejected)).toPayload(Ppp.LCP)
                }
            }
            Ppp.CONF_ACK -> if (p.id == lcpReqId) ourLcpAcked = true
            Ppp.CONF_NAK -> if (p.id == lcpReqId && !ourLcpAcked) {
                PppOption.parseAll(p.data)?.forEach { o ->
                    when (o.type) {
                        Ppp.LCP_MRU -> if (o.value.size == 2) lcpOptions[Ppp.LCP_MRU] = o.value
                        Ppp.LCP_MAGIC -> if (Ppp.LCP_MAGIC in lcpOptions) lcpOptions[Ppp.LCP_MAGIC] = newMagic()
                    }
                }
                out += lcpRequest(now)
            }
            Ppp.CONF_REJ -> if (p.id == lcpReqId && !ourLcpAcked) {
                PppOption.parseAll(p.data)?.forEach { lcpOptions.remove(it.type) }
                out += lcpRequest(now)
            }
            Ppp.TERM_REQ -> {
                out += ControlPacket(Ppp.TERM_ACK, p.id, ByteArray(0)).toPayload(Ppp.LCP)
                ended = "gateway ended the session"
            }
            Ppp.ECHO_REQ -> if (lcpOpen) {
                val rest = if (p.data.size > 4) p.data.copyOfRange(4, p.data.size) else ByteArray(0)
                out += ControlPacket(Ppp.ECHO_REPLY, p.id, magic + rest).toPayload(Ppp.LCP)
            }
            Ppp.ECHO_REPLY -> {
                // Round trip of our last keepalive; measurement only, nothing is sent.
                if (lastEchoSent in 1..now) lastRttMillis = now - lastEchoSent
                lastEchoReply = now
            }
            Ppp.TERM_ACK, Ppp.CODE_REJ, Ppp.PROTO_REJ, Ppp.DISCARD_REQ -> Unit
            else -> out += ControlPacket(Ppp.CODE_REJ, nextLcpId(), info).toPayload(Ppp.LCP)
        }
        if (!wasOpen && lcpOpen && ended == null) {
            trace("LCP open")
            out += ipcpRequest(now)
        }
        return out
    }

    private fun onIpcp(info: ByteArray, now: Long): List<ByteArray> {
        val p = ControlPacket.parse(info) ?: return emptyList()
        trace("IPCP got ${Ppp.codeName(p.code)} id ${p.id}")
        val wasOpen = ipcpOpen
        val out = mutableListOf<ByteArray>()
        when (p.code) {
            Ppp.CONF_REQ -> {
                val options = PppOption.parseAll(p.data) ?: return emptyList()
                val rejected = options.filter { it.type != Ppp.IPCP_ADDRESS }
                out += if (rejected.isEmpty()) {
                    peerIpcpAcked = true
                    ControlPacket(Ppp.CONF_ACK, p.id, p.data).toPayload(Ppp.IPCP)
                } else {
                    ControlPacket(Ppp.CONF_REJ, p.id, PppOption.encodeAll(rejected)).toPayload(Ppp.IPCP)
                }
            }
            Ppp.CONF_ACK -> if (p.id == ipcpReqId) ourIpcpAcked = true
            Ppp.CONF_NAK -> if (p.id == ipcpReqId && !ourIpcpAcked) {
                PppOption.parseAll(p.data)?.forEach { o ->
                    if (o.type in ipcpOptions && o.value.size == 4) ipcpOptions[o.type] = o.value
                }
                out += ipcpRequest(now)
            }
            Ppp.CONF_REJ -> if (p.id == ipcpReqId && !ourIpcpAcked) {
                PppOption.parseAll(p.data)?.forEach { ipcpOptions.remove(it.type) }
                out += ipcpRequest(now)
            }
            Ppp.TERM_REQ -> {
                out += ControlPacket(Ppp.TERM_ACK, p.id, ByteArray(0)).toPayload(Ppp.IPCP)
                ended = "gateway ended the session"
            }
            Ppp.TERM_ACK, Ppp.CODE_REJ -> Unit
            else -> out += ControlPacket(Ppp.CODE_REJ, nextIpcpId(), info).toPayload(Ppp.IPCP)
        }
        if (!wasOpen && ipcpOpen && ended == null) {
            val ip = ipcpOptions[Ppp.IPCP_ADDRESS]?.let(Ppp::ipv4ToString) ?: "0.0.0.0"
            val dns = listOfNotNull(ipcpOptions[Ppp.IPCP_DNS1], ipcpOptions[Ppp.IPCP_DNS2])
                .filter { v -> v.any { it.toInt() != 0 } }
                .map(Ppp::ipv4ToString)
            ipConfig = IpConfig(ip, dns)
            lastEchoSent = now
            lastEchoReply = now
            trace("IPCP open")
        }
        return out
    }

    private fun protocolReject(protocol: Int, info: ByteArray): ByteArray {
        trace("LCP sent Protocol-Reject for 0x%04x".format(protocol))
        return ControlPacket(Ppp.PROTO_REJ, nextLcpId(), Ppp.payload(protocol, info)).toPayload(Ppp.LCP)
    }

    private fun lcpRequest(now: Long): ByteArray {
        lcpReqId = nextLcpId()
        lcpSentAt = now
        val options = lcpOptions.map { (t, v) -> PppOption(t, v) }
        trace("LCP sent Configure-Request id $lcpReqId")
        return ControlPacket(Ppp.CONF_REQ, lcpReqId, PppOption.encodeAll(options)).toPayload(Ppp.LCP)
    }

    private fun ipcpRequest(now: Long): ByteArray {
        ipcpReqId = nextIpcpId()
        ipcpSentAt = now
        val options = ipcpOptions.map { (t, v) -> PppOption(t, v) }
        trace("IPCP sent Configure-Request id $ipcpReqId")
        return ControlPacket(Ppp.CONF_REQ, ipcpReqId, PppOption.encodeAll(options)).toPayload(Ppp.IPCP)
    }

    private fun nextLcpId(): Int {
        lcpId = (lcpId + 1) and 0xFF
        return lcpId
    }

    private fun nextIpcpId(): Int {
        ipcpId = (ipcpId + 1) and 0xFF
        return ipcpId
    }

    private fun newMagic(): ByteArray {
        var m: Int
        do {
            m = random.nextInt()
        } while (m == 0)
        return byteArrayOf((m ushr 24).toByte(), (m ushr 16).toByte(), (m ushr 8).toByte(), m.toByte())
    }

    private fun u16Bytes(v: Int) = byteArrayOf((v ushr 8).toByte(), v.toByte())

    private companion object {
        val LCP_ACCEPTED = setOf(Ppp.LCP_MRU, Ppp.LCP_ACCM, Ppp.LCP_MAGIC)
    }
}
