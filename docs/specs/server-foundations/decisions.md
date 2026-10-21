---
spec: server-foundations
ticket: none
tier: M
status: executing
---
# Team server foundations (roadmap phase 0): decisions

<!-- The single home for every decision. Other files cite the id; a brief may copy the one-line text verbatim. Row: id, decision, door (1-way or 2-way), source and date (intake, user, stakeholder:role or design), status (proposed, accepted, superseded-by plus the new id, or RETIRED → the new id). -->
<!-- A late answer after lock never edits a row: add a new decision that supersedes the old one, then run spec-lint.mjs with --impact on the old id to find the tasks and tests that cite it. -->
<!-- Example rows:
| D-1 | Record page views as a new event type in the existing event log. | 2-way | stakeholder:security, 2026-10-18 | accepted |
| D-2 | Serve the page-view route from a new small service, not the main one. | 2-way | design, 2026-10-18 | accepted |
-->

| D | Decision | Door | Source, date | Status |
|---|---|---|---|---|
| D-1 | Tier M: a new server codebase, wire contract package and CI that every later phase builds on, about 8 tasks in one repo and one PR, revertible. | 2-way | intake, 2026-10-18 | accepted |
| D-2 | Clients: only the current Android app; Phase 0 leaves the app unchanged and the server has no callers yet. | 2-way | intake, 2026-10-18 | accepted |
| D-3 | Environment: local only. Tests, builds and Docker containers run on the owner's Mac through OrbStack (installed 2026-10-18); nothing is deployed and no shared environment is used. | 2-way | intake, 2026-10-18 | superseded-by D-13 |
| D-4 | Roles: the agent writes code, commits per logical step, pushes a feature branch and opens a draft PR into qa. The owner reviews, merges and promotes. | 2-way | intake, 2026-10-18 | accepted |
| D-5 | Stakeholders: the owner only, no fixed date. | 2-way | intake, 2026-10-18 | accepted |
| D-6 | Layout: npm workspaces in this repo, with server, admin and a shared contract package next to the app folder. | 2-way | user, 2026-10-18 | accepted |
| D-7 | Local infrastructure: Docker Compose runs Postgres 17 and MinIO; integration tests get a fresh database through Testcontainers. | 2-way | user, 2026-10-18 | superseded-by D-10 |
| D-8 | Database access: migrations are plain SQL files; queries use Kysely for types. | 2-way | user, 2026-10-18 | accepted |
| D-9 | Process: the approved roadmap splits the server into phases 0 to 7, and each phase gets its own spec. This spec covers phase 0 only. | 2-way | user, 2026-10-18 | accepted |
| D-10 | Local infrastructure: Docker Compose runs Postgres 17; integration tests get a fresh database through Testcontainers. No object store until the diagnostics phase chooses one, since MinIO is archived. | 2-way | user, 2026-10-18 | accepted |
| D-11 | CI runs the app job (Flutter analyze, Flutter test with golden screenshots, Kotlin lint and unit tests) on a macOS runner, and the server job on Linux. | 2-way | user, 2026-10-18 | accepted |
| D-12 | The forbidden word check becomes a tracked hook that every clone and worktree uses, reads the list from the main checkout, and blocks loudly when the list is missing. CI never receives the list. | 2-way | user, 2026-10-18 | accepted |
| D-13 | Environment: local only. Tests, builds and containers run on the owner's Mac with Docker installed directly by the owner, not OrbStack; nothing is deployed and no shared environment is used. | 2-way | user, 2026-10-18 | accepted |
| D-14 | Runtime: Node 24 LTS, pinned in .nvmrc and engines. The server runs TypeScript through Node's native type stripping, with tsc for type checks only; if Node cannot load the workspace contract package that way, use tsx instead. Move to Node 26 in a later phase. | 2-way | design, accepted by user 2026-10-18 | accepted |
| D-15 | Migrations: node-pg-migrate with plain .sql files, run as a separate command, never on server start. | 2-way | design, accepted by user 2026-10-18 | accepted |
| D-16 | Tooling: npm workspaces with a committed lockfile, ESLint flat config with typescript-eslint type-checked rules, Prettier, vitest. TypeScript is pinned to the newest major that typescript-eslint supports. | 2-way | design, accepted by user 2026-10-18 | accepted |
| D-17 | Server shape: a buildApp factory that takes config and database, so tests use inject without a port; Fastify with the zod type provider; config parsed by zod at start; pino logs with header redaction. | 2-way | design, accepted by user 2026-10-18 | accepted |
| D-18 | Health check: GET /healthz, unversioned; 200 when the database answers within 1 s, else 503; the server stays up when the database is down. | 2-way | design, accepted by user 2026-10-18 | accepted |
| D-19 | The tracked hook finds the list through git's common directory and is enabled by the root prepare script setting core.hooksPath; SKIP_FORBIDDEN_CHECK=1 skips it with a warning. | 2-way | design, 2026-10-18 | superseded-by D-22 |
| D-20 | CI: commit the Gradle wrapper; the macOS app job writes local.properties and caps the Gradle heap; actions pinned by major (first-party) or commit SHA (third-party); read-only permissions. | 2-way | design, accepted by user 2026-10-18 | accepted |
| D-21 | This PR also commits docs/specs: the spec profile and this spec folder. Both are public-ready and checked by spec-lint. | 2-way | design, accepted by user 2026-10-18 | accepted |
| D-22 | The tracked hooks (.githooks/pre-commit and .githooks/commit-msg, committed executable) are copied by the root prepare script into the hooks folder of git's common directory, so every worktree runs them on any branch and after a revert; core.hooksPath is never set. They find the list through git's common directory, scan staged added lines and the commit message, and block when the list is missing; SKIP_FORBIDDEN_CHECK=1 is honoured only when the list is missing or empty. | 2-way | design, accepted by user 2026-10-18 | accepted |
| D-23 | If the first CI run shows golden screenshot differences that the owner judges rendering-only, the CI app job excludes the golden tests, which stay pixel-exact on the owner's Mac. | 2-way | design, 2026-10-18 | superseded-by D-24 |
| D-24 | If the first CI run shows golden screenshot differences that the owner judges rendering-only, the CI app job skips the golden test file by path (no app test changes); the goldens stay pixel-exact on the owner's Mac. | 2-way | design, accepted by user 2026-10-18 | accepted |
| D-25 | The executor installs the new hooks before its first commit, and before every push scans the whole branch diff against qa, every commit message, and the PR title and body against the private list and the private values in CLAUDE.local.md, reporting counts only. | 2-way | design, accepted by user 2026-10-18 | accepted |
| D-26 | DP4: the executor keeps the D-4 permissions unchanged: commit per task on feat/server-foundations, push that branch, open a draft PR into qa. Nothing else is granted. | 2-way | user, 2026-10-18 | accepted |

## Options
<!-- Only for 1-way or stakeholder decisions: one block each, headed with the decision id and "options". Mark the chosen option with ✓ and always include "do nothing". Confirm by names a test (in words at design, by id once handoff writes it) or a concrete check. Two-way design decisions need the row only. Example block:
### D-1 options
**Options**
- A. Do nothing: every call keeps writing its own event; the log stays noisy.
- B. New event type in the existing event log: current readers keep working; one filter value is added. ✓
- C. Separate page-view log: a clean shape, but every reader and the clean-up job change.

**Why**: B is the only option that keeps every current reader and the clean-up job unchanged.
**Cost / accepted risk**: events written before the release have no page type until they expire.
**Confirm by**: a staging check that one page open writes exactly one new event.
-->
