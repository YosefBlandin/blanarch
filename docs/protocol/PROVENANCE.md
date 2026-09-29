# Provenance of the VPN protocol engine

This records how the FortiGate SSL-VPN engine (`com.blanarch.app.sslvpn`) was produced,
so its independence from GPL-licensed clients can be shown. It is a factual log, not legal advice.

## Timeline

| Date | Step |
|---|---|
| 2026-09-24 | The first prototype engine (packages `forti` and `ppp`) was written while reading the source of openfortivpn (GPLv3). |
| 2026-09-24 | Decision: replace that engine with a clean-room implementation, so the code can be licensed freely (App Store distribution needs a non-GPL license). |
| 2026-09-24 | Spec writer (Claude, the session that had read openfortivpn) wrote `fortigate-sslvpn.md`. It describes wire behaviour only: endpoints, parameters, byte layouts, and PPP options from public RFCs. It contains no code from any existing client. Items to confirm against a real trace are marked. |
| 2026-09-24 | The old engine and its tests were deleted from the working tree before implementation began. The scratch copy of openfortivpn and the old drafts were deleted too. |
| 2026-09-24 | Implementer (a separate agent started fresh, with no conversation history) wrote `sslvpn/` from the spec only. Its rules: no access to openfortivpn, openconnect or FortiClient code, no git history, no scratch folders, and no web lookups about the protocol. The implementer's own report on following these rules is summarized below. |
| 2026-09-27 | Wrong-password reply observed from the app's own traffic against the user's gateway (status, content type and body shape only; no values kept). Spec §3.1, §3.2 and §8 updated first, then `LoginProtocol.classifyStep1` and a test. No other client's code was consulted. |
| 2026-09-27 | Instrumentation only, no wire change: `SslVpnLink` counts IPv4 bytes each way, `PppNegotiator` records the round trip of its existing keepalive echo, and `SslVpnGateway` reads the TLS version and cipher from the socket session. Written from the spec's existing behaviour; no other client's code was consulted. |
| 2026-09-28 | Spec §7 gained the rejoin rule (a refused rejoin means the session ended; sign in again) and the note that network changes keep the session. The orchestrator change is outside `sslvpn/`; no other client's code was consulted. |
| 2026-09-28 | Observed from the app's own sessions on the user's gateway (status codes only): expired session → tunnel settings 302 or 403; sign-in with a stale cookie → 302. Spec §3.2 and §7 updated first, then `SslVpnGateway.login` clears the old cookie. |
| 2026-09-28 | New `fortigate-ipsec.md` (draft). §2, the IKEv2 reachability probe, is written from RFC 7296 §1.2, §2.10 and §3 only. `fortigate-sslvpn.md` §3.7 gained the "can't serve" signals. Then `ipsec/IkeProbe*` and the prober changes were written from these sections. No strongSwan, libreswan, openfortivpn, OpenConnect or FortiClient code was consulted. |
| 2026-09-28 | Observed with curl against the user's gateway (status line and Location only): `/remote/login` → 303 → `/remote/login?lang=en` → 200. Spec §3.7 now says to follow same-gateway redirects; `SslVpnProber` follows up to two. |
| 2026-09-29 | Git history restarted with one commit of the current tree. The old history, which contains the openfortivpn-derived prototype (packages `forti` and `ppp`), is kept offline as a git bundle, never merged back. Before the restart, git copy detection (`git diff --find-copies-harder -C20%`) compared the new tree with the tree just before the clean-room commit and with the first commit: no current file is 20% or more similar to the prototype's `forti/` or `ppp/` files or to the first commit's `Gateway.kt` and `Ppp.kt`. Files that did carry over are the app's own non-protocol code (mail, OTP, sockets, TUN, routes, state, bridge). The app was renamed at the same time (package `com.blanarch.app`, folder `blanarch/`); no protocol code changed. |

## Inputs the implementer was allowed

- `docs/protocol/fortigate-sslvpn.md`
- RFC 1661, RFC 1332, RFC 1877
- The app's own integration interfaces and utilities: `vpn/Ports.kt`, `state/`, `net/`, `security/`, `config/`, `vpn/ConnectionOrchestrator.kt`, `vpn/VpnTunnelService.kt`. None of these contain protocol logic from openfortivpn.

## Implementer's report

Delivered 2026-09-24: 9 source files in `sslvpn/` and 56 tests in `test/.../sslvpn/`.

- **Sources used:** only the spec, the public RFCs, and general Kotlin/Android knowledge.
- **Rules followed:** no web search or fetch, no git history, nothing read from scratch folders.
- **Files opened outside the allowed list:** `vpn/AndroidTun.kt` and `vpn/Routes.kt` (function signatures only), `res/raw/vpn_config.json`, `app/build.gradle.kts`, and build reports. None of these contain protocol code from other clients.

Spec ambiguities the implementer resolved:
- Non-200 from `fortisslvpn_xml` → TUNNEL_REFUSED
- Push read timeout: 90 s
- Unknown LCP/IPCP codes → Code-Reject
- IPv6 dropped silently

These are to be confirmed or adjusted after tracing.

## Later confirmation

Items marked **[confirm by trace]** in the spec are checked against redacted traces of the
app's own sessions with the user's gateway. Traces are stored in `traces/` after review.
