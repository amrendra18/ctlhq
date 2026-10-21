---
name: no-comments
description: "Spawn a comment reviewer subagent, fix accepted findings, and offer encodings for claimed constraints."
disable-model-invocation: true
---

# No comments

Spawn a comment reviewer subagent that follows [`references/reviewer.md`](references/reviewer.md). Act on accepted findings.

Defer to the reviewer's fresh perspective.

## Tool

Run the lister first and hand its output to the reviewer as the scope, so the reviewer spends its attention on judging comments, not finding them.

```
bin/ctlhq-no-comments --diff main   # from this skill's folder, or `ctlhq-no-comments` when ctlhq/bin is on PATH; --help lists every flag, tag, and exit code
```

A tag marks a candidate, not a verdict. The reviewer decides, under its own exception list. Use `--strict` so a diff with only tagged comments still reaches the reviewer. Use `--removed` for the deletion count that step 6 reports. `--require-expiry` applies the **mistake-proof** skill's rule that an exception carries a reason, an expiry date, and a human's approval.

## Scope

Use the caller's files or diff. Otherwise use the current diff against the base branch, default `main`, including the working tree.

## Steps

1. Spawn a generic subagent, `Agent` with `subagent_type: "general-purpose"` in Claude Code or `spawn_agent` with the default agent in Codex. Its prompt gives the absolute path of `references/reviewer.md` in this skill's folder and tells it to read that file first and follow it as its instructions. Pass the scope. Pick each subagent's reasoning level and fast or standard speed for the job, per the Subagents section of the **ctlhq-mode** skill. Do not restate its rules. Reviewers are set up per the **blind-review** skill's section 1 (what a reviewer receives and never receives).
2. Inspect its report and diff. Reject application-code edits, scope escapes, exception-protected deletions, misstated `MUST KILL` reasons, and flags that treat kept intentional code as guilty. Reshape flags on our-code surprises stay actionable. Do not restore those comments. A keep survives only with proof it is about something we cannot change. Audit missed scoped lint and TypeScript suppressions. Correctness or safety suppressions stay actionable `MUST KILL`s. Restore deletions only with exact exceptions and scoped proof. Before accepting thin `IMPORTANT` or `do not remove` kills or keeps, run `/how` or `/why` on their symbol. If a kill is ambiguous, do not restore. If a keep is refuted or still ambiguous, delete it. Revert and rerun one rejected report with the failure named. Reject a second, report it open, and fail `/no-comments`.
3. Fix trivial accepted flags directly by deleting a dead path, dropping a parameter, or using the real API. If any fix needs a shape, run `/architect` once for the accepted set and surrounding code. Stop at the sketch. Architect shapes. Step 4 implements.
4. Implement the smallest root-cause fix in scope. Remove every named workaround. If the root cause is out of scope, land the smallest in-scope fix and report the rest open. The **principle-fix-root-causes** and **principle-redesign-from-first-principles** skills guide intent only. Neither authorizes widening the fence nor fixing instances outside it. Never bolt on symptom guards.
5. Constraint comments say `do not remove`, `do not change wording`, or `talk to X before changing`. Leave keeps about things we cannot change. Offer the cheapest in-scope type, runtime, test, or CI lint. Wait for interactive approval. Unattended and eval require caller pre-approval. If approved, encode then delete. Otherwise delete, report the constraint open, and sketch out-of-scope work.
6. Report the deletion count, restored comments, reruns, architect sketch, fixes, encoding offers, encodings, unenforced constraints, and other open work.
