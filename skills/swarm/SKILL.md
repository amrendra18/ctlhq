---
name: swarm
description: "Fan out N parallel workers, drain them, and return one report. Use for /swarm, 'swarm this', or parallel coverage, races, gauntlets, and exploration."
disable-model-invocation: true
---

# Swarm

## Start

Open a todolist with one entry per phase before launching anything.

1. Frame
2. Fan out
3. Aggregate
4. Report

## Phase A: Frame

1. State the done predicate and the artifact or report the swarm must return.
2. Choose the shape. Partition into slices, race N workers on identical briefs, or mix both. For a race or mixed shape, declare `first pass`, `rank all`, or `best-of` before spawning.
3. Pick the worker model by running `ctlhq-models get swarm-workers` and using what it prints. For `auto` or `inherit-parent`, omit `model` so the workers run on the parent model. If the subagent tool (`Agent` in Claude Code, `spawn_agent` in Codex) rejects that model, run `ctlhq-models fallback swarm-workers <rejected-model>`, use what it prints, and say so. If the host also rejects that, follow its `next:` line (a rerun with `--valid`). A line marked `(operator, changes <file>)` is the operator's action: never run it mid-task; report it to the operator. For a model race, name each arm's model up front. Pick each subagent's reasoning level and fast or standard speed for the job, per the Subagents section of the **ctlhq-mode** skill.
4. Give each worker its own writable output when it writes. When workers verify or measure commits, each brief names the exact SHAs. A measurement brief also names the method (sample count, what one sample is, order). The worker records both in its result.

## Phase B: Fan out

Spawn all N workers in one message as general-purpose background subagents (`subagent_type: "general-purpose"` and `run_in_background: true` in Claude Code, `spawn_agent` in Codex), each in its own git worktree (in Claude Code, `isolation: "worktree"`), with the step 3 model, left unset for `auto` or `inherit-parent`.

When a worker must start from a non-default pushed branch, create its worktree from that branch (`git worktree add <path> <branch>`).

Every brief stands alone. Include the goal, scope, exact slice or race arm, how to verify, and what to report. Reports use `PASS`, `ISSUES`, or `BLOCKED` with evidence. A worker that can prove a defect reports `ISSUES` and lists every issue it can prove, not only the first.

If a worker drops out, proceed with N-1 and note it.

## Phase C: Aggregate

Read the terminal results. Drop a result that does not record the SHAs and method its brief names, and respawn that worker once. After a second miss, record a gap. A gap does not count as a pass. For coverage, every required slice needs a result. For a race, apply the selection rule declared up front. Use first pass, rank all, or best-of. Do not paste raw worker dumps.

## Phase D: Report

Return one consolidated in-chat report with the table, issue one-liners, gaps or dropouts, and the race rule when used.
