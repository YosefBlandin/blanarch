package com.blanarch.app.security

import android.content.Context
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.security.keystore.UserNotAuthenticatedException
import android.util.Base64
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Saved passwords exist but need the user to unlock (fingerprint, face or screen lock) first. */
class CredentialsLockedException : Exception("unlock required")

/** Per-profile passwords. An interface so the engine can be tested without Android. */
interface CredentialStore {
    /** Throws [CredentialsLockedException] when the app lock is on and the user hasn't unlocked recently. */
    fun vpnPassword(profileId: String): String?
    fun setVpnPassword(profileId: String, value: String?)
    fun emailPassword(profileId: String): String?
    fun setEmailPassword(profileId: String, value: String?)
    fun hasVpnPassword(profileId: String): Boolean
    fun hasEmailPassword(profileId: String): Boolean
    fun forget(profileId: String) {
        setVpnPassword(profileId, null)
        setEmailPassword(profileId, null)
    }

    /** When true, passwords are encrypted with a key usable only shortly after the user unlocks. */
    val locked: Boolean

    /** Re-encrypts every password for the new mode. Call right after a successful unlock. */
    fun setLocked(locked: Boolean)
}

/** Certificate digests the user chose to trust, per gateway host. */
interface PinStore {
    fun pin(host: String): String?
    fun savePin(host: String, digest: String)
}

/**
 * AES-GCM with keys held in the Android Keystore (the phone's equivalent of
 * the macOS Keychain); the keys never leave secure hardware.
 *
 * Two keys: a plain one, and a locked one that the Keystore only lets us use
 * for [UNLOCK_SECONDS] after the user confirms with biometrics or the screen
 * lock. Each stored value is tagged with the key that encrypted it.
 */
class KeystoreCredentialStore(context: Context) : CredentialStore {
    private val prefs = context.getSharedPreferences("secure", Context.MODE_PRIVATE)
    private val settings = context.getSharedPreferences("security", Context.MODE_PRIVATE)

    override fun vpnPassword(profileId: String) = read("vpn:$profileId")
    override fun setVpnPassword(profileId: String, value: String?) = write("vpn:$profileId", value)
    override fun emailPassword(profileId: String) = read("email:$profileId")
    override fun setEmailPassword(profileId: String, value: String?) = write("email:$profileId", value)
    override fun hasVpnPassword(profileId: String) = prefs.contains("vpn:$profileId")
    override fun hasEmailPassword(profileId: String) = prefs.contains("email:$profileId")

    override val locked: Boolean get() = settings.getBoolean("locked", false)

    @Synchronized
    override fun setLocked(locked: Boolean) {
        if (locked == this.locked) return
        val plain = prefs.all.keys.associateWith { read(it) }
        settings.edit().putBoolean("locked", locked).commit()
        plain.forEach { (name, value) -> if (value != null) write(name, value) }
    }

    private fun key(lockedKey: Boolean): SecretKey {
        val alias = if (lockedKey) ALIAS_LOCKED else ALIAS
        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (ks.getKey(alias, null) as? SecretKey)?.let { return it }
        val spec = KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
        if (lockedKey) {
            spec.setUserAuthenticationRequired(true)
            if (Build.VERSION.SDK_INT >= 30) {
                spec.setUserAuthenticationParameters(
                    UNLOCK_SECONDS,
                    KeyProperties.AUTH_BIOMETRIC_STRONG or KeyProperties.AUTH_DEVICE_CREDENTIAL
                )
            } else {
                @Suppress("DEPRECATION")
                spec.setUserAuthenticationValidityDurationSeconds(UNLOCK_SECONDS)
            }
        }
        val gen = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        gen.init(spec.build())
        return gen.generateKey()
    }

    private fun write(name: String, value: String?) {
        if (value.isNullOrEmpty()) {
            prefs.edit().remove(name).apply()
            return
        }
        val lockedKey = locked
        try {
            val c = Cipher.getInstance(TRANSFORM)
            c.init(Cipher.ENCRYPT_MODE, key(lockedKey))
            val out = c.iv + c.doFinal(value.toByteArray(Charsets.UTF_8))
            val tag = if (lockedKey) LOCKED_TAG else PLAIN_TAG
            prefs.edit().putString(name, tag + Base64.encodeToString(out, Base64.NO_WRAP)).apply()
        } catch (e: UserNotAuthenticatedException) {
            throw CredentialsLockedException()
        }
    }

    private fun read(name: String): String? {
        val stored = prefs.getString(name, null) ?: return null
        // "v2:L:" locked key, "v2:P:" plain key; values from before the app lock have no tag.
        val lockedKey = stored.startsWith(LOCKED_TAG)
        val bytes = Base64.decode(stored.removePrefix(LOCKED_TAG).removePrefix(PLAIN_TAG), Base64.NO_WRAP)
        return try {
            val c = Cipher.getInstance(TRANSFORM)
            c.init(Cipher.DECRYPT_MODE, key(lockedKey), GCMParameterSpec(128, bytes, 0, 12))
            String(c.doFinal(bytes, 12, bytes.size - 12), Charsets.UTF_8)
        } catch (e: UserNotAuthenticatedException) {
            throw CredentialsLockedException()
        } catch (_: Exception) {
            null
        }
    }

    private companion object {
        const val ALIAS = "blanarch_key"
        const val ALIAS_LOCKED = "blanarch_key_locked"
        const val TRANSFORM = "AES/GCM/NoPadding"
        const val UNLOCK_SECONDS = 60
        const val LOCKED_TAG = "v2:L:"
        const val PLAIN_TAG = "v2:P:"
    }
}

class PrefsPinStore(context: Context) : PinStore {
    private val prefs = context.getSharedPreferences("pins", Context.MODE_PRIVATE)
    override fun pin(host: String): String? = prefs.getString(host, null)
    override fun savePin(host: String, digest: String) = prefs.edit().putString(host, digest).apply()
}
