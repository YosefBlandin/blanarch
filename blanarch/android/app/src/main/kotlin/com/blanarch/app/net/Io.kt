package com.blanarch.app.net

import java.io.Closeable
import java.io.EOFException
import java.io.InputStream
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Runs blocking socket work on [Dispatchers.IO] and makes it cancellable:
 * if the calling coroutine is cancelled, [this] resource is closed, which
 * unblocks the pending read/connect with an exception.
 */
suspend fun <T> Closeable.cancellableIo(block: () -> T): T = coroutineScope {
    val finished = AtomicBoolean(false)
    val closer = launch {
        try {
            awaitCancellation()
        } finally {
            if (!finished.get()) closeQuietly()
        }
    }
    try {
        withContext(Dispatchers.IO) { block() }
    } finally {
        finished.set(true)
        closer.cancel()
    }
}

fun Closeable.closeQuietly() {
    try {
        close()
    } catch (_: Exception) {
    }
}

fun InputStream.readFully(buf: ByteArray, off: Int = 0, len: Int = buf.size) {
    var n = 0
    while (n < len) {
        val r = read(buf, off + n, len - n)
        if (r < 0) throw EOFException("connection closed")
        n += r
    }
}

/** One CRLF- or LF-terminated line as ISO-8859-1, without the terminator; null at EOF. */
fun InputStream.readAsciiLine(): String? {
    val sb = StringBuilder()
    while (true) {
        val b = read()
        if (b < 0) return if (sb.isEmpty()) null else sb.toString()
        if (b == '\n'.code) {
            if (sb.endsWith("\r")) sb.setLength(sb.length - 1)
            return sb.toString()
        }
        sb.append(b.toChar())
    }
}
