---
name: prepare-public-repo
description: Make a repository ready to be public. Independent reviewers check personal data, secrets, internal language, license, docs for strangers, tracked files, and code; the main agent combines the best fix per item, moves private content to a private place first, and commits locally. Use before making a repository public, or before its first push to a public remote. It never rewrites history and never pushes; /fresh-history-push does that.
metadata:
  separate-tools: gitleaks
---

# Prepare a public repository

The goal is a current tree that a stranger can read and that holds nothing private.
This skill reviews and fixes that tree. It never touches `.git` history, remotes, or GitHub settings.

## Tools

Paths such as `tests/privacy/run.sh` are relative to the ctlhq repository (the folder that holds this `skills/` directory). `<project>` and `<worktree>` are folders of the repository being prepared.

`tests/privacy/run.sh` finds private words in tracked files and in untracked files Git does not ignore, and never prints a word. It reads first-commit's lists with the reader `ctlhq-first-push` uses, so both check the same words. It skips the owner's own GitHub address and a top-level `LICENSE`, `LICENSE.md`, `LICENSE.txt`, or `COPYING`. `--help` defines every exit code.

```
tests/privacy/run.sh --root <worktree>   # file:line per hit; ignored files are not read
```

`ctlhq-public-files` lists files, by name, that a stranger may not need: planning material, design mocks, measurement files, and tool configs. Each line is a question for the reviewer. A file that stays goes in the allow file with its reason, so the tool can exit 0. `--help` defines every exit code.

```
ctlhq-public-files --root <worktree> --allow <worktree>/.local/public-files-allow.txt   # path: kind per match; ignored files are not listed
```

A project built with ctlhq's method keeps `AGENTS.md`, so its allow file holds this line:

```
AGENTS.md  instructions for contributors who use a coding agent
```

Leave `--allow` out until that file exists; a missing allow file exits 2.

## Steps

1. **Confirm.** Set the defaults below, then show one short plan block and ask one yes-or-no question, whether to go ahead with this plan. The prompt may change any default.
   1. **Private place.** It is `<project>/.local/private/`, unless the prompt names another place. Content that leaves the public tree goes there. Create it when it is missing. Then run `git -C <project> check-ignore -q .local/private/`. Exit 1 means Git does not ignore `.local/`, so the readiness change adds the line `.local/` to `.gitignore`, and the plan block says so. Until that commit reaches `main`, the main folder lists `.local/` as untracked, so stage files only by name.
   2. **Uncommitted edits.** When `GIT_OPTIONAL_LOCKS=0 git -C <project> status --short` prints lines, save them with the block in step 8, run in `<project>` with the name `main-<UTC date>`. A line for `.local/` itself does not count. When Git does not ignore `.local/`, add `-- ':(exclude).local/'` right after the options of both `git ls-files` commands in the block, so the block does not save the private place into itself. Leave the edits as they are. This never stops the run.
   3. **Worktrees.** Record the output of `git -C <project> worktree list`, the worktrees that existed before this run. Step 8 compares against it.
   4. **Stops.** Each of these stops the run when it fails; say which.
      1. `git -C <project> ls-files -ci --exclude-standard` prints nothing, so no tracked file is also ignored.
      2. A private-values list exists. It is first-commit's user list `~/.config/first-commit/private-values.txt`, or `<project>/.local/first-commit/private-values.txt` with `git -C <project> check-ignore -q .local/first-commit/private-values.txt` exiting 0. When step 1.1 found `.local/` not ignored, that check exits 1 until the readiness change ignores the list, so skip it. Test each with `test -e` only. `tests/privacy/run.sh` and `ctlhq-first-push` both read every list that exists, from a worktree too.
   5. **License.** Keep an existing top-level `LICENSE`, `LICENSE.md`, `LICENSE.txt`, or `COPYING`. With none, the default is MIT, with the current year and the holder from the `name` in first-commit's identity file. That file is `$FIRST_COMMIT_IDENTITY_FILE` when set, else `$XDG_CONFIG_HOME/first-commit/identity.json`, else `~/.config/first-commit/identity.json`. Never print the name. When the file or the name is missing, the license becomes a "propose" item.
   6. **Plan block.** It holds these numbered lines, every one stated as a default:
      1. The project and the base commit.
      2. The scope, which is the checklist items with their split into "change" and "propose", per [the checklist](references/checklist.md). Each project issue with no safe default is one more "propose" item with its recommendation. Two examples are a project rule that conflicts with being public, and vendored code whose license is unclear.
      3. The number of reviewers, each in its own worktree from the base commit.
      4. The gate, which is the exact check command. When the full gate needs something a subagent cannot provide (a screen, a signing key, a network service), name the fast gate the reviewers run instead. Add a search for docs that tools read, and say what stays unproven until the main agent runs the full gate.
      5. Where moved files go, which is the private place, and whether the readiness change adds `.local/` to `.gitignore`. Where the commit rule and the private records live after publishing. One working layout is an ignored `PLAN.md` at the project root, with its master copy in the private place. The saved uncommitted edits, if any.
      6. The license, which is the kept file or the new MIT license with its year and the identity file as the holder's source.
      7. The protected files that nobody may touch. The default is "none".
      8. The project's former names (old project, package, command, or repository names), which reviewers search for under checklist item 2.3. The default is "none".
      9. What follows the yes with no further question when the operator ran this skill, except the "propose" items of rule 5 (step 6.3 says when the model started it). That is the readiness commit, the fast-forward of `main`, saving and removing the reviewer and combine worktrees, and deleting their branches. Never a push.
      10. The "not touched" line, which names history, remotes, repository visibility, and GitHub settings.
2. **Set up.** Make one Git worktree per reviewer from the base commit, as [the reviewer brief](references/reviewer-brief.md) shows. When step 1.1 found `.local/` not ignored, add the line `.local/` to `.gitignore` in each reviewer worktree right after you make it, so the base reviewer's diff carries it into the combine. Copy in any ignored file the checks need, other than a private-value list. Then install the dependencies (`npm ci --ignore-scripts`, or the project's equivalent). Save every brief in `<project>/.local/briefs/` before you spawn.
3. **Review.** Start two or three independent reviewers. Each does every item of the checklist in its own worktree and makes real changes for the "change" items. Reviewers never see each other's work. Code correctness may use `/project-audit` at `quick` depth in place of a hand review.
4. **Combine.** Read every reviewer's report and diff. Pick a base reviewer, then list per-file ports from the others, item by item. Copy every piece of content that leaves the public tree, and is not obsolete, to the private place. Then give one builder [the combine brief](references/combine-brief.md) in a fresh worktree from the same base.
5. **Nothing lost.** A read-only agent compares the base commit with the combined worktree and the private place, with [the content-audit brief](references/content-audit-brief.md). It runs after the combine and before the gate. Every line labelled LOST goes back, or the operator decides to drop it.
6. **Gate, review, commit.**
   1. Run the gate with `<repo-root>/bin/ctlhq-run-gate -C <combine-worktree> -- <check command>` after the last edit. [The commit sequence](../run-method/references/subagent-templates.md) says what `<repo-root>` is. `ctlhq-commit` refuses a gate older than the tree, so rerun it after any change.
   2. Get a fresh review per `/commit-review`. With no `PLAN.md` milestone for this work, the checklist is the "Done when" list.
   3. Commit on the combine branch with `<repo-root>/bin/ctlhq-commit -C <combine-worktree> --gate gate --paths-file .local/paths.txt`. This commit is the readiness commit. When the operator ran this skill (typed `/prepare-public-repo`, or asked for it by name in their own words), the Confirm yes approves this commit and all of step 8. When the model started the skill by itself, commit only on the operator's own words, or under the project's written commit rule (for example a `PLAN.md` section 10 row).
7. **Banner.** Only when the operator asks for one, make banner options with [the banner brief](references/banner-brief.md) and let the operator pick by number.
8. **Bring it to `main`.** The Confirm yes covers every part of this step. That is the merge, saving each worktree's leftovers, removing the reviewer and combine worktrees, and deleting their branches.
   1. With `main` checked out, run `git -C <project> merge --ff-only <combine branch>`.
   2. Save each reviewer and combine worktree to the private place, as the block below shows. The block keeps its uncommitted diff, the list of its untracked files, and those files.

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

   3. Remove each reviewer and combine worktree with `git -C <project> worktree remove --force <path>`. `--force` is needed because a reviewer worktree still holds changes. Remove no worktree that is in the list taken at Confirm.
   4. Delete their branches with `git -C <project> branch -D <branch>`.
   5. `git -C <project> rev-parse HEAD` must print the readiness commit, and `git -C <project> worktree list` must show the same worktrees as the list taken at Confirm.
   6. The merge deleted from `<project>` each root record that the readiness commit stopped tracking, such as `PLAN.md`. Copy each one back from the private place.
   7. In `<project>`, run the precondition block in section 0 of `/fresh-history-push`'s [verification commands](../fresh-history-push/references/verify.md). Its gate line is the main-folder run of `ctlhq-run-gate`. When plan block line 8 names former names, also run `ctlhq-rename-check <former names>` in `<project>`. A place where an old name must stay goes in an allow file the operator approves (`--allow`). The tree is ready only when every line prints exit 0 and `ctlhq-rename-check` exits 0. Otherwise list the failing lines.
   8. End by suggesting `/fresh-history-push`, which the operator types when they want one fresh commit pushed. That skill still waits for the operator's own words before it pushes.
9. **Report.** Give the findings summary in the format below.

## Rules

1. Never print a private word or a secret. Name the file, line, and kind.
2. Removing a file from the public tree is reversible only while a copy exists. Copy it to the private place before the delete.
3. The owner's name may appear in the repository's own GitHub address and the copyright line of the license file that step 1.5 keeps or writes. `tests/privacy/run.sh` skips both, and `ctlhq-first-push` accepts them through `.repo-policy.json`. The readiness change creates that file when it is missing, as `{"schema_version": 1}`. It writes `"public_github_owner_urls": true` and one `private_literal_exceptions` entry for the copyright line, shaped as `{"path": "<license file>", "line": <line>, "sha256": "<hash>", "reason": "copyright holder"}`. The hash is the first field of `sed -n '<line>p' <license file> | tr -d '\n' | shasum -a 256`. Report every other hit.
4. If the permission system refuses a tool for a subagent, that subagent stops the step and reports it. Nobody reruns the step another way.
5. The operator decides each "propose" item, each as its own numbered question with one recommendation. A "propose" item whose answer changes the readiness commit is asked after the combine and before step 6.1, and the commit waits for the answer. Every other "propose" item is an open decision in the Reply.
6. When the operator has given no words yet (a dry run, or a proposal), every brief's approval line says so. Never write approval words the operator did not give.

## Reply

1. A one-sentence verdict that says whether the tree is ready for a fresh-history push. It says "ready" only when every line of the precondition block in step 8.7 printed exit 0, and `ctlhq-rename-check <former names>` exited 0 when plan block line 8 named any. Otherwise it lists the failing lines.
2. A table with a leading # column and one row per checklist item. Each row says what changed, gives file:line examples, and names what is still open.
3. Where moved content went, and the content audit's LOST count.
4. The gate exit line, the fresh review's verdict, and "`main` is at <readiness commit hash>" (or why there is none).
5. Open decisions, one numbered question each.
