# FortiGate dial-up IPsec (IKEv2): implementation spec

Status: **draft, Phase 3a.** §2 (the reachability probe) is implemented and tested. §3 to §11
are the implementation spec for the full IKEv2 + ESP engine, written from the RFCs and Fortinet
public docs so an engineer who has never seen any IPsec code can build it from this document plus
the cited RFCs. Almost every FortiGate-specific detail past §2 is still **[confirm by trace]**:
build the pure cores and unit-test them against the RFC vectors first (§10), then confirm the
gateway's real behaviour on the VM bench (`ipsec-testbed.md`) before the engine relies on it.

## 0. Status and sources

### 0.1 What is confirmed vs what must be traced

- **Confirmed (public docs / RFCs / IANA):** the IKEv2 and ESP wire formats, code points, key
  derivation, AUTH computation, NAT-T and TCP framing, EAP and EAP-MSCHAPv2 packet formats, and
  all the crypto test vectors in §10. Fortinet's documented **defaults** (proposal lists, DH
  groups, lifetimes, transport modes, ports, the migration config) are confirmed from
  docs.fortinet.com and are cited inline.
- **[confirm by trace]:** every claim about what *our target FortiGate actually puts on the wire*
  as a dial-up responder. In particular: whether it answers a non-FortiClient initiator at all;
  PSK-vs-signature responder AUTH when EAP is on; the EAP method and how a one-time / emailed code
  is carried; the final AUTH key (EAP MSK vs PSK); the CFG attributes it returns; the DPD and
  NAT-keepalive intervals and formats; whether it sends proprietary vendor IDs / notifies; and the
  exact `ike-tcp-port` and TCP framing. These are marked **[confirm by trace]** throughout and
  collected in §11.
- **Not publicly documented:** Fortinet's proprietary EAP extension that carries FortiToken code /
  push prompts, the `VPN_NETWORK_ID` notify number, the FCT-UID / EMS payloads, and the
  EAP-MSCHAPv2 MSK tail. Where a fact exists only in an implementation's code, this spec says "not
  publicly documented" and never guesses a wire format from code.

### 0.2 Allowed sources (clean-room)

Only: IETF RFCs and drafts (rfc-editor.org, datatracker.ietf.org), Fortinet public documentation
(docs.fortinet.com, community.fortinet.com KB, fortinet.com), NIST/IANA registries, Android
developer docs, and redacted traces of Blanarch's own traffic against a gateway we control. Never
the code, repositories, READMEs or issue trackers of strongSwan, libreswan, Openswan,
racoon/ipsec-tools, iked, Linux xfrm, Android's IKE module, openfortivpn, OpenConnect, FortiClient
or WireGuard. Change this spec first, then the code; record every step in `PROVENANCE.md`. A live
trace is a black-box observation and is allowed input.

### 0.3 Primary references

| Ref | Topic |
|---|---|
| RFC 7296 | IKEv2 core: header, payloads, exchanges, keys, AUTH, EAP, NAT-T, errors |
| RFC 7383 | IKEv2 message fragmentation (SKF) |
| RFC 7427 | Digital Signature auth (method 14) |
| RFC 5282 | AEAD (AES-GCM/CCM) in the IKEv2 Encrypted payload |
| RFC 4303 | ESP |
| RFC 4106 | AES-GCM in ESP; RFC 3602 AES-CBC in ESP; RFC 7634 ChaCha20-Poly1305 |
| RFC 4868 / 2404 | HMAC-SHA2 / HMAC-SHA1-96 |
| RFC 3948 | UDP encapsulation of ESP, non-ESP marker, NAT keepalive |
| RFC 9329 | TCP encapsulation of IKE and ESP (obsoletes RFC 8229) |
| RFC 3526 / 5903 / 8031 / 7748 / 6989 | DH groups 14, 19-21, 31 and recipient checks |
| RFC 3748 | EAP; draft-kamath-pppext-eap-mschapv2-02 EAP-MSCHAPv2; RFC 2759 MS-CHAPv2; RFC 3079 MPPE keys |
| RFC 5281 / 9427 | EAP-TTLSv0 / with TLS 1.3 |
| RFC 8247 / 8221 | algorithm requirement levels for IKEv2 / ESP |
| IANA "IKEv2 Parameters", "EAP registry" | code points |

Fortinet anchors used repeatedly (full URLs in the research notes): the SSL-VPN-to-IPsec migration
guide (155142), the encryption-algorithms page (238852), the phase1 CLI reference (305883427), the
ESP-in-TCP page (351073), the custom-TCP-port dial-up page (567401), the EAP user-authentication
page (913974), and KB 219452 (MFA firmware floors / "proprietary EAP extensions").

---

## 1. Why

FortiOS 7.6.3 (April 2025) replaced SSL-VPN tunnel mode with dial-up IPsec on every
FortiGate model; old SSL-VPN settings are not migrated. Fortinet documents IKEv2 dial-up
with EAP user authentication (EAP-MSCHAPv2 by default; required for FortiToken prompts and
pushes) and IKE/ESP over TCP, whose default mode Fortinet calls RFC 8229 compliant
(RFC 9329 replaced RFC 8229 with the same wire format). Port 443 is common.

## 2. Reachability probe: does the server speak IKEv2?

Purpose: during setup, tell the user that a gateway which no longer offers SSL-VPN uses
IPsec. The probe only checks that an IKEv2 responder answers; it never completes an exchange.

### 2.1 Request: one IKE_SA_INIT (RFC 7296 §1.2, §3)

Sent in one UDP datagram to port 500 of the gateway. All integers are big-endian.

IKE header (§3.1), 28 bytes:

| Field | Size | Value |
|---|---|---|
| Initiator SPI | 8 | random, non-zero |
| Responder SPI | 8 | zero |
| Next Payload | 1 | 33 (SA) |
| Version | 1 | 0x20 (major 2, minor 0) |
| Exchange Type | 1 | 34 (IKE_SA_INIT) |
| Flags | 1 | 0x08 (Initiator) |
| Message ID | 4 | 0 |
| Length | 4 | total message length, header included |

Every payload starts with a generic payload header (§3.2): Next Payload (1), Critical bit
and reserved (1, zero), Payload Length (2, header included).

SA payload (§3.3), type 33, next payload 34 (KE). It carries one proposal:
- Proposal substructure: Last (1) = 0, reserved (1) = 0, Proposal Length (2), Proposal Num (1) = 1,
  Protocol ID (1) = 1 (IKE), SPI Size (1) = 0, Num Transforms (1) = 4.
- Four transform substructures (§3.3.2), each: Last-or-more (1: 3 = more, 0 = last),
  reserved (1), Transform Length (2), Transform Type (1), reserved (1), Transform ID (2),
  then attributes:
  1. Type 1 ENCR, ID 12 (AES-CBC), attribute Key Length (TV format, type 14 | 0x8000) = 256
  2. Type 2 PRF, ID 5 (PRF_HMAC_SHA2_256)
  3. Type 3 INTEG, ID 12 (AUTH_HMAC_SHA2_256_128)
  4. Type 4 DH, ID 14 (2048-bit MODP group), last

KE payload (§3.4), type 34, next payload 40 (Nonce): DH Group Num (2) = 14, reserved (2) = 0,
then 256 bytes of key exchange data. For a probe the data may be random: the responder
answers before it could notice.

Nonce payload (§3.9), type 40, next payload 0: 32 random bytes (§2.10 requires at least 16).

### 2.2 Reply

Any UDP datagram of at least 28 bytes whose Initiator SPI equals ours, whose Exchange Type is
34 and whose Flags have the Response bit (0x20) set means an IKEv2 responder is there. That
includes replies carrying only a Notify such as NO_PROPOSAL_CHOSEN (14), INVALID_KE_PAYLOAD
(17) or COOKIE (16390): all prove the server speaks IKEv2. No reply within 3 seconds means
"no answer" (UDP is lossy; this is a hint, never an error on its own).

**[confirm by trace]** that a FortiGate with a dial-up IKEv2 tunnel answers an unsolicited
IKE_SA_INIT on UDP 500 from an unknown peer.

---

## 3. Transports (UDP 500/4500, TCP per RFC 9329)

An IKE SA runs over exactly one transport for its whole life; ESP for its Child SAs follows the
same transport (RFC 9329 §5). Blanarch, being a userspace `VpnService` app, can never send raw IP
protocol 50, so **ESP is always UDP-encapsulated or TCP-encapsulated**, never bare
(android_feasibility.md §3.2, RFC 7296 §2.23).

### 3.1 UDP with NAT-T (RFC 7296 §2.23; RFC 3948)

- Start IKE_SA_INIT on **UDP 500** (matches the §2 probe and FortiClient's documented behaviour of
  starting on 500 and floating to 4500 when NAT is detected, KB 197873). The initiator MAY instead
  use **UDP 4500 from the first message** (RFC 7296 §2.23); whether FortiGate accepts an
  IKE_SA_INIT started directly on 4500 is **[confirm by trace]** (android_feasibility.md §7 item 3).
- On UDP 500 there is **no** non-ESP marker and no UDP-ESP.
- After NAT detection (or unconditionally, once past IKE_SA_INIT), move all IKE and ESP to **UDP
  4500** (RFC 7296 §2.23: if a NAT is detected the initiator MUST tunnel future IKE and ESP over
  4500). On 4500 (RFC 3948 §2.1-2.3, RFC 7296 §3.1):
  ```
  IKE:        UDP hdr | 00 00 00 00 (non-ESP marker) | IKE message
  ESP:        UDP hdr | ESP header (SPI != 0) ...
  Keepalive:  UDP hdr | FF                           (exactly one octet)
  ```
- Demux on receive at 4500: length 1 and 0xFF -> keepalive (ignore); first 4 octets zero -> IKE;
  else ESP (SPI is never 0, RFC 4303 §2.1). The 4-octet marker is **not** counted in the IKE
  Length, nor covered by the ICV or AUTH (RFC 7296 §3.1).
- FortiOS 7.6.5+ can move the IKE **UDP** port to 443 (`set ike-port 443`); with a custom UDP IKE
  port, traffic "remains on port 5000 since NAT-T floating to 4500 is only required when the IKE
  port is 500" (docs 33578). So the UDP port is a profile field, not a constant.

### 3.2 TCP (RFC 9329) and how Fortinet's transport modes fit

RFC 9329 framing (§3, §4): the TCP originator sends the 6 ASCII octets **`IKETCP`**
(`49 4b 45 54 43 50`) once at the start of every TCP connection; then every message is preceded by
a 2-octet big-endian **Length that includes the length field itself**:
```
IKE: Length(2) | 00 00 00 00 | IKE message      (Length = 2 + 4 + IKE length)
ESP: Length(2) | ESP packet                     (Length = 2 + ESP length; SPI != 0)
```
Length 0 or 1 -> fatal, close the connection; Length 2 (empty) -> silently ignore; max message
65533. Over TCP: do not retransmit requests (§6.2); the client reconnects on connection loss and
resends the outstanding request on the new connection, then sends an empty INFORMATIONAL
(§6.1); NAT-D is still sent, computed with the TCP ports (§6.5); NAT keepalives are not sent and
received ones are dropped (§6.6); liveness uses IKE INFORMATIONAL, not TCP keepalives (§6.7). TCP
encapsulation is **not negotiated in-band**; it is preconfigured on both ends (§2).

Fortinet mapping (docs 351073, 567401, migration guide 155142; all **[confirm by trace]** for
framing):
- `transport tcp` on the phase1: IKE negotiation and ESP are encapsulated in TCP, "in accordance
  with RFC 8229" (== RFC 9329 wire format). IKEv2 only; no NPU offload.
- `ike-tcp-port`: **default 4500 in 7.4.x and 7.6.0, 443 from 7.6.1**; upgraded boxes may keep
  4500 (docs 130421147). When it is not 4500, the IKE daemon "listens on port 4500 and port 11443
  while traffic enters on the ike-tcp-port and redirects to port 11443" (docs 351073) - internal
  to the gateway, invisible on the wire.
- `fortinet-esp`: MUST be **disable** (the default) for a third-party / FortiClient peer; `enable`
  is "non-standard TCP headers", FortiGate-to-FortiGate only. The engine speaks only RFC 9329
  framing.
- `transport auto` (7.6 default): the client "select[s] the transport automatically, preferring
  UDP over TCP", with fallback to TCP if UDP fails within `auto-transport-threshold` (default 15 s,
  docs 351073). On FortiOS 8.0, TCP is a VDOM service (`set ike-tcp-service enable`, default
  disable) and phase1 `transport` only exists for static/ddns tunnels; a dial-up VDOM with the
  service on "behave[s] as the Auto transport option" (docs 351073 / 567401 8.0).

### 3.3 Which to try first, and fallback (RFC 9329 §5.1; Fortinet "auto")

1. If the profile pins a transport, use it. Otherwise try **UDP** first (matches Fortinet's `auto`
   preference and RFC 9329 §5.1 "try UDP first unless the network is known to block UDP").
2. Send IKE_SA_INIT on UDP 500; retransmit at least once (RFC 9329 §5.1) with exponential backoff
   (RFC 7296 §2.1). If no IKE_SA_INIT response within the fallback window (start at Fortinet's 15 s
   `auto-transport-threshold`), fall back to **TCP**.
3. Switching UDP -> TCP needs a **new** IKE_SA_INIT with a **new** SPIi and recomputed NAT-D (RFC
   9329 §5.1); the half-finished UDP attempt is abandoned.
4. TCP connect target: the profile's `ike-tcp-port`, default 443 for our era, then 4500 as a second
   try (RFC 9329 mandates 4500 support). On a shared 443, SAML HTTPS and Agentless VPN / ZTNA take
   precedence on the gateway (docs 567401); the `IKETCP` prefix is how the gateway's listener tells
   an IKE-over-TCP stream from HTTPS (**[confirm by trace]**).
5. Remember the working transport per host so later reconnects skip the UDP timeout.

Map a transport dead end to `GATEWAY_UNREACHABLE` (both UDP and TCP failed to get any IKE
response); see §9.

---

## 4. IKE_SA_INIT

Exchange (RFC 7296 §1.2, §2.6):
```
HDR(SPIi, 0, MID 0, IKE_SA_INIT, I), SAi1, KEi, Ni,
    N(NAT_DETECTION_SOURCE_IP), N(NAT_DETECTION_DESTINATION_IP),
    [N(IKEV2_FRAGMENTATION_SUPPORTED)], [N(SIGNATURE_HASH_ALGORITHMS)]   -->
                <-- HDR(SPIi, SPIr, MID 0, R), SAr1, KEr, Nr, [CERTREQ],
                    N(NAT_DETECTION_*), [N(IKEV2_FRAGMENTATION_SUPPORTED)],
                    [N(SIGNATURE_HASH_ALGORITHMS)], [N(MULTIPLE_AUTH_SUPPORTED)]
```
Header, generic payload header and all payload byte layouts: RFC 7296 §3.1-§3.4, §3.9, §3.10, as
already used by the §2 probe. NAT-D notifies go just after Ni/Nr and before any CERTREQ (§2.23).

### 4.1 The proposals to offer (Fortinet-compatible default set)

FortiGate's IKEv2 phase1 default proposal is
`aes128-sha256 aes256-sha256 aes128gcm-prfsha256 aes256gcm-prfsha384 chacha20poly1305-prfsha256`
and it "matches the most secure proposal" (docs 238852). In IKEv2 the AEAD suites still need a PRF
but no INTEG. Fortinet dial-up examples commonly set `dhgrp 20 21` (docs 567401), with phase1
default `dhgrp 14`.

Offer these, most-preferred first, as **separate proposals** (AEAD and non-AEAD cannot share one
proposal, RFC 7296 §3.3 / RFC 5282 §8). Transform IDs from IANA (rfc_details.md §1). Put a full DH
group set in each proposal so an INVALID_KE_PAYLOAD retry keeps downgrade protection (§4.4).

| # | ENCR (type 1) | keylen attr | PRF (type 2) | INTEG (type 3) | DH (type 4) |
|---|---|---|---|---|---|
| 1 | AES_GCM_16 (20) | 256 | HMAC_SHA2_384 (6) | none (AEAD) | 20,19,21,14 |
| 2 | AES_GCM_16 (20) | 128 | HMAC_SHA2_256 (5) | none (AEAD) | 20,19,21,14 |
| 3 | CHACHA20_POLY1305 (28) | none | HMAC_SHA2_256 (5) | none (AEAD) | 20,19,21,14 |
| 4 | AES_CBC (12) | 256 | HMAC_SHA2_256 (5) | HMAC_SHA2_256_128 (12) | 20,19,21,14 |
| 5 | AES_CBC (12) | 128 | HMAC_SHA2_256 (5) | HMAC_SHA2_256_128 (12) | 20,19,21,14 |

Notes: ChaCha20-Poly1305 has a fixed 256-bit key, so **no** Key Length attribute (RFC 7634 §2). AES
keylen is TV-form attribute type 14 (`80 0E 01 00` for 256, `80 0E 00 80` for 128; rfc_details.md
§3.1). "To offer several key sizes, repeat the ENCR transform, one attribute each" (§3.3.5) - if
you would rather offer 128 and 256 in one proposal, use two ENCR transforms; keeping them in
separate proposals is simpler and matches the table. RFC 8247 requirement levels back this set:
AES_CBC MUST, AES_GCM_16 SHOULD, ChaCha20 SHOULD; PRF_HMAC_SHA2_256 MUST; DH 14 MUST, 19 SHOULD.
The exact suite the gateway picks is **[confirm by trace]**; the trial VM may only offer DES (see
`ipsec-testbed.md`), which is a lab-only debug transform, never shipped.

The initiator MUST check the returned SAr1 matches one of its proposals or terminate (§3.3.6).

### 4.2 KE encodings per group (RFC 7296 §3.4)

The KE payload's Group Num MUST match a group in the first proposal and SHOULD equal its first DH
group (§3.4). Encodings:
- **MODP group 14** (RFC 3526 §3): 256-octet big-endian public value, left zero-padded. g^ir is
  256 octets, same padding. Recipient check 1 < r < p-1 (RFC 6989 §2.1).
- **ECP groups 19/20/21** (RFC 5903 §7): KE data = x | y, each fixed width 32 / 48 / 66 octets, no
  0x04 prefix. g^ir = **x only**, fixed width. Java/Android `ECPoint` adds a 0x04 prefix - strip on
  send, re-add on parse. Recipient MUST verify the peer point is on the curve (RFC 6989 §2.3).
- **Curve25519 group 31** (RFC 8031, RFC 7748 §6.1): KE data = 32-octet little-endian u; g^ir =
  X25519(d, peer) 32 octets, used as-is. Mask the MSB of the last received octet; MAY reject an
  all-zero result. (Android has XDH only from API 33; use Bouncy Castle below that,
  android_feasibility.md §1.5.)

### 4.3 Nonce, NAT detection, fragmentation notify

- **Nonce Ni** (§3.9, §2.10): 32 random octets covers "half the PRF key size" for every PRF we
  offer (SHA2-512 wants 32); never reuse.
- **NAT detection** (§2.23): NAT_DETECTION_SOURCE_IP data = SHA-1(SPIi | SPIr | source IP | source
  port); NAT_DETECTION_DESTINATION_IP = SHA-1(SPIi | SPIr | dest IP | dest port). SPIs in header
  order (SPIr = 0 in the first request), IP 4 or 16 octets, port 2 octets, all network order. On
  the reply, recompute with the addresses/ports actually seen: if DESTINATION_IP does not match, we
  are behind a NAT (start keepalives, move to 4500); if no SOURCE_IP matches, the peer is behind a
  NAT. If a NAT is detected both sides MUST UDP-encapsulate ESP (§2.23). A client MAY deliberately
  send a non-matching SOURCE_IP hash to make the gateway believe there is a NAT and thus
  UDP-encapsulate its ESP (android_feasibility.md §3.2) - **[confirm by trace]** before relying on
  it.
- **IKEV2_FRAGMENTATION_SUPPORTED** (16430, no data, RFC 7383 §2.3): send it so large IKE_AUTH
  messages (certificates) can be fragmented; FortiGate advertises it (`frag-rfc`, docs 144926).
  Only usable if both sides sent it; never fragment IKE_SA_INIT (§2.2).
- **SIGNATURE_HASH_ALGORITHMS** (16431, RFC 7427 §4): optional; send hash IDs 2,3,4 (SHA2-256/384/
  512) to permit responder auth method 14. Required only if the gateway authenticates with method
  14 rather than method 1/2 (§6).

### 4.4 COOKIE and INVALID_KE_PAYLOAD retries (RFC 7296 §2.6, §2.6.1)

- **COOKIE** (16390): response is `HDR(SPIi,0), N(COOKIE)` with 1..64 octets. Retry IKE_SA_INIT
  with N(COOKIE) as the **first** payload, everything else unchanged, same SPIi, MID still 0. Limit
  cookie rounds with exponential backoff. Over TCP the responder SHOULD NOT send a cookie without a
  puzzle (RFC 9329 §6.3).
- **INVALID_KE_PAYLOAD** (17): data = 2-octet accepted group. Retry with KEi in that group, still
  offering the **full** proposal set (downgrade protection), same SPIi, MID 0. The shorter combined
  flow (cookie kept across retries) is RFC 7296 §2.6.1; support it but do not require it of the
  peer.
- The AUTH later (§6) signs the **last** IKE_SA_INIT request actually sent, after these retries
  (§2.15).
- **NO_PROPOSAL_CHOSEN** (14) in IKE_SA_INIT is fatal for this attempt -> `PROTOCOL` (or, once TCP
  and UDP are exhausted, `GATEWAY_UNREACHABLE`); IKE_SA_INIT errors are unauthenticated, so retry
  for a while before giving up except for the defined corrective actions above (§2.21.1).

After a successful IKE_SA_INIT both sides derive the keys (§5).

---

## 5. Key derivation and SK payload

### 5.1 prf, prf+, SKEYSEED (RFC 7296 §2.13, §2.14)

```
prf+(K,S) = T1 | T2 | ... ; T1=prf(K, S|0x01); Tn=prf(K, T(n-1)|S|n)   (counter is ONE octet)
SKEYSEED  = prf(Ni | Nr, g^ir)
{SK_d | SK_ai | SK_ar | SK_ei | SK_er | SK_pi | SK_pr} = prf+(SKEYSEED, Ni | Nr | SPIi | SPIr)
```
Ni, Nr are nonce values only (no headers); SPIi, SPIr are the 8-octet IKE SPIs of this SA. g^ir is
big-endian, zero-padded to the modulus length for MODP, x-coordinate fixed width for ECP, the raw
32 octets for X25519 (§4.2). SK_ai/SK_ei protect messages from the original initiator (us);
SK_ar/SK_er the other direction. Verified against the NIST CAVP IKEv2 KDF vectors (§10.6).

### 5.2 Every key and its length

| IKE suite | SK_d | SK_ai | SK_ar | SK_ei | SK_er | SK_pi | SK_pr | prf+ total |
|---|---|---|---|---|---|---|---|---|
| AES-CBC-256 / SHA2-256-128 / PRF-SHA2-256 | 32 | 32 | 32 | 32 | 32 | 32 | 32 | 224 |
| AES-CBC-128 / SHA1-96 / PRF-SHA1 | 20 | 20 | 20 | 16 | 16 | 20 | 20 | 132 |
| AES-GCM-16-256 / PRF-SHA2-256 | 32 | 0 | 0 | 36 | 36 | 32 | 32 | 168 |
| AES-GCM-16-128 / PRF-SHA2-256 | 32 | 0 | 0 | 20 | 20 | 32 | 32 | 136 |
| ChaCha20-Poly1305 / PRF-SHA2-256 | 32 | 0 | 0 | 36 | 36 | 32 | 32 | 168 |
| AES-CBC-256 / SHA2-384-192 / PRF-SHA2-384 | 48 | 48 | 48 | 32 | 32 | 48 | 48 | 304 |

For AEAD IKE suites SK_ai/SK_ar are length 0 and SK_ei/SK_er are `key || salt`, salt = the **last 4
octets** (RFC 5282 §7.1, RFC 7634 §3). SK_d/SK_pi/SK_pr are the PRF output length; SK_ai/SK_ar are
the INTEG key length (0 with AEAD); SK_ei/SK_er the ENCR key length (+ salt for AEAD). Cut keys from
the prf+ stream in the order above without regard to boundaries (§2.13).

### 5.3 SK payload encrypt/decrypt

**Non-AEAD (AES-CBC + HMAC), RFC 7296 §3.14:**
```
| generic header (Next Payload = first inner type) | IV (16 for AES-CBC) |
| encrypted{ inner payloads | Padding | Pad Length(1) } | ICV |
```
IV is new and unpredictable per message. Padding aligns (payloads + Padding + Pad Length) to the
block size; receiver accepts any aligning length. **Encrypt then MAC**: the ICV covers the whole
IKE message from the first header octet through Pad Length, so the IKE Length and SK Payload Length
must already include the ICV length. Encrypt key SK_ei / decrypt SK_er (from the original
initiator's view); MAC key SK_ai / SK_ar. HMAC-SHA2 ICVs are truncated to half the hash output
(§10.2). Verify the ICV (constant-time) before decrypting on receive.

**AEAD (AES-GCM, ChaCha20-Poly1305), RFC 5282 §3-5, RFC 7634 §3:**
```
| generic header | IV (8 octets) | Ciphertext (includes the 16-octet tag) |
```
Plaintext P = inner payloads | Padding | Pad Length (send Pad Length 0, no padding). Nonce N = salt
(4, from the end of SK_ei/SK_er) | IV (8) = 12 octets. **Associated data A** = from the first IKE
header octet through the SK payload's 4-octet generic header (nothing after); with SK first, A is 32
octets. The Length fields inside A (IKE Length, SK Payload Length) must be the **final** values
(include IV and tag) before sealing. AES-GCM tag is 16 octets (transform 20). Worked AEAD SK example
with exact AAD bytes: RFC 7634 Appendix B, reproduced in §10.5.

**Fragmentation (SKF, type 53), RFC 7383 §2.5:** same protection as SK but per chunk, with a 2-octet
Fragment Number and 2-octet Total after the generic header; prepend the original IKE header (only
Length and Next Payload changed). Whether the 4 Fragment/Total octets are part of the AEAD A is not
stated in the RFCs (rfc_details.md §10) - avoid sending fragments (keep IKE_AUTH small or use TCP,
RFC 9329 §7.5 says SHOULD NOT fragment over TCP) and, when receiving, be prepared to try both A
variants. **[confirm by trace]**.

---

## 6. IKE_AUTH with EAP

The client asks for EAP by **omitting AUTH** from the first IKE_AUTH request (RFC 7296 §2.16).
Sequence as the client sees it (§2.16, §2.2, §2.19):
```
msg3 HDR(MID 1), SK{ IDi, [CERTREQ,] [IDr,] [N(INITIAL_CONTACT),]
                     CP(CFG_REQUEST), SAi2, TSi, TSr }              (no AUTH)   -->
msg4              <-- HDR(MID 1), SK{ IDr, [CERT,] AUTH, EAP(Request) }
msg5 HDR(MID 2), SK{ EAP(Response) }                                            -->
msg6              <-- HDR(MID 2), SK{ EAP(Request) | EAP(Success) }
     ... repeat, MID 3,4 ... (support at least 10 IKE_AUTH round trips) ...
msg7 HDR(MID n), SK{ AUTH }                                                     -->
msg8              <-- HDR(MID n), SK{ AUTH, CP(CFG_REPLY), SAr2, TSi, TSr }
```
Message IDs: IKE_AUTH starts at 1 and increments per round (§2.2). Keep window 1 unless the gateway
sends SET_WINDOW_SIZE, but still answer the gateway's own requests while ours is outstanding
(§2.3). The gateway MUST send EAP Success or Failure at the end; an EAP Failure ends the attempt
without an AUTHENTICATION_FAILED notify (§2.21).

### 6.1 IDi format (RFC 7296 §3.5)

`| ID Type(1) | RESERVED(3) | data |`. For EAP, IDi is mostly for AAA routing (§2.16). Use
**ID_RFC822_ADDR (3)** when the username is a NAI with a realm (`user@realm`), else **ID_FQDN (2)**
or **ID_KEY_ID (11)** for a bare username; a configured local ID overrides. FortiGate examples show
the initiator IDi as the client IP or a configured local ID (docs 951346) - **[confirm by trace]**
whether the gateway cares about the IDi type when `eap-identity send-request` is set (it then also
asks for the identity again inside EAP).

### 6.2 CP request attributes (RFC 7296 §3.15; §7)

Send CP(CFG_REQUEST) **before** SAi2 in msg3, with empty (Length-0) attributes: INTERNAL_IP4_ADDRESS
(1), INTERNAL_IP4_NETMASK (2), INTERNAL_IP4_DNS (3), and for split DNS INTERNAL_DNS_DOMAIN (25). At
least one INTERNAL_IP4_ADDRESS is mandatory (§2.19). Details and the reply handling are in §7.

### 6.3 Authenticating the responder, and how Blanarch verifies it

FortiGate has two documented responder-auth designs (both **[confirm by trace]** for our gateway):

1. **PSK responder + EAP** (`authmethod psk`, the migration default). Msg4 carries IDr + AUTH
   **method 2 (Shared Key MIC)** + EAP-Request/Identity, with **no CERT** (decoded from
   Fortinet-published hex, fortinet_dialup_ikev2.md §6.1). This is outside RFC 7296 §2.16, which
   requires a public-key-signature responder with EAP; a strict RFC client would refuse it. If we
   choose to support it, the PSK is a per-tunnel secret shared by all users and must be a profile
   field; verifying method-2 AUTH means recomputing `prf(prf(PSK,"Key Pad for IKEv2"),
   ResponderSignedOctets)` and comparing (§6.6). Treating a shared PSK as server authentication is
   weak; prefer design 2 and pin the certificate.
2. **Signature responder** (`authmethod signature` + a server certificate). Msg4 carries IDr + CERT
   (+ chain) + AUTH **method 1 (RSA), 9-11 (ECDSA) or 14 (Digital Signature)** + EAP-Request. This
   is the RFC-compliant design and the one FortiClient's built-in Android client requires (an **RSA**
   server cert, full chain, `peertype any`, `cert-id-validation disable`; docs 189805).

**Blanarch's verification.** Because EAP-MSCHAPv2 is not dictionary-attack resistant, the client
MUST NOT use EAP_ONLY_AUTHENTICATION and MUST verify the responder's msg4 AUTH before trusting
anything (RFC 5998 §4; RFC 7296 §2.16). Reuse the SSL-VPN trust model: the user confirms the
**SHA-256 of the leaf certificate (DER)** on first use, and it is pinned per host (CLAUDE.md
architecture rules; SSL-VPN spec §2). So for design 2: parse the CERT chain (encoding 4, up to four
certs, first cert holds the AUTH key, §3.6), check the leaf fingerprint against the pin
(`CERT_MISMATCH` on change, `CERT_UNTRUSTED` if no pin and not system-trusted), then verify the
signature over ResponderSignedOctets (§6.6). For design 1 there is no certificate; the "identity"
is the PSK, which is far weaker - surface that in the UI. Verify method 1's hash by reading the OID
from the recovered PKCS#1 DigestInfo (accept SHA-1/256/384/512); method 14 uses the RFC 7427
AlgorithmIdentifier blobs in §3.6 of rfc_details.md and requires SIGNATURE_HASH_ALGORITHMS from
both sides.

### 6.4 EAP-MSCHAPv2 in full (RFC 3748; draft-kamath-pppext-eap-mschapv2-02; RFC 2759; RFC 3079)

EAP packet (RFC 3748 §4): `| Code(1) | Identifier(1) | Length(2) | [Type(1) | Type-Data] |`. Codes 1
Request, 2 Response, 3 Success, 4 Failure; Success/Failure are exactly 4 octets. A Response
Identifier MUST equal the Request's. EAP-MSCHAPv2 is Type **26**, with a common header after the EAP
header: `Type=26 | OpCode(1) | MS-CHAPv2-ID(1) | MS-Length(2)`, MS-Length = EAP Length - 5;
MS-CHAPv2-ID echoes the value from the Challenge.

Packet layouts (draft-kamath §2):

| Packet | Dir | After `Code Id Length Type(26)` |
|---|---|---|
| Challenge | Req(1) | OpCode 1, ID, MS-Length, Value-Size=0x10, **Challenge(16)**, Name(rest) |
| Response | Resp(2) | OpCode 2, ID, MS-Length, Value-Size=0x31, **Response(49)**, Name(username, no NUL) |
| Success Req | Req(1) | OpCode 3, ID, MS-Length, Message = "S=<40 hex> M=<text>" |
| Success Resp | Resp(2) | OpCode 3 only; EAP Length 6 |
| Failure Req | Req(1) | OpCode 4, ID, MS-Length, Message = "E=eeeeeeeeee R=r C=<32 hex> V=vvvvvvvvvv M=<text>" |
| Failure Resp | Resp(2) | OpCode 4 only; EAP Length 6 |

Response(49) = Peer-Challenge(16) | Reserved(8 zero) | NT-Response(24) | Flags(1 zero). EAP Length =
59 + len(Name).

Computations (RFC 2759 §8, errata 1924/391; verified vectors in §10.4):
```
NtPasswordHash(pw)      = MD4(pw as UTF-16LE, no terminator)              (MD4: Bouncy Castle / RFC 1320)
ChallengeHash(pc,ac,un) = SHA1(PeerChallenge | AuthChallenge | UserName)[0:8]   (UserName excludes any "DOMAIN\")
ChallengeResponse(chal8, hash16):
    Z = hash16 | 00 00 00 00 00                        (21 octets)
    R = DES-ECB(K(Z[0:7]), chal8) | DES-ECB(K(Z[7:14]), chal8) | DES-ECB(K(Z[14:21]), chal8)
    K(7 octets) -> 8: each output octet = next 7 bits << 1 (low parity bit ignored by DES)
GenerateNTResponse    = ChallengeResponse(ChallengeHash(pc,ac,un), NtPasswordHash(pw))   (24 octets)
PasswordHashHash      = MD4(NtPasswordHash(pw))
AuthenticatorResponse: Digest1 = SHA1(PasswordHashHash | NT-Response | Magic1)
                       Digest2 = SHA1(Digest1 | ChallengeHash | Magic2)
                       "S=" + uppercase hex(Digest2)
  Magic1 = "Magic server to client signing constant"
  Magic2 = "Pad to make it do more than one iteration"
```
Client flow: receive Challenge -> generate a random 16-octet Peer-Challenge, compute NT-Response,
send Response with the username -> receive Success Request -> **verify the authenticator response
"S="** (RFC 2759 §8.8; if missing or wrong, end the session without a response) -> send Success
Response -> the gateway sends EAP Success in the enclosing IKEv2 message. On a Failure Request, R=1
means a retry is allowed with a new NT-Response over the new challenge C=; R=0 is terminal (map by
error code: 691 -> AUTH_REJECTED; see §9). Never log the password, the NT-Response, or the hashes
(they allow an offline password guess).

**MSK derivation (RFC 3079 §3.3/§3.4; medium confidence, [confirm by trace]).** Two 16-octet keys:
```
MasterKey = SHA1(PasswordHashHash | NT-Response | "This is the MPPE Master Key")[0:16]
Key(s)    = SHA1(MasterKey | 00 x40 | s | F2 x40)[0:16]
  Magic2(84) = "On the client side, this is the send key; on the server side, it is the receive key."
  Magic3(84) = "On the client side, this is the receive key; on the server side, it is the send key."
MSK[0:16]  = Key(Magic2)   MSK[16:32] = Key(Magic3)   MSK[32:64] = filler (most likely 32 zero octets)
```
The 64-octet MSK's byte order comes from draft-ietf-emu-rfc7170bis and RFC 5422: EAP-MSCHAPv2 MSK =
MasterReceiveKey | MasterSendKey (the first/second 16-octet halves are swapped relative to
EAP-FAST-MSCHAPv2). The tail is undocumented in allowed sources but does not affect the IKEv2 AUTH:
`prf(MSK, "Key Pad for IKEv2")` uses MSK as an HMAC key, and HMAC zero-pads keys shorter than the
block, so 32 octets and 32 octets + 32 zeros give the same result (verified for SHA-1/256/384/512).
Only the order of the two 16-octet halves matters. If msg7's AUTH is rejected right after EAP
Success, the half order is the first suspect - and because a failed try can cost an OTP, this MUST
be confirmed by trace before shipping.

### 6.5 Where a FortiToken code / push / emailed code fits

Fortinet is explicit: "FortiGate triggering MFA prompts for IKEv2 Dialup Gateway clients relies on
proprietary EAP extensions ... only supported when FortiClient is used"; the wire format is **not
publicly documented** (KB 219452). So Blanarch cannot rely on an in-band token prompt. The
documented escape hatch for other clients is **concatenation**: send `password + code` as the
MSCHAPv2 password, and FortiGate "takes the last 6-digit token from the received string ... validates
the remaining portion against the user's password" (KB 180854). How FortiGate splits an MSCHAPv2
response (which never reveals the password) is not documented, so this must be traced.

For our **emailed-code** gateway there is a sequencing problem: the code is only sent **after** the
first factor passes (KB 216311), so the client cannot know it on the first attempt. Two things to
trace (§11): (a) does a first EAP-MSCHAPv2 attempt with the right password trigger the email even
though the tunnel then fails for a missing token, and (b) can a **second** attempt within the code
lifetime (about a minute on our gateway) send `password + code` and succeed. Blanarch already reads
emailed codes over IMAP (the SSL-VPN flow); reuse that: on the first attempt, watch the inbox; when
a code arrives, run a second IKE_AUTH with the concatenated password. Raise the effective timeout to
match the gateway's `negotiate-timeout` (default 30 s, raise to 50-120 for OTP). Map "code never
arrived" to `OTP_TIMEOUT`, "code rejected" to `OTP_REJECTED`.

### 6.6 The final AUTH from the MSK (RFC 7296 §2.15, §7)

```
InitiatorSignedOctets = RealMessage1 | Nr | prf(SK_pi, RestOfInitIDPayload)
ResponderSignedOctets = RealMessage2 | Ni | prf(SK_pr, RestOfRespIDPayload)
  RealMessage1/2  = the IKE_SA_INIT request/response exactly as last sent/received (after retries),
                    from SPIi to the end; the non-ESP marker and TCP length are NOT included.
  RestOf*IDPayload = ID Type | RESERVED(3) | ID data  (of IDi from msg3 / IDr from msg4)
initiator AUTH (msg7) = prf( prf(MSK, "Key Pad for IKEv2"), InitiatorSignedOctets ), method 2
```
The gateway's msg8 AUTH is verified the same way over ResponderSignedOctets with the **MSK** (for a
key-generating method like MSCHAPv2). If the gateway instead uses SK_pi/SK_pr for the final AUTH,
that is the non-key-generating case (RFC 7296 says SHOULD NOT); **[confirm by trace]** which key our
gateway uses (fortinet_dialup_ikev2.md §6.1). "Key Pad for IKEv2" is 17 ASCII octets, no NUL.

### 6.7 EAP-TTLS/PAP as an option (RFC 5281; RFC 9427)

Needed for LDAP backends (Fortinet: LDAP over IKEv2 "requires EAP-TTLS"). EAP Type 21. Phase 1 is a
normal TLS handshake carried in EAP-TTLS Data (the client verifies the gateway's EAP-server
certificate, `wifi-certificate` on the gateway). Phase 2 sends AVPs inside TLS application data;
inner **PAP** = User-Name(1) + User-Password(2) AVPs (password NUL-padded to a multiple of 16, not
RADIUS-encrypted). A tunnelled Access-Challenge (Reply-Message AVP) then a second User-Name /
User-Password round is how a token prompt can appear inside TTLS. MSK = TLS exporter: TLS 1.2 label
"ttls keying material" (MSK = bytes 0..63); TLS 1.3 label "EXPORTER_EAP_TLS_Key_Material" with
Type=0x15 (RFC 9427). Android exposes the exporter from API 31 (`SSLEngines.exportKeyingMaterial`);
below that use Bouncy Castle `bctls` (android_feasibility.md §5). Concatenation with SMS/email codes
does not work for TTLS/PAP (KB 216311).

### 6.8 SAML for IKEv2 (outline only)

FortiOS 7.2+ can front IKEv2 with SAML (docs 951346). It still needs `eap enable`: after the browser
SAML flow the client "proves ownership of the cached user authentication ... using EAP-MSCHAPv2 or
EAP-TTLS". Outline: the client hits `auth-ike-saml-port` (default 1001, or a shared `ike-tcp-port`
from 7.6.1) over HTTPS; the gateway redirects with a SAML AuthnRequest; the user authenticates at
the IdP in a browser; the client posts the SAML Response; the gateway returns a temporary token ID
used as the EAP identity (the FortiClient UID in debug). The initial HTTP path, how the token ID
reaches the client, and what EAP secret is used are **not publicly documented** (fortinet_dialup_
ikev2.md §8). Reuse Blanarch's existing SAML loopback listener from the SSL-VPN flow. Out of scope
for the first engine.

---

## 7. Configuration payload -> TunnelConfig, traffic selectors, routes

### 7.1 CP reply attributes (RFC 7296 §3.15; RFC 8598)

The gateway returns CP(CFG_REPLY) in msg8. Map attributes (numbers per IANA; FortiGate use per docs
951346, 836965; all **[confirm by trace]**) to `vpn/Ports.kt` `TunnelConfig`:

| CFG attribute | Value | -> TunnelConfig |
|---|---|---|
| INTERNAL_IP4_ADDRESS (1) | 4 octets | `assignedIp` (the tunnel inner IP) |
| INTERNAL_IP4_NETMASK (2) | 4 octets | inner netmask (Fortinet recommends /32 per client) |
| INTERNAL_IP4_DNS (3) | 4 octets, repeatable | `dns` list |
| INTERNAL_IP4_SUBNET (13) | 4 addr + 4 mask, repeatable | `routes` (split-include: route these via the tunnel) |
| INTERNAL_DNS_DOMAIN (25) | FQDN, DNS presentation, repeatable | `dnsSuffix` / split-DNS domains |
| APPLICATION_VERSION (7) | ASCII, not NUL-terminated | log only |

Unknown/unrequested attributes MUST be ignored (§3.15). If no CFG_REPLY arrives and we required an
address, treat it as an error (§3.15.4) -> `TUNNEL_REFUSED`. INTERNAL_ADDRESS_FAILURE (36) means the
IKE SA exists but no address was assigned; FAILED_CP_REQUIRED (37) means CP was required and missing
- both -> `TUNNEL_REFUSED` (the IKE SA is not fatal, §2.21.2). Which attribute carries the split-DNS
domain list is **[confirm by trace]** (expect 25; a 7.6.7 forum report says it was ignored with EAP
dial-up, fortinet_dialup_ikev2.md §9).

### 7.2 Traffic selectors (RFC 7296 §3.13, §2.9, §2.19)

Request wide selectors and let the gateway narrow: TSi = TSr = (protocol 0, ports 0-65535,
0.0.0.0-255.255.255.255) in msg3. The remote-access pattern (§2.19): the gateway echoes TSi narrowed
to (assigned IP - assigned IP) and TSr to the networks it will carry. With FortiGate's
`mode-cfg-allow-client-selector disable` (default), the client uses wildcard selectors and the
FortiClient tunnel shows `src 0.0.0.0-255.255.255.255`, `dst <assigned>-<assigned>` (docs 298520).
TS payload/selector byte layout: rfc_details.md §3.10 (TS_IPV4_ADDR_RANGE type 7, selector length
16). A rekey's new SA MUST NOT be narrower than the old (§2.9.2).

### 7.3 Routes precedence

Build routes for the Android TUN from, in order: (1) INTERNAL_IP4_SUBNET attributes if present
(split include); (2) otherwise the narrowed TSr; (3) if neither narrows (full tunnel), route
0.0.0.0/0. INTERNAL_IP4_SUBNET in a reply means "send these through me", and the client MAY send
other TSr-covered traffic directly (§3.15.2). For split tunnel, `allowFamily(AF_INET6)` so IPv6
falls through to the underlying network; for full tunnel leave IPv6 blocked to avoid a leak
(android_feasibility.md §3.4). Set the TUN MTU from §8.4.

---

## 8. CHILD_SA and ESP

### 8.1 The first Child SA (from IKE_AUTH) and SPIs

SAi2 in msg3 is an ESP proposal (Protocol ID 3), SPI size 4, SPI = **our inbound SPI** (the SPI we
want to see in ESP we receive; §1.3.3, rfc_details.md §3.1). Offer the ESP suites from FortiGate's
phase2 default `aes128-sha1 aes256-sha1 aes128-sha256 aes256-sha256 aes128gcm aes256gcm
chacha20poly1305` (docs 238852); prefer AEAD (AES-GCM-16, ChaCha20-Poly1305) first, then AES-CBC +
HMAC. Each ESP proposal MUST include an SN transform (type 5): offer SN 0 (32-bit) and, if we
implement ESN, SN 1; a lone SN 1 means 32-bit is unacceptable (§3.3.2). No KE transform in the
IKE_AUTH Child SA (PFS for the first child is not done here). The gateway's SAr2 SPI is our
**outbound** SPI.

### 8.2 KEYMAT split for both directions (RFC 7296 §2.17)

```
KEYMAT = prf+(SK_d, Ni | Nr)            first Child SA: the IKE_SA_INIT nonces
                                        CREATE_CHILD_SA (no KE): the new nonces
KEYMAT = prf+(SK_d, g^ir(new) | Ni | Nr)   CREATE_CHILD_SA with KE (PFS)
```
Order: all keys for **initiator -> responder** first, then **responder -> initiator**; within a
direction, **encryption key then integrity key**. "Initiator" = initiator of the exchange that
created the Child SA. For the IKE_AUTH child that is us, so our outbound key block is first. For a
**gateway-initiated** rekey the gateway is the initiator, so its block (gateway -> client) is first -
this is the classic sign-flip bug; get it from the exchange, not the IKE SA's original initiator.
Sizes verified against the NIST CAVP `DKM(Child SA)` vectors (§10.6).

| ESP suite | per direction | KEYMAT total |
|---|---|---|
| AES-GCM-16-256 | 32 key + 4 salt = 36 | 72 |
| AES-GCM-16-128 | 16 + 4 = 20 | 40 |
| ChaCha20-Poly1305 | 32 + 4 = 36 | 72 |
| AES-CBC-256 + HMAC-SHA2-256-128 | 32 + 32 = 64 | 128 |
| AES-CBC-128 + HMAC-SHA1-96 | 16 + 20 = 36 | 72 |

E.g. AES-GCM-256 via IKE_AUTH: our outbound key = KEYMAT[0:32], salt KEYMAT[32:36]; inbound key
KEYMAT[36:68], salt KEYMAT[68:72].

### 8.3 ESP packet, AES-GCM, CBC+HMAC, padding, sequence, replay

ESP layout (RFC 4303 §2):
```
| SPI(4) | Sequence(4) |            <- integrity-covered, never encrypted
| IV | Payload(inner IP packet) | Padding | Pad Length(1) | Next Header(1) |   <- encrypted
| ICV |
```
SPI is chosen by the receiver, never 0. Tunnel mode Next Header = 4 (IPv4) or 41 (IPv6); 59 = dummy,
discarded silently. Sequence starts at 0; first sent packet is 1; never let it cycle (rekey before
2^32, or 2^64 with ESN). Receive order (§3.4): SPI lookup -> preliminary replay check -> ICV/AEAD
check -> update window -> decrypt -> check padding -> deliver. Discard IP fragments before ESP.

**AES-GCM (RFC 4106):**
```
Payload = IV(8, explicit) | ciphertext
nonce(12) = salt(4, from KEYMAT) | IV(8)         IV never repeats for a key; a counter is fine
AAD = SPI(4) | Seq(4)                            32-bit SN, 8 octets
AAD = SPI(4) | ESN high(4) | ESN low(4)          ESN, 12 octets
plaintext = inner packet | Padding | Pad Length | Next Header
ICV = 16-octet GCM tag (transform 20)
```
Padding only to 4-octet alignment. Vectors in §10.5 (draft-mcgrew-gcm-test-01).

**ChaCha20-Poly1305 (RFC 7634):** transform 28, key 256-bit, KEYMAT 36 (32 key + 4 salt), IV 8
explicit, nonce = salt | IV, ChaCha20 block counter starts at 1, AAD like GCM, tag 16, padding to 4.

**AES-CBC + HMAC (RFC 3602, RFC 4868):** IV 16 octets, random and unpredictable per packet (or NIST
SP 800-38A method 1: one AES-ECB of a counter under the same key). Encrypted region (inner + padding
+ pad len + NH) MUST be a multiple of 16; default padding is 1,2,3,... (receiver SHOULD check). ICV
= HMAC over SPI | Seq | IV | ciphertext, encrypt-then-MAC, truncated to half (HMAC-SHA2-256-128 = 16
octets, SHA1-96 = 12). With ESN and a separate MAC, append the high 32 bits of the sequence after
Next Header for the MAC input only. Verify ICV before decrypt; constant-time compare. Vectors in
§10.5 (RFC 3602 tunnel-mode cases).

### 8.4 Anti-replay window and MTU math

**Replay window (RFC 4303 §3.4.3):** MUST support; min 32, default 64. Right edge T = highest
authenticated sequence; reject below the left edge, reject in-window duplicates, accept above T only
after the integrity check, and update the window only after the check passes. Use either the RFC
4303 Appendix A2 bit-shift algorithm (ESN case in rfc_details.md §12.3) or RFC 6479's ring of
blocks. Build this as the pure `ReplayWindow` core (§10).

**MTU (android_feasibility.md §3.3):** with a 1500-byte underlying link and outer IPv4+UDP, the
largest inner packet is **1438** for AES-GCM-16 and **1422** for AES-CBC + HMAC-SHA-256-128.
Overhead = 20 (outer IPv4) + 8 (UDP NAT-T) + 8 (SPI+Seq) + IV (8 GCM / 16 CBC) + 2 (padlen+NH) +
padding + 16 (ICV). Over TCP add the 2-octet RFC 9329 length (and any TCP options). Compute
`tunMtu = floor-to-alignment(underlyingMtu - overhead)` (GCM to a multiple of 4, CBC to 16, minus
2); on cellular plan for 1358 or lower (464XLAT adds 20). Always call `Builder.setMtu`; clamp inner
TCP MSS as a backstop.

### 8.5 ESP over NAT-T UDP and over TCP

- **UDP 4500:** ESP follows the UDP header directly (no marker), SPI first; source/dest ports equal
  IKE's; IPv4 UDP checksum SHOULD be 0 (receiver must not depend on it). Keepalive is a single 0xFF
  octet (§3.1).
- **TCP:** each ESP packet is framed `Length(2) | ESP` (Length includes itself), on the one TCP
  connection that carries the IKE SA; no NAT keepalives (RFC 9329 §6.6).

Build ESP as the pure `EspCodec` core (seal/open per packet, in-place buffers) plus the
`ReplayWindow`; keep socket I/O in the orchestrator, through `cancellableIo`.

---

## 9. Liveness, rekeying, delete, error mapping

### 9.1 Liveness / DPD (RFC 7296 §2.4)

Liveness is an **empty INFORMATIONAL** request (IKE header + SK with no inner payloads); it MUST be
answered (an empty SK is a valid response). Send one only when we have sent outbound traffic without
seeing any fresh authenticated IKE or ESP packet back. Any valid IKE or ESP packet proves liveness
of the IKE SA and all its Child SAs. Never decide "dead" from ICMP or unprotected notifies. FortiGate
DPD default is `on-demand`, `dpd-retrycount` 3; the effective interval is likely ~20 s (tunnel dumps
show `idle=20000ms`, FortiClient `<dpd_retry_interval>` default 20) though the admin guide also says
"every five seconds" - **[confirm by trace]** (fortinet_dialup_ikev2.md §10). NAT keepalive: send
0xFF on 4500 when behind a NAT and idle for M seconds (RFC 3948 default 20; FortiGate `keepalive`
default 10). NAT keepalives are not liveness. On battery, prefer the longest interval that keeps the
NAT mapping and merge with real traffic (android_feasibility.md §3.5-3.6).

### 9.2 Rekeying (RFC 7296 §1.3, §2.8, §2.17, §2.18)

Either peer may start CREATE_CHILD_SA, so the client must also act as **responder** for it.
- **Rekey a Child SA:** `SK{ N(REKEY_SA, proto 3, SPI = old inbound SPI), SA, Ni, [KEi,] TSi, TSr }`;
  new KEYMAT per §8.2; keep sending on the old SA until a valid packet arrives on the new inbound SA
  or the old SA's Delete arrives (§2.8). A failed child rekey SHOULD NOT tear down the IKE SA.
- **Rekey the IKE SA:** `SK{ SA(proto 1, SPI size 8, SPI = new), Ni, KEi }` (KE mandatory, no TS).
  New keys: `SKEYSEED = prf(SK_d(old), g^ir(new) | Ni | Nr)`, then prf+ with the new SPIs and new
  PRF (§2.18); message IDs reset to 0; the rekey initiator becomes the new original initiator (the I
  flag may flip); Child SAs move to the new IKE SA; Delete the old IKE SA last (§2.8).
- IKEv2 does not negotiate lifetimes; each side rekeys by its own policy (FortiGate IKE SA 86400 s,
  child 43200 s). **Reauthentication** is a brand-new IKE_SA_INIT + IKE_AUTH - which for an OTP login
  would need a **new code**, so prefer rekey over reauth and warn the user if the gateway forces
  reauth (`reauth`/AUTH_LIFETIME). Collisions: on simultaneous rekey, the SA made with the lowest of
  the four nonces is kept (§2.8.1).

### 9.3 Delete and informational (RFC 7296 §1.4)

On user disconnect send `INFORMATIONAL SK{ D(proto 1, no SPI) }` to delete the IKE SA (all Child SAs
die with it); the response is an empty INFORMATIONAL. Delete a single Child SA with D(proto 3, SPI
size 4, our **inbound** SPIs); the peer answers with its inbound SPIs for the same pairs. Always
answer peer-initiated INFORMATIONAL (DPD, Delete) and CREATE_CHILD_SA.

### 9.4 Error notifies -> ErrorCode

Existing `state/VpnStatus.kt` codes are reused; proposed additions are marked **NEW**.

| Condition (RFC 7296 §2.21, §3.10 notifies) | ErrorCode |
|---|---|
| AUTHENTICATION_FAILED (24); EAP Failure at the end; PSK/signature responder AUTH we cannot verify | AUTH_REJECTED |
| EAP-MSCHAPv2 Failure R=0 691, or bad password inside EAP | AUTH_REJECTED |
| Emailed/typed code rejected (EAP retry exhausted, or "missing token" outcome) | OTP_REJECTED |
| No code arrived within the timeout | OTP_TIMEOUT |
| Responder cert fingerprint changed vs pin | CERT_MISMATCH |
| No pin and cert not system-trusted | CERT_UNTRUSTED |
| No IKE response on UDP and TCP (both transports exhausted) | GATEWAY_UNREACHABLE |
| NO_PROPOSAL_CHOSEN (14), INVALID_SYNTAX (7), unexpected payloads, INVALID_KE loop, bad ICV | PROTOCOL |
| Child SA / CP failure after auth: TS_UNACCEPTABLE (38), SINGLE_PAIR_REQUIRED (34), INTERNAL_ADDRESS_FAILURE (36), FAILED_CP_REQUIRED (37), NO_ADDITIONAL_SAS (35), no CFG_REPLY | TUNNEL_REFUSED |
| ESP/IKE stops (DPD gives up, socket dies, TCP reset) | LINK_LOST |
| The gateway Deletes our IKE SA, or an AUTH_LIFETIME / forced reauth ends it | SESSION_EXPIRED |
| Phone switched networks | NETWORK_CHANGED |
| TEMPORARY_FAILURE (43) | **NEW** `RETRY_LATER` (do not retry immediately; back off over minutes, then close - §2.25) |
| Server asks for a client certificate we do not have (`eap-cert-auth`/peer cert required) | CLIENT_CERT_REQUIRED |

`RETRY_LATER` is the one genuinely new code; everything else maps onto the existing enum. CHILD_SA_
NOT_FOUND (44) is handled silently (delete that child, recreate if needed), not surfaced. Report
failures as `VpnException(ErrorCode)` from the orchestrator, never by matching gateway text
(CLAUDE.md).

---

## 10. Mapping to Blanarch ports and the pure cores

### 10.1 Engine ports (`vpn/Ports.kt`, reused unchanged where possible)

The IPsec gateway implements the same `VpnGateway` shape the SSL-VPN gateway does, so the
`ConnectionOrchestrator` sequence (`login` -> `fetchTunnelConfig` -> `openLink` -> `negotiate` ->
`pump`) does not change:

- **`login(username, password, secondFactor)`** runs IKE_SA_INIT (§4) and IKE_AUTH with EAP (§6).
  The certificate confirmation reuses the SSL-VPN pin flow (CERT_MISMATCH / CERT_UNTRUSTED). The
  `SecondFactorProvider` supplies the emailed/typed code; because the gateway sends the email only
  after the first factor, `login` may run IKE_AUTH twice (§6.5): once to trigger the email, then
  with the concatenated password. `secondFactor` `Push` is unsupported over standard IKEv2 (the push
  prompt is Fortinet-proprietary) -> report clearly rather than pretend.
- **`fetchTunnelConfig()`** returns the `TunnelConfig` built from CP(CFG_REPLY) + TSr + INTERNAL_IP4_
  SUBNET (§7). With IKEv2 the config arrives during IKE_AUTH, so cache it from `login` and return the
  cached value here.
- **`openLink()`** returns a `PacketLink` whose transport is the negotiated UDP-4500 or TCP-9329
  socket carrying ESP.
- **`negotiate(timeout)`** for IPsec has nothing left to negotiate (the inner IP came from CP), so it
  returns the `IpConfig` (assigned IP + DNS) already learned; keep the method to fit the interface.
- **`pump(tun)`** moves inner IPv4 packets between the TUN and ESP: TUN read -> `EspCodec.seal` ->
  socket; socket -> `EspCodec.open` (+ `ReplayWindow`) -> TUN write; runs DPD (§9.1) and rekey
  (§9.2) on the side; returns why it ended (mapped to LINK_LOST / SESSION_EXPIRED / NETWORK_CHANGED).

`GatewayProber`/`IkeProber` already exist for §2. A new `GatewayFactory` branch builds the IPsec
gateway when the profile is IPsec.

### 10.2 Pure, I/O-free cores to build and unit-test (CLAUDE.md Kotlin rules)

Keep protocol logic pure; socket work goes through `cancellableIo`; only the orchestrator knows the
sequence. Build:

| Core | Job | Test vectors (exact, from rfc_details.md §15) |
|---|---|---|
| `IkeCodec` | build/parse IKE header, generic payload header, SA/KE/Ni/Nr/IDi/IDr/CERT/CERTREQ/AUTH/N/D/V/TSi/TSr/CP/EAP/SK/SKF; proposal & transform encode/decode | round-trip self-tests; ChaCha20 SK message in §10.5 (RFC 7634 App B, whole 69-octet message) |
| `KeyDerivation` | prf, prf+, SKEYSEED, the 7 IKE keys, KEYMAT, IKE-rekey keys | NIST CAVP IKEv2 KDF, §10.6 (both COUNT=0 cases) |
| `SkPayload` | SK seal/open for AEAD (AES-GCM, RFC 5282) and CBC+HMAC; AAD construction | RFC 7634 App B (SK, §10.5); HMAC-SHA2 §10.2; AES-CBC §10.5 |
| `EapMsChapV2` | packet build/parse; NtPasswordHash, GenerateNTResponse, AuthenticatorResponse, MSK | RFC 2759 §9.2 and RFC 3079 §3.5.3, §10.4 |
| `EspCodec` | ESP seal/open: AES-GCM (RFC 4106), ChaCha20-Poly1305, AES-CBC+HMAC; padding; SPI/Seq | draft-mcgrew GCM packets and RFC 3602/7634 ESP packets, §10.5 |
| `ReplayWindow` | anti-replay (RFC 4303 A2 or RFC 6479) | synthetic sequences: accept new, reject old, reject dup, window slide |
| `NatT` / `TcpFraming` | non-ESP marker + demux (RFC 3948); IKETCP prefix + length framing (RFC 9329) | marker/keepalive/ESP demux cases; `49 4b 45 54 43 50` prefix, Length-includes-itself frames |
| `DhKem` | KE encode/decode and shared secret for MODP-14, ECP-19/20/21, X25519; recipient checks | RFC 5903 §8 (groups 19/20/21), RFC 7748 §6.1 X25519, §10.3 |

### 10.3 DH / ECDH / X25519 vectors (RFC 5903 §8, RFC 7748 §6.1)

Group 19 shared secret `girx = D6840F6B 42F6EDAF D13116E0 E1256520 2FEF8E9E CE7DCE03 812464D0 4B9442DE`
from the RFC 5903 §8 `i`/`r` scalars (full KEi/KEr bytes in rfc_details.md §15.9; groups 20 and 21
there too). X25519 DH (RFC 7748 §6.1): Alice private
`77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a`, Bob public
`de9edb7d7b7dc1b4d35b61c2ece435373f8343c85b78674dadfc7e146f882b4f`, shared
`4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742`.

### 10.4 EAP-MSCHAPv2 vectors (RFC 2759 §9.2, RFC 3079 §3.5.3)

```
UserName "User"; Password "clientPass" (UTF-16LE)
AuthenticatorChallenge 5B5D7C7D7B3F2F3E3C2C60213226262 8   PeerChallenge 2140232425 5E262A28295F2B3A337C7E
Challenge(8)         D02E4386BCE91226
PasswordHash(16)     44EBBA8D5312B8D611474411F56989AE
NT-Response(24)      82309ECD8D708B5EA08FAA3981CD8354 4233114A3D85D6DF
PasswordHashHash(16) 41C00C584BD2D91C4017A2A12FA59F3F
AuthenticatorResponse "S=407A5589115FD0D6209F510FE9C04566932CDA56"
```
RFC 3079 §3.5.3 MPPE (128-bit) for the same inputs: `MasterKey = FDECE3717A8C838CB388E527AE3CDD31`,
server SendStartKey128 (Magic3 key) `8B7CDC149B993A1BA118CB153F56DCCB`. Derived (not official,
[confirm by trace]) Magic2 key `D5F0E9521E3EA9589645E86051C82226`; candidate EAP-MSCHAPv2 MSK =
Magic2key | Magic3key | 32 zero octets (§6.4). DES key-expansion check (RFC 2759 §9.3, erratum 391):
password "MyPw" -> `NtPasswordHash FC156AF7EDCD6C0EDDE3337D427F4EAC`, first raw key `FC156AF7EDCD6C`
-> parity-corrected `FD0B5B5E7F6E34D9`.

### 10.5 AEAD / ESP packet vectors

- **IKEv2 SK, ChaCha20-Poly1305 (RFC 7634 App B):** iSPI `c0c1c2c3c4c5c6c7`, rSPI
  `d0d1d2d3d4d5d6d7`, INFORMATIONAL MID 9, one SET_WINDOW_SIZE=10 notify. AAD (32) =
  `c0c1c2c3c4c5c6c7 d0d1d2d3d4d5d6d7 2e202500 00000009 00000045 29000029`; whole 69-octet message
  `c0c1c2c3c4c5c6c7 d0d1d2d3d4d5d6d7 2e202500 00000009 00000045 29000029 1011121314151617
  610394701f8d017f7c12924889 6b71bfe25236efd7cdc67066906315b2`. This is the one full worked SK/AAD
  example; use it to lock down `SkPayload`.
- **ESP AES-GCM (draft-mcgrew-gcm-test-01):** e.g. #2 (32-bit SN, AES-128) key
  `feffe9928665731c6d6a8f9467308308`, spi `0000a5f8`, seq `0000000a`, nonce
  `cafebabefacedbaddecaf888`, AAD `0000a5f80000000a`; full plaintext and 80-octet ctext+tag in
  rfc_details.md §15.6 (with AES-256 case #3 and ESN cases).
- **ESP AES-CBC (RFC 3602 §4):** tunnel-mode case 7 key `0123456789abcdef0123456789abcdef`, SPI
  0x8765, Seq 2, IV `f4e765244f6407adf13dc1380f673f37`, 96-octet plaintext and ciphertext in
  rfc_details.md §15.5.
- **HMAC-SHA2 (RFC 4231 / RFC 4868):** e.g. HMAC-SHA-256-128 of "Hi There" under `0b x 32` =
  `198a607eb44bfbc69903a0f1cf2bbdc5`; more in rfc_details.md §15.3-15.4 (watch the two errata:
  AUTH512-4 key per erratum 1785, AUTH384-4 key as printed).

### 10.6 IKEv2 KDF vector (NIST CAVP SP 800-135)

Group 14 / SHA-256 case: `Ni fd21a5f19aaeaf1c`, `Nr ad1dbfe988cd8e19`, SPIi `af756945c2c6f7b7`,
SPIr `27f77c62e66b1077`, `SKEYSEED 7c7d22349a2b28f89c865d77f3a4e304ec5e13e7d3687e2aa61d53768b739591`;
the 132-octet DKM, DKM(Child SA), DKM(Child SA D-H) and SKEYSEED(Rekey) are in rfc_details.md §15.8
(with the group-19-size case). Verifies SKEYSEED = prf(Ni|Nr, g^ir), DKM = prf+(SKEYSEED,
Ni|Nr|SPIi|SPIr), child KEYMAT = prf+(SK_d, Ni|Nr) and the DH/rekey variants; SK_d = first 32 octets
of DKM.

---

## 11. Open questions for the FortiGate VM spike, and a trace checklist

### 11.1 Open questions (each blocks a design decision)

1. Does the gateway answer a **non-FortiClient** initiator's IKE_SA_INIT at all, and with which
   proposals / DH groups / notifies? Any vendor IDs or CERTREQ? (fortinet_dialup_ikev2.md §5, §13.1)
2. Responder auth with EAP on: **PSK (method 2)** or **signature (method 1/9-11/14)**? Which IDr
   type? If signature, RSA or ECDSA, and how many certs in the chain? (§6.3)
3. Final AUTH (msg7/8) key: **EAP MSK** or the PSK? (§6.6)
4. EAP method the gateway drives, and whether it sends EAP-Identity first. How is a **one-time /
   emailed** code carried (proprietary extension we cannot use, EAP-GTC, MSCHAPv2 retry, or TTLS
   inner challenge)? What does a non-FortiClient client receive? (§6.5)
5. **Emailed-code sequencing:** does a first EAP-MSCHAPv2 attempt trigger the email, and does a
   second attempt with `password+code` succeed within the ~60 s code lifetime? (§6.5, testbed §5)
6. CFG_REPLY contents: which attributes, split via INTERNAL_IP4_SUBNET or narrowed TSr or both,
   split-DNS attribute number (expect 25). (§7)
7. Transport reality: actual `ike-tcp-port`; does the 443 listener speak plain RFC 9329 framing
   (IKETCP prefix) with `fortinet-esp disable`? Does a `transport tcp` dial-up still accept UDP, and
   vice versa? (§3)
8. NAT-T: does the gateway UDP-encapsulate ESP when we are behind a NAT, and if we forge a
   non-matching NAT-D? Does it accept IKE_SA_INIT started directly on 4500? Keepalive format ("138-
   byte ISAKMP exchange" vs 0xFF) and interval. (§9.1, android_feasibility.md §7)
9. Effective DPD interval (5 s vs 20 s); does the gateway initiate rekeys (key order flips) or force
   reauth? (§9)
10. Does the gateway require INITIAL_CONTACT, FCT-UID, network-id or any Fortinet payload to accept
    IKE_AUTH? (fortinet_dialup_ikev2.md §5-6)
11. On the trial VM, is only DES offered (state-machine testing only), and are ECP groups allowed?
    (testbed §2)

### 11.2 Trace checklist (per attempt, redacted per testbed §7.5)

- Record: transport and port actually used; IKE_SA_INIT request/response payload list, chosen
  proposal, DH group, notifies (NAT-D, fragmentation, any 40960+ private notify); whether COOKIE or
  INVALID_KE_PAYLOAD occurred.
- IKE_AUTH: msg4 IDr type, presence/size of CERT chain, AUTH method; the EAP method and every EAP
  round (types and OpCodes only, never NT-Response bytes or the password); where a token/email prompt
  appears; msg8 AUTH method; CFG_REPLY attributes; TSi/TSr as narrowed.
- Child SA: chosen ESP suite, SPIs, SN (ESN yes/no); first ESP packet each way (SPI, seq, whether
  UDP-encapsulated or TCP-framed).
- Liveness/rekey: DPD interval and format; NAT keepalive interval and format; who initiates rekey and
  its lifetime; any Delete / AUTH_LIFETIME.
- Compare engine logs (message types, SPIs, transform IDs, notify numbers, timings) with the
  FortiGate `diagnose debug application ike -1` output. Log Blanarch's own decrypted EAP only in a
  debug build, never in the shipping app, and never a password or NT-Response.
- Store raw traces in a git-ignored folder; redact SK_* / ESP keys, usernames and codes before
  sharing; record in `PROVENANCE.md` that a behaviour came from a trace (version, date), not from any
  implementation.
