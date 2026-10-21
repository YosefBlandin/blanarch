# Blanarch

A generic Android client for FortiGate SSL-VPN (tunnel mode). People add their own connections:
address, certificate check, password with a code or push, or single sign-on, and optionally
reading emailed codes from their inbox. Nothing company-specific ships in the app.

Blanarch is an independent project, not affiliated with or endorsed by Fortinet. FortiGate and
FortiClient are trademarks of Fortinet, Inc.

## Layout

```
blanarch/          the app: Flutter UI + Kotlin engine (layout and commands in blanarch/README.md)
server/            the team server: Fastify, zod and Kysely on Postgres, with plain SQL migrations
packages/contract/ zod schemas shared by the server and its clients
compose.yaml       local Postgres for the server
docs/protocol/     the wire specs the engine is built from, and PROVENANCE.md (clean-room record)
docs/architecture/ "Inside Blanarch", an illustrated handbook of how the app works
docs/specs/        design specs for larger changes
reports/           research reports (e.g. FortiClient VPN complaints)
research_notes/    the notes behind those reports
```

Server setup (Node 24 and Docker): `npm ci`, copy `.env.example` to `.env` and `server/.env.example` to
`server/.env`, then `docker compose up -d` and `npm -w server run migrate`. Commands are listed in `CLAUDE.md`.

## Clean room

The protocol engine in `blanarch/android/app/src/main/kotlin/com/blanarch/app/sslvpn/` was written
from `docs/protocol/fortigate-sslvpn.md` only, never from the code of openfortivpn, OpenConnect or
FortiClient. Every source used for the specs is logged in `docs/protocol/PROVENANCE.md`.
