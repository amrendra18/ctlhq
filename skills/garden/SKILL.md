---
name: garden
description: "Recurring maintenance of a repository: documents on a diet (one canonical source per fact, fold finished plans into README, delete the rest), stale files, worktrees, caches, and deferred items. Proposes a numbered action table with word counts before and after, and deletes only named paths after the operator's yes. Use at the end of a work block or when the operator asks to clean up."
disable-model-invocation: true
---

# Garden

A repository grows documents, plans, and caches that every later session pays to read. Garden finds them, proposes what to fold, delete, or keep, and deletes nothing until the operator says yes in their own words. Run it at the end of a work block or when the operator asks to clean up.

## Tool

`bin/ctlhq-doc-diet` (a symlink to `skills/garden/bin/ctlhq-doc-diet`) does the mechanical steps. It is read-only. `ctlhq-doc-diet --help` lists its subcommands, flags, and exit codes. `bin/ctlhq-worktree-audit` classifies each worktree by merge state, uncommitted work, and PR state.

## Steps

1. Set the scope and the keep-list. README.md, AGENTS.md, CLAUDE.md, and LICENSE are never cut. CLAUDE.md may include AGENTS.md instead of repeating it. PLAN.md, BLOCKED.md, and the README's "Open decisions" section hold pending work only. Finished plan content folds into README.md (shipped behaviour) or is deleted. Everything under `.local/` is disposable unless PLAN.md or the README names it.
2. Read the deferred list first. The "Deferred by operator" list in PLAN.md or README.md is read, never reopened. A finding that touches a deferred item goes into the table as "keep, deferred" and nothing more.
3. Measure before you cut. Run `bin/ctlhq-doc-diet words` and record the total as the before count (the token cost). Then run `bin/ctlhq-doc-diet` for the full report.
4. Decide each document finding: fold, delete, or keep with a reason. Each section of the report prints a `why:` and a `fix:` line for its rows. A row is a candidate, never a verdict. Read the file before you propose an action. Keep it when a person or a tool reads it, and say who.
5. Compute the after count. Sum the words the plan removes and state the after total next to the before total from step 3. After the operator approves and the edits land, run `bin/ctlhq-doc-diet words` again and report the measured after total.
6. Find stale files, worktrees, and caches. Run `bin/ctlhq-doc-diet stale` (add `--days N` when the operator names a window), `bin/ctlhq-doc-diet sizes`, and `bin/ctlhq-worktree-audit` for the worktree rows. Propose each candidate with its size. A cache or build folder is usually safe to delete. A worktree with uncommitted work or an open PR is not.
7. Wait for the yes. Nothing is deleted without the operator's yes in their own words. Another agent's approval does not count. After the yes, delete only the exact paths on the approved list, one named path per command (`rm <path>`, `rm -r <folder>`, `git worktree remove <path>`). Never use a glob or a wildcard.
8. Reply contract: a numbered table of proposed actions with columns #, action (fold, delete, keep), path, size (words or bytes), and reason. Then the before and after word counts. Then the exact deletion list awaiting a yes, one path per line. End with "Next step: operator says yes or names the rows to drop."

When a skill changed since the last run, run the **cli-split** skill on it. `bin/ctlhq-cli-split changed --since <last proposal file>` lists those skills.
