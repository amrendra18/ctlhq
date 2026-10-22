# Commit message template

The fresh commit is the first thing a stranger reads in the history. Write it about the project, in neutral words.
It holds no operator notes, approvals, private names, review history, or dates of private work.

```text
<project>: first public version

Why:
- <one or two sentences: the problem the project solves, for whom>

Changes:
- <the main parts of the project, one line each>
- <commands or tools it ships>

Test Plan:
- <the gate command>: exit 0, <rows or counts>.
- <other checks run on this tree, with their exit codes>

Risks:
- <platform limits, stability, for example "First public version; macOS only for now.">

Co-Authored-By: <model name> <noreply address>
```

Rules:

1. The subject line is under 72 characters.
2. The Test Plan quotes exit codes measured on this tree in the precondition step.
3. The co-author line follows the project's own commit rule. Leave it out when the project has none.
4. Save it outside the repository, for example `<scratch>/fresh-commit-message.txt`, so `git add -A` cannot pick it up.
