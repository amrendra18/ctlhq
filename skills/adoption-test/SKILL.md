---
name: adoption-test
description: "Find out whether a finished project is usable. Play a newcomer on a fresh checkout, follow the README literally, log every friction with file and line, and declare the tier (milestones complete, usable, integrated). Use before you call a project done or hand it to someone else."
disable-model-invocation: true
---

# Adoption test

"Finished" means a newcomer can use it. You play the newcomer. You read only what a newcomer reads, you run only what the README says, and you fix nothing in this run. The result is a tier and a fix list for the owner.

## Tool

`bin/ctlhq-adoption-test` (a symlink to `skills/adoption-test/bin/ctlhq-adoption-test`) does the mechanical steps. `ctlhq-adoption-test --help` lists the exit codes.

```
bin/ctlhq-adoption-test checkout <repo> <dest>       # fresh copy: git clone --local, or a plain copy when <repo> is not a repository; refuses a non-empty <dest>; prints the path
bin/ctlhq-adoption-test commands <README.md>         # the documented commands in README order: n, README line, command
bin/ctlhq-adoption-test log <friction.tsv> <file> <line> <severity> <what happened...>   # one row with a UTC timestamp; header on first use; severity blocker, confusing, or cosmetic
bin/ctlhq-adoption-test tier <friction.tsv>          # counts by severity and the tier; exit 0 integrated, 1 usable, 2 milestones complete, 3 usage
bin/ctlhq-adoption-test tier --list <friction.tsv>   # the same, then every row ordered by severity, blocker first (the fix list)
```

`commands` keeps every line of a fenced block tagged sh, bash, zsh, or shell. In console, text, or untagged blocks it keeps only lines that start with `$` or with a known command. `log` refuses any other severity and writes nothing. `tier` reads an empty log as integrated and a missing log as a usage error (exit 3).

## Steps

1. Make the fresh checkout in a scratch folder with `bin/ctlhq-adoption-test checkout <repo> <scratch>/checkout`. Never test in the working tree. It holds uncommitted files and caches a newcomer does not have. Record the commit with `git -C <scratch>/checkout rev-parse --short HEAD`. Keep the log outside the checkout, at `<scratch>/friction.tsv`.
2. Read what a newcomer reads. README first, then only the files README points at, in the order README names them. Do not open the code, the plan, or the tests unless README sends you there. A fact you know from the working tree does not count.
3. List the journey with `bin/ctlhq-adoption-test commands <scratch>/checkout/README.md`. The output numbers every documented command with its README line. Walk the commands in that order, from the folder the README implies, even when you know a better order.
4. Run each command as written. Do not fix anything on the way, and do not swap in a command you know works. Each time the text is wrong, missing, or ambiguous, or a command fails, log one row with `bin/ctlhq-adoption-test log <scratch>/friction.tsv README.md <line> <severity> <what happened>`. Severity: blocker (the journey cannot continue without an undocumented step), confusing (it continues after a guess or a second read), cosmetic (a typo or a stale name that costs no step). After a blocker, take the smallest undocumented step that lets you continue, log it as the blocker's "what happened", and go on, so one blocker does not hide the rest.
5. Use the product the way the README promises. For every feature README names, run the happy path and one edge case (an empty input, a missing file, a second run of the same command). Log friction the same way, with the file and line that made the promise.
6. Run the project's harness when one exists. If the checkout has `scripts/verify`, run `scripts/verify fast` from the checkout root after the README journey. It is the one command you run that README may not name. Exit 0 logs nothing; note the evidence folder it prints. Exit 1 (a feature failed) or 3 (the environment is not ready) is a blocker. Log it with `bin/ctlhq-adoption-test log <scratch>/friction.tsv scripts/verify 1 blocker <the failed feature or doctor line>`. When README never names `scripts/verify`, also log one confusing row against `README.md` line 1, because a newcomer cannot find the proof command.
7. Declare the tier with `bin/ctlhq-adoption-test tier --list <scratch>/friction.tsv`. When you logged nothing, run `touch <scratch>/friction.tsv` first so the file exists. The tiers: milestones complete (the code is done and the journey fails on a blocker), usable (the journey works, the friction is only confusing or cosmetic), integrated (works from a fresh machine with no undocumented step). The `next` line names what blocks the next tier. Repeat it in your own words with the rows that cause it.
8. Hand the fix list to the owner. It is the `--list` rows, one line per friction, blockers first. Fix nothing in this run, not even a typo. The owner fixes, and a later run proves it.
9. Reply contract: the tier, the blockers (file, line, what happened), the counts by severity, the commit you tested, the log path, and, when the harness ran, its exit code and evidence folder. Write "adoption test, tier usable" and the like, never "done" or "finished".
