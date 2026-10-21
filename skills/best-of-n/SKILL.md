---
name: best-of-n
description: "Spawn N parallel candidates at the same task, pick a base, graft the strongest parts of the losers into it. Use for /best-of-n, 'best of n', 'arena this', 'throw it in the arena', or when one attempt at a non-trivial artifact would lock in the wrong shape."
disable-model-invocation: true
---

# Best of N

Open a todolist with one entry per phase (Frame, Fan out, Cross-judge, Pick, Graft, Verify) before launching anything.

## Phase A: Frame

Every candidate gets the same prompt, so the prompt is the contract.

1. State the artifact each candidate is producing.
2. Derive the rubric, 3-6 concrete gradeable criteria for what success looks like on *this* task. It is the picker's tool in Phase D. Candidates only see the task.
3. Pick the runners. Run `ctlhq-models get best-of-n-runners` and spawn one runner per entry it prints. An `auto` or `inherit-parent` entry in this role or the cross-judge role means the parent model, so omit `model` for it. If the subagent tool (`Agent` in Claude Code, `spawn_agent` in Codex) rejects a configured entry, run `ctlhq-models fallback best-of-n-runners <rejected-model>`, run that seat on what it prints, and say so. If the host also rejects that, follow its `next:` line (a rerun with `--valid`). A line marked `(operator, changes <file>)` is the operator's action: never run it mid-task; report it to the operator. Spawn more runners when the run covers multiple design directions. Use the same model N times when the work is generation-bound rather than judgment-sensitive. Pick each subagent's reasoning level and fast or standard speed for the job, per the Subagents section of the **ctlhq-mode** skill.
4. Give each candidate its own output location (a git worktree where possible, otherwise `/tmp/<slug>-<n>/`, where `<slug>` is a project-shaped name that holds none of the banned words in the ctlhq-mode eval playbook, so the same folder can serve an eval run), per the **separate-before-serializing-shared-state** principle skill.

## Phase B: Fan out

Spawn all N subagents in one message with `run_in_background: true`, each with the task, the path to the shared grounding, its own output path, and instructions to produce the artifact and a short rationale naming the alternatives it considered and what it rejected.

If a candidate produces no output, proceed with N-1 and note the dropout.

## Phase C: Cross-judge

After all Phase B candidates complete, run `ctlhq-models pick best-of-n-cross-judge-pool --not-family <parent-model>` and use the model it prints, because the judge should prefer a different model family from the parent's. When every entry shares the parent's family, it prints the first entry and says so: use that entry and say "same-family review (<family>)" in the reply. A line marked `(operator, changes <file>)` is the operator's action: never run it mid-task; report it to the operator. Spawn one read-only judge subagent on that model. In Claude Code, use `subagent_type: "Plan"`, a built-in type without Edit, Write, and NotebookEdit. Tell the judge it is read-only in both hosts, because Codex has no read-only subagent type and `Plan` still has Bash. It sees the rubric and the candidates by path label, scores each criterion, and recommends a base with rationale. It runs in parallel with your reading in Phase D. Don't spawn it while candidates are still writing. The judge is set up per the **blind-review** skill's section 1 (what a reviewer receives and never receives).

## Phase D: Pick a base

Read every candidate end to end before picking. Score each against the rubric criterion by criterion, not on holistic feel, and compare with the cross-judge. Agreement on the base confirms the pick. Disagreement means one of you is biased or the rubric was ambiguous. Read both rationales before deciding.

Pick the base a future maintainer can extend most easily without breaking invariants. When two feel tied, prefer the cleaner boundary or smaller API, per the Laziness Protocol.

## Phase E: Graft

Walk each losing candidate once more for what is worth porting into the base, usually one or two things per candidate, not most of it. Fold each graft in by hand, per the **redesign-from-first-principles** principle skill, so the result stays coherent under one mental model. Don't paste mechanically.

If the candidates converge on one shape, that is strong agreement. Note it and ship the consensus shape. No graft is needed. If they wildly diverge, Phase A was under-specified. Reframe and re-run rather than averaging the divergence.

## Phase F: Verify

Verify the synthesized artifact like any other output, per the **prove-it-works** principle skill. If verification finds a problem the best-of-n run missed, either Phase A was wrong (re-frame and re-run) or a candidate caught it and you missed the graft (go back to Phase E). Don't paper over it.

## Outputs

One synthesized artifact, with a short synthesis note alongside naming the base and why, the cross-judge's verdict, each graft with its source candidate, what was rejected and why, any convergence or dropouts, and the verification result.
