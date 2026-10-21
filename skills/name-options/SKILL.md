---
name: name-options
description: "Choose a name for a project, command, skill, or file. Give N candidates one line each, check each for collisions with ctlhq-name-check, recommend one, and let the operator pick by number. Includes the rename checklist. Use when something new needs a name or an old name needs to change."
disable-model-invocation: true
---

# Name options

A name is hard to change once other files, remotes, and habits use it. Give the operator a short list they can pick from by number, with collisions already checked.

## Tool

`bin/ctlhq-name-check` (a symlink to `skills/name-options/bin/ctlhq-name-check`) runs the collision check. `ctlhq-name-check --help` lists every option and exit code.

```
bin/ctlhq-name-check <name> [<name> ...]             # command -v, ~/projects folders, ctlhq skills and tools
bin/ctlhq-name-check --registry <name> [<name> ...]  # also npm and PyPI
```

Exit 0 every name is free, 1 any name collides, 2 usage, 3 a registry could not be reached (the check is incomplete).

## Steps

1. Restate in one line what is being named and who will type or read the name. Ask only when this changes the candidates.
2. Write 5 to 8 candidates (default 6). Each is short, lower case, easy to say and type, and says what the thing does. Mix plain names and one or two memorable ones.
3. Run `bin/ctlhq-name-check <every candidate>`. Add `--registry` when the thing may become a package. Drop or mark every row whose verdict is collides. On exit 3, say which registry was not checked.
4. Present a numbered table, one line per candidate: `#`, name, what it suggests in a few words, collisions (from step 3). Then one recommendation with the reason in one sentence.
5. Ask the operator to pick by number, or to say none. Never pick for them when the name is visible to others (a repository, a command, a skill).
6. When the pick renames something that exists, follow the rename checklist below and report each row as done or not done.

## Rename checklist

| # | item | how |
|---|---|---|
| 1 | folder | rename the folder; update any absolute paths in scripts and settings |
| 2 | remote | rename the hosted repository and run `git remote set-url origin <new url>`, after the operator approves |
| 3 | docs | README, PLAN.md, AGENTS.md, catalogs, help text, and the package manifest name |
| 4 | old name | `rg -i '<old name>'` across the repository and the operator's setup files; every hit fixed or listed with a reason |
| 5 | links | symlinks, installed skills, and shell aliases that point at the old path |

Reply contract: the table, the recommendation, and the question "Which number?". After a rename: the checklist rows and the `rg` count for the old name.
