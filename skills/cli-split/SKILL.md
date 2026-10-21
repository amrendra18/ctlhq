---
name: cli-split
description: "Review how one skill or workflow is written and decide which steps become a command. Lists each step, classes it deterministic, mixed, or judgment, names the command that owns each deterministic step (existing or proposed with inputs, outputs, and exit codes), finds text that does by hand what a tool already does, and checks tools for judgment hidden inside. Ends in a numbered proposal table. Use when a skill changed since the last run, or when the operator asks which steps should be scripts."
disable-model-invocation: true
---

# CLI split

A step a script can do the same way every run belongs in a command. A step that needs interpretation, design, taste, or priority stays as prose. This skill reviews one skill, playbook, agent file, or workflow on that split and ends in a list of commands to build and text to fix. It builds nothing. The rule: a skill names a command for every step a script can do the same way every run. That command answers `--help` with `name: one line`, exits 0, 1 or 2 by contract, and lives under `skills/<name>/bin/` with a symlink in `bin/`; `ctlhq-check` gates the contract. Judgment stays prose and says what the agent decides, not how to compute the inputs.

## Tool

`bin/ctlhq-cli-split` (a symlink to `skills/cli-split/bin/ctlhq-cli-split`) does the listing. It is read-only and never classifies. `ctlhq-cli-split --help` lists the exit codes: 0 when rows are printed, 1 when nothing is found, 2 on a usage error or an unknown skill.

```
bin/ctlhq-cli-split steps <skill|file|folder>              # one row per step: line, kind, section, commands it names, text
bin/ctlhq-cli-split steps <skill> --no-command             # only the steps that name no command
bin/ctlhq-cli-split changed --since <YYYY-MM-DD|FILE>      # skills with a file modified after the date or the file's time
```

`--json` prints the same rows as JSON. Every table has a leading `#` column. `bin/ctlhq-skills show <name>` lists the tools a skill ships, and `--help` on each tool gives its contract.

## Definitions

1. Deterministic (D): a script could do it the same way every run, with no reading comprehension. Examples: list or find files, parse frontmatter or a diff, count, search for a pattern, fill a template, format a table, stamp a time, resolve a path, run a pass-or-fail check, read or write a config value, drive git or gh, validate a shape.
2. Judgment (J): it needs interpretation, design, taste, or prioritization. Examples: decide what the user meant, choose an approach, write prose for a human, pick which finding matters, review code for correctness.
3. Mixed (M): a deterministic core inside a judgment wrapper, such as "find every caller of X and decide which need the change". The core is a command candidate; the decision stays prose.

## Steps

1. Set the scope. Name the skill, playbook, agent file, or workflow. When garden or the operator asks for every skill changed since the last run, run `bin/ctlhq-cli-split changed --since <last proposal file>` and take one skill per row.
2. List the steps. Run `bin/ctlhq-cli-split steps <skill>` and keep its row numbers. Read the file once end to end as well; a row is a candidate, and a paragraph can hold two steps.
3. Class each row D, M, or J under the definitions. Ignore rows that only explain (background, examples); mark them J with "background".
4. For each D row and each M core, name the owner. When the row already names a command, check that the command does what the sentence says (`<tool> --help`). When none does, propose one: name, inputs, outputs, exit codes 0, 1, 2, in one or two sentences. Prefer a new subcommand on an existing tool when the inputs match. A proposal without inputs, outputs, and exit codes is not a proposal.
5. Find text that does a tool's work by hand: a sentence that describes how to compute something a listed tool already prints (reading `~/.ctlhq/models.toml` instead of `ctlhq-models get`, "through the unslop skill" instead of `bin/ctlhq-unslop <file>`). Each one is a documentation fix: quote the line and name the command.
6. Check each tool the skill ships for the inverse error: a judgment call inside code (a hard failure on something a person should weigh, a verdict where a candidate list belongs). Say whether the `## Tool` section describes the tool accurately, one line each.
7. Rate the value of each proposal honestly. High: the step repeats across skills or goes wrong by hand. Medium: it repeats inside one skill. Low: a one-line step an agent gets right in seconds, even if it is deterministic.
8. Write the proposal file to `.local/review/cli-split-<skill>-<YYYY-MM-DD>.md`. Its modification time is the "last run" that step 1 reads next time.
9. Reply contract: the numbered proposal table, then the counts (D, M, J rows, already covered, documentation fixes, proposals by value), then the top three proposals with one sentence each on why. End with "Next step: operator picks the rows to build by number."

## Proposal table

| # | column | content |
|---|---|---|
| 1 | `#` | row number, cited in replies |
| 2 | `file:line` | from `ctlhq-cli-split steps` |
| 3 | step | the step, at most 15 words quoted |
| 4 | class | D, M, or J |
| 5 | owner | the existing command, or "proposed: <name>" |
| 6 | contract | inputs, outputs, exit codes for a proposal; "fix text" for a documentation fix |
| 7 | value | high, medium, or low, with the reason |

## Not part of this skill

Building the commands, editing the skill under review, and repository cleanup. Cleanup is the **garden** skill's job.
