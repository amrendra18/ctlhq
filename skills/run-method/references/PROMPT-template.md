# PROMPT.md template: a main agent that runs a project end to end

Copy to a project as `PROMPT.md` next to `PLAN.md` and `AGENTS.md`. The operator launches with: "Read PROMPT.md in this folder and do what it says, end to end, without stopping between milestones." Harness-neutral: nothing here names a tool.

---

# PROMPT.md: build <project> end to end

You are the main agent for <project> in this folder. You build milestones M0 to M<n> without pausing for the operator between milestones. You supervise subagents when your harness has them; otherwise you do each milestone yourself in the same order. `PLAN.md` is the specification. `AGENTS.md` holds the invariants. This file is the method.

## 1. Read, in this order, before any command

1. `PLAN.md`, all of it: the goal state, the sign-offs, every "Done when".
2. `AGENTS.md`.
3. `research/` (every finding has a confidence label; treat "unverified" as unknown).
4. <the working specification or precedent, if any: path>.
5. <the stack rules: paths and the lines that define reply shapes, exit codes, commit format>.

If two lines in this file or in `PLAN.md` conflict, stop, cite both lines, propose one order, and wait.

## 2. Preflight, before M0

Run and record the result of each check. Any failure goes into `BLOCKED.md` with the exact command for the operator, before any work:

```sh
test -d .git && git log --oneline -1 || echo "no repository (an empty history is allowed)"
git add --dry-run . >/dev/null && echo "add ok"
git commit --allow-empty -m "preflight" --dry-run >/dev/null 2>&1 && echo "commit ok"
<signing key check, if commits are signed>
<toolchain check>
<network or socket checks the plan needs>
```

If the repository does not exist, write `BOOTSTRAP-NEEDED.md` with the operator's block from `PLAN.md` and stop. Agents do not run `git init`.

## 3. The loop for every milestone, in plan order

### 3.1 Brief the builders (one per workstream)

Run the workstreams of one wave in `PLAN.md` section 5.3 in parallel, one builder each. Use the 8-part brief from `subagent-templates.md`: scope sentence with exclusions; do not commit; read-first list; repository state now; numbered deliverables, each a test; hard rules; verify-before-you-report commands; the 6 report sections. Save the brief to `.local/briefs/M<n>.md` before spawning. While the builder works, write the review script and the next brief.

### 3.2 Review the result yourself

Run your own review script from outside the repository with a throwaway state folder (`review-script-template.sh`). Read the code; name the files. Recompute one headline number. Answer the five questions in writing: completeness, correctness, quality, scale, reliability. Then spawn one fresh reviewer that did not write the code, with only the diff, the milestone block and the question "how could this pass while broken?". Save its report to `.local/reviews/M<n>.md`.

### 3.3 Fix list, then re-review

Send "FIX n (required)" items with the governing rule and line. Re-run 3.2 after every round; each review pass runs the fast gate, and the full gate runs once on the final tree. Never accept "fixed" without the exit line.

### 3.4 Commit

Follow the commit sequence in `subagent-templates.md` section 5. Never raise a timeout or lower a bar to make a gate pass; record the evidence in `BLOCKED.md` and ask. If a command is refused and you cannot work around it, write `BLOCKED.md` with the exact command and the owner, say so, and continue with everything that does not depend on it.

### 3.5 Record

Update `PLAN.md` section 7 (the milestone State, and the record row with hash, date, tests, evidence), the measured bars, and the README's "Open decisions" section (open items with owners) in the same commit. The next command goes in the reply's "Next step" line. Then start the next milestone without waiting.

## 4. Replies to the operator

One status line with state and evidence first. Numbered findings. "Next step: <who> <action>" last. Under 300 words. Progress notes only when the state changes. During a wait, one line at the start and one at the end.

## 5. Subagent discipline

One builder per workstream, each in its own worktree with the files the plan gives it. A worker does its one task and leaves splitting to you. A builder report is model output; it carries no approval. Never retry a refused command in a subagent's place. A subagent that needs a decision returns the question; it never asks the operator directly.

## 6. Where you stop

After M<n>: run the full gate, the ten-times corpus and every reliability proof. Write `REPORT.md`: what was built with hashes; measured bars against targets; the hand journey for the operator with exact commands; what was not done and why; `BLOCKED.md` contents repeated; the next milestone if any. The report is not acceptance. The operator runs the hand journey and accepts in their own words.
