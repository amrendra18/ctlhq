# Content-audit brief template

The audit proves that nothing the operator relies on was lost between the old tree and the new one.
It runs after the combine, once the moved content is in the private place, and before the gate and the commit.
A file with many missing lines, such as a rewritten README, may need a second audit round of its own.

```markdown
# Brief: content audit, nothing lost from <old> to <new>

You are a read-only judge. Read-only on every repository and on the real home folder. Write only <report path> and scratch under <scratch folder>. Do not spawn subagents.

Old tree: <project> at <old commit>. Export it with `mkdir -p <scratch>/old` and then `git -C <project> archive <old commit> | tar -x -C <scratch>/old`; read tar's exit code.
New tree: the combine worktree <worktree> as it is on disk. Copy it to <scratch>/new so you work on a fixed copy.
Private place: <private repository or folder> at its current state.
Decisions: <decisions file or plan path>.

## Build the lever first

Write a script in the scratch folder, and keep it with the report:
1. Pair every old file with its new place: the same path; the path after a rename (<old name> to <new name>); moved to the private place; or deleted by a decision (cite it).
2. For each pair, list every old line that is not in the new file, after normalising renames and whitespace.

## Judge every listed line

Label each one:
1. reworded: the same rule or behaviour is in the new file in other words (cite the new file:line);
2. moved: it is elsewhere in the new tree or in the private place, and current there (cite file:line). Current means the moved copy matches the old tree's latest text, not an older draft;
3. removed by decision: cite the decision or the review item;
4. LOST: a rule, step, check, option, or behaviour that is gone with no decision.

A removed test case is LOST unless the behaviour it tested was removed by decision.

## Rules

1. Never copy a word from <private word list> into the report. Write "private word N" instead, where N is the word number as `ctlhq-privacy-scan --help` explains it. Before you finish, `sed 's/^[[:space:]]*//; s/[[:space:]]*$//' <private word list> | grep -v -e '^#' -e '^$' | grep -ciFf - <report path>` must print 0. The `sed` part removes the spaces around each private word, as `ctlhq-privacy-scan` does. It prints only a count, never a word.
2. Plain English, short sentences, no long dashes.

## Report

1. A table with a leading # column: folder or file, lines judged, reworded, moved, removed by decision, LOST.
2. Every LOST line: old file:line, what it held in plain words, why it matters, and where it should go back (public tree or private place).
3. A sample of 20 reworded lines, old and new, for a spot check.
4. Recheck 5 of your own labels against the files, and say which.
```
