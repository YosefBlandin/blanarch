---
spec: server-foundations
ticket: none
tier: M
status: executing
refs: app@a278702
door: 2-way
appetite: about 4 focused days; nothing is deployed, one PR into qa
---
# Team server foundations (roadmap phase 0)

<!-- The executor reads this file. Outcome, Why and question cards are plain language: at most 25 words per sentence, no code spans, terms from the Glossary. Other files cite the ids defined here and never restate them. Examples sit in these comments; comments do not count toward the budget. -->

## Request (verbatim)
<!-- Pasted at intake, word for word: the ticket's acceptance criteria, or the user's request when there is no ticket. Remove personal data; keep internal ids. The intent phase turns it into AC rows. Do not edit it after intake. -->
Intake command (user, 2026-10-18): "intake Phase 0: Foundations for the Blanarch team server"

Phase 0 scope, from the roadmap the user approved on 2026-10-18:

> 0. **Foundations:** workspaces, Compose, Fastify skeleton with `/healthz`, zod config, Kysely, migration runner, vitest + Testcontainers, ESLint and Prettier, and GitHub Actions CI covering the server, admin and Flutter/Kotlin checks. Update `docs/specs/spec-profile.md` with the server and admin verify and preflight steps (node, docker), and fix its stale "no remote" note. Update `CLAUDE.md` with the new folders and commands. Install OrbStack (a human step).

The user's original request for the whole server (later phases cover the features):

> I'd like to add valuable features here, which I'm gonna use as learning process too. TypeScript, fastify, zod, posgresql, I want to add a server so we can add the following: admin log in, admin can create a team with a secure login and session, Signed profile distribution. An admin publishes connection profiles (host, port, pinned fingerprint, no passwords) and the server signs them. The app verifies the signature before using them. Teaches: schema design, signing, API versioning. Device enrolment by link or QR. A single-use, short-lived token in an blanarch://enrol link exchanges for a device credential. Teaches: token security, hashing at rest, rate limiting.
> Device revocation. An admin removes a device and it loses access on its next sync. Teaches: token revocation, refresh handling, handling offline clients.
> Audit log. Every admin action is recorded: who did what, and when. Teaches: append-only modeling, querying over time. Opt-in connection health telemetry. The app batches typed error codes, drops, and rejoin times, and uploads them when online. The server ingests them idempotently. Keep it off by default and never send passwords, hostnames, or traffic details. Teaches: ingestion, idempotency, time-series in Postgres, retention.
> Admin dashboard. Connection success rate, time to connect, and drops per network over time. This is your React and data-viz strength, so it also works as a portfolio piece. Teaches: aggregate queries, caching.
> Diagnostics upload. A "send my redacted Activity log to support" button, with signed upload URLs and automatic deletion after a set time. Teaches: file storage, background jobs, data lifecycle.  Don't build: anything that sends one-time codes or passwords through the server.

## Outcome
<!-- What a named user can do or see after this ships, in 2 to 4 plain sentences. -->
The owner can start the team server and its database on a laptop with a few commands, and see it answer a health check. Every pull request is checked automatically, for both the new server and the existing app. Later phases add features on top of this base without redoing setup.

## Why
<!-- The problem today and why it matters now: cost, risk, noise or a request. 2 to 4 bullets, with numbers where you have them. -->
- Every later roadmap phase needs a running server, a database with versioned changes, and automatic checks. Building them once avoids repeating setup six times.
- Nothing checks pull requests today, so a broken app build is only found on the owner's Mac.
- The forbidden word check silently does nothing in the side copies agents work in, so private names could leak into a public repo.
- This is a learning project. A clean base makes each later lesson about one topic, not about tooling.

## Acceptance criteria
<!-- Turn the Request into testable rows. One behaviour per row: "When <trigger>, the system shall <response>." (or While, or If ... then). From: ticket, a decision id or user. Ids are append-only; to retire one, start its statement cell with RETIRED. Example row: | AC-1 | When a user opens a page, the system shall write exactly one page-view event for that page. | ticket | -->
| AC | Statement | From |
|---|---|---|
| AC-1 | When a developer runs one install command at the repo root, the system shall install the server and contract packages as workspaces. | D-6 |
| AC-2 | While the new workspace is installed, the app's own checks shall give the same results as the baseline. | user |
| AC-3 | When a developer starts the local services, the system shall run the database in a container and keep its data across restarts. | D-10 |
| AC-4 | If the server starts with a missing or invalid setting, then it shall exit before accepting requests and name the setting, without printing any secret value. | user |
| AC-5 | When a client calls the health check, the server shall reply with its status and whether the database is reachable, and reply unhealthy when it is not. | user |
| AC-6 | When a developer runs the migrate command, the system shall apply each pending plain SQL migration once, in order, and record it, so a second run applies nothing. | D-8 |
| AC-7 | When the server tests run, the system shall start a fresh throwaway database for them and remove it afterwards. | D-10 |
| AC-8 | When a developer runs lint, typecheck or test at the repo root, the system shall run it for every workspace and fail on any error. | user |
| AC-9 | When a pull request targets qa, CI shall run the server checks and the existing app checks, each reported as its own check. | user |
| AC-10 | When anyone commits in a copy of the repo where the root install has run, on any branch, the forbidden word check shall block a commit whose changes or message contain a listed string, and block with a clear message when the list is missing, unless the person explicitly opts out because they have no list. | user, D-22 |
| AC-11 | When this change merges, the project rules file, the spec profile and the readmes shall list the new folders and commands, and the profile shall verify the server too. | user |

## No-gos
<!-- What this work will not do, each with a one-line reason or the decision that settled it. -->
- No admin login, teams or other feature endpoints. Those start in roadmap phase 1.
- No admin web app yet. It is created in phase 1 together with its first screen.
- No deployment or hosting. Nothing leaves the laptop (D-13); hosting is roadmap phase 7.
- No app changes (D-2).
- No secrets in the repo. Local settings come from an ignored env file; only an example file is committed.

## Constraints
<!-- Project rules this change must honour, as pointers (file and section), and hard limits from intake. Never copy the rules here; the brief copies the values it needs. -->
- Public-ready repo: app repo, CLAUDE.md, section "Clean-room rule" (last two bullets), and the forbidden-strings file named in spec-profile.md. The pre-commit hook must also cover the new server folders.
- Secrets: app repo, CLAUDE.md, section "Secrets and signing". Server config secrets come from the environment and are never committed or logged.
- Clean-room rule: app repo, CLAUDE.md, section "Clean-room rule". This change does not touch the protocol engine, so no protocol doc or log task applies.
- App stays green: app repo, CLAUDE.md, sections "Commands" and "Features to keep working". The app's verify commands in spec-profile.md must pass unchanged.
- Commits: app repo, CLAUDE.md, section "Conventions" (last bullet).
- Git and worktrees: the environment file named in spec-profile.md, section on git. Work in a worktree; never push to staging or main.
- Privacy in logs and reports: the environment file, privacy section.
- Hard limit from the user's request: nothing sends one-time codes or passwords through the server.
- Spec profile upkeep: docs/specs/spec-profile.md gets server verify and preflight entries and loses its stale "no remote" note, as part of this change.

## Glossary
<!-- Every term the plain-language text and question cards use. One line each. Example row: | page view | One visit to one page or named tab, recorded once. | -->
| Term | Meaning |
|---|---|
| team server | The new companion server for team admins, built over roadmap phases 0 to 7. |
| CI | The automatic checks GitHub runs on every pull request. |
| golden screenshots | Saved images of app screens. Tests fail when a screen draws even one pixel differently. |
| forbidden word list | The private list of company names and hosts that must never be committed. |
| object store | A file storage service with the Amazon S3 interface, used later for diagnostics uploads. |

## Open questions
<!-- M tier only: at most 3 question cards here, in the questions.md card format, then one Send list line: owner role and question ids, no names. L tier: cards live in questions.md, so delete this section. -->
None open.

### Answered
| Q | Decision | Date | Who |
|---|---|---|---|
| Q-1 | → D-10 | 2026-10-18 | owner |
| Q-2 | → D-11 | 2026-10-18 | owner |
| Q-3 | → D-12 | 2026-10-18 | owner |
