---
name: fresh-history-push
description: Replace a repository's whole Git history with one signed commit of the current tree, push it to a GitHub remote, and scan a fresh clone of what the remote holds. By default the remote must be private, and the skill stops when anyone can read it; a public remote needs the operator's own words. Use after /prepare-public-repo, when the operator wants a repository published without its old history. It never changes repository visibility or GitHub settings; the operator does that after the scan.
disable-model-invocation: true
---

# Fresh-history push

The new history is one commit whose files are exactly the current tree.
Deleting `.git` cannot be undone without the backup, so the backup comes first and the operator runs the delete.

## Steps

1. **Preconditions.** Stop at the first one that fails, and say which.
   1. The `/prepare-public-repo` report, or the operator in their own words, names the readiness commit. `git rev-parse HEAD` prints that same hash. Otherwise stop.
   2. `git status --porcelain` prints nothing, so the tree is clean. `git worktree list` shows one worktree.
   3. `git ls-files -ci --exclude-standard` prints nothing, so no tracked file is also ignored. After the reset, `git add -A` would leave such a file out.
   4. `git submodule status` prints nothing. A submodule's history lives inside `.git`, which the reset deletes.
   5. The gate is green on this tree. Run `ctlhq-run-gate -- <check command>` now and read its exit line.
   6. `.git/info/exclude` holds no active pattern. Each one moves into `.gitignore` first.
   7. The word list `.local/first-commit/private-values.txt` exists, and `git check-ignore -q .local/first-commit/private-values.txt` exits 0. `ctlhq-first-push` needs it in step 4.
   8. The operator has created the empty GitHub repository (no README, license, or `.gitignore`) and named its owner and name.
   9. The remote is private, per [the verification commands](references/verify.md) section 1. When anyone can read it, stop and ask, unless the operator chose a public remote in their own words. A private remote lets the scan run before anyone can see the commit.
   10. `git rev-parse 'HEAD^{tree}'` prints the old tree ID. Record it for the reset block and step 4.
2. **Back up `.git`.** Write a named archive outside the repository. Then extract it to scratch and check its tree ID, as in [the verification commands](references/verify.md) section 2.
3. **Reset.** Write the commit message from [the message template](references/commit-message.md) to a file outside the repository. Ask the operator about the block's two optional lines (time zone, commit hooks). Then give the operator [the reset block](references/reset-block.md), filled in, ready to paste. Agents are usually blocked from removing `.git`, `git init`, and `git config`, so the operator runs it.
4. **Verify.** Run every check in [the verification commands](references/verify.md) section 3. They prove one commit, the same tree ID as before, the intended author and email, a good signature, and `ctlhq-first-push` exit 0. The last check reruns the gate on the new commit.
5. **Push.** The reset block added the remote, with an HTTPS fetch address and an SSH push address. Rerun the private-remote check, then push with `ctlhq-push -u origin main`, as in [the verification commands](references/verify.md) section 4. Tag and push the tag only when the project releases by tag.
6. **Scan.** A fresh read-only agent clones what the remote holds and scans it, with [the scan brief](references/scan-brief.md).
7. **Hand over.** Stop. The operator switches visibility and, once the repository is public, turns on private vulnerability reporting in its security settings. Private vulnerability reporting exists only for public repositories.

Read [the notes](references/notes.md) before step 3. They cover commit time zones, the SSH agent after a restart, long pre-push hooks, commit hooks, and tests that read `HEAD`.

## Rules

1. Never push before step 4 passes in full.
2. Never push to a remote that anyone can read, unless the operator chose a public remote in their own words.
3. Never print a private word or a secret. Name the file, line, and kind.
4. On any failure after the reset, stop and report. The backup restores the old `.git` ([the verification commands](references/verify.md) section 5); the operator decides whether to restore.

## Reply

1. The new commit hash, its tree ID next to the old one, and the signature line.
2. The private-remote check's result, the gate exit line on the new commit, and the push line from `ctlhq-push`.
3. The scan's verdict and its table.
4. The backup archive's path.
5. The next step for the operator, which is to switch visibility and then turn on private vulnerability reporting.
