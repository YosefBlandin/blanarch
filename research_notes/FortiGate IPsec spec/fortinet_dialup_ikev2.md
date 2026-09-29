# FortiGate dial-up remote-access IPsec with IKEv2 (FortiOS 7.4 and 7.6)

Research notes, 2026-09-28. Scope: how a FortiGate acts as an IKEv2 dial-up responder for
FortiClient-style clients, with emphasis on FortiOS 7.6.3+ (SSL VPN tunnel mode removed).

## Provenance and rules followed

- Sources used: docs.fortinet.com (admin guides, CLI references, release notes, FortiClient and
  FortiAuthenticator guides), community.fortinet.com (Technical Tips and forum posts), rfc-editor.org,
  iana.org, developer.android.com. Every claim below carries its URL.
- No VPN or IPsec source code was opened, searched or quoted (no strongSwan, libreswan, openfortivpn,
  OpenConnect, FortiClient binaries, Android IKE module sources, kernel xfrm, GitHub/GitLab repos,
  READMEs or issue titles).
- Hex decodes in section 6 were done by me on hex dumps that Fortinet itself published in its KB/docs,
  using only the RFC 7296 payload format and the IANA registry. No implementation was consulted.
- Where a fact would only be available from code or a capture, it is marked **Not publicly documented**.
- `[TRACE]` marks claims that must be confirmed with a live trace against the target gateway before
  the engine relies on them.

Confidence legend: **High** = stated in current Fortinet docs or CLI reference. **Medium** = stated
in a KB/forum post, or inferred from Fortinet-published debug output. **Low** = indirect evidence.

---

## 0. Key takeaways for a third-party client (Blanarch)

1. Since FortiOS 7.6.3, SSL VPN tunnel mode is gone on all models; Fortinet's replacement is
   dial-up IPsec, IKEv2, EAP user auth, optionally over TCP 443 (RFC 8229 framing). [High]
   https://docs.fortinet.com/document/fortigate/7.6.3/fortios-release-notes/173430/ssl-vpn-tunnel-mode-no-longer-supported
   https://docs.fortinet.com/document/fortigate/7.6.4/administration-guide/155142/ssl-vpn-tunnel-mode-to-ipsec-vpn-migration
2. Fortinet's reference migration config: `type dynamic`, `ike-version 2`, `peertype any`,
   `authmethod psk` (PSK shared by all users), `mode-cfg enable`, `eap enable`,
   `eap-identity send-request`, `authusrgrp <group>`, `transport tcp`, `ike-tcp-port 443`,
   optional `network-overlay enable` + `network-id N`. [High] (same migration URL)
3. With PSK + EAP, the FortiGate authenticates **itself with the PSK** (AUTH method 2, Shared Key MIC)
   in the first IKE_AUTH response, next to an EAP-Request/Identity. This is not the RFC 7296 2.16
   model (which requires a signature-authenticated responder), so a stock RFC client may refuse it.
   [Medium, decoded from Fortinet-published hex; see section 6] `[TRACE]`
4. FortiClient's default EAP method is EAP-MSCHAPv2; EAP-TTLS/PAP is the only option for LDAP backends.
   [High] https://docs.fortinet.com/document/fortigate/8.0.0/administration-guide/913974/eap-user-authentication
5. **MFA prompts (FortiToken code, push, email/SMS OTP) over IKEv2 rely on "proprietary EAP
   extensions" and are only supported with FortiClient.** Wire format: **Not publicly documented.** [High]
   https://community.fortinet.com/fortigate-3/technical-tip-required-firmware-software-versions-for-using-fortitoken-mobile-or-otp-mfa-with-fortigate-ikev2-dialup-ipsec-219452
6. Documented workaround for non-FortiClient clients: type password and OTP concatenated
   (`p@ssw0rd345678`); FortiGate takes the last 6 digits as the token. Fortinet says this **does not work
   for email or SMS codes**, because those codes are only sent after the password is checked. [Medium]
   https://community.fortinet.com/fortigate-3/technical-tip-full-and-split-dialup-ikev1-ipsec-tunnel-with-fortitoken-2fa-180854
   https://community.fortinet.com/fortiauthenticator-8/technical-tip-how-to-resolve-the-eap-authentication-failed-due-to-missing-token-error-when-using-eap-ttls-pap-2fa-authentication-216311
   This matters directly for our emailed-code gateway. `[TRACE]`
7. FortiClient advertises three Fortinet vendor IDs in IKE_SA_INIT, one of them named
   "Forticlient EAP Extension" (hex published by Fortinet), and a proprietary `VPN_NETWORK_ID` notify.
   The notify type number is **Not publicly documented**. [Medium]
   https://community.fortinet.com/fortigate-3/technical-tip-how-to-configure-network-id-for-distinguishing-ikev2-ipsec-vpn-tunnels-using-forticlient-xml-file-223272

---

## 1. SSL VPN tunnel mode removal and what Fortinet tells admins to deploy

- 7.6.3: "the SSL VPN tunnel mode feature is replaced with IPsec VPN, which can be configured to use TCP
  port 443. SSL VPN tunnel mode is no longer available in the GUI and CLI. Settings will not be upgraded
  ... This applies to all FortiGate models." [High]
  https://docs.fortinet.com/document/fortigate/7.6.3/fortios-release-notes/173430/ssl-vpn-tunnel-mode-no-longer-supported
- SSL VPN web mode survives as "Agentless VPN"; FortiGate as SSL VPN client is dropped; a list of
  removed `vpn ssl settings` / `vpn ssl web portal` tunnel options is given (dtls-*, tunnel-ip-pools,
  dns-server*, split-tunneling*, host-check, etc.). [High]
  https://docs.fortinet.com/document/fortigate/7.6.4/administration-guide/155142/ssl-vpn-tunnel-mode-to-ipsec-vpn-migration
- TCP transport: "allows IKE negotiation on TCP and encapsulates of ESP packets within TCP header. This
  configuration uses TCP port 443 by default"; supported on FortiOS 7.4.2+ and FortiClient 7.4.1+. [High]
  (same URL)
- For remote access Fortinet "recommended to configure the IPsec tunnels using TCP as transport using a
  custom TCP port 443"; needs IKEv2 and FortiClient 7.4.1+. [High]
  https://docs.fortinet.com/document/fortigate/7.6.0/ssl-vpn-to-ipsec-vpn-migration/878694/tunneling-protocol-and-encapsulation
- But the custom-TCP-port page recommends `auto` for performance: "Because there is no NP offloading for
  the RFC compliant version of IPsec over TCP, its performance is lower ... it is recommended to configure
  auto, which allows clients to select the transport automatically, preferring UDP over TCP." [High]
  https://docs.fortinet.com/document/fortigate/7.6.4/administration-guide/567401/dialup-ipsec-vpn-using-custom-tcp-port
- IKEv1 vs IKEv2: IKEv1 uses XAuth, IKEv2 uses EAP; FortiClient 7.4.4+ dropped IKEv1 entirely.
  [High] https://docs.fortinet.com/document/fortigate/7.6.0/ssl-vpn-to-ipsec-vpn-migration/883534/ikev1-or-ikev2
- Auth methods matrix (migration guide): PSK or PKI signature required for the tunnel; Local and RADIUS
  users over IKEv1/IKEv2; LDAP over IKEv2 "requires EAP-TTLS"; SAML IKEv2 only; 2FA for both. [High]
  https://docs.fortinet.com/document/fortigate/7.6.0/ssl-vpn-to-ipsec-vpn-migration/281804/authentication-method
- IPsec has no "portals"; one SSL VPN portal may need one phase1 per use case; multiple dial-up phase1s on
  one WAN IP are told apart by `network-id` in IKEv2. [High]
  https://docs.fortinet.com/document/fortigate/7.6.4/administration-guide/155142/ssl-vpn-tunnel-mode-to-ipsec-vpn-migration
- User group placement: put the group either in `phase1-interface set authusrgrp` or in the firewall
  policy `set groups`, never both, or traffic does not flow. [High] (same URL)

### 1.1 Fortinet's reference migration config (Example 1, verbatim keys)

```
config vpn ipsec phase1-interface
  edit "my-full-tunnel"
    set type dynamic
    set interface "wan1"
    set ike-version 2
    set peertype any
    set net-device disable
    set mode-cfg enable
    set proposal aes128-sha256 aes256-sha256 aes128gcm-prfsha256 aes256gcm-prfsha384 chacha20poly1305-prfsha256
    set eap enable
    set eap-identity send-request
    set authusrgrp "vpn-user-group"
    set network-overlay enable
    set network-id 1
    set transport tcp
    set assign-ip-from name
    set ipv4-name "REMOTE-CLIENT-ADDRESS-RANGE"
    set save-password enable
    set client-auto-negotiate enable
    set client-keep-alive enable
    set psksecret ******
config vpn ipsec phase2-interface
  edit "my-full-tunnel"
    set phase1name "my-full-tunnel"
    set proposal aes128-sha1 aes256-sha1 aes128-sha256 aes256-sha256 aes128gcm aes256gcm chacha20poly1305
config system settings
  set ike-tcp-port 443
```
Source: https://docs.fortinet.com/document/fortigate/7.6.4/administration-guide/155142/ssl-vpn-tunnel-mode-to-ipsec-vpn-migration
Example 2 in the same page adds `ipv4-dns-server1..3`, `internal-domain-list`, `ipv4-split-include`,
and a `dhcp-ipsec enable` phase2 with DHCP relay. [High]

The FortiClient XML shown for the migrated tunnel uses: `<version>2</version>`,
`<authentication_method>Preshared Key</authentication_method>`, `<transport_mode>1</transport_mode>`,
`<tcp_port>443</tcp_port>`, `<udp_port>500</udp_port>`, `<xauth><enabled>1` (for IKEv2 this means EAP),
`<nat_traversal>1`, `<dpd>1`, `<dpd_retry_count>3`, `<dpd_retry_interval>5`, `<networkid>0`,
`<ike_saml_port>443`, `<enable_ike_fragmentation>0`, phase2 `<pfs>1`, `<replay_detection>1`,
`<key_life_seconds>43200`, `<dhgroup>14`. [High] (same URL, section "XML configuration for IPsec VPN")

---

## 2. `config vpn ipsec phase1-interface` options relevant to IKEv2 dial-up

Defaults from the CLI reference tables. 7.6 = 7.6.4 CLI, 7.4 = 7.4.8 CLI unless noted.
- 7.6.4 CLI: https://docs.fortinet.com/document/fortigate/7.6.4/cli-reference/305883427/config-vpn-ipsec-phase1-interface
- 7.4.8 CLI: https://docs.fortinet.com/document/fortigate/7.4.8/cli-reference/305883427/config-vpn-ipsec-phase1-interface

| Option | Values | Default 7.6 | Default 7.4 | Notes |
|---|---|---|---|---|
| `type` | static, dynamic, ddns | static | static | `dynamic` = dial-up server (IKE Mode Config server when mode-cfg on). |
| `ike-version` | 1, 2 | 1 | 1 | Must set 2 for EAP, TCP, SAML. |
| `authmethod` | psk, signature | psk | psk | Responder's own auth method. |
| `authmethod-remote` | psk, signature | (empty) | (empty) | "Authentication method (remote side)" (asymmetric auth). |
| `psksecret` / `psksecret-remote` | ASCII or 0x-hex | | | |
| `certificate` | local cert names | | | Used with `authmethod signature`. |
| `peertype` | any, one, dialup, peer, peergrp | peer | peer | Migration configs use `any`. |
| `peerid` | string (max 255) | | | IKEv2 IDi check. |
| `peer` / `peergrp` | user peer (CA+subject) | | | Client cert validation (see `eap-cert-auth`). |
| `cert-id-validation` | enable, disable | enable | | RFC 4945 ID vs cert cross check. FortiClient Android docs say disable it. |
| `proposal` | see section 3 | (empty in table) | | Admin guide gives the default list (section 3). |
| `dhgrp` | 1,2,5,14..21,27..32 | 14 | 14 | |
| `addke1..7` | ML-KEM-512/768/1024 (35/36/37) etc. | none | n/a | Post-quantum additional KE (7.6). |
| `keylife` | 120..172800 s | 86400 | 86400 | Phase 1 (IKE SA) lifetime. |
| `rekey` | enable, disable | enable | | |
| `reauth` | enable, disable | disable | | RFC 4478 style reauth. |
| `eap` | enable, disable | disable | disable | "Enable/disable IKEv2 EAP authentication." |
| `eap-identity` | use-id-payload, send-request | use-id-payload | use-id-payload | `send-request` = FortiGate sends EAP-Request/Identity; `use-id-payload` = take identity from IDi. |
| `eap-cert-auth` | enable, disable | disable | disable | "peer certificate authentication in addition to EAP if peer is a FortiClient endpoint". |
| `eap-exclude-peergrp` | peer group | | | Peers excluded from EAP. |
| `authusrgrp` | user group | | | EAP user group (or leave empty and use policy groups). |
| `mode-cfg` | enable, disable | disable | | |
| `mode-cfg-allow-client-selector` | enable, disable | disable | | disable = "Mode-cfg client to use wildcard selectors". |
| `assign-ip` | enable, disable | enable | | |
| `assign-ip-from` | range, usrgrp, dhcp, name | range | | `name` = firewall address/group (`ipv4-name`). |
| `ipv4-start-ip` / `ipv4-end-ip` | IPv4 | 0.0.0.0 | | |
| `ipv4-netmask` | netmask | 255.255.255.255 | | |
| `ipv4-dns-server1..3` | IPv4 | 0.0.0.0 | | |
| `ipv4-wins-server1..2` | IPv4 | 0.0.0.0 | | |
| `dns-mode` | manual, auto | manual | | `auto` = "Use default DNS servers". |
| `ipv4-split-include` / `ipv4-split-exclude` | address/group | | | |
| `split-include-service` | service/group | | | |
| `internal-domain-list` | domains | | | IKEv2 split DNS (section 9). |
| `dns-suffix-search`, `domain`, `banner`, `include-local-lan`, `unity-support` | | unity-support enable | | Unity items are IKEv1 client extensions. |
| `ip-delay-interval` | s | | | Hold released IPs before reuse. |
| `net-device` | enable, disable | disable | disable | enable = kernel device per dial-up tunnel. |
| `add-route` | enable, disable | enable | | Route to peer's selector (the assigned IP). |
| `dpd` | disable, on-idle, on-demand | on-demand | on-demand | |
| `dpd-retrycount` | 0..10 | 3 | 3 | |
| `dpd-retryinterval` | seconds | not shown in table | | Tunnel lists show `idle=20000ms` when unset (section 10). |
| `keepalive` | 5..900 s | 10 | | NAT-T keepalive interval. |
| `nattraversal` | enable, disable, forced | enable | enable | |
| `fragmentation` | enable, disable | enable | enable | "fragment IKE message on re-transmission". |
| `fragmentation-mtu` | 500..16000 | 1200 | 1200 | IKEv2 fragmentation threshold. |
| `negotiate-timeout` | 1..300 s | 30 | 30 | Raise for OTP entry (section 7). |
| `idle-timeout` / `idle-timeoutinterval` | / 5..43200 min | disable / 15 | | |
| `transport` | 7.6: udp, auto, tcp; 7.4: udp, udp-fallback-tcp, tcp | **auto** | **udp** | IKEv2 only. |
| `auto-transport-threshold` (7.6) / `fallback-tcp-threshold` (7.4) | 1..300 s | 15 | 15 | UDP to TCP fallback timer. |
| `fortinet-esp` | enable, disable | disable | disable | Proprietary TCP ESP; not for FortiClient (section 4). |
| `network-overlay` | enable, disable | disable | | Needed to use `network-id`. |
| `network-id` | 0..255 | 0 | | Fortinet-proprietary tunnel selector (section 5). |
| `save-password` | enable, disable | disable | disable | Lets FortiClient save XAuth/EAP credentials. |
| `client-auto-negotiate` | enable, disable | disable | disable | "allowing the VPN client to bring up the tunnel when there is no traffic". |
| `client-keep-alive` | enable, disable | disable | disable | "allowing the VPN client to keep the tunnel up when there is no traffic". |
| `client-resume` / `client-resume-interval` | / 120..172800 s | disable / 7200 | | Resume after client sleep (section 10). |
| `ems-sn-check` | enable, disable | disable | | EMS serial number verification. |
| `remote-gw-match` | any, ipmask, iprange, geography, ztna | any | | Source-IP anchoring for IKEv2 dial-up. |
| `cert-trust-store` | local, ems | local | | |
| `enforce-unique-id` | disable, keep-new, keep-old | disable | | |
| `esn` | require, allow, disable | disable | | |
| `childless-ike` | enable, disable | disable | | RFC 6023. |
| `digital-signature-auth` | enable, disable | disable | | RFC 7427. |
| `signature-hash-alg` | sha1, sha2-256/384/512 | sha2-512 | | |
| `rsa-signature-format` | pkcs1, pss | pkcs1 | | |
| `send-cert-chain` | enable, disable | enable | | |
| `ppk` | disable, allow, require | disable | | RFC 8784 PPK. |
| `dev-id-notification` / `dev-id` | | disable | | "Device ID carried by the device ID notification" (Fortinet). |
| `azure-ad-autoconnect` | enable, disable | disable | | FortiClient Entra autoconnect. |
| `wizard-type` | custom, dialup-forticlient, dialup-ios, dialup-android, dialup-windows, dialup-cisco, ... | custom | | GUI bookkeeping only. |
| `mode` | aggressive, main | main | | IKEv1 only. |
| `xauthtype` | disable, client, pap, chap, auto | disable | | IKEv1 only. |

Wizard defaults for Remote Access (FortiClient) per migration guide: Save Password enabled by default,
Auto Connect disabled, Always up disabled, keepalive 10, "EAP identity request", subnet
255.255.255.255 recommended; "Use Fortinet encapsulation ... Keep this option Disabled as FortiClient does
not support Fortinet Inc. encapsulation". [High]
https://docs.fortinet.com/document/fortigate/7.6.0/ssl-vpn-to-ipsec-vpn-migration/137787/part-2-configuring-ipsec-tunnels-using-the-vpn-wizard

EAP options in the GUI only from 7.6.1; before that CLI only. [Medium]
https://community.fortinet.com/fortigate-3/technical-tip-ipsec-dial-up-tunnel-using-ikev2-with-fortitoken-2fa-for-local-users-201395

---

## 3. Proposals, DH groups, lifetimes (phase 1 and phase 2 defaults)

- **IKEv2 phase 1 default proposal:** `aes128-sha256 aes256-sha256 aes128gcm-prfsha256 aes256gcm-prfsha384 chacha20poly1305-prfsha256`. [High]
  https://docs.fortinet.com/document/fortigate/7.6.4/administration-guide/238852/encryption-algorithms
  (identical in 7.4.4: https://docs.fortinet.com/document/fortigate/7.4.4/administration-guide/238852/encryption-algorithms)
- IKEv1 phase 1 default (for contrast): `aes128-sha256 aes256-sha256 aes128-sha1 aes256-sha1`. [High] (same URLs)
- **IKEv2 phase 2 default proposal:** `aes128-sha1 aes256-sha1 aes128-sha256 aes256-sha256 aes128gcm aes256gcm chacha20poly1305`. [High] (same URLs)
- Admin guide: AES-GCM and ChaCha20-Poly1305 "Only available for IKEv2"; "In IKEv2, encryption algorithms
  include authentication, but a PRF ... is still required (PRFSHA1, PRFSHA256, PRFSHA384, PRFSHA512)". [High]
  https://docs.fortinet.com/document/fortigate/7.6.0/administration-guide/790613/phase-1-configuration
- The full phase1 keyword list includes des/3des/aes128/192/256 x md5/sha1/sha256/384/512,
  aes128gcm/aes256gcm/chacha20poly1305 x prfsha1/256/384/512, aria*, seed*. Phase 2 adds `*-null`,
  `aes128gcm`, `aes256gcm`, `chacha20poly1305`. [High] CLI refs in section 2 and
  https://docs.fortinet.com/document/fortigate/7.6.3/cli-reference/252893715/config-vpn-ipsec-phase2-interface
- Mapping of keyword to IANA transforms, seen in Fortinet-published debug: `aes256-sha256` negotiates
  ENCR=AES_CBC(256), INTEGR=AUTH_HMAC_SHA2_256_128, PRF=PRF_HMAC_SHA2_256; an `AES128|SHA1` client proposal
  appears as AES_CBC(128), AUTH_HMAC_SHA_96, PRF_HMAC_SHA; child SA `aes256-sha256` appears as
  AES_CBC(256), INTEGR SHA256, ESN=NO. [Medium]
  https://community.fortinet.com/fortigate-3/technical-tip-understanding-the-ikev2-debugs-sa-init-and-ike-auth-144926
  https://community.fortinet.com/fortigate-3/technical-tip-how-to-configure-network-id-for-distinguishing-ikev2-ipsec-vpn-tunnels-using-forticlient-xml-file-223272
- DH: phase1 `dhgrp` default 14; phase2 `dhgrp` default 14 with `pfs enable`. [High] CLI refs.
  Fortinet examples for FortiClient commonly use `dhgrp 20 21` (e.g. custom TCP port and SAML pages). [High]
  https://docs.fortinet.com/document/fortigate/7.6.4/administration-guide/567401/dialup-ipsec-vpn-using-custom-tcp-port
- "The FortiGate matches the most secure proposal to negotiate with the peer." [High]
  https://docs.fortinet.com/document/fortigate/7.6.4/administration-guide/238852/encryption-algorithms

Phase 2 (`config vpn ipsec phase2-interface`) defaults, 7.6.3 CLI [High]
https://docs.fortinet.com/document/fortigate/7.6.3/cli-reference/252893715/config-vpn-ipsec-phase2-interface

| Option | Default |
|---|---|
| `pfs` | enable |
| `dhgrp` | 14 |
| `replay` | enable |
| `keylife-type` | seconds |
| `keylifeseconds` | 43200 (120..172800) |
| `keylifekbs` | 5120 |
| `encapsulation` | tunnel-mode |
| `src-subnet` / `dst-subnet` | 0.0.0.0 0.0.0.0 |
| `auto-negotiate` | disable |
| `keepalive` | disable |
| `add-route` | phase1 (follow phase1 setting) |
| `dhcp-ipsec` | disable |
| `initiator-ts-narrow` | disable |
| `single-source` | disable |
| `route-overlap` | use-new |

---

## 4. Transport: UDP, NAT-T, custom ports, TCP (RFC 8229/9329), Fortinet ESP

- UDP IKE port: `config system settings / set ike-port` (default 500). 7.6.4 CLI range 1024..65535;
  7.6.5 allows 443. [High]
  https://docs.fortinet.com/document/fortigate/7.6.4/cli-reference/130421147/config-system-settings
  https://docs.fortinet.com/document/fortigate/7.6.0/new-features/572770/allow-udp-port-443-for-dialup-ipsec-vpn-7-6-5
- With a custom UDP IKE port behind NAT, traffic "remains on port 5000 since NAT-T floating to 4500 is only
  required when the IKE port is 500". [High]
  https://docs.fortinet.com/document/fortigate/7.6.4/administration-guide/33578/configurable-udp-port-for-ike
- `ike-tcp-port` default: **4500 in 7.4.x and 7.6.0; 443 from 7.6.1**. Upgraded boxes may keep 4500. [High]
  https://docs.fortinet.com/document/fortigate/7.4.8/cli-reference/130421147/config-system-settings
  https://docs.fortinet.com/document/fortigate/7.6.0/cli-reference/130421147/config-system-settings
  https://docs.fortinet.com/document/fortigate/7.6.1/cli-reference/130421147/config-system-settings
  https://community.fortinet.com/fortigate-3/technical-tip-using-the-same-tcp-port-for-ipsec-saml-authentication-and-ike-tcp-encapsulation-in-fortios-v7-6-1-215779
- TCP encapsulation "in accordance with RFC 8229"; "only works with IKE version 2, and it does not support
  ADVPN or NPU offloading". FortiClient dial-up needs the RFC 8229 mode (`fortinet-esp disable`, the
  default); `fortinet-esp enable` = "non-standard TCP headers", FortiGate to FortiGate only. [High]
  https://docs.fortinet.com/document/fortigate/7.6.4/administration-guide/351073/encapsulate-esp-packets-within-tcp-headers
  KB: "fortinet-esp is a legacy protocol used only for FortiGate-FortiGate tunnels". [Medium]
  https://community.fortinet.com/fortigate-3/technical-tip-using-the-same-tcp-port-for-ipsec-saml-authentication-and-ike-tcp-encapsulation-in-fortios-v7-6-1-215779
- When `ike-tcp-port` is not 4500, "the IKE daemon listens on port 4500 and port 11443 while traffic enters
  on the ike-tcp-port and redirects to port 11443"; KB warns port 11443 conflicts with `admin-sport 11443`.
  Changing `ike-tcp-port` flushes all IPsec tunnels. [High/Medium]
  https://docs.fortinet.com/document/fortigate/7.6.4/administration-guide/351073/encapsulate-esp-packets-within-tcp-headers
  https://community.fortinet.com/fortigate-3/technical-tip-using-the-same-tcp-port-for-ipsec-saml-authentication-and-ike-tcp-encapsulation-in-fortios-v7-6-1-215779
- Port conflicts: TCP 443 vs admin GUI `admin-sport` (default 443), vs Agentless VPN / ZTNA (these take
  precedence), vs VIPs. [High] (same two URLs, and
  https://docs.fortinet.com/document/fortigate/7.6.4/administration-guide/567401/dialup-ipsec-vpn-using-custom-tcp-port)
- On a shared TCP port, FortiGate's iked demultiplexes: debug shows
  `accepts ike tcp-transport ... NOT IKETCP(), assign to AUTH` for SAML HTTPS. This matches the RFC 9329
  stream prefix: every TCP stream "MUST begin with ... the characters "IKETCP"" (0x49 0x4b 0x45 0x54 0x43
  0x50), sent once by the TCP originator, then 16-bit Length + (non-ESP marker + IKE) or ESP. [Medium, inferred]
  https://community.fortinet.com/fortigate-3/technical-tip-using-the-same-tcp-port-for-ipsec-saml-authentication-and-ike-tcp-encapsulation-in-fortios-v7-6-1-215779
  https://www.rfc-editor.org/rfc/rfc9329 (obsoletes RFC 8229; section 3 framing, section 4 prefix) `[TRACE]`
- Auto mode: "use UDP transport for IKE and ESP, with automatic fallback to TCP transport if UDP attempt
  fails for timeout threshold" (15 s). [High]
  https://docs.fortinet.com/document/fortigate/7.6.4/administration-guide/351073/encapsulate-esp-packets-within-tcp-headers
  https://docs.fortinet.com/document/fortigate/7.6.4/administration-guide/442351/ldap-authentication-with-ikev2-using-udp-or-tcp-as-transport
- FortiClient side: `<transport_mode>` 0 UDP, 1 TCP, 2 Auto; for Auto on FortiOS 7.4.2+ Fortinet says set
  `nattraversal forced` + `transport udp-fallback-tcp` (7.4) or `transport auto` (7.6). [High]
  https://docs.fortinet.com/document/forticlient/7.4.5/xml-reference-guide/96295/ike-settings
- `diagnose vpn ike gateway list` shows `transport: TCP` and the TCP port in `addr:`. [High]
  https://docs.fortinet.com/document/fortigate/7.6.4/administration-guide/567401/dialup-ipsec-vpn-using-custom-tcp-port

---

## 5. IKE_SA_INIT: what FortiClient sends, what FortiGate answers

### 5.1 FortiClient vendor IDs and notifies (Fortinet-published debug)

From FortiGate debug of a FortiClient IKEv2 SA_INIT [Medium]
https://community.fortinet.com/fortigate-3/technical-tip-how-to-configure-network-id-for-distinguishing-ikev2-ipsec-vpn-tunnels-using-forticlient-xml-file-223272

```
responder received SA_INIT msg
VID forticlient connect license 4C53427B6D465D1B337BB755A37A7FEF
VID Fortinet Endpoint Control B4F01CA951E9DA8D0BAFBBD34AD3044E
VID Forticlient EAP Extension C1DC4350476B98A429B91781914CA43E
received notify type NAT_DETECTION_SOURCE_IP
received notify type NAT_DETECTION_DESTINATION_IP
received notify type VPN_NETWORK_ID
NETWORK ID : 2
```

- The three VIDs are 16-byte values printed with names by FortiGate. What each VID enables is **Not
  publicly documented**. The "Forticlient EAP Extension" name, together with KB 219452's statement that MFA
  prompts need "proprietary EAP extensions", suggests the gateway gates its token prompt on this VID. [Low] `[TRACE]`
- `VPN_NETWORK_ID`: Fortinet-proprietary, "in the first initiator message of an IKEv2 phase 1
  negotiation", value 0..255, must match `network-id`; without it, dial-in clients match "the 1st Phase1
  configuration that uses IKEv2". Its notify type number and encoding are **Not publicly documented**
  (IANA reserves 40960..65535 for private-use status notifies). [High for semantics]
  https://docs.fortinet.com/document/fortigate/7.6.0/administration-guide/790613/phase-1-configuration
  https://community.fortinet.com/fortigate-3/technical-tip-fortigate-hub-with-multiple-ipsec-dial-up-phase1-using-ikev2-and-psk-authentication-152361
  https://www.iana.org/assignments/ikev2-parameters `[TRACE]`
- FortiClient network-id support: Windows/macOS 7.2.6, Linux 7.2.7, all 7.4.1+; not in the FortiClient GUI;
  `<networkid>` "not supported on FortiClient iOS or Android". [Medium]
  https://community.fortinet.com/forticlient-4/technical-tip-forticlient-support-for-multiple-ikev2-dialup-tunnels-at-the-same-fortigate-remote-gateway-address-215982
  https://docs.fortinet.com/document/forticlient/7.4.5/xml-reference-guide/96295/ike-settings
  (The FortiClient 8.0 Android guide lists "Network ID: Supported", so this changed in 8.0. [Medium]
  https://docs.fortinet.com/document/forticlient/8.0.0/android-administration-guide/189805/creating-an-ipsec-vpn-ikev2-connection)
- FortiClient `<sase_mode>`: forces port 4500 from the first message and "IKE_SA_INIT also has the EMS serial
  number as its payload" (payload type **Not publicly documented**). [High]
  https://docs.fortinet.com/document/forticlient/7.4.5/xml-reference-guide/96295/ike-settings

### 5.2 FortiGate SA_INIT response (FortiGate-to-FortiGate example; decoded by me)

Hex from https://community.fortinet.com/fortigate-3/technical-tip-understanding-the-ikev2-debugs-sa-init-and-ike-auth-144926
decoded per RFC 7296 and IANA [Medium]:
- Initiator SA_INIT: SA, KE (group 5), Ni (32 bytes), N(16388 NAT_DETECTION_SOURCE_IP),
  N(16389 NAT_DETECTION_DESTINATION_IP), N(16430 IKEV2_FRAGMENTATION_SUPPORTED). No VID.
- Responder SA_INIT: SA, KE, Nr (16 bytes), N(16388), N(16389), N(16430). **No VID, no CERTREQ.**
- IKE_AUTH (PSK site-to-site): IDi (ID_IPV4_ADDR), N(16384 INITIAL_CONTACT), AUTH (method 2),
  N(16420 IKEV2_MESSAGE_ID_SYNC_SUPPORTED, RFC 6311), SA, TSi, TSr. Response: IDr, AUTH(2), N(16420), SA, TSi, TSr.
- FortiGate SK padding pattern in the plaintext dump: descending bytes N..1 followed by pad length N.
- Registry values: https://www.iana.org/assignments/ikev2-parameters
- Whether FortiGate returns vendor IDs to a FortiClient initiator is **Not publicly documented**. `[TRACE]`

### 5.3 Other SA_INIT-time behaviour
- `remote-gw-match` (IKEv2 dial-up only) picks a phase1 by client source IP subnet, range, country or
  ZTNA tags. [High] https://docs.fortinet.com/document/fortigate/7.6.0/administration-guide/790613/phase-1-configuration
- IKE phase1 type cannot be changed after creation (tun_id). [High] (same URL)

---

## 6. IKE_AUTH: how the responder authenticates when users use EAP

### 6.1 PSK responder + EAP (the default migration design)

Fortinet: FortiClient "authenticates FortiGate using pre-shared key or signature authentication, then proves
ownership ... using EAP-MSCHAPv2 or EAP-TTLS". [High]
https://docs.fortinet.com/document/fortigate/8.0.0/administration-guide/913974/eap-user-authentication

Decoded FortiGate first IKE_AUTH response (plaintext `enc` hex published in FortiClient docs) [Medium]
https://docs.fortinet.com/document/forticlient/7.4.5/ems-quickstart-guide/745658/troubleshooting-ipsec-vpn-ikev2-with-saml-authentication

```
enc 2700000C010000000A80CCE0 3000002802000000<32 bytes> 000000090196000501 020102
IDr   : type 1 (ID_IPV4_ADDR) 10.128.204.224     (the gateway's IP)
AUTH  : method 2 (Shared Key Message Integrity Code), 32-byte MIC (SHA-256 PRF)
EAP   : Code 1 Request, Identifier 0x96, Length 5, Type 1 (Identity)
pad   : 02 01 | pad length 02
```
- So with `authmethod psk` + `eap enable` + `eap-identity send-request`, message 4 carries IDr + AUTH(PSK) +
  EAP-Request/Identity, with no CERT. [Medium] `[TRACE]` for our gateway.
- RFC 7296 2.16 says EAP methods "MUST be used in conjunction with a public-key-signature-based
  authentication of the responder". FortiGate's PSK-responder mode is outside that. [High]
  https://www.rfc-editor.org/rfc/rfc7296 (section 2.16)
- Final AUTH after EAP Success: RFC says both sides use the EAP MSK as the shared key for messages 7/8.
  Whether FortiGate uses MSK or the PSK there is **Not publicly documented**. `[TRACE]`
- Same debug shows what FortiGate extracts from FortiClient's IKE_AUTH request before replying:
  `received FCT-UID`, `received EMS SN`, `received EMS tenant ID`. Payload types **Not publicly documented**.
  A PSK mismatch shows as the log stopping at `sent IKE msg (AUTH_RESPONSE)`. [Medium]
  (same FortiClient troubleshooting URL)
- `gw validation failed` appears when EAP is disabled on one side or local/peer ID mismatch. [Medium] (same URL)

### 6.2 Signature responder (+ optional client cert, + EAP)
- `authmethod signature` + `certificate <local cert>`; `eap-cert-auth enable` + `peer <user peer>` makes the
  FortiGate validate the FortiClient X.509 cert and then run EAP (7.4.2+). With `eap-cert-auth disable` the
  client cert is not validated even if sent. [High]
  https://docs.fortinet.com/document/fortigate/7.6.4/administration-guide/298520/ipsec-ikev2-vpn-2fa-with-eap-and-certificate-authentication
- Debug of that flow: `received FCT-UID`, `received peer identifier DER_ASN1_DN`, `certificate validation before
  eap pending`, `responder preparing EAP identity request`, `local cert, subject='test1'`, then
  `EAP ... result FNBAM_CHALLENGED`, `responder preparing EAP pass through message`. [High] (same URL)
- FortiClient (Android, 8.0 guide, "built-in Android IKEv2 client"): username/password requires FortiGate
  `authmethod signature` with an **RSA** server cert (ECDSA not accepted), full chain uploaded, `peertype any`,
  `set cert-id-validation disable`; "The FortiClient IKEv2 client cannot combine authentication methods". [High]
  https://docs.fortinet.com/document/forticlient/8.0.0/android-administration-guide/189805/creating-an-ipsec-vpn-ikev2-connection
- FortiClient `<cert_subjectcheck>`: validates gateway hostname against the phase1 cert CN when enabled. [High]
  https://docs.fortinet.com/document/forticlient/7.4.5/xml-reference-guide/96295/ike-settings

### 6.3 Identity
- `eap-identity send-request`: FortiGate sends EAP-Request/Identity (see 6.1). `use-id-payload`: identity from
  IDi. [High] CLI ref (section 2).
- FortiClient IDi in dial-up debug shows as `peer-id: <client IP>` or a configured local ID. [Medium]
  https://docs.fortinet.com/document/fortigate/7.6.4/administration-guide/951346/saml-based-authentication-for-forticlient-remote-access-dialup-ipsec-vpn-clients

---

## 7. EAP methods, backends, MFA

### 7.1 Methods and where EAP terminates
- "FortiClient IKEv2 only supports initiating EAP-MSCHAPv2 and EAP-TTLS"; default EAP-MSCHAPv2; the FortiOS
  internal RADIUS (eap_proxy) supports other methods and "properly configured third-party VPN clients
  supporting other EAP methods may authenticate successfully". [High]
  https://docs.fortinet.com/document/fortigate/8.0.0/administration-guide/913974/eap-user-authentication
  https://community.fortinet.com/fortigate-3/technical-tip-fortios-ikev2-eap-user-authentication-operation-217759
- External RADIUS: FortiGate passes EAP through (EAP-TTLS goes end to end, inner PAP required); only one
  RADIUS server per dial-up gateway. [High] (same URLs)
- No external RADIUS (local users, LDAP): EAP-TTLS terminates on FortiGate's internal RADIUS, then plaintext
  credentials checked against local users / LDAP. TLS cert = `config system global / set wifi-certificate`
  (default `Fortinet_Wifi`, publicly signed). [High] (same URLs, and
  https://docs.fortinet.com/document/fortigate/7.6.4/cli-reference/339914554/config-system-global)
- "FortiGate cannot authenticate Active Directory users against an LDAP server directly using EAP-MSCHAPv2". [High] (same)
- LDAP over IKEv2 needs EAP-TTLS (FortiClient 7.4.3+). [High]
  https://docs.fortinet.com/document/fortigate/7.6.0/ssl-vpn-to-ipsec-vpn-migration/405532/ldap-based-user-authentication
- FortiClient XML `<eap_method>`: 1 = EAP-MSCHAPv2 (default), 2 = EAP-TTLS/PAP; iOS/Android 7.4 lack
  EAP-TTLS (8.0 adds it). [High]
  https://docs.fortinet.com/document/forticlient/7.4.5/xml-reference-guide/96295/ike-settings
  https://docs.fortinet.com/document/forticlient/7.4.0/new-features/907253/eap-ttls-support-for-ipsec-vpn-7-4-3
- eap_proxy debug of EAP-TTLS shows `respMethod=21` (EAP-TTLS type 21). [Medium]
  https://community.fortinet.com/fortigate-3/troubleshooting-tip-eap-ttls-connection-failing-with-forticlient-and-ipsec-ikev2-connection-due-to-certificate-error-207702
  https://www.iana.org/assignments/eap-numbers
- RADIUS server must support EAP-MSCHAPv2 for FortiClient's default (e.g. NPS "Microsoft: Secured password
  (EAP-MSCHAP v2)"). [Medium]
  https://community.fortinet.com/fortigate-3/technical-tip-ikev2-dial-up-ipsec-tunnel-with-radius-and-fortitoken-mfa-112975
- RFC note: initiator must tolerate at least ten IKE_AUTH round trips for prompts/retries. [High]
  https://www.rfc-editor.org/rfc/rfc7296 (section 2.16)

### 7.2 FortiToken, push, email/SMS

- "FortiGate triggering MFA prompts for IKEv2 Dialup Gateway clients relies on proprietary EAP extensions. It
  is only supported when FortiClient is used." And: "Fortinet uses a proprietary EAP extension to trigger the
  token code prompt ... Manual OTP code entry or FortiToken mobile push for other VPN clients is not
  supported." [High]
  https://community.fortinet.com/fortigate-3/technical-tip-required-firmware-software-versions-for-using-fortitoken-mobile-or-otp-mfa-with-fortigate-ikev2-dialup-ipsec-219452
- Version floors (same KB): EAP-MSCHAPv2 manual code entry FortiOS 6.2.4 / FortiClient 6.2.1; FTM push
  FortiOS 7.2.8, 7.4.4, 7.6.0 (manual entry broken while push configured until 7.4.8 / 7.6.5); EAP-TTLS 2FA
  FortiOS 7.4.9 / 7.6.1, FortiClient Windows 7.4.4, no FortiAuthenticator support. [High]
- Local-user FortiToken over IKEv2 EAP-MSCHAPv2 debug when no code yet: `FNBAM_NEED_TOKEN`,
  `EAP requires token for user`, `responder preparing EAP pass through message`. [Medium]
  https://community.fortinet.com/fortigate-3/technical-tip-ipsec-dial-up-tunnel-using-ikev2-with-fortitoken-2fa-for-local-users-201395
- **How the code is requested on the wire (MSCHAPv2 retry, EAP-GTC, expanded type, notify): Not publicly
  documented.** `[TRACE]` (our own client can log decrypted EAP payloads since it holds SK_e*).
- Concatenation workaround (documented for FortiClient iOS and generally for IPsec): enter `password + code`
  (`p@ssw0rd345678`); debug `2fa code has already been verified in concatenated password`. [Medium]
  https://community.fortinet.com/fortigate-3/technical-tip-ipsec-dial-up-tunnel-using-ikev2-with-fortitoken-2fa-for-local-users-201395
  https://community.fortinet.com/fortigate-3/technical-tip-ikev2-dial-up-ipsec-tunnel-with-radius-and-fortitoken-mfa-112975
- "In IPsec (whether IKEv1 or IKEv2, with XAuth or EAP-MSCHAPv2), the protocol doesn't have a separate
  parameter for OTP ... FortiClient with a Windows device always sends the password and OTP concatenated ...
  FortiGate ... Takes the last 6-digit token from the received string. Validates that OTP against the assigned
  FortiToken. Validates the remaining portion against the user's password." [Medium]
  https://community.fortinet.com/fortigate-3/technical-tip-full-and-split-dialup-ikev1-ipsec-tunnel-with-fortitoken-2fa-180854
  (How FortiGate splits an MSCHAPv2 response, which never reveals the password, is **Not publicly documented**.)
- **Email/SMS OTP:** Fortinet lists email and SMS as IKEv2 MFA methods where "FortiGate or FortiAuthenticator
  delivers the OTP ... User enters OTP on FortiClient, similar to FortiToken use cases." [Medium]
  https://community.fortinet.com/fortigate-3/technical-tip-fortios-ikev2-dial-up-vpn-user-and-multi-factor-authentication-resources-220170
  But: "Since an email or SMS token can only be received after entering the username and password, token
  concatenation for EAP-TTLS does not work with SMS or Email as a two-factor method." [Medium]
  https://community.fortinet.com/fortiauthenticator-8/technical-tip-how-to-resolve-the-eap-authentication-failed-due-to-missing-token-error-when-using-eap-ttls-pap-2fa-authentication-216311
  Whether an email code can be obtained by a non-FortiClient initiator over EAP-MSCHAPv2 (e.g. a first attempt
  that triggers the email, then a second attempt with password+code within the code lifetime) is **Not
  publicly documented**. `[TRACE]`
- Before FortiOS 7.4.9, FortiClient 7.4.4 with EAP-TTLS got no token prompt and FortiGate logged `2FA=no`
  (auth succeeded without the second factor); with EAP-MSCHAPv2 a prompt appeared and `2FA=yes`. [Medium]
  https://community.fortinet.com/fortigate-3/technical-tip-dial-up-ipsec-ra-authentication-using-forticlient-v7-4-4-and-2fa-215091
- Timeouts: default `negotiate-timeout` 30 s may expire while the user types the OTP; raise to 50..120.
  RADIUS MFA: raise `config user radius / set timeout` (e.g. 60) and `config system global / set
  remoteauthtimeout` (default 5 s). LDAP remote timeout cannot be extended for IKEv2 EAP (planned 7.6.7). [High/Medium]
  https://docs.fortinet.com/document/fortigate/8.0.0/administration-guide/913974/eap-user-authentication
  https://community.fortinet.com/fortigate-3/technical-tip-required-firmware-software-versions-for-using-fortitoken-mobile-or-otp-mfa-with-fortigate-ikev2-dialup-ipsec-219452
  https://community.fortinet.com/fortigate-3/technical-tip-multi-factor-authentication-support-for-windows-forticlient-with-ldap-eap-ttls-212498 (7.6.7 LDAP enhancement)
  https://docs.fortinet.com/document/fortigate/7.6.4/cli-reference/339914554/config-system-global
- FortiAuthenticator: RADIUS policy option "Allow OTP for EAP-MSCHAPv2 Authentication with Forticlient"
  (needs Password/OTP auth with Accept EAP > EAP-MSCHAPv2). Mechanism not described. [High]
  https://docs.fortinet.com/document/fortiauthenticator/8.0.1/administration-guide/416152/policies
  A FortiAuthenticator debug in a failing case shows `EAP-Message = 0x0101000f0650617373776f72643a20`, which
  decodes (RFC 3748) to EAP Request, id 1, type 6 (GTC), text "Password: ". Context is ambiguous; do not treat as
  FortiGate behaviour. [Low]
  https://community.fortinet.com/fortiauthenticator-8/troubleshooting-tip-token-prompt-not-received-for-ipsec-dial-up-vpn-and-eap-password-failure-error-received-221876
  https://www.iana.org/assignments/eap-numbers
- FortiToken Mobile push infrastructure on FortiGate: `config system ftm-push` (server-port default 4433),
  proxy `push.fortinet.com`. [High]
  https://docs.fortinet.com/document/fortigate/7.6.4/administration-guide/927108/fortitoken-mobile-push
- Compatibility table (KB): IKEv2 local users, any 2FA on FortiGate, FTM push from 7.2.8; RADIUS: 3rd-party RADIUS
  triggering OTP as second factor not supported; LDAP needs FortiClient 7.4.2+ with EAP-TTLS, 2FA from FortiClient
  7.4.4 + FortiOS 7.4.9/7.6.1. [Medium]
  https://community.fortinet.com/fortigate-3/technical-tip-overview-of-compatible-ike-versions-user-authentication-methods-and-fortigate-forticlient-firmware-versions-218991
- MFA with EAP-TTLS LDAP: FortiToken on FortiGate users works for FortiClient Windows 7.4.4 managed by EMS, not
  the free VPN-only client. [Medium]
  https://community.fortinet.com/fortigate-3/technical-tip-multi-factor-authentication-support-for-windows-forticlient-with-ldap-eap-ttls-212498
- Diagnostics shown by `diagnose vpn ike gateway list`: `eap-user:`, `2FA: yes|no`, `groups:`,
  `FortiClient UID:`. [High]
  https://community.fortinet.com/fortigate-3/technical-tip-dial-up-ipsec-ikev2-with-ldap-authentication-and-2fa-with-fortitoken-fortitoken-cloud-220763

---

## 8. SAML over IKEv2 (FortiOS 7.2+, FortiClient 7.2.4+)

- Requires IKEv2; `eap enable` still required because "SAML authentication is not an EAP method"; FortiClient
  then "proves ownership of the cached user authentication by authenticating itself against the FortiGate
  eap_proxy using EAP-MSCHAPv2 or EAP-TTLS". [High]
  https://docs.fortinet.com/document/fortigate/8.0.0/administration-guide/913974/eap-user-authentication
- Port: `config system global / set auth-ike-saml-port` (0..65535, default **1001**), served by authd. 7.6.1+:
  can share the `ike-tcp-port` (then `ike-tcp-port` wins and `auth-ike-saml-port` must be a different, unused
  value). [High]
  https://docs.fortinet.com/document/fortigate/7.6.4/administration-guide/951346/saml-based-authentication-for-forticlient-remote-access-dialup-ipsec-vpn-clients
  https://community.fortinet.com/fortigate-3/technical-tip-using-the-same-tcp-port-for-ipsec-saml-authentication-and-ike-tcp-encapsulation-in-fortios-v7-6-1-215779
- Binding: `config system interface / set ike-saml-server <saml server>` on the first interface the client hits;
  SP cert: `config user setting / set auth-cert`; CN should match gateway FQDN. One SAML IdP per interface. [High] (same URLs, and
  https://community.fortinet.com/forticlient-4/technical-tip-forticlient-support-for-multiple-ikev2-dialup-tunnels-at-the-same-fortigate-remote-gateway-address-215982)
- SP URLs (`config user saml`): `entity-id http://<fqdn>[:port]/remote/saml/metadata/`,
  `single-sign-on-url https://<fqdn>[:port]/remote/saml/login`, `single-logout-url .../remote/saml/logout`. [High]
  https://community.fortinet.com/fortigate-3/technical-tip-using-the-same-tcp-port-for-ipsec-saml-authentication-and-ike-tcp-encapsulation-in-fortios-v7-6-1-215779
  https://docs.fortinet.com/document/fortigate/7.6.4/administration-guide/432396/configuring-microsoft-entra-id-as-saml-idp-and-fortigate-as-saml-sp
- Flow (Fortinet's words): client connects to `auth-ike-saml-port`; FortiGate returns a redirect carrying the
  SAML AuthnRequest; client (browser) authenticates at IdP; client posts the SAML Response to FortiGate; FortiGate
  "provides FortiClient with a temporary token ID"; client then runs IKEv2 and "presents the token ID for
  authentication". [High]
  https://docs.fortinet.com/document/fortigate/7.6.4/administration-guide/951346/saml-based-authentication-for-forticlient-remote-access-dialup-ipsec-vpn-clients
- Debug evidence: authd `SAML login with UID '19E1...'` and a redirect to `https://<gw>:9443/saml?<hex>`; fnbamd
  creates an auth cache entry with `user='<FortiClient UID>'`; IKE shows `EAP user "<FortiClient UID>"`. So the
  EAP identity in SAML mode is the FortiClient UID. [Medium] (same URL, and
  https://docs.fortinet.com/document/forticlient/7.4.5/ems-quickstart-guide/745658/troubleshooting-ipsec-vpn-ikev2-with-saml-authentication)
- The exact initial HTTP request path, how the token ID is returned to the client, and what EAP secret is used
  with the UID are **Not publicly documented**. `[TRACE]`
- External browser for IPsec SAML: FortiOS 7.6.1+ or 7.4.9+, FortiClient Win/mac 7.2.5 / 7.4.1, Linux 7.4.3;
  below FortiOS 7.4.9 only the internal browser. [High/Medium]
  https://docs.fortinet.com/document/fortigate/7.6.4/administration-guide/951346/saml-based-authentication-for-forticlient-remote-access-dialup-ipsec-vpn-clients
  https://community.fortinet.com/forticlient-4/technical-tip-forticlient-saml-authentication-configuration-demystified-194700
- FortiClient XML: `<sso_enabled>`, `<use_external_browser>` (auto-on for IKEv2 + SSO), `<ike_saml_port>`;
  EMS docs say XAuth must be enabled for IKEv2 SAML tunnels and "when XAuth is enabled, user authentication is
  handled using EAP". [High]
  https://docs.fortinet.com/document/forticlient/7.4.5/xml-reference-guide/96295/ike-settings
  https://docs.fortinet.com/document/forticlient/7.4.7/ems-administration-guide/712604/ipsec-vpn-saml-based-authentication
- SAML debug also shows `sent tunnel-up message to EMS: (fct-uid=..., intf=..., addr=...)`. [Medium] (SAML admin URL)

---

## 9. Mode-cfg (configuration payload) and routing

- Attributes FortiGate sends in IKEv2, from Fortinet debug: `mode-cfg assigned (1) IPv4 address`,
  `(2) IPv4 netmask`, `mode-cfg send (13) 0:0.0.0.0/0.0.0.0:0` (full tunnel) or one `(13)` per split-include
  subnet, `mode-cfg send (3) IPv4 DNS(1)`. Numbers match IANA: 1 INTERNAL_IP4_ADDRESS, 2 INTERNAL_IP4_NETMASK,
  3 INTERNAL_IP4_DNS, 13 INTERNAL_IP4_SUBNET. [Medium]
  https://docs.fortinet.com/document/fortigate/7.6.4/administration-guide/951346/saml-based-authentication-for-forticlient-remote-access-dialup-ipsec-vpn-clients
  https://community.fortinet.com/support-forum-92/dial-up-ipsec-ikev2-split-tunnel-218924
  https://www.iana.org/assignments/ikev2-parameters
- `ipv4-netmask` default 255.255.255.255; Fortinet recommends /32 per client. [High] CLI ref; wizard guide.
- Split include/service/exclude semantics: split-include and split-include-service are "Applicable to IKEv1 and
  IKEv2"; split-exclude is documented under "Split-exclude in IKEv1"; `domain` (DNS suffix) is IKEv1 + unity only. [High]
  https://docs.fortinet.com/document/fortigate/7.4.9/administration-guide/526306/ike-mode-config-clients
- Split DNS: `internal-domain-list` "available on IKEv2 phase1 dialup gateways if mode-cfg is enabled"; client
  resolves only matching FQDNs through the tunnel DNS; if `dns-mode manual` without `ipv4-dns-server1`, tunnel DNS is
  0.0.0.0. [High]
  https://docs.fortinet.com/document/fortigate/7.6.4/administration-guide/836965/ipsec-split-dns
  Which CFG attribute carries the domains is **Not publicly documented** (IANA 25 INTERNAL_DNS_DOMAIN per RFC 8598
  is the standard candidate). A 7.6.7 forum report says the list was not applied with EAP dial-up. `[TRACE]`
  https://community.fortinet.com/support-forum-92/ipsec-dialup-split-dns-internal-domain-list-ignored-on-fortios-7-6-7-229047
- Traffic selectors: with `mode-cfg-allow-client-selector disable` (default) the client uses wildcard selectors.
  Tunnel list for a FortiClient shows `src: 0:0.0.0.0-255.255.255.255:0` and `dst: 0:<assigned IP>-<assigned IP>:0`,
  `add-route`. [High/Medium]
  https://docs.fortinet.com/document/fortigate/7.6.4/cli-reference/305883427/config-vpn-ipsec-phase1-interface
  https://docs.fortinet.com/document/fortigate/7.6.4/administration-guide/298520/ipsec-ikev2-vpn-2fa-with-eap-and-certificate-authentication
- Multiple ranges: `assign-ip-from name` + `ipv4-name <addrgrp>`. DHCP relay: `assign-ip-from dhcp`/phase2
  `dhcp-ipsec enable`. `ip-delay-interval` holds released IPs. [High]
  https://docs.fortinet.com/document/fortigate/7.6.4/administration-guide/155142/ssl-vpn-tunnel-mode-to-ipsec-vpn-migration
  https://docs.fortinet.com/document/fortigate/7.6.4/administration-guide/4729/ipsec-vpn-ip-address-assignments
- `net-device disable` (default, used by all Fortinet dial-up examples) = no per-client kernel interface. [High] CLI ref.

---

## 10. Liveness, rekey, resume, fragmentation

- DPD modes: `on-demand` default (probe only when outbound traffic gets no reply), `on-idle` (probe when idle).
  Admin guide text says "By default, dead peer detection (DPD) sends probe messages every five seconds", while
  FortiGate tunnel dumps for tunnels without an explicit interval show `dpd: mode=on-demand ... idle=20000ms retry=3`,
  and FortiClient's `<dpd_retry_interval>` default is 20 s. Treat 20 s as the likely effective default. [Medium] `[TRACE]`
  https://docs.fortinet.com/document/fortigate/7.6.0/administration-guide/790613/phase-1-configuration
  https://docs.fortinet.com/document/fortigate/7.6.4/administration-guide/298520/ipsec-ikev2-vpn-2fa-with-eap-and-certificate-authentication
  https://docs.fortinet.com/document/forticlient/7.4.5/xml-reference-guide/96295/ike-settings
- IKEv2 DPD is an INFORMATIONAL exchange (`send IKEv2 DPD probe`, `RETRANSMIT_INFORMATIONAL`). [Medium]
  https://docs.fortinet.com/document/fortigate/7.6.4/administration-guide/241386/resuming-sessions-for-ipsec-tunnel-ike-version-2
- NAT-T keepalive default 10 s (`keepalive`); tunnel dumps show `natt: mode=silent draft=32 interval=10`. Admin guide
  describes the keepalive as "a 138-byte ISAKMP exchange" (likely IKEv1 wording). [High/Medium] `[TRACE]`
  https://docs.fortinet.com/document/fortigate/7.6.0/administration-guide/790613/phase-1-configuration
  https://community.fortinet.com/fortigate-3/technical-tip-full-and-split-dialup-ikev1-ipsec-tunnel-with-fortitoken-2fa-180854
- Lifetimes: IKE SA 86400 s (`lifetime/rekey: 86400/...` in gateway list); child SA 43200 s default. [High] CLI refs.
- `client-resume`: FortiGate keeps the dial-up tunnel for `client-resume-interval` after the client disappears;
  debug `starting client-resume sleep period`, then on a new SA_INIT `client has resumed`. FortiClient
  `<session_resume>`. Mechanism (how the new SA_INIT is tied to the old SA) **Not publicly documented**. [Medium]
  https://docs.fortinet.com/document/fortigate/7.6.4/administration-guide/241386/resuming-sessions-for-ipsec-tunnel-ike-version-2
  https://docs.fortinet.com/document/forticlient/7.4.5/xml-reference-guide/96295/ike-settings
  Separate knob: `config system settings / set ike-session-resume` = RFC 5723 (default disable). [High]
  https://docs.fortinet.com/document/fortigate/7.6.4/cli-reference/130421147/config-system-settings
- IKEv2 fragmentation (RFC 7383): "if the IKE payloads are greater than a configured threshold, the IKE packets are
  preemptively fragmented and encrypted"; `fragmentation enable` default, `fragmentation-mtu` default 1200.
  FortiGate advertises IKEV2_FRAGMENTATION_SUPPORTED (16430) in SA_INIT; tunnel flags show `frag-rfc`. [High/Medium]
  https://docs.fortinet.com/document/fortigate/7.6.5/administration-guide/167137/choosing-ike-version-1-and-2
  https://community.fortinet.com/fortigate-3/technical-tip-understanding-the-ikev2-debugs-sa-init-and-ike-auth-144926
  https://www.rfc-editor.org/rfc/rfc7383
- Other system knobs: `ike-quick-crash-detect` (RFC 6290, default disable). [High] (system settings CLI URL)

---

## 11. FortiClient-specific extensions and knobs

| Item | What is documented | Wire format | Source |
|---|---|---|---|
| VID "forticlient connect license" `4C53427B6D465D1B337BB755A37A7FEF` | Seen in FortiClient SA_INIT | 16-byte VID; meaning not documented | KB 223272 |
| VID "Fortinet Endpoint Control" `B4F01CA951E9DA8D0BAFBBD34AD3044E` | Seen in FortiClient SA_INIT | meaning not documented | KB 223272 |
| VID "Forticlient EAP Extension" `C1DC4350476B98A429B91781914CA43E` | Seen in FortiClient SA_INIT | meaning not documented (likely gates the MFA prompt) | KB 223272, KB 219452 |
| `VPN_NETWORK_ID` notify | In SA_INIT, value 0..255 selects phase1 | type number not documented | Phase 1 config page, KB 223272 |
| FCT-UID, EMS SN, EMS tenant ID | Received by FortiGate in IKE_AUTH | not documented | FortiClient SAML troubleshooting |
| EMS serial in SA_INIT (`sase_mode`) | Documented | not documented | FortiClient XML IKE settings |
| Proprietary EAP extension for token prompt / push | Documented to exist, FortiClient only | not documented | KB 219452 |
| `save-password`, `client-auto-negotiate`, `client-keep-alive` | FortiGate-side policy pushed to FortiClient (Save Password, Auto Connect, Always Up); conflict with `unity-support` when setting them | not documented | KB 99089, FortiClient doc 437773 |
| `ems-sn-check`, `remote-gw-match ztna`, `cert-trust-store ems` | EMS integration | not documented | EMS SN page, phase1 page |
| `fortinet-esp` | Proprietary TCP ESP, not for FortiClient | not documented | ESP-in-TCP page |
| `dev-id-notification` | "device ID notification" | not documented | CLI ref |

URLs:
- KB 223272: https://community.fortinet.com/fortigate-3/technical-tip-how-to-configure-network-id-for-distinguishing-ikev2-ipsec-vpn-tunnels-using-forticlient-xml-file-223272
- KB 219452: https://community.fortinet.com/fortigate-3/technical-tip-required-firmware-software-versions-for-using-fortitoken-mobile-or-otp-mfa-with-fortigate-ikev2-dialup-ipsec-219452
- Phase 1 config: https://docs.fortinet.com/document/fortigate/7.6.0/administration-guide/790613/phase-1-configuration
- FortiClient SAML troubleshooting: https://docs.fortinet.com/document/forticlient/7.4.5/ems-quickstart-guide/745658/troubleshooting-ipsec-vpn-ikev2-with-saml-authentication
- FortiClient XML IKE settings: https://docs.fortinet.com/document/forticlient/7.4.5/xml-reference-guide/96295/ike-settings
- KB 99089: https://community.fortinet.com/fortigate-3/technical-tip-how-to-activate-save-password-auto-connect-and-always-up-in-forticlient-99089
- FortiClient 437773: https://docs.fortinet.com/document/forticlient/7.4.5/administration-guide/437773/save-password-auto-connect-and-always-up
- EMS SN: https://docs.fortinet.com/document/fortigate/7.6.4/administration-guide/260309/enhancing-ipsec-security-using-ems-sn-verification
- ESP-in-TCP: https://docs.fortinet.com/document/fortigate/7.6.4/administration-guide/351073/encapsulate-esp-packets-within-tcp-headers

Other FortiClient behaviours worth copying (documented):
- Always Up: reconnects silently if credentials saved; prompts if MFA required. [High] FortiClient 437773 URL.
- `<remove_password_for_unexpected_eap_failure>` refers to an "expiring due to EAP failure" message; FortiGate logs
  `connection expiring due to EAP failure` on failure. How that is signalled to the client is **Not publicly
  documented** (probably an EAP-Failure then no AUTH). [Low] `[TRACE]`
  https://docs.fortinet.com/document/forticlient/7.4.5/xml-reference-guide/96295/ike-settings

---

## 12. Android platform facts (developer.android.com)

- `Ikev2VpnProfile.Builder.setAuthUsernamePassword(user, pass, serverRootCa)` "will configure IKEv2 authentication
  using EAP-MSCHAPv2" and verifies the server with a root cert; `setAuthPsk` = PSK for both sides; "Only one
  authentication method may be set". Constructor `Builder(IkeTunnelConnectionParams)` allows full IKE params. [High]
  https://developer.android.com/reference/android/net/Ikev2VpnProfile.Builder
- `IkeSessionParams.Builder.setAuthEap(serverCaCert, eapConfig)`: EAP "MUST be used in conjunction with a
  public-key-signature-based authentication of the remote server, unless EAP-Only authentication is enabled";
  `setAuthPsk`: "Both client and server MUST be authenticated using the provided shared key". API 31+. [High]
  https://developer.android.com/reference/android/net/ipsec/ike/IkeSessionParams.Builder
  https://developer.android.com/reference/android/net/ipsec/ike/IkeSessionParams
- `EapSessionConfig.Builder` offers `setEapMsChapV2Config`, `setEapTtlsConfig`, `setEapIdentity`, SIM/AKA. [High]
  https://developer.android.com/reference/android/net/eap/EapSessionConfig.Builder
- Consequence: the platform IKE stack cannot express Fortinet's default "PSK responder + EAP initiator" design, nor
  RFC 9329 TCP transport, nor the proprietary VIDs/notifies. This matches FortiClient Android's documented need for a
  signature-authenticated FortiGate. Our own engine on `VpnService` would be needed for PSK+EAP gateways. [Medium, inference]
  https://docs.fortinet.com/document/forticlient/8.0.0/android-administration-guide/189805/creating-an-ipsec-vpn-ikev2-connection

---

## 13. Open questions (need a live trace against the real gateway)

1. Exact bytes of FortiGate's SA_INIT response to a FortiClient-like initiator: any VIDs? CERTREQ? which notifies?
2. Does our gateway use PSK (AUTH method 2) or signature in IKE_AUTH #1 when EAP is on? Which IDr type?
3. Final AUTH (messages 7/8) key: EAP MSK (RFC 7296) or the PSK?
4. Notify type number and payload layout of `VPN_NETWORK_ID`; is it needed when only one dial-up phase1 exists
   (`network-id 0`)?
5. What EAP message does FortiGate send after `FNBAM_NEED_TOKEN` (token/email OTP prompt)? Is it sent only if the
   "Forticlient EAP Extension" VID was present? What does a non-FortiClient initiator receive instead?
6. With email two-factor on a local user and EAP-MSCHAPv2: does a first attempt trigger the email, and can a second
   attempt with password+code succeed within the code lifetime (about a minute on our gateway)?
7. Split DNS attribute number for `internal-domain-list` (expect 25 INTERNAL_DNS_DOMAIN).
8. Does a dial-up phase1 with `transport tcp` still accept UDP IKE, and vice versa with `udp`? (server-side semantics of
   `transport` on a dynamic gateway are not spelled out).
9. TCP stream: confirm the "IKETCP" prefix is required by FortiGate on TCP 443 and that framing follows RFC 9329.
10. How `client-keep-alive` / `client-auto-negotiate` / `save-password` reach the client (proprietary CFG attributes?).
11. Effective DPD interval default (5 s vs 20 s) and NAT-T keepalive format for IKEv2.
12. Whether FortiGate requires INITIAL_CONTACT, FCT-UID or any Fortinet payload to accept an IKE_AUTH.
13. SAML: initial HTTPS path on `auth-ike-saml-port`, how the token ID reaches the client, and what EAP credential is used.

---

## 14. Source index

Fortinet docs
- https://docs.fortinet.com/document/fortigate/7.6.3/fortios-release-notes/173430/ssl-vpn-tunnel-mode-no-longer-supported
- https://docs.fortinet.com/document/fortigate/7.6.4/administration-guide/155142/ssl-vpn-tunnel-mode-to-ipsec-vpn-migration
- https://docs.fortinet.com/document/fortigate/7.6.4/administration-guide/567401/dialup-ipsec-vpn-using-custom-tcp-port
- https://docs.fortinet.com/document/fortigate/7.6.4/administration-guide/351073/encapsulate-esp-packets-within-tcp-headers
- https://docs.fortinet.com/document/fortigate/7.6.4/cli-reference/305883427/config-vpn-ipsec-phase1-interface
- https://docs.fortinet.com/document/fortigate/7.4.8/cli-reference/305883427/config-vpn-ipsec-phase1-interface
- https://docs.fortinet.com/document/fortigate/7.6.3/cli-reference/252893715/config-vpn-ipsec-phase2-interface
- https://docs.fortinet.com/document/fortigate/7.6.4/cli-reference/130421147/config-system-settings (also 7.6.0, 7.6.1, 7.4.8 variants)
- https://docs.fortinet.com/document/fortigate/7.6.4/cli-reference/339914554/config-system-global
- https://docs.fortinet.com/document/fortigate/7.6.4/administration-guide/238852/encryption-algorithms
- https://docs.fortinet.com/document/fortigate/7.4.4/administration-guide/238852/encryption-algorithms
- https://docs.fortinet.com/document/fortigate/7.6.0/administration-guide/790613/phase-1-configuration
- https://docs.fortinet.com/document/fortigate/7.6.5/administration-guide/167137/choosing-ike-version-1-and-2
- https://docs.fortinet.com/document/fortigate/7.6.4/administration-guide/298520/ipsec-ikev2-vpn-2fa-with-eap-and-certificate-authentication
- https://docs.fortinet.com/document/fortigate/8.0.0/administration-guide/913974/eap-user-authentication
- https://docs.fortinet.com/document/fortigate/7.6.4/administration-guide/951346/saml-based-authentication-for-forticlient-remote-access-dialup-ipsec-vpn-clients
- https://docs.fortinet.com/document/fortigate/7.6.4/administration-guide/432396/configuring-microsoft-entra-id-as-saml-idp-and-fortigate-as-saml-sp
- https://docs.fortinet.com/document/fortigate/7.6.4/administration-guide/836965/ipsec-split-dns
- https://docs.fortinet.com/document/fortigate/7.4.9/administration-guide/526306/ike-mode-config-clients
- https://docs.fortinet.com/document/fortigate/7.6.4/administration-guide/241386/resuming-sessions-for-ipsec-tunnel-ike-version-2
- https://docs.fortinet.com/document/fortigate/7.6.4/administration-guide/260309/enhancing-ipsec-security-using-ems-sn-verification
- https://docs.fortinet.com/document/fortigate/7.6.4/administration-guide/442351/ldap-authentication-with-ikev2-using-udp-or-tcp-as-transport
- https://docs.fortinet.com/document/fortigate/7.6.4/administration-guide/33578/configurable-udp-port-for-ike
- https://docs.fortinet.com/document/fortigate/7.6.0/new-features/572770/allow-udp-port-443-for-dialup-ipsec-vpn-7-6-5
- https://docs.fortinet.com/document/fortigate/7.6.4/administration-guide/785501/forticlient-as-dialup-client
- https://docs.fortinet.com/document/fortigate/7.6.4/administration-guide/4729/ipsec-vpn-ip-address-assignments
- https://docs.fortinet.com/document/fortigate/7.6.4/administration-guide/927108/fortitoken-mobile-push
- 7.6 migration guide pages: https://docs.fortinet.com/document/fortigate/7.6.0/ssl-vpn-to-ipsec-vpn-migration/878694/tunneling-protocol-and-encapsulation ,
  .../883534/ikev1-or-ikev2 , .../281804/authentication-method , .../405532/ldap-based-user-authentication ,
  .../446639/saml-based-user-authentication , .../403063/split-dns-and-dns-suffix , .../690046/customizing-ipsec-tunnel-settings ,
  .../137787/part-2-configuring-ipsec-tunnels-using-the-vpn-wizard
- FortiClient: https://docs.fortinet.com/document/forticlient/7.4.5/xml-reference-guide/96295/ike-settings ,
  https://docs.fortinet.com/document/forticlient/8.0.0/android-administration-guide/189805/creating-an-ipsec-vpn-ikev2-connection ,
  https://docs.fortinet.com/document/forticlient/7.4.5/ems-quickstart-guide/745658/troubleshooting-ipsec-vpn-ikev2-with-saml-authentication ,
  https://docs.fortinet.com/document/forticlient/7.4.7/ems-administration-guide/712604/ipsec-vpn-saml-based-authentication ,
  https://docs.fortinet.com/document/forticlient/7.4.0/new-features/907253/eap-ttls-support-for-ipsec-vpn-7-4-3 ,
  https://docs.fortinet.com/document/forticlient/7.4.4/ems-administration-guide/914884/ipsec-vpn-over-tcp ,
  https://docs.fortinet.com/document/forticlient/7.4.5/administration-guide/437773/save-password-auto-connect-and-always-up ,
  https://docs.fortinet.com/document/forticlient/7.2.10/ems-administration-guide/923380/ipsec-vpn-with-fortitoken-mobile-push-mfa
- FortiAuthenticator: https://docs.fortinet.com/document/fortiauthenticator/8.0.1/administration-guide/416152/policies

Fortinet community KB / forum
- 217759 EAP operation, 201395 FortiToken local, 218991 compatibility, 212498 EAP-TTLS MFA, 220170 MFA resources,
  219452 version floors + proprietary EAP extension, 112975 RADIUS + FortiToken, 220763 LDAP 2FA, 221876 FAC token prompt,
  213133 EAP-TTLS free client, 216311 missing token / email-SMS limitation, 215091 FortiClient 7.4.4 2FA,
  207702 EAP-TTLS cert, 144926 IKEv2 debugs (hex), 152361 network-id hub, 215982 FortiClient multi-tunnel,
  223272 network-id XML (VIDs), 215779 shared TCP port SAML, 194700 SAML browsers, 99089 save-password,
  180854 IKEv1 FortiToken (concatenation rules), 218924 split tunnel debug, 229047 split DNS 7.6.7.
  All under https://community.fortinet.com/ with the full URLs given inline above.

Standards and registries
- RFC 7296 (IKEv2): https://www.rfc-editor.org/rfc/rfc7296
- RFC 9329 (TCP encapsulation, obsoletes RFC 8229): https://www.rfc-editor.org/rfc/rfc9329
- RFC 7383 (IKEv2 fragmentation): https://www.rfc-editor.org/rfc/rfc7383
- IANA IKEv2 parameters: https://www.iana.org/assignments/ikev2-parameters
- IANA EAP numbers: https://www.iana.org/assignments/eap-numbers

Android
- https://developer.android.com/reference/android/net/Ikev2VpnProfile.Builder
- https://developer.android.com/reference/android/net/ipsec/ike/IkeSessionParams.Builder
- https://developer.android.com/reference/android/net/ipsec/ike/IkeSessionParams
- https://developer.android.com/reference/android/net/eap/EapSessionConfig.Builder
