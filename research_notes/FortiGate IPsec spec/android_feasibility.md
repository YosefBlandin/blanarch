# Android feasibility: a userspace IKEv2 + ESP client inside a VpnService app

Date: 2026-09-28. Target: Blanarch engine (Kotlin), minSdk 29 (Android 10), IPv4 inside the tunnel.

**Clean-room statement.** Everything below comes from public documentation: Android developer docs
(developer.android.com, source.android.com, the Android Developers Blog), Oracle JCA documentation, BoringSSL API docs,
conscrypt.org, Bouncy Castle license page and javadoc, IETF RFCs (rfc-editor.org), the IANA IKEv2 registry, NIST
SP 800-38A and Fortinet public docs/KB. No source code of any VPN or IPsec implementation (strongSwan, libreswan,
Openswan, racoon, iked, Linux xfrm, Android's IKE module, openfortivpn, OpenConnect, FortiClient, WireGuard) was opened,
searched or quoted, and no GitHub/GitLab repository or README was read. Where a fact would only be available from such
code, it is marked **not publicly documented**.

**Legend.** Confidence: **H** (stated verbatim in the cited doc), **M** (inferred from docs, or doc is ambiguous),
**L** (plausible, weakly supported). **[TEST]** = confirm on real devices. **[TRACE]** = confirm with a live packet
trace against the FortiGate.

---

## 0. Verdict in one screen

- **Feasible on minSdk 29 with the platform JCA** for AES-GCM, AES-CBC, HMAC-SHA1/256/384/512, ECDH P-256/384/521,
  MODP-2048 DH, SHA-1/2 and RSA/ECDSA signature checks. Gaps on the platform: **X25519 only from API 33**, **no MD4**
  (needed by EAP-MSCHAPv2), **TLS keying-material export only from API 31** (needed by EAP-TTLS), **no ML-KEM**.
  Bouncy Castle (MIT license) covers all four gaps. (Sections 1, 2.)
- **ESP must always be UDP-encapsulated (4500) or TCP-encapsulated (RFC 9329).** A normal app cannot send or receive raw
  IP protocol 50. The kernel ESP path (IpSecManager) is limited to transport mode on sockets. (Section 3.2.)
- **MTU:** with a 1500-byte underlying link and outer IPv4, the largest inner packet is **1438** for AES-GCM-16 and
  **1422** for AES-CBC + HMAC-SHA-256-128. On cellular (often below 1500, often IPv6-only with 464XLAT) plan for
  smaller: see the table in 3.3.
- **The hard problem is screen-off keepalive, not crypto.** Userspace timers stop in deep sleep, Doze throttles alarms,
  long-held wake locks are now penalised on Google Play. The only battery-friendly documented mechanism, hardware
  `SocketKeepalive`, works only with an `IpSecManager.UdpEncapsulationSocket`, and whether userspace ESP can share that
  socket is not publicly documented. This needs a prototype. (Section 3.5.)
- **NAT keepalive interval:** RFC 3948 default is 20 s; FortiGate default is 10 s; Android's own IKE library default is
  10 s; RFC 8085 says not more often than every 15 s; RFC 5626 notes many NATs time out UDP at 30 s. Recommended start:
  20 s with jitter, adaptive upward. (Section 4.)

---

## 1. JCA availability on Android API 29+

### 1.1 Availability table (from the Android reference "Android provides the following ..." tables)

| Need in IKEv2/ESP | JCA name | Android API | Conf. | Source |
|---|---|---|---|---|
| ESP/IKE AES-GCM (RFC 4106, RFC 5282) | `Cipher "AES/GCM/NoPadding"` | 10+ | H | https://developer.android.com/reference/javax/crypto/Cipher |
| Key-size-pinned GCM | `"AES_128/GCM/NoPadding"`, `"AES_256/GCM/NoPadding"` | 26+ | H | https://developer.android.com/reference/javax/crypto/Cipher |
| ESP/IKE AES-CBC (RFC 3602) | `Cipher "AES/CBC/NoPadding"` | 1+ | H | https://developer.android.com/reference/javax/crypto/Cipher |
| AES block op (CBC IV generation, XCBC if ever needed) | `Cipher "AES/ECB/NoPadding"` | 1+ | H | https://developer.android.com/reference/javax/crypto/Cipher |
| ChaCha20-Poly1305 (RFC 7634) | `Cipher "ChaCha20/Poly1305/NoPadding"` | 28+ | H | https://developer.android.com/reference/javax/crypto/Cipher |
| DES-ECB (EAP-MSCHAPv2 response, RFC 2759) | `Cipher "DES/ECB/NoPadding"` | 1+ | H (listed), M (provider) | https://developer.android.com/reference/javax/crypto/Cipher |
| HMAC-SHA1-96, HMAC-SHA2-256/384/512 (RFC 4868), PRFs | `Mac "HmacSHA1" / "HmacSHA256" / "HmacSHA384" / "HmacSHA512"` | 1+ | H | https://developer.android.com/reference/javax/crypto/Mac |
| AES-CMAC (PRF_AES128_CMAC, rarely used) | `Mac "AESCMAC"` | 31+ | H | https://developer.android.com/reference/javax/crypto/Mac |
| NAT-D hashes (SHA-1), cert hashes | `MessageDigest "SHA-1" / "SHA-256" / "SHA-384" / "SHA-512"` | 1+ | H | https://developer.android.com/reference/java/security/MessageDigest |
| MD4 (EAP-MSCHAPv2 NtPasswordHash) | not listed | none | H | https://developer.android.com/reference/java/security/MessageDigest |
| MODP DH (group 14) | `KeyAgreement "DH"`, `KeyPairGenerator "DH"`, `KeyFactory "DH"` | 1+ | H | https://developer.android.com/reference/javax/crypto/KeyAgreement · https://developer.android.com/reference/java/security/KeyPairGenerator |
| ECP DH (groups 19/20/21) | `KeyAgreement "ECDH"`, `KeyPairGenerator "EC"`, `KeyFactory "EC"` | 11+ | H | https://developer.android.com/reference/javax/crypto/KeyAgreement · https://developer.android.com/reference/java/security/KeyFactory |
| Curve25519 (group 31) | `KeyAgreement "XDH"`, `KeyPairGenerator "XDH"`, `KeyFactory "XDH"` | **33+** | H | https://developer.android.com/reference/javax/crypto/KeyAgreement |
| X25519 parameter spec | `NamedParameterSpec.X25519` | **33+** | H | https://developer.android.com/reference/java/security/spec/NamedParameterSpec |
| GCM params | `GCMParameterSpec(tLen, iv[, off, len])` | 19+ | H | https://developer.android.com/reference/javax/crypto/spec/GCMParameterSpec |
| AAD | `Cipher.updateAAD(byte[],int,int)` / `updateAAD(ByteBuffer)` | 19+ | H | https://developer.android.com/reference/javax/crypto/Cipher |
| Tag failure signal | `AEADBadTagException` | exists in reference | H | https://developer.android.com/reference/javax/crypto/AEADBadTagException |
| RSA sig (IKE AUTH method 1 / RFC 7427) | `Signature "SHA256withRSA"` etc. | 1+ | H | https://developer.android.com/reference/java/security/Signature |
| RSA-PSS | `Signature "SHA256withRSA/PSS"` (the bare `"RSASSA-PSS"` name is listed only for API 1-8) | 23+ | H | https://developer.android.com/reference/java/security/Signature |
| ECDSA (auth methods 9/10/11, RFC 7427) | `Signature "SHA256withECDSA"` / 384 / 512 | 11+ | H | https://developer.android.com/reference/java/security/Signature |
| Ed25519 | `Signature "Ed25519"` | 33+ | H | https://developer.android.com/reference/java/security/Signature |
| TLS exporter (EAP-TTLS key derivation) | `android.net.ssl.SSLEngines.exportKeyingMaterial` | **31+** | H | https://developer.android.com/reference/android/net/ssl/SSLEngines |
| ML-KEM / KEM (RFC 9370 additional key exchange) | `javax.crypto.KEM` has no Android reference page (HTTP 404 on 2026-09-28) | none | M | https://developer.android.com/reference/javax/crypto/KEM |
| Randomness | `SecureRandom()` (no provider) | 1+ | H | https://developer.android.com/reference/java/security/SecureRandom |

General rules from Android's crypto guide (H, https://developer.android.com/privacy-and-security/cryptography):
- Do not name a provider except for Android Keystore: "Android doesn't guarantee a particular provider for a given
  algorithm. Specifying a provider without using the Android Keystore system can cause compatibility problems."
- Explicit requests for the platform `"BC"` provider are deprecated; the `"Crypto"` provider was removed in API 28.
- Recommended algorithms list AES-GCM/CBC with 256-bit keys, SHA-2, HMAC-SHA2, ECDSA with SHA-2.

Provider background:
- Conscrypt provides "a large portion of Android cryptographic functionality such as key generators, ciphers, and
  message digests" and uses BoringSSL. It is shipped as the `com.android.conscrypt` APEX (updatable Mainline module).
  Android 10 also ships "a slimmed copy of Bouncy Castle to provide lower-popularity cryptographic tools" as part of
  ART, outside the Conscrypt module. (H) https://source.android.com/docs/core/ota/modular-system/conscrypt
- Consequence: which provider serves `"DH"` or `"DES"` is **not publicly documented**; log `getProvider().getName()` at
  runtime. [TEST]
- Android P blog: explicitly requesting deprecated BC algorithms throws `NoSuchAlgorithmException` for apps targeting P+.
  (H) https://android-developers.googleblog.com/2018/03/cryptography-changes-in-android-p.html

### 1.2 AES-GCM for ESP (RFC 4106) with the JCA

Wire rules (RFC 4106, H, https://www.rfc-editor.org/rfc/rfc4106.html):
- Explicit IV is **8 octets**, must never repeat for a key; "the most natural way to implement this is with a counter"
  (s. 3.1). Nonce = **4-byte salt || 8-byte IV** = 12 bytes (s. 4). Salt = last 4 bytes of the KEYMAT for that key:
  KEYMAT is 20 / 28 / 36 bytes for AES-128 / 192 / 256 (s. 8.1).
- AAD = SPI (4) || 32-bit seq (4) = **8 bytes**, or SPI || 64-bit ESN = **12 bytes** (s. 5).
- ICV = GCM tag, **16 octets MUST**, 8 or 12 MAY (s. 6). IANA/RFC 4106 transform IDs: 18 (ICV 8), 19 (ICV 12),
  **20 (ICV 16 = ENCR_AES_GCM_16)**. https://www.iana.org/assignments/ikev2-parameters/ikev2-parameters.xhtml
- Padding: minimum needed so the ciphertext ends on a 4-byte boundary, "less than four octets" (s. 3.2).

JCA mapping (Android reference, H):
- `Cipher.getInstance("AES/GCM/NoPadding")`; `init(mode, SecretKeySpec(key,"AES"), GCMParameterSpec(128, nonce12))`;
  `updateAAD(aad, 0, 8 or 12)`; then `doFinal`. AAD must be given before any `update`/`doFinal`.
  https://developer.android.com/reference/javax/crypto/Cipher
- The Cipher doc: "after each encryption operation using GCM mode, callers should re-initialize the cipher objects
  with GCM parameters which has a different IV value." Oracle's JCA guide says the same. So **one `init()` per packet is
  unavoidable in JCA** (the nonce changes every packet, in both directions).
  https://developer.android.com/reference/javax/crypto/Cipher ·
  https://docs.oracle.com/en/java/javase/17/security/java-cryptography-architecture-jca-reference-guide.html
- `doFinal(ByteBuffer in, ByteBuffer out)` "should be copy-safe, which means the input and output buffers can reference
  the same byte array" → encrypt/decrypt **in place** inside the packet buffer. After `doFinal` the cipher is reset to its
  init state. https://developer.android.com/reference/javax/crypto/Cipher
- Tag lengths: the `GCMParameterSpec` doc says GCM allows tLen {128, 120, 112, 104, 96} or {64, 32} for certain
  applications, and that other values "can be specified for this class, but not all CSP implementations will support
  them." Only 128 (ICV 16) is needed for ENCR_AES_GCM_16. Support for 96/64 in Conscrypt is **not publicly
  documented**. [TEST if ICV 8/12 ever negotiated]
  https://developer.android.com/reference/javax/crypto/spec/GCMParameterSpec
- Key sizes: the generic `"AES"` transformation takes the size from the key; `AES_128`/`AES_256` variants (26+) pin it.
  **192-bit GCM support is not explicitly documented** for Android. [TEST] FortiGate proposals in Fortinet examples use
  `aes128gcm`/`aes256gcm`. https://docs.fortinet.com/document/fortigate/7.6.4/administration-guide/567401/dialup-ipsec-vpn-using-custom-tcp-port
- IV-reuse enforcement: Oracle documents it as a usage rule; whether Conscrypt rejects a repeated key+IV on encrypt is
  **not publicly documented**. Irrelevant if the IV is the ESP sequence counter (never repeats inside one SA,
  RFC 4303 s. 3.3.3 forbids sequence cycling). https://www.rfc-editor.org/rfc/rfc4303.html

### 1.3 AES-CBC + HMAC-SHA-256-128 for ESP

- AES-CBC IV is 16 bytes; "The IV MUST be chosen at random, and MUST be unpredictable" (RFC 3602 s. 3). Padding so
  payload + padding + 2 trailer bytes is a multiple of 16 (s. 2.4). Use `"AES/CBC/NoPadding"` and add ESP padding
  yourself. https://www.rfc-editor.org/rfc/rfc3602.html
- Cheap unpredictable IVs: NIST SP 800-38A App. C gives two methods: (1) encrypt a unique nonce (e.g. a counter) with
  the forward cipher **under the same key**, or (2) an approved RNG. Method 1 = one `AES/ECB/NoPadding` block per packet
  instead of a `SecureRandom` call. (H) https://nvlpubs.nist.gov/nistpubs/Legacy/SP/nistspecialpublication800-38a.pdf
- HMAC-SHA-256-128 = HMAC-SHA-256 truncated to 128 bits; -384-192 and -512-256 likewise (RFC 4868).
  `Mac "HmacSHA256"` returns 32 bytes, truncate to 16. https://www.rfc-editor.org/rfc/rfc4868.html
- `Mac` can be initialised once per SA: `doFinal` "resets this Mac object to the state it was in when previously
  initialized ... available to generate another MAC from the same key". So HMAC has **no per-packet key setup**.
  (H) https://developer.android.com/reference/javax/crypto/Mac
- Inbound order: verify the ICV first, then decrypt (RFC 4303 s. 3.4.4). https://www.rfc-editor.org/rfc/rfc4303.html
- Constant-time compare: `MessageDigest.isEqual` implementation note says the time depends only on the length of the
  first argument (H for the current reference; whether API 29's libcore matches is not stated). Copy the 16-byte ICV
  into fixed arrays, or write a constant-time loop. https://developer.android.com/reference/java/security/MessageDigest
- RFC 8221: ENCR_AES_GCM_16 MUST, ENCR_AES_CBC MUST, ENCR_CHACHA20_POLY1305 SHOULD, AUTH_HMAC_SHA2_256_128 MUST,
  AUTH_HMAC_SHA1_96 MUST-. https://www.rfc-editor.org/rfc/rfc8221.html
  FortiGate phase-2 examples still offer `aes128-sha1`, so HMAC-SHA1-96 (12-byte ICV) should be supported too.
  https://docs.fortinet.com/document/fortigate/7.6.0/new-features/572770/allow-udp-port-443-for-dialup-ipsec-vpn-7-6-5

### 1.4 ECDH P-256 / P-384 / P-521 (IKE groups 19 / 20 / 21)

- `KeyAgreement "ECDH"` and `KeyPairGenerator "EC"` since API 11. (H) https://developer.android.com/reference/javax/crypto/KeyAgreement
- Curve names: JCA standard names are `secp256r1`, `secp384r1`, `secp521r1` for `ECGenParameterSpec`
  (https://docs.oracle.com/en/java/javase/17/docs/specs/security/standard-names.html). Android's reference does not
  list which names it accepts. (M) [TEST all three on API 29]
- IKE encoding (RFC 5903 s. 7): KE data = x || y, each fixed-length (256 / 384 / **528** bits → 32 / 48 / **66** bytes),
  zero-prefixed if needed. Shared secret = **x only**, same fixed length. https://www.rfc-editor.org/rfc/rfc5903.html
  JCA `ECDH` is "as defined in ANSI X9.63" (x-coordinate output, Oracle standard names). Output length padding by
  Conscrypt is **not publicly documented** → always left-pad to 32/48/66. [TEST]
- Build the peer key with `KeyFactory "EC"` + `ECPublicKeySpec(ECPoint(x, y), ownKey.params)`.
- RFC 6989 s. 2.3: receiver **MUST** check the peer point satisfies the curve equation. Whether `doPhase` rejects
  off-curve points is not documented → check explicitly. https://www.rfc-editor.org/rfc/rfc6989.html
- Why it matters: Fortinet's dial-up IKEv2 examples use `set dhgrp 20 21` (P-384 and P-521), not 19.
  https://docs.fortinet.com/document/fortigate/7.6.4/administration-guide/567401/dialup-ipsec-vpn-using-custom-tcp-port
  The FortiOS 7.4 CLI lists groups 1, 2, 5, 14 to 21, 27 to 32 (31 = Curve25519, 32 = Curve448), default 14.
  https://docs.fortinet.com/document/fortigate/7.4.0/cli-reference/331620/config-vpn-ipsec-phase1-interface

### 1.5 X25519 (IKE group 31, RFC 8031)

- Platform: `KeyAgreement/KeyPairGenerator/KeyFactory "XDH"` and `NamedParameterSpec.X25519` are **API 33+** only. (H)
  https://developer.android.com/reference/javax/crypto/KeyAgreement ·
  https://developer.android.com/reference/java/security/spec/NamedParameterSpec
- Conscrypt module notes list "Added limited support for X25519 keys, key agreements, and signatures" under Android 14
  changes. Conscrypt is updatable, so a newer module might exist on older devices, but `NamedParameterSpec` is a
  framework class that only exists from API 33, so do not rely on it for API 29-32. (M)
  https://source.android.com/docs/core/ota/modular-system/conscrypt
- X448 (group 32): `NamedParameterSpec.X448` exists from API 33, but Conscrypt only claims X25519. Platform X448
  support is **not publicly documented**. (M)
- Encoding: KE data is the raw 32-byte u-coordinate (RFC 8031 s. 3.1 → RFC 7748 s. 6); receivers **MUST mask the MSB of
  the last byte** and accept non-canonical values (RFC 8031 s. 3.2). https://www.rfc-editor.org/rfc/rfc8031.html
  RFC 7748: both sides MAY check the all-zero shared secret. https://www.rfc-editor.org/rfc/rfc7748.html
- JCA keys use X.509 SubjectPublicKeyInfo (RFC 8410, OID 1.3.101.110) → own raw key = last 32 bytes of
  `getEncoded()`; peer key = `KeyFactory("XDH").generatePublic(X509EncodedKeySpec(fixed 12-byte prefix || raw))`.
  https://www.rfc-editor.org/rfc/rfc8410.html
- API 29-32: use Bouncy Castle's lightweight `X25519Agreement` or `org.bouncycastle.math.ec.rfc7748.X25519` (section 2).
  RFC 8247 lists group 31 only via RFC 8031, and group 19 as SHOULD, group 14 as MUST, so X25519 is optional for
  interop; offer it only where available. https://www.rfc-editor.org/rfc/rfc8247.html

### 1.6 DH MODP 2048 (IKE group 14)

- `KeyPairGenerator "DH"` initialised with `DHParameterSpec(p, g=2, l)` where p is the RFC 3526 s. 3 prime; then
  `KeyAgreement "DH"`. All API 1+. (H) https://developer.android.com/reference/javax/crypto/spec/DHParameterSpec ·
  https://www.rfc-editor.org/rfc/rfc3526.html
- `l` = private exponent size in bits. RFC 3526 table: group 14 strength 110 to 160 bits, exponent 220 to 320+ bits;
  "you must use more than 256 bits of randomness in the exponent" for 128-bit strength. Smaller `l` = much faster
  keygen and agreement. https://www.rfc-editor.org/rfc/rfc3526.html
- KE data and g^ir must be the full modulus length, big-endian, zero-padded (RFC 7296 s. 2.14). Normalise BigInteger /
  JCA output to exactly 256 bytes. https://www.rfc-editor.org/rfc/rfc7296.html
- RFC 6989: check the peer value is in range 1 < r < p-1. https://www.rfc-editor.org/rfc/rfc6989.html
- RFC 8247 status: group 14 MUST, group 19 SHOULD. FortiOS default `dhgrp` is 14.
  https://www.rfc-editor.org/rfc/rfc8247.html · https://docs.fortinet.com/document/fortigate/7.4.0/cli-reference/331620/config-vpn-ipsec-phase1-interface
- Provider and constant-time behaviour of Android DH / `BigInteger.modPow` are **not publicly documented**. Keys are
  ephemeral per exchange, which limits exposure. (M)

### 1.7 SecureRandom

- Use `SecureRandom()` without naming a provider; `"SHA1PRNG","Crypto"` throws since API 28.
  https://developer.android.com/privacy-and-security/cryptography
- "SecureRandom objects are safe for use by multiple concurrent threads." (H)
  https://developer.android.com/reference/java/security/SecureRandom
- Uses: IKE SPIs, nonces Ni, DH/ECDH private keys (via KeyPairGenerator), CBC IVs (or SP 800-38A method 1).

### 1.8 Performance notes and recommended patterns

Facts:
- Conscrypt is built on BoringSSL (https://conscrypt.org/ ·
  https://source.android.com/docs/core/ota/modular-system/conscrypt). BoringSSL exposes `EVP_has_aes_hardware` ("we
  enable hardware support for fast and constant-time AES-GCM") (H)
  https://commondatastorage.googleapis.com/chromium-boringssl-docs/aead.h.html. That Conscrypt's JCA `Cipher` path uses
  ARMv8 AES/PMULL instructions is therefore likely but **not stated in Android docs**. (M)
- Not every Android 10+ device has AES instructions: CDD 9.9.3 [C-1-12] requires AES-256-XTS storage encryption "if the
  device has AES instructions (ARMv8 Cryptography Extensions)", and lets devices without them use Adiantum. (H)
  https://source.android.com/docs/compatibility/10/android-10-cdd → on those devices ChaCha20-Poly1305 (API 28+,
  RFC 7634, FortiGate supports `chacha20poly1305`) is the better ESP cipher. (M for performance, no numbers published)
- Native CPU feature check: `getauxval(AT_HWCAP)` from the NDK. https://developer.android.com/ndk/guides/cpu-features
- Per-packet `Cipher.init()` cost in Conscrypt (key schedule redone or cached?) is **not publicly documented**. Measure it
  with Jetpack Microbenchmark on a low-end and a high-end device before choosing the architecture. [TEST]
  https://developer.android.com/topic/performance/benchmarking/microbenchmark-overview
- Android Keystore keys are unsuitable for per-packet ESP: "plaintext, ciphertext ... are fed to a system process"
  (IPC per operation); StrongBox "is slower". Keep IKE/ESP keys as in-memory `SecretKeySpec`.
  https://developer.android.com/privacy-and-security/keystore
- High-rate native path: BoringSSL `EVP_AEAD_CTX` is initialised once per key; `EVP_AEAD_CTX_seal/open` take the nonce
  per call, allow in-place (`out == in`), and "may be called concurrently ... on the same EVP_AEAD_CTX". (H)
  https://commondatastorage.googleapis.com/chromium-boringssl-docs/aead.h.html
  Apps may not link the platform `libcrypto.so` (private since Android 7.0); the app must **bundle its own copy**.
  https://developer.android.com/about/versions/nougat/android-7.0-changes

Recommended patterns (engineering recommendations, not doc claims):
1. One TX thread (TUN read → encrypt → UDP send) and one RX thread (UDP receive → decrypt → TUN write). Each owns its
   own `Cipher`/`Mac` objects per SA. Thread-safety of `Cipher` is **not stated** in the Android or Oracle docs, so never
   share one.
2. Pre-allocate packet buffers with headroom for outer headers; encrypt in place with `doFinal(ByteBuffer, ByteBuffer)`
   or the `byte[]`/offset overloads; reuse a nonce array; allocate only the small `GCMParameterSpec` per packet.
3. GCM: `init` + `updateAAD` + `doFinal` per packet. CBC+HMAC: `Mac` init once per SA; CBC IV via one AES-ECB block.
4. Replay window on RX: at least 32, default 64 (RFC 4303 s. 3.4.3); rekey before the sequence number would cycle.
   https://www.rfc-editor.org/rfc/rfc4303.html
5. Start in Kotlin/JCA. Move the ESP data path to NDK + bundled BoringSSL only if the benchmark shows JCA `init` cost
   dominates at target throughput. IKE (a few messages per minute) never needs native code.

---

## 2. Bouncy Castle as a fallback

- **License: MIT.** Page text: "Copyright (c) 2000 - 2023 The Legion of the Bouncy Castle Inc. ... Permission is hereby
  granted, free of charge ..." (standard MIT wording). Extra third-party code exists only in the OpenPGP module (BZIP2,
  Apache 2.0) and the MLS module (gRPC Apache 2.0, protobuf BSD-3). The core provider (`bcprov`) is plain MIT. (H)
  https://www.bouncycastle.org/about/license/
- **Appropriate as a fallback:** yes. It is a crypto library, not a VPN/IPsec implementation, so linking it does not touch
  the repo's clean-room rule. Useful pieces:
  - X25519 on API 29-32: `org.bouncycastle.crypto.agreement.X25519Agreement` (`init`, `getAgreementSize`,
    `calculateAgreement(pub, buf, off)`), or the low-level `org.bouncycastle.math.ec.rfc7748.X25519`.
    https://downloads.bouncycastle.org/java/docs/bcprov-jdk18on-javadoc/org/bouncycastle/crypto/agreement/X25519Agreement.html ·
    https://downloads.bouncycastle.org/java/docs/bcprov-jdk18on-javadoc/org/bouncycastle/math/ec/rfc7748/X25519.html
  - X448 (group 32) on all API levels (BC provider has X448 key agreement per its javadoc listing; M).
  - MD4 for EAP-MSCHAPv2: `org.bouncycastle.crypto.digests.MD4Digest`.
    https://downloads.bouncycastle.org/java/docs/bcprov-jdk18on-javadoc/org/bouncycastle/crypto/digests/MD4Digest.html
    (Alternative: implement MD4 from RFC 1320, ~100 lines, test vectors in the RFC.) https://www.rfc-editor.org/rfc/rfc1320.html
  - TLS exporter for EAP-TTLS on API 29-30: `bctls` `TlsContext.exportKeyingMaterial(String, byte[], int)`.
    https://downloads.bouncycastle.org/java/docs/bctls-jdk18on-javadoc/org/bouncycastle/tls/TlsContext.html
- **How to use it on Android:** call the lightweight classes directly; do **not** register BC as a JCA provider:
  - Android already has a provider named `"BC"` (the guide's deprecation example uses `Security.getProvider("BC")`), and
    `Security.addProvider` "returns -1 if the provider was not added because it is already installed".
    https://developer.android.com/privacy-and-security/cryptography ·
    https://developer.android.com/reference/java/security/Security
  - Whether the platform's BC classes are repackaged (so a bundled `org.bouncycastle` jar cannot clash) is **not
    publicly documented** in the allowed sources. [TEST: build, run on API 29 and 35]
- **Size:** bcprov is large; rely on R8 shrinking to keep only referenced classes.
  https://developer.android.com/topic/performance/app-optimization/enable-app-optimization
- BC's algorithm overview page lists EdDSA/XDH (RFC 7748/8032/8410) support. https://www.bouncycastle.org/documentation/specification_interoperability/

---

## 3. VpnService specifics for IPsec

### 3.1 Sockets, protect() and ports

- `protect(DatagramSocket)`, `protect(Socket)` and `protect(int fd)` (all API 14): "data sent through this socket will go
  directly to the underlying network ... a VPN tunnel should protect itself if its destination is covered by VPN routes.
  Otherwise its outgoing packets will be sent back to the VPN interface and cause an infinite loop. This method will fail
  if the application is not prepared or is revoked. The socket is NOT closed by this method." (H)
  https://developer.android.com/reference/android/net/VpnService
- Order from the VPN guide: `prepare()` → `protect()` the tunnel socket → `DatagramSocket.connect()` to the gateway →
  `Builder` → `establish()`. (H) https://developer.android.com/develop/connectivity/vpn
  So IKE_SA_INIT/IKE_AUTH run over protected sockets **before** the TUN exists; that is the natural IKEv2 order
  (config payload gives the inner address first).
- Alternative to per-socket protect: `Builder.addDisallowedApplication(ownPackage)`: "Denied applications will use
  networking as if the VPN wasn't running." (H) https://developer.android.com/reference/android/net/VpnService.Builder
- Pinning to a network: `Network.bindSocket(DatagramSocket)` ("The socket must not be connected"), then
  `setUnderlyingNetworks(...)`, which "only needs to be called if the VPN has explicitly bound its underlying
  communications channels". (H) https://developer.android.com/reference/android/net/Network ·
  https://developer.android.com/reference/android/net/VpnService
- UDP 500 and 4500 (RFC 7296 s. 2.23, H, https://www.rfc-editor.org/rfc/rfc7296.html):
  - After a NAT is detected, all traffic moves to 4500; IKE on 4500 carries a 4-byte zero non-ESP marker; ESP follows
    the UDP header directly (SPI is never zero).
  - "An initiator can use port 4500 for both IKE and ESP, regardless of whether or not there is a NAT, even at the
    beginning of IKE." Useful because RFC 4787 REQ-5a lets NATs apply shorter timers to well-known destination ports
    (0-1023), which includes 500 but not 4500. https://www.rfc-editor.org/rfc/rfc4787.html
  - RFC 3948 shares one port for IKE and ESP so there is "only one NAT mapping ... no need to send separate IKE
    keepalives". https://www.rfc-editor.org/rfc/rfc3948.html
  - FortiGate behaviour: even with `nattraversal forced`, "The FortiGate still sends this negotiation in UDP port 500 at
    the initial negotiation stage and switches to UDP 4500 when NAT is detected"; DPD uses 4500 when NAT-T is on.
    https://community.fortinet.com/t5/FortiGate/Technical-Tip-IPSec-VPN-NAT-traversal/ta-p/197873
    Whether FortiGate accepts IKE_SA_INIT initiated directly on 4500 is [TRACE].
  - FortiOS 7.6.5+ can move the IKE UDP port to 443 (`config system settings / set ike-port 443`), so the port must be a
    profile field, not a constant.
    https://docs.fortinet.com/document/fortigate/7.6.0/new-features/572770/allow-udp-port-443-for-dialup-ipsec-vpn-7-6-5
- TCP 443 (RFC 9329): each message is prefixed by a 16-bit length (which includes itself); IKE messages start with the
  non-ESP marker; the stream begins with the ASCII prefix "IKETCP"; "The maximum message length is used as the effective
  MTU"; ESP NAT-keepalives "SHOULD NOT be sent when using TCP encapsulation"; TCP-in-TCP can cause "TCP meltdown"
  (s. 9.1). (H) https://www.rfc-editor.org/rfc/rfc9329.html
  - FortiGate: `set transport tcp|auto` per tunnel; `ike-tcp-port` "(1 - 65535, default = 443)"; IKEv2 only; needs
    FortiClient 7.4.1+ on Fortinet's side; not NPU-offloaded. (H)
    https://docs.fortinet.com/document/fortigate/7.6.4/administration-guide/567401/dialup-ipsec-vpn-using-custom-tcp-port
  - Android side: a normal `Socket` + `protect(Socket)` before `connect()`. Nothing special. (H for the API)

### 3.2 Why ESP must be encapsulated in a userspace client

- Receiving or sending raw IP protocol 50 needs a raw socket. That ordinary Android apps cannot open raw sockets is
  **not stated in the allowed Android docs** (it follows from Linux capabilities). [TEST: `Os.socket(AF_INET, SOCK_RAW,
  50)` should fail with EPERM/EACCES]
- `IpSecManager` (kernel ESP) is not a way out: "Applications may create transport mode security associations and apply
  them to individual sockets. Applications looking to create an IPsec VPN should use VpnManager and Ikev2VpnProfile."
  (H) https://developer.android.com/reference/android/net/IpSecManager
- RFC 7296 s. 2.23: "Either side can decide whether or not to use UDP encapsulation for ESP irrespective of the choice
  made by the other side. However, if a NAT is detected, both devices MUST use UDP encapsulation." So without a NAT the
  gateway may legally send raw ESP that the app cannot receive. Mitigations:
  - Phones are almost always behind a NAT (carrier CGN, home Wi-Fi), so encapsulation normally happens anyway. (M)
  - FortiGate `set nattraversal forced`: "the FortiGate will use a port value of zero when constructing the NAT discovery
    hash for the peer. This causes the peer to think it is behind a NAT device, and it will use UDP encapsulation for
    IPsec, even if no NAT is present. This approach maintains interoperability with any IPsec implementation that
    supports the NAT-T RFC." Default is `enable` (not forced). (H)
    https://docs.fortinet.com/document/fortigate/7.4.3/administration-guide/790613/phase-1-configuration ·
    https://docs.fortinet.com/document/fortigate/7.4.0/cli-reference/331620/config-vpn-ipsec-phase1-interface
  - Client side, the same trick (a deliberately non-matching NAT_DETECTION_SOURCE_IP) makes the gateway detect a NAT,
    which triggers the RFC 7296 "MUST use UDP encapsulation" rule. (M, derived from RFC 7296 + Fortinet's description)
    [TRACE: confirm FortiGate then sends ESP-in-UDP]

### 3.3 Choosing the TUN MTU

ESP tunnel mode over UDP (RFC 4303 + RFC 3948), outer IPv4:

| Part | AES-GCM-16, 8-byte IV | AES-CBC + HMAC-SHA-256-128 | Source |
|---|---|---|---|
| Outer IPv4 header | 20 | 20 | https://www.rfc-editor.org/rfc/rfc791.html |
| UDP header (NAT-T) | 8 | 8 | https://www.rfc-editor.org/rfc/rfc3948.html |
| SPI + sequence | 8 | 8 | https://www.rfc-editor.org/rfc/rfc4303.html |
| IV | 8 | 16 | https://www.rfc-editor.org/rfc/rfc4106.html · https://www.rfc-editor.org/rfc/rfc3602.html |
| Pad length + next header | 2 | 2 | https://www.rfc-editor.org/rfc/rfc4303.html |
| Padding | 0 to 3 (4-byte alignment) | 0 to 15 (16-byte block) | RFC 4106 s. 3.2 · RFC 3602 s. 2.4 |
| ICV | 16 | 16 | RFC 4106 s. 6 · https://www.rfc-editor.org/rfc/rfc4868.html |
| **Total overhead** | **62 fixed, 62 to 65** | **70 fixed, 70 to 85** | computed |

RFC 4106 s. 7 confirms the GCM number: IV 8 + ICV 16 + "10-13 octets taken up by the ESP SPI, Sequence Number, Padding,
Pad Length, and Next Header" = 34 to 37, plus 28 for IPv4 + UDP.

Other suites (same method): ChaCha20-Poly1305 = same as GCM-16 (8-byte IV, 16-byte tag, RFC 7634,
https://www.rfc-editor.org/rfc/rfc7634.html); AES-CBC + HMAC-SHA1-96 = 66 to 81; + HMAC-SHA-384-192 = 78 to 93;
+ HMAC-SHA-512-256 = 86 to 101.

Largest inner packet (= TUN MTU) for a given underlying MTU (computed: GCM ciphertext rounded down to a multiple of 4,
CBC ciphertext to a multiple of 16, minus the 2 trailer bytes):

| Underlying MTU | Outer | AES-GCM-16 | AES-CBC + SHA-256-128 | AES-CBC + SHA1-96 |
|---|---|---|---|---|
| 1500 | IPv4 + UDP | **1438** | **1422** | 1422 |
| 1500 | IPv6 + UDP (e.g. via 464XLAT) | 1418 | 1406 | 1406 |
| 1400 | IPv4 + UDP | 1338 | 1326 | 1326 |
| 1358 | IPv4 + UDP | 1294 | 1278 | 1278 |
| 1358 | IPv6 + UDP | 1274 | 1262 | 1262 |
| 1280 | IPv4 + UDP | 1218 | 1198 | 1214 |
| 1500 | IPv4 + TCP (20 B hdr) + 2 B length (RFC 9329) | 1422 | 1406 | n/c |
| 1500 | IPv4 + TCP with 12 B timestamp option + 2 B length | 1410 | 1390 | n/c |

Inputs and recommendations:
- `Builder.setMtu(int)`: "If it is not set, the default value in the operating system will be used." The default value
  is not documented → always set it. (H) https://developer.android.com/reference/android/net/VpnService.Builder
- Underlying MTU: `LinkProperties.getMtu()` (API 29) "Gets any non-default MTU size set for this link ... if the default
  is being used this will return 0" → treat 0 as 1500. (H) https://developer.android.com/reference/android/net/LinkProperties
- Cellular MTUs vary: "many 3GPP networks do not have a standard MTU setting" and 3GPP TS 23.060 suggests a link MTU of
  **1358** to avoid fragmentation in the GTP transport (RFC 7849). (H) https://www.rfc-editor.org/rfc/rfc7849.html
- IPv6-only carriers with 464XLAT translate the outer IPv4 packet to IPv6 at the CLAT (RFC 6877), adding 20 bytes
  (40-byte IPv6 header vs 20). `LinkProperties.getNat64Prefix()` (API 30) reveals NAT64 on a link. (H for API, M for
  applying it to MTU) https://www.rfc-editor.org/rfc/rfc6877.html · https://developer.android.com/reference/android/net/LinkProperties
- Do not rely on IP fragmentation of the outer packet: "more and more ISPs use equipment that drops IP fragments"
  (RFC 7383, about CGNs). Also means IKE_AUTH with certificates should use IKEv2 fragmentation (RFC 7383). FortiGate
  `fragmentation-mtu` default is 1200. (H) https://www.rfc-editor.org/rfc/rfc7383.html ·
  https://docs.fortinet.com/document/fortigate/7.4.0/cli-reference/331620/config-vpn-ipsec-phase1-interface
- Practical choice (recommendation): compute `tunMtu = floor-to-alignment(underlyingMtu - overhead(outerFamily, suite))`
  when establishing; on a network switch, either rebuild the interface with `establish()` (the system replaces the old
  interface: "The existing interface is deactivated when a new one is created", https://developer.android.com/reference/android/net/VpnService)
  or pick one conservative value (e.g. 1280 to 1360) that fits both Wi-Fi and cellular. The engine sees every inner TCP
  SYN, so it can also clamp MSS in userspace. Whether the outer UDP socket sets DF is **not publicly documented** for
  Android. [TEST with a large ping through the tunnel]

### 3.4 IPv4-only inner tunnel

- `addAddress` accepts IPv4 or IPv6; "Adding an address implicitly allows traffic from that address family".
- `allowFamily`: "By default, if no address, route or DNS server of a specific family (IPv4 or IPv6) is added to this VPN,
  then all outgoing traffic of that family is blocked." (H)
  https://developer.android.com/reference/android/net/VpnService.Builder
  - Full tunnel (0.0.0.0/0): leave IPv6 blocked → no IPv6 leak around the tunnel.
  - Split tunnel (FortiGate split-include): call `allowFamily(AF_INET6)` so IPv6 "fall[s]-through to the underlying
    network", otherwise the phone loses IPv6 internet while connected.
- The outer (carrier) side may still be IPv6 (DNS64/464XLAT); protected sockets handle that, only the MTU changes (3.3).
- `excludeRoute` (API 33) is not needed for the gateway address because the tunnel socket is protected.
- Edge case: apps targeting SDK 37 need `ACCESS_LOCAL_NETWORK` to reach local-network addresses (e.g. testing against a
  FortiGate on the same Wi-Fi LAN). UDP failures show as EPERM. (H)
  https://developer.android.com/privacy-and-security/local-network-permission

### 3.5 Keepalives with the screen off (Doze, alarms, wake locks)

What the system does:
- `Thread.sleep`, `Object.wait`, `System.nanoTime` and most interval timing use `uptimeMillis()`, which "stops when the
  system enters deep sleep"; "if the device enters sleep, the remainder of the time will be postponed until the device
  wakes up." Handler also uses this clock. → **A coroutine `delay()` keepalive loop does not fire while the CPU sleeps.**
  (H) https://developer.android.com/reference/android/os/SystemClock
- Doze: "Suspends network access. Ignores wake locks. Defers standard AlarmManager alarms"; `setAndAllowWhileIdle` /
  `setExactAndAllowWhileIdle` cannot fire "more than once per nine minutes, per app". (H)
  https://developer.android.com/training/monitoring-device-state/doze-standby
- `setExactAndAllowWhileIdle` doc: normally not "more than about every minute"; in idle "may be significantly longer,
  such as 15 minutes"; apps targeting 31+ need `SCHEDULE_EXACT_ALARM`. (H)
  https://developer.android.com/reference/android/app/AlarmManager
- Power table: Doze "While-idle alarms: Limited to 7 per hour"; an app process running a **foreground service** has
  Network: "No restrictions". (H) https://developer.android.com/topic/performance/power/power-details
  → The VPN service must stay in the foreground (the guide requires `startForeground()` for background starts,
  https://developer.android.com/develop/connectivity/vpn), and keeps network access, but its timers still need the CPU.
- Foreground-service type: `systemExempted` is allowed for "VPN apps (configured using Settings > Network & Internet >
  VPN)". (H) https://developer.android.com/develop/background-work/services/fgs/service-types
- Partial wake locks: Play vitals flags "holding a non-exempted partial wake lock for at least two hours on average
  while the screen is off in more than 5% of user sessions in the past 28 days"; from 1 March 2026 Play applies store
  treatments (listing warnings, exclusion from recommendations). A VPN wake lock is not in the exempt list (audio,
  location, user-initiated jobs). (H) https://android-developers.googleblog.com/2026/03/battery-technical-quality-enforcement.html ·
  https://developer.android.com/topic/performance/vitals/excessive-wakelock
- Battery-optimisation exemption lets an app "use the network and hold partial wake locks during Doze", but Play only
  allows `ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` for listed use cases; VPN is not listed ("enterprise VOIP apps"
  and "Doze ... break the core function" are). (H) https://developer.android.com/training/monitoring-device-state/doze-standby

Options for NAT keepalives while idle:
1. **Hardware offload (best for battery, needs a prototype).** `ConnectivityManager.createSocketKeepalive(network,
   UdpEncapsulationSocket, src, dst, executor, callback)` (API 29): "Request that keepalives be started on a IPsec NAT-T
   socket." `SocketKeepalive` "Allows applications to request that the system periodically send specific packets on
   their behalf, using hardware offload to save battery power"; interval **10 to 3600 s**; "For cellular, the device
   MUST support at least 1 keepalive slot. For WiFi, the device SHOULD support keepalive offload ... at least 3". (H)
   No extra permission is listed on the reference pages (M, [TEST]).
   https://developer.android.com/reference/android/net/ConnectivityManager ·
   https://developer.android.com/reference/android/net/SocketKeepalive
   Catch: it only accepts an `IpSecManager.UdpEncapsulationSocket` ("a system-provided datagram socket intended for IKEv2
   signalling and UDP encapsulated IPsec traffic", obtained from `openUdpEncapsulationSocket()`; it cannot be re-bound;
   use `getFileDescriptor()`). https://developer.android.com/reference/android/net/IpSecManager.UdpEncapsulationSocket
   **Whether inbound ESP-in-UDP on that socket is delivered to userspace (rather than consumed by the kernel's ESP
   decapsulation with no matching SA) is not publicly documented.** [TEST: open encap socket, protect its fd, run
   IKE + userspace ESP, check RX]. If it works, the whole data path can use this socket and get free keepalives.
2. **Wake lock + timer.** Reliable but trips the Play "excessive wake lock" threshold for any session > 2 h screen-off.
   Acceptable only for a short "keep alive for N minutes" user mode, or for sideloaded builds.
3. **Alarms.** Too coarse in Doze (9 to 15 min, 7/h) for NAT timers of 30 s to 5 min. Useful only as a watchdog.
4. **Rely on the gateway's packets.** FortiGate sends its own NAT-T keepalives when NAT-T is on (`keepalive` default 10 s,
   range 10 to 900); the admin guide says "The keepalive packet is a 138-byte ISAKMP exchange" (so possibly not the
   RFC 3948 one-byte 0xFF packet). [TRACE] https://docs.fortinet.com/document/fortigate/7.4.3/administration-guide/790613/phase-1-configuration
   But inbound packets are not a reliable refresh: RFC 4787 REQ-6 makes outbound refresh MUST and inbound refresh only
   MAY; RFC 7857 says inbound packets on EIF mappings that do not create a session "SHOULD NOT refresh the mapping".
   https://www.rfc-editor.org/rfc/rfc4787.html · https://www.rfc-editor.org/rfc/rfc7857.html
   Every inbound packet also wakes the radio and probably the CPU (wake-on-packet behaviour is not publicly documented).
5. **Let the mapping die and recover.** RFC 7296 s. 2.23: a host not behind a NAT "SHOULD send all packets ... to the IP
   address and port in the validated packet" (dynamic address update). If FortiGate does this, the client's next
   authenticated outbound packet re-creates the NAT mapping and inbound flow resumes; only unsolicited inbound traffic
   is lost while idle. [TRACE: idle past the carrier NAT timeout, then send; see if FortiGate follows the new port]
   https://www.rfc-editor.org/rfc/rfc7296.html
6. **TCP transport while idle.** TCP mappings last longer: RFC 5382 REQ-5 established idle-timeout "MUST NOT be less than
   2 hours 4 minutes" (though RFC 5626 notes "NATs with TCP timeouts as low as 15 minutes"). Costs TCP-in-TCP
   performance. https://www.rfc-editor.org/rfc/rfc5382.html · https://www.rfc-editor.org/rfc/rfc5626.html

Also relevant: Android's own platform VPN has automatic NAT-T keepalive timers "based on internal platform signals"
(`Ikev2VpnProfile.Builder.setAutomaticNattKeepaliveTimerEnabled`, API 34, needs `FEATURE_IPSEC_TUNNELS`), which a
VpnService app cannot use. https://developer.android.com/reference/android/net/Ikev2VpnProfile.Builder

### 3.6 Battery implications

- Radio tail: in Android's 3G model a transfer keeps the radio at full power for the transfer + 5 s, then 12 s at low
  power, so "an app which makes a one second data transfer, three times a minute, will keep the wireless radio
  perpetually active". A 20 s keepalive is exactly that pattern. (H)
  https://developer.android.com/develop/connectivity/network-ops/network-access-optimization
- RFC 7849 quotes measurements: with a **20 s** keepalive (RFC 3948 default) a device draws 29 mA (2G) / 34 mA (3G);
  40 s → 16 / 24 mA; 150 s → 9.1 / 16 mA; 180 s → 7.3 / 14 mA; no keepalive → 5.2 / 6.1 mA. (H, dated 2G/3G data)
  https://www.rfc-editor.org/rfc/rfc7849.html
- RFC 8085: "on battery-powered devices ... the frequency at which keep-alive messages are sent can become the
  determining factor that governs power consumption". https://www.rfc-editor.org/rfc/rfc8085.html
- Implication: the keepalive interval is the main battery lever. Use the longest interval that keeps the mapping, merge
  keepalives with real traffic (RFC 3948 only sends one "if no other packet to the peer has been sent in M seconds"),
  add jitter, and prefer hardware offload if 3.5 option 1 works.

---

## 4. NAT keepalive intervals: what the sources say

| Source | Statement | URL |
|---|---|---|
| RFC 3948 s. 4 | Send a NAT-keepalive "if no other packet to the peer has been sent in M seconds. M ... default value of 20 seconds"; keepalive = 1-byte 0xFF payload; must not be used for liveness | https://www.rfc-editor.org/rfc/rfc3948.html |
| RFC 4787 REQ-5 | "A NAT UDP mapping timer MUST NOT expire in less than two minutes" (except well-known dest ports 0-1023); "A default value of five minutes or more ... is RECOMMENDED"; "There is great variation in the values used by different NATs" | https://www.rfc-editor.org/rfc/rfc4787.html |
| RFC 4787 REQ-6 | Outbound refresh MUST; inbound refresh MAY | same |
| RFC 6888 | Carrier-grade NATs must comply with RFC 4787 (it updates RFC 4787) | https://www.rfc-editor.org/rfc/rfc6888.html |
| RFC 8085 s. 3.5 | Keepalives "SHOULD NOT [be transmitted] more frequently than once every 15 seconds and SHOULD use longer intervals when possible"; "empirical evidence suggests that a significant fraction of currently deployed middleboxes unfortunately use shorter timeouts" than 2 min; add jitter | https://www.rfc-editor.org/rfc/rfc8085.html |
| RFC 5626 s. 4.4.2 (UDP) and 4.4.1 (TCP/CRLF) | UDP STUN keepalive every 24 to 29 s "as many NATs have UDP timeouts as low as 30 seconds"; connection-oriented keepalive 95 to 120 s, or 672 to 840 s "where battery power is a concern" ("NATs with TCP timeouts as low as 15 minutes") | https://www.rfc-editor.org/rfc/rfc5626.html |
| RFC 8445 s. 11 | ICE keepalive Tr SHOULD be 15 s, MUST NOT be smaller | https://www.rfc-editor.org/rfc/rfc8445.html |
| RFC 7849 | Battery cost of 20/40/150/180 s keepalives (see 3.6); recommends PCP to reduce keepalives | https://www.rfc-editor.org/rfc/rfc7849.html |
| RFC 7857 | Inbound packets SHOULD NOT refresh EIF mappings; TCP transitory idle timeout default 4 min recommended | https://www.rfc-editor.org/rfc/rfc7857.html |
| RFC 5382 REQ-5 | TCP established idle-timeout MUST NOT be less than 2 h 4 min | https://www.rfc-editor.org/rfc/rfc5382.html |
| RFC 9329 s. 6.6 | No ESP NAT-keepalives over TCP encapsulation | https://www.rfc-editor.org/rfc/rfc9329.html |
| FortiOS CLI | `keepalive`: "NAT-T keep alive interval", min 10, max 900, **default 10**; `nattraversal` default enable; `dpd` default on-demand; `dpd-retrycount` default 3 | https://docs.fortinet.com/document/fortigate/7.4.0/cli-reference/331620/config-vpn-ipsec-phase1-interface |
| FortiOS admin guide | "The keepalive interval must be smaller than the session lifetime value used by the NAT device." | https://docs.fortinet.com/document/fortigate/7.4.3/administration-guide/790613/phase-1-configuration |
| Android IKE API | `IkeSessionParams.Builder.setNattKeepAliveDelaySeconds`: "Defaults to 10 seconds. MUST be a value from 10 seconds to 3600 seconds"; DPD default 120 s | https://developer.android.com/reference/android/net/ipsec/ike/IkeSessionParams.Builder |

Carrier-specific measured timeouts: **not available from the allowed sources** (published measurements are academic
papers, outside this task's source list). The IETF texts above only say "as low as 30 seconds" (RFC 5626) and "a
significant fraction ... shorter" than 2 minutes (RFC 8085).

Recommendation (derived): start at 20 s (RFC 3948 default, above the RFC 8085 15 s floor, below the 30 s worst case in
RFC 5626), add ±10% jitter, only send when no other outbound packet went out in the interval, and optionally probe
upward (e.g. 20 → 45 → 90 → 110 s, never past the 2 min RFC 4787 floor) per network, falling back when a DPD or
inbound-silence check shows the mapping died. Remember that the gateway default is 10 s, so a FortiGate admin may expect
at least that from FortiClient; whether FortiGate tears down a peer that sends fewer keepalives is [TRACE].

---

## 5. EAP-related primitives (FortiGate dial-up usually means EAP)

- Fortinet KB: EAP-MSCHAPv2 is "default for FortiClient" with IKEv2; EAP-TTLS from FortiClient 7.4.3. (H)
  https://community.fortinet.com/fortigate-3/technical-tip-ikev2-dial-up-vpn-with-ldap-authentication-207007
- EAP-MSCHAPv2 (RFC 2759): `NtPasswordHash` uses MD4 (s. 8.3) → not on Android, use BC `MD4Digest` or RFC 1320;
  `DesEncrypt` = DES-ECB with a 7-byte key expanded to 8 (s. 8.6) → `Cipher "DES/ECB/NoPadding"` (listed 1+; provider
  not documented) [TEST]; `ChallengeHash` uses SHA-1. https://www.rfc-editor.org/rfc/rfc2759.html
- EAP-TTLS (RFC 5281): keying material = PRF(master_secret, "ttls keying material", client_random + server_random),
  which is the RFC 5705 exporter with that label and no context. Android exposes it as
  `SSLEngines.exportKeyingMaterial(engine, label, context, length)` on **API 31+**, and only for "engines from the
  platform TLS provider". TLS 1.3 uses the exporter label "EXPORTER_EAP_TLS_Key_Material" (RFC 9427). API 29-30 need
  bctls. https://www.rfc-editor.org/rfc/rfc5281.html · https://www.rfc-editor.org/rfc/rfc5705.html ·
  https://www.rfc-editor.org/rfc/rfc9427.html · https://developer.android.com/reference/android/net/ssl/SSLEngines
- `SSLEngine` is transport-agnostic, so EAP-TTLS TLS records can be carried in IKE EAP payloads (JCA/JSSE lists
  `SSLEngine.Supported`). https://developer.android.com/privacy-and-security/cryptography

## 6. Context: the platform alternative and why it does not fit

- `VpnManager` + `Ikev2VpnProfile` (API 30) provisions a platform IKEv2 VPN; auth is PSK, digital signature, or
  username/password which "will configure IKEv2 authentication using EAP-MSCHAPv2". `setMaxMtu` must be ≥ 1280.
  https://developer.android.com/reference/android/net/Ikev2VpnProfile ·
  https://developer.android.com/reference/android/net/Ikev2VpnProfile.Builder
- There is no API surface for EAP-TTLS or an interactive challenge (e.g. an emailed one-time code) in that builder, so
  the userspace engine remains necessary for this project's code flow. (M, from the method list)

---

## 7. Must confirm on devices or by trace

| # | Item | How | Type |
|---|---|---|---|
| 1 | Raw socket for protocol 50 is refused to the app | `Os.socket(AF_INET, SOCK_RAW, 50)` on API 29 and latest | [TEST] |
| 2 | FortiGate always UDP-encapsulates ESP when client is behind NAT; also when client forges NAT-D | pcap on the phone side (Wi-Fi) and FortiGate `diagnose sniffer` | [TRACE] |
| 3 | FortiGate accepts IKE_SA_INIT started on UDP 4500 | trace | [TRACE] |
| 4 | Content/size of FortiGate NAT-T keepalive ("138-byte ISAKMP exchange" vs RFC 3948 0xFF) | trace | [TRACE] |
| 5 | FortiGate follows a client whose NAT port changed (RFC 7296 dynamic update) | idle past NAT timeout, then send | [TRACE] |
| 6 | Userspace ESP RX on an `UdpEncapsulationSocket` + `SocketKeepalive` offload | prototype on 2+ devices, cellular and Wi-Fi | [TEST] |
| 7 | Per-packet `Cipher.init` cost, GCM vs ChaCha20-Poly1305, low-end vs high-end | Jetpack Microbenchmark | [TEST] |
| 8 | `ECGenParameterSpec` secp384r1/secp521r1 accepted; ECDH output length; off-curve rejection | unit/instrumented test | [TEST] |
| 9 | XDH present on API 33+; bundled BC works on API 29-32 without clashing with platform "BC" | instrumented test | [TEST] |
| 10 | DH and DES providers and speed (group 14 with l = 256 vs 2048) | instrumented test | [TEST] |
| 11 | Real underlying MTU on the target carrier (LinkProperties, NAT64 prefix) and DF behaviour of outer UDP | ping sweep through the tunnel | [TEST] |
| 12 | Carrier NAT UDP timeout on the user's carriers | adaptive probe logging | [TEST] |

## 8. Not publicly documented (in the allowed sources)

- Conscrypt's per-`init` cost, GCM tag lengths other than 128, 192-bit GCM, IV-reuse checks, `Cipher` thread-safety.
- Which provider serves `DH` and `DES` on API 29+, and whether `BigInteger.modPow` is constant-time.
- Whether platform Bouncy Castle is repackaged (bundled BC class clash).
- Whether the kernel consumes inbound ESP on an `UdpEncapsulationSocket`.
- Whether an inbound UDP packet wakes the application processor in Doze for a foreground-service VPN app.
- Default TUN MTU when `setMtu` is not called; DF bit on outer UDP.
- Real-world carrier NAT UDP timeouts (only "as low as 30 s" and "significant fraction shorter than 2 min").
- Whether raw sockets are refused to apps (Linux capability behaviour, not stated in Android docs).
