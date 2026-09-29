# Prevention plan: threat model and defences for Blanarch's IKEv2 engine

Written 2026-09-28. **Status: research note.** It feeds the "which approach" discussion that comes before the IPsec
spec is finished or any engine code is written. Nothing here is implemented, and `docs/protocol/fortigate-ipsec.md`
is unchanged.

**Scope.** The planned Kotlin engine: an IKEv2 initiator (RFC 7296) with EAP-MSCHAPv2 user authentication and
userspace ESP (RFC 4303), inside the Android `VpnService` app, talking to FortiGate dial-up gateways. Clean-room from
RFCs, with no FortiClient-proprietary extensions.

**Sources.** Only the 43 verified claims in the sibling notes `impl_cves.md`, `protocol_attacks.md` and
`practices.md`, with the verifiers' corrections applied. Each fact carries its claim id in brackets, for example
[impl_cves-1], plus the main URL. **[inference]** marks my own reasoning from those facts. **[local]** marks something
read in this repo. No IPsec or VPN implementation source code was opened for this note.

---

## 0. The short version

1. **Authenticate the gateway before any EAP byte leaves the phone.** Check IDr, the responder's AUTH and the per-host
   pin on the first IKE_AUTH response, then answer EAP. strongSwan's Android client got this order wrong
   (CVE-2015-4171), and RFC 7296 §5 makes it a MUST. (R1 to R3)
2. **Never trust "EAP-Success" on its own.** Accept it only after the MSCHAPv2 authenticator response (S=) verifies
   and the MSK exists, then use the MSK for both final AUTH payloads (CVE-2021-45079). (R6, R7)
3. **Treat every gateway byte as hostile.** Client parsers have been crashed or overflowed by server packets
   (CVE-2025-62291 in EAP-MSCHAPv2, CVE-2024-20474, CVE-2016-6423), and FortiOS has at least 15 entries in CISA's
   Known Exploited Vulnerabilities catalog. Kotlin removes memory corruption, not logic or availability bugs. (R9 to R16)
4. **Make the state machine a table.** Messages outside the table are dropped. Nothing is installed before both AUTH
   payloads verify (CVE-2026-78135, CVE-2014-2338, CVE-2019-12312). (R17 to R20)
5. **Own the crypto floor.** Offer only AES-GCM or AES-CBC with HMAC-SHA2, and DH 14/19/20/21/31. Validate peer DH
   values. ESP IVs come from a per-SA counter, never random, never resumed. Compare secrets in constant time.
   (R21 to R33, R43)
6. **Unprotected messages are hints, not commands.** Never tear down or show an error because of an unauthenticated
   notify (RFC 7296 §2.4). (R34 to R36)
7. **Some risks stay whatever we build.** A FortiGate that proves itself with a group PSK can be impersonated by
   anyone holding that PSK, and anyone who can reach it can brute-force a weak PSK offline. MSCHAPv2 hands a
   crackable, password-equivalent value to whoever passes that check. The app must say so plainly to users and IT
   (section 5).
8. **Verification is the real cost.** Known-answer tests, a (state x message) matrix, property tests, Jazzer fuzz
   targets per pure core, a hostile test responder, interop on the AWS FortiGate, and adversarial review
   (section 4).

---

## 1. What an attacker can do, and where

### 1.1 What we protect

- The user's password and its NT hash, which is password-equivalent for MS-CHAP [protocol_attacks-3]. Also the
  MSCHAPv2 NT-Response and the emailed one-time code (however the spike finds it is carried).
- The per-host gateway pin and the user's trust decision. Certificates are never trusted silently [local: CLAUDE.md].
- Session secrets: DH private values, SKEYSEED, SK_*, the MSK, ESP keys.
- Tunnel traffic (confidentiality and integrity) and the promise that nothing leaks around the tunnel.
- Availability: always-on starts, the Quick Settings tile and the reconnect logic must not be crash-looped
  [local: CLAUDE.md].

### 1.2 Where the engine is reachable, phase by phase

| Phase | Who the peer is at this point | Who can put bytes in front of our parser | What is exposed |
|---|---|---|---|
| 1. IKE_SA_INIT (UDP 500/4500, or TCP 443) | Unknown. Nothing is authenticated. | Anyone on the path | SA and KE parsing before any authentication [impl_cves-9]. Error notifies are "completely unauthenticated" (RFC 7296 §2.21.1) [protocol_attacks-7]. |
| 2. First IKE_AUTH response (message 4) | Holds keys shared with whoever answered phase 1, not yet authenticated | Whoever answered phase 1 | IDr, CERT, AUTH and the first EAP-Request. A FortiGate sends IDr, then AUTH method 2 (shared-key MIC), then EAP-Request/Identity [protocol_attacks-2]. Our IDi already went out in message 3, encrypted but to an unauthenticated peer [inference]. |
| 3. EAP rounds | Authenticated gateway, or anyone holding the group PSK in PSK mode | The gateway or its AAA backend | EAP and MSCHAPv2 parsing [impl_cves-3]; EAP has an unlimited number of messages (RFC 7296 §5) [protocol_attacks-9]. |
| 4. Final AUTH (MSK-based) | Mutually authenticated | The gateway | MSK derivation and AUTH verification [impl_cves-2]. |
| 5. CHILD_SA, ESP, INFORMATIONAL, rekey | Authenticated, but possibly compromised [practices-1] | The gateway; on-path attackers can inject bytes that must fail the ICV | ESP decap and replay window [impl_cves-11], TCP framer [protocol_attacks-8], fragments [impl_cves-5], DELETE and notifies [impl_cves-7]. |
| 6. Outside the protocol | Not applicable | Local network, other apps, the OS | Routing and DNS leaks [protocol_attacks-10 to -12], logs [impl_cves-12], memory and storage [practices-10]. |

### 1.3 Attackers

| # | Attacker | What they can do | Evidence it is realistic | Rules |
|---|---|---|---|---|
| A1 | **Rogue gateway**: anyone holding the group PSK, or a server the client wrongly accepts | Impersonate the gateway, collect the EAP identity and the MSCHAPv2 response for offline cracking, send malformed EAP, send an early EAP-Success | CVE-2015-4171 [impl_cves-1]; CVE-2021-45079 [impl_cves-2]; Fortinet's worked dial-up example uses one PSK "used by all remote users" [protocol_attacks-1] | R1 to R8, R15 |
| A2 | **Compromised real gateway** | Everything A1 can do, while legitimately authenticated. It receives the MSCHAPv2 response anyway | FortiOS/FortiProxy: 15 KEV entries by product field, 20 counting multi-product entries (catalog 2026.09.27), e.g. CVE-2022-42475 [practices-1] | R9 to R20, R35 |
| A3 | **On-path attacker** (hostile Wi-Fi, carrier, ISP) | Forge unauthenticated rejections to steer negotiation, forge INVALID_SPI to cause teardown or reconnect storms, block UDP to force TCP, spoof RSTs or Length fields on TCP, drop or replay ESP, spoof DNS for the gateway name. It cannot forge ESP payloads [protocol_attacks-8] | RFC 7296 §1.2, §2.4, §2.21.1 [protocol_attacks-7, impl_cves-7]; RFC 9329 §Security [protocol_attacks-8] | R21 to R24, R27 to R34, R38, R39 |
| A4 | **Anyone who can reach a PSK gateway** | Run IKE_SA_INIT as initiator, receive the gateway's PSK-keyed AUTH in message 4, brute-force a weak PSK offline. No victim and no on-path position needed | Inference from RFC 7296 §2.15 plus Fortinet's documented message 4 [protocol_attacks-2] | None client-side (section 5.1) |
| A5 | **Malicious local network** | Push routes (TunnelVision), claim public ranges as local (TunnelCrack LocalNet), abuse split tunnels | [protocol_attacks-10], [protocol_attacks-11] | R40, R41 |
| A6 | **Malformed packets from any of the above** | Crash the engine; with always-on this can loop | Cisco Secure Client CVE-2024-20474 and Cisco IOS initiator CVE-2016-6423, both crashed by server-side packets [impl_cves-4] | R9 to R16, R35, R37 |
| A7 | **Stolen or rooted phone, other apps** | Read logs, memory or storage | CVE-2022-33878: a local user read the FortiClient for Mac SSL-VPN password from the FortiTray log stream [impl_cves-12] | R42 to R44 |
| A8 | **Supply chain** | Vulnerable or tampered dependencies, test tools that inject agent-directed text | Bouncy Castle DoS CVEs [practices-3]; jqwik 1.10.0 protestware [practices-12] | R45 to R47 |

Out of scope: breaking AES or SHA-2; precomputation against DH groups we never offer; the gateway's internal backend,
except where it can inject EAP (see CVE-2025-62291 in section 2, class D).

---

## 2. Known failure classes, with real examples

Each class lists what actually happened (corrections applied), then the lesson for us.

### Class A: gateway not authenticated before EAP

- **CVE-2015-4171**, strongSwan 4.3.0 to 5.3.1 and its Android client before 1.4.6, fixed in 5.3.2 (2015-06-08).
  The server's chain was still validated against trusted CAs, but the client's own constraints on the server
  (identity and issuing CA) were "only enforced after all authentication rounds are completed successfully". A
  malicious server with any certificate from a trusted CA, reachable by any path (DNS spoofing was only the reporter's
  proof of concept), received the username and the MSCHAPv2 value for an offline dictionary attack. A client that
  accepted EAP-GTC could be made to send its plaintext password. [impl_cves-1]
  https://nvd.nist.gov/vuln/detail/CVE-2015-4171 · https://www.openwall.com/lists/oss-security/2015/05/29/6
- RFC 7296 §5: "An implementation using EAP MUST also use a public-key-based authentication of the server to the
  client before the EAP authentication begins, even if the EAP method offers mutual authentication." §2.16 adds that
  EAP "MUST be used in conjunction with a public-key-signature-based authentication of the responder".
  [impl_cves-1, protocol_attacks-1] https://www.rfc-editor.org/rfc/rfc7296
- Fortinet's documented dial-up example and first wizard option authenticate the FortiGate with a PSK shared by all
  users ("The same pre-shared key is used by all remote users ... For better security, use a digital certificate
  instead", doc 785501; "The key must be shared among all FortiClient endpoints", doc 137787). Signature
  authentication is offered next to it. It is not a firmware default. A PSK responder with EAP does not meet
  RFC 7296 §2.16 or §5, and RFC 5998's EAP-only exception does not cover it. [protocol_attacks-1]
  https://docs.fortinet.com/document/fortigate/8.0.0/administration-guide/913974/eap-user-authentication
- **Lesson:** the pin and AUTH checks happen on message 4, before our first EAP-Response. EAP-Identity counts.

### Class B: EAP completion trusted without proof

- **CVE-2021-45079**, strongSwan 4.1.2 up to 5.9.5 (advisory 2022-01-24, CVSS 9.1). The client ignored a failed MSK
  retrieval and built the AUTH payload without an MSK "even for methods that would actually be key-generating but
  were never completed". An EAP-Success before any method started crashed the daemon (NULL pointer). The server could
  skip its own authentication only with EAP-only authentication (RFC 5998) and a mutual, key-generating method such
  as EAP-TLS, TTLS or AKA. EAP-MSCHAPv2 cannot be shortcut this way because its MSK needs the password.
  Certificate-first setups (the strongSwan Android client's configuration) kept server authentication.
  [impl_cves-2, protocol_attacks-4, practices-2] https://nvd.nist.gov/vuln/detail/CVE-2021-45079 (the strongSwan
  advisory URL now returns 404; the text survives on the Wayback Machine [practices-2])
- RFC 3748 §4.2: a peer "MUST silently discard a 'canned' Success packet", so that "a rogue authenticator will not be
  able to bypass mutual authentication". §7.16: Success and Failure "are neither acknowledged nor integrity protected".
  Inside IKEv2 they travel in SK{}, so the realistic sender is the malicious responder or its AAA server.
  [protocol_attacks-4] https://www.rfc-editor.org/rfc/rfc3748
- RFC 2759 §5: "The authenticating peer MUST verify the authenticator response ... If the authenticator response is
  either missing or incorrect, the peer MUST end the session." This is the MS-CHAPv2 Success packet over PPP; applying
  it to EAP-MSCHAPv2 is an analogy. [practices-2] https://www.rfc-editor.org/rfc/rfc2759.txt
- RFC 7296 §2.16: for key-generating methods the MSK "MUST be used by both the initiator and responder to generate
  AUTH payloads in messages 7 and 8". [protocol_attacks-4]
- **Lesson:** EAP-Success is only the end of a checklist we verified ourselves.

### Class C: EAP method negotiation and downgrade

- RFC 3748 §7.8: "EAP does not provide protection for Nak Response packets". The same section defines the attack as
  convincing both sides "to negotiate a less secure EAP method". There SHOULD be "exactly one method" per peer name.
  §7.14: cleartext passwords "cannot be securely used within EAP, except where encapsulated within a protected tunnel
  with server authentication". §5.6: GTC "MUST NOT" carry cleartext passwords without such a tunnel.
  [protocol_attacks-5]
- CVE-2015-4171's EAP-GTC case (above) and CVE-2025-62291's precondition, "the client uses EAP without pinning a
  specific method" [impl_cves-3], both show the cost of accepting whatever method the server asks for.
- **Lesson:** one method per profile, and never adapt to the server's request.

### Class D: length arithmetic in parsers

- **CVE-2025-62291**, strongSwan eap-mschapv2 plugin (client side), 4.2.12 up to 6.0.3, advisory 2025-10-27, CVSS 8.1.
  The plugin checked the 6-byte minimal header against the whole packet instead of the payload, then subtracted the
  full 9-byte header. A Failure Request of 6 or 7 bytes gave a huge failed malloc and a segfault; 8 bytes gave
  malloc(0) and memcpy(-1), a heap overflow "potentially exploitable for remote code execution". The sender must be the
  authenticated IKEv2 server, or an on-path party between the IKEv2 and RADIUS servers holding the RADIUS secret
  when EAP-MSCHAPv2 is not tunnelled. [impl_cves-3, practices-1] https://nvd.nist.gov/vuln/detail/CVE-2025-62291
- **CVE-2024-20474**, Cisco Secure Client (4.9.00086 to 5.1.3.62, fixed 5.1.4.74): integer underflow in IKEv2
  processing, client app crash, needs user interaction (CVSS 4.3). **CVE-2016-6423**, Cisco IOS 15.5(3)M and IOS XE:
  a rogue IKEv2 server reloads the initiator device. [impl_cves-4]
  https://nvd.nist.gov/vuln/detail/CVE-2024-20474 · https://nvd.nist.gov/vuln/detail/CVE-2016-6423
- **CVE-2023-41913**, strongSwan charon-tkm only (5.3.0 to 5.9.11): unchecked copy of a DH public value into a
  512-byte stack buffer from a crafted IKE_SA_INIT, possible unauthenticated RCE. [impl_cves-9, practices-4]
  https://nvd.nist.gov/vuln/detail/CVE-2023-41913
- **Lesson:** every length is checked against its own container before any subtraction; in Kotlin the same bug becomes
  an exception or a huge allocation that kills the service.

### Class E: fragment reassembly

- **CVE-2016-1287**, Cisco ASA (IKEv1 and IKEv2, Cisco's proprietary fragmentation, not RFC 7383): "a signed check for
  a maximum value, but no minimum value"; a fragment shorter than its 8-byte header underflowed the copy length.
  Unauthenticated RCE, CVSS 9.8. [impl_cves-5] https://nvd.nist.gov/vuln/detail/CVE-2016-1287 ·
  https://blog.exodusintel.com/2016/02/10/firewall-hacking/
- **CVE-2024-20307/20308**, Cisco IOS/IOS XE IKEv1 fragmentation heap overflow and underflow, DoS only.
  **CVE-2026-12413**, libreswan 4.6 to 5.3 (fixed 5.3.1), off-by-one bounds assertion while storing unknown outer
  payloads of IKEv2 fragments, DoS only. **CVE-2016-10396**, racoon (IPsec-Tools 0.8.2), O(n^2) reassembly check, DoS.
  [impl_cves-5] https://nvd.nist.gov/vuln/detail/CVE-2026-12413 · https://nvd.nist.gov/vuln/detail/CVE-2016-10396
- RFC 7383: fragments are encrypted and authenticated one by one, and only IKE_AUTH and later can be fragmented. A
  peer that completed IKE_SA_INIT holds the keys and can send a large, incomplete, valid set. Capping the total
  decrypted size is RECOMMENDED, a cap above 64 KB is NOT RECOMMENDED, and on overflow the receiver SHOULD drop the
  connection and discard all fragments. [protocol_attacks-9] https://www.rfc-editor.org/rfc/rfc7383
- **Lesson:** fragmentation is a whole bug class. Ship without it if the testbed allows (R37).

### Class F: loose state machines

- **CVE-2026-78135**, strongSwan 5.9.7 to 6.0.7 (fixed 6.1.0), responder side: a CREATE_CHILD_SA request during EAP
  skipped the state check while passive tasks were queued, giving an unauthenticated peer a Child SA (removed after
  30 s; typical pool-based roadwarrior setups not affected). **CVE-2014-2338** (4.0.7 before 5.1.3) is the initiator
  variant: a rekey during initiation or re-authentication marked the IKE SA established. [impl_cves-6]
  https://nvd.nist.gov/vuln/detail/CVE-2026-78135 · https://nvd.nist.gov/vuln/detail/CVE-2014-2338
- **CVE-2019-12312**, libreswan 3.27: a bogus INFORMATIONAL where IKE_AUTH was expected made pluto try to send an
  encrypted error before keys existed, NULL pointer, restart. **CVE-2026-78133**, strongSwan 6.0.0 to 6.0.7:
  use-after-free in rekey collisions with multiple key exchanges (IKE_FOLLOWUP_KE), authenticated peer, potential RCE.
  [impl_cves-6] https://nvd.nist.gov/vuln/detail/CVE-2019-12312 · https://nvd.nist.gov/vuln/detail/CVE-2026-78133
- **CVE-2023-38710**, Libreswan 3.20 to 4.11 (C code): a Child SA REKEY with protocol ID 0 or 1 failed an assertion and
  restarted pluto. The same class in Kotlin is an uncaught `check()` or `require()` on peer data. [practices-3]
  https://nvd.nist.gov/vuln/detail/CVE-2023-38710
- **Lesson:** our EAP flow spans several IKE_AUTH round trips, exactly the window these bugs used.

### Class G: acting on messages that were not verified

- **CVE-2019-10155**, libreswan before 3.29 (also strongSwan before 5.0 and Openswan through 2.6.51.3): IKEv1
  INFORMATIONAL packets (DPD, Delete, Notify) were decrypted but their ICV was not checked. Impact was low because
  forged ciphertext decrypted to nonsense. [impl_cves-7] https://nvd.nist.gov/vuln/detail/CVE-2019-10155
- RFC 7296 §2.4 (the IKEv2 rule, applied here by analogy): an endpoint "MUST NOT conclude that the other endpoint has
  failed based on ... IKE messages that arrive without cryptographic protection (e.g., Notify messages complaining
  about unknown SPIs)", and "Implementations MUST limit the rate at which they take actions based on unprotected
  messages." [impl_cves-7] https://www.rfc-editor.org/rfc/rfc7296#section-2.4
- **Lesson:** our network-aware rejoin and drop alerts [local: `vpn/AndroidNetworkWatch.kt`, `vpn/DropAlerts.kt`] must never fire on unprotected input.

### Class H: signature and identity verification

- **CVE-2018-16151/16152**, strongSwan gmp plugin before 5.7.0: PKCS#1 v1.5 verification accepted extra bytes after the
  algorithm OID and in digestAlgorithm.parameters. With e=3 keys an attacker could impersonate any peer that
  authenticates with an RSA signature, or forge certificates if a CA key used e=3. This is Bleichenbacher's 2006
  low-exponent forgery, not a ROBOT padding oracle. [impl_cves-8, practices-4, protocol_attacks-13]
  https://nvd.nist.gov/vuln/detail/CVE-2018-16151
- **CVE-2024-45750**, TheGreenBow clients including Android 6.4.5 and older: malformed ECDSA signatures accepted and the
  tunnel established. **CVE-2020-16088**, OpenIKED (OpenBSD through 6.7): wrong public-key match logic,
  authentication bypass. (**CVE-2025-11955** is Windows Enterprise 7.5.x/7.6.x with OCSP enabled only.) [impl_cves-8]
  https://nvd.nist.gov/vuln/detail/CVE-2024-45750 · https://nvd.nist.gov/vuln/detail/CVE-2020-16088
- Felsch et al. (USENIX Security 2018): a Bleichenbacher oracle in IKEv1 RSA-encrypted-nonce modes breaks those modes
  and, when one RSA key is reused, RSA-signature authentication in IKEv1 and IKEv2 (Cisco, Huawei, Clavister, ZyXEL).
  A single attempt succeeds 7 to 26 % of the time under Cisco's default timers. [protocol_attacks-13]
  https://www.usenix.org/system/files/conference/usenixsecurity18/sec18-felsch.pdf
- **Lesson:** use the platform verifier strictly, and never implement RSA-encrypted-nonce modes or IKEv1.

### Class I: unvalidated key exchange values and proposals

- **CVE-2015-3240**, libreswan before 3.15 and Openswan before 2.6.45 (NSS builds): a zero g^x crashed pluto.
  **CVE-2014-9221**, strongSwan 4.5.0 through 5.2.x (the two checks gave 5.2.0 and 5.2.1 as the last affected
  version): a KE payload with DH group 1025 caused an invalid pointer dereference. Both DoS only.
  [impl_cves-9] https://nvd.nist.gov/vuln/detail/CVE-2015-3240 · https://nvd.nist.gov/vuln/detail/CVE-2014-9221
- **CVE-2024-3652**, libreswan 3.22 to 4.14, is a different pattern: after authentication, an IKEv1 Quick Mode
  proposal with AES-GMAC crashed a responder that had no esp= line. It shows that unexpected proposals reach code
  paths nobody tested. [impl_cves-9] https://libreswan.org/security/CVE-2024-3652
- RFC 6989: MODP receivers check 1 < r < p-1 (plus r^q = 1 or no key reuse for small-subgroup groups); ECP receivers
  check the point is on the curve, y^2 = x^3 + ax + b mod p. §2 makes the tests RECOMMENDED for all implementations
  and REQUIRED for those that reuse DH private keys. RFC 5903 §7: the ECDH shared secret is the x coordinate only.
  RFC 7748 §5: X25519 receivers MUST mask the top bit and MUST accept non-canonical values; §6.1: they MAY abort on an
  all-zero shared secret. [practices-5, impl_cves-9] https://www.rfc-editor.org/rfc/rfc6989.html

### Class J: weak and downgraded algorithms

- RFC 8247 (IKEv2): MUST NOT for ENCR_NULL, ENCR_DES, PRF_HMAC_MD5, AUTH_HMAC_MD5_96 and DH groups 1 and 22; SHOULD NOT
  for groups 2, 5, 23 and 24; ENCR_3DES is MAY. RFC 8221 (ESP): ENCR_NULL is a MUST (for authentication-only ESP),
  3DES SHOULD NOT, DES and AUTH_HMAC_MD5_96 MUST NOT, and §4: "Encryption without authentication is not effective and
  MUST NOT be used." Refusing 3DES and ESP NULL is our local policy, stricter than the RFCs. [impl_cves-10,
  protocol_attacks-14] https://www.rfc-editor.org/rfc/rfc8247 · https://www.rfc-editor.org/rfc/rfc8221
- SWEET32 (CVE-2016-2183) names IPsec explicitly. Logjam (CCS 2015): 66.1 % of profiled IKEv1 and 63.9 % of IKEv2
  servers preferred Oakley Group 2, a projection of exposure if that one 1024-bit group were broken. [impl_cves-10,
  protocol_attacks-7] https://weakdh.org/
- RFC 7296 §2.15: AUTH covers the latest IKE_SA_INIT messages, so tampering with the final exchange is caught. The
  downgrade path is a forged rejection (INVALID_KE_PAYLOAD, NO_PROPOSAL_CHOSEN) that steers our retry. §1.2: after
  INVALID_KE_PAYLOAD the initiator "MUST again propose its full set of acceptable cryptographic suites". A weak group
  that stays in the offer can still be reached, so weak groups must be left out, not ranked lower.
  [protocol_attacks-7]

### Class K: ESP integrity and replay

- RFC 4303 §3.4.3: "The receive window is updated only if the integrity verification succeeds." A 32-packet window
  MUST be supported with 32-bit sequence numbers and 64 SHOULD be the default; a preliminary sequence check before
  integrity is allowed if it changes no state. Anti-replay MUST be supported, is on by default, and MUST NOT be
  enabled without integrity. §3.4.4.1: in parallel processing, integrity checking "MUST be completed before the
  decrypted packet is passed on". [impl_cves-11, protocol_attacks-14] https://www.rfc-editor.org/rfc/rfc4303
- **CVE-2025-2796**, Arista EOS 4.33.0 to 4.33.2F with hardware IPsec: duplicate packets forwarded despite anti-replay.
  **CVE-2020-3220**, Cisco 4300 ISR and Catalyst 9800-L hardware crypto driver: "insufficient verification of
  authenticity of received ESP packets" let a man in the middle disconnect sessions (linking it to window ordering is
  an inference). [impl_cves-11] https://nvd.nist.gov/vuln/detail/CVE-2025-2796
- Degabriele and Paterson (IEEE S&P 2007) break "any RFC-compliant implementation of IPsec making use of
  encryption-only ESP". [protocol_attacks-14] https://eprint.iacr.org/2007/125
- (CVE-2017-7184 is a local privilege escalation in Linux replay-state configuration code, not a wire-level replay
  failure. It only shows that replay bookkeeping is attack surface too. [impl_cves-11])

### Class L: AES-GCM nonce reuse

- Joux's "forbidden attack": two messages under one IV reveal candidates for the hash key H; with H the attacker can
  put arbitrary content under an IV already seen with a valid tag. The key K is not recovered. Böck et al. (WOOT 2016)
  found 184 HTTPS servers repeating nonces, which "fully breaks the authenticity". [protocol_attacks-6, practices-6]
  https://www.usenix.org/conference/woot16/workshop-program/presentation/bock
- RFC 4106 §3.1: "For a given key, the IV MUST NOT repeat. The most natural way to implement this is with a counter".
  16-octet ICVs MUST be supported and implementations "SHOULD use as large a size as reasonable". NIST SP 800-38D §8:
  IV uniqueness is "almost as important as the secrecy of the key"; §9.1: "A loss of power to the module shall not
  cause the repetition of IVs." RFC 4303 §2.2: with anti-replay on, the sequence number "must never be allowed to
  cycle". [protocol_attacks-6, practices-6] https://www.rfc-editor.org/rfc/rfc4106 ·
  https://nvlpubs.nist.gov/nistpubs/Legacy/SP/nistspecialpublication800-38d.pdf
- **Lesson:** Android killing the VPN process is our "loss of power" case.

### Class M: password-equivalent credentials exposed by design

- MS-CHAPv2's security reduces to one DES encryption (2^56, inferred from RFC 2759 §8.5); Marlinspike, Hulton and Ray
  (DEF CON 20, 2012) cracked any captured handshake "with a 100% success rate", in under a day. The recovered NT hash
  is enough to authenticate as the user. Microsoft advisory 2743314 is scoped to PPTP with MS-CHAPv2 as the only
  authentication, and recommends PEAP or IKEv2/L2TP/SSTP tunnels around it. The break needs the handshake in the
  clear or a man in the middle on the outer tunnel. [protocol_attacks-3, impl_cves-14]
  https://www.theregister.com/2012/07/31/ms_chapv2_crack/ ·
  https://learn.microsoft.com/en-us/security-updates/securityadvisories/2012/2743314
- RFC 5998 §4: EAP-only responder authentication needs methods that are mutual, key-generating and dictionary-attack
  resistant. MSCHAPv2 fails the last test. §6.3: until AUTH is verified, a man in the middle can read the EAP payloads.
  Felsch §9.2: EAP-MSCHAPv2 does "not prevent offline dictionary attacks, they just require the attackers to shift from
  IKE to attacking EAP". [impl_cves-14] https://www.rfc-editor.org/rfc/rfc5998#section-4
- PSK: Felsch et al. showed an active attacker posing as the responder can brute-force an IKE PSK offline (tested on
  IKEv1 main mode; "works similarly against IKEv2"). Against a FortiGate the roles reverse: it sends its PSK-keyed
  AUTH in message 4 before checking any client credential, so an attacker acting as initiator can guess the PSK
  offline, limited only by the gateway's ID checks. RFC 7296 §2.15 warns dictionary attacks "are not prevented".
  [protocol_attacks-2]

### Class N: logging

- CVE-2022-33878 (above, local user reads a password from a log stream). **CVE-2023-28771**, Zyxel firewalls: per
  Rapid7, the Notify data of an IKEv2 NO_PROPOSAL_CHOSEN was copied into a log line built as a shell command and run
  with system(), giving unauthenticated root command execution (CISA KEV 2023-05-31). **CVE-2020-1763**, libreswan
  3.27 to 3.31: building a "packet dropped" log message for a stateless IKEv1 INFORMATIONAL packet dereferenced NULL,
  DoS. [impl_cves-12] https://nvd.nist.gov/vuln/detail/CVE-2023-28771 ·
  https://www.rapid7.com/blog/post/ra-cve-2023-28771-analysis/
- Android: "Ensure all logging to logcat is sanitized in non-debug versions of your application." [impl_cves-12]
  https://developer.android.com/privacy-and-security/risks/log-info-disclosure

### Class O: memory-safe code still fails

- Google: memory-safety issues fell from 76 % of Android vulnerabilities (2019) to 24 % (2024, partial year), and
  vulnerabilities "decay exponentially" with code age, so new code carries most of them. [practices-3]
  https://security.googleblog.com/2024/09/eliminating-memory-safety-vulnerabilities-Android.html
- Bouncy Castle Java: CVE-2024-29857 (EC F2m parameters, excessive CPU, before 1.78), CVE-2024-30172 (Ed25519 verify
  infinite loop, before 1.78), CVE-2025-8916 (PKIXCertPathReviewer excessive allocation, 1.44 to 1.78). [practices-3]
- Protocol state fuzzing found logic flaws in Java's JSSE as well as GnuTLS and OpenSSL (USENIX Security 2015).
  [practices-13] https://www.usenix.org/conference/usenixsecurity15/technical-sessions/presentation/de-ruiter
- **Lesson:** a brand-new Kotlin engine sits at the top of the vulnerability curve. Language safety is not the budget.

### Class P: client-side leaks around the tunnel

- TunnelVision (CVE-2024-3661): DHCP option 121 routes pull traffic off the VPN on Windows, Linux, iOS and macOS.
  Android was unaffected only because its DHCP client lacks option 121, which is not a permanent guarantee.
  [protocol_attacks-10] https://www.leviathansecurity.com/blog/tunnelvision
- TunnelCrack (USENIX Security 2023): 33 of 42 Android VPN apps were not vulnerable to LocalNet, credited to per-UID
  policy routing since Android 4.4. ServerIP hit only Android's built-in legacy VPNs, fixed in AOSP 12+ by removing
  those protocols (a Samsung Android 12 device stayed vulnerable). RFC 1918-only exclusion is "not complete" in split
  tunnels. [protocol_attacks-11] https://tunnelcrack.mathyvanhoef.com/details.html
- Mullvad: Android sends connectivity checks outside the VPN on every Wi-Fi join, even with "Block connections without
  VPN" (MUL22-03). DNS leaks for direct `getaddrinfo` callers when a VPN has no DNS server, or briefly while a VPN
  reconfigures or crashes; seen on several versions including Android 14. [protocol_attacks-12]
  https://mullvad.net/en/blog/dns-traffic-can-leak-outside-the-vpn-tunnel-on-android

### Class Q: the peer's own bugs

- **CVE-2024-46670** (FG-IR-24-266): out-of-bounds read in the FortiOS IKE service, unauthenticated DoS, FortiOS
  7.6.0, 7.4.0 to 7.4.4, 7.2.0 to 7.2.9, fixed in 7.6.1, 7.4.5 and 7.2.10. **CVE-2024-46669** (FG-IR-24-267): integer
  overflow in the IKEv1 service, an authenticated attacker crashes the tunnel; fixed in 7.4.5 and 7.2.12; Fortinet's
  workaround is IKEv2. **CVE-2017-3130**: old FortiOS leaked its build version in IKE Vendor ID payloads.
  [impl_cves-13] https://fortiguard.fortinet.com/psirt/FG-IR-24-266
- **Lesson:** the tunnel will sometimes vanish under us for reasons that are not our bugs. Reconnect must be calm.

### Class R: TCP encapsulation and pre-auth DoS

- RFC 9329 §Security: SYN floods, RST spoofing, Length-field injection (mis-framing; Length 0 or 1 MUST close the
  connection), and "An attacker capable of blocking UDP traffic can force peers to use TCP encapsulation". Injected
  TCP data "has no effect on application data". State SHOULD survive TCP drops. Each stream MUST begin with "IKETCP",
  sent once by the TCP originator. RFC 9329 itself names port 4500, not 443; port 443 is Fortinet's
  [protocol_attacks-8; local: docs/protocol/fortigate-ipsec.md]. https://www.rfc-editor.org/rfc/rfc9329
- RFC 7296 §5: "the unlimited number of messages in EAP-based authentication" makes pre-auth DoS "particularly
  worrisome". COOKIE (§2.6) and RFC 8019 puzzles are the responder's tools; an initiator MAY ignore a PUZZLE notify.
  [protocol_attacks-9] https://www.rfc-editor.org/rfc/rfc8019

---

## 3. Design rules the engine must follow

Each rule is written so a test can fail it. "Test" names the check that proves it. Sources in brackets.

### A. Gateway authentication and EAP (R1 to R8)

**R1. Authenticate the gateway on message 4, before any EAP-Response.** On the first IKE_AUTH response, verify IDr,
the responder's AUTH (signature against the pinned certificate, or PSK AUTH), and the per-host pin, before sending any
EAP-Response, EAP-Identity included. *Test:* a test responder sends a valid EAP-Request/Identity with a wrong AUTH, a
wrong IDr, or an unpinned certificate; the engine sends nothing more and fails with a typed `VpnException`.
[impl_cves-1, protocol_attacks-1; RFC 7296 §5]

**R2. Refuse EAP-only.** A first IKE_AUTH response without a responder AUTH is a hard failure. Never offer
EAP_ONLY_AUTHENTICATION while the method is MSCHAPv2. *Test:* response with EAP but no AUTH fails before EAP.
[impl_cves-2, impl_cves-14; RFC 5998 §4]

**R3. Pins are exact and never soft-fail.** Compare the full hash (constant time is harmless here, since the pin is
public). No "accept this time" path and no revocation soft-fail. On an unpinned host the engine stops after message 4,
reports the fingerprint for the user to confirm, sends no EAP, and after confirmation starts a fresh IKE SA
[inference]. *Test:* one flipped bit in the certificate or key gives a pin mismatch; an unpinned host never reaches
EAP. [impl_cves-8] Decision to take (section 6): the SSL-VPN pin today is SHA-256 of the DER leaf certificate,
compared as a hex string [local: `security/CertPinning.kt`]; the claim's advice is a full SPKI hash.

**R4. Verify signatures only through the platform, strictly.** Use JCA `Signature.verify`, never hand-rolled PKCS#1
or DER parsing. Require strict DER for ECDSA, and check the RFC 7427 AlgorithmIdentifier matches the key type.
*Test:* known-bad signature vectors (trailing data, e=3 forgeries, malformed ECDSA) all fail. [impl_cves-8,
practices-4, protocol_attacks-13]

**R5. Record how the gateway authenticates, and treat a change as an attack.** The profile stores the gateway's
authentication method and IDr seen at first confirmation. PSK with MSCHAPv2 needs an explicit user acknowledgement
(section 5.1). A pinned certificate host that later answers with PSK AUTH is a hard failure, before EAP [inference].
*Test:* profile pinned with a certificate, responder switches to AUTH method 2, engine stops with a specific
`ErrorCode`. [protocol_attacks-1, impl_cves-14]

**R6. EAP-Success is the end of a checklist.** Accept it only after: our MSCHAPv2 Response was sent, the MSCHAPv2
Success Request arrived, the authenticator response (S=) verified in constant time, and the MSK was derived. A canned
or early Success, or a missing or wrong S=, ends the attempt; the engine never continues to the final AUTH.
*Test:* every (state x message) cell with EAP-Success in it. [practices-2, protocol_attacks-4, impl_cves-2;
RFC 3748 §4.2, RFC 2759 §5]

**R7. Both final AUTH payloads use the MSK.** Compute ours with the MSK and verify the gateway's with the MSK
(RFC 7296 §2.16). A missing MSK or a mismatch is a hard `VpnException`, never a fallback to SK_pi/SK_pr.
*Test:* responder sends a final AUTH computed with SK_pr; engine fails. [impl_cves-2, protocol_attacks-4]

**R8. One EAP method per profile.** NAK any other requested type and abort rather than adapt. Never send a cleartext
password except inside a completed, server-authenticated EAP-TTLS tunnel (if TTLS is ever added). *Test:* requests
for GTC, MD5, OTP and an unknown type all end the attempt without sending credentials. [protocol_attacks-5,
impl_cves-3]

### B. Parsing (R9 to R16)

**R9. One bounded reader.** All decoding goes through one `ByteReader` that checks declared >= header and
declared <= remaining before any arithmetic, and computes each sub-length from the right header (IKE payload, EAP,
MSCHAPv2, message text). *Test:* for each message type, every length from 0 to the minimum plus 1 is rejected
cleanly. [impl_cves-3, impl_cves-4, practices-1]

**R10. Fixed-size fields have exact sizes.** The KE group equals the group we sent and the KE length equals that
group's exact size (for example 64 bytes for group 19, 32 for X25519). *Test:* KE one byte short, one byte long, and
with a different group number all fail. [impl_cves-9, practices-4]

**R11. No trailing bytes, respect the critical bit.** Reject trailing bytes everywhere. Reject unknown payloads with
the critical bit set (RFC 7296 §3.2). Ignore unknown non-critical payloads, including unknown Vendor IDs, and never
base a decision on Vendor ID contents. *Test:* append one byte to any valid message and it fails; an unknown critical
payload fails; an unknown VID changes nothing. [practices-4, impl_cves-13]

**R12. Hard caps before allocating.** Maximum IKE message size, payload count, certificate bytes, EAP rounds, and
TCP frame size are checked before any buffer is allocated. *Test:* property test that declared sizes above each cap
never allocate. [practices-3, protocol_attacks-9]

**R13. No assertions on peer data; one exception boundary.** No `require`, `check`, `!!` or unchecked indexing on
attacker-controlled data. One parse boundary maps every failure to a typed `VpnException` (today's closest code is
`ErrorCode.PROTOCOL`; the spike may add finer ones), matching the repo rule of typed errors, never text matching
[local: CLAUDE.md, `state/VpnStatus.kt`]. *Test:* each fuzz harness asserts that only
`VpnException` escapes. [practices-3]

**R14. Cheap checks first.** SPIs and message ID are checked before deep parsing or decryption. *Test:* wrong SPI or
unexpected message ID is dropped without touching the payload decoder. [impl_cves-4]

**R15. MSCHAPv2 text is untrusted.** Treat the Failure fields (E=, R=, C=, V=, M=) and the Success message as
untrusted input with length limits. *Test:* short and empty Failure Requests (the 6 to 8 byte CVE-2025-62291 shapes)
are regression cases. [impl_cves-3]

**R16. Peer data never reaches a shell, a format string or reflection.** Log formatting is null-safe for "no state"
cases. *Test:* lint rule plus a unit test logging a message for a packet with no matching state. [impl_cves-12]

### C. State machine (R17 to R20)

**R17. A sealed-class state machine with an explicit table.** For each state the table lists the allowed exchange
type, response flag and message ID. Everything else is dropped. Only `ConnectionOrchestrator` knows the sequence
[local: CLAUDE.md]. *Test:* the full (state x message) matrix, including every illegal transition. [impl_cves-6,
practices-2]

**R18. Nothing is installed or acted on before both AUTH payloads verify.** No CREATE_CHILD_SA, rekey or
INFORMATIONAL is processed, and no ESP key or route is installed, until R1 and R7 have both passed.
*Test:* CREATE_CHILD_SA, rekey and INFORMATIONAL injected during each EAP round are dropped. [impl_cves-6]

**R19. `Connected` is only reachable through server authentication and EAP success.** *Test:* property test over
random message sequences: the machine never reaches `Connected` without passing `ServerAuthVerified` and
`EapSucceeded`. [practices-12]

**R20. Keep rekeying simple at first.** Do not implement multiple key exchanges (IKE_FOLLOWUP_KE) in the first
version, and handle rekey collisions by an explicit, tested rule [inference from CVE-2026-78133]. *Test:*
simultaneous rekey from both sides in the matrix. [impl_cves-6]

### D. Negotiation, key exchange and randomness (R21 to R26)

**R21. Offer only an allowlist.** IKE and ESP: AES-GCM, or AES-CBC with HMAC-SHA2. DH groups 14, 19, 20, 21 and 31.
Never NONE integrity or ENCR_NULL for IKE (RFC 7296 §5 MUST NOT); by local policy also no ESP NULL encryption, no 3DES,
no DES, no MD5. Refuse a response that selects anything else and show a clear "outdated encryption" error instead of
connecting. *Test:* a responder selecting each forbidden transform is refused. [impl_cves-10, protocol_attacks-7,
protocol_attacks-14] (Group 31 needs Android 13 or Bouncy Castle [local: android_feasibility.md §1.5].)

**R22. The responder's SA must be a subset of our offer.** Exactly one transform per type, each one we offered; with
AEAD, no integrity transform or a single NONE. *Test:* two transforms of one type, an unoffered transform, or AEAD
plus a real integrity transform all fail. [impl_cves-9, protocol_attacks-7]

**R23. Handle INVALID_KE_PAYLOAD without being steered.** Retry only with a group from our allowlist, resend the full
proposal list, and cap retries. *Test:* forged INVALID_KE_PAYLOAD asking for group 2 is refused; one asking for
group 19 leads to a retry that still carries the full list. [protocol_attacks-7]

**R24. Validate every peer DH value; use fresh DH each time.** MODP: 1 < r < p-1. ECP: on-curve check before
`KeyAgreement`, because invalid-point handling is provider-dependent. X25519: mask the top bit, accept non-canonical
values, abort on an all-zero shared secret (cheap, so do it). ECDH secret is the x coordinate only. Never reuse DH
private values. *Test:* RFC 5903 §8 and RFC 7748 §5.2 vectors pass; Wycheproof invalid-curve vectors fail.
[practices-5, impl_cves-9] https://appsec.guide/docs/crypto/wycheproof/

**R25. Randomness from one injected `SecureRandom`.** `new SecureRandom()`, no `setSeed`, no provider name (the
"Crypto" provider was removed in Android 9; name a provider only for the Keystore). Nonces are 16 to 256 bytes, at
least half the key size of every PRF we propose, never reused. 32 bytes covers every SHA-2 PRF we offer [inference;
the probe already sends 32, local]. *Test:* nonce length per proposed PRF; tests inject a deterministic source.
[practices-9; RFC 7296 §2.10, §3.9]

**R26. IKEv2 only.** No IKEv1 (deprecated by RFC 9395) and no RSA-encrypted-nonce modes. [protocol_attacks-13,
protocol_attacks-14]

### E. ESP data path (R27 to R33)

**R27. Fixed receive order.** SPI match, then a replay pre-check that changes nothing, then the ICV check in constant
time (or AEAD open), then the window update, then decrypt and deliver. Window of 64 or more. *Test:* duplicates,
out-of-window packets and bad-ICV packets are dropped, and a bad-ICV packet never moves the window. [impl_cves-11,
protocol_attacks-14]

**R28. Authenticate the sequence number.** With AEAD, the sequence number is part of the AAD (and ESN high bits, if
ESN is ever negotiated). *Test:* a packet with a modified sequence number fails. [impl_cves-11]

**R29. Outbound GCM IV is a per-SA 64-bit counter with a single owner.** Never random. A new `Cipher` init with the new
IV for every packet. Distinct per-SA salt from KEYMAT. Prefer the 16-octet ICV. Keep it in the pure codec.
*Test:* over a long run and under concurrent sends, every (key, IV) pair is distinct. [protocol_attacks-6,
practices-6]

**R30. Rekey before the counter can wrap, and hard-stop at the limit.** A new Child SA well before 2^32 packets
(32-bit sequence numbers); the sender refuses to send rather than cycle. *Test:* a counter set near the limit triggers
a rekey, and at the limit sending fails. [practices-6; RFC 4303 §2.2, §3.3.3]

**R31. Never resume SA keys or counters after process death.** A restarted service always builds a new IKE SA.
*Test:* the engine has no code path that loads SA keys or counters from storage. [practices-6, protocol_attacks-6;
SP 800-38D §9.1]

**R32. AES-CBC IVs are random and unpredictable.** From the injected `SecureRandom`, never a counter (RFC 3602 §3).
*Test:* the CBC encoder takes its IV from the random source. [protocol_attacks-14]

**R33. Never encryption-only ESP.** Every ESP SA has integrity (AEAD or HMAC). *Test:* covered by R21 and R22.
[protocol_attacks-14; RFC 8221 §4]

### F. Unprotected messages, liveness and reconnect (R34 to R36)

**R34. Only protected messages change state.** Act on DELETE, INITIAL_CONTACT, AUTHENTICATION_FAILED and similar
notifies only inside a verified SK payload. An unprotected INVALID_SPI or error notify triggers at most a rate-limited
liveness probe, never a teardown and never a user-visible error. The peer is dead only after repeated unanswered
protected attempts over a timeout. *Test:* a flood of unprotected INVALID_SPI causes at most N probes per minute and
no disconnect. [impl_cves-7; RFC 7296 §2.4]

**R35. Calm reconnects.** Backoff with jitter, a clean IKE_SA_INIT restart after unanswered retransmits, and a cap on
attempts, so that always-on or a crash-restart never becomes a tight loop. *Test:* a responder that crashes the
engine's input on every attempt produces a slowing, bounded retry sequence. [impl_cves-13, practices-3]

**R36. Cooperate with COOKIE; ignore PUZZLE.** Retry IKE_SA_INIT with the cookie, tolerate a reissued cookie, cap the
loop. Ignore a PUZZLE notify (RFC 8019 permits it). *Test:* cookie, reissued cookie, endless cookies (bounded).
[protocol_attacks-9]

### G. Fragmentation (R37)

**R37. Ship without RFC 7383 fragmentation first; if we must add it, add it strictly.** The need depends on whether
the FortiGate's IKE_AUTH certificate chain exceeds the path MTU on mobile networks, which the testbed must show
[impl_cves-5]. If added: accept only Encrypted Fragment payloads, verify each fragment's ICV and silently drop
failures before buffering, validate Fragment Number and Total Fragments, restart on an inconsistent Total, cap the
total decrypted size at 64 KB or less and drop the exchange when exceeded, and time out incomplete sets.
*Test:* zero-length, oversized, duplicate, out-of-range and inconsistent-Total fragments; a valid but never-complete
set. [impl_cves-5, protocol_attacks-9; RFC 7383 §2.2, §2.6, §5]

### H. TCP transport (R38, R39)

**R38. Send "IKETCP" once at the start of every TCP connection we open,** including reconnects for an existing IKE SA.
Never expect it from the responder. *Test:* framer output for new and reopened streams. [protocol_attacks-8]

**R39. A strict framer that survives drops.** Validate the 16-bit Length against the buffer; Length 0 or 1 closes the
connection; any unparseable frame is treated as corruption (close and reconnect, bounded). Keep the IKE SA and keys
across TCP drops and reopen; a bare RST is not a teardown. Prefer UDP and fall back to TCP after retransmits, unless
the profile says TCP [inference: for example when the user's network blocks UDP]. *Test:* fuzzed stream splits, Length
0, 1 and 65535, RST mid-session keeps the IKE SA. [protocol_attacks-8]

### I. Android routing and leaks (R40, R41)

**R40. Full tunnel means nothing falls through.** Never call `allowBypass()`. Route all traffic through the TUN in
full-tunnel mode and leave IPv6 blocked unless explicitly split. Always call `addDnsServer(...)`: never bring up a TUN
with no DNS server. Hold the existing TUN across reconnects and establish the replacement before tearing down.
*Test:* on a device, capture on the physical interface during connect, reconnect and a forced crash.
[protocol_attacks-10, protocol_attacks-12] Note [local]: today's `vpn/AndroidTun.kt` adds DNS servers only when the
gateway or config provides some, and swallows failures with `runCatching`, so an empty list gives exactly Mullvad's
"VPN with no DNS server" case.

**R41. Split tunnels are checked against the local network.** Do not exclude local-network routes by default. In
split-tunnel mode, warn when an included subnet overlaps the current local network, and only ever exclude RFC 1918
ranges, never public ones. Resolve the gateway name once and keep that IP for the session. *Test:* `Routes` unit tests
for overlap warnings and exclusion ranges. [protocol_attacks-11]

### J. Secrets (R42 to R45)

**R42. No secrets in logs, ever.** Never log the password, NT hash, NT-Response, PSK, MSK, nonces, SKEYSEED, SK_* or
ESP keys. Log constant strings plus `ErrorCode`. Wrap secrets in types whose `toString()` redacts. Strip verbose
`Log` calls with R8 in release builds. *Test:* a unit test that renders every secret type; a CI grep over engine
sources. [impl_cves-12; local: CLAUDE.md]

**R43. Constant-time comparison for every secret.** ESP ICV (CBC plus HMAC), the MSCHAPv2 authenticator response and
the AUTH values use `MessageDigest.isEqual` or a local OR-accumulate loop. Android documents the constant-time
behaviour only as an "Implementation Note" with no API level, so keep the local loop as the fallback for API 29.
*Test:* a lint or grep rule forbids `contentEquals` and `==` on secret arrays. [practices-8]

**R44. Wipe what we own; store nothing we do not need.** Secrets we own live in `ByteArray`/`CharArray` and are
overwritten at rekey and teardown. SA keys are never persisted. The password at rest lives only in the Android
Keystore [local: CLAUDE.md]. This is best effort: `SecretKeySpec.destroy()` is "Won't Fix" in the JDK, `String` and
`BigInteger` cannot be wiped, and `Arrays.fill` can be optimized away. *Test:* no engine API takes the password as
`String` past the bridge [inference]. [practices-10]

**R45. Bouncy Castle only where the platform has a gap, at a fixed version.** Use it for MD4 (MSCHAPv2) and X25519
below API 33 [local: android_feasibility.md §0], never for certificate path review. Pin a version after 1.78 (all
three DoS CVEs are fixed only then). *Test:* dependency lock plus OSV-Scanner. [practices-3]

### K. Supply chain (R46, R47)

**R46. Locked and verified dependencies.** Gradle lockfiles and `gradle/verification-metadata.xml` with PGP and
SHA-256. Check bootstrapped checksums by hand: Android warns "It's possible that the current set of checksums and
signatures are already compromised." OSV-Scanner
on `gradle.lockfile`, `verification-metadata.xml` and `pubspec.lock`. Dependabot sees Gradle only through dependency
submission. [practices-15] https://developer.android.com/build/dependency-verification

**R47. Test tools that cannot hijack the workflow.** kotest-property, not jqwik (1.10.0 printed a hidden instruction
aimed at AI coding agents; 1.10.x keeps an "Anti-AI Usage Clause"). Pin the Jazzer version, and write fuzz targets as
plain `fuzzerTestOneInput(ByteArray)` functions so they survive a change of fuzzer. [practices-11, practices-12]

---

## 4. Verification pipeline

### 4.1 Prerequisite: where the tests run

- Protocol logic stays pure and I/O-free, as the repo already requires for `sslvpn/` [local: CLAUDE.md]. Then all of
  4.2 to 4.5 are plain JVM tests that run in seconds.
- Jazzer's `@FuzzTest` is a JUnit 5 integration; the app module uses `junit:junit:4.13.2` [local:
  `android/app/build.gradle.kts`]. Simplest path: put the pure engine in a plain Kotlin/JVM Gradle module with JUnit 5,
  and keep the app module on JUnit 4. [practices-11]
- The repo has no CI workflow today [local]. "CI" below means one to add.

### 4.2 Known-answer tests (official vectors)

| Primitive | Source | Notes |
|---|---|---|
| MSCHAPv2 PasswordHash to AuthenticatorResponse | RFC 2759 §9.2 | Stops before any MSK. Erratum 1924: password is UTF-16LE; add our own non-ASCII case. |
| MSCHAPv2 MasterKey and MPPE keys | RFC 3079 §3.5.1 to §3.5.3 (same User/clientPass inputs) | MasterKey FDECE3717A8C838CB388E527AE3CDD31. The 64-octet MSK layout has no official vector: confirm by interop. |
| HMAC-SHA2 incl. 128-bit truncation | RFC 4231 (Test Case 5) | SHA-384/192 and SHA-512/256 truncations only in RFC 4868. |
| PRF and HMAC-SHA-256-128 as used in IPsec | RFC 4868 §2.7 | Erratum 1785: the AUTH512-4 key is misprinted, use 0x01..0x40. Do not apply erratum 5507. |
| prf+, SKEYSEED, SK_* | NIST CAVP SP 800-135 `ikev2.zip` | RFC 4868 covers one PRF call only. |
| AES-GCM incl. failing decrypts | NIST CAVP `gcmtestvectors.zip` | Filter IVlen=96, Taglen=128. FAIL cases include bad ciphertext as well as bad tags. |
| AES-CBC | RFC 3602 §4 (128-bit), NIST AESAVS (256-bit) | |
| HMAC-SHA-1-96, ChaCha20-Poly1305 (if offered) | RFC 2202 §3 TC5; RFC 7634 App. A and B | |
| ECDH groups 19/20/21 | RFC 5903 §8 | |
| X25519 | RFC 7748 §5.2 | The second vector sets the top bit, so it tests masking. |
| MODP-2048 (group 14) | none official found | Round-trip and interop only. |

All from [practices-7]. Run the same vectors twice: as JVM unit tests and as instrumented tests on a device, because
Android does not guarantee which provider serves an algorithm. https://developer.android.com/privacy-and-security/cryptography

### 4.3 Deterministic adversarial unit tests

- The (state x message) matrix for R17 to R20, including EAP-Success in every cell (R6).
- Truncation ladders: every length from 0 to minimum plus 1 for every message type (R9, R15).
- A **hostile test responder**, written from the RFCs inside the test sources, that can on command: send a wrong AUTH
  with a valid EAP-Request (R1), omit AUTH (R2), switch certificate to PSK (R5), send early or canned EAP-Success,
  omit or corrupt S= (R6), sign the final AUTH with SK_pr (R7), request GTC (R8), send 6 to 8 byte MSCHAPv2 Failures
  (R15), inject CREATE_CHILD_SA or INFORMATIONAL during EAP (R18), forge INVALID_KE_PAYLOAD (R23), send bad DH
  values (R24), flood unprotected INVALID_SPI (R34), and misframe TCP (R39) [inference].
- ESP: duplicates, out-of-window, bad ICV that must not move the window (R27), counter near the wrap (R30).
- Known-bad signatures (R4) and Wycheproof invalid-curve vectors (R24).

### 4.4 Property tests (kotest-property)

`decode(encode(x)) == x`; every strict prefix of a valid message is rejected; any single-byte length-field mutation
is rejected or re-encodes identically; the machine never reaches `Connected` without `ServerAuthVerified` and
`EapSucceeded`; the ESP sender never repeats an IV; declared sizes above a cap never allocate. [practices-12]

### 4.5 Fuzz targets, one per pure core

Proposed cores (names are placeholders [inference]). Oracle for all: only `VpnException` escapes, no allocation above
the caps, and inputs that decode re-encode identically.

| Target | Input | Seeds |
|---|---|---|
| IKE message decoder (header plus payload chain) | raw message | probe replies and bench traces (redacted) |
| SA proposal selector | SA payload bytes | our offer, FortiGate replies |
| KE and DH validator | group number plus bytes | RFC 5903, RFC 7748 vectors |
| IKE_AUTH payload set (IDr, CERT, AUTH, CP) | decrypted SK contents | bench traces |
| EAP and MSCHAPv2 decoder | EAP packet | RFC 2759 values, 6 to 8 byte Failures |
| Traffic selectors and config payload | TS/CP payloads | bench traces |
| SK payload decrypt then decode | ciphertext under fixed test keys | encrypt valid messages under the test keys |
| Fragment reassembler (only if R37 adds it) | sequence of fragments | split valid messages |
| TCP stream framer | byte stream | IKETCP plus valid frames |
| ESP decap plus replay window | packet sequence under fixed keys | valid packets, replays |
| IKE state machine | sequence of decoded messages | recorded good runs |

Jazzer runs saved inputs as regression tests by default and fuzzes only when `JAZZER_FUZZ` is set, one fuzz test per
run (default `maxDuration` 5 minutes). Crashing inputs are committed as a regression corpus. ClusterFuzzLite batch
fuzzing on a cron is optional. Jazzer's steward, Code Intelligence GmbH, has a provisional insolvency administrator
(order 2026-03-09) and a "Liquidation" register entry (2026-06-05), so pin the version and keep targets
fuzzer-neutral (R47). [practices-11, impl_cves-4] https://google.github.io/oss-fuzz/getting-started/new-project-guide/jvm-lang/

### 4.6 Interop and black-box differential testing

- **AWS FortiGate** [local: testbed.md]: the free permanent-trial VM is limited to low encryption, so AES/SHA2 runs
  need the AWS PAYG instance. Matrix: FortiOS 7.4 and 7.6, UDP and TCP, each allowed DH group and cipher, gateway
  authentication by certificate and by PSK, split and full tunnel. [practices-13]
- **Black-box differential**: run Android's platform IKEv2 client (`Ikev2VpnProfile`) and a packaged strongSwan binary
  configured from its documentation against the same gateway or test responder; compare accept or reject decisions
  and Wireshark traces. Never read their code, and record the method in `PROVENANCE.md`. [practices-13] Note [local]:
  the allowed-sources list in `docs/protocol/fortigate-ipsec.md` does not yet name third-party binaries or their docs;
  add that before using them.
- **Leak checks on a device** (R40): capture on the physical interface through connect, reconnect, network change and
  a forced crash.
- Done means the Activity log shows "Connected" on the real app [local: CLAUDE.md].

### 4.7 Adversarial review

- Every change to a pure core is reviewed against the rule numbers it touches, by someone trying to break them,
  with the fuzz and matrix results attached.
- Map rules to OWASP MASVS: NETWORK-1, CRYPTO-1/2, STORAGE-1/2, CODE-3, CODE-4. NETWORK-2 covers only endpoints
  "under the developer's control", so user-confirmed pinning goes beyond it. [practices-14]
- Before a Play release: ADA MASA AL2 lab review (about 32 lab hours, $3,000 to $6,000, valid one year; AL1 does not
  earn the badge), plus a separate protocol-focused review with the fuzzing report, since MASA tests a subset of MASVS
  Level 1 and not IKE correctness. Play's VpnService policy requires encrypting data to the tunnel endpoint and a
  declaration form. [practices-14] https://appdefensealliance.dev/masa ·
  https://support.google.com/googleplay/android-developer/answer/12564964?hl=en

### 4.8 Dependency scanning and builds

OSV-Scanner, Gradle lockfiles and verification metadata, Dependabot through dependency submission (R46).
Reproducible builds are a later tier: F-Droid lists embedded build paths (Flutter among others) and timestamps as the
most common breakers, and apksigner from build-tools 35.0.0-rc1 outputs APKs apksigcopier cannot verify (pin
build-tools 34). [practices-15] https://f-droid.org/docs/Reproducible_Builds/

### 4.9 What runs where

| When | What | Needs |
|---|---|---|
| Every push (CI) | `ktlintCheck`, app `testDebugUnitTest`, engine JUnit 5 suite (KATs, state matrix, hostile responder, property tests with a logged seed, Jazzer regression corpus), grep and lint rules (secret compares, secret logging, `allowBypass`), Gradle dependency verification, OSV-Scanner, `flutter analyze` and `flutter test` | JVM runner only; minutes |
| Nightly (cron) | Jazzer fuzz mode, one target per job, rotating; longer property runs; new crashes become corpus files | CI minutes |
| Before each release build | Instrumented KATs on the device, interop matrix on the AWS FortiGate, leak captures, review of changed cores | Phone, AWS instance hours |
| Before a Play release | MASA AL2, protocol review, VpnService declaration | Lab budget |

---

## 5. Residual risks we cannot remove, and what the app tells people

Copy below is a draft in English only, with no dashes; the app needs it in both `app_en.arb` and `app_es.arb`
[local: CLAUDE.md]. The IT sheet is the existing copyable details sheet [local: `lib/ui/home/widgets/connected_details.dart`].

### 5.1 Group PSK plus MSCHAPv2

- **Why it stays.** In PSK mode the gateway proves only that it knows a key every user holds. Anyone with that key can
  pose as the gateway, pass R1, and receive the MSCHAPv2 response, which cracks to a password-equivalent NT hash.
  Separately, anyone who can reach the gateway can brute-force a weak PSK offline from its message 4 (no client can
  prevent this). [protocol_attacks-1, protocol_attacks-2, protocol_attacks-3, impl_cves-14]
- **What we do.** Show the method at first confirmation, require acknowledgement, treat a switch from certificate to
  PSK as an attack (R5), accept PSKs of at least 64 octets in hex or ASCII (RFC 7296 §2.15) [protocol_attacks-2],
  never log the PSK.
- **User sees (draft):** "This gateway proves who it is with a key shared by everyone who uses it. Someone with that
  key could pose as the gateway and try to learn your password. Ask your IT team to switch it to a certificate."
- **IT sheet:** "Gateway authentication: shared key. Recommended: certificate (authmethod signature). If a shared key
  stays, use a random key of 32 bytes or more."

### 5.2 MSCHAPv2 even with a certificate

- **Why it stays.** The real gateway, or a compromised one, receives the NT-Response and can crack it offline. EAP-TTLS
  with PAP would hand a compromised gateway the plaintext password instead [inference], so it does not help against
  this attacker. FortiOS has at least 15 (20 counting multi-product) KEV entries. [practices-1, protocol_attacks-3]
- **What we do.** Nothing client-side beyond R1 to R8. The user's password protects only as well as the gateway is
  patched.
- **IT sheet:** a static line that FortiOS IKE fixes exist (for example CVE-2024-46670 fixed in 7.2.10, 7.4.5, 7.6.1).
  The app cannot see the FortiOS version and must not guess it from Vendor IDs [impl_cves-13].

### 5.3 Identity sent before the gateway is authenticated

- **Why it stays.** IKEv2 puts our IDi in message 3, before the responder's AUTH arrives. R1 holds back the EAP
  identity, but whoever answered IKE_SA_INIT sees IDi [inference from protocol_attacks-2]. Keep IDi free of anything
  the user did not choose to share (open question for the spike).

### 5.4 Gateway crashes and restarts

- **Why it stays.** FortiOS IKE DoS bugs (CVE-2024-46670 unauthenticated; CVE-2024-46669 IKEv1, authenticated) drop the
  tunnel for reasons outside our code. [impl_cves-13]
- **What we do.** Calm reconnect (R35), existing drop alerts [local: `vpn/DropAlerts.kt`].

### 5.5 Gateways with outdated crypto

- **Why it stays.** A gateway configured only for 3DES, SHA-1 with group 2 or 5, or NULL cannot be served under R21.
  That is an availability loss we choose on purpose. [impl_cves-10]
- **User sees (draft):** "This gateway only offers outdated encryption, so Blanarch will not connect. Ask your IT team
  to update the VPN settings." (Fits the existing "say plainly when a gateway can't be served" flow [local: `sslvpn/SslVpnProber.kt`,
  `setup_view_model.dart`].)
- **IT sheet:** proposals offered by the app and the one the gateway chose.

### 5.6 Android's own leaks

- **Why it stays.** Android sends connectivity checks outside any VPN on every Wi-Fi join, even with "Block connections
  without VPN", and no app can stop it. DNS through `getaddrinfo` can leak briefly while the tunnel reconfigures or
  the app is killed. Android's TunnelVision immunity depends on its DHCP client, not on VPN design; LocalNet still
  matters in split tunnels. [protocol_attacks-10, protocol_attacks-11, protocol_attacks-12]
- **What we do.** R40 and R41 shrink the window; they cannot close it.
- **User sees (help text, draft):** "When you join a Wi-Fi network, Android checks the connection outside the VPN. No
  VPN app can prevent this."

### 5.7 Secrets in memory

- **Why it stays.** JVM zeroization is best effort (R44). A memory dump on a rooted or unlocked phone can reveal keys
  or the password. Recorded as accepted residual risk, not as solved. App lock and Keystore storage limit the stolen,
  locked phone case [local: CLAUDE.md]. [practices-10]

### 5.8 TCP transport denial of service

- **Why it stays.** RST spoofing, Length injection and UDP blocking can degrade or break a TCP tunnel. They cannot read
  or forge tunnel data. [protocol_attacks-8]
- **What we do.** R39 keeps the IKE SA across drops.

### 5.9 A new engine and its tools

- **Why it stays.** New code carries most vulnerabilities whatever the language; our fuzzer's steward is being wound
  up; Bouncy Castle has had DoS CVEs in each of the last two years. [practices-3, practices-11]
- **What we do.** Section 4, R45 to R47, and an external review before wide release. Nothing to tell users; say it
  plainly in the release notes for IT pilots if the engine ships before a review [inference].

---

## 6. What this plan assumes, and how it bears on the approach choice

### 6.1 Assumptions inside this plan

| # | Assumption | If it is wrong |
|---|---|---|
| S1 | The FortiGate puts its AUTH in the first IKE_AUTH response (seen in Fortinet's own debug output [protocol_attacks-2]) | If a gateway uses EAP-only, R2 refuses it and those users cannot connect |
| S2 | EAP-MSCHAPv2 is the method | If a gateway requires EAP-TTLS, we need TLS inside EAP (keying export from API 31 [local: android_feasibility.md §0]) and R8's tunnel rule becomes live |
| S3 | Gateways offer at least one allowlisted suite | Otherwise R21 blocks them (5.5) |
| S4 | IKE_AUTH fits without fragmentation on mobile | Otherwise R37's strict reassembler becomes mandatory work and attack surface |
| S5 | Protocol code stays pure | Otherwise sections 4.2 to 4.5 need devices or Robolectric and slow down |
| S6 | Jazzer stays usable | Otherwise fuzzing stops improving; targets still run as regression tests (R47) |
| S7 | Android keeps per-UID routing and still lacks DHCP option 121 | Otherwise leak defences need revisiting (5.6) |

### 6.2 Who owns these rules under each engine approach [inference]

| Approach | Who owns R1 to R47 | Main security assumption | If wrong |
|---|---|---|---|
| Own Kotlin engine (this plan) | We own all of them | We fund section 4 as part of the engine, not after it | We reproduce the documented classes in section 2, in new code at the top of the vulnerability curve |
| Android platform IKEv2 (`Ikev2VpnProfile`) | Android owns R1 to R41 (protocol and routing); we keep R42 to R47 | The platform authenticates the gateway before EAP and handles EAP-Success correctly; we can only check that black-box (4.6) | We cannot patch it, only wait for Android updates; and per local notes it has no API for an interactive code or EAP-TTLS [local: android_feasibility.md §6] |
| Embedded native IKE library | The library owns R1 to R39; we keep R40 to R47 | Upstream fixes arrive promptly and we ship them (MASVS CODE-3) | Memory-corruption classes return (most section 2 examples are C daemons); licence and clean-room fit must be checked first [local: CLAUDE.md clean-room rule] |

### 6.3 Decisions in this plan that are hard to undo

| Decision | Undo cost | Why |
|---|---|---|
| Pin format for IKE (DER leaf certificate, as SSL-VPN does today, or SPKI hash) | **High** | Changing it later forces every user to re-confirm every gateway [inference] |
| Policy for PSK plus MSCHAPv2 (allow with acknowledgement, or refuse) | Medium | Loosening later is easy; tightening later cuts off users already connecting |
| Crypto allowlist (R21) | Low if we start strict | Adding a suite later is easy; removing one breaks gateways |
| Fragmentation (R37) | Low to defer, then permanent | Once shipped, the reassembler is attack surface we must keep |
| Pure engine module with JUnit 5 (4.1) | Low | A module split now; easy to keep or fold back |
| How the password crosses Pigeon (String or bytes, R44) | Medium | Changing Pigeon types later touches Dart and Kotlin together and needs regeneration [local: CLAUDE.md] |
| Fuzzer choice | Low | Targets are plain `ByteArray` functions (R47) |
