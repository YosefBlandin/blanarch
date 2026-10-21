# forti-vpn

Tools for FortiGate SSL-VPN with one-time codes:
- `blanarch/`: **Blanarch**, a generic Android client for FortiGate SSL-VPN (Flutter UI + Kotlin engine).
  Users add their own connections; nothing company-specific ships in the app. Layout and commands: `blanarch/README.md`.
- `server/`: the team server (Fastify + zod + Kysely on Postgres 17), roadmap phases 0 to 7. Plain SQL migrations in
  `server/migrations/`; Kysely types in `server/src/db/types.ts` are generated, never hand-edited.
- `packages/contract/`: zod schemas shared by the server and, later, the admin app (`@blanarch/contract`).
- `docs/protocol/`: the wire spec the engine is built from, and `PROVENANCE.md` (clean-room record).
- `docs/specs/`: spec folders and `spec-profile.md` for the `/spec` workflow.
- `private/` (git-ignored, never commit): the macOS script `forti_vpn.py` + `vpn.conf` (wraps openfortivpn,
  passwords in the macOS Keychain), its README, and business notes. Company hosts and usernames live only there.

## Commands (run from `blanarch/`)
- Dart: `flutter analyze` then `flutter test` (view-model tests + golden screenshots)
- Kotlin: `(cd android && ./gradlew ktlintFormat ktlintCheck testDebugUnitTest)`
- After editing `pigeons/vpn_api.dart`: `dart run pigeon --input pigeons/vpn_api.dart`
- After editing `lib/l10n/*.arb`: `flutter gen-l10n`
- Build + install: `flutter build apk --release --target-platform android-arm64 && adb install -r build/app/outputs/flutter-apk/app-release.apk`
- zsh does not word-split `$VAR` holding a command; use `export ANDROID_SERIAL=<serial>` then plain `adb`. The owner's device serial is in `CLAUDE.local.md`.

## Server commands (run from the repo root)
- `npm ci` first: installs every workspace and the forbidden-word git hooks. Node 24 (`.nvmrc`).
- Local Postgres: copy `.env.example` to `.env` and `server/.env.example` to `server/.env`, then `docker compose up -d`.
- `npm -w server run migrate` applies pending migrations; `npm -w server run migrate:create -- <name>` adds a SQL file;
  `npm -w server run db:types` regenerates the Kysely types from the migrated local database.
- `npm -w server run dev` runs the server with reload and `server/.env`; `GET /healthz` is the health check.
- `npm run lint` · `npm run typecheck` · `npm test` · `npm run format:check` each run across every workspace.
  Tests start a throwaway Postgres with Testcontainers, so Docker must be running.

## Clean-room rule
- `sslvpn/` was implemented from `docs/protocol/fortigate-sslvpn.md` only. Never paste or consult openfortivpn,
  openconnect or FortiClient code when changing it; change the spec first, then the code. Log it in `PROVENANCE.md`.
- Git history restarted on 2026-09-29 without the GPL-derived prototype engine. The old history is kept offline as a git
  bundle (path in `CLAUDE.local.md`) as clean-room evidence. Never merge or fetch it back.
- The repo is public-ready: no company hosts, usernames or email domains in tracked files. Tests use
  `example.com` names and documentation IPs (192.0.2.0/24, 198.51.100.0/24, 203.0.113.0/24).

## Architecture rules
- Flutter follows the official MVVM guide: views draw only; view-models hold state and expose `Command`s
  (`lib/utils/command.dart`); repositories return `Result`; dependencies are wired only in
  `lib/config/dependencies.dart`. No globals or statics for state.
- Kotlin: keep protocol logic pure and I/O-free (`sslvpn/` `LoginProtocol`, `TunnelXml`, `FrameCodec`,
  `PppNegotiator`; `mail/Mime`; `vpn/Routes`; `profile/Address`) and unit-test it. Socket work goes through `cancellableIo`. Only `ConnectionOrchestrator` knows the
  connection sequence. Report failures as `VpnException(ErrorCode)`, never by matching text.
- Dart and Kotlin talk only through Pigeon. Never hand-edit generated files: `*.g.dart`, `*.g.kt`, `lib/l10n/generated/`.
- Connections are user profiles (`profile/`, stored by the engine). `res/raw/vpn_config.json` holds only generic engine
  defaults. Certificates are never trusted silently: the user confirms a fingerprint, then it is pinned per host.

## Conventions
- UI copy: no em or en dashes (the user finds them AI-looking). Use short sentences, commas or a middle dot.
- Every user-facing string goes in both `app_en.arb` and `app_es.arb`. Notification text goes in `res/values*/strings.xml`.
- Brand: beige/bronze palette in `lib/ui/core/theme/theme.dart`. Light first, with Auto/Light/Dark. Instrument Serif + Inter.
- Goldens in `test/goldens/` guard the look. Use `--update-goldens` only for an intended UI change, and look at the images.
- Commit per logical step, with the attribution trailer.

## Secrets and signing
- Never print or log passwords. They are in the phone's Keystore, and on the Mac in the Keychain
  (items named in `private/vpn.conf`). Engine log messages must not contain secrets.
- Release key: `~/.android-keys/blandfortivpn.jks`, read through the git-ignored `android/key.properties`
  (password also in Keychain `blandfortivpn-keystore`). Losing it means reinstalling the app, which wipes its saved data.

## Features to keep working
- Quick Settings tile (`vpn/VpnTileService.kt`), notification Reconnect/Disconnect, always-on starts
  (`VpnTunnelService` with no action), setup links `blanarch://add?host=…&port=…&pin=…` and QR codes
  (`domain/models/setup_link.dart`, never includes passwords), app lock (auth-bound Keystore key, 60 s window).
- Drops: `vpn/AndroidNetworkWatch.kt` follows the real network through a non-VPN `NetworkRequest` (never the
  default-network callback: a VPN app's default network is its own VPN once up). It drives `WAITING_NETWORK`
  and immediate rejoin on network change; a refused rejoin signs in again. Alerts come from the pure `vpn/DropAlerts.kt`; the status notification takes a code inline (RemoteInput).
- QR scanning uses Play services ML Kit (`useUnbundled` in gradle.properties); F-Droid would need a different scanner.

## Gotchas
- `NoSuchFileException … transforms/…` from Gradle means a corrupt cache entry: delete that folder, run `./gradlew --stop`, rebuild.
- The gateway's emailed code expires in about a minute; the IMAP check runs every 2 s.
- Testcontainers with Colima needs `export DOCKER_HOST=unix://$HOME/.colima/default/docker.sock` and
  `export TESTCONTAINERS_DOCKER_SOCKET_OVERRIDE=/var/run/docker.sock`; without them `npm test` fails with
  "Could not find a working container runtime strategy".
- If `docker compose` is an unknown command, Homebrew's plugin is not linked: use `docker-compose`, or add
  `"cliPluginsExtraDirs": ["/opt/homebrew/lib/docker/cli-plugins"]` to `~/.docker/config.json`.
- Postgres keeps the password from the volume's first start. After changing `POSTGRES_PASSWORD`, run
  `docker compose down -v` (this deletes the local data). If port 5432 is taken, set `POSTGRES_PORT` in `.env` and the
  same port in `server/.env`.
- The hooks in `.githooks/` are copied into the shared `.git/hooks/` by `npm ci` (or `node scripts/install-hooks.mjs`),
  so every worktree and branch runs them, and they stay after a revert. They read the main checkout's
  `private/company-strings.txt` and block when it is missing; `SKIP_FORBIDDEN_CHECK=1` only works without a list.
  Never set `core.hooksPath`.
- End-to-end SSL-VPN connections are confirmed on a real gateway (connect, network loss, session expiry).
  IPsec has never connected; don't claim it works until the Activity log shows "Connected".
