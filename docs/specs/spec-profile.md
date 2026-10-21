---
project: blanarch
spec_home: .
ticket_source: none
ticket_prefixes: none
repos: app=../..
task_prefix.app: APP
base_branch.app: qa
verify.app: (cd blanarch && flutter analyze); (cd blanarch && flutter test); (cd blanarch/android && ./gradlew ktlintCheck testDebugUnitTest); npm ci && npm run format:check && npm run lint && npm run typecheck && npm test
test.app.ts: npx vitest run {file}
test.app.hooks: node --test {file}
preflight: flutter --version => Flutter; dart --version => Dart; java -version => version; adb version => Android Debug Bridge; node --version => v24; docker info => Server Version
forbidden_strings_file: ../../private/company-strings.txt
environment_file: ~/agent-kit/local/environment.md
---
# Blanarch spec profile

Specs for Blanarch changes live here, one folder per change: `docs/specs/<slug>/`. There is no ticket tracker, so a
short request becomes the slug. This folder is committed, so everything in it must be public-ready.

## Rules to honour (pointers, never copies)
- `CLAUDE.md` at the repo root: the clean-room rule, the architecture rules (MVVM, Pigeon, pure Kotlin protocol logic),
  the conventions (no dashes in UI copy, every string in English and Spanish), secrets, and the features to keep working.
- Clean room: a change to the protocol engine plans a task that edits `docs/protocol/` and logs it in
  `docs/protocol/PROVENANCE.md` *before* any code task.
- Generated files are regenerated, never hand-edited: run pigeon after changing the bridge contract, and gen-l10n after
  changing the `.arb` files.
- Public-ready: tests and specs use `example.com` names and documentation IP ranges. The pre-commit hook and
  `spec-lint` both check the strings in `private/company-strings.txt`.

## Human-only actions
- Installing on the owner's phone (adb), and any check against a real gateway (connect, network loss, session expiry).
- Release builds and signing (the keystore and its password).
- Installing or starting Docker (Colima), and setting branch protection on GitHub.
- Committing and pushing, unless the user allows it for the change.

## Notes
- Verify commands run from the repo root as written above. Goldens only change for an intended UI change; look at the
  images before accepting.
- `origin` is a public GitHub repo with `main`, `qa` and `staging`. Feature PRs target `qa`; `drift` compares against `origin/qa`, so fetch it first.
- Worktree and branch convention: `<repo>/.claude/worktrees/<slug>` on branch `feat/<slug>`, created from `origin/qa` with `--no-track` (environment file, git section).
- The server workspace (`server/`, `packages/`) runs from the repo root: `npm ci` first, then `docker compose up -d` for local Postgres. Docker on the owner's Mac is Colima: `npm test` needs `DOCKER_HOST` and `TESTCONTAINERS_DOCKER_SOCKET_OVERRIDE` set as in `CLAUDE.md` Gotchas.
- No PR template exists; PR bodies list tasks, test ids and results, deviations and HUMAN steps.
