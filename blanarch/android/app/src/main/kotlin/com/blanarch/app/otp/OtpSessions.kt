package com.blanarch.app.otp

import com.blanarch.app.config.OtpRules
import com.blanarch.app.mail.ImapClient
import com.blanarch.app.mail.OtpMatcher
import com.blanarch.app.net.SocketFactory
import com.blanarch.app.profile.EmailOtpSource
import com.blanarch.app.state.ErrorCode
import com.blanarch.app.state.VpnException
import com.blanarch.app.vpn.OtpSession
import com.blanarch.app.vpn.OtpSessionFactory
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull

/** Codes the user types in the app. Conflated: only the newest counts. */
class ManualOtpInbox {
    private val channel = Channel<String>(Channel.CONFLATED)

    fun submit(code: String) {
        code.trim().takeIf { it.isNotEmpty() }?.let { channel.trySend(it) }
    }

    fun clear() {
        while (channel.tryReceive().isSuccess) Unit
    }

    suspend fun receive(): String = channel.receive()
}

/** Finds the code in mail that arrived after the marker taken at login time. */
class EmailOtpWatcher(
    private val imap: ImapClient,
    private val marker: Long,
    private val rules: OtpRules,
    private val from: String
) {
    suspend fun findCode(): String? {
        for (uid in imap.uidsAfter(marker)) {
            val raw = imap.fetch(uid) ?: continue
            OtpMatcher.codeIn(raw, rules, from)?.let { return it }
        }
        return null
    }
}

/** Waits for whichever comes first: the email code or one typed by hand. */
class CompositeOtpSession(
    private val email: EmailOtpWatcher?,
    private val imap: ImapClient?,
    private val manual: ManualOtpInbox,
    private val rules: OtpRules,
    override val emailIssue: ErrorCode?,
    private val onEmailError: (String) -> Unit
) : OtpSession {
    override val watchingEmail get() = email != null
    override val timeout get() = if (email != null) rules.timeout else rules.manualTimeout

    override suspend fun awaitCode(): String? = withTimeoutOrNull(timeout) {
        coroutineScope {
            val result = CompletableDeferred<String>()
            val typed = launch { result.complete(manual.receive()) }
            val polled = email?.let { watcher ->
                launch {
                    while (true) {
                        try {
                            watcher.findCode()?.let { result.complete(it) }
                        } catch (e: CancellationException) {
                            throw e
                        } catch (e: Exception) {
                            onEmailError(e.message ?: e.javaClass.simpleName)
                        }
                        delay(rules.pollInterval)
                    }
                }
            }
            result.await().also {
                typed.cancel()
                polled?.cancel()
            }
        }
    }

    override fun close() {
        imap?.close()
    }
}

class DefaultOtpSessionFactory(
    private val sockets: SocketFactory,
    private val rules: OtpRules,
    private val manual: ManualOtpInbox,
    private val log: (String) -> Unit
) : OtpSessionFactory {
    override suspend fun open(source: EmailOtpSource?, emailPassword: String?): OtpSession {
        manual.clear()
        if (source == null || emailPassword == null) {
            return CompositeOtpSession(null, null, manual, rules, ErrorCode.EMAIL_NOT_CONFIGURED) {}
        }
        return try {
            val imap = ImapClient.open(sockets, source, emailPassword)
            val marker = imap.highestUid()
            log("Watching ${source.account} for the code email")
            CompositeOtpSession(EmailOtpWatcher(imap, marker, rules, source.from), imap, manual, rules, null) {
                log("Email check failed: $it")
            }
        } catch (e: VpnException) {
            log("Can't read the inbox (${e.code}). Type the code by hand")
            CompositeOtpSession(null, null, manual, rules, e.code) {}
        }
    }
}
