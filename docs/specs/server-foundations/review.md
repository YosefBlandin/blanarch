---
spec: server-foundations
ticket: none
tier: M
status: executing
---
# Team server foundations (roadmap phase 0): review

<!-- Tables only. Scripts check what can be checked; reviewers judge the rest. No numeric scores and no self-grading: every reviewer is a fresh context, ideally on a different model. M tier adds this file with new-spec.mjs --add review.md when it first needs it. Examples sit in these comments. -->

## Lens review
<!-- At G-design. One fresh reviewer per lens: security and data; contract and deploy; pre-mortem (states and exits); frontend when there is a web or app UI PR. Reviewers report only correctness or requirement gaps, with evidence. Rows have no ids; cite the AC or decision a finding touches. Severity: blocker, major or minor. Disposition: accepted (what changed, where) or rejected (why, with evidence). Example row: | contract and deploy | major | Reads would still write an event per call if the old logger stays on. | D-1 | architecture.md Components | accepted: the logger skips reads; a test checks it | -->
| Lens | Severity | Finding | Cites | Evidence | Disposition |
|---|---|---|---|---|---|
| security and data | blocker | A relative core.hooksPath turns the check off on branches without .githooks, including the main checkout on staging. | AC-10, D-19 | main checkout on staging at a278702 has no .githooks; setting is shared in .git/config | accepted: D-22 supersedes D-19; hooks are copied into the shared hooks folder, core.hooksPath never set; a test commits in a worktree on a branch without .githooks |
| contract and deploy | blocker | Same: core.hooksPath disables the check in every copy without .githooks, from the first install. | AC-10, D-19 | same as above | accepted: same change, D-22 |
| security and data | major | SKIP_FORBIDDEN_CHECK skips the scan even when the list exists. | AC-10, D-19 | Hook behaviour table had no condition | accepted: honoured only when the list is missing or empty (D-22, Hook behaviour table); a hook test covers both cases |
| security and data | major | No pool error listener or connect timeout, so a database stop after start crashes the process. | AC-5, D-18 | createDb described only a Pool and Kysely | accepted: createDb sets 1000 ms connect and query timeouts and a pool error listener (Components, RK-9); a test terminates pooled connections and expects 503 then 200 |
| contract and deploy | major | A revert leaves core.hooksPath pointing at a deleted folder, so no check runs. | AC-10, D-19 | Cross-cutting: rollback is a revert | accepted: with D-22 nothing points at the tracked folder; installed hooks survive a revert (Cross-cutting) |
| premortem | major | Pool error events crash the process when Postgres restarts. | AC-5, D-18 | same as the security finding | accepted: same change, RK-9 |
| premortem | major | Relative core.hooksPath depends on the branch and survives a revert silently. | AC-10, D-19 | same as the blockers | accepted: same change, D-22, RK-10 |
| premortem | major | RK-1 claims D-11 accepts golden mismatches, but no fallback is recorded. | AC-9, D-11 | D-11 row had no fallback | accepted: D-23 adds the rendering-only fallback; RK-1 cites it |
| security and data | minor | A fresh clone has no hook until the root install runs. | AC-10 | architecture: first npm ci enables it | accepted: AC-10 narrowed to copies where the root install ran; README and CLAUDE.md say to run it first (Cross-cutting) |
| security and data | minor | Commit messages are not scanned. | AC-10 | only staged lines scanned | accepted: commit-msg hook with the same scan (D-22) |
| security and data | minor | Decisions table broken: D-10 glued to D-9, blank line before D-14. | D-10, D-14 | decisions.md rows | accepted: table repaired |
| contract and deploy | minor | DATABASE_URL source for migrate and db:types, and the compose settings, are undefined. | AC-3, AC-6 | Settings contract named only dev | accepted: Contracts adds the root .env table and one env-file rule for dev, migrate and db:types |
| contract and deploy | minor | Decisions table broken, and intent cites superseded D-3 and D-7. | D-3, D-7 | intent AC-3, AC-7, No-gos | accepted: table repaired; intent cites D-10 and D-13 |
| premortem | minor | The 1000 ms health bound does not cover the pool checkout. | AC-5, D-18 | Health contract wording | accepted: bound covers checkout and query; test against an unreachable documentation address expects 503 within about 1.5 s |
| premortem | minor | No behaviour stated for a concurrent migrate or an unreachable database. | AC-6, D-15 | migrating state row | accepted: both exit 1 with nothing applied (States and exits) |
| premortem | minor | The hook must be committed executable or git skips it. | AC-10 | no mode stated | accepted: mode 100755 and installer sets the bit (D-22, RK-10) |
| premortem | minor | A missing root .env or a changed password breaks compose with no stated exit. | AC-3, D-10 | compose description | accepted: compose fails loudly on a missing password; reset with down -v in Gotchas (Contracts) |
| premortem | minor | Decisions table malformed. | D-14 | decisions.md | accepted: table repaired |
| security and data (re-run) | major | Executor commits before the hooks exist, and the pushed branch and PR text are never scanned. | AC-10, D-12, D-4 | F-2; origin is public; CI never gets the list | accepted: D-25, hooks installed before the first commit and a counts-only pre-push scan of diff, messages and PR text (Cross-cutting) |
| contract and deploy (re-run) | major | The health time limit is stated three different ways. | AC-5, D-18 | D-18, Health contract, createDb and States disagreed | accepted: one 1000 ms per-request limit in Contracts, Health check; createDb and States cite it; test slack stated |
| security and data (re-run) | minor | The opt-out contradicts AC-10's block when the list is missing. | AC-10, D-22 | D-12 vs D-22 wording | accepted: AC-10 names the explicit opt-out |
| security and data (re-run) | minor | The hook test does not say where its listed string comes from. | AC-10 | RK-10 | accepted: throwaway repo with a made-up token (RK-10) |
| security and data (re-run) | minor | Committed specs are only checked against the forbidden list, not other private values. | D-21 | spec-lint checks only the list | accepted: D-25 pre-push scan includes the private values in CLAUDE.local.md |
| contract and deploy (re-run) | minor | The golden fallback relies on a tag no test has, which would mean app test edits. | D-23, AC-9 | no tags in blanarch/test | accepted: D-24 supersedes D-23; skip by path |
| contract and deploy (re-run) | minor | A revert deletes the owner's local Gradle wrapper files. | D-20 | wrapper files exist locally, ignored at the pin | accepted: restore step in Cross-cutting |

## Cold-read log
<!-- At G-handoff, one run per brief and round: a fresh context on a cheaper or different model gets only intent.md, the brief and the sections it cites (tier S: spec.md). Model class is cheaper, different, or same in a fresh context; never a model name. Gate: zero cannot-start items. -->
| Brief | Round | Date | Model class | Cannot start | Missing values | Assumptions | Fixed in |
|---|---|---|---|---|---|---|---|
| pr-app.md | 1 | 2026-10-18 | cheaper | 0 | 7 | 14 | pr-app.md: Docker blocks only APP-5; root script bodies, dependency and lockfile rule, gh access line, drift and spec-lint commands added; .env copy step in APP-5; baseline field shape in APP-0; T-WS-1 and T-WS-2 moved to APP-4; verify chain uses subshells (also in spec-profile.md); whole spec folder copied in APP-11. Accepted as written: Colima socket variables are a discovery step (RK-6); action majors resolved at write time; worktree folder ignored from APP-2. |

## Conformance review
<!-- Before each draft PR: a fresh reviewer compares the diff with the brief and its test ids. A finding that needs a decision becomes a deviation, not an edit. -->
| Brief | Date | Tasks matched | Test ids found | Off-brief changes | Verdict |
|---|---|---|---|---|---|

## Outcome
<!-- At G-close. One line per AC: pass, fail or partial, and where it was verified, for example: - AC-1: pass, T-E2E-1 on production. Then the merge sha per repo. -->

## Defects
<!-- Every defect found after G-handoff. Origin: spec-gap (the spec was silent), spec-wrong (the spec was wrong), executor (the brief was right, the code was not), env (tools, access, CI). -->
| Defect | Origin | Found at | Fixed in | Kit change |
|---|---|---|---|---|

## Metrics
| Metric | Value |
|---|---|
| Decision point minutes (DP1, DP2, DP3, DP4) | |
| Decision rounds after G-design | |
| Lens findings, and the share rejected (%) | |
| Cold-read cannot-start items, per round | |
| Deviations | |
| Folder tokens; executor required reading (status.mjs) | |

## Kit changes
<!-- Each recurring issue becomes a lint rule or a template change in agent-kit. One line each, naming the defect or metric behind it. -->
