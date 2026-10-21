# <repository folder name> goal

<One or two short paragraphs. State the goal in the operator's words, the repository path, and what a user can do when the goal is complete. Say what this goal does not change.>

## Completion rule

<This goal is complete only when all <N> boxes below are checked and each box names its evidence. A demonstrated failure means the requirement was not met. Missing evidence keeps a box open. Name the document that owns the exact requirements, if one exists.>

## Current result

<The state when this brief was written: the last commit hash, its date and subject, whether the working tree was clean, and what already exists that the goal builds on. Write "No work toward this goal has started." when that is true. Mark each fact you could not check as "not checked".>

## Next work

1. <First step, ordered by dependency. One action per step.>
2. <Next step.>

## Checklist

- [ ] REQ-01: <One requirement a user can see, written so that a check can prove it.>
- [ ] TEST-01: <One automated or scripted check that proves one or more REQ items.>
- [ ] DONE-01: <A finish condition, such as: every checked box names its evidence.>

## Evidence and remaining boundaries

<Where the run saves its evidence. What is out of scope. What needs the operator's approval first, such as network use, installs, pushes or administrator dialogs. Limits that stay open after the goal is complete.>

## Pre-flight audit

<First line exactly "Ready for an unattended run: yes." or "Ready for an unattended run: no. Missing: <row numbers>." Then one sentence on what the operator must wire before the run starts.>

### External systems

| # | System | What the run needs from it | Mapped to |
| --- | --- | --- | --- |
| E1 | <A system outside the repository> | <What the run does with it> | <`command`, skill: name, or missing: what would wire it> |

### Context sources

| # | Source | What the agent learns from it | Mapped to |
| --- | --- | --- | --- |
| C1 | <A file, folder or note store> | <What the agent must know from it> | <`command`, skill: name, or missing: what would wire it> |

### Exit checks

| # | Check | Checklist items it proves | Mapped to |
| --- | --- | --- | --- |
| X1 | <What is checked> | <REQ-01, TEST-01> | <`command`, skill: name, or missing: what would wire it> |
