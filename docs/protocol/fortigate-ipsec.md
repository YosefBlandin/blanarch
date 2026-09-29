# FortiGate dial-up IPsec (IKEv2): implementation spec

Status: **draft, Phase 3a.** Only §2 (the reachability probe) is ready to implement. The rest is
the outline the spike fills in against a FortiGate VM trial.

Sources allowed for this document: IETF RFCs (7296 IKEv2, 4303 ESP, 4106 AES-GCM for ESP,
3948 NAT-T, 9329 TCP encapsulation, 3748 EAP), Fortinet's public documentation and KB
articles, and redacted traces of Blanarch's own traffic. Never the code of strongSwan,
libreswan, openfortivpn, OpenConnect or FortiClient. Record every step in `PROVENANCE.md`.

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

## 3. Outline for the spike (to be written from the VM trial)

- IKE_SA_INIT proposals Fortinet accepts by default for dial-up; NAT detection and the move to 4500.
- IKE_AUTH with EAP: identity, EAP-MSCHAPv2 rounds, where the FortiToken prompt or push appears,
  how an emailed code is requested; how the responder authenticates (certificate or PSK).
- Configuration payload: INTERNAL_IP4_ADDRESS, DNS, SUBNET; traffic selectors for split tunnel.
- CHILD_SA and ESP (AES-GCM, RFC 4106), anti-replay, rekeying (CREATE_CHILD_SA), liveness.
- TCP transport (RFC 9329 "IKETCP" prefix, length-prefixed messages) on port 443.
