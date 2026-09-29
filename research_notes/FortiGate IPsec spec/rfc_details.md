# IKEv2 + ESP client engine: implementation details from the RFCs

Research date: 2026-09-28. Audience: whoever writes the Kotlin IKEv2/ESP engine (initiator only).

## 0. Clean-room statement and method

- Written only from: IETF RFCs and Internet-Drafts (rfc-editor.org, ietf.org/archive/id, datatracker.ietf.org),
  IANA registries (iana.org), and NIST CSRC (csrc.nist.gov) test-vector files.
- No source code of any VPN or IPsec implementation (strongSwan, libreswan, Openswan, racoon, iked, Linux xfrm,
  Android IKE module, openfortivpn, OpenConnect, FortiClient, WireGuard) and no code repository, README or issue
  was opened. Where a fact exists only in such code, it is marked "not publicly documented".
- RFC 6479 contains example C code; that code is part of the RFC text (IETF Trust, BSD licence) and was read as spec.
- Test vectors below were re-computed locally with small Python scripts written from the RFC pseudocode only
  (hashlib SHA-1/MD4/HMAC, `openssl enc` for DES-ECB and AES-CBC). Every vector marked "verified" matched.
  Values marked "derived" are our own computation, not official.
- Transcription check: every hex string of 16+ digits in this file was searched in the downloaded source texts.
  The only misses were (a) our derived values (MSK candidate, Magic2 key, UTF-16LE of "MyPw") and (b) values the
  sources print as hex dumps with offsets or ASCII columns (RFC 7427 Appendix A/B, RFC 4231 data lines, RFC 7634
  appendices); those were compared by hand.
- Section numbers are given as `RFC nnnn §x.y`.

Documents used (all fetched 2026-09-28):

| Doc | Topic |
|---|---|
| RFC 7296 | IKEv2 (header, payloads, exchanges, key derivation, AUTH, EAP, NAT-T, errors) |
| IANA "IKEv2 Parameters" (updated 2026-07-16) | all current code points |
| RFC 5282 | AEAD (AES-GCM/CCM) in the IKEv2 Encrypted payload |
| RFC 7634 | ChaCha20-Poly1305 for ESP and IKEv2 (+ full test packets) |
| RFC 4303 | ESP |
| RFC 6479 | alternative anti-replay window algorithm |
| RFC 4106 | AES-GCM in ESP |
| RFC 3602 | AES-CBC in ESP (+ ESP test packets) |
| RFC 4868, RFC 2404, RFC 2104, RFC 4231 | HMAC-SHA2 / HMAC-SHA1-96 and test vectors |
| RFC 3948 | UDP encapsulation of ESP, non-ESP marker, NAT keepalive |
| RFC 9329 | TCP encapsulation of IKE and ESP |
| RFC 7383 | IKEv2 message fragmentation (SKF) |
| RFC 3526, RFC 5903, RFC 8031, RFC 7748, RFC 6989 | DH groups 14, 19, 20, 21, 31 and recipient checks |
| RFC 7427, RFC 4754 | signature AUTH (method 14), ECDSA AUTH |
| RFC 5998 | EAP-only authentication (why it does not apply to MSCHAPv2) |
| RFC 8598 | INTERNAL_DNS_DOMAIN (split DNS) |
| RFC 8247, RFC 8221 | algorithm requirement levels for IKEv2 and ESP |
| RFC 3748 | EAP |
| draft-kamath-pppext-eap-mschapv2-02 | EAP-MSCHAPv2 encapsulation |
| RFC 2759 | MS-CHAPv2 computations (+ vectors) |
| RFC 3079 | MPPE key derivation from MS-CHAPv2 (+ vectors) |
| RFC 2548, RFC 3580, RFC 5216, RFC 5422, draft-ietf-emu-rfc7170bis-22 | MSK layout conventions |
| RFC 5281, RFC 9427 | EAP-TTLSv0, EAP-TTLS with TLS 1.3 |
| draft-mcgrew-gcm-test-01 | AES-GCM ESP packet test vectors |
| NIST CAVP gcmtestvectors.zip, NIST CAVP 800-135 ikev2.zip | GCM and IKEv2 KDF vectors |

---

## 1. Code points (IANA "IKEv2 Parameters", RFC 7296 §3)

Exchange types (RFC 7296 §3.1): IKE_SA_INIT 34, IKE_AUTH 35, CREATE_CHILD_SA 36, INFORMATIONAL 37
(also IKE_SESSION_RESUME 38, IKE_INTERMEDIATE 43, IKE_FOLLOWUP_KE 44; 240-255 private).

Payload types (RFC 7296 §3.2, RFC 7383): 0 none, 33 SA, 34 KE, 35 IDi, 36 IDr, 37 CERT, 38 CERTREQ, 39 AUTH,
40 Nonce, 41 Notify, 42 Delete, 43 Vendor ID, 44 TSi, 45 TSr, 46 SK, 47 CP, 48 EAP, 49 GSPM, 53 SKF, 54 PS.
Values 1-32 reserved (IKEv1 overlap). 128-255 private use.

Protocol IDs: 1 IKE, 2 AH, 3 ESP.

Transform types: 1 ENCR, 2 PRF, 3 INTEG, 4 KE (was "D-H"), 5 SN (was "ESN"), 6-12 ADDKE1-7 (RFC 9370).

Transform attribute: 14 Key Length, TV format (only one defined for our purposes).

Type 1 ENCR (the ones that matter): 3 ENCR_3DES, 11 ENCR_NULL (ESP only, not IKE), 12 ENCR_AES_CBC,
13 ENCR_AES_CTR, 14/15/16 ENCR_AES_CCM_8/12/16, 18 ENCR_AES_GCM_8, 19 ENCR_AES_GCM_12, 20 ENCR_AES_GCM_16,
21 ENCR_NULL_AUTH_AES_GMAC (ESP only), 28 ENCR_CHACHA20_POLY1305.

Type 2 PRF: 1 HMAC_MD5 (deprecated), 2 PRF_HMAC_SHA1, 4 PRF_AES128_XCBC, 5 PRF_HMAC_SHA2_256,
6 PRF_HMAC_SHA2_384, 7 PRF_HMAC_SHA2_512, 8 PRF_AES128_CMAC.

Type 3 INTEG: 0 NONE, 1 AUTH_HMAC_MD5_96 (deprecated), 2 AUTH_HMAC_SHA1_96, 5 AUTH_AES_XCBC_96,
8 AUTH_AES_CMAC_96, 12 AUTH_HMAC_SHA2_256_128, 13 AUTH_HMAC_SHA2_384_192, 14 AUTH_HMAC_SHA2_512_256.

Type 4 KE methods: 0 NONE, 2 MODP-1024, 5 MODP-1536, 14 MODP-2048, 15 MODP-3072, 16 MODP-4096,
17 MODP-6144, 18 MODP-8192, 19 ECP-256 (P-256), 20 ECP-384, 21 ECP-521, 31 Curve25519, 32 Curve448,
35/36/37 ML-KEM-512/768/1024 (draft), 1 and 22 deprecated.

Type 5 SN: 0 "32-bit Sequential Numbers" (old name "No ESN"), 1 "Partially Transmitted 64-bit" (old name "ESN").

ID types (RFC 7296 §3.5): 1 ID_IPV4_ADDR, 2 ID_FQDN, 3 ID_RFC822_ADDR, 5 ID_IPV6_ADDR, 9 ID_DER_ASN1_DN,
10 ID_DER_ASN1_GN, 11 ID_KEY_ID, 13 ID_NULL (RFC 7619).

Certificate encodings (RFC 7296 §3.6): 4 X.509 Certificate - Signature (DER), 7 CRL, 12 Hash and URL of X.509
certificate, 13 Hash and URL of X.509 bundle, 14 OCSP Content, 15 Raw Public Key.

Auth methods (RFC 7296 §3.8, IANA): 1 RSA Digital Signature (PKCS#1 v1.5), 2 Shared Key Message Integrity Code,
3 DSS, 9/10/11 ECDSA P-256/SHA-256, P-384/SHA-384, P-521/SHA-512 (RFC 4754), 12 GSPM, 13 NULL,
14 Digital Signature (RFC 7427).

Hash algorithm IDs for SIGNATURE_HASH_ALGORITHMS (RFC 7427): 1 SHA1, 2 SHA2-256, 3 SHA2-384, 4 SHA2-512, 5 Identity.

Notify error types (0-16383; IANA). Unknown error type in a RESPONSE means the request failed entirely
(RFC 7296 §3.10.1):

| Value | Name | Notes |
|---|---|---|
| 1 | UNSUPPORTED_CRITICAL_PAYLOAD | data: 1-octet payload type (§2.5) |
| 4 | INVALID_IKE_SPI | unprotected, outside SA (§2.21.4) |
| 5 | INVALID_MAJOR_VERSION | §2.5 |
| 7 | INVALID_SYNTAX | fatal to IKE SA (§2.21.3) |
| 9 | INVALID_MESSAGE_ID | data: 4-octet MID; only as new INFORMATIONAL request (§2.3) |
| 11 | INVALID_SPI | data: the SPI (§1.5) |
| 14 | NO_PROPOSAL_CHOSEN | §2.7 |
| 17 | INVALID_KE_PAYLOAD | data: 2-octet accepted group, big endian (§1.3) |
| 24 | AUTHENTICATION_FAILED | no data (§2.21.2) |
| 34 | SINGLE_PAIR_REQUIRED | §2.9 |
| 35 | NO_ADDITIONAL_SAS | §1.3 |
| 36 | INTERNAL_ADDRESS_FAILURE | §3.15.4 |
| 37 | FAILED_CP_REQUIRED | §2.19 |
| 38 | TS_UNACCEPTABLE | §2.9 |
| 39 | INVALID_SELECTORS | §3.10.1 |
| 40 | UNACCEPTABLE_ADDRESSES | MOBIKE RFC 4555 |
| 41 | UNEXPECTED_NAT_DETECTED | MOBIKE |
| 43 | TEMPORARY_FAILURE | §2.25 |
| 44 | CHILD_SA_NOT_FOUND | §2.25 |
| 47 | STATE_NOT_FOUND | RFC 9370 |
| 8192-16383 | private use | |

Notify status types (16384-65535) most relevant to a client:
16384 INITIAL_CONTACT, 16385 SET_WINDOW_SIZE, 16386 ADDITIONAL_TS_POSSIBLE, 16387 IPCOMP_SUPPORTED,
16388 NAT_DETECTION_SOURCE_IP, 16389 NAT_DETECTION_DESTINATION_IP, 16390 COOKIE, 16391 USE_TRANSPORT_MODE,
16392 HTTP_CERT_LOOKUP_SUPPORTED, 16393 REKEY_SA, 16394 ESP_TFC_PADDING_NOT_SUPPORTED,
16395 NON_FIRST_FRAGMENTS_ALSO, 16396 MOBIKE_SUPPORTED, 16400 UPDATE_SA_ADDRESSES, 16403 AUTH_LIFETIME,
16404 MULTIPLE_AUTH_SUPPORTED, 16405 ANOTHER_AUTH_FOLLOWS, 16406 REDIRECT_SUPPORTED, 16407 REDIRECT,
16417 EAP_ONLY_AUTHENTICATION, 16418 CHILDLESS_IKEV2_SUPPORTED, 16430 IKEV2_FRAGMENTATION_SUPPORTED,
16431 SIGNATURE_HASH_ALGORITHMS, 16438 INTERMEDIATE_EXCHANGE_SUPPORTED, 16441 ADDITIONAL_KEY_EXCHANGE.
40960-65535 private use (vendor extensions show up here).

CFG types (RFC 7296 §3.15): 1 CFG_REQUEST, 2 CFG_REPLY, 3 CFG_SET, 4 CFG_ACK.

Configuration attributes (RFC 7296 §3.15.1, IANA): 1 INTERNAL_IP4_ADDRESS (0/4), 2 INTERNAL_IP4_NETMASK (0/4),
3 INTERNAL_IP4_DNS (0/4), 4 INTERNAL_IP4_NBNS (0/4), 6 INTERNAL_IP4_DHCP (0/4), 7 APPLICATION_VERSION (0+),
8 INTERNAL_IP6_ADDRESS (0/17), 10 INTERNAL_IP6_DNS (0/16), 12 INTERNAL_IP6_DHCP (0/16),
13 INTERNAL_IP4_SUBNET (0/8), 14 SUPPORTED_ATTRIBUTES (2n), 15 INTERNAL_IP6_SUBNET (17),
18 INTERNAL_IP6_PREFIX (17), 25 INTERNAL_DNS_DOMAIN (0+, RFC 8598), 26 INTERNAL_DNSSEC_TA,
16384-32767 private use.

TS types (RFC 7296 §3.13.1): 7 TS_IPV4_ADDR_RANGE, 8 TS_IPV6_ADDR_RANGE, 10 TS_SECLABEL.

EAP (IANA "EAP registry"): codes 1 Request, 2 Response, 3 Success, 4 Failure (5/6 are ERP, RFC 6696).
Method types: 1 Identity, 2 Notification, 3 Legacy Nak, 4 MD5-Challenge, 5 OTP, 6 GTC, 13 EAP-TLS, 21 EAP-TTLS,
25 PEAP, 26 "MS-EAP-Authentication" (this is the number EAP-MSCHAPv2 uses per draft-kamath: "Type 26"),
29 "EAP-MSCHAP-V2" (a different registration, Cisco), 43 EAP-FAST, 254 Expanded.

---

## 2. IKE header and generic payload header

### 2.1 IKE header, 28 octets (RFC 7296 §3.1)

```
 0                   1                   2                   3
 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                   IKE SA Initiator's SPI (8)                  |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                   IKE SA Responder's SPI (8)                  |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|  Next Payload | MjVer | MnVer | Exchange Type |     Flags     |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                          Message ID                           |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                            Length                             |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
```

- All integers big endian.
- SPIi: 8 octets, MUST NOT be zero. SPIr: zero in the first IKE_SA_INIT request and its retries (also in the
  COOKIE / INVALID_KE / NO_PROPOSAL responses, but "if the responder sends a non-zero responder SPI, the initiator
  should not reject the response for only that reason", §2.6).
- Version octet = 0x20 (major 2, minor 0). Receiver MUST ignore minor version. Major > 2 → drop, SHOULD send
  INVALID_MAJOR_VERSION (§2.5).
- Flags: bits `|X|X|R|V|I|X|X|X|` with bit 0 as MSB, so R (Response) = 0x20, V (Version) = 0x10, I (Initiator) =
  0x08. X bits MUST be 0 on send, ignored on receipt. V MUST be 0 when sending, ignored on receipt.
  I = 1 in every message sent by the ORIGINAL initiator of the IKE SA (changes to whoever did the last IKE rekey).
  R = 1 in every response. Never answer a message that has R=1 (§3.1).
- Message ID: 4 octets (§2.2, see §5 below).
- Length: whole IKE message (header + payloads). Excludes the 4-octet non-ESP marker on UDP/TCP 4500 (§3.1).
- One IKE message per UDP datagram. Payload chain starts from the header's Next Payload; stops at Next Payload 0.
  SK (46) MUST be the last payload and MUST NOT contain another SK (§3.1).
- A message MUST be accepted if payloads come in another order than the figures (§2.5).

### 2.2 Generic payload header, 4 octets (RFC 7296 §3.2)

```
| Next Payload (1) |C|RESERVED(7)| Payload Length (2, includes these 4 octets) |
```

- C (critical) = 0x80 of octet 1. MUST be 0 for all RFC 7296 payload types. If an unknown payload type has C=1 the
  whole message MUST be rejected with UNSUPPORTED_CRITICAL_PAYLOAD (data = 1-octet type); unknown with C=0 is skipped.
  Payloads in responses MUST NOT set C (§2.5).
- For the SK payload, Next Payload = type of the FIRST INNER payload; the last inner payload has Next Payload 0.

---

## 3. Payload formats (initiator needs to build and parse all of these)

### 3.1 SA payload, Proposal, Transform, Attribute (RFC 7296 §3.3, §3.3.1, §3.3.2, §3.3.5, §3.3.6)

SA payload = generic header + one or more Proposal substructures, most preferred first. Payload type 33.

Proposal substructure:
```
| Last Substruc (1) | RESERVED (1) | Proposal Length (2)              |
| Proposal Num (1)  | Protocol ID (1) | SPI Size (1) | Num Transforms (1) |
| SPI (SPI Size octets, no padding) |
| Transforms ... |
```
- Last Substruc: 0 = last proposal, 2 = more follow.
- Proposal Num: first = 1, each next = previous + 1. The response echoes the number of the accepted proposal.
- Protocol ID: 1 IKE, 3 ESP.
- SPI Size: 0 for the IKE SA in IKE_SA_INIT (SPI comes from header); 8 for IKE when rekeying the IKE SA via
  CREATE_CHILD_SA; 4 for ESP.
- ESP SPI in a proposal = the SENDER's SPI, i.e. the SPI the sender wants to see in ESP packets it RECEIVES.
  (Consistent with §1.3.3 REKEY_SA "the SPI the exchange initiator would expect in inbound ESP" and §1.4.1.)
  So the client's SAi2 SPI is its inbound SPI; the gateway's SAr2 SPI is the client's outbound SPI.
- Proposal Length includes all transforms and attributes.

Transform substructure:
```
| Last Substruc (1) | RESERVED (1) | Transform Length (2) |
| Transform Type (1) | RESERVED (1) | Transform ID (2) |
| Transform Attributes ... |
```
- Last Substruc: 0 = last transform, 3 = more follow.
- Several transforms of the same type = OR; different types = AND (§3.3). The responder picks exactly one of each
  type present and returns attributes unmodified (§3.3.6). The initiator MUST check that the reply matches one of
  its proposals, else terminate.
- Transform ID 0 of a type offered as an option means "this transform may be omitted" (§3.3.2).
- Mandatory types: IKE = ENCR, PRF, INTEG (unless AEAD), KE. ESP = ENCR, SN(ESN); optional INTEG (not with AEAD),
  KE (§3.3.3). An initiator that supports ESN usually sends both SN 0 and SN 1; a lone SN 1 means 32-bit is
  unacceptable (§3.3.2).
- AEAD ciphers (GCM, CCM, ChaCha20-Poly1305): no INTEG transform (or a single INTEG NONE; "no integrity algorithm
  being the RECOMMENDED method", §3.3). If an initiator wants AEAD and non-AEAD suites it needs two proposals
  (§2.7, §3.3, RFC 5282 §8).
- IKE_AUTH's SAi2 MUST NOT carry a KE transform other than NONE; SHOULD omit it (§1.2).

Attribute (§3.3.5):
```
|A|  Attribute Type (15)  | AF=0: Attribute Length (2) / AF=1: Attribute Value (2) |
| AF=0: Attribute Value (variable) |
```
- Key Length = type 14, TV form (AF=1): octets `80 0E` + 2-octet key bits. Example AES-256: `80 0E 01 00`.
- Key Length MUST be present for ENCR_AES_CBC, AES_CTR, AES-GCM, AES-CCM (RFC 7296 §3.3.5; RFC 4106 §8.4;
  RFC 5282 §7.3) and MUST NOT be used with fixed-key transforms (all PRF, all INTEG, DES). ChaCha20-Poly1305 has a
  fixed 256-bit key (RFC 7634 §2), so no Key Length.
- To offer several key sizes, repeat the ENCR transform, one attribute each. A transform MUST NOT have two
  attributes of the same type.
- Unknown transform type in a proposal → that proposal is unacceptable; unknown transform ID/attribute → that
  transform is unacceptable (§3.3.6).

Worked example of one IKE proposal (AES-CBC-256, HMAC-SHA2-256-128, PRF-HMAC-SHA2-256, group 19), wire bytes
(our own encoding following §3.3, not an RFC vector):
```
Proposal: 00 00 00 2C  01 01 00 04          (last, len 44, #1, IKE, SPI size 0, 4 transforms)
  T ENCR: 03 00 00 0C  01 00 00 0C  80 0E 01 00
  T PRF : 03 00 00 08  02 00 00 05
  T INTEG:03 00 00 08  03 00 00 0C
  T KE  : 00 00 00 08  04 00 00 13
```

### 3.2 Key Exchange payload (RFC 7296 §3.4)

```
| generic header (type 34) |
| DH Group Num (2) | RESERVED (2) |
| Key Exchange Data |
```
- Group Num MUST match a group proposed in the same message's SA payload and SHOULD equal the first group in the
  first proposal. If no proposal has a group, no KE.
- MODP: public value zero-padded on the left to the modulus length (group 14 → 256 octets).
- ECP 19/20/21: x | y, each padded to 256 / 384 / 528 bits (32 / 48 / 66 octets). NO 0x04 point-format prefix.
  Shared secret g^ir = x coordinate only (RFC 5903 §7). KE payload lengths: 72 / 104 / 140 octets (0x48, 0x68, 0x8C
  in the RFC 5903 §8 vectors).
- Curve25519 (31): 32-octet little-endian u-coordinate from RFC 7748 §6.1; Payload Length = 40. Shared secret =
  X25519(d, peer) 32 octets used directly as g^ir (RFC 8031 §2, §3.1). Receiver MUST mask the MSB of the last
  byte of the peer value and MUST accept non-canonical values (RFC 8031 §3.2). RFC 7748 §6.1: parties MAY check
  that the shared secret is not all-zero (constant-time OR of all bytes).
- If the responder picked a different group (not NONE) the message is rejected with INVALID_KE_PAYLOAD (§3.4).

### 3.3 Nonce payload (RFC 7296 §3.9, §2.10)

Generic header (type 40) + Nonce Data. 16..256 octets. MUST be random, at least 128 bits, and at least half the
key size of the negotiated PRF. The initiator does not know the PRF yet, so pick a length good for all proposed
PRFs (32 octets covers HMAC-SHA2-512's 64-octet key: half = 32). Nonces MUST NOT be reused.

### 3.4 Identification payloads IDi (35) / IDr (36) (RFC 7296 §3.5)

```
| generic header | ID Type (1) | RESERVED (3) | Identification Data |
```
- The AUTH computation uses IDx' = everything after the generic header: `ID Type | RESERVED(3) | data` (§2.15).
- ID_FQDN / ID_RFC822_ADDR: no terminators (no NUL/CR). EAP identities: NAIs with a realm SHOULD use
  ID_RFC822_ADDR; NAIs without realm SHOULD use ID_KEY_ID (§3.5).
- With EAP, IDi may be used only for AAA routing / method selection; the authenticated identity may differ
  (§2.16).
- Optional IDr in message 3 lets the initiator ask for a specific responder identity; the responder may answer with
  a different IDr, and the initiator may then close the SA (§1.2).

### 3.5 Certificate payload CERT (37) and Certificate Request CERTREQ (38) (RFC 7296 §3.6, §3.7)

```
CERT:    | generic header | Cert Encoding (1) | Certificate Data |
CERTREQ: | generic header | Cert Encoding (1) | Certification Authority |
```
- Encoding 4 = one DER X.509 certificate per CERT payload. If a chain is sent, the FIRST CERT holds the key that
  verifies AUTH; others in any order. Implementations MUST be able to accept up to four certificates (§3.6).
- CERTREQ CA field (types 4, 12, 13): concatenation of 20-octet SHA-1 hashes of the SubjectPublicKeyInfo of each
  trusted CA certificate, no other formatting (§3.7). CERTREQ is a hint; if nothing matches it is ignored.
- CERTREQ can appear in the IKE_SA_INIT response and in the IKE_AUTH request.

### 3.6 Authentication payload AUTH (39) (RFC 7296 §3.8; RFC 7427 §3)

```
| generic header | Auth Method (1) | RESERVED (3) | Authentication Data |
```
- Method 1 (RSA): RSASSA-PKCS1-v1_5 over the signed octets (§2.15). "implementations ... SHOULD use SHA-1 as the
  default hash function when generating signatures"; the hash is not signalled in method 1, it is inside the
  PKCS#1 DigestInfo (a verifier recovers it after the RSA public operation).
- Method 2 (Shared Key MIC): prf(prf(secret, "Key Pad for IKEv2"), signed octets) with the negotiated PRF. Used by
  the initiator and by the responder after EAP (messages 7 and 8).
- Methods 9/10/11 (RFC 4754 §7): signature = r | s, each left-padded to 256 / 384 / 528 bits.
- Method 14 (RFC 7427 §3): only allowed if both peers sent SIGNATURE_HASH_ALGORITHMS in IKE_SA_INIT.
  Authentication Data = `ASN.1 Length (1) | AlgorithmIdentifier DER | Signature Value`, no padding between.
  Common AlgorithmIdentifier blobs (RFC 7427 Appendix A, informative, match RFC 5912):
  - sha1WithRSAEncryption, len 15: `30 0d 06 09 2a 86 48 86 f7 0d 01 01 05 05 00`
  - sha256WithRSAEncryption, len 15: `30 0d 06 09 2a 86 48 86 f7 0d 01 01 0b 05 00`
  - sha384WithRSAEncryption, len 15: `30 0d 06 09 2a 86 48 86 f7 0d 01 01 0c 05 00`
  - sha512WithRSAEncryption, len 15: `30 0d 06 09 2a 86 48 86 f7 0d 01 01 0d 05 00`
  - ecdsa-with-sha256, len 12: `30 0a 06 08 2a 86 48 ce 3d 04 03 02`
  - ecdsa-with-sha384, len 12: `30 0a 06 08 2a 86 48 ce 3d 04 03 03`
  - ecdsa-with-sha512, len 12: `30 0a 06 08 2a 86 48 ce 3d 04 03 04`
  - RSASSA-PSS with SHA-256, len 72: `30 46 06 09 2a 86 48 86 f7 0d 01 01 0a 30 39 a0 0f 30 0d 06 09 60 86 48 01 65
    03 04 02 01 05 00 a1 1c 30 1a 06 09 2a 86 48 86 f7 0d 01 01 08 30 0d 06 09 60 86 48 01 65 03 04 02 01 05 00
    a2 03 02 01 20 a3 03 02 01 01`
  - Payload start example (Appendix B.1): `NN 00 00 LL 0e 00 00 00 0f 30 0d 06 09 2a 86 48 86 f7 0d 01 01 05 05 00 ...`
- SIGNATURE_HASH_ALGORITHMS notify (16431): Protocol ID 0, SPI size 0, data = list of 2-octet hash IDs, no padding.
  The signer MUST pick one of the hashes the OTHER side listed (RFC 7427 §4).

### 3.7 Notify payload N (41) (RFC 7296 §3.10)

```
| generic header | Protocol ID (1) | SPI Size (1) | Notify Message Type (2) |
| SPI (SPI Size) | Notification Data |
```
- For notifications about the IKE SA: Protocol ID 0 and SPI Size 0 (erratum 6940 clarifies "the SPI field must be
  empty"). SPI present only for INVALID_SELECTORS, REKEY_SA, CHILD_SA_NOT_FOUND (Protocol ID 3 for ESP, SPI size 4).
- Error types 0-16383: unknown error in a response → the request failed; unknown error in a request and unknown
  status types → ignore (log).

### 3.8 Delete payload D (42) (RFC 7296 §3.11)

```
| generic header | Protocol ID (1) | SPI Size (1) | Num of SPIs (2) | SPIs |
```
- Delete IKE SA: Protocol ID 1, SPI Size 0, Num 0.
- Delete ESP SA: Protocol ID 3, SPI Size 4, SPIs = the sender's INBOUND SPIs. One protocol per Delete payload.

### 3.9 Vendor ID payload V (43) (RFC 7296 §3.12)

Generic header + opaque VID. Critical bit MUST be 0. Unknown VIDs MUST be ignored. May appear in any message.

### 3.10 Traffic Selector payloads TSi (44) / TSr (45) (RFC 7296 §3.13, §3.13.1)

```
TS payload: | generic header | Number of TSs (1) | RESERVED (3) | Traffic Selectors ... |
Selector:   | TS Type (1) | IP Protocol ID (1) | Selector Length (2) |
            | Start Port (2) | End Port (2) |
            | Starting Address | Ending Address |
```
- Type 7: 4-octet addresses, Selector Length 16. Type 8: 16-octet addresses, Selector Length 40.
- IP Protocol 0 = any. Ports: "ANY" = 0..65535. OPAQUE = start 65535, end 0. ICMP type/code packed as a 16-bit
  "port" (type high byte).
- A packet matches if it matches at least one selector in TSi AND at least one in TSr.
- The responder may narrow; it echoes (possibly narrowed) TSi/TSr in its response (§2.9). Remote-access example
  (§2.19): request TSi = TSr = (0, 0-65535, 0.0.0.0-255.255.255.255); reply TSi = (0, 0-65535, assigned-assigned),
  TSr = the networks the gateway will carry.
- In a rekey the new SA MUST NOT be narrower than the old one (§2.9.2).

### 3.11 Encrypted payload SK (46) (RFC 7296 §3.14; AEAD form in RFC 5282 §3)

Non-AEAD form (e.g. AES-CBC + HMAC):
```
| generic header (Next Payload = first inner payload type) |
| IV (cipher block size: 16 for AES-CBC) |
| Encrypted: inner payloads | Padding (0-255) | Pad Length (1) |
| Integrity Checksum Data (ICV, length from INTEG transform) |
```
- Payload Length covers header, IV, ciphertext, ICV.
- IV: new, unpredictable for every message; "using the final ciphertext block of the previous message is not
  considered unpredictable". Recipient MUST accept any IV.
- Padding: any value; (payloads + Padding + Pad Length) must be a multiple of the block size. Sender SHOULD use the
  minimum; receiver MUST accept any length that aligns.
- ICV = MAC over the whole IKE message from the first octet of the IKE header through the Pad Length, computed over
  the ENCRYPTED data (encrypt-then-MAC). So the IKE header Length and SK Payload Length must already include the
  ICV length when the MAC is computed. Key = SK_ai for messages from the original initiator, SK_ar otherwise.
- Encryption key: SK_ei (from original initiator) / SK_er.

AEAD form (RFC 5282 §3, §4, §5):
```
| generic header | IV (8 octets for AES-GCM/CCM/ChaCha20-Poly1305) | Ciphertext (includes the tag) |
```
- Plaintext P = inner payloads | Padding | Pad Length. For AEAD there are no alignment requirements; recipient
  MUST accept up to 255 octets of padding. RFC 7634 §3: sender SHOULD send no padding and Pad Length 0.
- Nonce N = salt (4 octets, from the end of SK_ei / SK_er) | IV (8 octets) = 12 octets for GCM and ChaCha20.
  AES-CCM uses an 11-octet nonce (3-octet salt).
- Associated data A = from the first octet of the IKE header through the 4-octet generic header of the SK payload,
  including any unencrypted payloads in between. The IV and ciphertext are NOT in A. With SK as the first payload,
  A is 32 octets (28 + 4) (RFC 7634 §3).
- Length fields inside A (IKE Length, SK Payload Length) must be final values, i.e. include IV and tag
  (RFC 7634 Appendix B says so explicitly).
- AES-GCM ICV = 16-octet tag (MUST support 16; MAY 8 or 12). RFC 5282 §7.2: 16-octet ICV SHOULD be used with IKEv2
  (transform 20).
- When AEAD is negotiated for IKE, SK_ai and SK_ar have length 0 and SK_ei/SK_er are key + salt
  (AES-GCM-128: 20 octets, AES-GCM-256: 36 octets, ChaCha20-Poly1305: 36 octets) (RFC 5282 §7.1, RFC 7634 §3).
- A full worked AEAD SK example is in the test-vector section (RFC 7634 Appendix B).

### 3.12 Configuration payload CP (47) (RFC 7296 §3.15, §3.15.1-3.15.4; RFC 8598)

```
| generic header | CFG Type (1) | RESERVED (3) | attributes ... |
Attribute: |R| Attribute Type (15) | Length (2, length of Value only) | Value |
```
- Request an address by sending an empty attribute (Length 0): e.g. INTERNAL_IP4_ADDRESS `00 01 00 00`,
  INTERNAL_IP4_DNS `00 03 00 00`, INTERNAL_IP4_NETMASK `00 02 00 00`, INTERNAL_IP6_ADDRESS `00 08 00 00`,
  INTERNAL_IP6_DNS `00 0A 00 00`, INTERNAL_DNS_DOMAIN `00 19 00 00`.
- CP(CFG_REQUEST) MUST contain at least one INTERNAL_IP4_ADDRESS or INTERNAL_IP6_ADDRESS (§2.19). It goes in the
  message that carries SAi2, i.e. message 3 in the EAP flow; CFG_REPLY arrives in the message carrying SAr2 (the
  last IKE_AUTH response in the EAP flow) (§2.19). "In all cases, the CP payload MUST be inserted before the SA
  payload."
- INTERNAL_IP6_ADDRESS / INTERNAL_IP6_SUBNET values = 16-octet address + 1-octet prefix length.
  INTERNAL_IP4_SUBNET = 4-octet address + 4-octet netmask. APPLICATION_VERSION: printable ASCII, not NUL-terminated.
- The reply MAY contain unrequested attributes; unknown attributes MUST be ignored.
- If the responder cannot assign an address: INTERNAL_ADDRESS_FAILURE (IKE SA still created, no Child SA). If it
  does not support CP at all it silently ignores it, so "If the initiator requires the assignment of an IP address,
  it will treat a response without CFG_REPLY as an error." (§3.15.4). If CP is required and missing:
  FAILED_CP_REQUIRED (not fatal to the IKE SA) (§2.19).
- Split DNS (RFC 8598 §3.1, §4.1): to accept split DNS the initiator includes one or more INTERNAL_DNS_DOMAIN (25)
  attributes (usually empty) AND at least one INTERNAL_IP4_DNS / INTERNAL_IP6_DNS in the CFG_REQUEST. Value = FQDN in
  DNS presentation format (IDNA A-label), not NUL-terminated.
- INTERNAL_IP4_SUBNET in a reply means "send traffic to these addresses through me"; the client may send other
  traffic covered by TSr directly (§3.15.2).

### 3.13 EAP payload (48) (RFC 7296 §3.16)

Generic header + one EAP packet (RFC 3748 §4). EAP Length MUST be Payload Length - 4. Code 1 Request, 2 Response,
3 Success, 4 Failure; Success/Failure are exactly 4 octets (no Type). In a Response the Identifier MUST equal the
request's. "the responder SHOULD NOT send EAP Identity requests (type 1). The initiator MAY, however, respond to such
requests if it receives them."

### 3.14 Encrypted Fragment payload SKF (53) (RFC 7383 §2.5)

```
| generic header (Next Payload: first inner type in fragment 1, 0 in all others) |
| Fragment Number (2) | Total Fragments (2) |
| IV | encrypted chunk | Padding | Pad Length | ICV |
```
- See §10 of these notes for use.

---

## 4. Exchanges (initiator view)

### 4.1 IKE_SA_INIT (RFC 7296 §1.2, §2.6, §2.23, §3.4; RFC 7383 §2.3; RFC 7427 §4)

```
HDR(SPIi, 0, MID 0, IKE_SA_INIT, I), SAi1, KEi, Ni,
    N(NAT_DETECTION_SOURCE_IP), N(NAT_DETECTION_DESTINATION_IP),
    [N(IKEV2_FRAGMENTATION_SUPPORTED)], [N(SIGNATURE_HASH_ALGORITHMS)], [V...]   -->
                          <--  HDR(SPIi, SPIr, MID 0, R), SAr1, KEr, Nr, [CERTREQ],
                               N(NAT_DETECTION_*), [N(IKEV2_FRAGMENTATION_SUPPORTED)],
                               [N(SIGNATURE_HASH_ALGORITHMS)], [N(MULTIPLE_AUTH_SUPPORTED)], [V...]
```
- NAT-D notifies go "just after the Ni and Nr payloads (before the optional CERTREQ payload)" (§2.23).
- IKEV2_FRAGMENTATION_SUPPORTED: Protocol ID 0, SPI size 0, type 16430, no data (RFC 7383 §2.3).
- After this exchange both sides compute SKEYSEED and the seven keys (§6 of these notes).
- The initiator MUST check the returned SAr1 matches something it offered (§3.3.6).
- Unprotected responses: an attacker can answer first. Initiator MAY accept multiple responses, continue with each,
  and keep only the one that later authenticates (§2.4). With TCP transport this is unnecessary: act on the first
  error (RFC 9329 §6.4).

COOKIE (§2.6): response `HDR(A,0), N(COOKIE)` with 1..64 octets of data. The initiator MUST retry IKE_SA_INIT with
N(COOKIE) as the FIRST payload and "all other payloads unchanged", same SPIi (the figures show HDR(A,0)), Message
ID still 0. If a cookie does not validate the responder treats it as absent (usually sends a new cookie). The
initiator should limit cookie rounds (exponential back-off).

INVALID_KE_PAYLOAD (§1.2, §1.3, §3.3.6, §2.6.1): data = 2-octet group number. The initiator MUST retry IKE_SA_INIT
with a KEi in that group, MUST still propose its FULL set of suites (downgrade protection), same SPIi, MID 0.
Shorter flow if cookie kept in all retries (§2.6.1):
```
HDR(A,0), SAi1, KEi, Ni                    --> <-- HDR(A,0), N(COOKIE)
HDR(A,0), N(COOKIE), SAi1, KEi, Ni         --> <-- HDR(A,0), N(INVALID_KE_PAYLOAD)
HDR(A,0), N(COOKIE), SAi1, KEi', Ni        --> <-- HDR(A,B), SAr1, KEr, Nr
```
"Implementations SHOULD support this shorter exchange, but MUST NOT fail if other implementations do not".
The AUTH later signs the LAST version of message 1 that was sent (§2.15).

NO_PROPOSAL_CHOSEN in IKE_SA_INIT: fatal for this attempt. All IKE_SA_INIT errors are unauthenticated; "the
recipient should continue trying for some time before giving up" except for defined corrective actions (COOKIE,
INVALID_KE_PAYLOAD, INVALID_MAJOR_VERSION) (§2.21.1).

### 4.2 IKE_AUTH without EAP (RFC 7296 §1.2)

```
HDR(MID 1), SK{IDi, [CERT,] [CERTREQ,] [IDr,] AUTH, [CP(CFG_REQUEST),] SAi2, TSi, TSr}  -->
                      <--  HDR(MID 1), SK{IDr, [CERT,] AUTH, [CP(CFG_REPLY),] SAr2, TSi, TSr}
```

### 4.3 IKE_AUTH with EAP (RFC 7296 §2.16, §2.2, §2.19; RFC 5998 §3)

```
msg1  HDR(MID 0), SAi1, KEi, Ni, N(NAT-D)...                           -->
msg2                                       <--  HDR(MID 0), SAr1, KEr, Nr, [CERTREQ], N(NAT-D)...
msg3  HDR(MID 1), SK{IDi, [CERTREQ,] [IDr,] [N(INITIAL_CONTACT),]
                     CP(CFG_REQUEST), SAi2, TSi, TSr}     (NO AUTH)    -->
msg4                                       <--  HDR(MID 1), SK{IDr, [CERT,] AUTH, EAP(Request)}
msg5  HDR(MID 2), SK{EAP(Response)}                                     -->
msg6                                       <--  HDR(MID 2), SK{EAP(Request) or EAP(Success)}
      ... repeat, MID 3, 4 ...
msg7  HDR(MID n), SK{AUTH}                                              -->
msg8                                       <--  HDR(MID n), SK{AUTH, CP(CFG_REPLY), SAr2, TSi, TSr}
```
- Leaving AUTH out of message 3 is how the initiator asks for EAP.
- The responder defers SAr2/TSi/TSr until EAP finished. MUST send EAP Success or EAP Failure at the end; MAY send
  EAP Failure any time. "If the exchange is terminated with EAP Failure, an AUTHENTICATION_FAILED notification is
  not sent" (§2.21).
- The initiator must support at least ten IKE_AUTH exchanges (§2.16).
- "the EAP AUTH payloads MUST be included in the two messages following the one containing the EAP Success message"
  (§2.16).
- Message 4 carries a public-key AUTH from the responder. EAP methods are used "in conjunction with a
  public-key-signature-based authentication of the responder to the initiator" (§2.16). The client MUST verify
  message 4's CERT + AUTH before trusting anything.
- RFC 5998 (EAP_ONLY_AUTHENTICATION, 16417) lets a client skip the responder certificate, but only for EAP methods
  that are mutual, key-generating AND dictionary-attack resistant (RFC 5998 §4). EAP-MSCHAPv2 is not dictionary
  resistant (draft-kamath §3 "Dictionary attack prot.: No"), so the client must NOT use EAP_ONLY_AUTHENTICATION with
  it and must require the certificate AUTH in message 4.
- AUTH in messages 7 and 8 uses the EAP MSK (key-generating methods) or SK_pi / SK_pr (non-key-generating),
  see §7 of these notes. RFC 7296: non-key-generating methods "SHOULD NOT be used".
- If the Child SA part fails after authentication succeeded (NO_PROPOSAL_CHOSEN, TS_UNACCEPTABLE,
  SINGLE_PAIR_REQUIRED, INTERNAL_ADDRESS_FAILURE, FAILED_CP_REQUIRED) the IKE SA still exists; the responder
  includes IDr/CERT/AUTH plus the error notify, and "the initiator MUST NOT fail the authentication because of
  this" (§1.2, §2.21.2).

### 4.4 CREATE_CHILD_SA (RFC 7296 §1.3, §1.3.1-1.3.3, §2.8, §2.17, §2.18)

Either peer may start it (so the client must also act as responder). May be refused with NO_ADDITIONAL_SAS.

New Child SA:
```
HDR, SK{SA, Ni, [KEi,] TSi, TSr, [N(USE_TRANSPORT_MODE)], [N(ESP_TFC_PADDING_NOT_SUPPORTED)]}  -->
                                                     <--  HDR, SK{SA, Nr, [KEr,] TSi, TSr}
```
Rekey Child SA:
```
HDR, SK{N(REKEY_SA, proto 3, SPI = old inbound SPI), SA, Ni, [KEi,] TSi, TSr}  -->
                                                     <--  HDR, SK{SA, Nr, [KEr,] TSi, TSr}
```
Rekey IKE SA (TS omitted; KE mandatory; SA has Protocol 1, SPI size 8, SPI = new SPI of the sender):
```
HDR, SK{SA, Ni, KEi}  -->   <--  HDR, SK{SA, Nr, KEr}
```
- If KEi is present, at least one SA offer must include its group; if the responder picks another group (not NONE)
  it rejects with INVALID_KE_PAYLOAD and 2-octet group; the exchange fails and the initiator may retry (§1.3).
- A failed Child SA creation SHOULD NOT tear down the IKE SA (§1.3.1).
- New IKE SA after rekey: message counters reset to 0, window size reset to 1, the rekey initiator becomes the new
  "original initiator" (so the I flag may flip) (§1.3.2, §2.18). The old IKE SA keeps its numbering; the Delete of
  the old IKE SA "MUST be the last request sent over the old IKE SA" (§2.8). Child SAs move to the new IKE SA.
- Responder of CREATE_CHILD_SA must accept traffic on the new SA before it sends the response; the initiator may
  send on it after processing the response; when rekeying, keep sending on the old SA until a valid packet arrives
  on the new inbound SA or the old SA's delete arrives (§2.8).
- IKEv2 does not negotiate lifetimes; each side rekeys by its own policy. If rekey fails and the SA is expiring,
  close the IKE SA and start again (§2.8).
- Reauthentication = brand-new IKE_SA_INIT/IKE_AUTH, then delete the old IKE SA. With EAP/CP, in practice only the
  original initiator can do it (§2.8.3). IMPORTANT for an OTP-based login: reauthentication would need a new code.
- Collisions: simultaneous rekey → the SA created with the lowest of the four nonces (octet-wise compare, shorter
  wins on equal prefix) SHOULD be closed by its creator (§2.8.1, §2.8.2). TEMPORARY_FAILURE / CHILD_SA_NOT_FOUND
  rules in §2.25.

### 4.5 INFORMATIONAL (RFC 7296 §1.4, §1.4.1, §2.4)

```
HDR, SK{[N,] [D,] [CP,] ...}  -->   <--  HDR, SK{[N,] [D,] [CP,] ...}
```
- MUST always be answered (an empty SK is a valid response).
- Liveness check (DPD): an empty INFORMATIONAL request (IKE header + SK with no inner payloads; SK Next Payload 0).
- Delete Child SA: send D with your inbound SPIs; the peer answers with D for its inbound SPIs of the same pairs.
  If both sides deleted the same SA at once, the responses MUST NOT include Delete payloads for those SAs (§1.4.1).
- Delete IKE SA: D(protocol 1, no SPI); answer is an empty INFORMATIONAL; all Child SAs die with it.
- Half-closed ESP pairs: a node MUST NOT unilaterally close them and reuse the SPIs (§1.4.1).

### 4.6 Messages outside an IKE SA (RFC 7296 §1.5, §2.21.4)

- Unknown ESP SPI from a peer with an IKE SA: MAY send INVALID_SPI over that IKE SA. Without an IKE SA: MAY send an
  unprotected informational (zero or random SPIs, I=1, R=0); the receiver MUST NOT respond to it.
- Encrypted request with unknown IKE SPI: unprotected response with INVALID_IKE_SPI, same SPIs and MID, R=1.
- A peer receiving an unprotected Notify MUST NOT respond and MUST NOT change SA state; treat it only as a hint to
  run a liveness check (rate-limited).

---

## 5. Message IDs, window, retransmission, liveness, errors

### 5.1 Message ID (RFC 7296 §2.2)
- 32-bit. 0 for IKE_SA_INIT including COOKIE / INVALID_KE retries. First IKE_AUTH = 1; with EAP the second
  IKE_AUTH = 2, and so on. Incremented per exchange.
- Each side keeps two counters: next MID for requests it sends; next MID it expects in requests it receives.
  Responses copy the request MID. The same number n can appear in four messages; the I and R flags disambiguate.
- Reset to 0 in the new IKE SA after an IKE rekey. If it would exceed 32 bits, rekey or close.

### 5.2 Window (RFC 7296 §2.3)
- Window is 1 until the initial exchanges complete. Without the peer's SET_WINDOW_SIZE (16385, data = 4-octet
  big-endian count) wait for each response before the next request.
- Even with window 1 a node MUST accept and process a request from the peer while its own request is outstanding
  (no deadlock).
- Keep a copy (or exact regeneration) of every request until answered, and of as many past responses as your
  declared window, to replay them on request retransmission. Window can only grow; a rekeyed IKE SA starts at 1.
- Out-of-window MID: optionally send INVALID_MESSAGE_ID (data = the 4-octet MID) in a NEW INFORMATIONAL request,
  never as a response; rate limited.

### 5.3 Retransmission (RFC 7296 §2.1, §2.4; RFC 9329 §6.2)
- Only the exchange initiator retransmits. A retransmission MUST be bit-for-bit identical from the IKE header on
  (so cache the encrypted bytes; do not re-encrypt with a new IV).
- The responder MUST NOT retransmit a response unless it receives the request again; it then resends the cached
  response. Responders may forget responses after several minutes; a retransmitted request whose response was
  forgotten is ignored.
- Timing is not specified ("do not affect interoperability"). Suggested: "at least a dozen times over a period of at
  least several minutes", and retransmission intervals "MUST increase exponentially".
- Over TCP (RFC 9329 §6.2): the exchange initiator SHOULD NOT retransmit; if no response in a reasonable time,
  delete the IKE SA. If a new TCP connection is opened while waiting, the request MUST be resent on it.
- EAP layer: EAP Requests are retransmitted by the authenticator with the same Identifier; the peer MUST resend its
  original Response to a duplicate Request (RFC 3748 §4.1). Inside IKEv2 this is mostly covered by IKE
  retransmission (EAP Identifier "serves no function here", RFC 7296 §3.16).

### 5.4 Liveness / dead peer (RFC 7296 §2.4)
- Decide a peer is dead only after repeated unanswered attempts over a timeout, or after an authenticated
  INITIAL_CONTACT on another IKE SA. Never based on ICMP or unprotected notifies.
- If only outgoing traffic has been seen recently, send a liveness check (empty INFORMATIONAL). Any fresh
  cryptographically valid IKE or ESP packet proves liveness of the IKE SA and all its Child SAs.
- After giving up: delete all state for the IKE SA and its Child SAs.
- INITIAL_CONTACT (16384): MAY be sent in the FIRST IKE_AUTH request only; asserts this is the only IKE SA between
  the identities; MUST NOT be sent if the same credentials may be used from two devices at once (§2.4).
- NAT keepalives are not liveness (RFC 3948 §4: "MUST NOT be used to detect whether a connection is live"). TCP/TLS
  keepalives are not liveness either (RFC 9329 §6.7).

### 5.5 Error handling (RFC 7296 §2.21, §2.21.1-2.21.4, §2.25)
- Only AUTHENTICATION_FAILED, EAP Failure, INVALID_SYNTAX and UNSUPPORTED_CRITICAL_PAYLOAD delete (or prevent) the
  IKE SA without a Delete payload.
- Error in a response: do not send an error message back (responses must not create requests), but clean up
  (e.g. delete the bad SA). Exception: if the initiator fails to authenticate the responder during IKE_AUTH it MAY
  send AUTHENTICATION_FAILED in a separate INFORMATIONAL (§2.21.2).
- After the IKE SA is authenticated every bad request MUST get a response with an error notify (INVALID_SYNTAX
  for anything not covered by another type, §3.10.1).
- TEMPORARY_FAILURE (43): do not retry immediately; retry over several minutes; if it persists, close the IKE SA.
- CHILD_SA_NOT_FOUND (44): silently delete that Child SA (if it still exists) and create a new one if needed.

### 5.6 Sizes (RFC 7296 §2)
- MUST handle IKE messages up to 1280 octets, SHOULD up to 3000. Use IKE fragmentation (RFC 7383) for larger
  IKE_AUTH messages (certificates). IKE_SA_INIT cannot be fragmented (RFC 7383 §2.2).

---

## 6. Key derivation (RFC 7296 §2.13, §2.14, §2.17, §2.18)

### 6.1 prf and prf+ (§2.13)
```
prf+(K, S) = T1 | T2 | T3 | ...
T1 = prf(K, S | 0x01)
T2 = prf(K, T1 | S | 0x02)
Tn = prf(K, T(n-1) | S | n)          (counter is ONE octet)
```
- Keys are cut from the stream "without regard to boundaries". prf+ is undefined beyond 255 * output length.
- HMAC PRFs take keys of any length (RFC 4868 §2.1.2 / RFC 2104: pad short keys with zeros to the block size, hash
  keys longer than the block size). Preferred key size = hash output size; this is the length of SK_d, SK_pi, SK_pr.
- Integrity keys for HMAC-based INTEG = hash output size (§2.13; RFC 4868 §2.1.1; RFC 2404).

### 6.2 IKE SA keys (§2.14)
```
SKEYSEED = prf(Ni | Nr, g^ir)
{SK_d | SK_ai | SK_ar | SK_ei | SK_er | SK_pi | SK_pr} = prf+(SKEYSEED, Ni | Nr | SPIi | SPIr)
```
- Ni, Nr = nonce data only (no payload header). SPIi, SPIr = the 8-octet IKE SPIs from the header of the NEW SA.
- g^ir = DH shared secret, big endian, zero-padded to the modulus length (MODP). ECP: x coordinate, fixed length
  (RFC 5903 §7). Curve25519: the 32-octet X25519 output (RFC 8031 §2).
- Only for PRF_AES128_XCBC / PRF_AES128_CMAC: SKEYSEED uses only the first 64 bits of Ni and of Nr.
- SK_ai/SK_ei protect messages FROM THE ORIGINAL INITIATOR; SK_ar/SK_er the other direction.
- Lengths: SK_d, SK_pi, SK_pr = PRF preferred key length. SK_ai/SK_ar = INTEG key length (0 with AEAD).
  SK_ei/SK_er = ENCR key length (+ salt for AEAD, RFC 5282 §7.1).

Worked lengths (our arithmetic from the rules above):

| IKE suite | SK_d | SK_ai | SK_ar | SK_ei | SK_er | SK_pi | SK_pr | total |
|---|---|---|---|---|---|---|---|---|
| AES-CBC-256, HMAC-SHA2-256-128, PRF-HMAC-SHA2-256 | 32 | 32 | 32 | 32 | 32 | 32 | 32 | 224 (7 blocks) |
| AES-CBC-128, HMAC-SHA1-96, PRF-HMAC-SHA1 | 20 | 20 | 20 | 16 | 16 | 20 | 20 | 132 |
| AES-GCM-16-256, PRF-HMAC-SHA2-256 | 32 | 0 | 0 | 36 | 36 | 32 | 32 | 168 |
| AES-GCM-16-128, PRF-HMAC-SHA2-256 | 32 | 0 | 0 | 20 | 20 | 32 | 32 | 136 |
| ChaCha20-Poly1305, PRF-HMAC-SHA2-256 | 32 | 0 | 0 | 36 | 36 | 32 | 32 | 168 |
| AES-CBC-256, HMAC-SHA2-384-192, PRF-HMAC-SHA2-384 | 48 | 48 | 48 | 32 | 32 | 48 | 48 | 304 |
| AES-CBC-256, HMAC-SHA2-512-256, PRF-HMAC-SHA2-512 | 64 | 64 | 64 | 32 | 32 | 64 | 64 | 384 |

For AEAD: SK_ex = key || salt(4) (salt = LAST 4 octets).

### 6.3 Child SA keys (§2.17; RFC 4106 §8.1; RFC 7634 §2)
```
KEYMAT = prf+(SK_d, Ni | Nr)                   first Child SA (from IKE_AUTH): Ni, Nr of IKE_SA_INIT
KEYMAT = prf+(SK_d, Ni | Nr)                   CREATE_CHILD_SA without KE: the NEW nonces
KEYMAT = prf+(SK_d, g^ir(new) | Ni | Nr)       CREATE_CHILD_SA with KE
```
Order inside KEYMAT (§2.17, via RFC 4301):
1. All keys for the SA carrying data initiator → responder, then responder → initiator.
   "Initiator" = initiator of the exchange that created the Child SA. For the IKE_AUTH Child SA that is the client.
   For a CREATE_CHILD_SA started by the gateway (gateway-initiated rekey), the GATEWAY is the initiator, so the
   first key block is the gateway→client direction. (Ni/Nr likewise are the exchange initiator's/responder's.)
2. Within one SA: encryption key first, then integrity key.

Worked ESP sizes:

| ESP suite | per direction | KEYMAT total |
|---|---|---|
| AES-GCM-16-256 | 32 key + 4 salt = 36 | 72 |
| AES-GCM-16-128 | 16 + 4 = 20 | 40 |
| ChaCha20-Poly1305 | 32 + 4 = 36 | 72 |
| AES-CBC-256 + HMAC-SHA2-256-128 | 32 + 32 = 64 | 128 |
| AES-CBC-128 + HMAC-SHA1-96 | 16 + 20 = 36 | 72 |

So for AES-GCM-256 via IKE_AUTH, client outbound = KEYMAT[0:32] key, KEYMAT[32:36] salt; client inbound =
KEYMAT[36:68] key, KEYMAT[68:72] salt.

### 6.4 IKE SA rekey (§2.18)
```
SKEYSEED = prf(SK_d(old), g^ir(new) | Ni | Nr)     using the OLD IKE SA's PRF
{SK_d | SK_ai | ... | SK_pr} = prf+(SKEYSEED, Ni | Nr | SPIi | SPIr)   new SPIs (from the SA payloads), new PRF
```
- MUST do a new DH (no NONE). New SA message IDs start at 0.
- Note: RFC 7296 §2.18 lists only SK_d, SK_ai, SK_ar, SK_ei, SK_er as "computed from SKEYSEED as specified in
  Section 2.14"; the prf+ in §2.14 always produces all seven, SK_pi/SK_pr are simply unused after a rekey
  (no AUTH in rekey).

The NIST CAVP IKEv2 vectors (section 15.8 below) cover exactly these four formulas; we verified that DKM(Child SA)
uses SK_d = first PRF-length octets of DKM.

---

## 7. AUTH computation (RFC 7296 §2.15, §2.16)

### 7.1 Signed octets
```
InitiatorSignedOctets = RealMessage1 | NonceRData | MACedIDForI
    RealMessage1 = the IKE_SA_INIT request exactly as last sent, from the first octet of SPIi to the end
                   (LAST version: after COOKIE / INVALID_KE retries)
    NonceRData   = Nr (value only)
    MACedIDForI  = prf(SK_pi, RestOfInitIDPayload),  RestOfInitIDPayload = IDType | RESERVED(3) | IDi data
ResponderSignedOctets = RealMessage2 | NonceIData | MACedIDForR
    RealMessage2 = the IKE_SA_INIT response (the one that created the SA)
    NonceIData   = Ni (value only)
    MACedIDForR  = prf(SK_pr, RestOfRespIDPayload)
```
- RFC 7296 defines `GenIKEHDR = [ four octets 0 if using port 4500 ] | RealIKEHDR` but then builds RealMessage from
  RealIKEHDR; i.e. the non-ESP marker is NOT part of the signed octets (the marker is "not part of the IKE message",
  §3.1). Same for the TCP length field.
- "all of the payloads are included under the signature, including any payload types not defined in this document".

### 7.2 Shared key / EAP MSK
```
initiator: AUTH = prf( prf(Shared Secret, "Key Pad for IKEv2"), InitiatorSignedOctets )
responder: AUTH = prf( prf(Shared Secret, "Key Pad for IKEv2"), ResponderSignedOctets )
"Key Pad for IKEv2" = 17 ASCII octets, no NUL.
```
- Auth Method = 2 for these.
- EAP key-generating method: Shared Secret = MSK ("the field from the EAP specification named MSK"). The AUTH in
  message 7 (initiator) and message 8 (responder) both use it. The MSK "MUST NOT be used for any other purpose".
- EAP non-key-generating method: Shared Secret = SK_pi for the initiator's AUTH and SK_pr for the responder's.
- IDs in MACedIDForI/R are the IDi from message 3 and the IDr from message 4 (the payloads of this IKE SA), not the
  EAP identity.
- Message 4's responder AUTH is a signature (method 1, 9-11 or 14) over ResponderSignedOctets; message 8's is the
  MSK-based MIC over the same ResponderSignedOctets.

### 7.3 MSK for EAP-MSCHAPv2 (analysis; confirm by trace)

What the IETF documents say:
- RFC 3748 §7.10: a key-generating EAP method MUST export an MSK of at least 64 octets.
- draft-kamath-pppext-eap-mschapv2-02 §1/§3: EAP-MSCHAPv2 derives keys per RFC 3079 but does NOT spell out the MSK
  byte layout.
- RFC 3079 §3.3/§3.4: MasterKey = SHA1(PasswordHashHash | NT-Response | "This is the MPPE Master Key")[0:16];
  two 16-octet keys: GetAsymmetricStartKey(MasterKey, *, 16, IsSend, IsServer). s = Magic2 when (IsSend && !IsServer)
  or (!IsSend && IsServer); s = Magic3 otherwise. Key = SHA1(MasterKey | 40 x 0x00 | s(84) | 40 x 0xF2)[0:16].
  Magic2 = "On the client side, this is the send key; on the server side, it is the receive key."
  Magic3 = "On the client side, this is the receive key; on the server side, it is the send key."
- RFC 5422 §3.2.3 (EAP-FAST-MSCHAPv2): 32-octet key = MasterSendKey (first 16) | MasterReceiveKey (last 16).
- draft-ietf-emu-rfc7170bis-22 §3.6.4: "The difference between EAP-MSCHAPv2 and EAP-FAST-MSCHAPv2 is that the first
  and the second 16 octets of EAP-MSCHAPv2 Master Session Key (MSK) are swapped". So EAP-MSCHAPv2 MSK[0:32] =
  MasterReceiveKey | MasterSendKey. That draft cites Microsoft's [MS-CHAP] "Master Session Key (MSK) Derivation" for
  the full definition; that document is outside our allowed sources.
- Perspective: RFC 3580 §4 "the MS-MPPE-Send-Key and MS-MPPE-Recv-Key attributes are defined from the point of view
  of the Authenticator"; RFC 5216 §2.3 and RFC 5281 §8: MSK(0,31) = MS-MPPE-Recv-Key = Peer-to-Authenticator key,
  MSK(32,63) = MS-MPPE-Send-Key.

Our conclusion (medium confidence):
```
MSK[0:16]  = key with Magic2  (= peer's MasterSendKey = authenticator's MasterReceiveKey)
MSK[16:32] = key with Magic3  (= peer's MasterReceiveKey = authenticator's MasterSendKey)
MSK[32:64] = unknown filler; most likely 32 zero octets, but "not publicly documented" in our allowed sources
```
Why the filler does not matter for IKEv2 with HMAC PRFs: prf(MSK, "Key Pad for IKEv2") uses MSK as an HMAC key.
HMAC zero-pads keys shorter than the block size (RFC 2104 §2; RFC 4868 §2.1.2). SHA-1/SHA-256 have 64-octet
blocks and SHA-384/512 128-octet blocks, so a 32-octet key and the same key followed by 32 zero octets give the
same HMAC. Verified numerically for SHA-1/256/384/512. Only the ORDER of the two 16-octet halves matters.
If the gateway answers message 7 with AUTHENTICATION_FAILED after EAP Success, the half order is the first
suspect. This is a MUST-CONFIRM-BY-TRACE item (a failed try costs a login attempt; with OTP it costs the code).

Derived (not official) MSK for the RFC 3079 §3.5.3 sample inputs, using the conclusion above:
```
Magic2 key = D5 F0 E9 52 1E 3E A9 58 96 45 E8 60 51 C8 22 26
Magic3 key = 8B 7C DC 14 9B 99 3A 1B A1 18 CB 15 3F 56 DC CB   (= RFC 3079 "SendStartKey128", server send key)
MSK (candidate) = D5F0E9521E3EA9589645E86051C82226 8B7CDC149B993A1BA118CB153F56DCCB || 00 x 32
```

### 7.4 EAP-TTLS MSK (RFC 5281 §8; RFC 9427 §2.1)
- TLS 1.0-1.2: Keying Material = PRF-128(master_secret, "ttls keying material", client_random | server_random);
  MSK = [0..63], EMSK = [64..127]. PRF = the TLS PRF of the negotiated TLS version.
- TLS 1.3: Key_Material = TLS-Exporter("EXPORTER_EAP_TLS_Key_Material", Type=0x15, 128); MSK = first 64 octets.
- Full 64-octet MSK is used as the IKE shared secret.

---

## 8. NAT traversal and UDP encapsulation (RFC 7296 §2.23, §2.11, §3.1; RFC 3948)

### 8.1 Detection
- NAT_DETECTION_SOURCE_IP data = SHA-1(SPIi | SPIr | source IP | source port) of the sending packet (20 octets).
  NAT_DETECTION_DESTINATION_IP data = SHA-1(SPIi | SPIr | destination IP | destination port).
  SPIs "in the order they appear in the header" (8 + 8 octets; SPIr = 0 in the first request), IP = 4 or 16 octets,
  port = 2 octets, all network order. Multiple SOURCE_IP notifies are allowed if the sender is unsure of its
  address.
- Receiver: recompute with the addresses/ports seen on the packet. If NAT_DETECTION_DESTINATION_IP does not match,
  THIS host is behind a NAT → SHOULD start keepalives. If no SOURCE_IP matches, the PEER is behind a NAT.
- The initiator "MUST check" these and, if they do not match, "MUST tunnel all future IKE and ESP packets associated
  with this IKE SA over UDP port 4500". If a NAT is detected both sides MUST use UDP encapsulation for ESP.
- An initiator can use port 4500 from the start, even without NAT. On 4500, understanding received UDP-encapsulated
  ESP is required; UDP encapsulation MUST NOT be done on port 500.
- A host behind a NAT SHOULD NOT change the peer address based on a validated packet from a different address/port;
  a host NOT behind a NAT SHOULD follow the new address (dynamic update), only for fresh packets (§2.23).
- IKE MUST answer to the address/port the request came from, and accept requests from any source port (§2.11).

### 8.2 Wire formats on UDP 4500 (RFC 3948 §2.1-2.3; RFC 7296 §3.1)
```
IKE:        UDP hdr | 00 00 00 00 (non-ESP marker) | IKE message
ESP:        UDP hdr | ESP header (SPI != 0) ...
Keepalive:  UDP hdr | FF                           (exactly one octet)
```
- Source/destination ports for UDP-ESP MUST equal those used by IKE. IPv4 UDP checksum SHOULD be sent as 0;
  receivers MUST NOT depend on it being 0.
- Demux rule for received datagrams on 4500: length 1 and 0xFF → keepalive (ignore); first 4 octets zero → IKE;
  else ESP (SPI can never be 0, RFC 4303 §2.1).
- The marker is not counted in the IKE Length field and not covered by the ICV or the AUTH.

### 8.3 NAT keepalive (RFC 3948 §4; RFC 7296 §2.23)
- SHOULD be sent if a NAT was detected (we are behind it) and no other packet was sent to the peer for M seconds,
  M default 20 s. MAY be sent while any SA exists or existed within N minutes (default 5).
- Receiver SHOULD ignore it; MUST NOT use it as liveness.

---

## 9. TCP encapsulation (RFC 9329)

- Not negotiated; must be preconfigured on both ends (§2). MUST support TCP port 4500; other ports configurable.
  Optional extra framing such as TLS is allowed but must also be preconfigured (§2, Appendix A).
- Stream prefix: the TCP originator sends once, at the start of every TCP connection, the 6 octets "IKETCP"
  = `49 4b 45 54 43 50` (§4). The responder waits for the full prefix. On a new TCP connection for an existing
  IKE SA the prefix is sent again (§6.1).
- Framing (§3): every message is preceded by a 2-octet big-endian Length that INCLUDES the length field itself.
  ```
  IKE: Length(2) | 00 00 00 00 | IKE message      (Length = 2 + 4 + IKE length)
  ESP: Length(2) | ESP packet                     (Length = 2 + ESP length; SPI != 0)
  ```
  Length 0 or 1 → fatal, close the connection. Length 2 (empty) → silently ignore. Max message 65533 octets;
  SHOULD limit messages to the sizes used with UDP encapsulation (that sets the effective ESP MTU).
- If TCP is used for an IKE SA, ALL its IKE messages and all its Child SAs' ESP packets go over TCP until the SA is
  deleted (or MOBIKE moves it) (§5). One TCP connection per IKE SA; multiple IKE SAs MUST NOT share one, except
  briefly during an IKE rekey (§6.1).
- Fallback (§5.1): try UDP first unless the network is known to block UDP; retransmit the UDP IKE_SA_INIT at least
  once before falling back. Switching UDP → TCP needs a NEW IKE_SA_INIT with a NEW SPIi and recomputed NAT-D.
- Retransmission (§6.2): SHOULD NOT retransmit requests over TCP; if a new TCP connection is opened while waiting,
  MUST resend the request on it.
- NAT-D (§6.5): still SHOULD be sent, computed with the TCP ports. A detected NAT changes nothing for TCP.
- NAT keepalives (§6.6): SHOULD NOT be sent over TCP; received ones (Length 3, value 0xFF) MUST be silently dropped.
- Liveness (§6.7): use IKE INFORMATIONAL; TCP/TLS keepalives are not IKE liveness.
- Connection loss (§6.1): the TCP originator (client) is responsible for reconnecting; partial messages are dropped;
  the responder MUST accept packets for existing SAs from new addresses/ports. After reconnecting, send an empty
  INFORMATIONAL (or UPDATE_SA_ADDRESSES if MOBIKE).
- Cookies over TCP (§6.3): the responder SHOULD NOT send a cookie without a puzzle; initiator behaviour unchanged.
  After an IKE_SA_INIT error needing correction (INVALID_KE_PAYLOAD) the responder SHOULD keep the TCP connection
  open (§6.4).
- Fragmentation (§7.5): SHOULD NOT send IKE fragments over TCP but MUST be able to receive them.
- DF bit / DSCP: TCP stack controls the outer header (§6.8).

---

## 10. IKE fragmentation (RFC 7383)

- Negotiated by IKEV2_FRAGMENTATION_SUPPORTED (16430, no data) in both IKE_SA_INIT messages (§2.3). MUST NOT be used
  unless both sent it. Each exchange initiator decides; the responder usually answers in the same form (§2.4).
- Only messages that have an SK payload can be fragmented (not IKE_SA_INIT) (§2.2).
- Sender (§2.5): take the PLAINTEXT content of the SK payload (inner payloads, no padding), split it anywhere into
  chunks, encrypt and protect each chunk exactly like an SK payload but in an SKF payload (type 53), prepend a copy
  of the original IKE header with only Length and Next Payload changed (Next Payload = 53 when SKF is first).
  SKF Next Payload = first inner payload type in fragment 1, 0 in the others. Fragment Number 1..Total, non-zero.
  All fragments share the Message ID.
- Fragment size (§2.5.1): IPv4 SHOULD default to a 576-octet IP datagram, IPv6 to 1280, unless PMTU is known.
  Overhead per fragment (Appendix B, IPv4): 20 IP + 8 UDP + 4 marker + 28 IKE + 8 SKF header (4 generic + 4
  fragment fields) + IV + ICV + padding.
- Receiver (§2.6): silently drop if Fragment Number or Total is 0, Number > Total, or Total smaller than already
  queued; drop replays (same MID, Number, Total); verify ICV per fragment; a larger Total means restart reassembly
  (sender is doing PMTU discovery). When all arrived, concatenate decrypted contents and process as a normal
  message. Reassembly timeout: discard all fragments.
- Retransmission (§2.6.1): Fragment Number and Total are part of the retransmit/replay key. A responder that already
  answered retransmits its (fragmented) response only when it receives fragment number 1 again.
- AEAD + SKF: RFC 7383 only says processing is "identical to that described in Section 3.14 of [RFC7296], as well as
  documents updating such processing ... such as [RFC5282]". RFC 5282 §5.1 defines A as IKE header through the
  4-octet payload header. Whether the 4 octets Fragment Number/Total Fragments are also in A is NOT stated
  explicitly in the RFCs we read. Must confirm by trace (a receiver can try both A variants).

---

## 11. Diffie-Hellman groups

### 11.1 Group 14, 2048-bit MODP (RFC 3526 §3)
```
p = 2^2048 - 2^1984 - 1 + 2^64 * { [2^1918 pi] + 124476 }
FFFFFFFF FFFFFFFF C90FDAA2 2168C234 C4C6628B 80DC1CD1
29024E08 8A67CC74 020BBEA6 3B139B22 514A0879 8E3404DD
EF9519B3 CD3A431B 302B0A6D F25F1437 4FE1356D 6D51C245
E485B576 625E7EC6 F44C42E9 A637ED6B 0BFF5CB6 F406B7ED
EE386BFB 5A899FA5 AE9F2411 7C4B1FE6 49286651 ECE45B3D
C2007CB8 A163BF05 98DA4836 1C55D39A 69163FA8 FD24CF5F
83655D23 DCA3AD96 1C62F356 208552BB 9ED52907 7096966D
670C354E 4ABC9804 F1746C08 CA18217C 32905E46 2E36CE3B
E39E772C 180E8603 9B2783A2 EC07A28F B5C55DF0 6F4C52C9
DE2BCBF6 95581718 3995497C EA956AE5 15D22618 98FA0510
15728E5A 8AACAA68 FFFFFFFF FFFFFFFF
g = 2
```
- KE data and g^ir: 256 octets, big endian, left zero-padded (RFC 7296 §3.4, §2.14).
- Recipient check (RFC 6989 §2.1, safe-prime group): peer value r MUST satisfy 1 < r < p-1.

### 11.2 ECP groups 19, 20, 21 (RFC 5903 §3, §7; RFC 6989 §2.3)
Curve y^2 = x^3 - 3x + b over GF(p). These are NIST P-256, P-384, P-521.

Group 19 (256-bit):
```
p  = FFFFFFFF 00000001 00000000 00000000 00000000 FFFFFFFF FFFFFFFF FFFFFFFF
b  = 5AC635D8 AA3A93E7 B3EBBD55 769886BC 651D06B0 CC53B0F6 3BCE3C3E 27D2604B
n  = FFFFFFFF 00000000 FFFFFFFF FFFFFFFF BCE6FAAD A7179E84 F3B9CAC2 FC632551
gx = 6B17D1F2 E12C4247 F8BCE6E5 63A440F2 77037D81 2DEB33A0 F4A13945 D898C296
gy = 4FE342E2 FE1A7F9B 8EE7EB4A 7C0F9E16 2BCE3357 6B315ECE CBB64068 37BF51F5
```
Group 20 (384-bit):
```
p  = FFFFFFFF FFFFFFFF FFFFFFFF FFFFFFFF FFFFFFFF FFFFFFFF FFFFFFFF FFFFFFFE
     FFFFFFFF 00000000 00000000 FFFFFFFF
b  = B3312FA7 E23EE7E4 988E056B E3F82D19 181D9C6E FE814112 0314088F 5013875A
     C656398D 8A2ED19D 2A85C8ED D3EC2AEF
n  = FFFFFFFF FFFFFFFF FFFFFFFF FFFFFFFF FFFFFFFF FFFFFFFF C7634D81 F4372DDF
     581A0DB2 48B0A77A ECEC196A CCC52973
gx = AA87CA22 BE8B0537 8EB1C71E F320AD74 6E1D3B62 8BA79B98 59F741E0 82542A38
     5502F25D BF55296C 3A545E38 72760AB7
gy = 3617DE4A 96262C6F 5D9E98BF 9292DC29 F8F41DBD 289A147C E9DA3113 B5F0B8C0
     0A60B1CE 1D7E819D 7A431D7C 90EA0E5F
```
Group 21 (521-bit):
```
p  = 01FF followed by 64 x FF   (2^521 - 1, written as 66 octets)
b  = 0051953E B9618E1C 9A1F929A 21A0B685 40EEA2DA 725B99B3 15F3B8B4 89918EF1
     09E15619 3951EC7E 937B1652 C0BD3BB1 BF073573 DF883D2C 34F1EF45 1FD46B50 3F00
n  = 01FFFFFF FFFFFFFF FFFFFFFF FFFFFFFF FFFFFFFF FFFFFFFF FFFFFFFF FFFFFFFF
     FFFA5186 8783BF2F 966B7FCC 0148F709 A5D03BB5 C9B8899C 47AEBB6F B71E9138 6409
gx = 00C6858E 06B70404 E9CD9E3E CB662395 B4429C64 8139053F B521F828 AF606B4D
     3DBAA14B 5E77EFE7 5928FE1D C127A2FF A8DE3348 B3C1856A 429BF97E 7E31C2E5 BD66
gy = 01183929 6A789A3B C0045C8A 5FB42C7D 1BD998F5 4449579B 446817AF BD17273E
     662C97EE 72995EF4 2640C550 B9013FAD 0761353C 7086A272 C24088BE 94769FD1 6650
```
- KE data = x | y, each fixed width 32 / 48 / 66 octets (528 bits for group 21). No 0x04 prefix.
  (Java/Android `ECPoint` encodings usually add 0x04; strip/add it at the boundary.)
- Shared secret g^ir = x coordinate of the common point, fixed width (RFC 5903 §7, §9 changed this from RFC 4753).
- Recipient check (RFC 6989 §2.3): MUST verify the peer point satisfies the curve equation (point at infinity cannot
  be encoded, so no extra check). On failure in IKE_SA_INIT: drop the message and do not use it (RFC 6989 §2.5).

### 11.3 Group 31, Curve25519 (RFC 8031 §2-3; RFC 7748 §5, §6.1)
- KE data = 32 octets = X25519(d, 9) (u-coordinate little endian). Payload Length 40.
- g^ir = X25519(d, peer_public), 32 octets, used as-is in SKEYSEED.
- Mask the high bit of the last octet of received u; accept non-canonical values. MAY reject an all-zero result.
- Private scalar: 32 random octets; X25519 clamps internally (RFC 7748 §5 decodeScalar25519).

### 11.4 What to propose (RFC 8247 §2.4, §2.1-2.3)
IKEv2: DH 14 MUST, 19 SHOULD; 1/22 MUST NOT; 2/5 SHOULD NOT. ENCR_AES_CBC MUST, AES_GCM_16 SHOULD,
CHACHA20_POLY1305 SHOULD. PRF_HMAC_SHA2_256 MUST, SHA2_512 SHOULD+, SHA1 MUST-. INTEG HMAC_SHA2_256_128 MUST,
SHA2_512_256 SHOULD, SHA1_96 MUST-. Auth: RSA sig (1) MUST, shared key (2) MUST, ECDSA (9-11) SHOULD, Digital
Signature (14) SHOULD (RFC 8247 §3.1).
ESP (RFC 8221 §5, §6): AES_CBC MUST, AES_GCM_16 MUST (128 and 256-bit), CHACHA20_POLY1305 SHOULD, 3DES SHOULD NOT;
INTEG HMAC_SHA2_256_128 MUST, SHA2_512_256 SHOULD, SHA1_96 MUST-.

---

## 12. ESP (RFC 4303)

### 12.1 Packet layout (§2, Figures 1-2)
```
| SPI (4) | Sequence Number (4, low 32 bits) |           <- integrity covered, never encrypted
| IV (algorithm specific) | Payload Data (inner IP packet in tunnel mode) | [TFC padding] |
| Padding (0-255) | Pad Length (1) | Next Header (1) |    <- encrypted
| ICV (algorithm specific) |
```
- Outer IPv4 protocol 50 (not used when UDP/TCP encapsulated).
- SPI: chosen by the RECEIVER; 0 MUST NOT be sent; 1-255 reserved by IANA (§2.1).
- Next Header in tunnel mode: 4 (IPv4) or 41 (IPv6). 59 = dummy packet: receiver MUST discard silently; transmitter
  MUST be able to generate them (§2.6).
- Padding (§2.4): make (payload + padding + 2) a multiple of the cipher block size, and in any case make Pad Length
  and Next Header end on a 4-octet boundary (ICV aligned). Default content if the algorithm does not say otherwise:
  1, 2, 3, ... (first pad byte = 1); receiver SHOULD check it. Sender MAY add 0-255 octets.
- TFC padding only if negotiated (ESP_TFC_PADDING_NOT_SUPPORTED says the sender will not accept it) (§2.7,
  RFC 7296 §1.3.1). In tunnel mode the receiver finds the real end from the inner IP length.
- ICV computed over SPI | Seq | IV | ciphertext (incl. padding, pad length, next header), encrypt first then MAC.
  With ESN and a separate MAC, the high 32 bits of the sequence number are appended after Next Header for the MAC
  input only (not sent) (§3.3.2.1). Implicit integrity padding (zeros) only if the MAC algorithm says so; HMAC-SHA2
  needs none (RFC 4868 §2.2).
- Receive order (§3.4): SA lookup by SPI → preliminary replay check → ICV check (or AEAD decrypt) → then update
  window → decrypt → check padding → discard if NH=59 → deliver inner packet. Fragments (MF set or offset non-zero)
  MUST be discarded (reassembly happens before ESP).
- Errata 4798/4799: the TFC references in §2 and §2.6 should point to §2.7.

### 12.2 Sequence numbers and ESN (§2.2, §2.2.1, §3.3.3)
- Counters start at 0 at SA creation; the first packet sent has sequence number 1. Increment for every packet.
- With anti-replay on (default for the sender's assumption), the counter MUST NOT cycle: rekey before the 2^32nd
  packet (32-bit) or before 2^64 (ESN).
- ESN: only low 32 bits on the wire; both ends keep 64-bit counters; the high 32 bits are fed into the ICV (separate
  MAC) or AAD (AEAD). RFC 4303 §2.2.1 says the IKEv2 default is ESN, but RFC 7296 makes the SN transform mandatory
  in every ESP proposal, so it is always explicit. A receiver that does not do anti-replay SHOULD NOT negotiate ESN.

### 12.3 Anti-replay window (§3.4.3; Appendix A2)
- MUST support; window min 32, SHOULD default to 64 (32-bit SN). Receiver does not tell the sender its window.
- Right edge T = highest AUTHENTICATED sequence number. Reject below the left edge; within the window reject
  duplicates; above T accept after the integrity check. Update the window only after the ICV/AEAD check passes.
- ESN receive algorithm (Appendix A2.3, W = window size, 32-bit arithmetic mod 2^32):
```
If (Tl >= W - 1)                                   Case A: window within one subspace
    If (Seql >= Tl - W + 1)
        Seqh = Th
        If (Seql <= Tl)
            If (pass replay check) and (pass integrity check): set bit(Seql), accept
            Else reject
        Else
            If (pass integrity check): Tl = Seql (shift bits), set bit, accept
            Else reject
    Else
        Seqh = Th + 1
        If (pass integrity check): Tl = Seql (shift bits), Th = Th + 1, set bit, accept
        Else reject
Else                                               Case B: window spans two subspaces
    If (Seql >= Tl - W + 1)
        Seqh = Th - 1
        If (pass replay check) and (pass integrity check): set bit, accept
        Else reject
    Else
        Seqh = Th
        If (Seql <= Tl)
            If (pass replay check) and (pass integrity check): set bit, accept
            Else reject
        Else
            If (pass integrity check): Tl = Seql (shift bits), set bit, accept
            Else reject
```
- Resync (A3): after many consecutive auth failures, retry a bad packet with Seqh+1, +2, ... (bounded).
- RFC 6479 (alternative, no bit shifting): keep a ring of M blocks of N bits (both powers of two); usable window
  = (M-1)*N. Bit position = seq & (N-1); block index = (seq >> log2 N) & (M-1). When seq > last, zero the blocks
  between the old and the new block index (at most M), set last = seq. Check: seq == 0 → reject; seq > last →
  accept (pending integrity); seq + window < last → reject (too old); else test the bit. Note the example code in
  RFC 6479 §3 uses macro names that do not match their definitions (IPSEC_BITMAP_LEN vs BITMAP_LEN,
  IPSEC_REDUNDANT_BITS vs REDUNDANT_BITS); treat it as pseudocode. Update only after authentication.

### 12.4 AES-CBC for ESP and IKE (RFC 3602 §2-3)
- Key 128/192/256 bits (Key Length attribute), block and IV 16 octets. IV at the start of Payload Data, MUST be
  random and unpredictable per packet; MUST NOT be a counter or other low-Hamming-distance source.
- Encrypted data (inner packet + padding + pad len + NH) MUST be a multiple of 16; that also keeps ICV aligned.
- Key = first bits of the direction's keying material (RFC 3602 §3.2).

### 12.5 HMAC integrity (RFC 4868 §2.1-2.6; RFC 2404)
| Transform | ID | Key | Block | ICV (truncated) |
|---|---|---|---|---|
| AUTH_HMAC_SHA1_96 | 2 | 20 | 64 | 12 |
| AUTH_HMAC_SHA2_256_128 | 12 | 32 | 64 | 16 |
| AUTH_HMAC_SHA2_384_192 | 13 | 48 | 128 | 24 |
| AUTH_HMAC_SHA2_512_256 | 14 | 64 | 128 | 32 |
- As integrity: fixed key length = hash output length; other lengths MUST NOT be supported. ICV = first nnn/2 bits
  of HMAC output; receiver computes the full HMAC and compares the leading half (use constant-time compare).
- As PRF (IDs 5/6/7): same HMAC, variable key length, NO truncation (RFC 4868 §2.4).

### 12.6 AES-GCM for ESP (RFC 4106 §3-8)
```
Payload Data = IV (8 octets, explicit) | ciphertext
nonce (12)   = salt (4, from KEYMAT) | IV (8)
AAD          = SPI (4) | Seq (4)                  32-bit SN, 8 octets
AAD          = SPI (4) | ESN high (4) | ESN low (4)   ESN, 12 octets (64-bit big endian)
plaintext    = inner packet | [TFC] | padding | pad length | next header
ICV          = GCM tag, 16 octets (transform 20); 12 (19) or 8 (18) optional
```
- IV MUST NOT repeat for a key; a counter is fine (RFC 4106 §3.1). The RFC 7634 §2 note: with the counter method the
  last 32 bits of the IV may equal the sequence number.
- Padding: only to 4-octet alignment ("less than four octets" if not hiding length, §3.2).
- KEYMAT per direction = key + 4-octet salt (20 / 28 / 36 octets for 128 / 192 / 256) (§8.1). Key Length attribute
  MUST be 128, 192 or 256 (§8.4).
- Packet expansion: 8 IV + ICV + 10..13 for SPI/Seq/pad/padlen/NH (§7).
- No integrity transform with GCM (RFC 5282 §8).

### 12.7 ChaCha20-Poly1305 for ESP (RFC 7634 §2, §2.1, §4)
- Transform 28, no Key Length attribute, key 256 bits, KEYMAT 36 octets (32 key + 4 salt). IV 8 octets explicit,
  nonce = salt | IV. ChaCha20 block counter starts at 1 (block 0 makes the Poly1305 key).
- AAD like GCM: SPI | Seq (8) or SPI | 64-bit ESN (12). Tag 16 octets. Padding need not exceed 4 octets.

---

## 13. EAP and the methods

### 13.1 EAP packet (RFC 3748 §4, §4.1, §4.2, §5)
```
| Code (1) | Identifier (1) | Length (2, whole packet) | [Type (1) | Type-Data] |
```
- Codes 1-4 only; others silently discarded. Length larger than received → discard; octets beyond Length are
  padding and ignored.
- Response Identifier MUST match the outstanding Request's. Peer MUST resend its original response to a duplicate
  Request; responses are never sent on a timer.
- A Response Type MUST match the Request Type or be Nak (3) / Expanded Nak (254). Once a non-Nak response was sent
  in a method, no Nak may follow.
- Identity (1): Response carries the identity, not NUL-terminated; Request may carry a display message (portion
  before a NUL is displayed). Identity SHOULD NOT exceed 1020 octets.
- Notification (2): Request carries a UTF-8 message; peer MUST answer with an empty Notification Response (never
  Nak).
- Legacy Nak (3): Response only, Type-Data = one octet per acceptable method type, or 0 for "none"; Length >= 6.
- GTC (6): Request = display message; Response = token/response text. MUST NOT carry cleartext passwords without a
  protected tunnel (inside IKEv2 SK it is encrypted, but RFC 7296 §2.16 still says non-key-generating methods SHOULD
  NOT be used; AUTH then uses SK_pi / SK_pr).
- Success (3) / Failure (4): 4 octets total.
- Key-generating methods MUST export MSK >= 64 octets and EMSK >= 64 (§7.10).

### 13.2 EAP-MSCHAPv2 encapsulation (draft-kamath-pppext-eap-mschapv2-02 §2)
Common header after the EAP header: `Type = 26 | OpCode (1) | MS-CHAPv2-ID (1) | MS-Length (2)`,
MS-Length = EAP Length - 5. MS-CHAPv2-ID is "typically" equal to the EAP Identifier (echo the value from the
Challenge in the Response).

| Packet | Dir | Layout after `Code Id Length Type(26)` |
|---|---|---|
| Challenge | Request (1) | OpCode 1, MS-CHAPv2-ID, MS-Length, Value-Size = 0x10, Challenge (16), Name (Length - 26 octets; the draft writes "Length - Value-Size - 10") |
| Response | Response (2) | OpCode 2, MS-CHAPv2-ID, MS-Length, Value-Size = 0x31, Response (49) = Peer-Challenge (16) \| Reserved (8 zero) \| NT-Response (24) \| Flags (1, zero), Name = user name (no NUL) |
| Success Request | Request (1) | OpCode 3, MS-CHAPv2-ID, MS-Length, Message = "S=<40 uppercase hex> M=<text>" |
| Success Response | Response (2) | OpCode 3 only; EAP Length = 6 |
| Failure Request | Request (1) | OpCode 4, MS-CHAPv2-ID, MS-Length, Message = "E=eeeeeeeeee R=r C=<32 hex> V=vvvvvvvvvv M=<text>" |
| Failure Response | Response (2) | OpCode 4 only; EAP Length = 6 |
| Change-Password | Response (2) | OpCode 7, MS-CHAPv2-ID, MS-Length, Data (582) = Encrypted-Password (516) \| Encrypted-Hash (16) \| Peer-Challenge (16) \| Reserved (8) \| NT-Response (24) \| Flags (2); EAP Length = 591 |

- Response lengths: EAP Length = 10 + 49 + len(Name) = 59 + len(Name).
- Peer MUST verify the authenticator response in Success (RFC 2759 §8.8); if missing or wrong "the peer MUST end
  the session without sending a response".
- Failure error codes: 646 ERROR_RESTRICTED_LOGON_HOURS, 647 ERROR_ACCT_DISABLED, 648 ERROR_PASSWD_EXPIRED,
  649 ERROR_NO_DIALIN_PERMISSION, 691 ERROR_AUTHENTICATION_FAILURE, 709 ERROR_CHANGING_PASSWORD. R=1 retry allowed
  (send a new Response with a new NT-Response computed on the new challenge C=), R=0 not (SHOULD send Failure
  Response). V is 3 for EAP MS-CHAP-V2. "Typically, errors 646, 647, and 649 are non-retryable (R=0)".
- Name in the Response may be "DOMAIN\user"; only the user part is hashed (RFC 2759 §8.2, draft §2.2).
- Typical successful flow (draft Appendix A): [Identity Req/Resp] → Challenge → Response → Success Request →
  Success Response → EAP Success.
- Security claims (§3): mutual auth yes, key derivation yes, dictionary attack protection NO, confidentiality no.

### 13.3 MS-CHAPv2 computations (RFC 2759 §8, errata 1924 and 391)
```
ChallengeHash(PeerChallenge, AuthenticatorChallenge, UserName) = SHA1(PeerChallenge | AuthChallenge | UserName)[0:8]
NtPasswordHash(Password) = MD4(Password encoded UTF-16LE, no terminator)          (errata 1924)
ChallengeResponse(Challenge8, PasswordHash16):
    Z = PasswordHash | 00 00 00 00 00   (21 octets)
    Response = DES-ECB(K(Z[0:7]), Challenge) | DES-ECB(K(Z[7:14]), Challenge) | DES-ECB(K(Z[14:21]), Challenge)
    K(7 octets) = expand 56 bits to 8 octets: each octet = next 7 bits << 1, low bit = odd parity (ignored by DES)
GenerateNTResponse = ChallengeResponse(ChallengeHash(...), NtPasswordHash(Password))   (24 octets)
PasswordHashHash = MD4(PasswordHash)
GenerateAuthenticatorResponse:
    Digest1 = SHA1(PasswordHashHash | NT-Response | Magic1)
    Digest2 = SHA1(Digest1 | ChallengeHash | Magic2)
    AuthenticatorResponse = "S=" + uppercase hex(Digest2)       (42 octets)
Magic1 (39) = "Magic server to client signing constant"
Magic2 (41) = "Pad to make it do more than one iteration"
```
RFC 3079 MPPE/MSK keys: see §7.3 above.

### 13.4 EAP-TTLSv0 basics (RFC 5281 §7-11; RFC 9427 §2.4)
- EAP Type 21. Packet after the EAP header: `Flags (1) | [TLS Message Length (4) if L] | Data`.
  Flags bits (MSB first): L = 0x80 length included, M = 0x40 more fragments, S = 0x20 start, bits 3-4 reserved,
  V = low 3 bits version (000 = TTLSv0) (§9.1).
- Start (S=1) comes from the server, may carry AVPs. Client answers with V set to min(server, own) (§9.2.1).
- Fragmentation (§9.2.2): all but last fragment M=1; first fragment of a multi-fragment message L=1 with total
  length; receiver of an M=1 packet MUST send an Acknowledgement (EAP-TTLS packet with only the Flags octet, L/M/S=0).
  After the server's final TTLS message the client sends an Acknowledgement so the server can send EAP-Success.
- Phase 1: a normal TLS handshake carried in Data (client verifies the server certificate). Phase 2: AVPs inside
  TLS application data (§10).
- AVP (§10.1): `AVP Code (4) | Flags (1: V=0x80 vendor, M=0x40 mandatory) | AVP Length (3, excludes padding) |
  [Vendor-ID (4)] | Data`, each AVP padded with zeros to a 4-octet boundary (§10.2). Vendor AVPs MUST use the V bit,
  not RADIUS attribute 26 (§11.2).
- AVP codes (RADIUS numbers, IANA radius-types): User-Name 1, User-Password 2, CHAP-Password 3, Reply-Message 18,
  State 24, CHAP-Challenge 60, EAP-Message 79. Microsoft vendor 311 (RFC 2548 §3): MS-CHAP-Error 2,
  MS-CHAP-Challenge 11, MS-CHAP2-Response 25, MS-CHAP2-Success 26, MS-CHAP2-CPW 27.
- Inner PAP (§11.2.5): send User-Name + User-Password (password NOT RADIUS-encrypted; SHOULD be NUL-padded to a
  multiple of 16). Server may answer with an Access-Challenge style round: tunnelled AVPs that include at least
  Reply-Message; the client answers with User-Name + User-Password carrying the new response (this is how a second
  factor / token prompt can work inside TTLS).
- Inner MS-CHAP-V2 (§11.2.4): challenge material = PRF-17("ttls challenge") (TLS 1.3: TLS-Exporter("ttls challenge",
  no context, 17)); first 16 octets = MS-CHAP-Challenge, 17th = Ident. Client sends User-Name, MS-CHAP-Challenge,
  MS-CHAP2-Response (Ident, Flags 0, Peer-Challenge, Reserved 0, NT-Response). Server returns MS-CHAP2-Success (42
  octet "S=..."); client verifies it and sends an EAP-TTLS packet with empty Data.
- Inner EAP (§11.2.1): each inner EAP packet goes in one EAP-Message AVP.
- MSK: see §7.4. With TLS 1.3, PAP/CHAP inner methods have no protected success indication unless the server sends
  a NewSessionTicket; peers MUST keep going until EAP-Success/Failure (RFC 9427 §2.4).

---

## 14. Client checklist derived from the above (for the engine design)

1. UDP socket to gateway:500 (or directly 4500 with the non-ESP marker). IKE_SA_INIT with SA (AES-GCM proposal +
   AES-CBC/HMAC proposal), KE (group 19 or 14 first; be ready for INVALID_KE_PAYLOAD), 32-octet Ni, NAT-D x2,
   IKEV2_FRAGMENTATION_SUPPORTED, optional SIGNATURE_HASH_ALGORITHMS (2,3,4).
2. Handle COOKIE (resend with cookie first) and INVALID_KE_PAYLOAD (new KE, full proposal list, MID 0, same SPIi).
3. Compute SKEYSEED and 7 keys; check NAT-D; if NAT detected (or always) switch to UDP 4500 for everything next.
4. IKE_AUTH #1 (MID 1): IDi (RFC822 or KEY_ID or FQDN), optional IDr, no AUTH (EAP), CP(CFG_REQUEST: IP4 address,
   IP4 DNS, [NETMASK, IP6 address, IP6 DNS, DNS_DOMAIN]), SAi2 (ESP, SPI = our inbound SPI, SN 0 [and 1]),
   TSi/TSr = everything, optional INITIAL_CONTACT, optional CERTREQ.
5. Response: verify CERT chain / pinned fingerprint, verify AUTH signature over ResponderSignedOctets, then run EAP
   (Identity if asked, MSCHAPv2 or TTLS), up to 10+ rounds, MIDs 2, 3, ...
6. After EAP Success: AUTH (method 2) with MSK, verify the responder's MSK AUTH, read CP(CFG_REPLY), SAr2, TSi/TSr.
7. Child SA keys from prf+(SK_d, Ni | Nr) of IKE_SA_INIT; our outbound key block first (we initiated).
8. ESP over UDP 4500 (or TCP); keepalive 0xFF every 20 s idle if behind NAT; DPD with empty INFORMATIONAL.
9. Respond to peer-initiated INFORMATIONAL (DPD, Delete) and CREATE_CHILD_SA (rekey: note the key order flips).
10. Delete: INFORMATIONAL with D(IKE) when the user disconnects.

---

## 15. Official test vectors (exact values)

All vectors below were copied from the cited document. "Verified" = recomputed locally from the RFC text.

### 15.1 MS-CHAPv2 (RFC 2759 §9.2): verified
```
UserName               = 55 73 65 72                                  ("User")
Password (UTF-16LE)    = 63 00 6C 00 69 00 65 00 6E 00 74 00 50 00 61 00 73 00 73 00   ("clientPass")
AuthenticatorChallenge = 5B 5D 7C 7D 7B 3F 2F 3E 3C 2C 60 21 32 26 26 28
PeerChallenge          = 21 40 23 24 25 5E 26 2A 28 29 5F 2B 3A 33 7C 7E
Challenge (8)          = D0 2E 43 86 BC E9 12 26
PasswordHash (16)      = 44 EB BA 8D 53 12 B8 D6 11 47 44 11 F5 69 89 AE
NT-Response (24)       = 82 30 9E CD 8D 70 8B 5E A0 8F AA 39 81 CD 83 54 42 33 11 4A 3D 85 D6 DF
PasswordHashHash (16)  = 41 C0 0C 58 4B D2 D9 1C 40 17 A2 A1 2F A5 9F 3F
AuthenticatorResponse  = "S=407A5589115FD0D6209F510FE9C04566932CDA56"
```
DES key expansion example (RFC 2759 §9.3 as corrected by verified erratum 391; verified):
```
Password "MyPw" (ASCII 4D 79 50 77), UTF-16LE 4D 00 79 00 50 00 77 00
NtPasswordHash         = FC 15 6A F7 ED CD 6C 0E DD E3 33 7D 42 7F 4E AC
first raw key  (7)     = FC 15 6A F7 ED CD 6C  -> parity-corrected 8: FD 0B 5B 5E 7F 6E 34 D9
second raw key (7)     = 0E DD E3 33 7D 42 7F  -> parity-corrected 8: 0E 6E 79 67 37 EA 08 FE
```

### 15.2 RFC 3079 MPPE keys from MS-CHAPv2 (§3.5.3, 128-bit): verified
Same inputs as 15.1.
```
MasterKey        = FD EC E3 71 7A 8C 83 8C B3 88 E5 27 AE 3C DD 31
SendStartKey128  = 8B 7C DC 14 9B 99 3A 1B A1 18 CB 15 3F 56 DC CB   (GetAsymmetricStartKey(..., TRUE, TRUE): server send, Magic3)
SendSessionKey128= 40 5C B2 24 7A 79 56 E6 E2 11 00 7A E2 7B 22 D4   (GetNewKeyFromSHA, MPPE only; not needed for IKEv2)
rc4(SendSessionKey128, "test message") = 81 84 83 17 DF 68 84 62 72 FB 5A BE
```
Derived by us (not official): Magic2 key (client send / server receive) = D5 F0 E9 52 1E 3E A9 58 96 45 E8 60 51 C8 22 26.
Candidate EAP-MSCHAPv2 MSK = that | 8B7CDC149B993A1BA118CB153F56DCCB | 00 x 32 (see §7.3; confirm by trace).

### 15.3 HMAC-SHA2 (RFC 4231 §4.2-4.8): spot-verified (TC1, TC5 SHA-256)
```
TC1  Key = 0b x 20            Data = 4869205468657265 ("Hi There")
  SHA-256 = b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7
  SHA-384 = afd03944d84895626b0825f4ab46907f15f9dadbe4101ec682aa034c7cebc59cfaea9ea9076ede7f4af152e8b2fa9cb6
  SHA-512 = 87aa7cdea5ef619d4ff0b4241a1d6cb02379f4e2ce4ec2787ad0b30545e17cdedaa833b7d6b8a702038b274eaea3f4e4be9d914eeb61f1702e696c203a126854
TC2  Key = 4a656665 ("Jefe")  Data = 7768617420646f2079612077616e7420666f72206e6f7468696e673f ("what do ya want for nothing?")
  SHA-256 = 5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843
  SHA-384 = af45d2e376484031617f78d2b58a6b1b9c7ef464f5a01b47e42ec3736322445e8e2240ca5e69e2c78b3239ecfab21649
  SHA-512 = 164b7a7bfcf819e2e395fbe73b56e0a387bd64222e831fd610270cd7ea2505549758bf75c05a994a6d034f65f8f0e6fdcaeab1a34d4a6b4b636e070a38bce737
TC3  Key = aa x 20            Data = dd x 50
  SHA-256 = 773ea91e36800e46854db8ebd09181a72959098b3ef8c122d9635514ced565fe
  SHA-384 = 88062608d3e6ad8a0aa2ace014c8a86f0aa635d947ac9febe83ef4e55966144b2a5ab39dc13814b94e3ab6e101a34f27
  SHA-512 = fa73b0089d56a284efb0f0756c890be9b1b5dbdd8ee81a3655f83e33b2279d39bf3e848279a722c806b485a47e67c807b946a337bee8942674278859e13292fb
TC4  Key = 0102030405060708090a0b0c0d0e0f10111213141516171819 (25)   Data = cd x 50
  SHA-256 = 82558a389a443c0ea4cc819899f2083a85f0faa3e578f8077a2e3ff46729665b
  SHA-384 = 3e8a69b7783c25851933ab6290af6ca77a9981480850009cc5577c6e1f573b4e6801dd23c4a7d679ccf8a386c674cffb
  SHA-512 = b0ba465637458c6990e5a8c5f61d4af7e576d97ff94b872de76f8050361ee3dba91ca5c11aa25eb4d679275cc5788063a5f19741120c4f2de2adebeb10a298dd
TC5  Key = 0c x 20            Data = 546573742057697468205472756e636174696f6e ("Test With Truncation"), output truncated to 128 bits
  SHA-256 = a3b6167473100ee06e0c796c2955552b
  SHA-384 = 3abf34c3503b2a23a46efc619baef897
  SHA-512 = 415fad6271580a531d4179bc891d87a6
TC6  Key = aa x 131           Data = "Test Using Larger Than Block-Size Key - Hash Key First"
       (54657374205573696e67204c6172676572205468616e20426c6f636b2d53697a65204b6579202d2048617368204b6579204669727374)
  SHA-256 = 60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54
  SHA-384 = 4ece084485813e9088d2c63a041bc5b44f9ef1012a2b588f3cd11f05033ac4c60c2ef6ab4030fe8296248df163f44952
  SHA-512 = 80b24263c7c1a3ebb71493c1dd7be8b49b46d1f41b4aeec1121b013783f8f3526b56d037e05f2598bd0fd2215d6a1e5295e64f73f63f0aec8b915a985d786598
TC7  Key = aa x 131           Data = "This is a test using a larger than block-size key and a larger than block-size data. The key needs to be hashed before being used by the HMAC algorithm."
  SHA-256 = 9b09ffa71b942fcb27635fbcd5b0e944bfdc63644f0713938a7f51535c3a35e2
  SHA-384 = 6617178e941f020d351e2f254e8fd32c602420feb0b8fb9adccebb82461e99c5a678cc31e799176d3860e6110c46523e
  SHA-512 = e37b6a775dc87dbaa4dfa9f96e5e3ffddebd71f8867289865df5a32d20cdc944b6022cac3c4982b10d5eeb55c3e4de15134676fb6de0446065c97440fa8c6a58
```
(The RFC 4868 §2.7.1 "PRF" vectors PRF-1..PRF-6 are exactly RFC 4231 TC1, TC2, TC3, TC4, TC6, TC7.)
TC6/TC7 data are the ASCII bytes of the quoted strings (no terminator).

### 15.4 HMAC-SHA2 truncated authenticators (RFC 4868 §2.7.2): AUTH256-1, -4 and both -4 errata cases verified
```
AUTH256-1 Key = 0b x 32, Data "Hi There"
  PRF = 198a607eb44bfbc69903a0f1cf2bbdc5ba0aa3f3d9ae3c1c7a3b1696a0b68cf7   HMAC-SHA-256-128 = 198a607eb44bfbc69903a0f1cf2bbdc5
AUTH256-2 Key = "JefeJefeJefeJefeJefeJefeJefeJefe" (4a656665 x 8), Data "what do ya want for nothing?"
  PRF = 167f928588c5cc2eef8e3093caa0e87c9ff566a14794aa61648d81621a2a40c6   HMAC-SHA-256-128 = 167f928588c5cc2eef8e3093caa0e87c
AUTH256-3 Key = aa x 32, Data = dd x 50
  PRF = cdcb1220d1ecccea91e53aba3092f962e549fe6ce9ed7fdc43191fbde45c30b0   HMAC-SHA-256-128 = cdcb1220d1ecccea91e53aba3092f962
AUTH256-4 Key = 0102...1f20 (32 octets 01..20), Data = cd x 50
  PRF = 372efcf9b40b35c2115b1346903d2ef42fced46f0846e7257bb156d3d7b30d3f   HMAC-SHA-256-128 = 372efcf9b40b35c2115b1346903d2ef4
AUTH384-1 Key = 0b x 48, Data "Hi There"
  HMAC-SHA-384-192 = b6a8d5636f5c6a7224f9977dcf7ee6c7fb6d0c48cbdee973   (RFC text mislabels it "384-128")
AUTH384-2 Key = 4a656665 x 12, Data "what do ya want for nothing?"
  HMAC-SHA-384-192 = 2c7353974f1842fd66d53c452ca42122b28c0b594cfb184d
AUTH384-3 Key = aa x 48, Data = dd x 50
  HMAC-SHA-384-192 = 809f439be00274321d4a538652164b53554a508184a0c316
AUTH384-4 Key = 0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f200a0b0c0d0e0f10111213141516171819, Data = cd x 50
  HMAC-SHA-384-192 = 5b540085c6e6358096532b2493609ed1cb298f774f87bb5c
  NOTE: erratum 5507 (held) proposes a different key (…2122…2f30); we verified that the ORIGINAL printed key gives
  the printed output and the erratum key does not. Use the key as printed.
AUTH512-1 Key = 0b x 64, Data "Hi There"
  HMAC-SHA-512-256 = 637edc6e01dce7e6742a99451aae82df23da3e92439e590e43e761b33e910fb8
AUTH512-2 Key = 4a656665 x 16, Data "what do ya want for nothing?"
  HMAC-SHA-512-256 = cb370917ae8a7ce28cfd1d8f4705d6141c173b2a9362c15df235dfb251b15454
AUTH512-3 Key = aa x 64, Data = dd x 50
  HMAC-SHA-512-256 = 2ee7acd783624ca9398710f3ee05ae41b9f9b0510c87e49e586cc9bf961733d8
AUTH512-4 Key = 0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f40 (64, per verified erratum 1785), Data = cd x 50
  HMAC-SHA-512-256 = 5e6688e5a3daec826ca32eaea224eff5e700628947470e13ad01302561bab108
  NOTE: the key printed in the RFC has an extra first line (80 octets); erratum 1785 is correct (we verified).
```

### 15.5 AES-CBC and ESP packets (RFC 3602 §4): cases 1 and 7 verified
```
Case 1  Key 06a9214036b8a15b512e03d534120006  IV 3dafba429d9eb430b422da802c9fac41
        PT "Single block msg"  CT e353779c1079aeb82708942dbe77181a
Case 2  Key c286696d887c9aa0611bbb3e2025a45a  IV 562e17996d093d28ddb3ba695a2e6f58
        PT 000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f
        CT d296cd94c2cccf8a3a863028b5e1dc0a7586602d253cfff91b8266bea6d61ab1
Case 3  Key 6c3ea0477630ce21a2ce334aa746c2cd  IV c782dc4c098c66cbd9cd27d825682c81
        PT "This is a 48-byte message (exactly 3 AES blocks)"
        CT d0a02b3836451753d493665d33f0e8862dea54cdb293abc7506939276772f8d5021c19216bad525c8579695d83ba2684
Case 4  Key 56e47a38c5598974bc46903dba290349  IV 8ce82eefbea0da3c44699ed7db51b7d9
        PT a0a1...dfdf (a0 through df, 64 octets)
        CT c30e32ffedc0774e6aff6af0869f71aa0f3af07a9a31a9c684db207eb0ef8e4e35907aa632c3ffdf868bb7b29d3d46ad83ce9f9a102ee99d49a53e87f4c3da55
```
Case 7, tunnel-mode ESP (no ICV in this vector; encryption only):
```
Key 0123456789abcdef0123456789abcdef   SPI 0x8765   Seq 2   IV f4e765244f6407adf13dc1380f673f37
Inner IP packet (84): 45000054 09040000 4001f988 c0a87b03 c0a87bc8
                      08009f76 a90a0100 b49c083d 02a20400 08090a0b 0c0d0e0f 10111213 14151617
                      18191a1b 1c1d1e1f 20212223 24252627 28292a2b 2c2d2e2f 30313233 34353637
Padding 01..0a (10 octets), Pad length 0a, Next header 04 (IPv4)
Plaintext to encrypt (96) = inner packet | 0102030405060708090a | 0a | 04
Outer IP header: 4500008c 09050000 4032f91e c0a87b03 c0a87bc8
SPI/Seq: 00008765 00000002
Encrypted (96): 773b5241 a4c44922 5e4f3ce5 ed611b0c 237ca96c f74a9301 3c1b0ea1 a0cf70f8
                e4ecaec7 8ac53aad 7a0f022b 859243c6 47752e94 a859352b 8a4d4d2d ecd136e5
                c177f132 ad3fbfb2 201ac990 4c74ee0a 109e0ca1 e4dfe9d5 a100b842 f1c22f0d
```
Case 8, tunnel-mode:
```
Key 0123456789abcdef0123456789abcdef  SPI 0x8765  Seq 5  IV 85d47224b5f3dd5d2101d4ea8dffab22
Plaintext (80): 45000044 090c0000 4001f990 c0a87b03 c0a87bc8 0800d63c aa0a0200 c69c083d
                a3de0300 ffffffff ffffffff ffffffff ffffffff ffffffff ffffffff ffffffff
                ffffffff 01020304 05060708 090a0a04
Encrypted (80): 15b92683 819596a8 047232cc 00f7048f e45318e1 1f8a0f62 ede3c3fc 61203bb5
                0f980a08 c9843fd3 a1b06d5c 07ff9639 b7eb7dfb 3512e5de 435e7207 ed971ef3
                d2726d9b 5ef6affc 6d17a0de cbb13892
```
Case 5, transport-mode (shows default padding 01..0e, pad length 0e, NH 01):
```
Key 90d382b410eeba7ad938c46cec1a82bf  SPI 0x4321  Seq 1  IV e96e8c08ab465763fd098d45dd3ff893
Plaintext (80): 08000ebd a70a0000 8e9c083d b95b0700 08090a0b 0c0d0e0f 10111213 14151617
                18191a1b 1c1d1e1f 20212223 24252627 28292a2b 2c2d2e2f 30313233 34353637
                01020304 05060708 090a0b0c 0d0e0e01
Encrypted (80): f663c25d 325c18c6 a9453e19 4e120849 a4870b66 cc6b9965 330013b4 898dc856
                a4699e52 3a55db08 0b59ec3a 8e4b7e52 775b07d1 db34ed9c 538ab50c 551b874a
                a269add0 47ad2d59 13ac19b7 cfbad4a6
```

### 15.6 AES-GCM ESP packets (draft-mcgrew-gcm-test-01 §4)
Format: nonce = salt | IV; aad = SPI | seq(4 or 8); packet = SPI | seq(low 32) | IV | ctext+tag. Tag 16 octets.
```
#1 (ESN, AES-128)
  key   4c80cdefbb5d10da906ac73c3613a634   spi 00004321   seq 8765432100000000 (64-bit)
  nonce 2e443b684956ed7e3b244cfe          (salt 2e443b68, IV 4956ed7e3b244cfe)
  plaintext (72) 45000048699a000080114db7c0a80102c0a801010a9bf15638d301000001000000000000045f736970045f756470037369700963796265726369747902646b000021000101020201
  aad   000043218765432100000000
  ctext+tag (88) fecf537e729d5b07dc30df528dd22b768d1b98736696a6fd348509fa13ceac34cfa2436f14a3f3cf65925bf1f4a13c5d15b21e1884f5ff6247aeabb786b93bce61bc17d768fd9732459018148f6cbe722fd04796562dfdb4
  packet (104) 00004321000000004956ed7e3b244cfe || ctext+tag
#2 (32-bit SN, AES-128)
  key   feffe9928665731c6d6a8f9467308308   spi 0000a5f8   seq 0000000a
  nonce cafebabefacedbaddecaf888
  plaintext (64) 4500003e698f000080114dccc0a80102c0a801010a980035002a2343b2d001000001000000000000037369700963796265726369747902646b00000100010001
  aad   0000a5f80000000a
  ctext+tag (80) deb22cd9b07c72c16e3a65beeb8df304a5a5897d33ae530f1ba76d5d114d2a5c3de81827c10e9a4f51330d0eec416642cfbb85a5b47e48a4ec3b9ba95d918bd183b70d3aa8bc6ee4c309e9d85a41ad4a
  packet (96) 0000a5f80000000afacedbaddecaf888 || ctext+tag
#3 (32-bit SN, AES-256)
  key   abbccddef00112233445566778899aababbccddef00112233445566778899aab   spi 4a2cbfe3   seq 00000002
  nonce 112233440102030405060708
  plaintext (52) 4500003069a6400080062690c0a801029389155e0a9e008b2dc57ee0000000007002400020bf0000020405b40101040201020201
  aad   4a2cbfe300000002
  ctext+tag (68) ff425c9b724599df7a3bcd510194e00d6a78107f1b0b1cbf06efae9d65a5d763748a637985771d347f0545659f14e99def842d8eb335f4eecfdbf831824b4c4915956c96
  packet (84) 4a2cbfe3000000020102030405060708 || ctext+tag
#4 (all-zero key, AES-128)
  key   00000000000000000000000000000000   spi 00000000   seq 00000001   nonce 000000000000000000000000
  plaintext (64) 4500003c99c500008001cb7a40679318010101010800075c020044006162636465666768696a6b6c6d6e6f707172737475767761626364656667686901020201
  aad   0000000000000001
  ctext+tag (80) 4688daf2f973a392732909c331d56d60f694abaa414b5e7ff5fdcdfff5e9a284456476492719ffb64de7d9dca1e1d894bc3bd57873ed4d181d19d4d5c8c18af3f821d496eeb096e98ad2b69e4799c71d
#12 (seq ffffffff, 4-octet plaintext = only pad/NH: "01020201")
  key   7d773d00c144c525ac619d18c84a3f47   spi 335467ae   seq ffffffff   nonce d966426743457e9182443bc6
  plaintext 01020201   aad 335467aeffffffff
  ctext+tag (20) 437f866bcb3f699fe9b0822bac961c4504bef270
  packet (36) 335467aeffffffff43457e9182443bc6437f866bcb3f699fe9b0822bac961c4504bef270
#14 (ESN ffffffffffffffff, AES-256)
  key   6c6567616c697a656d6172696a75616e61616e64646f69746265666f72656961   spi 796b6963   seq ffffffffffffffff
  nonce 7475726e333021696765746d
  plaintext (52) 45000030da3a00008001df3bc0a80005c0a800010800c6cd020007006162636465666768696a6b6c6d6e6f707172737401020201
  aad   796b6963ffffffffffffffff
  ctext+tag (68) f97ab2aa356d8edce17644ac8c78e25dd24dedbb29ebf1b64a274b39b49c3a864cd3d78ca4ae68a32b42458fb57dbe821dcc63b9d0937ba2945f669368661a329fb4c053
  packet (84) 796b6963ffffffff333021696765746d || ctext+tag
```
Note these vectors end the plaintext with padding "0102" + pad length 02 + next header 01/04 etc. (e.g. `01020201`
= pad 01 02, pad length 02, NH 01).

### 15.7 AES-GCM primitive (NIST CAVP gcmtestvectors.zip, CAVS 14.0; IV 96 bits, Tag 128)
```
gcmEncryptExtIV128 [PTlen=0,AADlen=0] Count 0
  Key 11754cd72aec309bf52f7687212e8957  IV 3c819d9a9bed087615030b65  PT -  AAD -  CT -  Tag 250327c674aaf477aef2675748cf6971
gcmEncryptExtIV128 [PTlen=128,AADlen=128] Count 0
  Key c939cc13397c1d37de6ae0e1cb7c423c  IV b3d8cc017cbb89b39e0f67e2
  PT c3b3c41f113a31b73d9a5cd432103069  AAD 24825602bd12a984e0092d3e448eda5f
  CT 93fe7d9e9bfd10348a5606e5cafa7354  Tag 0032a1dc85f1c9786925a2e71d8272dd
gcmEncryptExtIV128 [PTlen=408,AADlen=160] Count 0
  Key fe47fcce5fc32665d2ae399e4eec72ba  IV 5adb9609dbaeb58cbd6e7275
  PT 7c0e88c88899a779228465074797cd4c2e1498d259b54390b85e3eef1c02df60e743f1b840382c4bccaf3bafb4ca8429bea063
  AAD 88319d6e1d3ffa5f987199166c8a9b56c2aeba5a
  CT 98f4826f05a265e6dd2be82db241c0fbbbf9ffb1c173aa83964b7cf5393043736365253ddbc5db8778371495da76d269e5db3e
  Tag 291ef1982e4defedaa2249f898556b47
gcmEncryptExtIV256 [PTlen=0,AADlen=0] Count 0
  Key b52c505a37d78eda5dd34f20c22540ea1b58963cf8e5bf8ffa85f9f2492505b4  IV 516c33929df5a3284ff463d7  Tag bdc1ac884d332457a1d2664f168c76f0
gcmEncryptExtIV256 [PTlen=128,AADlen=128] Count 0
  Key 92e11dcdaa866f5ce790fd24501f92509aacf4cb8b1339d50c9c1240935dd08b  IV ac93a1a6145299bde902f21a
  PT 2d71bcfa914e4ac045b2aa60955fad24  AAD 1e0889016f67601c8ebea4943bc23ad6
  CT 8995ae2e6df3dbf96fac7b7137bae67f  Tag eca5aa77d51d4a0a14d9c51e1da474ab
gcmEncryptExtIV256 [PTlen=408,AADlen=160] Count 0
  Key 24501ad384e473963d476edcfe08205237acfd49b5b8f33857f8114e863fec7f  IV 9ff18563b978ec281b3f2794
  PT 27f348f9cdc0c5bd5e66b1ccb63ad920ff2219d14e8d631b3872265cf117ee86757accb158bd9abb3868fdc0d0b074b5f01b2c
  AAD adb5ec720ccf9898500028bf34afccbcaca126ef
  CT eb7cb754c824e8d96f7c6d9b76c7d26fb874ffbf1d65c6f64a698d839b0b06145dae82057ad55994cf59ad7f67c0fa5e85fab8
  Tag bc95c532fecc594c36d1550286a7a3f0
gcmDecrypt128 [PTlen=128,AADlen=128] Count 0 (PASS)
  Key 816e39070410cf2184904da03ea5075a  IV 32c367a3362613b27fc3e67e  CT 552ebe012e7bcf90fcef712f8344e8f1
  AAD f2a30728ed874ee02983c294435d3c16  Tag ecaae9fc68276a45ab0ca3cb9dd9539f  PT ecafe96c67a1646744f1c891f5e69427
gcmDecrypt128 [PTlen=128,AADlen=128] Count 1 (FAIL: must reject)
  Key 867fc5d5476d5008f0703d81e3622255  IV 22945529dff947c3c9264df7  CT 1c785025e5a2678e4b29b29276e395bb
  AAD 261a9efd4f32bc3d07c115b4edcf8adf  Tag 87fdf1261846164a950c37a3f2eea17d
```
Source URL: https://csrc.nist.gov/CSRC/media/Projects/Cryptographic-Algorithm-Validation-Program/documents/mac/gcmtestvectors.zip
(The McGrew/Viega GCM spec PDF referenced by RFC 4106 §9 returned 404 on csrc.nist.gov; the CAVP files replace it.)

### 15.8 IKEv2 KDF (NIST CAVP SP 800-135 ikev2.zip, CAVS 12.0): both cases verified
Formulas checked: SKEYSEED = prf(Ni|Nr, g^ir); DKM = prf+(SKEYSEED, Ni|Nr|SPIi|SPIr);
DKM(Child SA) = prf+(SK_d, Ni|Nr); DKM(Child SA D-H) = prf+(SK_d, g^ir(new)|Ni|Nr);
SKEYSEED(Rekey) = prf(SK_d, g^ir(new)|Ni|Nr); SK_d = first 32 octets of DKM (PRF output length). DKM lengths are
1056 bits = 132 octets.
```
[g^ir length = 1024] [SHA-256] [Ni length = 64] [Nr length = 64] COUNT = 0
Ni = ed80dc79912c32a9
Nr = 35fb6d1a3feac078
g^ir = 42968e5d0ccc3cfc5a3e4bc1bba370cea1fae0d54c49ccba34b2bee804beeb2e9e8c57a4e01bd45102cf2433aacc6cfec06792f363e5170e6aa6650274e906648e449d27a8f00b5b44261982c9835c748a751ec5138eaacc5e025661339538a61bf418e454699e19c32db8d9ce5dd86b220f1e89afc5872e68be36cb1a0c8866
g^ir (new) = a0747f546ca1460016828843c9a5bfaff64f1beb0eaf2a7999a55790851546b93e79600e9c1fd263f10e0a6b0b3efe0cada3e57e2352779156392d2372fe834e874d0aaecff5d1ba0dfb02b1b7848275e5f6951a57fda99d365acf3a8909139ad8714995ffc7aedd5764d36c1a6936afacfbee7ab74a44695019ee544c9b525f
SPIi = 47c1858efc932ea4
SPIr = 606fd05609624002
SKEYSEED = 37fde90b81d63692620f67367b62092e3efdc6a03509137d731004767ff35010
DKM = 63d018a08f7a29daa7d1f92cb63f45fa39bbaf5e5f1a78139613bb891e3e6bf9d0448f7c74e05b4c1a25c0b61e62c875e852f287e192d4ae536112db5197216400bd5e123470efc15f53161865fe8b19a1416518a157d651ecd2caddab6a9eae6a27a55af088218d5156edaa9789f934d9836ed43edffda553822202ff9f7d4860ca72e0
DKM(Child SA) = 1aa75030d18185338fb509c3822481bb1cc7cd96cfcc29e110287a4ea2798be3455edb260ab8b3d503cfbd24f36833ff3506c741dd641d4c425087221e231dc6058ce3c620424c884c631abd9482c9ffada2e11f0c011dc4cbb35dd2bdfb47a75bdd7cb1a7f2f81ffabe183d37ab5c43b16e9099adbb4f97385d6cdbb08ed54dae99585b
DKM(Child SA D-H) = c4bcf3b4f6cd8e1801700e4b0ce435e3688fffd3f8e8523e8099de77689b1600c1272e6bf908624df0742bc95843e3e83859d2e1f658b4b0217440e06b7f10069b3cc8f68f499069a3febff59a14ae2a8a5f40b664b4a6bcffe742ce257d41d170c295e3b92ae515e827b83399aab6484da2256715fa5a9b11f6f76c29e33f7168ac6e96
SKEYSEED(Rekey) = 42a6415f55def1a764aa3265a0ab43e3702d7d6d36a0bf2f19952816d6209a3a

[g^ir length = 2048 (group 14 size)] [SHA-256] [Ni length = 64] [Nr length = 64] COUNT = 0
Ni = fd21a5f19aaeaf1c
Nr = ad1dbfe988cd8e19
g^ir = 04a5ec6681555c3db1f24d8091117e05088b2cacb971cf2131488c78af0d0a9c85eb677c894bd14107fba6dca4f306515a1998579699b5e8ccb85fe3f82afca8802224e276eeadc3603d251bd1f41e3a48a7bea589f096086506f5b4ce5940d7483acce623da38d367fc177a7ed78a26cf2d991cf2b18697c6db1d3e8b4a6cadf22d0d5f24a26aeaa0c3e9e0e629b95060464c6ee0a8cbf2b106ba90d64891822b007e52b1b42bc2ff1a24cc6de994b69fdde86e31cac7bac7bca9193bcce00fccc08503b1f5c31c3063dcc3fc959698859a737b13a5b4313febfede221937ca6b16249afd48cdaad12f27094e05664ef86f8db92bce5260885888764958cc3e
g^ir (new) = 8f1b79bac8db2fb47efa9e50fad3a8c22bcc7cee4f4e21b2877b4526c7759012616369369c4e87f2f28f96066a89999ed72115cb14902fb03d95b37a459a4716414f946a5209e5cf7a5805ef2eb49f9c6c3d38ad23c6bc68c2085bb09a49e4b37606a4c76b0e6ac8b12416f2b7ebd796143380176a4f2493bc62dcf2c81c55346a9cac7552db289bf0a17692cc9f0f945ae2d445e4db8643c5d9dfc2dfb566f0118e94ac016a1ce011bb3d04d5346f0ba13b345c23b03e8da8e10b35b7c580eb55336ca981a9991dde06e05c49a81194e3834a579e6923244953136bbe542bf8d2b2662be623af864dc383073d29d7deba047fa3442cf4f47bc217c46c08668c
SPIi = af756945c2c6f7b7
SPIr = 27f77c62e66b1077
SKEYSEED = 7c7d22349a2b28f89c865d77f3a4e304ec5e13e7d3687e2aa61d53768b739591
DKM = 29686d4087b694697b02130f72434a53b8880904e17222705a911ac33a128284bc3f62cf870cf4702e8f330c2cf8dde7f893c5f974b67882a2666914198d09458cc5280ab4b7e3cc9f98fefbcd273b4f92bec2208401b8806bb02a1eecd94095b10eeba95f01907ab358b6aa84689f624c98b0f53c2b2cbe02970a064b7255274246981a
DKM(Child SA) = dbbbe03a7473e18c0db643a76da65d438ea97404f65ffcc6f79f474b49a28d8deb3b53d4f96ce5a5c2e6bd349aff65ac4b6ddafc26e372214ee2c94c423dcfebc81395f4ec54b62490e9bbfadedde53eb278190ae7384dd6564e6ddcf7ff569cd4cdde71d670858fec1299687ed1bfd87f96e0285553c9ecb3018a6ada805bb19bae3ae8
DKM(Child SA D-H) = a6aec7aa48c4dd8e9b6e8b8d3529165a88af23de06f9245840d1aaeff15cf210bd54a453af08522e4164754061b4d4b1395c0a67e943c6cacca65bc41236089eabbbcc57b1567eb4431263790060272e7e74912a880baa715f53a9a34099c579de5ca03a6605d68b9a4cd84a3c152563ff00aef2c49da53b71026ac43a51dda2cc193981
SKEYSEED(Rekey) = 1d8624953be8d8adff976f245665dfaee206d01d8a99667570ce83087b5693a8
```
Source: https://csrc.nist.gov/CSRC/media/Projects/Cryptographic-Algorithm-Validation-Program/documents/components/800-135testvectors/ikev2.zip
(also contains SHA-1, SHA-384, SHA-512 and 2048-bit-nonce cases, plus a file with the intermediate T1..T7 values).

### 15.9 ECDH and KE payloads (RFC 5903 §8)
Group 19:
```
i   = C88F01F5 10D9AC3F 70A292DA A2316DE5 44E9AAB8 AFE84049 C62A9C57 862D1433
gix = DAD0B653 94221CF9 B051E1FE CA5787D0 98DFE637 FC90B9EF 945D0C37 72581180
giy = 5271A046 1CDB8252 D61F1C45 6FA3E59A B1F45B33 ACCF5F58 389E0577 B8990BB3
KEi = 00000048 00130000 DAD0B653 94221CF9 B051E1FE CA5787D0 98DFE637 FC90B9EF
      945D0C37 72581180 5271A046 1CDB8252 D61F1C45 6FA3E59A B1F45B33 ACCF5F58
      389E0577 B8990BB3
r   = C6EF9C5D 78AE012A 011164AC B397CE20 88685D8F 06BF9BE0 B283AB46 476BEE53
grx = D12DFB52 89C8D4F8 1208B702 70398C34 2296970A 0BCCB74C 736FC755 4494BF63
gry = 56FBF3CA 366CC23E 8157854C 13C58D6A AC23F046 ADA30F83 53E74F33 039872AB
KEr = 00000048 00130000 D12DFB52 89C8D4F8 1208B702 70398C34 2296970A 0BCCB74C
      736FC755 4494BF63 56FBF3CA 366CC23E 8157854C 13C58D6A AC23F046 ADA30F83
      53E74F33 039872AB
girx (shared secret) = D6840F6B 42F6EDAF D13116E0 E1256520 2FEF8E9E CE7DCE03 812464D0 4B9442DE
giry = 522BDE0A F0D8585B 8DEF9C18 3B5AE38F 50235206 A8674ECB 5D98EDB2 0EB153A2
```
(KE payload bytes start with the generic header: Next Payload 00, flags 00, Length 0x0048, then group 0x0013 and
reserved 0x0000.)

Group 20:
```
i   = 099F3C70 34D4A2C6 99884D73 A375A67F 7624EF7C 6B3C0F16 0647B674 14DCE655 E35B5380 41E649EE 3FAEF896 783AB194
gix = 667842D7 D180AC2C DE6F74F3 7551F557 55C7645C 20EF73E3 1634FE72 B4C55EE6 DE3AC808 ACB4BDB4 C88732AE E95F41AA
giy = 9482ED1F C0EEB9CA FC498462 5CCFC23F 65032149 E0E144AD A0241815 35A0F38E EB9FCFF3 C2C947DA E69B4C63 4573A81C
KEi = 00000068 00140000 || gix || giy
r   = 41CB0779 B4BDB85D 47846725 FBEC3C94 30FAB46C C8DC5060 855CC9BD A0AA2942 E0308312 916B8ED2 960E4BD5 5A7448FC
grx = E558DBEF 53EECDE3 D3FCCFC1 AEA08A89 A987475D 12FD950D 83CFA417 32BC509D 0D1AC43A 0336DEF9 6FDA41D0 774A3571
gry = DCFBEC7A ACF31964 72169E83 8430367F 66EEBE3C 6E70C416 DD5F0C68 759DD1FF F83FA401 42209DFF 5EAAD96D B9E6386C
KEr = 00000068 00140000 || grx || gry
girx = 11187331 C279962D 93D60424 3FD592CB 9D0A926F 422E4718 7521287E 7156C5C4 D6031355 69B9E9D0 9CF5D4A2 70F59746
giry = A2A9F38E F5CAFBE2 347CF7EC 24BDD5E6 24BC93BF A82771F4 0D1B65D0 6256A852 C983135D 4669F879 2F2C1D55 718AFBB4
```
Group 21:
```
i   = 0037ADE9 319A89F4 DABDB3EF 411AACCC A5123C61 ACAB57B5 393DCE47 608172A0 95AA85A3 0FE1C295 2C6771D9 37BA9777
      F5957B26 39BAB072 462F68C2 7A57382D 4A52
gix = 0015417E 84DBF28C 0AD3C278 713349DC 7DF153C8 97A1891B D98BAB43 57C9ECBE E1E3BF42 E00B8E38 0AEAE57C 2D107564
      94188594 2AF5A7F4 601723C4 195D176C ED3E
giy = 017CAE20 B6641D2E EB695786 D8C94614 6239D099 E18E1D5A 514C739D 7CB4A10A D8A78801 5AC405D7 799DC75E 7B7D5B6C
      F2261A6A 7F150743 8BF01BEB 6CA3926F 9582
KEi = 0000008C 00150000 || gix || giy
r   = 0145BA99 A847AF43 793FDD0E 872E7CDF A16BE30F DC780F97 BCCC3F07 8380201E 9C677D60 0B343757 A3BDBF2A 3163E4C2
      F869CCA7 458AA4A4 EFFC311F 5CB15168 5EB9
grx = 00D0B397 5AC4B799 F5BEA16D 5E13E9AF 971D5E9B 984C9F39 728B5E57 39735A21 9B97C356 436ADC6E 95BB0352 F6BE64A6
      C2912D4E F2D0433C ED2B6171 640012D9 460F
gry = 015C6822 6383956E 3BD066E7 97B623C2 7CE0EAC2 F551A10C 2C724D98 52077B87 220B6536 C5C408A1 D2AEBB8E 86D678AE
      49CB5709 1F473229 6579AB44 FCD17F0F C56A
KEr = 0000008C 00150000 || grx || gry
girx = 01144C7D 79AE6956 BC8EDB8E 7C787C45 21CB086F A64407F9 7894E5E6 B2D79B04 D1427E73 CA4BAA24 0A347868 59810C06
       B3C715A3 A8CC3151 F2BEE417 996D19F3 DDEA
giry = 01B901E6 B17DB294 7AC017D8 53EF1C16 74E5CFE5 9CDA18D0 78E05D1B 5242ADAA 9FFC3C63 EA05EDB1 E13CE5B3 A8E50C3E
       B622E8DA 1B38E0BD D1F88569 D6C99BAF FA43
```

### 15.10 X25519 (RFC 7748 §5.2, §6.1)
```
Scalar  a546e36bf0527c9d3b16154b82465edd62144c0ac1fc5a18506a2244ba449ac4
u       e6db6867583030db3594c1a424b15f7c726624ec26b3353b10a903a6d0ab1c4c
out     c3da55379de9c6908e94ea4df28d084f32eccf03491c71f754b4075577a28552

Scalar  4b66e9d4d1b4673c5ad22691957d6af5c11b6421e0ea01d42ca4169e7918ba0d
u       e5210f12786811d3f4b7959d0538ae2c31dbe7106fc03c3efc4cd549c715a493
out     95cbde9476e8907d7aade45cb4b873f88b595a68799fa152e6f8f7647aac7957

Iterated (k = u = 0900..00; each round k' = X25519(k, u), u = old k):
  1 iteration      422c8e7a6227d7bca1350b3e2bb7279f7897b87bb6854b783c60e80311ae3079
  1,000 iterations 684cf59ba83309552800ef566f2f4d3c1c3887c49360e3875f2eb94d99532c51
  1,000,000        7c3911e0ab2586fd864497297e575e6f3bc601c0883c30df5f4dd2d24f665424

DH (§6.1):
  Alice private a   77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a
  Alice public      8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a
  Bob private b     5dab087e624a8a4b79e17f8b83800ee66f3bb1292618b6fd1c2f8b27ff88e0eb
  Bob public        de9edb7d7b7dc1b4d35b61c2ece435373f8343c85b78674dadfc7e146f882b4f
  Shared K          4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742
```
For IKEv2 group 31 the KE Key Exchange Data is the 32-octet public value exactly as above and g^ir = K.

### 15.11 ChaCha20-Poly1305 in ESP and in the IKEv2 SK payload (RFC 7634 Appendices A and B)
These are the only RFC vectors we found that exercise a complete AEAD SK payload including the AAD construction.
```
KEYMAT (36) = 808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9f a0a1a2a3
  key = 80..9f, salt = a0a1a2a3
IV = 1011121314151617 ; nonce = a0a1a2a3 1011121314151617

ESP (Appendix A): tunnel mode, SPI 01020304, Seq 5, no ESN, 198.51.100.5 -> 192.0.2.5 ICMP inside,
outer 203.0.113.153 -> 203.0.113.5, no NAT
  Inner packet (84, 16 octets per line):
    45000054a6f200004001e778c6336405
    c000020508005b7a3a080000553bec10
    0007362708090a0b0c0d0e0f10111213
    1415161718191a1b1c1d1e1f20212223
    2425262728292a2b2c2d2e2f30313233
    34353637
  Plaintext (88) = inner packet | 01 02 | 02 | 04     (pad 0102, pad length 2, NH 4)
  Ciphertext (88):
    24039428b97f417e3c13753a4f05087b
    67c352e6a7fab1b982d466ef407ae5c6
    14ee8099d52844eb61aa95dfab4c02f7
    2aa71e7c4c4f64c9befe2facc638e8f3
    cbec163fac469b502773f6fb94e664da
    9165b82829f641e0
  Poly1305 one-time key af1f412cc115adce5e4d0e29d5c130bf4631210e0fef7431c0454fe70fd7c2d1
  AAD 0102030400000005
  Tag 76aaa8266b7fb0f7b11b369907e1ad43
  Outer packet = 4500008c234500004032de5bcb007199cb007105 (outer IPv4, proto 50)
                 | 01020304 | 00000005 | 1011121314151617 | ciphertext | tag

IKEv2 (Appendix B): INFORMATIONAL request, one Notify SET_WINDOW_SIZE = 10, MID 9
  iSPI c0c1c2c3c4c5c6c7   rSPI d0d1d2d3d4d5d6d7
  Notify payload (12): 0000000c 00004001 0000000a
  Plaintext (13): 0000000c000040010000000a 00          (no padding, Pad Length 0)
  Ciphertext (13): 610394701f8d017f7c12924889
  AAD (32): c0c1c2c3c4c5c6c7 d0d1d2d3d4d5d6d7 2e202500 00000009 00000045 29000029
            (IKE header: Next 2e=SK, ver 20, exch 25=INFORMATIONAL, flags 00, MID 9, Length 0x45=69;
             SK header: Next 29=Notify, 00, Length 0x29=41 = 4 + 8 IV + 13 ct + 16 tag)
  Tag (16): 6b71bfe25236efd7cdc67066906315b2
  Encrypted payload (41): 29000029 | 1011121314151617 | 610394701f8d017f7c12924889 | tag
  Whole IKE message (69):
    c0c1c2c3c4c5c6c7 d0d1d2d3d4d5d6d7 2e202500 00000009 00000045
    29000029 1011121314151617 610394701f8d017f7c12924889 6b71bfe25236efd7cdc67066906315b2
```
Note the IKE header flags octet is 00 here (a request from the original responder); the example still shows the AAD
rule: header with final Length, then the 4-octet SK header, nothing else.

---

## 16. Gaps, ambiguities and things to confirm with a live trace

Items the RFCs leave open, or where our reading is an inference. "Trace" = a capture against a real FortiGate with
our own debug keys logged locally (never logged in the app).

1. EAP-MSCHAPv2 MSK layout (medium confidence): MSK[0:16] = Magic2 key, MSK[16:32] = Magic3 key; tail unknown
   but irrelevant for HMAC PRFs (§7.3). Microsoft's [MS-CHAP] MSK section is the normative source and is outside
   our allowed sources. Confirm by trace: success of the message 7 AUTH.
2. AEAD associated data for SKF fragments (§10): whether Fragment Number / Total Fragments are included in A is not
   stated in RFC 7383 or RFC 5282. Confirm by trace, or avoid by not sending fragments (use TCP or keep IKE_AUTH
   small) and trying both variants when receiving.
3. RFC 7427 (method 14) signature value encoding for ECDSA is not spelled out beyond "the actual signature value";
   the AlgorithmIdentifier is PKIX, which suggests the PKIX (DER) ECDSA signature format, unlike methods 9-11 which
   use raw r|s (RFC 4754 §7). Low confidence; confirm by trace if the gateway uses an ECDSA certificate.
4. Auth method 1 (RSA) hash: SHA-1 is the RFC default, but nothing forbids SHA-256 in the DigestInfo. The verifier
   must read the hash OID from the recovered DigestInfo and accept SHA-1/SHA-256/384/512.
5. Which EAP method a FortiGate proposes for IKEv2 remote access, whether it sends EAP-Identity first (RFC 7296 says
   it SHOULD NOT, but may), and how a one-time code is carried (EAP-GTC? TTLS inner PAP challenge? a second EAP
   round?). Not in RFCs. Check Fortinet docs, then trace.
6. Which IKE/ESP proposals, DH groups, lifetimes, DPD interval and NAT keepalive interval the gateway uses; whether
   it initiates rekeys (then our key order flips, §6.3) or reauthentication. Not in RFCs.
7. TCP transport: RFC 9329 requires port 4500 support and the "IKETCP" prefix; a vendor may use another port and/or
   wrap the stream in TLS (RFC 9329 Appendix A). Whether FortiGate uses the RFC 9329 prefix and framing unmodified,
   and on which port, is not in RFCs. Trace needed.
8. Whether the gateway sends CERT without our CERTREQ, how many certificates (chain), and whether it needs an IDr
   from us to pick its certificate (RFC 7427 §5). Trace.
9. INTERNAL_IP4_SUBNET / INTERNAL_DNS_DOMAIN / private-use CP attributes (16384+) the gateway may send; split
   tunnel may appear as narrowed TSr, as INTERNAL_IP4_SUBNET, or both (§3.15.2). Trace.
10. Window size: RFC default 1; whether the gateway sends SET_WINDOW_SIZE. Our engine can stay at 1 but MUST still
    answer the gateway's requests while ours is outstanding (§5.2).
11. MOBIKE (RFC 4555) was not studied here; if the gateway sends MOBIKE_SUPPORTED, network changes could use
    UPDATE_SA_ADDRESSES instead of a full reconnect. Out of scope for these notes.
12. ESN: whether the gateway accepts SN=0 only. Always offer SN 0 (and optionally 1); implement both code paths.
13. There are no official full IKE_SA_INIT / IKE_AUTH exchange vectors in the RFCs we read (only component vectors
    and RFC 7634 Appendix B for one SK payload). Unit tests for the message builder must be self-consistent
    round-trips plus the component vectors above.

## 17. Pitfalls collected while reading

- Do not include the 4-octet non-ESP marker (or the TCP Length) in the IKE Length, the ICV, or the AUTH octets.
- ECP KE data has no 0x04 prefix; shared secret is x only. MODP values are left-padded to 256 octets.
- Nonces go into SKEYSEED/prf+ without payload headers; IDs go into MACedID without the 4-octet generic header
  but WITH the ID Type and 3 reserved octets.
- AUTH signs the LAST IKE_SA_INIT request actually sent (after COOKIE / INVALID_KE retries).
- Retransmit cached bytes, do not re-encrypt.
- Message IDs: IKE_AUTH starts at 1 and increments per EAP round.
- KEYMAT order follows the initiator OF THAT EXCHANGE, not the IKE SA's original initiator.
- ESP SPI in our proposal is our INBOUND SPI; Delete lists our inbound SPIs.
- AES-GCM salt is the LAST 4 octets of each direction's key material; IV is 8 octets on the wire.
- IKE SK with AEAD: A covers header + SK header only; Length fields must be final before sealing.
- HMAC-SHA2 ICVs are truncated to half; PRFs are not truncated.
- RFC 4868 test vector errata: AUTH512-4 key per erratum 1785; AUTH384-4 key as printed (erratum 5507 is wrong).
- MS-CHAPv2 password is UTF-16LE (erratum 1924); username in ChallengeHash excludes any "DOMAIN\" prefix.
- With EAP-MSCHAPv2, never use EAP_ONLY_AUTHENTICATION; always verify the gateway's certificate AUTH in message 4.
