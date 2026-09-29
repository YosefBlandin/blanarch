package com.blanarch.app.mail

import com.blanarch.app.net.SocketFactory
import com.blanarch.app.net.cancellableIo
import com.blanarch.app.net.closeQuietly
import com.blanarch.app.net.readAsciiLine
import com.blanarch.app.net.readFully
import com.blanarch.app.profile.EmailOtpSource
import com.blanarch.app.state.ErrorCode
import com.blanarch.app.state.VpnException
import java.io.Closeable
import java.io.EOFException
import java.io.InputStream
import javax.net.ssl.SSLSocket
import kotlinx.coroutines.CancellationException

/** Just enough IMAP to find the AuthCode email, like the script's imaplib code. */
class ImapClient private constructor(private val sock: SSLSocket) : Closeable {
    private val input = sock.inputStream.buffered()
    private var tag = 0

    private suspend fun command(cmd: String): List<String> = sock.cancellableIo {
        val t = "A${++tag}"
        sock.outputStream.write("$t $cmd\r\n".toByteArray(Charsets.UTF_8))
        sock.outputStream.flush()
        ImapResponses.readUntilTagged(input, t)
    }

    private suspend fun searchUids(criteria: String): List<Long> =
        ImapResponses.searchUids(command("UID SEARCH $criteria"))

    suspend fun highestUid(): Long = searchUids("ALL").maxOrNull() ?: 0

    /** UIDs newer than [sinceUid], newest first. */
    suspend fun uidsAfter(sinceUid: Long): List<Long> {
        command("NOOP") // lets the server report newly arrived mail
        return searchUids("UID ${sinceUid + 1}:*").filter { it > sinceUid }.sortedDescending()
    }

    /** The raw RFC 822 message, without marking it read. */
    suspend fun fetch(uid: Long): String? = ImapResponses.fetchedBody(command("UID FETCH $uid BODY.PEEK[]"))

    override fun close() {
        sock.closeQuietly()
    }

    companion object {
        /** Connects, logs in and selects the mailbox. Throws [VpnException] with an EMAIL_* code. */
        suspend fun open(sockets: SocketFactory, settings: EmailOtpSource, password: String): ImapClient {
            val sock = try {
                sockets.tls(settings.imapHost, settings.imapPort)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                throw VpnException(ErrorCode.EMAIL_UNREACHABLE, e.message, e)
            }
            val client = ImapClient(sock)
            try {
                sock.cancellableIo { client.input.readAsciiLine() } // greeting
                client.command("LOGIN ${quote(settings.account)} ${quote(password)}")
                client.command("SELECT ${quote(settings.mailbox)}")
                return client
            } catch (e: ImapException) {
                client.close()
                val code = if (e.status.contains("AUTHENTICATIONFAILED") || e.status.startsWith("NO")) {
                    ErrorCode.EMAIL_AUTH_FAILED
                } else {
                    ErrorCode.EMAIL_UNREACHABLE
                }
                throw VpnException(code, e.status, e)
            } catch (e: Exception) {
                client.close()
                if (e is CancellationException) throw e
                throw VpnException(ErrorCode.EMAIL_UNREACHABLE, e.message, e)
            }
        }

        private fun quote(s: String) = "\"" + s.replace("\\", "\\\\").replace("\"", "\\\"") + "\""
    }
}

class ImapException(val status: String) : Exception("IMAP $status")

/** Pure parsing of IMAP server output. */
object ImapResponses {
    /** Reads untagged lines (with literals inlined after a newline) up to the tagged status. */
    fun readUntilTagged(input: InputStream, tag: String): List<String> {
        val out = mutableListOf<String>()
        while (true) {
            val sb = StringBuilder(input.readAsciiLine() ?: throw EOFException("IMAP closed"))
            while (true) {
                val m = LITERAL.find(sb) ?: break
                val n = m.groupValues[1].toInt()
                val buf = ByteArray(n).also { input.readFully(it) }
                sb.append('\n').append(String(buf, Charsets.ISO_8859_1))
                sb.append(input.readAsciiLine() ?: "")
            }
            val line = sb.toString()
            if (line.startsWith("$tag ")) {
                val status = line.substring(tag.length + 1)
                if (!status.startsWith("OK")) throw ImapException(status)
                return out
            }
            out += line
        }
    }

    fun searchUids(lines: List<String>): List<Long> = lines.filter { it.startsWith("* SEARCH") }
        .flatMap { it.removePrefix("* SEARCH").trim().split(" ") }
        .mapNotNull { it.toLongOrNull() }

    /** The message literal from a `UID FETCH … BODY[]` response, or null. */
    fun fetchedBody(lines: List<String>): String? =
        lines.firstOrNull { it.contains(" FETCH ") && it.contains('\n') }?.substringAfter('\n')

    private val LITERAL = Regex("""\{(\d+)\}$""")
}
