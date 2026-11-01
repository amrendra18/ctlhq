---
name: commit-review
description: Review one commit with a fresh agent that did not write it. Use before every commit of subagent or main-agent work, and whenever an independent review is requested. The author never reviews its own work. Holds the reviewer setup and the question list that plan-review and pr-review use too.
---

# Commit review

Independent means a fresh context that did not write the code. Self-review, or a fork of the builder, does not count.

## 1. What the reviewer receives, and nothing else

1. The diff (`git diff <base>..<head>`).
2. The milestone block from `PLAN.md` (Outcome, Done when, Not in this milestone) and `AGENTS.md`.
3. The governing rules file lines that define shapes and exit codes.
4. The repository path, read-only. A throwaway state folder for runs.

Do not give the reviewer the builder's report, the main agent's suspicions, or the fix history.

## 2. The reviewer's model

The reviewer runs on a different model family from the author when the host offers one, so it does not share the author's blind spots.

1. Run `ctlhq-models pick planners-and-reviewers --not-family <author-model>` (in Codex, add `--host codex`). The author model is the builder's model, or the parent model for main-agent work. `planners-and-reviewers` is the operator's role for plans and reviews (`skills/ctlhq-setup/SKILL.md` step (d)); the review skills have no role of their own.
2. Spawn the reviewer on the model it prints. In Codex, when the subagent tool takes no model name, run `codex exec -m <model> -c model_reasoning_effort=xhigh` with the brief. Exit 1 means the role's model shares the author's family, and it prints that model. Run on it and write "same family as the author" in the review file.
3. Inside Claude Code every model is Claude family, so the step 1 command exits 1 there with the shipped defaults. A reviewer of a different family has to run from another host, such as Codex. Do that when the operator asks for a different family; otherwise the same-family review stands, labeled as such.
4. If the host rejects the printed model, or the model hits its usage limit, run `ctlhq-models get planners-and-reviewers-limit-fallback` (in Codex, add `--host codex`), run on what it prints, and say so.

## 3. Steps

1. Run the **no-comments** skill on the diff. The main agent fixes its accepted findings.
2. Run the project's gate on the resulting tree and read its exit line.
3. Give the reviewer the inputs in section 1 and the brief below.

## 4. The brief

```
You are reviewing a commit you did not write. Read only the inputs listed.
Answer every question in <absolute path of references/questions.md>.
Run the check lanes yourself from outside the repository and paste the exit lines.
Try the hand step on real data with the throwaway state folder.
Report: 1. verdict (accept / fix first / reject); 2. defects, each with file, line, the
question it fails, and how to reproduce; 3. what you ran, with exit codes; 4. what you did not
check. No defect without a reproduction. "I did not check" is a valid line.
```

## 5. What the main agent does with it

1. Save the report to `.local/reviews/<milestone-or-commit>.md`.
2. Every "fix first" defect goes into the builder's fix list with the reviewer's reproduction. A fix reopens the review for the files it changed.
3. Record the verdict in the commit message under `Test Plan:` as "commit review <verdict>, <n> defects fixed".
4. A commit without a saved review file is not allowed in projects that adopt this skill.
