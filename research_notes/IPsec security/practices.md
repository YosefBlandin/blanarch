# Secure engineering practices for a Kotlin IKEv2 + EAP-MSCHAPv2 + ESP engine on Android

Researched 2026-09-28. Scope: how to avoid shipping vulnerabilities in the Blanarch IKEv2 engine (Kotlin, JVM/ART,
minSdk 29, talking to FortiGate dial-up IPsec). This note feeds the "which approach" discussion; section 14 maps the
practices onto assumptions, costs and how hard each choice is to undo.

**Clean-room statement.** Sources are NVD/MITRE CVE records, vendor advisory prose (strongSwan blog, Libreswan notes
as quoted by NVD, Microsoft, Fortinet via CISA KEV), peer-reviewed papers (USENIX Security, WOOT, IEEE S&P) read at
the abstract/landing-page level, IETF RFCs, NIST publications, OWASP MAS pages, Google/Android developer docs, Oracle
JDK docs, OSS-Fuzz/ClusterFuzzLite docs, the Jazzer Javadoc site, Gradle/GitHub/F-Droid docs. **No source code of any
IPsec/VPN implementation was opened, and no code repository, README or issue tracker was read.** Where a CVE record
names a source file, only the prose description was used.

**Confidence tags.** **[doc]** the cited page says so. **[paper]** stated in a paper's abstract/landing page.
**[inference]** my reasoning from cited facts. **[local]** from this repo (build files or earlier notes).

---

## 0. Bottom line

1. **The gateway is part of the attack surface.** A client-side parser bug in EAP-MSCHAPv2 (strongSwan CVE-2025-62291,
   Failure Request of 6 to 8 bytes) gave a malicious server a heap overflow. FortiOS/FortiProxy have 15 entries in
   CISA's Known Exploited Vulnerabilities catalog, so "the server is trusted" is a weak assumption. Parse every server
   byte as hostile. [doc]
2. **Kotlin removes memory corruption, not logic or availability bugs.** Expect the remaining bugs to be state-machine
   mistakes (accepting EAP-Success early, CVE-2021-45079), lenient parsing that enables forgery (CVE-2018-16151),
   uncaught exceptions and unbounded allocation (DoS), and crypto misuse (GCM nonce reuse, non-constant-time compares).
   [doc] [inference]
3. **New code is where vulnerabilities live.** Google's Android data shows vulnerability density decays with code age;
   a fresh engine starts at the top of that curve regardless of language. Budget testing accordingly. [doc]
4. **Cheap, high-value practices** (do first): bounded byte reader with hard maximum sizes; explicit sealed-class state
   machine with a (state x message) test matrix; known-answer tests from RFC 2759, 4231, 4868, 5903, 7748 and NIST
   GCM vectors; RFC 6989 DH public-value checks; GCM IV from a per-SA counter with hard rekey limits;
   `MessageDigest.isEqual` for every secret comparison; one injected `SecureRandom`. [doc]
5. **Medium-cost practices:** coverage-guided fuzzing with Jazzer (needs JUnit 5; project is on JUnit 4.13.2), property
   tests with kotest-property, black-box differential testing against Android's own IKEv2 client and a packaged
   strongSwan responder, OSV-Scanner + Gradle dependency verification in CI. [doc] [local]
6. **Tooling risks found:** Jazzer's steward, Code Intelligence GmbH, entered insolvency (March 2026) and liquidation
   (June 2026). jqwik 1.10.0 shipped protestware that printed hidden instructions aimed at AI coding agents to stdout.
   Both matter for a Claude-assisted workflow. [doc]
7. **Key zeroization on the JVM is best effort only.** `SecretKeySpec.destroy()` is "Won't Fix" in the JDK, and
   `String`/`BigInteger` cannot be wiped. State this as accepted residual risk rather than claiming it. [doc]
8. **Independent review:** Google Play's "Independent security review" badge for VPN apps is backed by the App Defense
   Alliance MASA program (OWASP MASVS based, lab-assessed). It is the natural external review target before a Play
   release. [doc]

---

## 1. Threat model (STRIDE applied to this client)

STRIDE categories as defined by Microsoft: Spoofing, Tampering, Repudiation, Information disclosure, Denial of service,
Elevation of privilege. [doc] https://learn.microsoft.com/en-us/azure/security/develop/threat-modeling-tool-threats

| Actor | STRIDE threats that matter | Evidence it is realistic |
|---|---|---|
| Malicious or compromised gateway (or a MitM if server auth fails) | E (code exec via parser), D (crash/OOM loops), S (fake EAP-Success, fake AUTH), I (steal MSCHAPv2 response and crack it) | CVE-2025-62291, CVE-2021-45079; FortiOS in CISA KEV (e.g. CVE-2022-42475 heap overflow in SSL-VPN, CVE-2024-21762 out-of-bounds write, CVE-2024-55591 auth bypass) [doc] |
| On-path attacker on Wi-Fi/cellular before IKE SA exists | T/S on IKE_SA_INIT, D via unauthenticated notifies, I via routing leaks | RFC 7296 2.21 (don't act on unprotected errors); TunnelCrack (USENIX Security 2023); CVE-2019-14899; CVE-2024-3661 [doc] [paper] |
| Other app on the phone | I (logs, backups, IPC), T (setup links) | MASVS-STORAGE-2, MASVS-CODE-4 [doc] |
| Thief with the unlocked phone / memory dump | I (password, keys in heap) | MASTG process-memory guidance [doc] |
| Supply chain (Gradle/pub dependencies) | E, T | Bouncy Castle DoS CVEs 2024-2025; Gradle/Android dependency verification docs [doc] |

Sources:
- CISA KEV JSON feed (catalog 2026.09.27): 30 Fortinet entries, 15 for FortiOS/FortiProxy. https://www.cisa.gov/sites/default/files/feeds/known_exploited_vulnerabilities.json [doc]
- CVE-2022-42475 (NVD): "A heap-based buffer overflow vulnerability [CWE-122] in FortiOS SSL-VPN ... may allow a remote
  unauthenticated attacker to execute arbitrary code". https://nvd.nist.gov/vuln/detail/CVE-2022-42475 [doc]
- TunnelCrack: "VPN apps on Android are typically the most secure" because "Android has a more carefully designed API";
  ServerIP fix: "send all traffic through the VPN tunnel, except traffic generated by the VPN app itself".
  https://tunnelcrack.mathyvanhoef.com/details.html and paper https://papers.mathyvanhoef.com/usenix2023-tunnelcrack.pdf [doc] [paper]
  - Relevance [inference]: on Android use `VpnService.protect()` on the IKE/ESP socket instead of an excluded route to
    the gateway IP, and do not add a "local LAN bypass" by default.
- CVE-2019-14899 (NVD) lists Android among platforms where an adjacent attacker can infer and inject into VPN-tunnelled
  TCP. https://nvd.nist.gov/vuln/detail/CVE-2019-14899 [doc]
- CVE-2024-3661 (TunnelVision, DHCP option 121 routes). https://nvd.nist.gov/vuln/detail/CVE-2024-3661 [doc]
- OWASP threat modeling cheat sheet for process. https://cheatsheetseries.owasp.org/cheatsheets/Threat_Modeling_Cheat_Sheet.html (not re-read for this note)

**Why EAP-MSCHAPv2 raises the stakes of server authentication.** Microsoft: MS-CHAP v2 has "known cryptographic
weaknesses"; an attacker who intercepts the handshake "could then use the exploit code to decrypt a user's
credentials", and Microsoft recommends IKEv2 "in conjunction with ... EAP-MS-CHAP v2" as the safe encapsulation.
https://learn.microsoft.com/en-us/security-updates/securityadvisories/2012/2743314 [doc]. RFC 7296 2.16: "EAP methods
can be used only with a responder authenticating via public-key signature". https://www.rfc-editor.org/rfc/rfc7296.html
[doc]. So the gateway certificate/pin check before sending the MSCHAPv2 response is the control that protects the
user's password. If it is wrong, the password is exposed to offline cracking. [inference]

---

## 2. Memory safety: JVM/ART vs native

- Google: memory-safety issues were "76% of Android vulnerabilities in 2019, and are currently 24% in 2024", falling as
  new code moved to memory-safe languages; also "vulnerabilities decay exponentially. They have a half-life" and "The
  problem is overwhelmingly with new code". https://security.googleblog.com/2024/09/eliminating-memory-safety-vulnerabilities-Android.html [doc]
- Google (2022): "For Java, Android uses JNI ... When using JNI, care must be taken ... memory safety vulnerabilities
  are exceptionally rare in our Java code." https://security.googleblog.com/2022/12/memory-safe-languages-in-android-13.html [doc]
- CISA/NSA joint guide (June 24, 2025) on memory-safe languages. https://www.cisa.gov/resources-tools/resources/memory-safe-languages-reducing-vulnerabilities-modern-software-development [doc]

What the JVM does **not** prevent (all seen in IPsec/crypto code, including Java code):
- **Crash-by-assertion on attacker data.** Libreswan CVE-2023-38710: a protocol ID copied from the packet failed an
  assertion and "causes the pluto daemon to crash and restart". https://nvd.nist.gov/vuln/detail/CVE-2023-38710 [doc].
  Kotlin analogue [inference]: `require`/`check`/`!!`/`IndexOutOfBounds` thrown on hostile input and not caught at one
  boundary kills the tunnel (and with always-on VPN, may loop).
- **Unbounded CPU/allocation in Java crypto libraries.** Bouncy Castle Java: CVE-2024-29857 (crafted F2m EC parameters
  cause "excessive CPU consumption"), CVE-2024-30172 (Ed25519 "infinite loop"), CVE-2025-8916 ("Excessive
  Allocation"). https://nvd.nist.gov/vuln/detail/CVE-2024-29857 , https://nvd.nist.gov/vuln/detail/CVE-2024-30172 ,
  https://nvd.nist.gov/vuln/detail/CVE-2025-8916 [doc]. Relevant because the feasibility note plans Bouncy Castle for
  MD4 and pre-API-33 X25519. [local: `research_notes/FortiGate IPsec spec/android_feasibility.md`]
- **State-machine and logic bugs in Java TLS.** Protocol state fuzzing found new flaws in JSSE (Java), GnuTLS and
  OpenSSL. https://www.usenix.org/conference/usenixsecurity15/technical-sessions/presentation/de-ruiter [paper]

---

## 3. Strict parser design

Principles:
- LangSec: "treating all valid or expected inputs as a formal language, and the respective input-handling routines as
  a recognizer"; ad hoc validation "scattered throughout the program ... provides ample opportunities for
  exploitation". https://langsec.org/ [doc]
- RFC 9413 (IAB, 2023): tolerating unexpected inputs "is no longer considered best practice in all scenarios".
  https://www.rfc-editor.org/rfc/rfc9413.html [doc]

CVE evidence that length and trailing-data handling is where IKE/EAP code breaks:
- **CVE-2025-62291** (strongSwan, client side): "a malicious EAP-MSCHAPv2 server can send a crafted message of size 6
  through 8, and cause an integer underflow that potentially results in a heap-based buffer overflow." Advisory: the
  plugin expected at least 9 bytes but accepted 6 to 8. https://nvd.nist.gov/vuln/detail/CVE-2025-62291 ,
  https://www.strongswan.org/blog/2025/10/27/strongswan-vulnerability-(cve-2025-62291).html [doc]
- **CVE-2023-41913** (strongSwan charon-tkm): "buffer overflow ... via a DH public value that exceeds the internal
  buffer ... via a crafted IKE_SA_INIT message." https://nvd.nist.gov/vuln/detail/CVE-2023-41913 [doc]
- **CVE-2018-16151** (strongSwan gmp plugin): signature check "does not reject excess data after the encoded algorithm
  OID", allowing forged signatures and "impersonation when only an RSA signature is used for IKEv2 authentication".
  https://nvd.nist.gov/vuln/detail/CVE-2018-16151 [doc]

Rules for our engine [inference from the above plus RFC 7296]:
1. One `ByteReader` over an immutable slice. Every `readN(n)` checks `n <= remaining` first. No arithmetic on declared
   lengths without checking `declared >= headerSize` (the exact CVE-2025-62291 bug class, which in Kotlin becomes a
   negative-size exception or a wrong slice instead of a heap overflow).
2. Declared lengths are claims, not facts: IKE header length must equal the datagram length; each payload length must
   be `>= 4` and `<= remaining`; the EAP length must equal the EAP payload body; nested lengths must sum exactly.
3. Fixed-size fields are exact: KE data length must equal the group's size (e.g. 64 bytes for group 19, 32 for
   X25519); MSCHAPv2 Success/Failure bodies have documented minimums; nonce 16..256 bytes (RFC 7296 3.9).
4. Hard maximums before allocation: IKE message size, payload count, certificate chain length, CFG attribute count,
   EAP message length, fragment count. Never `ByteArray(declaredLength)` without a cap.
5. Reject trailing bytes everywhere (the CVE-2018-16151 lesson). Use the platform `Signature` for RSA/ECDSA rather than
   hand-parsing PKCS#1.
6. Unknown payloads: RFC 7296 3.2, "If the critical flag is set and the payload type is unrecognized, the message MUST
   be rejected". https://www.rfc-editor.org/rfc/rfc7296.html [doc]
7. Parse fully, then validate, then act. No state change from a message that has not fully parsed and (after
   IKE_SA_INIT) authenticated. Map every parse failure to one `VpnException(ErrorCode.MALFORMED_...)` at a single
   boundary (matches the repo's `VpnException(ErrorCode)` rule). [local: CLAUDE.md]
8. MASVS-CODE-4: "The app validates and sanitizes all untrusted inputs." https://mas.owasp.org/MASVS/controls/MASVS-CODE-4/ [doc]

---

## 4. Explicit state machines

- **CVE-2021-45079** (strongSwan < 5.9.5): "a malicious responder can send an EAP-Success message too early without
  actually authenticating the client and (in the case of EAP methods with mutual authentication and EAP-only
  authentication for IKEv2) even without server authentication." https://nvd.nist.gov/vuln/detail/CVE-2021-45079 .
  Advisory prose: the client concluded the EAP method prematurely; standard IKEv2 with certificate server auth was the
  lower-risk case. https://www.strongswan.org/blog/2022/01/24/strongswan-vulnerability-(cve-2021-45079).html [doc]
- RFC 3748 4.2: a peer receiving Success/Failure where not permitted "MUST silently discard it"; "an EAP peer MUST
  silently discard a 'canned' Success packet". https://www.rfc-editor.org/rfc/rfc3748.html [doc]
- RFC 2759: "The authenticating peer MUST verify the authenticator response when a Success packet is received ... If
  the authenticator response is either missing or incorrect, the peer MUST end the session." (section 8.8 has the check).
  https://www.rfc-editor.org/rfc/rfc2759.txt [doc]
- RFC 7296 2.21: "An endpoint MUST NOT conclude that the other endpoint has failed based on any routing information
  (e.g., ICMP messages) or IKE messages that arrive without cryptographic protection." [doc]
- Research: state-machine learning found flaws in JSSE, GnuTLS, OpenSSL
  (https://www.usenix.org/conference/usenixsecurity15/technical-sessions/presentation/de-ruiter); composite TLS state
  machines hid FREAK and other bugs for years (IEEE S&P 2015, https://ieeexplore.ieee.org/document/7163046/); model
  learning of IPsec implementations found interaction bugs and RFC violations
  (https://www.researchgate.net/publication/337550930_Model_Learning_and_Model_Checking_of_IPSec_Implementations_for_Internet_of_Things);
  state-aware learning applied to strongSwan and Libreswan
  (https://link.springer.com/article/10.1186/s13677-024-00593-0). [paper]

Rules [inference]:
- A Kotlin `sealed interface IkeState` with a pure `transition(state, event) -> (state, actions)` function; unexpected
  (state, message) pairs go to a single "drop or fail" branch, never to a default that continues.
- EAP sub-machine for MSCHAPv2: accept EAP-Success only after (a) we sent our Response, (b) we received the MSCHAPv2
  Success Request, (c) the AuthenticatorResponse verified with a constant-time compare, (d) MSK derived. Then the
  final IKE AUTH uses the MSK (RFC 7296 2.16). Anything else ends the session.
- Test matrix: every state x every message type (including duplicates, reordering, wrong exchange type, wrong message
  ID, unprotected notifies). This is cheap because the machine is pure.

---

## 5. Official test vectors (known-answer tests)

| Primitive in our engine | Vectors | URL |
|---|---|---|
| MSCHAPv2 NT-Response, AuthenticatorResponse, MSK inputs | RFC 2759 section 9.2: UserName "User", Password "clientPass", challenges, PasswordHash, NT-Response, PasswordHashHash, AuthenticatorResponse [doc] | https://www.rfc-editor.org/rfc/rfc2759.txt |
| HMAC-SHA-256/384/512 | RFC 4231, 7 test cases incl. truncation to 128 bits (case 5) and keys larger than the block (6, 7) [doc] | https://www.rfc-editor.org/rfc/rfc4231.html |
| PRF-HMAC-SHA2 and HMAC-SHA-256-128 ICV in IKE/ESP | RFC 4868 section 2.7.1 (PRF-1..6) and 2.7.2 (AUTH256-1..4 etc.) [doc] | https://www.rfc-editor.org/rfc/rfc4868.html |
| AES-GCM | NIST CAVP `gcmtestvectors.zip` incl. `gcmDecrypt*.rsp` with good and bad tags; "does not replace validation" [doc] | https://csrc.nist.gov/projects/cryptographic-algorithm-validation-program/cavp-testing-block-cipher-modes |
| ECDH groups 19/20/21 | RFC 5903 section 8 (initiator/responder keys and shared secret); KE = x \|\| y; shared secret = x only (section 9, changed from RFC 4753) [doc] | https://www.rfc-editor.org/rfc/rfc5903.html |
| X25519 (group 31) | RFC 7748 section 5.2 single and iterated vectors; RFC 8031 Appendix A example [doc] | https://www.rfc-editor.org/rfc/rfc7748.html , https://www.rfc-editor.org/rfc/rfc8031.html |
| Attack-oriented edge cases (invalid curve points, modified GCM tags) | Project Wycheproof JSON vectors, via Trail of Bits Testing Handbook description [doc] | https://appsec.guide/docs/crypto/wycheproof/ |

Also required by the RFCs (implement and test):
- RFC 6989: MODP: "Each recipient MUST verify that the peer's public value r is in the legal range (1 < r < p-1)";
  ECP: "A receiving peer MUST check that its peer's public value is valid; that is ... satisfy the curve equation".
  https://www.rfc-editor.org/rfc/rfc6989.html [doc]
- RFC 7748: X25519 receivers "MUST mask the most significant bit in the final byte" and "MUST accept non-canonical
  values"; both sides "MAY check ... whether K is the all-zero value and abort if so" (section 6.1). RFC 8031 adds no
  all-zero MUST. [doc] Recommendation [inference]: do the all-zero check anyway; it is one OR-loop.

Practice [inference]: run the known-answer tests twice, on the host JVM (SunJCE) in `testDebugUnitTest` and on a
device (Conscrypt/BC) as instrumented tests, because the provider differs and the Android crypto doc warns that
"Android doesn't guarantee a particular provider for a given algorithm".
https://developer.android.com/privacy-and-security/cryptography [doc]

---

## 6. GCM nonce management (ESP and IKE SA)

- NIST SP 800-38D section 8: "The probability that the authenticated encryption function ever will be invoked with the
  same IV and the same key on two (or more) distinct sets of input data shall be no greater than 2^-32 ... if even one
  IV is ever repeated, then the implementation may be vulnerable to the forgery attacks ... this requirement is almost
  as important as the secrecy of the key." Section 8.3: with random IVs "The total number of invocations ... shall not
  exceed 2^32". Section 9.1 asks how IV generation "recover[s] from a loss of power without violating the uniqueness
  requirement". https://nvlpubs.nist.gov/nistpubs/Legacy/SP/nistspecialpublication800-38d.pdf [doc]
- NIST announced (March 2024) it will revise SP 800-38D, citing the 2^32 random-nonce limit; 2007 text is still the
  published one. https://csrc.nist.gov/pubs/sp/800/38/d/final ,
  https://csrc.nist.gov/news/2024/nist-to-revise-sp-80038d-gcm-and-gmac-modes [doc]
- RFC 4106 3.1: "For a given key, the IV MUST NOT repeat. The most natural way to implement this is with a counter";
  section 2: reuse "destroys the security guarantees"; implementations "MUST use an automated key management system,
  such as ... IKE". Section 8.1: KEYMAT per key = AES key + 4-byte salt. https://www.rfc-editor.org/rfc/rfc4106.html [doc]
- RFC 4303 3.3.3: "the sender MUST NOT send a packet on an SA if doing so would cause the sequence number to cycle";
  3.4.3: preliminary sequence check before integrity check, and "The receive window is updated only if the integrity
  verification succeeds." https://www.rfc-editor.org/rfc/rfc4303.html [doc]
- Android `Cipher` docs: "When IVs are repeated for GCM encryption, such usages are subject to forgery attacks ... after
  each encryption operation using GCM mode, callers should re-initialize the cipher objects with GCM parameters which
  has a different IV value." https://developer.android.com/reference/javax/crypto/Cipher [doc]
- Real-world failure: 184 HTTPS servers repeated GCM nonces, "which fully breaks the authenticity"; over 70,000 used
  random nonces. Bock et al., WOOT 2016. https://www.usenix.org/conference/woot16/workshop-program/presentation/bock [paper]

Rules [inference]:
- ESP explicit IV = the 64-bit per-SA outbound counter (which equals the ESP sequence number, or a separate counter);
  never random. One owner of the counter (single-threaded send path or an `AtomicLong`), incremented before use.
- Rekey the Child SA well before 2^32 packets (no ESN) and on a time/byte budget; hard-fail sending at the limit.
- Never persist SA keys or counters. After process death (Android kills VPN processes), start a new IKE SA; never
  "resume" an SA from saved state with a possibly stale counter (the SP 800-38D 9.1 power-loss case).
- IKE SA with AES-GCM (RFC 5282): same rule, counter-based IV per IKE SA direction; retransmit the exact same bytes
  rather than re-encrypting changed content under an old IV.
- Unit-test the invariant: over N packets, all (key, IV) pairs distinct; counter at limit throws.

---

## 7. Constant-time comparison

- Android `MessageDigest.isEqual`: "Implementation Note: All bytes in digesta are examined to determine equality. The
  calculation time depends only on the length of digesta. It does not depend on the length of digestb or the contents".
  https://developer.android.com/reference/java/security/MessageDigest [doc] (Same text in Oracle JDK 21:
  https://docs.oracle.com/en/java/javase/21/docs/api/java.base/java/security/MessageDigest.html)
- History: CVE-2009-3875, the old `isEqual` had "timing attack vulnerabilities" allowing HMAC spoofing.
  https://nvd.nist.gov/vuln/detail/CVE-2009-3875 [doc]
- Use it for [inference]: ESP ICV check when we do AES-CBC + HMAC ourselves; MSCHAPv2 AuthenticatorResponse check;
  IKE AUTH payload check for the MSK-based AUTH; any cookie/token compare. GCM tag checks happen inside `Cipher`.
  Forbid `contentEquals`/`==` on secret byte arrays with a lint/grep check in CI.
- Caveat [inference]: the Android doc describes the current platform; it does not state since which API level the note
  applies. Our own 5-line constant-time loop is a fallback if that matters for API 29.

---

## 8. Secure randomness on Android

- `SecureRandom` doc: "A newly created PRNG SecureRandom object is not seeded ... The first call to nextBytes will force
  it to seed itself ... This self-seeding will not occur if setSeed was previously called."
  https://developer.android.com/reference/java/security/SecureRandom [doc]
- Android crypto guide: the "Crypto" JCA provider was removed in Android 9; do not specify providers except for the
  Android Keystore; BC implementations are deprecated in the platform. https://developer.android.com/privacy-and-security/cryptography [doc]
- The 2013 Android JCA PRNG initialization bug affected Android 4.1 to 4.3 only.
  https://android-developers.googleblog.com/2013/08/some-securerandom-thoughts.html [doc] (Not relevant at minSdk 29,
  but shows why one tested source of randomness matters.)
- RFC 7296 2.10: "Nonces used in IKEv2 MUST be at least 128 bits in length and at least half the key size of the PRF".
  [doc]

Rules [inference]: one `SecureRandom()` created once and injected (so tests can pass a deterministic one); never call
`setSeed`; SPIs, nonces, DH private keys, MSCHAPv2 PeerChallenge all come from it; test nonce lengths per PRF.

---

## 9. Key zeroization: what the JVM allows

- JDK-8160206 "SecretKeySpec should implement destroy()": Closed, **Won't Fix**. https://bugs.openjdk.org/browse/JDK-8160206 [doc]
- `Destroyable.destroy()` default implementation throws `DestroyFailedException`.
  https://docs.oracle.com/en/java/javase/25/docs/api/java.base/javax/security/auth/Destroyable.html [doc]
- OWASP MASTG: "Don't use immutable structures (e.g., String and BigInteger) to represent secrets. Nullifying these
  structures will be ineffective"; store secrets in `byte[]`/`char[]` and overwrite them. The test MASTG-TEST-0011 is now
  **deprecated** because the weakness is "best addressed during the development process" (see MASTG-KNOW-0051).
  https://mas.owasp.org/MASTG/tests/android/MASVS-STORAGE/MASTG-TEST-0011/ [doc]

Implications [inference]:
- DH/ECDH private values inside JCA `KeyAgreement` live in `BigInteger`/provider objects we cannot wipe. SK_* keys we
  derive ourselves can be `ByteArray` and filled after rekey/teardown, but `SecretKeySpec` copies them.
- The password crosses Pigeon as a Dart/Kotlin `String` today. Moving it to `ByteArray`/`CharArray` in the engine
  helps a little; the honest statement is "keys live only in process memory and are dropped at teardown; a
  memory-dump attacker on a rooted/unlocked phone is out of scope".
- What we can guarantee: never log secrets (repo rule), never persist SA keys, keep the password at rest in the Android
  Keystore (MASVS-CRYPTO-2 / STORAGE-1).

---

## 10. Coverage-guided fuzzing on the JVM (Jazzer)

- OSS-Fuzz: "Java fuzzing in OSS-Fuzz depends on Jazzer"; "As Jazzer operates directly on the bytecode level, it can be
  applied to any project written in a JVM-based language"; targets are `fuzzerTestOneInput(byte[])` or use
  `FuzzedDataProvider`. https://google.github.io/oss-fuzz/getting-started/new-project-guide/jvm-lang/ [doc]
- ClusterFuzzLite (CI fuzzing on GitHub Actions/GitLab) supports JVM via Jazzer, including batch fuzzing on a cron.
  https://google.github.io/clusterfuzzlite/build-integration/jvm-lang/ , https://google.github.io/clusterfuzzlite/ [doc]
- JUnit integration, `@FuzzTest` Javadoc: fuzzing mode "when the environment variable JAZZER_FUZZ is set to any
  non-empty value"; otherwise regression mode runs the empty input plus files in `<TestClassName>Inputs`; `maxDuration`
  default "5m"; "In fuzzing mode, only a single fuzz test per test run will be executed." Built on JUnit 5
  `@ParameterizedTest`/`@ExtendWith`. https://codeintelligencetesting.github.io/jazzer-docs/jazzer-junit/com/code_intelligence/jazzer/junit/FuzzTest.html [doc]
- **Maintenance risk:** Code Intelligence GmbH (Bonn, HRB 23408): provisional insolvency administrator appointed by the
  Bonn local court on 2026-03-09 (published 2026-03-16); liquidation announcement 2026-06-05.
  https://www.northdata.com/Code%20Intelligence%20GmbH,%20Bonn/HRB%2023408 [doc]. The company's website no longer
  resolves (DNS failure on 2026-09-28) [observed]. Jazzer had earlier paused and then resumed open-source maintenance
  under Apache 2.0 (per search-result summaries of the company's "Jazzer back to open source" post; page unreachable).
- **Project fit:** the Android module uses `junit:junit:4.13.2` only. [local: `blanarch/android/app/build.gradle.kts`]

Rules [inference]:
- Fuzz targets per parser: IKE header+payload chain, each payload decoder, EAP/MSCHAPv2 decoder, CFG attributes, ESP
  decapsulation (after a test-only "decrypt" stub), and the state machine driven by a byte stream of events.
- Oracle: the only allowed failure is `VpnException(MALFORMED...)`; any other exception, a timeout, or allocation over
  the cap is a bug. Add round-trip oracles where we also encode.
- Keep targets as plain `fun fuzzerTestOneInput(data: ByteArray)` so they run under Jazzer standalone, the JUnit
  integration, OSS-Fuzz or a replacement fuzzer. Commit crashing inputs to the regression corpus; regression mode runs in
  normal `test` with no fuzzing cost.
- Pin the Jazzer version; plan a fallback (random-input property tests below) if it stops being maintained.

---

## 11. Property-based testing

- kotest-property is standalone: "You do not need to be using Kotest as your test framework ... to benefit from the
  property test support"; generators include edge cases. https://kotest.io/docs/proptest/property-based-testing.html [doc]
- jqwik is a JUnit 5 engine (https://jqwik.net/). Since 1.10 it ships an "Anti-AI Usage Clause"
  (https://jqwik.net/docs/current/user-guide.html). jqwik 1.10.0 (2026-05-25) printed an instruction aimed at AI agents
  to stdout, hidden from humans with ANSI escapes; 1.10.1 softened it and made the hiding opt-in.
  https://snyk.io/blog/protestware-open-source-maintainer-qwik-1-10-0-prompt-injection/ [doc]
  - Relevance [inference]: this repo is developed with Claude Code; a test dependency that injects agent-directed text
    into build output is a supply-chain and workflow risk. Prefer kotest-property.

Useful properties [inference]: `decode(encode(x)) == x`; every strict prefix of a valid message is rejected; every
single-byte length-field mutation is rejected or decodes to something that re-encodes identically; the state machine
never reaches `Connected` without passing through `ServerAuthVerified` and `EapSucceeded`; the ESP sender never emits a
repeated IV.

---

## 12. Differential and interoperability testing (black-box only)

- Differential testing uses other implementations as an oracle: Frankencerts found 208 discrepancies across TLS
  libraries, "many of them caused by serious security vulnerabilities" (IEEE S&P 2014).
  https://ieeexplore.ieee.org/document/6956560/ [paper]. NEZHA (IEEE S&P 2017) generalizes this to find logic bugs
  that do not crash. https://ieeexplore.ieee.org/document/7958601/ [paper]

Clean-room-compatible references [inference]:
- **Android's platform IKEv2 client** (`Ikev2VpnProfile`/`IkeSessionParams`, public API) on the same phone against the
  same FortiGate: compare negotiated proposals, accept/reject behaviour and packet traces (Wireshark), never its code.
  https://developer.android.com/reference/android/net/Ikev2VpnProfile.Builder [doc]
- **A packaged strongSwan binary as a test responder** in the testbed, configured from its documentation only, to
  send hostile or unusual messages and compare our reactions. Running a binary is not reading code; keep it in
  `PROVENANCE.md`.
- **Crypto providers against each other**: SunJCE (host), Conscrypt (device), Bouncy Castle on the same vectors.
- **Interop matrix**: FortiOS 7.4.x and 7.6.x (TCP 443 default since 7.6.3 per the testbed note), UDP 500/4500 and TCP,
  groups 14/19/20/21/31, GCM and CBC+HMAC. [local: `research_notes/FortiGate IPsec spec/testbed.md`]

---

## 13. OWASP MASVS/MASTG controls that apply to a VPN client

| Control | Text [doc] | What it means here [inference] |
|---|---|---|
| MASVS-NETWORK-1 | "The app secures all network traffic according to the current best practices." | IKE/ESP with RFC 8247/8221 algorithms; no fallback to weak proposals. |
| MASVS-NETWORK-2 | "The app performs identity pinning for all remote endpoints under the developer's control." | Gateway cert/public-key pin per host, confirmed by the user (existing repo rule). |
| MASVS-CRYPTO-1 | "The app employs current strong cryptography and uses it according to industry best practices." | Sections 5 to 8. |
| MASVS-CRYPTO-2 | "The app performs key management according to industry best practices." | Keystore for the password; ephemeral SA keys; rekey limits. |
| MASVS-STORAGE-1/2 | "securely stores sensitive data" / "prevents leakage of sensitive data" (logs, backups). | No secrets in the Activity log or `adb logcat`; backup exclusions. |
| MASVS-CODE-3 | "only uses software components without known vulnerabilities." | Section 15. |
| MASVS-CODE-4 | "validates and sanitizes all untrusted inputs." | Section 3, including setup links and QR codes. |

URLs: https://mas.owasp.org/MASVS/controls/MASVS-NETWORK-1/ , .../MASVS-NETWORK-2/ , .../MASVS-CRYPTO-1/ ,
.../MASVS-CRYPTO-2/ , .../MASVS-STORAGE-1/ , .../MASVS-STORAGE-2/ , .../MASVS-CODE-3/ , .../MASVS-CODE-4/

Google Play VpnService policy: only apps with VPN as core functionality; apps "must encrypt the data from the device to
the VPN tunnel endpoint"; declaration in Play Console since November 2022.
https://support.google.com/googleplay/android-developer/answer/12564964?hl=en [doc]

---

## 14. Independent security review / pentest

- App Defense Alliance MASA: based on OWASP MASVS; lab-assessed (AL2) or self-attested (AL1); results shown in the
  Play Data safety section; "the limited nature of testing does not guarantee complete safety".
  https://appdefensealliance.dev/masa [doc]. Google Play started the "Independent security review" badge with VPN apps
  (Nov 2023). https://www.helpnetsecurity.com/2023/11/06/google-vpn-apps-security/ [doc]
- MASA tests the app (MASVS level), not the IKE engine's protocol correctness. A protocol-focused code review plus a
  fuzzing report is a separate scope. [inference]
- OTF Security Lab funds audits, but for "technology-focused internet freedom projects"; an enterprise VPN client is
  unlikely to qualify. https://www.opentech.fund/labs/red-team-lab/ [doc] [inference]

---

## 15. Dependency scanning, supply chain, reproducible builds

- OSV-Scanner supports `gradle.lockfile`, `buildscript-gradle.lockfile`, `gradle/verification-metadata.xml` and Dart
  `pubspec.lock`. https://google.github.io/osv-scanner/supported-languages-and-lockfiles/ [doc]
- Dependabot: Gradle security updates work for dependencies uploaded via the dependency submission API (transitives
  included); version updates understand Gradle version catalogs.
  https://github.blog/changelog/2023-08-24-gradle-support-for-dependabot-security-updates/ ,
  https://docs.github.com/en/code-security/dependabot/dependabot-version-updates/about-dependabot-version-updates [doc]
- Android recommends Gradle dependency verification (checksums and PGP) against MitM-injected dependencies; bootstrap
  with `./gradlew --write-verification-metadata pgp,sha256 --export-keys help`, and warns "It's possible that the
  current set of checksums and signatures are already compromised". https://developer.android.com/build/dependency-verification ,
  https://docs.gradle.org/current/userguide/dependency_verification.html [doc]
- Reproducible builds: "given the same source code, build environment and build instructions, any party can recreate
  bit-by-bit identical copies". https://reproducible-builds.org/docs/definition/ [doc]. F-Droid lists timestamps, ZIP
  ordering, baseline profiles, **Flutter embedded build paths**, NDK paths, and apksigner 35+ as common breakers.
  https://f-droid.org/docs/Reproducible_Builds/ [doc]. Relevant because a VPN client's users must trust the binary;
  also the path to F-Droid (which already needs a different QR scanner per the repo notes). [local: CLAUDE.md]

---

## 16. How these practices bear on the approach decision

The user asked, for each approach: what it assumes, what if the assumption is wrong, cost, and undo difficulty. The
practices above group into three assurance tiers that can be combined with any engine approach (own Kotlin engine,
Android's platform IKEv2 client, or an embedded native library). All costs are estimates. [inference]

| Tier | Contents | Assumes | If wrong | Cost | Undo |
|---|---|---|---|---|---|
| A. Baseline (must have) | Sections 3, 4, 5, 6, 7, 8; "no secrets in logs"; MASVS mapping | Pure, I/O-free protocol code (already the repo rule) so all of it is plain JVM unit tests | If protocol code leaks into Android classes, tests need Robolectric or devices and get slow | Low build time (seconds); no APK size; learning curve: RFC reading | Trivial: tests only |
| B. Automated adversarial testing | Jazzer fuzz targets + regression corpus, kotest-property, OSV-Scanner, Gradle verification | A JUnit 5 test path (separate pure-Kotlin JVM module is simplest) and a CI runner | If Jazzer goes unmaintained (steward in liquidation), fuzzing stops improving; targets still run as regression tests | Medium: one new Gradle module, JUnit 5, fuzz CI minutes; zero APK size (test-only deps) | Easy: delete the module or swap fuzzer; targets are plain `ByteArray` functions |
| C. External assurance | Black-box differential vs Android IKE client and strongSwan binary; MASA AL2 lab review; reproducible builds | Access to a licensed FortiGate (see testbed note) and budget for a lab | Without it, bugs that tests cannot express (interop, state) reach users | High: lab fees, testbed licence, reproducible-build work especially with Flutter | Review money is sunk; reproducible build config is easy to drop |

Key assumption to state explicitly: **"memory-safe language" is not "safe engine"**. If we rely on Kotlin alone, the
documented failure modes (early EAP-Success, lenient parsing, nonce reuse, DoS loops) are all still open, and a new
engine is at the high end of Google's vulnerability-age curve.

---

## Sources (all accessed 2026-09-28)

CVE / advisories:
- https://nvd.nist.gov/vuln/detail/CVE-2025-62291 ; https://www.strongswan.org/blog/2025/10/27/strongswan-vulnerability-(cve-2025-62291).html
- https://nvd.nist.gov/vuln/detail/CVE-2021-45079 ; https://www.strongswan.org/blog/2022/01/24/strongswan-vulnerability-(cve-2021-45079).html
- https://nvd.nist.gov/vuln/detail/CVE-2023-41913 ; https://nvd.nist.gov/vuln/detail/CVE-2018-16151 ; https://nvd.nist.gov/vuln/detail/CVE-2023-38710
- https://nvd.nist.gov/vuln/detail/CVE-2009-3875 ; https://nvd.nist.gov/vuln/detail/CVE-2022-42475
- https://nvd.nist.gov/vuln/detail/CVE-2024-3661 ; https://nvd.nist.gov/vuln/detail/CVE-2019-14899
- https://nvd.nist.gov/vuln/detail/CVE-2024-29857 ; https://nvd.nist.gov/vuln/detail/CVE-2024-30172 ; https://nvd.nist.gov/vuln/detail/CVE-2025-8916
- https://www.cisa.gov/sites/default/files/feeds/known_exploited_vulnerabilities.json
- https://learn.microsoft.com/en-us/security-updates/securityadvisories/2012/2743314

RFCs / NIST: RFC 2759, 3748, 4106, 4231, 4303, 4868, 5903, 6989, 7296, 7748, 8031, 9413 (rfc-editor.org URLs above);
https://nvlpubs.nist.gov/nistpubs/Legacy/SP/nistspecialpublication800-38d.pdf ;
https://csrc.nist.gov/pubs/sp/800/38/d/final ; https://csrc.nist.gov/projects/cryptographic-algorithm-validation-program/cavp-testing-block-cipher-modes

Papers: de Ruiter and Poll, USENIX Security 2015; Beurdouche et al., IEEE S&P 2015; Brubaker et al., IEEE S&P 2014;
Petsios et al., IEEE S&P 2017; Bock et al., WOOT 2016; Felsch et al., USENIX Security 2018
(https://www.usenix.org/conference/usenixsecurity18/presentation/felsch, key reuse across IKE modes); Vanhoef et al.,
USENIX Security 2023 (TunnelCrack).

Platform / tooling docs: developer.android.com (MessageDigest, SecureRandom, Cipher, cryptography, dependency
verification); docs.oracle.com; bugs.openjdk.org; mas.owasp.org; google.github.io/oss-fuzz; google.github.io/clusterfuzzlite;
codeintelligencetesting.github.io/jazzer-docs; northdata.com; kotest.io; jqwik.net; snyk.io; google.github.io/osv-scanner;
docs.github.com; github.blog changelog; docs.gradle.org; reproducible-builds.org; f-droid.org; appdefensealliance.dev;
support.google.com (Play VpnService policy); security.googleblog.com; android-developers.googleblog.com; langsec.org;
learn.microsoft.com; appsec.guide; opentech.fund.
