# Combine brief template

The main agent reads every reviewer's report and diff first. It picks one reviewer's change as the base, then lists each port from the other reviewers file by file.
One builder applies the picks in a fresh worktree from the same base, set up like a reviewer's (word list copied in, dependencies installed).
Large renames go in a second phase on top of the first, so the gate checks each phase alone.
Before the builder deletes anything, the main agent has copied every piece of content that leaves the public tree, and is not obsolete, to the private place.

```markdown
# Brief: combine the <n> reviews of <project>, phase <n>

You are a builder. Work only in the worktree <path> (branch <branch>, at <base commit>, clean). Do not commit, stage, push, merge, run `git init`, change git config, or touch <the main folder>, <the private place>, or the real home folder's settings. Never touch <protected paths>.

If the permission system refuses a delete, stop that step and report it. Do not move files aside instead. If it refuses any other tool, stop that step and report it. Never rerun the step another way.

Inputs:
1. Reviewer worktrees, all at <base commit>, each with uncommitted changes: A <path>, B <path>, C <path>.
2. The review brief: <path>.
3. The operator's decisions: <path>. <In a dry run: "None yet. This is a dry run; the operator has approved nothing.">

## Picks

1. **Base: reviewer <X>'s change.** Apply `git -C <X> diff --binary` with `git apply` (no `--index`). Add <X>'s untracked files. Confirm your tree equals <X>'s with `diff -r`, leaving out `.git`, `.local`, and dependency folders.
2. **Keep from <X>:** <the changes that stay as they are>.
3. **Ports, one row per file:** read the other reviewer's diff for that file, and merge by hand where <X> also changed it.
   | # | File | From | What to port |
   | --- | --- | --- | --- |
   | 1 | <file> | <Y> | <change> |
4. **Decisions to apply:**
   1. <decision, with the operator's words or the decisions file row>
5. **Not in this phase:** <items left for a later phase>.

## Checks (read each exit code directly; start the gate after your last edit)

1. <the gate named in Confirm>: exit 0, all rows. Name any failing row.
2. `ctlhq-privacy-scan --root <your worktree>` and `--joined`: exit 0, or each hit with its file:line, word number, and your judgment. Never print a word.
3. The copy of the listed files, as the checklist shows: `rsync` and the count check exit 0. Then `gitleaks dir` on that copy: exit 0.
4. `git diff --quiet -- <protected paths>`: exit 0.
5. `git status --short`, `git diff --stat`, and the untracked files.

## Report

Per pick: what you did, what you merged from where, and each conflict you resolved. Then the checks with their exit codes. Plain English, short sentences, no long dashes.
```
