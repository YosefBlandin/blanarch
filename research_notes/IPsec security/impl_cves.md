# Implementation CVEs in IKEv1 / IKEv2 / IPsec / EAP (2015 to 2026), and what they mean for Blanarch

Date: 2026-09-28. Target: a Kotlin IKEv2 + EAP-MSCHAPv2 + userspace ESP client (Android `VpnService`) talking to a
FortiGate dial-up gateway.

**Clean-room statement.** Built only from CVE records (NVD API 2.0 JSON, `services.nvd.nist.gov`), vendor advisory prose
(strongswan.org blog, libreswan.org advisories, Cisco PSIRT, FortiGuard PSIRT, TheGreenBow, Arista, Zyxel via NVD),
the oss-security mailing list, IETF RFC text (rfc-editor.org), a USENIX Security paper page, weakdh.org (CCS 2015), a
Microsoft security advisory and Android developer docs. No source code of strongSwan, libreswan, Openswan, racoon, iked,
Linux xfrm, Android's IKE module, openfortivpn, OpenConnect, FortiClient or WireGuard was opened. Commit/patch links
that NVD lists as references (GitHub, kernel.org, cvsweb) were **not** opened. Two third-party write-ups (Rapid7 on
CVE-2023-28771, Exodus Intelligence on CVE-2016-1287) analyse closed vendor firmware and include some decompiled
fragments; only their prose was used and nothing from them is reproduced here.

**Method.** `cveId=` lookups for known CVEs, then `keywordSearch=` sweeps on NVD ("strongSwan", "IKEv2 client",
"IKEv2 fragmentation", "anti-replay IPsec", "FortiOS IKE", "FortiClient IPsec", "MSCHAPv2", "IKE amplification",
secret-in-log phrases, Android IKE class names). Descriptions below are paraphrased from NVD unless marked as a quote.

**Legend.** Relevance to Blanarch: **H** = the same code path exists in our client, **M** = analogous path or it shapes
a design choice, **L** = server-side or IKEv1-only, kept for the pattern.

---

## 0. The short version (what to carry into the spec)

1. **Authenticate the gateway before any EAP byte leaves the phone.** strongSwan's own Android client sent the EAP
   identity and the MSCHAPv2 response to a server that had a valid certificate for a *different* host
   (CVE-2015-4171). Captured MSCHAPv2 is offline-crackable (Microsoft advisory 2743314). Our pin check must run on the
   first IKE_AUTH response, before we answer the EAP-Identity request.
2. **An EAP-Success is not proof of anything.** strongSwan clients accepted an early EAP-Success with no MSK and
   finished the IKE SA (CVE-2021-45079). The client must require a completed MSCHAPv2 exchange (valid server
   authenticator response), derive the MSK, and verify the gateway's final AUTH with it.
3. **Client-side EAP-MSCHAPv2 parsing is an attack surface of its own.** CVE-2025-62291: a crafted 6 to 8 byte
   Failure Request underflowed a length in strongSwan's *client* plugin and could overflow the heap.
4. **Every length field is hostile, and IKE clients crash too.** Cisco Secure Client (CVE-2024-20474) and Cisco IOS in
   the IKEv2 initiator role (CVE-2016-6423) were crashed by crafted IKEv2 packets. Kotlin removes memory corruption but
   not crashes, hangs or huge allocations: every parse error must become a typed `VpnException`, not an uncaught
   `IndexOutOfBoundsException` that kills the tunnel service.
5. **Fragment reassembly is a classic hole.** Cisco ASA RCE (CVE-2016-1287), Cisco IOS heap overflow/underflow
   (CVE-2024-20307/20308), libreswan off-by-one (CVE-2026-12413), racoon quadratic reassembly (CVE-2016-10396).
   Follow RFC 7383 exactly: check each fragment's ICV before storing it, bound count and bytes.
6. **Gate every exchange type by state.** A Child SA usable before AUTH (strongSwan CVE-2026-78135, and the initiator
   variant CVE-2014-2338), a bogus INFORMATIONAL where IKE_AUTH was expected (libreswan CVE-2019-12312), and
   INFORMATIONAL/DELETE processed without checking the ICV (libreswan CVE-2019-10155) all come from loose dispatch.
7. **Signature checks: use the platform verifier, strict encodings, no "soft fail".** Lax PKCS#1 v1.5 parsing
   (strongSwan CVE-2018-16151/16152), malformed ECDSA accepted by a VPN client that also ships on Android
   (TheGreenBow CVE-2024-45750), wrong key-match logic (OpenIKED CVE-2020-16088), OCSP failure treated as success
   (TheGreenBow CVE-2025-11955).
8. **Validate KE payloads and the chosen proposal.** Zero DH value (libreswan CVE-2015-3240), oversized DH value
   (strongSwan CVE-2023-41913, unauthenticated RCE), unexpected group number (strongSwan CVE-2014-9221), unexpected
   AES-GMAC transform (libreswan CVE-2024-3652). Accept only transforms we offered; RFC 8247 makes ENCR_NULL and DES
   MUST NOT for IKE.
9. **ESP: verify the ICV before touching the replay window, and drop duplicates.** RFC 4303 §3.4.3 is explicit; Arista
   (CVE-2025-2796) forwarded duplicates, Cisco (CVE-2020-3220) under-verified ESP authenticity.
10. **Logs are a leak and a code path.** FortiClient for Mac put the VPN password in the system log stream
    (CVE-2022-33878). Zyxel's IKE error-logging path executed attacker data as a shell command (CVE-2023-28771, on the
    CISA KEV list). libreswan crashed while building a "packet dropped" log line (CVE-2020-1763).

---

## 1. Catalogue: 20 core CVEs grouped by class

### Class A: EAP inside IKEv2, ordering of authentication

**1. CVE-2015-4171, strongSwan 4.3.0 to 5.3.1 and strongSwan VPN Client (Android) before 1.4.6, 2015. Server identity
enforced too late, client leaks EAP/PSK credentials.** Relevance **H**.
- NVD: "when using EAP or pre-shared keys for authenticating an IKEv2 connection, does not enforce server
  authentication restrictions until the entire authentication process is complete, which allows remote servers to
  obtain credentials by using a valid certificate and then reading the responses."
- The oss-security report shows the Android client logging a successful signature check for one hostname, then
  sending its EAP identity and running MSCHAPv2 with the rogue server; the hostname constraint only failed afterwards,
  giving the attacker material for an offline dictionary attack. The attacker needed DNS spoofing plus any certificate
  from a trusted CA.
- Sources: https://nvd.nist.gov/vuln/detail/CVE-2015-4171 · https://www.openwall.com/lists/oss-security/2015/05/29/6
- Lesson: identity/pin check of the responder (IDr + certificate or PSK AUTH) must pass **before** the first
  EAP-Response. RFC 7296 §2.16: EAP methods "MUST be used in conjunction with a public-key-signature-based
  authentication of the responder to the initiator" (https://www.rfc-editor.org/rfc/rfc7296#section-2.16).

**2. CVE-2021-45079, strongSwan 4.1.2 to 5.9.4, 2022. Early EAP-Success accepted by the client.** Relevance **H**.
- NVD: "a malicious responder can send an EAP-Success message too early without actually authenticating the client
  and (in the case of EAP methods with mutual authentication and EAP-only authentication for IKEv2) even without
  server authentication."
- Vendor: the client ignored a failed `get_msk()` and completed IKE authentication anyway; with EAP-only (RFC 5998)
  configurations the server was never authenticated, so a rogue server could read tunnelled traffic "or may even
  allow it to access hosts behind the client". Configurations that require a server certificate were safe.
- Sources: https://nvd.nist.gov/vuln/detail/CVE-2021-45079 ·
  https://www.strongswan.org/blog/2022/01/24/strongswan-vulnerability-%28cve-2021-45079%29.html
- Lesson: RFC 7296 §2.16: for key-generating EAP methods the MSK "MUST be used by both the initiator and responder to
  generate AUTH payloads in messages 7 and 8". Treat a missing MSK, or an EAP-Success before the MSCHAPv2 Success
  Request has been verified, as a hard failure.

**3. CVE-2015-8023, strongSwan eap-mschapv2 (server side) 4.2.12 to 5.3.3, 2015. MSCHAPv2 state not validated.**
Relevance **M** (we are the peer, but the same state-machine shape exists on our side).
- NVD: "does not properly validate local state, which allows remote attackers to bypass authentication via an empty
  Success message in response to an initial Challenge message."
- Source: https://nvd.nist.gov/vuln/detail/CVE-2015-8023
- Lesson: MSCHAPv2 opcodes (Challenge, Response, Success, Failure) must be accepted only in the one state where they
  are legal; an empty or out-of-order Success must fail the method.

### Class B: EAP method parsing

**4. CVE-2025-62291, strongSwan eap-mschapv2 plugin (client side) before 6.0.3, published 2025-10 / NVD 2026-01.
Integer underflow on a short Failure Request, heap overflow.** Relevance **H** (this is exactly our method and role).
- NVD: "a malicious EAP-MSCHAPv2 server can send a crafted message of size 6 through 8, and cause an integer underflow
  that potentially results in a heap-based buffer overflow."
- Vendor: the minimum-length check for the 3-character error code compared against the whole packet size instead of
  the payload; impact is a crash or, depending on compiler options, potential RCE. It is reached after the client has
  authenticated the server with a certificate, so the attacker must be (or have compromised) a trusted gateway.
- Sources: https://nvd.nist.gov/vuln/detail/CVE-2025-62291 ·
  https://www.strongswan.org/blog/2025/10/27/strongswan-vulnerability-%28cve-2025-62291%29.html
- Lesson: in the MSCHAPv2 parser, compute every sub-length relative to the right base (EAP header vs MSCHAPv2 header
  vs message text), reject before subtracting, and treat the Failure text (`E=… R=… C=… V=… M=…`) as untrusted input.

**5. CVE-2026-47895, strongSwan before 6.0.7, 2026. Empty-but-non-NULL EAP-Identity cloned wrongly, double free.**
Relevance **M**.
- NVD: "Parsed EAP-Identities that result in an empty but non-NULL encoding are not correctly cloned and trigger a
  double-free once the duplicates are destroyed."
- Source: https://nvd.nist.gov/vuln/detail/CVE-2026-47895
- Lesson: zero-length values are a distinct test case for every variable-length field (identity, nonce, notify data,
  MSCHAPv2 name). Related: CVE-2026-25075 (strongSwan EAP-TTLS AVP length underflow, server side,
  https://www.strongswan.org/blog/2026/03/23/strongswan-vulnerability-(cve-2026-25075).html).

### Class C: IKE message parsing (length fields, integer under/overflow, out-of-bounds reads)

**6. CVE-2024-20474, Cisco Secure Client (AnyConnect) before 5.1.4.74, 2024. Integer underflow in IKEv2 processing
crashes the client.** Relevance **H** (client role, unauthenticated attacker).
- NVD/Cisco: "due to an integer underflow condition. An attacker could exploit this vulnerability by sending a crafted
  IKEv2 packet"; the result is a crash of the client software. Cisco lists no workaround.
- Sources: https://nvd.nist.gov/vuln/detail/CVE-2024-20474 ·
  https://sec.cloudapps.cisco.com/security/center/content/CiscoSecurityAdvisory/cisco-sa-csc-dos-XvPhM3bj

**7. CVE-2016-6423, Cisco IOS 15.5(3)M and IOS XE, 2016. IKEv2 client/initiator reloaded by crafted packets from a
server.** Relevance **H** (proves the initiator's parser is attacked by the responder).
- NVD: "The IKEv2 client and initiator implementations … allow remote IKEv2 servers to cause a denial of service
  (device reload) via crafted IKEv2 packets."
- Sources: https://nvd.nist.gov/vuln/detail/CVE-2016-6423 ·
  http://tools.cisco.com/security/center/content/CiscoSecurityAdvisory/cisco-sa-20161005-ios-ikev

**8. CVE-2023-23009, libreswan 3.28 to 4.9, 2023. Traffic Selector payload with a wrong selector length.** Relevance
**H** (we parse TSr from the gateway).
- NVD: DoS "via crafted TS payload with an incorrect selector length."
- Sources: https://nvd.nist.gov/vuln/detail/CVE-2023-23009 · https://www.debian.org/security/2023/dsa-5368
- Lesson: a TS's Selector Length must equal 16 (IPv4) or 40 (IPv6) for its TS type and must fit the payload; the
  payload's TS count must match what is actually present.

**9. CVE-2024-46670 (FG-IR-24-266), FortiOS 7.2.0 to 7.2.9, 7.4.0 to 7.4.4, 7.6.0, 2025. Out-of-bounds read in the
FortiGate IKE service, unauthenticated DoS.** Relevance **M** (this is our peer; it shows the gateway can die under
us). Companion: CVE-2024-46669 (FG-IR-24-267), integer overflow in the same service lets an *authenticated* peer crash
the tunnel.
- FortiGuard: "may allow an unauthenticated remote attacker to trigger memory consumption leading to Denial of Service
  via crafted requests." Fixed in 7.2.10, 7.4.5, 7.6.1.
- Sources: https://nvd.nist.gov/vuln/detail/CVE-2024-46670 · https://fortiguard.fortinet.com/psirt/FG-IR-24-266 ·
  https://nvd.nist.gov/vuln/detail/CVE-2024-46669
- Lesson: the reconnect path must handle a gateway that restarts its IKE daemon (lost SAs, INVALID_SPI, silence).

**10. CVE-2016-6415 "BENIGNCERTAIN", Cisco IOS / IOS XE / IOS XR / PIX, 2016. IKEv1 response leaks device memory.**
Relevance **L** (IKEv1 server), kept as the canonical over-read disclosure.
- NVD: "allows remote attackers to obtain sensitive information from device memory via a Security Association (SA)
  negotiation request".
- Source: https://nvd.nist.gov/vuln/detail/CVE-2016-6415

### Class D: fragmentation reassembly

**11. CVE-2016-1287, Cisco ASA, 2016. IKEv1/IKEv2 fragment reassembly length underflow, unauthenticated RCE.**
Relevance **H** if we implement RFC 7383.
- NVD: buffer overflow in the IKEv1 and IKEv2 implementations that "allows remote attackers to execute arbitrary code
  … via crafted UDP packets."
- Exodus Intelligence (finder): the reassembly code checked a maximum fragment length but no minimum, so a fragment
  shorter than its own header underflowed the copy length; reachable pre-authentication.
- Sources: https://nvd.nist.gov/vuln/detail/CVE-2016-1287 ·
  http://tools.cisco.com/security/center/content/CiscoSecurityAdvisory/cisco-sa-20160210-asa-ike ·
  https://blog.exodusintel.com/2016/02/10/firewall-hacking/

**12. CVE-2024-20307 / CVE-2024-20308, Cisco IOS and IOS XE, 2024. IKEv1 fragmentation heap overflow and heap
underflow, unauthenticated DoS.** Relevance **M** (IKEv1, same bug class nine years later).
- NVD: "crafted, fragmented IKEv1 packets are not properly reassembled."
- Sources: https://nvd.nist.gov/vuln/detail/CVE-2024-20307 · https://nvd.nist.gov/vuln/detail/CVE-2024-20308 ·
  https://sec.cloudapps.cisco.com/security/center/content/CiscoSecurityAdvisory/cisco-sa-ikev1-NO2ccFWz

**13. CVE-2026-12413, libreswan, 2026. IKEv2 fragment with unknown outer payloads, off-by-one, daemon abort.**
Relevance **H** if we implement RFC 7383.
- NVD: reassembly "would ignore unknown outer payloads but still store these in a fixed size array"; an off-by-one in
  the bound assertion aborts the daemon. Any IKEv2 configuration not setting `fragmentation=no` was exposed.
- Sources: https://nvd.nist.gov/vuln/detail/CVE-2026-12413 · https://libreswan.org/security/CVE-2026-12413/
- Lesson for all of class D: RFC 7383 §2.6 requires checking Fragment Number and Total Fragments, then verifying each
  fragment's ICV and silently discarding failures, **before** storing it; §5 asks for a cap on buffered fragment bytes
  (https://www.rfc-editor.org/rfc/rfc7383). Fragments only ever carry an Encrypted Fragment payload (§2.2).

### Class E: state-machine confusion

**14. CVE-2026-78135, strongSwan 5.9.7 to 6.0.7, 2026. CREATE_CHILD_SA handled while EAP is still in progress, Child SA
before authentication.** Relevance **M** (responder bug; the initiator-side twin is CVE-2014-2338).
- NVD: "mishandles behavioral workflow in the IKEv2 state machine. Because CREATE_CHILD_SA requests are mishandled,
  there can be an authentication bypass."
- Vendor: a state check only ran "while no passive exchanges are currently in progress", and during EAP several tasks
  sit in that queue, so an unauthenticated peer could get a usable Child SA; only EAP configurations were affected.
  The advisory names CVE-2014-2338 as the earlier, initiator-side variant (NVD: "bypass authentication by rekeying an
  IKE_SA during (1) initiation or (2) re-authentication, which triggers the IKE_SA state to be set to established").
- Sources: https://nvd.nist.gov/vuln/detail/CVE-2026-78135 ·
  https://www.strongswan.org/blog/2026/09/07/strongswan-vulnerability-(cve-2026-78135).html ·
  https://nvd.nist.gov/vuln/detail/CVE-2014-2338
- Related: CVE-2026-78133, strongSwan 6.0.0 to 6.0.7, use-after-free in IKEv2 rekey-collision handling
  (https://nvd.nist.gov/vuln/detail/CVE-2026-78133).

**15. CVE-2019-12312, libreswan 3.27, 2019. Bogus INFORMATIONAL instead of IKE_AUTH, NULL dereference.** Relevance
**M**.
- NVD: triggered "by initiating an IKEv2 IKE_SA_INIT exchange, followed by a bogus INFORMATIONAL exchange instead of
  the normally expected IKE_AUTH exchange."
- Source: https://nvd.nist.gov/vuln/detail/CVE-2019-12312
- Related: CVE-2022-23094 (libreswan 4.2 to 4.5, crafted IKEv1 packet where the code "wrongly expects that a state
  object exists", https://nvd.nist.gov/vuln/detail/CVE-2022-23094).

### Class F: unauthenticated or unverified INFORMATIONAL / DELETE handling

**16. CVE-2019-10155, libreswan before 3.29, 2019. IKEv1 INFORMATIONAL (DPD, Delete, Notify) processed without
verifying the ICV.** Relevance **M**.
- NVD: packets "are encrypted and integrity protected … but as a receiver, the integrity check value was not verified."
  The vendor rated it not practically exploitable because the attacker lacks the key, but the check was simply absent.
- Sources: https://nvd.nist.gov/vuln/detail/CVE-2019-10155 ·
  https://libreswan.org/security/CVE-2019-10155/CVE-2019-10155.txt
- Lesson: RFC 7296 §2.4: "an endpoint MUST NOT conclude that the other endpoint has failed based on … IKE messages that
  arrive without cryptographic protection (e.g., Notify messages complaining about unknown SPIs)". Act on DELETE,
  INITIAL_CONTACT or AUTHENTICATION_FAILED only inside a verified SK payload; unprotected INVALID_SPI is a hint that
  may trigger a rate-limited liveness check, never a teardown.

### Class G: signature and certificate verification

**17. CVE-2018-16151 / CVE-2018-16152, strongSwan gmp plugin before 5.7.0, 2018. Lax PKCS#1 v1.5 parsing, forgeable
RSA signatures with small exponents.** Relevance **M** (only if we hand-parse signatures).
- NVD: the verifier "does not reject excess data after the encoded algorithm OID" (16151) and "does not reject excess
  data in the digestAlgorithm.parameters field" (16152); "a remote attacker can forge signatures when small public
  exponents are being used, which could lead to impersonation when only an RSA signature is used for IKEv2
  authentication." A variant of CVE-2006-4790 / CVE-2014-1568 (Bleichenbacher 2006 style).
- Sources: https://nvd.nist.gov/vuln/detail/CVE-2018-16151 · https://nvd.nist.gov/vuln/detail/CVE-2018-16152 ·
  https://www.strongswan.org/blog/2018/09/24/strongswan-vulnerability-(cve-2018-16151,-cve-2018-16152).html
- Related parser crashes on crafted certificates/signatures in the same library: CVE-2017-9022, CVE-2017-9023,
  CVE-2017-11185, CVE-2018-6459, CVE-2018-17540, CVE-2021-41990 (all at https://nvd.nist.gov/vuln/detail/<id>).

**18. CVE-2024-45750, TheGreenBow VPN Client (Windows, Linux, macOS and Android 6.4.5 and older), 2024. Malformed
ECDSA signatures accepted in IKEv2 AUTH.** Relevance **H** (a commercial Android IKEv2 client, same role as ours).
- Vendor: "During the IKEv2 Authentication phase, the VPN client accepts malformed ECDSA signatures and establishes the
  tunnel." Android fixed in 6.4.6.
- Sources: https://nvd.nist.gov/vuln/detail/CVE-2024-45750 · https://www.thegreenbow.com/en/support/security-alerts/
- Related from the same vendor: CVE-2025-11955, the OCSP-enabled client "establishes the tunnel even if it does not
  receive an OCSP response or if the OCSP response signature is invalid" (https://nvd.nist.gov/vuln/detail/CVE-2025-11955).

**19. CVE-2020-16088, OpenIKED (OpenBSD through 6.7), 2020. Wrong public-key match logic, authentication bypass.**
Relevance **M** (our pin comparison is the same kind of small, critical function).
- NVD: "allows authentication bypass because ca.c has the wrong logic for checking whether a public key matches."
- Sources: https://nvd.nist.gov/vuln/detail/CVE-2020-16088 · https://www.openiked.org/security.html

### Class H: weak or invalid crypto parameters

**20. CVE-2023-41913 (strongSwan charon-tkm, before 5.9.12, 2023) and CVE-2015-3240 (libreswan before 3.15 / Openswan
before 2.6.45, 2015). KE payload not validated: oversized DH value overflows a buffer (unauthenticated RCE); zero
g^x crashes the daemon.** Relevance **H** (we parse KEr from IKE_SA_INIT, before any authentication).
- NVD (41913): "buffer overflow and possible unauthenticated remote code execution via a DH public value that exceeds
  the internal buffer … An attack can occur via a crafted IKE_SA_INIT message."
- NVD (3240): DoS "via a zero DH g^x value in a KE payload".
- Related: CVE-2014-9221 (strongSwan, published 2015-01, KE with DH group 1025 caused an invalid pointer dereference),
  CVE-2024-3652 (libreswan IKEv1: a peer proposing AES-GMAC crashed the default proposal handler).
- Sources: https://nvd.nist.gov/vuln/detail/CVE-2023-41913 ·
  https://www.strongswan.org/blog/2023/11/20/strongswan-vulnerability-%28cve-2023-41913%29.html ·
  https://nvd.nist.gov/vuln/detail/CVE-2015-3240 · https://nvd.nist.gov/vuln/detail/CVE-2014-9221 ·
  https://libreswan.org/security/CVE-2024-3652
- Lesson: KE Diffie-Hellman Group Num must equal the group we sent; KE data length must equal the group's exact size;
  MODP values must lie in [2, p-2] and ECP points must be on the curve (RFC 6989,
  https://www.rfc-editor.org/rfc/rfc6989). The responder's SA must contain exactly one transform per type, each one we
  offered.

---

## 2. Supporting CVEs by class (checked in NVD, one line each)

| Class | CVE | Product, year | One line |
|---|---|---|---|
| ESP integrity / replay | CVE-2025-2796 | Arista EOS (HW IPsec), 2025 | Duplicate ESP packets forwarded although anti-replay was configured. https://nvd.nist.gov/vuln/detail/CVE-2025-2796 |
| ESP integrity / replay | CVE-2020-3220 | Cisco IOS XE HW crypto driver, 2020 | "insufficient verification of authenticity of received ESP packets"; on-path attacker tears down sessions. https://nvd.nist.gov/vuln/detail/CVE-2020-3220 |
| ESP integrity / replay | CVE-2017-7184 | Linux xfrm, 2017 | Replay-state size not validated on XFRM_MSG_NEWAE, heap OOB, local root (Pwn2Own). https://nvd.nist.gov/vuln/detail/CVE-2017-7184 |
| ESP integrity / replay | CVE-2026-23440 | Linux mlx5e IPsec offload, 2026 | Race during ESN update in full offload mode. https://nvd.nist.gov/vuln/detail/CVE-2026-23440 |
| ESP data plane | CVE-2022-27666 | Linux esp4/esp6, 2022 | Heap overflow in ESP transformation, local privilege escalation. https://nvd.nist.gov/vuln/detail/CVE-2022-27666 |
| Weak cipher | CVE-2016-2183 | 3DES/DES in TLS, SSH, IPsec, 2016 | SWEET32 birthday attack on 64-bit block ciphers in long sessions. https://nvd.nist.gov/vuln/detail/CVE-2016-2183 |
| Protocol / key reuse | CVE-2018-5389 | IKEv1 PSK main mode (CERT VU#857035), 2018 | Offline dictionary attack on main-mode PSK; key reuse across IKE versions enables cross-protocol bypass. https://www.kb.cert.org/vuls/id/857035 |
| Protocol / key reuse | CVE-2018-0131 | Cisco IOS IKEv1 RSA-encrypted nonces, 2018 | Bleichenbacher oracle on decryption failures. https://nvd.nist.gov/vuln/detail/CVE-2018-0131 |
| Amplification | CVE-2016-5361 | libreswan IKEv1, 2016 | Retransmitting in initial-responder states gives traffic amplification via spoofed UDP. https://nvd.nist.gov/vuln/detail/CVE-2016-5361 |
| Computational DoS | CVE-2016-10396 | racoon (ipsec-tools 0.8.2), 2017 | Worst-case complexity in ISAKMP fragment reassembly check. https://nvd.nist.gov/vuln/detail/CVE-2016-10396 |
| Parsing / assert | CVE-2023-38710 | libreswan 3.20 to 4.11, 2023 | Invalid protocol ID (0/1) in Child SA REKEY echoed into INVALID_SPI notify, assert crash. https://libreswan.org/security/CVE-2023-38710/ |
| Parsing | CVE-2023-38711 | libreswan 4.6 to 4.11, 2023 | IKEv1 IDcr of an unexpected ID type, NULL dereference. https://libreswan.org/security/CVE-2023-38711/ |
| Parsing | CVE-2015-4047 | racoon, 2015 | Series of crafted UDP requests, NULL dereference in gssapi.c. https://nvd.nist.gov/vuln/detail/CVE-2015-4047 |
| Logging path | CVE-2020-1763 | libreswan 3.27 to 3.31, 2020 | Crash while building the log line for a dropped INFORMATIONAL packet with no state. https://libreswan.org/security/CVE-2020-1763/CVE-2020-1763.txt |
| Logging path | CVE-2023-28771 | Zyxel ZyWALL/USG/ATP/VPN, 2023 | IKEv2 Notify (NO_PROPOSAL_CHOSEN) data reached a shell-built debug-log command; unauthenticated RCE, CISA KEV. https://nvd.nist.gov/vuln/detail/CVE-2023-28771 · https://www.rapid7.com/blog/post/ra-cve-2023-28771-analysis/ |
| Secret in logs | CVE-2022-33878 | FortiClient for Mac 7.0.0 to 7.0.5, 2022 | SSL-VPN password readable in cleartext via a log stream of FortiTray. https://nvd.nist.gov/vuln/detail/CVE-2022-33878 |
| Fingerprinting | CVE-2017-3130 | FortiOS 5.4.4 / 5.6.0 and below, 2017 | IKE Vendor ID payloads disclose the FortiOS version. https://nvd.nist.gov/vuln/detail/CVE-2017-3130 |
| EAP (Wi-Fi, same pattern) | CVE-2023-52160 | wpa_supplicant PEAP, 2024 | Client skips Phase 2 on an early EAP-TLV Success when server cert is not verified. https://nvd.nist.gov/vuln/detail/CVE-2023-52160 |
| EAP identity binding | CVE-2022-4967 | strongSwan 5.9.2 to 5.9.5, 2024 | Claimed IKE/EAP identity not bound to the TLS client certificate. https://nvd.nist.gov/vuln/detail/CVE-2022-4967 |
| Cert fetch DoS | CVE-2022-40617 | strongSwan before 5.9.8, 2022 | Peer certificate's CRL/OCSP URL points to a stalling server, revocation plugin DoS. https://nvd.nist.gov/vuln/detail/CVE-2022-40617 |
| Origin validation | CVE-2023-46715 | FortiOS IPsec 7.2.6 and below, 7.4.0 to 7.4.1, 2025 | Authenticated dial-up user can send packets spoofing another user's tunnel IP. https://nvd.nist.gov/vuln/detail/CVE-2023-46715 |

---

## 3. Protocol-level weaknesses that frame the EAP-MSCHAPv2 choice (not implementation bugs)

- **MSCHAPv2 is crackable once captured.** Microsoft advisory 2743314: an attacker who can "intercept the victim's
  MS-CHAP v2 handshake" can "decrypt a user's credentials"; Microsoft's fix is to wrap it in an authenticated tunnel
  (PEAP) or use IKEv2 with EAP-MSCHAPv2. Inside IKEv2 that tunnel is only as good as our responder authentication.
  https://learn.microsoft.com/en-us/security-updates/securityadvisories/2012/2743314
- **RFC 5998 (EAP-only responder authentication) requires methods that are mutual, key-generating and "resistant to
  dictionary attacks"** (§4); its list of safe methods does not include EAP-MSCHAPv2. So Blanarch must never accept
  EAP-only (no responder AUTH before EAP) with MSCHAPv2. https://www.rfc-editor.org/rfc/rfc5998#section-4
- **Felsch, Grothe, Schwenk, Czubak, Szymanek (USENIX Security 2018), "The Dangers of Key Reuse: Practical Attacks on
  IPsec IKE"**: Bleichenbacher oracles in IKEv1 RSA-encrypted-nonce mode (Cisco CVE-2018-0131, Huawei CVE-2017-17305,
  Clavister CVE-2018-8753, ZyXEL CVE-2018-9129) break IKEv1 and IKEv2 signature authentication when the same RSA key is
  reused, plus an offline dictionary attack on PSK modes. Relevance: if the FortiGate authenticates itself with a
  group PSK during EAP, every holder of that PSK can impersonate the gateway and harvest MSCHAPv2 responses.
  https://www.usenix.org/conference/usenixsecurity18/presentation/felsch
- **Logjam (Adrian et al., CCS 2015, "Imperfect Forward Secrecy: How Diffie-Hellman Fails in Practice")**: 66.1% of
  IKEv1 VPN servers in IPv4 space would be exposed if the most common 1024-bit group were broken; advice is 2048-bit
  or larger. RFC 8247 now says Group 2 SHOULD NOT, Group 1 MUST NOT, Group 14 MUST. https://weakdh.org/ ·
  https://www.rfc-editor.org/rfc/rfc8247
- **Algorithm floor** (RFC 8247 for IKEv2): ENCR_DES and ENCR_NULL MUST NOT, PRF_HMAC_MD5 and AUTH_HMAC_MD5_96 MUST NOT,
  SHA-1 for signatures MUST NOT. For ESP (RFC 8221 §4) "Encryption without authentication is not effective and MUST
  NOT be used". https://www.rfc-editor.org/rfc/rfc8221
- **ESP anti-replay** (RFC 4303 §3.4.3): minimum window 32, default 64; "The receive window is updated only if the
  integrity verification succeeds." https://www.rfc-editor.org/rfc/rfc4303#section-3.4.3

---

## 4. Mitigation checklist for the Blanarch engine (derived from the classes above)

1. **Ordering gate (A):** after IKE_AUTH response #1, verify IDr, the responder AUTH (signature against the pinned
   certificate, or PSK AUTH) and the pin, then answer EAP-Identity. Refuse to continue if the responder sent no AUTH
   (EAP-only) while the method is MSCHAPv2.
2. **EAP completion gate (A):** accept EAP-Success only after we sent the MSCHAPv2 Success response ack for a server
   authenticator response we verified (RFC 2759 `S=` value); derive the MSK; compute our final AUTH with it and verify
   the gateway's final AUTH with it. Any mismatch or missing MSK is `ErrorCode` failure, never "continue".
3. **Pure, bounded parsers (B, C, D):** keep all IKE/EAP/ESP decoding in I/O-free Kotlin (as the architecture rules
   already require) over a read-only cursor that checks `remaining >= n` before every read, validates each length
   against its own container, rejects zero where the RFC gives a minimum, and caps total allocations. Map every parse
   failure to a typed `VpnException`, never let a runtime exception escape to the service.
4. **Fuzz those parsers:** Jazzer on the JVM (OSS-Fuzz documents JVM projects:
   https://google.github.io/oss-fuzz/getting-started/new-project-guide/jvm-lang/), seeded with our own captured
   traces, with the CVEs above as regression cases (short MSCHAPv2 Failure, TS with bad selector length, KE with wrong
   length/zero value, fragment with Total=0 or Number>Total, empty identity).
5. **Fragmentation (D):** either ship without RFC 7383 at first (if the FortiGate's IKE_AUTH fits the path MTU on test
   networks), or implement it strictly: ICV per fragment before buffering, consistent Total Fragments, cap count and
   bytes, drop the whole set on inconsistency, timeout.
6. **Explicit state machine (E, F):** a sealed state type with a table of allowed (exchange type, flags, message ID)
   per state; install ESP keys only after both AUTHs verify; act on DELETE / notifies only inside a verified SK
   payload; rate-limit reactions to unprotected messages (RFC 7296 §2.4).
7. **Crypto verification (G, H):** use platform JCA `Signature.verify` (no hand-rolled PKCS#1 or DER), require strict
   DER for ECDSA, check the RFC 7427 AlgorithmIdentifier matches the key, pin compare in constant time over the whole
   SPKI hash; never soft-fail revocation or pin checks; do not fetch CRL/OCSP URLs taken from peer certificates.
8. **Proposal and KE checks (H):** propose only an allowlist (AES-GCM or AES-CBC+HMAC-SHA2, DH 14/19/20/21/31); the
   response must pick exactly one of ours per transform type; KE group and length must match exactly; validate the
   value range / curve point.
9. **ESP receive path (I):** SPI match, then window pre-check, then ICV (constant time), then window update, then
   decrypt/deliver; 64-bit window or larger; rekey before sequence wrap.
10. **Logging (K):** never log passwords, MSCHAPv2 NT-Response or Challenge, MSK, SKEYSEED, SK_*, nonces or ESP keys;
    log constants plus error codes; wrap secrets in types whose `toString()` redacts; strip verbose `Log` calls in
    release with R8. Android docs: "Don't log sensitive data. Only log compile-time constants whenever possible."
    https://developer.android.com/privacy-and-security/risks/log-info-disclosure. Make the logging code itself
    null-safe (CVE-2020-1763) and never pass peer data to a shell (CVE-2023-28771).
11. **Robustness against the gateway (C, J):** FortiOS's own IKE service has had unauthenticated crash bugs
    (CVE-2024-46670); reconnect with backoff, and do not answer unsolicited IKE requests (we are only an initiator).
12. **Fingerprinting (L):** we do not need to parse Fortinet Vendor IDs for security decisions; ignore unknown ones.

---

## 5. Gaps and caveats

- **Android's own IKE module:** NVD keyword sweeps for its class names (IkeSessionStateMachine, EapMsChapV2, IpSecService)
  returned nothing. No public CVE for it was found this way; absence in a keyword search is not proof there are none
  (Android bulletin entries often name only the component).
- **Windows IKEEXT (CVE-2022-34721 and others) and the Windows TCP/IP ESP bug CVE-2022-34718:** NVD carries titles
  only, and the third-party write-up could not be fetched, so they are not catalogued.
- **Fortinet FortiGuard pages** return HTTP 500 to plain `curl`; FG-IR-24-266 was read through a browser-like fetcher.
  FG-IR-24-267 and FG-IR-22-246 details come from NVD text only.
- Several 2026 strongSwan CVEs (CVE-2026-78123 to CVE-2026-78135, released with 6.1.0 on 2026-09-07) are two weeks
  old; only CVE-2026-78135's advisory was read in full.
