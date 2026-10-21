# Subagent templates: brief, report, fix list, commit sequence

Use them as written; change only the angle-bracket parts. Section 6 holds the reproduction receipt for defect work.

## 1. The builder brief (8 parts, in this order)

```
<Milestone name> is only <scope sentence>. Not in scope: <exclusions>.
Do this one task; leave splitting to the coordinator.

Do NOT run git commit, git push, or change Git settings. Build, test, report.
Do not create or write the real data folder; use <throwaway folder> for every run.

Read these first, in this order:
1. PLAN.md sections <n> (the milestone block, the contract, the bars).
2. AGENTS.md (the invariants).
3. <governing rules file> lines <a to b> (reply shapes, exit codes). Copy shapes verbatim.
4. <precedent file> (how the last milestone did it).

Repository state right now:
<git status --short; last commit hash; toolchain path; line budget used of total>

Deliverable, each item a test:
1. <behaviour> proved by <TestName>.
2. ...
<For defect work: the reproduction receipt (section 6) comes before any code change.>

Hard rules:
- No network. No writes outside this repository and <throwaway folder>.
- No stubs, no TODOs, no placeholder data.
- Plain English in every message and comment.
- If a required command is denied, stop and report the exact command. Skip optional diagnostics and note them.

Verify before you report:
./scripts/check full      (paste the last 5 lines and the exit code)
<hand command 1>          (paste the output)

Report back with exactly these sections, incidents first:
1. Files changed, with line counts.
2. Check output: the last lines and the exit code of every lane.
3. Tests and measured numbers against the bars.
4. The commit message you propose, in full, written to .local/commit-<n>.txt.
5. Decisions the plan did not settle, and what you chose.
6. What could not be done, and why.
```

## 2. The builder report (6 sections)

Status line first: `implemented and tested: <n> tests, check full exit 0`. Then any incident ("One mistake on my side, already cleaned up: ..."). Then the six numbered sections from the brief, nothing else. Numbers, exit codes and file paths, not prose.

## 3. The main agent's review (before any commit)

Each review pass inside a round runs the fast gate. The full gate runs once, on the final tree, in the commit sequence (section 5).

1. Run your own review script from outside the repository (see `review-script-template.sh`). The builder's report is a claim; your run is the evidence.
2. Read the code. Name every file you read in full in the fix list.
3. Recompute one headline number a second way. Explain any difference.
4. Check: no stubs, no home paths, no writes outside the repository, sibling repositories unchanged, line budget, `git status` shows only the expected files.
5. Answer the five questions in writing: completeness, correctness, quality, scale, reliability.

## 4. The fix list

```
What I verified myself: <lanes run, hand steps run, files read in full>.

FIX 1 (required): <what>, because <rule file> line <n> says <rule>.
FIX 2 (required): ...

Settled by me, no action for you: <decisions I took>.
Your decisions 1 and 3 are accepted as made. Decision 2 is overridden: <why>.

Report back with: the same six sections, plus the diff for each FIX.
```

Re-review after every fix round. Do not accept a report that says "fixed" without the exit line.

## 5. The commit sequence (run by whoever commits, in this order)

1. Add the review paragraph to the commit message under `Test Plan:` (the five answers, one line each).
2. Run the gate: `./scripts/check full`. Read its exit code directly. Never pipe it through `tail` or `grep`.
3. `git add <each path by name>`.
4. `git status --short` shows only the intended `A` and `M` lines.
5. `git commit -F .local/commit-<n>.txt`.
6. Verify: signature (`git log --show-signature -1`), clean tree, `--version` prints the new stamp, the data folder is absent.
7. If a hook rejects the commit, or the harness denies a step: write the exact command and the reason to `BLOCKED.md`, report, stop that step. Keep working on anything that does not depend on it.
8. Record the hash, date, tests and lines in `PLAN.md` section 7 and in memory. Only then report "committed <hash>".

## 6. The reproduction receipt (defect work)

A reported defect is reproduced twice on the current code before anyone changes code. The builder returns this receipt first:

```
Report: <where the report came from>, version <app version or commit the report names>.
Current code: <commit hash the runs used>.
Steps: <numbered steps, setup, and data, copied from the report>.
Run 1 (fresh launch): expected <what should happen>; observed <what happened>; screenshot <path>.
Run 2 (fresh launch): expected <what should happen>; observed <what happened>; screenshot <path>.
Result: reproduced twice / not reproduced on the current code.
```

When neither run reproduces the defect, the current code may already hold the fix. The remaining work is then a release or an explanation, and no code changes.
