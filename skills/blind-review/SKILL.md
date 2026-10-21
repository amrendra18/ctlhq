---
name: blind-review
description: Independent review of a change by a fresh agent that did not write it. Use before every commit of subagent or main-agent work, before publishing a report the operator will rely on, whenever "independent review" is requested, and on a plan before building. The author never reviews its own work.
---

# Blind review

Independent means a fresh context that did not write the code. Self-review, or a fork of the builder, does not count.

## 1. What the reviewer receives, and nothing else

1. The diff (`git diff <base>..<head>`), or the report file.
2. The milestone block from `PLAN.md` (Outcome, Done when, Not in this milestone) and `AGENTS.md`.
3. The governing rules file lines that define shapes and exit codes.
4. The repository path, read-only. A throwaway state folder for runs.

Do not give the reviewer the builder's report, the main agent's suspicions, or the fix history.

A plan reviewer receives the inputs in section 5 instead of items 1 and 2. Every reviewer runs on the model section 4 picks.

## 2. The brief

```
You are reviewing a change you did not write. Read only the inputs listed.
Question 1: how could this pass its tests while being broken for the operator?
Question 2: which "Done when" line is not proved by a named test? Cite the line.
Question 3: which invariant in AGENTS.md could this change break? Name the test that would catch it.
Question 4: which negative claim has no positive control (expected shown next to observed)?
Run the check lanes yourself from outside the repository and paste the exit lines.
Try the hand step on real data with the throwaway state folder.
Report: 1. verdict (accept / fix first / reject); 2. defects, each with file, line, the rule
broken, and how to reproduce; 3. what you ran, with exit codes; 4. what you did not check.
No defect without a reproduction. "I did not check" is a valid line.
```

## 3. What the main agent does with it

1. Save the report to `.local/reviews/<milestone-or-commit>.md`.
2. Every "fix first" defect goes into the builder's fix list with the reviewer's reproduction.
3. Record the verdict in the commit message under `Test Plan:` as "blind review: <verdict>, <n> defects fixed".
4. A commit without a saved review file is not allowed in projects that adopt this skill.

## 4. The reviewer's model

The reviewer runs on a different model family from the author when the host offers one, so it does not share the author's blind spots.

1. Run `ctlhq-models pick planners-and-reviewers --not-family <author-model>` (in Codex, add `--host codex`). The author model is the builder's model, or the parent model for main-agent work. `planners-and-reviewers` is the operator's role for plans and reviews (`skills/ctlhq-setup/SKILL.md` step (d)); blind review has no role of its own.
2. Spawn the reviewer on the model it prints. In Codex, when the subagent tool takes no model name, run `codex exec -m <model> -c model_reasoning_effort=xhigh` with the brief. Exit 1 means the role's model shares the author's family, and it prints that model. Run on it and write "same family as the author" in the review file.
3. Inside Claude Code every model is Claude family, so the step 1 command exits 1 there with the shipped defaults. A reviewer of a different family has to run from another host, such as Codex. Do that when the operator asks for a different family; otherwise the same-family review stands, labeled as such.
4. If the host rejects the printed model, or the model hits its usage limit, run `ctlhq-models get planners-and-reviewers-limit-fallback` (in Codex, add `--host codex`), run on what it prints, and say so.

## 5. Plan-review mode

Use it before building, when a `PLAN.md`, PRD, or design draft is ready and no code is written yet. The reviewer reads and reports. It changes no files.

The plan reviewer receives:

1. The plan file.
2. The operator's ask, in their own words or as the numbered restatement they said yes to.
3. `AGENTS.md` and the rules files the plan cites.
4. The repository path, read-only, to check that the files, commands, and targets the plan names exist.

It never receives the author's reasoning, the rejected alternatives, or the chat that produced the plan.

```
You are reviewing a plan you did not write. Nothing is built yet. Read only the inputs listed.
Change no files.
Question 1: which part of the operator's ask does the plan drop, and what does it add that
nobody asked for?
Question 2: which "Done when" line has no named test or measured number? Cite the line.
Question 3: which bar is an estimate instead of a measurement on real data?
Question 4: which step depends on something the plan has not proved exists (the real target,
a permission, a tool, a file)? Does milestone 0 prove it?
Question 5: which negative claim has no positive control (expected shown next to observed)?
Question 6: what is the smallest change to the plan that removes the largest risk?
Report: 1. verdict (build / revise first / rethink); 2. findings, each with the plan line, the
problem, and the fix; 3. what you checked in the repository, with the commands; 4. what you
did not check. "I did not check" is a valid line.
```

What the main agent does with it:

1. Save the report to `.local/reviews/plan-<name>.md`.
2. Show the operator the findings beside the plan and discuss them before building. The operator decides each "revise first" finding.
3. Record the verdict and the operator's decisions in `PLAN.md`.
4. No build starts on a "rethink" verdict.
