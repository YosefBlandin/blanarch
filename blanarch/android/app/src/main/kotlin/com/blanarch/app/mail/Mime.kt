package com.blanarch.app.mail

import com.blanarch.app.config.OtpRules
import java.io.ByteArrayOutputStream
import java.util.Base64

/** Tiny MIME reader: headers, RFC 2047 encoded words, decoded text parts. Pure. */
object Mime {
    fun split(part: String): Pair<String, String> {
        val p = part.replace("\r\n", "\n")
        val i = p.indexOf("\n\n")
        return if (i < 0) p to "" else p.substring(0, i) to p.substring(i + 2)
    }

    fun headers(part: String): Map<String, String> =
        split(part).first.replace(Regex("\n[ \t]+"), " ").lines().mapNotNull { l ->
            val i = l.indexOf(':')
            if (i <= 0) null else l.substring(0, i).trim().lowercase() to l.substring(i + 1).trim()
        }.toMap()

    fun decodeWords(s: String): String = Regex("""=\?([^?]+)\?([bBqQ])\?([^?]*)\?=""").replace(s) { m ->
        val cs = runCatching { charset(m.groupValues[1]) }.getOrDefault(Charsets.UTF_8)
        val bytes = if (m.groupValues[2].equals("b", ignoreCase = true)) {
            base64(m.groupValues[3])
        } else {
            quotedPrintable(m.groupValues[3].replace('_', ' '))
        }
        String(bytes, cs)
    }

    fun quotedPrintable(s: String): ByteArray {
        val out = ByteArrayOutputStream()
        val t = s.replace("=\n", "")
        var i = 0
        while (i < t.length) {
            val c = t[i]
            if (c == '=' && i + 3 <= t.length && t.substring(i + 1, i + 3).matches(HEX2)) {
                out.write(t.substring(i + 1, i + 3).toInt(16))
                i += 3
            } else {
                out.write(c.code and 0xff)
                i++
            }
        }
        return out.toByteArray()
    }

    private fun base64(s: String): ByteArray =
        runCatching { Base64.getMimeDecoder().decode(s.trim()) }.getOrDefault(ByteArray(0))

    /** All text/plain and text/html parts, decoded (HTML tags stripped). */
    fun text(part: String): String {
        val h = headers(part)
        val body = split(part).second
        val type = h["content-type"] ?: "text/plain"
        if (type.startsWith("multipart/", ignoreCase = true)) {
            val boundary = Regex("""boundary\s*=\s*"?([^";]+)"?""", RegexOption.IGNORE_CASE)
                .find(type)?.groupValues?.get(1) ?: return body
            return body.split("--$boundary").drop(1).filterNot { it.startsWith("--") }
                .joinToString("\n") { text(it.trimStart('\r', '\n')) }
        }
        if (!type.startsWith("text/", ignoreCase = true)) return ""
        val cs = Regex("""charset\s*=\s*"?([^";]+)"?""", RegexOption.IGNORE_CASE).find(type)
            ?.groupValues?.get(1)?.let { runCatching { charset(it) }.getOrNull() } ?: Charsets.UTF_8
        val bytes = when ((h["content-transfer-encoding"] ?: "").lowercase()) {
            "base64" -> base64(body)
            "quoted-printable" -> quotedPrintable(body)
            else -> body.toByteArray(Charsets.ISO_8859_1)
        }
        val s = String(bytes, cs)
        return if (type.startsWith("text/html", ignoreCase = true)) s.replace(Regex("<[^>]+>"), " ") else s
    }

    private val HEX2 = Regex("[0-9A-Fa-f]{2}")
}

/** Finds a one-time code in one raw RFC 822 message. Pure. */
object OtpMatcher {
    /** [from] limits which sender counts (empty = any). The code must match [rules]' pattern. */
    fun codeIn(rawMessage: String, rules: OtpRules, from: String = ""): String? {
        val headers = Mime.headers(rawMessage)
        val sender = (headers["from"] ?: "").lowercase()
        if (from.isNotBlank() && !sender.contains(from.trim().lowercase())) return null
        val subject = Mime.decodeWords(headers["subject"] ?: "")
        val m = rules.codePattern.find(subject + "\n" + Mime.text(rawMessage)) ?: return null
        return m.groupValues.getOrNull(1)?.takeIf { it.isNotEmpty() } ?: m.value
    }
}
