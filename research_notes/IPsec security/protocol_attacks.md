# Documented protocol attacks relevant to Blanarch's IKEv2 client

Research notes, 2026-09-28. Defensive threat model for our own client. Scope: an Android (VpnService) IKEv2
**initiator** that authenticates the user with **EAP-MSCHAPv2** (possibly EAP-TTLS/PAP later), talking to a
**FortiGate** that authenticates itself with either a **group PSK** (Fortinet's default dial-up migration design)
or a **certificate**, carrying **ESP** with AES-GCM or AES-CBC + HMAC, over UDP 500/4500 (NAT-T) or **TCP 443**
(RFC 9329 framing).

Purpose: know which documented weaknesses touch our design so we build the defenses in from the start. Each entry is
what it is, what has to be true for it to apply, what it would cost us, and what our client does about it.

## Provenance and rules followed

- Sources: peer-reviewed papers (USENIX Security, IEEE S&P, CCS, NDSS, WOOT), IETF RFCs (rfc-editor.org), NIST CSRC,
  CVE records (cve.org / MITRE CVE API prose), vendor advisory prose (Microsoft, Fortinet PSIRT via CVE text, the
  strongSwan advisory page for CVE-2021-45079 read only for its prose description), researcher disclosure pages
  (Leviathan, TunnelCrack, Mullvad, ROBOT), Android developer docs, OSS-Fuzz docs.
- **No IPsec/VPN implementation source code or code repository was opened, searched or quoted** (strongSwan,
  libreswan, Openswan, racoon, iked, Linux xfrm, Android IKE module, openfortivpn, OpenConnect, FortiClient,
  WireGuard). Where a CVE names an internal function or file, that detail is deliberately left out.
- Fortinet facts reused from `../FortiGate IPsec spec/fortinet_dialup_ikev2.md` keep their original Fortinet URLs.
- Labels: **[Doc]** = stated in the cited source. **[Derived]** = my reasoning from cited RFC text, not stated
  verbatim anywhere. **[TRACE]** = confirm with a live trace against the real gateway. **[TEST]** = confirm on a device.

---

## 0. The short version (ranked for our client)

| # | Weakness | Applies when | What it would cost us | Our defense |
|---|---|---|---|---|
| 1 | Rogue gateway accepted because the group PSK is shared | PSK mode, PSK known to attacker, attacker on path | User credentials exposed to an impostor; full MITM | Prefer + pin a **certificate** gateway; mark PSK mode weaker; advise IT |
| 2 | Offline dictionary recovery of a weak group PSK (Felsch 2018) | PSK mode, low-entropy PSK | Enables #1 with no victim needed | Treat PSK as public; ask IT for a random 32+ byte PSK |
| 3 | MS-CHAPv2 reduces to one DES key (Marlinspike/Hulton 2012) | The MSCHAPv2 exchange is visible to the attacker | Password-equivalent NT hash, ~100%, under a day | Never run MSCHAPv2 unless the responder was authenticated by a non-shared secret |
| 4 | Early EAP-Success / missing MSK-AUTH check (CVE-2021-45079 class) | Client accepts Success before the method completes | Tunnel to an unauthenticated gateway | Accept Success only after a verified Authenticator Response; always verify MSK-based AUTH |
| 5 | EAP method bid-down to a cleartext method | Client answers whatever method is asked | Cleartext password to whoever holds the PSK | One fixed EAP method per profile; NAK others, abort |
| 6 | AES-GCM IV reuse (Joux forbidden attack) | Our sender ever repeats an 8-byte IV under one key | Auth key H recovered; forgeries into the tunnel | Atomic per-SA counter, rekey before wrap, never reuse KEYMAT |
| 7 | Proposal / DH downgrade via unauthenticated errors | Active attacker; client accepts weak groups | Weak DH (Logjam-class) or weaker suite | Offer only strong groups; re-propose full list; no NULL transforms |
| 8 | TCP-encapsulation DoS (RFC 9329) | On-path attacker, TCP 443 transport | Repeated drops, slow reconnects | Keep IKE SA across TCP drops; re-open with IKETCP prefix; fuzz the framer |
| 9 | LocalNet leak (TunnelCrack, USENIX 2023) | Hostile Wi-Fi; client excludes local routes, or split tunnel overlaps LAN | Plaintext leak of selected traffic | Do not exclude local routes by default; warn on split/LAN overlap |
| 10 | Android DNS / connectivity-check leaks | No DNS set, or reconfig; captive-portal checks | DNS / HTTP(S) outside the tunnel | Always set DNS; hold TUN during reconnect; document lockdown caveat |
| - | TunnelVision (CVE-2024-3661) | OS supports DHCP option 121 | Route-injection leak | **Android not affected** (no option 121); keep not calling `allowBypass()` |
| - | ServerIP leak (TunnelCrack) | OS routes server-IP traffic outside tunnel | Leak via DNS-spoofed server IP | VpnService apps use per-UID routing; not affected (built-in legacy VPN <A12 was) |

The through-line: **the group-PSK design is the root risk.** It makes MSCHAPv2 crackable in practice (3), enables the
rogue gateway (1), and is itself guessable (2). The single most valuable thing our client can do is support and prefer
a **certificate-authenticated, fingerprint-pinned** gateway, and treat PSK mode as a clearly-labelled fallback.

---

## 1. Offline dictionary attack on the group PSK (Felsch et al., USENIX Security 2018)

**What it is.** Felsch, Grothe, Schwenk, Czubak, Szymanek, "The Dangers of Key Reuse: Practical Attacks on IPsec IKE".
Alongside the Bleichenbacher results (section 8), the paper shows every PSK variant of IKE is open to an offline
dictionary attack: "IKEv1 PSK in aggressive mode can be broken by a passive adversary, and both IKEv1 PSK in main
mode and IKEv2 PSK can be broken by an active adversary who acts as a responder." [Doc]
https://www.usenix.org/conference/usenixsecurity18/presentation/felsch ·
https://www.usenix.org/system/files/conference/usenixsecurity18/sec18-felsch.pdf (sections 4.5, 9, 11)

- The active adversary completes a DH with the target and obtains a value computed from public data, the DH secret
  and the PSK; "Since the attackers know all of these values except the PSK, they can now perform an offline
  dictionary attack." [Doc] (PDF 4.5, 9.1). Their only fix: "choosing a cryptographically strong PSK that resists
  dictionary attacks." [Doc] (9.1)
- On EAP the paper adds that EAP-MD5 / EAP-MSCHAPv2 "do not prevent offline dictionary attacks, they just require
  the attackers to shift from IKE to attacking EAP." [Doc] (9.2)
- RFC 7296 says the same in prose: a PSK from "a password, name, or other low-entropy source is not secure," and it
  should "contain as much randomness as the strongest key being negotiated." [Doc]
  https://www.rfc-editor.org/rfc/rfc7296 (2.15, 5)

**Relevance / why it is sharper in Fortinet's PSK+EAP mode. [Derived]** In EAP mode the initiator omits its AUTH and
the **responder** proves the PSK first, in message 4, as `AUTH = prf(prf(PSK,"Key Pad for IKEv2"), ResponderSignedOctets)`
(RFC 7296 2.15/2.16). Anyone who merely *initiates* to the gateway knows their own DH secret and can decrypt that
message, so they hold every input except the PSK. The dictionary attack therefore needs **no victim and no on-path
position** against a PSK gateway; the message-4 content (IDr + AUTH method 2 + EAP-Request/Identity, no CERT) is
Fortinet-published. https://docs.fortinet.com/document/forticlient/7.4.5/ems-quickstart-guide/745658/troubleshooting-ipsec-vpn-ikev2-with-saml-authentication
`[TRACE]` whether our gateway replies that far to an unknown initiator.

**Preconditions.** PSK mode; a guessable PSK. **Impact.** Recovery of the PSK, which unlocks section 2. Even a strong
PSK is shared by every user and stored in every FortiClient config, so we assume it is public regardless.

**Mitigation for our client.** No client code makes a weak PSK strong. So: accept hex and ASCII PSKs of at least 64
octets (RFC 7296 2.15 MUST); present PSK mode as the weaker choice in the UI; give IT a one-line recommendation
(random PSK 32+ bytes, or certificate mode); never log the PSK.

## 2. Rogue gateway accepted because the PSK is shared by all users

**What it is.** RFC 7296 requires the responder to be authenticated to the initiator by a public key before EAP:
"EAP methods ... MUST be used in conjunction with a public-key-signature-based authentication of the responder to the
initiator" (2.16), and "An implementation using EAP MUST also use a public-key-based authentication of the server to
the client before the EAP authentication begins, even if the EAP method offers mutual authentication. This ... protects
the EAP data from active attackers" (5). [Doc] https://www.rfc-editor.org/rfc/rfc7296

Fortinet's default migration design does not meet that bar: the gateway proves itself with a **shared** PSK, not a
per-server key. "FortiClient authenticates FortiGate using pre-shared key or signature authentication, then proves
ownership ... using EAP-MSCHAPv2 or EAP-TTLS." [Doc]
https://docs.fortinet.com/document/fortigate/8.0.0/administration-guide/913974/eap-user-authentication

**Preconditions.** The attacker possesses the group PSK (any employee, a stolen or leaked FortiClient config, or
recovered per section 1) and can place itself between user and gateway (hostile Wi-Fi, DNS spoofing of the gateway
name, LAN ARP). Because the same secret both sides use is held by everyone, a PSK "gateway authentication" gives the
client no real assurance it is talking to the true gateway.

**Impact.** An impostor that satisfies the client's PSK check becomes the EAP peer for the user's MSCHAPv2 exchange.
Combined with section 3, that yields the user's password-equivalent hash, and thereafter a full man-in-the-middle of
the user's tunnelled traffic. This is the highest-impact item in these notes and the reason the client must offer a
stronger option.

**Mitigation for our client.**
- Support **certificate (signature) gateway authentication** and make it the recommended mode. Per project rule,
  the user confirms the gateway certificate fingerprint on first use and it is then **pinned per host**; a changed
  fingerprint blocks the connection until re-confirmed. This restores the per-server key RFC 7296 5 demands.
- In PSK mode, surface plainly that gateway identity is only as good as a secret every user shares, and that MSCHAPv2
  over PSK is weak. Consider requiring an explicit acknowledgement for PSK + MSCHAPv2 profiles.
- Report failures as `VpnException(ErrorCode)`, never by matching gateway text, so a rogue cannot steer our logic with
  crafted strings.
- Note for IT: FortiClient's own Android path (built-in client) requires `authmethod signature` with an RSA server
  cert, i.e. Fortinet itself pushes certificates on Android. [Doc]
  https://docs.fortinet.com/document/forticlient/8.0.0/android-administration-guide/189805/creating-an-ipsec-vpn-ikev2-connection

## 3. MS-CHAPv2 weaknesses (Marlinspike/Hulton 2012; Schneier/Mudge 1999; RFC 2759)

**What it is.** MSCHAPv2's response is built from the MD4/NT hash of the password, split into three DES keys against a
known challenge. The 1999 analysis (Schneier, Mudge, "Cryptanalysis of Microsoft's PPTP Authentication Extensions
(MS-CHAPv2)") found the security core reduces to the NT hash and DES. [Doc]
https://www.schneier.com/academic/archives/1999/09/cryptanalysis_of_mic_1.html
In 2012 Marlinspike and Hulton ("Divide and Conquer: Cracking MS-CHAPv2") reduced a captured handshake to the strength
of "a single DES encryption" (2^56) with a 100% success rate on FPGA hardware in under a day; the recovered NT hash is
"enough to authenticate as them," no plaintext password needed. [Doc]
https://www.theregister.com/2012/07/31/ms_chapv2_crack/ · https://en.wikipedia.org/wiki/MS-CHAP

Microsoft's advisory (2743314, "Unencapsulated MS-CHAP v2 Authentication Could Allow Information Disclosure",
2012-08-20): "An attacker who successfully exploited these cryptographic weaknesses could obtain user credentials,"
after intercepting the handshake via MITM or open wireless; the remedy is to run MSCHAPv2 only inside PEAP or a more
secure tunnel with server authentication. [Doc]
https://learn.microsoft.com/en-us/security-updates/securityadvisories/2012/2743314

- RFC 2759 confirms the construction (`ChallengeResponse`: NT hash zero-padded to 21 octets, three DES operations)
  and offers only "limit the number of password retries" as a mitigation, which does nothing against offline
  cracking of a captured handshake. [Doc] https://www.rfc-editor.org/rfc/rfc2759 (sections 8.5, 10)
- RFC 3079 shows the same NT hash (via PasswordHashHash) also seeds the derived keys, so recovering it compromises
  more than the login. [Doc] https://www.rfc-editor.org/rfc/rfc3079

**Relevance.** MSCHAPv2 is FortiClient's and thus our default EAP method. Its "mutual authentication" is worthless
against a rogue gateway that already holds the group PSK: the impostor is the endpoint the user proves the password
to, so it obtains the crackable handshake directly (section 2). The IKE tunnel is only as protective as the gateway
authentication wrapping it, which in PSK mode is a shared secret.

**Mitigation for our client.**
- The real fix is upstream: only run MSCHAPv2 when the IKE responder was authenticated by a **non-shared** key, i.e.
  a pinned certificate (section 2). Then the MSCHAPv2 exchange is never exposed to an impostor.
- Prefer **EAP-TTLS/PAP** where the backend allows it: the password travels inside a server-authenticated TLS tunnel,
  which is the tunnel-with-server-auth Microsoft's advisory calls for. (FortiClient adds EAP-TTLS on Android in 8.0;
  LDAP backends require it.) https://docs.fortinet.com/document/fortigate/8.0.0/administration-guide/913974/eap-user-authentication
- Verify the MSCHAPv2 **Authenticator Response** from the gateway before treating auth as complete (ties to section 4).
- Never log the password, the NT hash, or the MSCHAPv2 response.

## 4. Early EAP-Success and skipped MSK-AUTH (CVE-2021-45079 class)

**What it is.** A client EAP state machine that concludes on an EAP-Success message arriving too early can finish
"authentication" without the method having run, and can generate the final IKE AUTH payload without a proper MSK.
The CVE-2021-45079 record: "a malicious responder can send an EAP-Success message too early without actually
authenticating the client and (in the case of EAP methods with mutual authentication and EAP-only authentication for
IKEv2) even without server authentication." [Doc] https://nvd.nist.gov/vuln/detail/CVE-2021-45079 ·
prose at https://www.strongswan.org/blog/2022/01/24/strongswan-vulnerability-%28cve-2021-45079%29.html
(read for description only). The advisory's own note is that configurations where the gateway authenticates with a
**certificate first** were not exposed the same way, because the server was already authenticated.

RFC context: EAP Success/Failure "are neither acknowledged nor integrity protected" and "can be spoofable by an
attacker" (RFC 3748 7.16). [Doc] https://www.rfc-editor.org/rfc/rfc3748
RFC 7296 2.16: for key-generating EAP the final AUTH "MUST be used by both the initiator and responder to generate
AUTH payloads ... The shared key from EAP is the field ... named MSK." [Doc] https://www.rfc-editor.org/rfc/rfc7296

**Relevance.** This is a state-machine bug we must not reproduce in our own `LoginProtocol` / EAP handling. It is most
dangerous precisely in EAP-only / PSK gateway mode (our default risk case): an early Success can let the client accept
a tunnel to an unauthenticated peer.

**Mitigation for our client.**
- Treat EAP-Success as advisory, not authoritative: accept it only after the method itself reached success (for
  MSCHAPv2, a verified Authenticator Response; for EAP-TTLS, a completed inner exchange).
- Always require and verify the responder's final AUTH computed over the MSK for key-generating methods; never
  synthesize an AUTH from a missing key. Fail closed with `VpnException(ErrorCode)`.
- Keep this logic in the pure, unit-tested protocol layer and cover the early-Success and no-method cases in tests.

## 5. EAP method downgrade to a cleartext method

**What it is.** EAP negotiation is not integrity-protected before a method secures it: "EAP does not provide
protection for Nak Response packets" and a negotiation attack tries "to negotiate a less secure EAP method"; RFC 3748
advises "there SHOULD be an indication of exactly one method used to authenticate that peer name." [Doc]
https://www.rfc-editor.org/rfc/rfc3748 (7.8). RFC 3748 7.14: cleartext passwords "cannot be securely used within EAP,
except where encapsulated within a protected tunnel with server authentication."

**Relevance. [Derived]** A rogue or on-path responder could request EAP-GTC / a PAP-like inner method / EAP-MD5 hoping
our client answers with the password in a weakly-protected form. Since FortiClient only initiates MSCHAPv2 and
TTLS/PAP, a real gateway will not do this, so an unexpected method request is a red flag.

**Mitigation for our client.** Pin exactly one EAP method per profile (chosen by the user / config). If the gateway
requests any other method, NAK it and abort with `VpnException` rather than adapting. Never send a cleartext password
except inside a completed, server-authenticated EAP-TTLS tunnel.

## 6. AES-GCM nonce/IV reuse: Joux "forbidden attack"

**What it is.** GCM authentication collapses if an IV repeats under one key. Joux, "Authentication Failures in NIST
version of GCM": an adversary "can recover the secret key of the keyed hash function underlying the authentication,
using a chosen IV attack. Once this secret key is known, the encryption mode is no longer authenticated." [Doc]
https://csrc.nist.gov/csrc/media/projects/block-cipher-techniques/documents/bcm/joux_comments.pdf
Demonstrated in the wild for TLS by Bock, Zauner, Devlin, Somorovsky, Jovanovic, "Nonce-Disrespecting Adversaries:
Practical Forgery Attacks on GCM in TLS" (WOOT 2016): repeated nonces "fully break the authenticity of the
connections." [Doc] https://www.usenix.org/conference/woot16/workshop-program/presentation/bock

RFC 4106 (AES-GCM for ESP): "The most important security consideration is that the IV never repeat for a given key";
the 8-octet IV "MUST NOT repeat"; peers "MUST ensure that the two peers assign different salt values"; generate a
fresh key before 2^64 blocks. [Doc] https://www.rfc-editor.org/rfc/rfc4106 (3.1, 10). Also "Clearly, smaller ICV
values are more likely to be subject to forgery attacks. Implementations SHOULD use as large a size as reasonable" —
so use the 16-octet ICV, not 8. [Doc] (same, 10)

**Relevance.** We are the ESP **sender** for outbound packets; an IV-generation bug (non-atomic counter under
concurrent send, reuse of the counter after a service restart or SA resume without new keys, or reusing KEYMAT across
SAs) would hand an on-path attacker forgery into our own tunnel. Fortinet's IKEv2 defaults include AES-GCM.

**Mitigation for our client.**
- One monotonic 64-bit counter per outbound ESP SA, incremented atomically per packet; distinct salt per SA from the
  IKE KEYMAT (never a fixed or shared salt).
- Rekey (new Child SA) well before the counter could wrap or before 2^64 blocks; never resume an SA with old keys and
  a reset counter.
- Prefer the 16-octet ICV. Keep GCM to IKE-established keys only (never manual keying, per RFC 8221 section 3).
- Keep the counter and the codec in the pure `FrameCodec` layer and unit-test the wrap/rekey boundary.

## 7. Proposal and DH-group downgrade; weak DH (Logjam, RFC 8247)

**What it is.** IKE_SA_INIT and its error notifies are unauthenticated, so an active attacker can try to force a weaker
suite or group. RFC 7296 warns that after an INVALID_KE_PAYLOAD "The initiator MUST again propose its full set of
acceptable cryptographic suites because the rejection message was unauthenticated and otherwise an active attacker
could trick the endpoints into negotiating a weaker suite than a stronger one that they both prefer." [Doc]
https://www.rfc-editor.org/rfc/rfc7296 (2.7 area). It also forbids NULL/NONE for the IKE SA: implementations "MUST NOT
negotiate NONE as the IKE integrity protection algorithm or ENCR_NULL as the IKE encryption algorithm." [Doc] (5)

Weak DH groups are the payoff: Adrian et al., "Imperfect Forward Secrecy: How Diffie-Hellman Fails in Practice"
(Logjam, CCS 2015) estimate that breaking one common 1024-bit prime would passively expose "66% of VPN servers"; they
recommend 2048-bit groups and ECDHE. [Doc] https://weakdh.org/
RFC 8247 codifies this: MODP-2048 (group 14) MUST, ECP-256 (group 19) SHOULD, group 5/2 SHOULD NOT, group 1 and group
22 MUST NOT. [Doc] https://www.rfc-editor.org/rfc/rfc8247 (2.4)

**Relevance.** Fortinet's IKEv2 defaults use group 14, with FortiClient examples using 19/20/21. We choose what we
offer, so we control our own floor.

**Mitigation for our client.**
- Offer only strong groups (14, 19, 20, 21; MODP-2048+ or ECP-256+). Refuse group 1/2/5/22, and refuse NULL/NONE
  transforms for the IKE SA.
- On INVALID_KE_PAYLOAD, retry with the corrected group but **re-send the full proposal list** (RFC 7296).
- Validate peer DH public values before use: MODP range `1 < r < p-1`, and for ECP that the point satisfies the curve
  equation (RFC 6989 2.1, 2.3). We use ephemeral DH per exchange (PFS), so we are not in the key-reuse danger case,
  but the range/curve checks are cheap sanity checks and we do them anyway. [Doc]
  https://www.rfc-editor.org/rfc/rfc6989

## 8. Bleichenbacher / RSA key-reuse (Felsch 2018; ROBOT 2018)

**What it is.** The other half of Felsch et al.: Bleichenbacher oracles in IKEv1's RSA-encrypted-nonce modes let an
attacker decrypt nonces and forge signatures, breaking the signature-authenticated handshakes of **both IKEv1 and
IKEv2** when a device reuses its RSA key across modes. Affected: Cisco (CVE-2018-0131), Huawei (CVE-2017-17305),
Clavister (CVE-2018-8753), ZyXEL (CVE-2018-9129). The attacker must finish within the responder's IKE timeout
(e.g. Cisco IKEv2 forged-signature window ~240 s). [Doc]
https://nvd.nist.gov/vuln/detail/CVE-2018-0131 · https://nvd.nist.gov/vuln/detail/CVE-2017-17305 ·
https://nvd.nist.gov/vuln/detail/CVE-2018-8753 · https://nvd.nist.gov/vuln/detail/CVE-2018-9129 ·
https://www.usenix.org/system/files/conference/usenixsecurity18/sec18-felsch.pdf (sections 4, 11)
Authors' countermeasures: use only high-entropy PSKs and **disable PKE/RPKE modes on all devices**. [Doc] (11)

The same RSA PKCS#1 v1.5 padding-oracle family (ROBOT, USENIX 2018) hit Fortinet's TLS features:
FortiOS SSL Deep Inspection (CVE-2018-9192) and VIP SSL (CVE-2018-9194) allowed "plaintext recovery ... or a
Man-in-the-middle (MiTM) attack on RSA PKCS #1 v1.5 encryption ... without knowledge of the server's private key."
[Doc] https://robotattack.org/ · CVE prose via https://cveawg.mitre.org/api/cve/CVE-2018-9192

**Relevance.** These are mostly **responder/server** and **IKEv1** bugs, and we are an **IKEv2 initiator** that will
not implement RSA-encrypted-nonce modes at all, so we are not directly vulnerable. They matter to us as design
guardrails and as evidence the gateway vendor has shipped RSA-oracle bugs. If we ever verify a gateway RSA signature,
the signature-verification code must reject trailing/extra data after the PKCS#1 v1.5 structure (the class behind
CVE-2018-16151, an IKEv2 signature-forgery-on-verify bug) and prefer RSASSA-PSS / ECDSA / EdDSA where the gateway
offers them. [Doc] https://nvd.nist.gov/vuln/detail/CVE-2018-16151

**Mitigation for our client.** Implement only IKEv2; never RSA-encrypted-nonce modes. Use a vetted crypto provider for
RSA verification; do not hand-roll PKCS#1 parsing. Keep the DH ephemeral (PFS) so a future gateway key compromise does
not retroactively decrypt captured sessions.

## 9. EAP identity privacy

**What it is.** The initiator identifies (and usually authenticates) itself first, and a rogue responder can probe for
that identity: RFC 7296 5 notes the responder "or someone impersonating the responder ... can probe the initiator for
its identity," and with EAP "the responder proves its identity before the initiator does, so an initiator that knew the
name of a valid initiator could probe the responder." [Doc] https://www.rfc-editor.org/rfc/rfc7296 (5)
The EAP-Response/Identity can differ from the method-authenticated identity, which is how privacy (an anonymous outer
identity) is achieved (RFC 3748 7.3). [Doc] https://www.rfc-editor.org/rfc/rfc3748

**Relevance. [Derived]** In Fortinet's flow the gateway sends EAP-Request/Identity and the client replies with the
username; the IDi and EAP identity travel inside the IKE-encrypted channel (SK{...}), so they are hidden from a pure
eavesdropper, but a rogue gateway that passed the (shared-PSK) check sees them in clear. So identity exposure collapses
into section 2: fix the gateway authentication and the identity is protected.

**Mitigation for our client.** Rely on the pinned-certificate gateway so identity is only ever revealed to the real
gateway. Where the deployment supports an anonymous outer identity (EAP-TTLS), consider offering it. Do not send the
username in any pre-auth, unencrypted payload. Keep usernames out of logs.

## 10. NAT-T and TCP-encapsulation issues (RFC 3948, RFC 9329)

**What it is.** Over UDP, NAT traversal moves traffic to port 4500 and each peer must recheck NAT-detection payloads;
dynamic address updates "can only be done safely if replay protection is enabled," otherwise an attacker "can revert
the addresses with old replayed packets" or "break the connection with a single packet." [Doc]
https://www.rfc-editor.org/rfc/rfc7296 (2.23). UDP-encap checksum fix-up rules are in RFC 3948. [Doc]
https://www.rfc-editor.org/rfc/rfc3948

Over TCP (RFC 9329, Fortinet's recommended port-443 transport), the security considerations are explicit: TCP adds
SYN-flood and RST-spoofing exposure; a Length-field injection makes the receiver "incorrectly identify the boundaries
of the following packets and ... drop all of them or even tear down the TCP connection"; "An attacker capable of
blocking UDP traffic can force peers to use TCP encapsulation, thus degrading the performance and making the connection
more vulnerable to DoS attacks"; and implementations "SHOULD make sure that IKE session state persists even if the
underlying TCP connection is torn down." Data injection cannot forge application data (ESP integrity holds) but is a
DoS lever. [Doc] https://www.rfc-editor.org/rfc/rfc9329 (section 10, 6.1)

- Every TCP stream "MUST begin with ... the characters 'IKETCP'", sent once by the originator; a new connection for an
  existing SA must resend the prefix. [Doc] (RFC 9329 4, 6.1)
- On TCP, an IKE_SA_INIT error notification should be acted on immediately (unlike UDP), since a response over TCP is
  either genuine or the session was hijacked. [Doc] (RFC 9329 6.4)

**Relevance.** We will implement RFC 9329 TCP-443 transport (SSL VPN tunnel mode is gone from FortiOS 7.6.3+). The
framer that splits the TCP stream into IKE/ESP records is attacker-reachable pre-auth and is exactly the kind of
length-prefixed parser that mishandles adversarial input.

**Mitigation for our client.**
- Keep the IKE SA (and its keys) alive across TCP drops; on a drop, the initiator reopens the TCP connection and
  resends the IKETCP prefix, and we rely on our existing network-aware rejoin. Do not tear down the SA on a bare RST.
- Validate the 16-bit Length against the buffer; treat Length 0/1 and unparseable frames as a corrupt stream, close
  the TCP connection and reconnect rather than looping. Bound resync attempts (RFC 9329 advises limiting resync).
- Prefer UDP first and fall back to TCP only after retransmits (RFC 9329 5.1), so an attacker cannot silently pin us
  to the weaker transport without also blocking UDP.
- Do all this in the pure `FrameCodec` with adversarial unit tests; socket work stays in `cancellableIo`.

## 11. IKEv2 DoS and the cookie mechanism (RFC 7296, RFC 8019, RFC 7383)

**What it is.** "The IKE_SA_INIT and IKE_AUTH exchanges happen before the initiator has been authenticated ... an
implementation ... needs to be completely robust when deployed on any insecure network. Implementation
vulnerabilities, particularly DoS attacks, can be exploited by unauthenticated peers. This issue is particularly
worrisome because of the unlimited number of messages in EAP-based authentication." [Doc]
https://www.rfc-editor.org/rfc/rfc7296 (5). The responder's defenses are the COOKIE (return-routability) challenge
against half-open-SA floods (2.6) and, optionally, client puzzles (RFC 8019). [Doc]
https://www.rfc-editor.org/rfc/rfc8019
IKE fragmentation (RFC 7383) protects each fragment's authenticity, but a flood of incomplete authenticated fragments
can exhaust reassembly memory, so a receiver should cap the reassembly queue. [Doc]
https://www.rfc-editor.org/rfc/rfc7383 (5)

**Relevance.** We are the initiator, so most DoS defense (cookies, puzzles) is the gateway's job, but our client must
**cooperate** and must not itself be DoS-able by a rogue gateway or on-path attacker during the unauthenticated phase.

**Mitigation for our client.**
- Handle a COOKIE notify: retry IKE_SA_INIT including the cookie (and be tolerant of a gateway that rejects and
  reissues after including KEi in its cookie calc, RFC 7296 2.6.1). Support a PUZZLE notify at least to the extent of
  not breaking, ignoring it if we do not implement solving (RFC 8019 allows ignoring). [Doc] rfc8019
- During the unauthenticated phase, do not commit unbounded state: cap IKE fragment reassembly buffers, cap retries,
  time out cleanly, and never let a single crafted pre-auth message crash the engine (fuzz targets, section 13).
- Bound the number of EAP round trips we will follow (RFC 7296 expects at least ~10 for prompts) but not unlimited,
  so a rogue peer cannot keep us in an endless EAP loop.

## 12. Client-side VPN leak attacks and their Android applicability

### 12a. TunnelVision (CVE-2024-3661) — Android not affected
DHCP option 121 (classless static routes) lets a DHCP server on the local network inject more-specific routes that
pull traffic off the tunnel: "VPN-based security solutions that rely on routes to redirect traffic can be forced to
leak traffic over the physical interface." [Doc] https://nvd.nist.gov/vuln/detail/CVE-2024-3661 ·
https://www.leviathansecurity.com/blog/tunnelvision — but "**Android does not implement support for DHCP option 121**"
and is the one tested platform not affected; Windows, Linux, iOS, macOS are affected. [Doc] (same Leviathan page)
**Relevance/mitigation.** Our minSdk-29 Android app is out of scope for TunnelVision. We keep it that way by **not**
calling `allowBypass()` and by routing all families through the tunnel in full-tunnel mode. No action needed beyond
not regressing.

### 12b. TunnelCrack LocalNet and ServerIP (Xue et al., USENIX Security 2023)
"LocalNet": a hostile Wi-Fi claims public IP ranges as local so that traffic to them bypasses the tunnel; "ServerIP":
the OS routes traffic to the VPN server's IP outside the tunnel, and DNS-spoofing the server name turns that into an
arbitrary-traffic leak. [Doc] https://tunnelcrack.mathyvanhoef.com/details.html ·
https://www.usenix.org/system/files/usenixsecurity23-xue.pdf (CVE-2023-36672/36673/36671/35838 are used by the
authors as umbrella IDs for the leak classes). Android fared best: "most VPN apps on Android were not vulnerable (33
out of 42)" to LocalNet, and for ServerIP "on Android only built-in VPNs were vulnerable ... Android 12 and above are
not vulnerable"; the reason is Android's per-UID policy-based routing since 4.4. [Doc] (paper 5.4.1, 5.6.9)
**Preconditions for us.** A VpnService app that routes all non-VPN-app traffic through the tunnel is structurally
protected on ServerIP (our tunnel socket is `protect()`-ed; other apps' traffic always goes to the TUN). LocalNet can
still bite if we **exclude local routes** or run a **split tunnel** whose included corporate subnet overlaps the
hostile Wi-Fi subnet: the paper notes RFC 1918 filtering "is not complete ... in a split-tunnel setting." [Doc] (6.1.2)
**Mitigation for our client.**
- Do not exclude local-network routes by default; in full-tunnel mode route `0.0.0.0/0` and leave IPv6 blocked unless
  explicitly split, so nothing falls through (our existing `allowFamily` handling).
- For split tunnels, warn when a split-include route overlaps the current local network, and only ever exclude
  RFC 1918 ranges from the tunnel, never public ranges.
- Optionally offer "server IP verification": after the tunnel is up, confirm the outer gateway IP over the
  authenticated channel (TunnelCrack 6.2.2). With cert pinning this is largely covered already.

### 12c. Android platform DNS / connectivity-check leaks (Mullvad, 2022 and 2024)
Android sends captive-portal **connectivity checks outside the tunnel** on every Wi-Fi join even with "Block
connections without VPN" on (MUL-22, 2022-10-10): DNS lookups, HTTP(S), possibly NTP leak; it is OS behavior a VPN app
cannot suppress. [Doc] https://mullvad.net/en/blog/android-leaks-connectivity-check-traffic
Separately (2024-05-03), DNS can leak "if a VPN is active without any DNS server configured," or transiently during
tunnel reconfiguration/crashes, on Android up to 14; apps calling `getaddrinfo` directly are affected, `DnsResolver`
users less so; Mullvad's workaround is to set a dummy DNS server in blocking mode. [Doc]
https://mullvad.net/en/blog/dns-traffic-can-leak-outside-the-vpn-tunnel-on-android
**Relevance/mitigation for our client.**
- **Always** add at least one DNS server via `VpnService.Builder.addDnsServer(...)` when we establish the TUN; never
  bring up a tunnel with no DNS set. https://developer.android.com/develop/connectivity/vpn
- Minimize tunnel reconfiguration churn; hold the existing TUN during a reconnect (`establish()` a replacement rather
  than tearing down first) so there is no bare-interface window.
- Document to users that Android's own connectivity checks are outside any app's control (recommend GrapheneOS-style
  toggle / lockdown "Block connections without VPN" but note its limits). This is an OS caveat, not our bug.

## 13. Robustness testing (OSS-Fuzz / Jazzer)

Our IKE/ESP parsers (`FrameCodec`, `TunnelXml`, `Mime`, IKE payload decoders) sit on the pre-auth attack surface.
Jazzer fuzzes JVM bytecode, "so it can be applied to any project written in a JVM-based language" (i.e. our Kotlin),
via `fuzzerTestOneInput(FuzzedDataProvider)`. [Doc]
https://google.github.io/oss-fuzz/getting-started/new-project-guide/jvm-lang/
**Action.** Add fuzz targets for the TCP framer (section 10), IKE payload parsing, EAP/MSCHAPv2 message parsing, and
config-payload/`TunnelXml` parsing; run them in CI. These are pure, I/O-free classes per our architecture rules, so
they are cheap to fuzz.

## 14. Cross-cutting engineering notes for our client

- **Encryption must be authenticated.** ESP encryption without integrity is forbidden: RFC 8221 4, "Encryption
  without authentication is not effective and MUST NOT be used." Use AEAD (AES-GCM-16) or AES-CBC + HMAC-SHA-2, never
  encryption-only ESP (the Degabriele/Paterson 2007 attacks target exactly that). [Doc]
  https://www.rfc-editor.org/rfc/rfc8221 · https://eprint.iacr.org/2007/125
- **Verify integrity before use.** RFC 4303: "integrity checking MUST be completed before the decrypted packet is
  passed on," and enable anti-replay (only meaningful with integrity). For AES-CBC use unpredictable random IVs
  (RFC 3602). [Doc] https://www.rfc-editor.org/rfc/rfc4303 · https://www.rfc-editor.org/rfc/rfc3602
- **IKEv1 is dead.** RFC 9395 deprecates IKEv1; we implement IKEv2 only, which also sidesteps the aggressive-mode PSK
  and RSA-nonce attack families. [Doc] https://www.rfc-editor.org/rfc/rfc9395
- **No text-matching for errors.** Every failure path returns `VpnException(ErrorCode)`; a rogue gateway must not be
  able to drive our control flow with attacker-chosen strings (project rule; reinforces sections 2, 4, 5).

## 15. Open items to confirm against the real gateway

- `[TRACE]` Does our FortiGate reply with message 4 (responder AUTH) to an unknown initiator before any credential?
  (section 1 severity depends on this.)
- `[TRACE]` In PSK + EAP-MSCHAPv2, does the final AUTH (messages 7/8) use the EAP MSK or the PSK? (RFC 7296 says MSK;
  Fortinet behavior not publicly documented — affects section 4 verification logic.)
- `[TRACE]` Confirm the gateway offers a certificate (signature) mode we can pin, and whether ECDSA or only RSA is
  accepted (Fortinet Android docs say RSA only for the built-in client).
- `[TEST]` Verify our ESP GCM IV counter is atomic and never resets on service restart / SA resume (section 6).
- `[TEST]` Verify DNS is always set and no bare-interface window exists across reconnects (section 12c).
