---
name: prepare-public-repo
description: Make a repository ready to be public. Independent reviewers check personal data, secrets, internal language, license, docs for strangers, tracked files, and code; the main agent combines the best fix per item, moves private content to a private place first, and commits locally. Use before making a repository public, or before its first push to a public remote. It never rewrites history and never pushes; /fresh-history-push does that.
---

# Prepare a public repository

The goal is a current tree that a stranger can read and that holds nothing private.
This skill reviews and fixes that tree. It never touches `.git` history, remotes, or GitHub settings.

## Tool

Paths such as `bin/ctlhq-privacy-scan` are relative to the ctlhq repository (the folder that holds this `skills/` directory). `<project>` and `<worktree>` are folders of the repository being prepared.

`bin/ctlhq-privacy-scan` (a symlink to `skills/prepare-public-repo/bin/ctlhq-privacy-scan`) finds private words in the current files, tracked and untracked, and never prints a word. It skips the owner's own GitHub address and the `LICENSE` file, as `tests/privacy/run.sh` does. It also skips the words in `public_terms` of `ctlhq-first-push`. `--help` defines the word number and every exit code.

```
bin/ctlhq-privacy-scan --root <worktree>            # file:line and word number per hit; the word list is .local/first-commit/private-values.txt
bin/ctlhq-privacy-scan --root <worktree> --joined   # also words split across quotes, "_", "+", ".", or line breaks
```

## Steps

1. **Confirm.** Name the private place, check the preconditions, then restate the ask as a numbered list and wait for the operator's yes.
   1. The private place is a private repository or folder outside the project. Content that leaves the public tree goes there. Ask the operator for it when no project rule names it, before precondition 1 needs it.
   2. Preconditions. Precondition 1 never stops the run. Preconditions 2 and 3 stop it at the first one that fails; say which.
      1. `GIT_OPTIONAL_LOCKS=0 git -C <project> status --short` prints nothing. When it prints lines, name each uncommitted edit and copy it to the private place before any work. Then go on.
      2. `git -C <project> ls-files -ci --exclude-standard` prints nothing, so no tracked file is also ignored.
      3. The word list `<project>/.local/first-commit/private-values.txt` exists, and `git -C <project> check-ignore -q .local/first-commit/private-values.txt` exits 0. `ctlhq-privacy-scan` and `ctlhq-first-push` both read it.
   3. The list names the project and the base commit. It also holds the output of `git -C <project> worktree list`, the worktrees that existed before this run.
   4. It names the gate, which is the exact check command. When the full gate needs something a subagent cannot provide (a screen, a signing key, a network service), name the fast gate the reviewers run instead. Add a search for docs that tools read, and say what stays unproven until the main agent runs the full gate.
   5. It names the license. The operator settles it here, before the docs item links to it.
   6. It lists the checklist items with their split into "change" and "propose", per [the checklist](references/checklist.md).
   7. It names the files nobody may touch.
   8. It names the private place. It also says where the commit rule and the private records live after publishing. One working layout is an ignored `PLAN.md` at the project root, with its master copy in the private place.
   9. It ends with the "not touched" line, which names history, remotes, and repository visibility.
2. **Set up.** Make one Git worktree per reviewer from the base commit, as [the reviewer brief](references/reviewer-brief.md) shows. In each worktree, copy in the ignored files the checks need (at least the word list), and install the dependencies (`npm ci --ignore-scripts`, or the project's equivalent). Save every brief in `<project>/.local/briefs/` before you spawn.
3. **Review.** Start two or three independent reviewers. Each does every item of the checklist in its own worktree and makes real changes for the "change" items. Reviewers never see each other's work. Code correctness may use `/project-audit` at `quick` depth in place of a hand review.
4. **Combine.** Read every reviewer's report and diff. Pick a base reviewer, then list per-file ports from the others, item by item. Copy every piece of content that leaves the public tree, and is not obsolete, to the private place. Then give one builder [the combine brief](references/combine-brief.md) in a fresh worktree from the same base.
5. **Nothing lost.** A read-only agent compares the base commit with the combined worktree and the private place, with [the content-audit brief](references/content-audit-brief.md). It runs after the combine and before the gate. Every line labelled LOST goes back, or the operator decides to drop it.
6. **Gate, review, commit.**
   1. Run the gate with `ctlhq-run-gate -- <check command>` after the last edit. `ctlhq-commit` refuses a gate older than the tree, so rerun it after any change.
   2. Get a fresh review per `/blind-review`. With no `PLAN.md` milestone for this work, the checklist is the "Done when" list.
   3. Commit on the combine branch with `ctlhq-commit --gate gate -- <paths>`. Commit only on the operator's own words, or under the project's written commit rule (for example a `PLAN.md` section 10 row). This commit is the readiness commit.
7. **Banner.** Only when the operator asks for one, make banner options with [the banner brief](references/banner-brief.md) and let the operator pick by number.
8. **Report.** Give the findings summary in the format below. It names the readiness commit hash and asks whether to bring that commit to `main`.
9. **Bring it to `main`.** The operator's yes, in their own words, covers every part of this step. That is the merge, saving each worktree's leftovers, removing the reviewer and combine worktrees, and deleting their branches.
   1. With `main` checked out, run `git -C <project> merge --ff-only <combine branch>`.
   2. Save each reviewer and combine worktree to the private place, as the block below shows. The block keeps its uncommitted diff, the list of its untracked files, and those files.
   3. Remove each reviewer and combine worktree with `git -C <project> worktree remove --force <path>`. `--force` is needed because a reviewer worktree still holds changes. Remove no worktree that is in the list taken at Confirm.
   4. Delete their branches with `git -C <project> branch -D <branch>`.
   5. `git -C <project> rev-parse HEAD` must print the readiness commit, and `git -C <project> worktree list` must show the same worktrees as the list taken at Confirm.
   6. End by suggesting `/fresh-history-push`, which the operator types when they want one fresh commit pushed.

   ```bash
   cd "<worktree>"
   echo "cd exit $?"
   git diff --binary HEAD > "<private place>/<worktree name>.diff"
   echo "diff exit $?"
   git ls-files -o --exclude-standard > "<private place>/<worktree name>-untracked.txt"
   echo "untracked list exit $?"
   git ls-files -o --exclude-standard -z | tar -czf "<private place>/<worktree name>-untracked.tgz" --null -T -
   echo "tar exit $?"
   ```

   Run the block once per worktree, and read each exit code. A nonzero code stops this step; remove nothing for that worktree. `git diff --binary HEAD` keeps staged and unstaged edits in one diff. Git ignores `.local/` and dependency folders, so the block does not save them.

## Rules

1. Never print a private word or a secret. Name the file, line, and kind, or the word number.
2. Removing a file from the public tree is reversible only while a copy exists. Copy it to the private place before the delete.
3. The owner's name may appear in the repository's own address, the copyright line, and the commit author. Accept a word-list hit there. Report one anywhere else.
4. The project's own name may be on the operator's word list. Then every mention of the project is a hit. The fix is a per-repository exception. The project's word list leaves that one word out. Never remove the word from the operator's own list. This is the operator's decision, so ask it as a numbered question.
5. If the permission system refuses a tool for a subagent, that subagent stops the step and reports it. Nobody reruns the step another way.
6. The operator decides each "propose" item. Put each one as its own numbered question with one recommendation.
7. When the operator has given no words yet (a dry run, or a proposal), every brief's approval line says so. Never write approval words the operator did not give.

## Reply

1. A one-sentence verdict that says whether the tree is ready for a fresh-history push.
2. A table with a leading # column and one row per checklist item. Each row says what changed, gives file:line examples, and names what is still open.
3. Where moved content went, and the content audit's LOST count.
4. The gate exit line, the fresh review's verdict, and the readiness commit hash (or why there is none).
5. Open decisions, one numbered question each. The last one asks whether to bring the readiness commit to `main` and remove the review worktrees.
