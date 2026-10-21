# PLAN.md template

Copy this file to a project as `PLAN.md`. Fill every section and replace or delete each part in angle brackets. `ctlhq-plan-lint PLAN.md` (this repository's `bin/`) prints a fix line for each part that is missing or unfilled. The plan is the record. Chat and approval requests cite it by path and commit hash.

---

# <Project name>

Status: <date>. <one line: planned / building Mn / complete>.

## 1. What, why, how

**What.** <Three to six lines a newcomer can follow: what it is, who uses it, what they type or click, what they get back.>

**Why.** <The problem it removes for that user, and how the user does the job today.>

**How.** <Two to four lines: the surface, the stack, where data lives. No model, no network, no service, unless this plan says so.>

Owns: <the behaviour this project is responsible for>.
Does not own: <what belongs to other tools or is out of scope for good>.

## 2. What exists today

| # | Fact | Measured value | Where measured |
| --- | --- | --- | --- |
| 1 | <example: files in the corpus> | <1,036> | <command or script, date> |

<Every number in this plan rests on a row here. Measure with a throwaway prototype before setting a bar. Never estimate.>

## 3. Complete, in plain words

<One paragraph of what the operator sees when this is done: the command they run, what it prints, how long it takes.>

Complete when three sign-offs hold on the same commit:

1. **The builder's evidence.** `./scripts/check full` exits 0, `scripts/verify full` exits 0, and every test named in a "Done when" cell exists and passes. The main agent reruns them.
2. **The main agent's review.** Five questions answered in writing, in the commit message under `Test Plan:`: completeness (every "Done when" cell met), correctness (hand journey on real data), quality (code read, named files), scale (ten-times corpus inside the bars), reliability (kill, concurrency, no-network proofs).
3. **The operator's hand journey.** The operator runs `scripts/hand-journey` (steps below) and accepts in their own words. Nothing else counts as acceptance.

Accepted by operator on <date>: "<their words>", ledger row <n>. <blank until it happens>

### Hand journey (sign-off 3)

| Step | Command | What to look for |
| --- | --- | --- |
| 1 | <command> | <what "works" looks like> |

### Measured bars

| # | What | Bar | Where measured |
| --- | --- | --- | --- |
| 1 | <warm start> | <under 1 s> | <test name> |

### Not part of complete

<Numbered list. Each item says why it is out and what would bring it in.>

## 4. Deferred by the operator, do not raise

<Topics the operator has deferred. The agent does not mention them until the operator reopens them.>

## 5. How it is built and checked

### 5.1. Architecture and contract

<Modules, files, data folder, reply shapes, exit codes. Copy shapes verbatim from the governing rules file with its line number; never retype a shape.>

### 5.2. Repeated jobs

Every job that runs more than once gets a command and a check before the work that depends on it. Replace each command below with this project's own. Add a row only for a job this project already runs more than once.

| # | Job | Command | Check that proves it done |
| --- | --- | --- | --- |
| 1 | Prove the product works on the real surface (the harness from `verify-setup`) | `scripts/verify fast` | Exit 0. The last line names the evidence folder under `.local/verify/`, and its `summary.json` lists every mapped feature as proven. Exit 1 names the failed feature. |
| 2 | Fast gate, run by each review pass inside a round | `./scripts/check fast` | Exit 0. |
| 3 | Full gate, run once on the final tree of a round | `./scripts/check full` | Exit 0, read from the exit line directly. |

### 5.3. Workstreams and waves

Rows with the same wave run in parallel. Each writable file and shared resource (ports, live sessions, test data, the main agent's own writes) has one owner. Read-only work (investigations, plans, reviews) needs no row; the main agent runs it in parallel from the start. One row in which the main agent owns all files is a valid table.

| # | Wave | Workstream | Owns these files | Depends on |
| --- | --- | --- | --- | --- |
| 1 | <M1 wave 1> | <workstream name> | <`src/feature-a/`, `tests/feature-a/`> | <none, or the row it waits for> |

### 5.4. Audit rule

**When.** Hooks from first-commit check every commit and push. After each accepted milestone, before the next feature starts, the main agent runs the `project-audit` skill on the accepted commit.

**Bar.** 0 high and 0 medium findings. A critical finding counts as high. Low findings are recorded and fixed when cheap; a low finding never keeps the loop running.

**Severity scale.** The scale in `project-audit` `references/report-contract.md`, section "Severity", fixed before round 1. Grading does not change between rounds.

**Stop.** Audit and fix repeat until the bar holds. When the high plus medium count fails to fall 2 rounds in a row, the loop stops and goes to the operator as a named exception. `bin/ctlhq-audit-report check` on each round report computes the verdict. Write one "Round 1 started: 2026-10-20T09:00Z" line and one "Round 1 ended: ..." line per round in section 7, so `ctlhq-status` shows the cost.

**Fix kind.** An audit fix changes behaviour only to remove a finding. A fix that adds a check, a scan, a mode, or a rule opens a milestone in section 7 with its own "Done when".

## 6. Milestones

<One block per milestone, ordered by dependency. Each "Done when" lives in its section 7 row.>

M0 is always the harness (`scripts/verify`, from `verify-setup`) plus one real user journey. The journey drives the real app the way a user does, never a mock of the product.

### M0: <harness and the first journey>

- **Outcome.** <what the operator can do after this milestone that they could not before>
- **Build.** <files and behaviour, numbered>
- **Test first.** <the tests written before the code, by name>
- **Not in this milestone.** <explicit exclusions>
- **Depends on.** <milestone or operator action>

## 7. Milestone status

The next step is the first row whose State is `in progress`, else the first `planned` row. State is one of `planned`, `in progress`, `done`, `blocked`; `done` is one row, and "complete" (section 3) is the whole plan. Each "Done when" cell names the verification command and its exit codes.

| # | Milestone | Done when | State |
| --- | --- | --- | --- |
| M0 | <harness and the first journey> | `scripts/verify fast --feature` <journey name> exits 0 and names its evidence folder; with <planted failure> it exits 1 and names the feature; `./scripts/check full` exits 0. | planned |
| M1 | <name> | <the verification command> exits 0; <named tests> pass; <measured number> within its bar. | planned |

### Milestone record

| # | Milestone | Commit | Date | Tests | Evidence folder |
| --- | --- | --- | --- | --- | --- |
| 1 | M0 | | | | |

Last session: <session id>.

<Update both tables after every commit. A session that resets or a new session resumes from here.>

## 8. Decisions

<Numbered, dated, with the reason and what was rejected. Settled decisions are not reopened without new evidence.>

## 9. Open questions for the operator

<Each as its own numbered yes-or-no question with one recommendation and what each answer changes. Move answered ones to Decisions.>

## 10. Approvals ledger

| # | Date and time | What was approved, exactly | Plan file and commit | By whom, in their words | Covers until |
| --- | --- | --- | --- | --- | --- |

<The first row approves this plan and committing it; it cites the commit the main agent made on that yes, for example `PLAN.md` at `a1b2c3d`. Later rows cite the plan's last commit. An earlier message is never new approval after a context reset. Check this table.>
