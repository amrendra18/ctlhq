# jot

Status: 2026-10-19. Building M1.

## 1. What, why, how

**What.** A command-line notebook. A user types `jot add "buy milk"` and `jot list`, and gets back numbered notes saved in one local file.

**Why.** The user keeps notes in scattered text files today and cannot list or search them in one place.

**How.** One Python 3.13 command, notes in `~/.jot/notes.json`. No network, no service.

Owns: adding, listing, and searching notes.
Does not own: sync between machines.

## 2. What exists today

| # | Fact | Measured value | Where measured |
| --- | --- | --- | --- |
| 1 | Notes in the test corpus | 1,036 | `wc -l tests/data/notes.txt`, 2026-10-19 |

## 3. Complete, in plain words

The user runs `jot list` on 1,036 notes and sees them numbered in under 1 s.

### Not part of complete

1. Sync between machines, because the user works on one machine.

## 4. Deferred by the operator, do not raise

None.

## 5. How it is built and checked

### 5.1. Architecture and contract

One module, `src/jot.py`. Exit 0 on success, 1 on a missing note, 2 on a usage error.

### 5.2. Repeated jobs

| # | Job | Command | Check that proves it done |
| --- | --- | --- | --- |
| 1 | Prove the product works | `scripts/verify fast` | Exit 0 and the evidence folder on the last line. |
| 2 | Full gate | `./scripts/check full` | Exit 0. |

### 5.3. Workstreams and waves

| # | Wave | Workstream | Owns these files | Depends on |
| --- | --- | --- | --- | --- |
| 1 | M1 wave 1 | search | `src/search.py`, `tests/search/` | none |
| 2 | M1 wave 1 | list | `src/list.py`, `tests/list/` | none |

### 5.4. Audit rule

**When.** After each accepted milestone, before the next feature starts.

**Bar.** 0 high and 0 medium findings.

**Severity scale.** The scale in `project-audit` `references/report-contract.md`, section "Severity".

**Stop.** When the high plus medium count fails to fall 2 rounds in a row, the loop goes to the operator.

## 6. Milestones

### M0: harness and the add journey

- **Outcome.** The user adds a note and sees it listed.

### M1: search

- **Outcome.** The user finds a note by a word in it.

## 7. Milestone status

| # | Milestone | Done when | State |
| --- | --- | --- | --- |
| M0 | Harness and the add journey | `scripts/verify fast --feature add-note` exits 0; with the notes file read-only it exits 1 and names add-note. | done |
| M1 | Search | `scripts/verify fast --feature search` exits 0; `./scripts/check full` exits 0. | in progress |

## 8. Decisions

1. 2026-10-19: one JSON file, because 1,036 notes load in 40 ms.

## 9. Open questions for the operator

None.

## 10. Approvals ledger

| # | Date and time | What was approved, exactly | Plan file and commit | By whom, in their words | Covers until |
| --- | --- | --- | --- | --- | --- |
| 1 | 2026-10-19 10:00 | M0 to M1 as planned | `PLAN.md` at `a1b2c3d` | operator, "yes" | M1 done |
