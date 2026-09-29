# Blanarch

A generic Android client for FortiGate SSL-VPN (tunnel mode). People add their own connections:
address, certificate check, password with a code or push, or single sign-on, and optionally
reading emailed codes from their inbox. Nothing company-specific ships in the app.

Blanarch is an independent project, not affiliated with or endorsed by Fortinet. FortiGate and
FortiClient are trademarks of Fortinet, Inc.

## Layout

```
blanarch/          the app: Flutter UI + Kotlin engine (layout and commands in blanarch/README.md)
docs/protocol/     the wire specs the engine is built from, and PROVENANCE.md (clean-room record)
docs/architecture/ "Inside Blanarch", an illustrated handbook of how the app works
reports/           research reports (e.g. FortiClient VPN complaints)
research_notes/    the notes behind those reports
```

## Clean room

The protocol engine in `blanarch/android/app/src/main/kotlin/com/blanarch/app/sslvpn/` was written
from `docs/protocol/fortigate-sslvpn.md` only, never from the code of openfortivpn, OpenConnect or
FortiClient. Every source used for the specs is logged in `docs/protocol/PROVENANCE.md`.
