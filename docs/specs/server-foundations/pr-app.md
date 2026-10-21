---
spec: server-foundations
ticket: none
tier: M
status: executing
---
# Team server foundations (roadmap phase 0): brief for app

- Goal: add the npm workspace with a Fastify server skeleton, Postgres through Compose and Testcontainers, SQL migrations, tracked forbidden-word hooks and a CI workflow, without changing the app.
- Implements: AC-1, AC-2, AC-3, AC-4, AC-5, AC-6, AC-7, AC-8, AC-9, AC-10, AC-11; D-4, D-26, D-6, D-8, D-10, D-11, D-12, D-13, D-14, D-15, D-16, D-17, D-18, D-20, D-21, D-22, D-24, D-25
- Spec folder: /Users/v/projects/forti-vpn/docs/specs/server-foundations
- Refs: app at the sha in intent.md refs; before the first task run `node ~/.claude/skills/spec/scripts/drift.mjs /Users/v/projects/forti-vpn/docs/specs/server-foundations`
- Worktree: /Users/v/projects/forti-vpn/.claude/worktrees/server-foundations
- Branch: feat/server-foundations · Base: origin/qa
- Brief version: the locked-vN named in the handoff prompt (the front matter says executing once DP4 passes); record it as pr-app.md@locked-vN in progress-app.json

## Read first
1. This file, all of it.
2. intent.md: Acceptance criteria, No-gos, Constraints.
3. architecture.md: Components, Contracts, States and exits, Risks.
4. CLAUDE.md at the repo root, in the worktree.
5. ~/agent-kit/local/environment.md: "Git and worktrees", "Privacy rule".

## HUMAN needs
- <HUMAN: start Docker on the owner's Mac (`colima start`, then `docker context use colima`) so `docker info` shows a Server Version; preflight fails on this today> · Blocks: APP-5 (APP-0 to APP-4 need no Docker)
- <HUMAN: after the draft PR is open, look at the CI run; if golden screenshots fail, open the uploaded failure images and say whether the differences are rendering-only (D-24)> · Blocks: G-merge

## Global constraints
- D-26: DP4: the executor keeps the D-4 permissions unchanged: commit per task on feat/server-foundations, push that branch, open a draft PR into qa. Nothing else is granted.
- D-4: Roles: the agent writes code, commits per logical step, pushes a feature branch and opens a draft PR into qa. The owner reviews, merges and promotes.
- D-6: Layout: npm workspaces in this repo, with server, admin and a shared contract package next to the app folder.
- D-8: Database access: migrations are plain SQL files; queries use Kysely for types.
- D-10: Local infrastructure: Docker Compose runs Postgres 17; integration tests get a fresh database through Testcontainers. No object store until the diagnostics phase chooses one, since MinIO is archived.
- D-11: CI runs the app job (Flutter analyze, Flutter test with golden screenshots, Kotlin lint and unit tests) on a macOS runner, and the server job on Linux.
- D-12: The forbidden word check becomes a tracked hook that every clone and worktree uses, reads the list from the main checkout, and blocks loudly when the list is missing. CI never receives the list.
- D-13: Environment: local only. Tests, builds and containers run on the owner's Mac with Docker installed directly by the owner, not OrbStack; nothing is deployed and no shared environment is used.
- D-14: Runtime: Node 24 LTS, pinned in .nvmrc and engines. The server runs TypeScript through Node's native type stripping, with tsc for type checks only; if Node cannot load the workspace contract package that way, use tsx instead. Move to Node 26 in a later phase.
- D-15: Migrations: node-pg-migrate with plain .sql files, run as a separate command, never on server start.
- D-16: Tooling: npm workspaces with a committed lockfile, ESLint flat config with typescript-eslint type-checked rules, Prettier, vitest. TypeScript is pinned to the newest major that typescript-eslint supports.
- D-17: Server shape: a buildApp factory that takes config and database, so tests use inject without a port; Fastify with the zod type provider; config parsed by zod at start; pino logs with header redaction.
- D-18: Health check: GET /healthz, unversioned; 200 when the database answers within 1 s, else 503; the server stays up when the database is down.
- D-20: CI: commit the Gradle wrapper; the macOS app job writes local.properties and caps the Gradle heap; actions pinned by major (first-party) or commit SHA (third-party); read-only permissions.
- D-21: This PR also commits docs/specs: the spec profile and this spec folder. Both are public-ready and checked by spec-lint.
- D-22: The tracked hooks (.githooks/pre-commit and .githooks/commit-msg, committed executable) are copied by the root prepare script into the hooks folder of git's common directory, so every worktree runs them on any branch and after a revert; core.hooksPath is never set. They find the list through git's common directory, scan staged added lines and the commit message, and block when the list is missing; SKIP_FORBIDDEN_CHECK=1 is honoured only when the list is missing or empty.
- D-24: If the first CI run shows golden screenshot differences that the owner judges rendering-only, the CI app job skips the golden test file by path (no app test changes); the goldens stay pixel-exact on the owner's Mac.
- D-25: The executor installs the new hooks before its first commit, and before every push scans the whole branch diff against qa, every commit message, and the PR title and body against the private list and the private values in CLAUDE.local.md, reporting counts only.
- Versions (caret ranges unless noted): fastify ^5.12, fastify-type-provider-zod ^7, zod ^4.6, kysely ^0.29, kysely-codegen ^0.20, pg ^8.23, node-pg-migrate ^9, testcontainers and @testcontainers/postgresql ^12.2, vitest ^5, eslint ^10, typescript-eslint ^8.71, eslint-config-prettier latest, prettier ^3.9, @types/node ^24, @types/pg latest. Docker image `postgres:17.11` everywhere. Flutter 3.47.5 stable, Temurin JDK 17.
- CI actions: actions/checkout@v7, actions/setup-node@v7, actions/setup-java@v6, actions/upload-artifact at its current major, gradle/actions/wrapper-validation at its current major, subosito/flutter-action pinned to the commit SHA of tag v2.23.0 (resolve it read-only with `gh api repos/subosito/flutter-action/git/ref/tags/v2.23.0`).
- The wrapper files to commit are copied from the owner's checkout: /Users/v/projects/forti-vpn/blanarch/android/gradlew, gradlew.bat and gradle/wrapper/gradle-wrapper.jar (Gradle 9.3.1).
- Public-ready: example.com names and documentation IPs only (CLAUDE.md, "Clean-room rule").
- Dependencies: each task adds the packages from Versions that its own code needs to that workspace's package.json; package-lock.json changes in any task that adds a dependency.
- Root scripts: `lint` = `eslint .`; `typecheck` = `npm run typecheck --workspaces --if-present` (each workspace runs `tsc --noEmit -p .`); `format` = `prettier --write .`; `format:check` = `prettier --check .`; `test` = `vitest run && node --test scripts/`.
- GitHub: `gh` and the origin SSH alias use the owner's personal account. Check `gh auth status` before APP-11; a failure is a stop.
- Logs, errors and reports carry internal ids and counts only: no names, emails, IPs or file keys.

## ALWAYS / ASK FIRST / NEVER
**ALWAYS**
- Run every npm and git command from the worktree root. Use Node from `.nvmrc` (24).
- Before any push: run the D-25 scan (APP-11 steps) and record counts only.
- Write the test first and see it fail. One task, one commit.
- Put the test id in the test title.
- Record each verify command and its result in progress-app.json before the next task.

**ASK FIRST**
- Adding or upgrading a dependency that no decision or architecture.md Contracts names.
- Any command with side effects outside the worktree and the spec folder (the hook installer writing to the shared git hooks folder is allowed; it is the point of APP-1).

**NEVER**
- Print, log or commit a string from the private list or CLAUDE.local.md. Never set core.hooksPath.
- Change anything under blanarch/ except blanarch/android/.gitignore and the three wrapper files.
- Merge, mark a PR ready, promote, push a protected branch, write to cloud resources, read production or enter a password.
- Edit a decision. Record a deviation in progress-app.json and stop.

## Tasks

### APP-0 · Record the baselines
- Implements: none · After: none · Judgment: normal
- Files: none (no change)
- Tests first: none
- Do:
  - Create the worktree: `git -C /Users/v/projects/forti-vpn fetch origin qa`, then `git -C /Users/v/projects/forti-vpn worktree add --no-track -b feat/server-foundations .claude/worktrees/server-foundations origin/qa`.
  - Copy the ignored local files the app build needs from the owner's checkout into the worktree (they stay ignored here): blanarch/android/gradlew, blanarch/android/gradle/wrapper/gradle-wrapper.jar and blanarch/android/local.properties. Run `flutter pub get` in blanarch/.
  - Run every verify command once, before any change.
- Verify: `(cd blanarch && flutter analyze); (cd blanarch && flutter test); (cd blanarch/android && ./gradlew ktlintCheck testDebugUnitTest)` from the worktree root → record in progress-app.json `baseline`: `tests` = flutter test and Gradle unit test results, `lint` = flutter analyze and ktlintCheck results, `typecheck` = "absent (no workspace yet)"
- Done when: the baseline in progress-app.json is filled and the worktree is clean

### APP-1 · Tracked forbidden-word hooks, installed first
- Implements: AC-10, D-12, D-22, D-25 · After: APP-0 · Judgment: high
- Files: app:.githooks/forbidden-scan.sh (new), app:.githooks/pre-commit (new), app:.githooks/commit-msg (new), app:scripts/install-hooks.mjs (new), scripts/hooks.test.mjs (new)
- Tests first: T-HOOK-1, T-HOOK-2, T-HOOK-3, T-HOOK-4, T-HOOK-5
- Do:
  - Tests build a throwaway repo in a temp folder with its own private/company-strings.txt holding a made-up token, run the installer there, and drive commits.
  - Port today's scan logic into forbidden-scan.sh with the changes in architecture.md Contracts, Hook behaviour; list path from `git rev-parse --path-format=absolute --git-common-dir`.
  - Installer copies the three files into the common hooks folder with mode 755, refuses when core.hooksPath is set, does nothing outside a git checkout.
  - Commit the hook files with mode 100755 (`git update-index --chmod=+x`), then run `node scripts/install-hooks.mjs` in the worktree before committing anything.
- Verify: `node --test scripts/hooks.test.mjs` → all pass; `git ls-files -s .githooks` shows 100755 for all three
- Done when: verify is green, evidence is in progress-app.json, and the reviewer has no blocker

### APP-2 · Root workspace and tooling
- Implements: AC-1, AC-8, D-6, D-14, D-16 · After: APP-1 · Judgment: normal
- Files: app:package.json (new), app:package-lock.json (new), app:.nvmrc (new), app:tsconfig.base.json (new), app:eslint.config.js (new), app:vitest.config.ts (new), app:.prettierrc.json (new), app:.prettierignore (new), app:.gitignore
- Tests first: none (T-WS-1 and T-WS-2 run in APP-4, once a workspace exists)
- Do:
  - Root package.json per architecture.md Components, Root workspace. `prepare` runs scripts/install-hooks.mjs. `test` runs `vitest run` (root config with projects `packages/*` and `server`) then `node --test scripts/`.
  - Pick TypeScript from typescript-eslint's declared peer range (RK-3); record the version in progress.
  - .gitignore adds node_modules/, dist/, coverage/, *.tsbuildinfo and .claude/worktrees/.
  - Before committing the lockfile, run the forbidden scan on it and record the hit count only (RK-5).
- Verify: `npm install && npm run format:check && npm run lint && npm run typecheck` → all exit 0 with no workspaces present yet
- Done when: verify is green and evidence is in progress-app.json

### APP-3 · Contract package with the health schema
- Implements: AC-5, D-6 · After: APP-2 · Judgment: normal
- Files: app:packages/contract/package.json (new), app:packages/contract/src/health.ts#HealthResponse (new), app:packages/contract/src/index.ts (new), packages/contract/src/health.test.ts (new)
- Tests first: T-CON-1
- Do: write the schema from architecture.md Contracts, Health check; export it from index.ts; package.json per Components, Contract package.
- Verify: `npx vitest run packages/contract/src/health.test.ts` → all pass
- Done when: verify is green and evidence is in progress-app.json

### APP-4 · Server config loading
- Implements: AC-4, D-17 · After: APP-3 · Judgment: normal
- Files: app:server/package.json (new), app:server/tsconfig.json (new), app:server/src/config.ts#loadConfig (new), server/src/config.test.ts (new), app:server/.env.example (new)
- Tests first: T-CFG-1, T-CFG-2, T-CFG-3, T-WS-1, T-WS-2
- Do: zod schema for architecture.md Contracts, Settings; failures print `config: <NAME> <reason>` lines and exit 1; values never printed; .env.example with placeholders only. Then run T-WS-1 and T-WS-2 by hand and record them.
- Verify: `npx vitest run server/src/config.test.ts` → all pass; `rm -rf node_modules && npm ci && npm run lint && npm run typecheck` → exit 0 (T-WS-1)
- Done when: verify is green and evidence is in progress-app.json

### APP-5 · Local Postgres, pool and test container
- Implements: AC-3, AC-7, D-10 · After: APP-4 · Judgment: normal
- Files: app:compose.yaml (new), app:.env.example (new), app:server/src/db.ts#createDb (new), app:server/vitest.config.ts (new), app:server/test/global-setup.ts (new), server/src/db.test.ts (new)
- Tests first: T-DB-1, T-DB-2
- Do:
  - compose.yaml and root .env.example per architecture.md Contracts, Local compose settings. Create the ignored `.env` and `server/.env` by copying the two example files.
  - createDb with the pool error listener and connect timeout (Components, Server).
  - Global setup starts one `postgres:17.11` container per run. If it cannot find Colima's socket, find the variables that make it work and record them for APP-10 (RK-6).
  - Run T-MAN-1 by hand and record the result.
- Verify: `npx vitest run server/src/db.test.ts` → all pass; `docker ps -a` shows no leftover test container after the run
- Done when: verify is green and evidence is in progress-app.json

### APP-6 · SQL migrations
- Implements: AC-6, D-8, D-15 · After: APP-5 · Judgment: high
- Files: app:server/migrations/ (new), app:server/src/db/types.ts#Database (new), server/src/migrations.test.ts (new), app:server/package.json, app:server/test/global-setup.ts
- Tests first: T-MIG-1, T-MIG-2, T-MIG-3
- Do:
  - node-pg-migrate with .sql files; first migration enables citext. Scripts `migrate`, `migrate:create`, `db:types` per architecture.md Contracts, Commands, all reading server/.env.
  - Global setup applies migrations before tests.
  - Tests use fixture migration folders in a fresh database each: order and once-only, a failing file rolls back the batch, a concurrent run exits 1 with nothing applied.
  - Generate types.ts from the migrated compose database with `db:types`.
- Verify: `npx vitest run server/src/migrations.test.ts` → all pass
- Done when: verify is green, evidence is in progress-app.json, and the reviewer has no blocker

### APP-7 · App factory and health route
- Implements: AC-5, D-17, D-18 · After: APP-6 · Judgment: normal
- Files: app:server/src/app.ts#buildApp (new), app:server/src/routes/health.ts#healthRoutes (new), server/src/health.test.ts (new)
- Tests first: T-HLT-1, T-HLT-2, T-HLT-3, T-HLT-4
- Do:
  - buildApp per Components, Server; pino redacts `req.headers.authorization` and `req.headers.cookie`.
  - healthRoutes per Contracts, Health check: one per-request 1000 ms timer covering checkout plus `select 1`, releasing the client.
  - T-HLT-2 uses a DATABASE_URL on 192.0.2.1; T-HLT-3 terminates the pooled backends with pg_terminate_backend.
- Verify: `npx vitest run server/src/health.test.ts` → all pass
- Done when: verify is green and evidence is in progress-app.json

### APP-8 · Server entry and shutdown
- Implements: AC-4, D-14, D-17 · After: APP-7 · Judgment: normal
- Files: app:server/src/server.ts#main (new), server/src/server.test.ts (new), app:server/package.json
- Tests first: T-SRV-1, T-SRV-2
- Do:
  - main loads config, builds, listens; shutdown per architecture.md States and exits.
  - Scripts `start` (`node src/server.ts`) and `dev` (`node --watch --env-file-if-exists=.env src/server.ts`).
  - Tests spawn `node server/src/server.ts`, proving type stripping loads the contract (RK-2); if not, use tsx (D-14) and record it.
- Verify: `npx vitest run server/src/server.test.ts` → all pass
- Done when: verify is green and evidence is in progress-app.json

### APP-9 · CI workflow and Gradle wrapper
- Implements: AC-9, D-11, D-20, D-24 · After: APP-8 · Judgment: normal
- Files: app:.github/workflows/ci.yml (new), app:blanarch/android/.gitignore, blanarch/android/gradlew (new), blanarch/android/gradlew.bat (new), blanarch/android/gradle/wrapper/gradle-wrapper.jar (new)
- Tests first: T-CI-1 (manual, runs on the draft PR)
- Do:
  - Workflow per architecture.md Components, CI and Contracts, CI checks; the app job puts `org.gradle.jvmargs=-Xmx3g` in `~/.gradle/gradle.properties` and writes `flutter.sdk=<Flutter root>` to `blanarch/android/local.properties`.
  - Stop ignoring gradlew, gradlew.bat and gradle-wrapper.jar in blanarch/android/.gitignore; commit them, gradlew with mode 100755.
- Verify: `cd blanarch/android && ./gradlew --version` → Gradle 9.3.1; `git ls-files -s blanarch/android/gradlew` → 100755
- Done when: verify is green and evidence is in progress-app.json

### APP-10 · Docs: CLAUDE.md, README
- Implements: AC-11 · After: APP-9 · Judgment: normal
- Files: app:CLAUDE.md, app:README.md
- Tests first: T-DOC-1 (manual)
- Do:
  - CLAUDE.md: add server/ and packages/contract/ to the intro list; a new "Server commands (run from the repo root)" block from architecture.md Contracts, Commands, with `npm ci` first; Gotchas for Colima with Testcontainers (the variables found in APP-5), `docker compose down -v` after a password change, and the shared hooks.
  - README.md Layout: server/, packages/contract/, compose.yaml, and a setup line (`npm ci`, `docker compose up -d`).
- Verify: `npm run format:check` → exit 0; T-DOC-1 checklist recorded
- Done when: verify is green and evidence is in progress-app.json

### APP-11 · Specs, full verify, privacy scan, draft PR
- Implements: AC-2, AC-11, D-4, D-21, D-25 · After: APP-10 · Judgment: normal
- Files: docs/specs/spec-profile.md (new), docs/specs/server-foundations/ (new)
- Tests first: T-APP-1
- Do:
  - Run `node ~/.claude/skills/spec/scripts/spec-lint.mjs /Users/v/projects/forti-vpn/docs/specs/server-foundations` (0 errors), then copy /Users/v/projects/forti-vpn/docs/specs/spec-profile.md and the whole spec folder, progress and review files included, into the worktree's docs/specs/ and commit them.
  - Run the full verify.app; compare the app part with the baseline (T-APP-1).
  - D-25 scan: build a temp pattern file from the private list (comments and blank lines dropped) plus the adb serial and the backup folder path named in CLAUDE.local.md; count matches in `git diff origin/qa...HEAD`, in `git log --format=%B origin/qa..HEAD`, and in the drafted PR title and body. Record counts only; any hit is a stop.
  - `git push -u origin feat/server-foundations`, then `gh pr create --draft --base qa` with the body from "PR body" below.
- Verify: full verify.app → app results equal the baseline, npm checks exit 0; scan counts all 0
- Done when: the draft PR is open, its body is checked, and evidence is in progress-app.json

## Tests
| Test | Traces | Task | Level | Gate | Check |
|---|---|---|---|---|---|
| T-HOOK-1 | AC-10, D-22 | APP-1 | int | G-merge | A staged line with the made-up token is blocked; the output shows a count, never the token. |
| T-HOOK-2 | AC-10, D-22 | APP-1 | int | G-merge | A commit message with the token is blocked by commit-msg. |
| T-HOOK-3 | AC-10, D-22 | APP-1 | int | G-merge | A missing list blocks with the expected path; with SKIP_FORBIDDEN_CHECK=1 it proceeds with a warning. |
| T-HOOK-4 | AC-10, D-22 | APP-1 | int | G-merge | With the list present, SKIP_FORBIDDEN_CHECK=1 still blocks a hit. |
| T-HOOK-5 | AC-10, D-22 | APP-1 | int | G-merge | In a linked worktree on a branch without .githooks, a token commit is blocked; the installer refuses when core.hooksPath is set. |
| T-WS-1 | AC-1 | APP-4 | int | G-merge | A clean `npm ci` installs both workspaces and installs the hooks. |
| T-WS-2 | AC-8 | APP-4 | int | G-merge | A deliberate lint error in a workspace makes root `npm run lint` exit non-zero (error removed before commit). |
| T-CON-1 | AC-5 | APP-3 | unit | G-merge | HealthResponse accepts both contract bodies and rejects other status values. |
| T-CFG-1 | AC-4 | APP-4 | unit | G-merge | Valid env parses with the documented defaults. |
| T-CFG-2 | AC-4 | APP-4 | unit | G-merge | Missing DATABASE_URL exits 1 and names it. |
| T-CFG-3 | AC-4 | APP-4 | unit | G-merge | An invalid PORT with a DATABASE_URL set prints no setting value. |
| T-DB-1 | AC-7 | APP-5 | int | G-merge | The test container answers select 1, and no container is left after the run. |
| T-DB-2 | AC-5 | APP-5 | int | G-merge | A pool error is logged without the connection string and does not crash the process. |
| T-MAN-1 | AC-3 | manual | manual | none | Given compose is up with a test table row, when it is stopped and started again, then the row is still there. |
| T-MIG-1 | AC-6 | APP-6 | int | G-merge | Two fixture migrations apply in order once; a second run applies nothing. |
| T-MIG-2 | AC-6 | APP-6 | int | G-merge | A failing second file leaves neither file applied and exits 1. |
| T-MIG-3 | AC-6 | APP-6 | int | G-merge | A run while another holds the lock exits 1 with nothing applied. |
| T-HLT-1 | AC-5, D-18 | APP-7 | int | G-merge | Healthy database gives 200 with the ok body. |
| T-HLT-2 | AC-5, D-18 | APP-7 | int | G-merge | An unreachable database gives 503 in under 1500 ms, with no host or driver text in the body. |
| T-HLT-3 | AC-5, D-18 | APP-7 | int | G-merge | After the pooled backends are terminated, the process stays up and the next call gives 200. |
| T-HLT-4 | AC-4 | APP-7 | unit | G-merge | Authorization and cookie headers appear redacted in the request log. |
| T-SRV-1 | AC-4 | APP-8 | int | G-merge | Starting with invalid config exits 1 before the port opens. |
| T-SRV-2 | AC-4, D-14 | APP-8 | int | G-merge | The server started with plain node answers /healthz, and SIGTERM exits 0. |
| T-CI-1 | AC-9, D-11 | manual | manual | G-merge | Given the draft PR, when CI runs, then the server and app checks both report; golden failures follow D-24. |
| T-DOC-1 | AC-11 | manual | manual | G-merge | Given the PR, then CLAUDE.md, README and the profile name the new folders and commands, and verify.app runs the server checks. |
| T-APP-1 | AC-2 | APP-11 | int | G-merge | The app part of verify.app gives the same results as the APP-0 baseline. |

## Stop and hand back when
- The forbidden scan reports any hit, in a commit, the branch diff, a message or the PR text.
- Docker is not running (the APP-0 HUMAN need is open) when a task needs it.
- A task would deviate from a decision. Record the deviation first.
- A value this brief needs is missing.
- Verify is still red after 2 fix rounds.
- A change is needed outside the task's Files.
- Credentials or production access are needed.
- The next step is a push to a protected branch, marking a PR ready, or a merge.
- The draft PR is open and its body is checked.

## Hand-back report
- PR: link and state
- Tool and model: as recorded in progress
- Baseline → final: tests, lint, typecheck
- Tasks: done and blocked, with commit shas
- Deviations: each with the decision it touches and the proposal
- Surprises: what this brief did not predict, with evidence
- Next HUMAN step

## PR body
- Title: `Team server foundations (roadmap phase 0)`.
- Body: per task id what changed; test ids and results; deviations; HUMAN steps left (CI golden check; branch protection on qa, if wanted); D-25 scan counts. End with the tool's attribution lines.
