---
name: plan-review
description: Review a plan, PRD, or design draft with a fresh agent before anything is built. Use when a PLAN.md or design is ready and no code is written yet. The reviewer reads and reports; it changes no files.
---

# Plan review

The reviewer is set up per the **commit-review** skill. Its section 1 says what a reviewer never receives, and its section 2 picks the model.

## 1. What the reviewer receives

1. The plan file.
2. The operator's ask, in their own words or as the numbered restatement they said yes to.
3. `AGENTS.md` and the rules files the plan cites.
4. The repository path, read-only, to check that the files, commands, and targets the plan names exist.

It never receives the author's reasoning, the rejected alternatives, or the chat that produced the plan.

## 2. The brief

```
You are reviewing a plan you did not write. Nothing is built yet. Read only the inputs listed.
Change no files.
Question 1: which part of the operator's ask does the plan drop, and what does it add that
nobody asked for?
Question 2: which "Done when" line has no measured number? Cite the line.
Question 3: which bar is an estimate instead of a measurement on real data?
Question 4: which step depends on something the plan has not proved exists (the real target,
a permission, a tool, a file)? Does milestone 0 prove it?
Question 5: what is the smallest change to the plan that removes the largest risk?
Then answer questions 2 to 6, 8, and 9 in <absolute path of ../commit-review/references/questions.md>
for what the plan will build.
Report: 1. verdict (build / revise first / rethink); 2. findings, each with the plan line, the
problem, and the fix; 3. what you checked in the repository, with the commands; 4. what you
did not check. "I did not check" is a valid line.
```

## 3. What the main agent does with it

1. Save the report to `.local/reviews/plan-<name>.md`.
2. Show the operator the findings beside the plan and discuss them before building. The operator decides each "revise first" finding.
3. Record the verdict and the operator's decisions in `PLAN.md`.
4. No build starts on a "rethink" verdict.
