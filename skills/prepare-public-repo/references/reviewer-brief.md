# Reviewer brief template

Copy this into `<project>/.local/briefs/public-review.md`, fill every `<placeholder>`, and give each reviewer the same file with its own worktree path in the prompt.

Set up each reviewer's worktree before you spawn it:

```bash
git -C <project> worktree add <scratch>/review-a -b public-review-a <base commit>
mkdir -p <scratch>/review-a/.local/first-commit
cp <project>/.local/first-commit/private-values.txt <scratch>/review-a/.local/first-commit/
git -C <scratch>/review-a check-ignore -q .local/first-commit/private-values.txt
cd <scratch>/review-a && npm ci --ignore-scripts
```

1. The `cp` line brings in the word list, which Git ignores, so a new worktree lacks it. Copy any other ignored file the checks need the same way.
2. `check-ignore -q` must exit 0, so nobody can commit the copied list.
3. The last line installs dependencies without running their install scripts. Use the project's own install command when it has no `package-lock.json`.

```markdown
# Brief: public-readiness review and cleanup of <project>

You are one of <2 or 3> independent reviewers. The others do the same task in separate copies; you will not see their work. The main agent compares all results and combines the best change per item. Make real changes in your copy for the "change" items, and write proposals for the "propose" items.

Operator approval: <date>, "<the operator's words>" for the items below. <In a dry run or a proposal, write instead: "None yet. This is a dry run; the operator has approved nothing.">
The operator will later replace the history with one fresh commit, so only the current files matter.

Protected files (never change): <paths, or "none">.

## Your copy

Work only in your worktree (named in your prompt), on its branch, at <base commit>. Do not commit, push, merge, stage, run `git init`, change git config, or touch <the main folder>, <the private place>, or the real home folder's settings. Write scratch files only under your worktree's `.local/` (ignored) or <scratch folder>.

If the permission system refuses a delete, stop that step and report it. Do not move files aside instead. If it refuses any other tool, stop that step and report it. Never rerun the step another way.

Read first: <README, CONTRIBUTING, SECURITY, AGENTS.md, .gitignore, the build and check files>.

## Checklist

Do every item of <path to this skill>/references/checklist.md.

## Change these

1. <item, with the operator's own number>
2. <item>

## Propose these (no change in your copy; a table in your report)

1. <item>

## Checks before you report (read each exit code directly)

1. <the gate named in Confirm>: exit 0, or name each failing row and why. <When this is the fast gate: also list each doc that a tool or test reads, found by searching the code for doc file names, and say what stays unproven.>
2. `ctlhq-privacy-scan --root <your worktree>` and `--joined`: exit 0, or each hit with its file:line, word number, and your judgment. Never print a word.
3. The copy of the listed files, as the checklist shows: `rsync` and the count check exit 0. Then `gitleaks dir` on that copy: exit 0, or each finding with its kind.
4. `git diff --quiet -- <protected paths>`: exit 0.
5. `git status --short` and `git diff --stat`, including deletions and new files.

## Report

1. Per item: what you changed or propose, with file:line examples and reasons.
2. For the docs item, a table: # | file | keep, merge, or delete | reason | where its content goes.
3. Every piece of content that leaves the public tree and is not obsolete, so the main agent can move it to the private place.
4. Questions as numbered items, each with your recommendation.
5. Plain English, short sentences, no long dashes, every table with a leading # column. Never print a private value; name the file, line, and kind, or the word number.
```
