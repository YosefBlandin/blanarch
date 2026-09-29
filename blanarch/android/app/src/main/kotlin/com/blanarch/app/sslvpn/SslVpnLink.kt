package com.blanarch.app.sslvpn

import com.blanarch.app.net.cancellableIo
import com.blanarch.app.net.closeQuietly
import com.blanarch.app.state.ErrorCode
import com.blanarch.app.state.VpnException
import com.blanarch.app.vpn.IpConfig
import com.blanarch.app.vpn.LinkStats
import com.blanarch.app.vpn.PacketLink
import com.blanarch.app.vpn.TunDevice
import java.io.BufferedInputStream
import java.io.Closeable
import java.io.IOException
import java.net.Socket
import java.util.concurrent.atomic.AtomicLong
import kotlin.time.Duration
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.channels.ClosedReceiveChannelException
import kotlinx.coroutines.channels.trySendBlocking
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull

/**
 * The PPP link over an already switched tunnel connection (spec §5 and §6).
 * The socket must already have sent the tunnel request; this class owns it from then on.
 */
class SslVpnLink(
    private val socket: Socket,
    mru: Int,
    private val log: (String) -> Unit,
    private val clock: () -> Long = System::currentTimeMillis
) : PacketLink {
    private val negotiator = PppNegotiator(mru, trace = log)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val incoming = Channel<ByteArray>(INCOMING_CAPACITY)
    private val writeLock = Any()
    private var readerStarted = false

    @Volatile private var tunEnded: String? = null
    private val bytesIn = AtomicLong()
    private val bytesOut = AtomicLong()

    override val stats: LinkStats
        get() = LinkStats(bytesIn.get(), bytesOut.get(), negotiator.lastRttMillis)

    override suspend fun negotiate(timeout: Duration): IpConfig = withContext(Dispatchers.IO) {
        startReader()
        val deadline = clock() + timeout.inWholeMilliseconds
        send(negotiator.start(clock()))
        while (true) {
            negotiator.ipConfig?.let { ip ->
                if (ip.ip == "0.0.0.0") throw VpnException(ErrorCode.PROTOCOL, "gateway assigned no address")
                log("PPP up · IP ${ip.ip}")
                return@withContext ip
            }
            negotiator.ended?.let { throw VpnException(ErrorCode.LINK_LOST, it) }
            val now = clock()
            if (now >= deadline) throw VpnException(ErrorCode.PROTOCOL, "PPP negotiation timed out")
            val payload = try {
                nextPayload(minOf(TICK_MILLIS, deadline - now))
            } catch (e: ClosedReceiveChannelException) {
                throw VpnException(ErrorCode.LINK_LOST, "gateway closed the connection", e)
            }
            if (payload != null) send(negotiator.receive(payload, clock()).send)
            send(negotiator.tick(clock()))
        }
        @Suppress("UNREACHABLE_CODE")
        error("unreachable")
    }

    override suspend fun pump(tun: TunDevice): String = withContext(Dispatchers.IO) {
        check(negotiator.ipcpOpen) { "negotiate first" }
        val tunJob = scope.launch { tunToGateway(tun) }
        try {
            while (true) {
                negotiator.ended?.let { return@withContext it }
                tunEnded?.let { return@withContext it }
                val payload = try {
                    nextPayload(TICK_MILLIS)
                } catch (_: ClosedReceiveChannelException) {
                    return@withContext "gateway closed the connection"
                } catch (e: IOException) {
                    return@withContext "connection lost (${e.javaClass.simpleName})"
                }
                if (payload != null) {
                    val result = negotiator.receive(payload, clock())
                    send(result.send)
                    result.ipv4?.let { packet ->
                        try {
                            tun.output.write(packet)
                            bytesIn.addAndGet(packet.size.toLong())
                        } catch (_: IOException) {
                            return@withContext "device closed"
                        }
                    }
                }
                send(negotiator.tick(clock()))
            }
            @Suppress("UNREACHABLE_CODE")
            error("unreachable")
        } finally {
            tunJob.cancel()
        }
    }

    override fun close() {
        scope.cancel()
        incoming.cancel()
        socket.closeQuietly()
    }

    private fun startReader() {
        if (readerStarted) return
        readerStarted = true
        val frames = FrameReader(BufferedInputStream(socket.getInputStream(), READ_BUFFER))
        scope.launch {
            try {
                socket.cancellableIo {
                    while (true) {
                        val payload = frames.read() ?: break
                        if (incoming.trySendBlocking(payload).isClosed) break
                    }
                }
                incoming.close()
            } catch (e: CancellationException) {
                incoming.close()
                throw e
            } catch (e: Exception) {
                incoming.close(e)
            }
        }
    }

    /** The next payload, or null when [waitMillis] passes first. Rethrows the reader's failure. */
    private suspend fun nextPayload(waitMillis: Long): ByteArray? =
        withTimeoutOrNull(waitMillis.coerceAtLeast(1)) { incoming.receive() }

    private suspend fun send(payloads: List<ByteArray>) {
        if (payloads.isEmpty()) return
        socket.cancellableIo { payloads.forEach(::writeFrame) }
    }

    private fun writeFrame(payload: ByteArray) {
        val frame = FrameCodec.encode(payload)
        synchronized(writeLock) {
            socket.getOutputStream().apply {
                write(frame)
                flush()
            }
        }
    }

    /** Reads IPv4 packets from the device and sends them; closing the device or socket ends it. */
    private suspend fun tunToGateway(tun: TunDevice) {
        val both = Closeable {
            tun.closeQuietly()
            socket.closeQuietly()
        }
        try {
            both.cancellableIo {
                val buf = ByteArray(MAX_PACKET)
                while (true) {
                    val n = tun.input.read(buf)
                    if (n < 0) break
                    if (n == 0 || (buf[0].toInt() ushr 4) != 4) continue // IPv6 is not carried
                    writeFrame(Ppp.payload(Ppp.IPV4, buf.copyOf(n)))
                    bytesOut.addAndGet(n.toLong())
                }
            }
            tunEnded = "device closed"
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            tunEnded = "device or tunnel closed (${e.javaClass.simpleName})"
        }
    }

    private companion object {
        const val TICK_MILLIS = 1_000L
        const val INCOMING_CAPACITY = 512
        const val READ_BUFFER = 64 * 1024
        const val MAX_PACKET = FrameCodec.MAX_PAYLOAD - 2
    }
}
