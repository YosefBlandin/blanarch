# FortiGate SSL-VPN tunnel protocol: implementation spec

Status: draft 1 (2026-09-24). Describes the behaviour a client must implement to use
FortiGate SSL-VPN *tunnel mode* (FortiOS 7.6.2 and older; 7.6.3+ replaced it with IPsec).

This is a functional description of messages on the wire. It deliberately contains no code
from any existing client. Sections marked **[confirm by trace]** are to be checked against
a redacted trace of a real session (see §9) before release.

Sources: RFC 1661 (PPP), RFC 1332 (IPCP), RFC 1877 (IPCP DNS options), RFC 1570 (LCP
extensions), RFC 7230 (HTTP/1.1), Fortinet public documentation on SSL-VPN, SAML with an
external browser (FortiOS 7.0.1+) and FortiToken, and behaviour observed from a working
client against a FortiOS gateway.

---

## 1. Overview

1. The client opens TLS to the gateway (`host:port`, often 443 or a custom port like 10443).
2. Over HTTPS it authenticates and receives a session cookie named `SVPNCOOKIE`.
3. It fetches the tunnel settings (an XML document).
4. It opens a **new** TLS connection, sends one HTTP request that switches it to tunnel mode,
   and from then on the connection carries PPP frames in a small binary envelope (§5).
5. PPP (LCP, then IPCP) negotiates an IPv4 address and DNS servers; then IPv4 packets flow.

Every HTTP exchange may use its own TLS connection (send `Connection: close`).

## 2. TLS and server identity

- TLS 1.2+ with normal cipher suites. No SNI requirement; gateways are often addressed by IP.
- Gateways frequently use self-signed or private-CA certificates. The client identifies a
  gateway by the **SHA-256 digest of the leaf certificate's DER encoding**, written as 64
  lowercase hex characters. A profile may carry an expected digest ("pin").
  - Pin present and equal: proceed. Pin present and different: abort (certificate changed).
  - No pin and certificate not trusted by the system: ask the user (trust on first use) or,
    when a validated system trust chain exists, proceed.
- Hostname verification against the certificate is not meaningful when pinning.

## 3. HTTP authentication

All requests are HTTP/1.1 with these headers (values that matter in bold):

```
<METHOD> <path> HTTP/1.1
Host: <host>:<port>
User-Agent: Mozilla/5.0 SV1          (any browser-like value works)
Accept: */*
Content-Type: application/x-www-form-urlencoded
Cookie: SVPNCOOKIE=<value>           (only once logged in)
Connection: close
Content-Length: <n>
```

Bodies are `application/x-www-form-urlencoded`. Responses may use `Content-Length`,
`Transfer-Encoding: chunked`, or close-delimited bodies.

### 3.1 Response body format ("ret" values)

Login responses carry comma- or ampersand-separated `key=value` pairs, possibly across
lines, for example:

```
ret=2,actionurl=/remote/logincheck,tokeninfo=,reqid=123456,polid=1-1-2,grp=VPN_USERS,portal=full-access,magic=1-7a9f3c
```

Split on `&`, `,`, CR and LF; each piece is `key=value` (value may be empty; the key
`tokeninfo` with an empty value is meaningful). Values are used verbatim when echoed back.

- `ret=0`: credentials rejected.
- `ret=1`: accepted (the cookie is in `Set-Cookie`).
- `ret=2` with `tokeninfo`: a second factor is required (§3.3).
- `ret=3` with `tokeninfo`: also a second factor. Observed 2026-09-27 on a gateway that emails
  the code: `tokeninfo` then holds the masked, URL-encoded address the code was sent to, and a
  `chal_msg` key is present (empty). Treat any `tokeninfo` key as "second factor needed",
  whatever the `ret` value.
- `ret=6`: a challenge type the client does not support.

### 3.2 Step 1: username and password

```
POST /remote/logincheck
username=<u>&credential=<p>&realm=<realm>&ajax=1
```

All values URL-encoded. `realm` may be empty. Send step 1 **without** a session cookie: when
signing in again after a session ended, a stale SVPNCOOKIE makes the gateway answer HTTP 302
instead of evaluating the credentials (observed 2026-09-28). Outcomes:

| Response | Meaning |
|---|---|
| `Set-Cookie: SVPNCOOKIE=<non-empty>` | Logged in (no second factor) |
| body has `ret=0` | Wrong username or password |
| body has `tokeninfo` key, no cookie | Second factor needed (§3.3) |
| body has `ret=6` | Unsupported challenge |
| 200 with `Content-Type: text/html`, no `ret`/`tokeninfo` keys, SVPNCOOKIE cleared | Wrong username or password |
| HTTP status other than 200 | Error; report status |

A `Set-Cookie: SVPNCOOKIE=` with an **empty** value does not count as logged in.

Observed 2026-09-27 (own client against the user's gateway): a wrong password does **not**
return `ret=0`. The gateway answers 200 with its HTML login page ("SSL VPN Remote Access Web
Portal"), `Content-Type: text/html`, and `Set-Cookie` headers that expire SVPNCOOKIE and
SVPNNETWORKCOOKIE. The same request with the right password returns `text/plain` with
`ret=3,...,tokeninfo=...`. Treat the HTML page as rejected credentials, not as a protocol error,
so the client stops instead of retrying (retrying a wrong password can lock the account).

When a step-1 reply matches no row, report it without values: status, content type, whether
the body is HTML, empty or `key=value` (key names only), and whether the cookie was cleared.

### 3.3 Step 2: second factor (token)

The step-1 response carries these keys; echo them back unchanged:
`reqid`, `polid`, `grp`, `portal`, `magic`, `peer` (any may be absent → send empty).

- **Typed code** (FortiToken TOTP, SMS or email token). After step 1 the gateway sends the
  code by SMS/email when configured to; for FortiToken the user reads it from the app.

```
POST /remote/logincheck
username=<u>&realm=<realm>&reqid=<reqid>&polid=<polid>&grp=<grp>&portal=<portal>&peer=<peer>&code=<code>&code2=&magic=<magic>
```

- **FortiToken Mobile push**: when `tokeninfo` begins with `ftm_push`, the client may
  instead request a push approval: same body but replace `&code=<code>&code2=&magic=<magic>`
  with `&ftmpush=1`. The request completes when the user approves on the FortiToken app
  (the response then carries the cookie) or fails/times out. **[confirm by trace]** timeout
  length and the rejection body.

Success: `Set-Cookie: SVPNCOOKIE=<value>`. Anything else: the code was wrong or expired.

### 3.4 SAML / SSO (FortiOS 7.0.1+ with external browser)

1. Client listens on `http://127.0.0.1:<port>` (default port 8020, configurable per profile).
2. Client opens the system browser at `https://<host>:<port>/remote/saml/start?redirect=1`.
   The user signs in with the identity provider (Entra ID, Okta…), including any MFA.
3. The browser is redirected to `http://127.0.0.1:<port>/?id=<session-id>`. The client
   answers that request with a small "you can return to the app" page and reads `id`.
4. Client calls `GET /remote/saml/auth_id?id=<session-id>`; the response sets `SVPNCOOKIE`.
   **[confirm by trace]**

### 3.5 Session setup after login

With the cookie:
1. `GET /remote/index` (allocates the VPN session; response body ignored).
2. `GET /remote/fortisslvpn` (response ignored).
3. `GET /remote/fortisslvpn_xml` → tunnel settings (§4). Non-200 means the user has no
   tunnel-mode access.

### 3.6 Logout

`GET /remote/logout` with the cookie. Best effort.

### 3.7 Detecting the sign-in method (probe)

`GET /remote/login` (optionally `?realm=<realm>`) returns the gateway's HTML login page, possibly
after a redirect: the user's gateway answers `303 See Other` with `Location: /remote/login?lang=en`
(observed 2026-09-28). Follow up to two redirects whose `Location` is a path on the same gateway,
each on a new TLS connection, and read the final page.
**[confirm by trace]** A page that offers SSO contains a link or button targeting
`/remote/saml/start`; its absence means password sign-in. The probe also records the
certificate digest (§2).

The probe also tells the user early when a gateway can't be served:
- **SSL-VPN off.** The portal counts as present when `GET /remote/login` answers 200 with a
  page that mentions `logincheck` or "SSL VPN" (the user's gateway serves a page titled
  "SSL VPN Remote Access Web Portal", observed 2026-09-27). Otherwise SSL-VPN is off on this
  address, which is what FortiOS 7.6.3+ looks like once tunnel mode is removed
  **[confirm by trace on 7.6.3+]**. If the address also answers an IKEv2 probe
  (`fortigate-ipsec.md` §2), tell the user the server uses IPsec.
- **Client certificate required.** During the TLS handshake the server sends a
  CertificateRequest. Blanarch has no client certificates yet, so warn before sign-in; the
  user may still try, since some gateways ask without requiring one.
- Host check can only be seen after sign-in and is not detected yet **[confirm by trace]**.

## 4. Tunnel settings XML

Example (attribute quotes may be single or double; ignore unknown elements):

```xml
<?xml version='1.0' encoding='utf-8'?>
<sslvpn-tunnel ver='2' dtls='1' patch='1'>
  <dtls-config heartbeat-interval='10' heartbeat-fail-count='10' heartbeat-idle-timeout='3' client-hello-timeout='10'/>
  <tunnel-method value='ppp'/>
  <tunnel-method value='tun'/>
  <fos platform='FG100F' major='7' minor='2' patch='8' build='1639' branch='1639'/>
  <client-config save-password='off' keep-alive='on' auto-connect='off'/>
  <ipv4>
    <dns ip='10.0.0.53'/>
    <dns ip='10.0.0.54'/>
    <dns domain='corp.example'/>
    <assigned-addr ipv4='10.212.134.7'/>
    <split-tunnel-info>
      <addr ip='10.10.0.0' mask='255.255.0.0'/>
      <addr ip='192.168.50.0' mask='255.255.255.0'/>
    </split-tunnel-info>
  </ipv4>
  <idle-timeout val='3600'/>
  <auth-timeout val='28800'/>
</sslvpn-tunnel>
```

Use: `dns@ip` (DNS servers, fallback if IPCP gives none), `dns@domain` (search domain; may
contain several separated by `;`, `,` or spaces), `assigned-addr@ipv4` (informational),
`split-tunnel-info/addr` (routes as network + dotted mask). **No `split-tunnel-info`, or an
empty one, means route all traffic through the tunnel.** `client-config@save-password`
tells whether the admin allows saving the password (advisory).

## 5. Tunnel connection and framing

Open a new TLS connection (same pinning rules) and send exactly:

```
GET /remote/sslvpn-tunnel HTTP/1.1\r\n
Host: sslvpn\r\n
Cookie: SVPNCOOKIE=<value>\r\n
\r\n
```

There is **no HTTP response** on success: the stream immediately switches to frames. If the
first six bytes read are ASCII `HTTP/1`, the gateway refused tunnel mode (e.g. 403); report
"tunnel mode not allowed".

Each frame in both directions:

| Offset | Size | Field |
|---|---|---|
| 0 | 2 | total length = payload length + 6, big-endian |
| 2 | 2 | magic `0x50 0x50` |
| 4 | 2 | payload length, big-endian |
| 6 | n | payload: a PPP packet **without** HDLC framing (no flag, no address/control, no FCS, no byte stuffing) |

The payload begins with the 2-byte PPP protocol number (never compressed, see §6.1),
followed by the information field. Protocols: `0xC021` LCP, `0x8021` IPCP, `0x0021` IPv4.

Worked example: an LCP Echo-Request (id 7, magic `01 02 03 04`) is the 8-byte LCP packet
`09 07 00 08 01 02 03 04`, protocol `C0 21` → payload 10 bytes → frame
`00 10 50 50 00 0A C0 21 09 07 00 08 01 02 03 04`.

A frame whose lengths disagree (`total − 6 ≠ payload`, magic wrong, payload < 2) is a
protocol error: close the tunnel.

## 6. PPP negotiation (RFC 1661, 1332, 1877)

Control packets (LCP and IPCP share the format): `code (1) | identifier (1) | length (2) | data`.
Configuration options: `type (1) | length (1, includes these 2 bytes) | value`.

Codes: 1 Configure-Request, 2 Configure-Ack, 3 Configure-Nak, 4 Configure-Reject,
5 Terminate-Request, 6 Terminate-Ack, 7 Code-Reject, 8 Protocol-Reject (LCP only),
9 Echo-Request, 10 Echo-Reply, 11 Discard-Request (9–11 LCP only).

### 6.1 LCP

Client's Configure-Request: MRU (type 1, 2 bytes) = **1354**, Magic-Number (type 5, 4
random bytes). Resend every 3 s until acked (new identifier each time), for up to the
attempt timeout.

On the peer's Configure-Nak for our request: adopt the suggested MRU; choose a new random
magic if magic was Nak'd; resend. On Configure-Reject: drop the rejected options; resend.

For the peer's Configure-Request: acknowledge only MRU (1), ACCM (2) and Magic-Number (5).
**Reject** everything else, notably Authentication-Protocol (3), Quality-Protocol (4),
Protocol-Field-Compression (7) and Address-and-Control-Field-Compression (8): the stream
has no HDLC, and compressed protocol fields must not appear. If any option is rejected,
send a Configure-Reject listing exactly those options (same identifier); otherwise a
Configure-Ack echoing the options (same identifier).

LCP is **open** when our request was acked and we acked theirs. No PPP authentication
phase follows (the HTTPS login already authenticated the user).

Echo-Request received (after LCP open): reply Echo-Reply with the same identifier, our
magic number, then the request's data after its magic. Terminate-Request: reply
Terminate-Ack (same identifier) and treat the session as ended by the gateway.

Packets for protocols other than LCP, IPCP and IPv4 (e.g. CCP `0x80FD`, IPv6CP `0x8057`)
after LCP is open: send LCP Protocol-Reject (new identifier) whose data is the rejected
protocol number (2 bytes) followed by the rejected packet's information field.

### 6.2 IPCP

Start once LCP is open. Client's Configure-Request: IP-Address (type 3) = 0.0.0.0,
Primary-DNS (129) = 0.0.0.0, Secondary-DNS (131) = 0.0.0.0. The gateway Naks with the real
values; resend with them; the gateway Acks. On Reject, drop those options (e.g. DNS) and
resend. For the gateway's own Configure-Request (normally just its IP-Address), Ack it
unless it contains other options, which are rejected (e.g. IP-Compression-Protocol, type 2).

IPCP is **open** when both requests are acked. Our IP-Address value is the tunnel address;
non-zero DNS values are the DNS servers (fall back to the XML's).

### 6.3 Data and keepalive

After IPCP opens: IPv4 packets from the device are sent as protocol `0x0021`; received
`0x0021` payloads are IPv4 packets for the device. Drop IPv6 (not supported by this mode).

Send an LCP Echo-Request every 20 s. If no Echo-Reply arrives within 90 s, consider the
link dead. A dead or closed link may be re-opened with the same cookie (§5) while the
session is valid; otherwise log in again.

## 7. Timing and retry guidance

- TCP connect timeout 10 s; HTTP read timeout 30 s; PPP negotiation 30 s.
- Emailed/SMS codes typically expire after about 60 s; a push approval waits up to about
  60 s **[confirm by trace]**.
- On failure try the profile's next gateway address; stop immediately on rejected
  credentials or a certificate change.
- After the tunnel drops, rejoin with the same SVPNCOOKIE (§3.5 onwards) before signing in again.
  If that rejoin is refused (tunnel settings answer with a non-200 status or an unexpected
  reply), the gateway has ended the session, for example at its hard session timeout: sign in
  again from §3.2. Observed 2026-09-28 on the user's gateway: after the client's network changed,
  `GET /remote/fortisslvpn_xml` with the old cookie returned HTTP 302 on one occasion and HTTP 403
  on another. So in practice a network change ends the session on that gateway, and a new sign-in
  is needed.
- A change of the client's underlying network (for example Wi-Fi to mobile data) keeps the
  session valid on the gateway; only a new TCP/TLS connection and tunnel are needed. This is
  client behaviour, not wire format.

## 8. Error mapping (client-facing)

| Condition | Error code |
|---|---|
| `ret=0` at step 1 | AUTH_REJECTED |
| HTML login page at step 1 (no `ret`, no `tokeninfo`) | AUTH_REJECTED |
| `ret=6` | UNSUPPORTED_CHALLENGE |
| step 2 without cookie | OTP_REJECTED |
| no code within the timeout | OTP_TIMEOUT |
| TCP/TLS connect failure | GATEWAY_UNREACHABLE |
| pin mismatch | CERT_MISMATCH |
| `HTTP/1` instead of a frame | TUNNEL_REFUSED |
| bad frame, negotiation timeout, unexpected HTTP status | PROTOCOL |
| echo timeout / closed link | LINK_LOST |

## 9. Trace capture (for the [confirm by trace] items)

A debug build logs each HTTP request line, status line, header names, and bodies with
`credential`, `code`, `SVPNCOOKIE`, `id` values replaced by `<redacted>`, plus PPP control
packets (never IPv4 payloads). Store traces in `docs/protocol/traces/` only after review.
