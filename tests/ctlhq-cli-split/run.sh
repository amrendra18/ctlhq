#!/usr/bin/env bash
# tests/ctlhq-cli-split/run.sh: checks for skills/cli-split/bin/ctlhq-cli-split through bin/ctlhq-cli-split.
# Prints "N checks passed" and exits 1 when any check fails. Writes only to a temp folder.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
cs="$root/bin/ctlhq-cli-split"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
pass=0
fail=0
ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL: $1"; }
expect_rc() { if [ "$1" -eq "$2" ]; then ok; else bad "$3 (expected exit $1, got $2)"; fi; }
expect_eq() { if [ "$1" = "$2" ]; then ok; else bad "$3 (expected '$1', got '$2')"; fi; }
expect_grep() { if printf '%s\n' "$2" | grep -Eq -- "$1"; then ok; else bad "$3 (no line matches: $1)"; fi; }

# Fixture: front matter, a heading, prose, numbered steps with a continuation line,
# a bullet, a fenced block, a table, and commands of each kind.
mkdir -p "$tmp/demo"
cat > "$tmp/demo/SKILL.md" <<'MD'
---
name: demo
description: a fixture
---

# Demo

Background prose with no command.

## Steps

1. Measure first. Run `bin/ctlhq-doc-diet words` and
   record the total with `git ls-files`.
2. Decide what matters.
   - Pick by `.gitignore` rules only.
3. Read `scripts/watch-pr/watch-pr` and `ctlhq-models get best-of-n-runners`.

```
1. not a step: inside a fence
```

| # | a |
|---|---|
| 1 | not a step |
MD

# 1. --help.
out="$("$cs" --help 2>&1)"; expect_rc 0 $? "--help exits 0"
expect_grep '^ctlhq-cli-split: ' "$(printf '%s\n' "$out" | head -1)" "--help first line is 'ctlhq-cli-split: ...'"

# 2. Usage errors exit 2.
"$cs" >/dev/null 2>&1; expect_rc 2 $? "no arguments exits 2"
"$cs" nosuch >/dev/null 2>&1; expect_rc 2 $? "unknown subcommand exits 2"
"$cs" steps >/dev/null 2>&1; expect_rc 2 $? "steps without a target exits 2"
"$cs" steps no-such-skill-xyz >/dev/null 2>&1; expect_rc 2 $? "unknown skill exits 2"
"$cs" steps "$tmp/demo" --bogus >/dev/null 2>&1; expect_rc 2 $? "unknown option exits 2"
"$cs" changed --since notadate >/dev/null 2>&1; expect_rc 2 $? "bad date exits 2"

# 3. steps on the fixture folder: 5 rows, kinds, lines, commands, fence and table skipped.
out="$("$cs" steps "$tmp/demo" 2>&1)"; expect_rc 0 $? "steps on a folder exits 0"
expect_grep '^5 steps, 2 name a command, 3 name none$' "$out" "summary counts 5 steps, 2 with a command"
expect_grep $'^1\t8\tP\tDemo\t-\tBackground prose' "$out" "row 1 is the prose paragraph at line 8"
expect_grep $'^2\t12\tN\tSteps\tbin/ctlhq-doc-diet words; git ls-files\t' "$out" "row 2 joins the continuation line and finds both commands"
expect_grep $'^4\t15\tB\tSteps\t-\t' "$out" "row 4 is the bullet; .gitignore is not a command"
expect_grep $'^5\t16\tN\tSteps\tscripts/watch-pr/watch-pr; ctlhq-models get best-of-n-runners\t' "$out" "row 5 finds a scripts path and a bin tool"
expect_eq 0 "$(printf '%s\n' "$out" | grep -c 'not a step')" "fenced and table lines are skipped"

# 4. --no-command and --json.
out="$("$cs" steps "$tmp/demo/SKILL.md" --no-command 2>&1)"; expect_rc 0 $? "--no-command exits 0"
expect_eq 3 "$(printf '%s\n' "$out" | grep -Ec $'^[0-9]+\t')" "--no-command keeps the 3 rows with no command"
json="$("$cs" steps "$tmp/demo/SKILL.md" --json 2>/dev/null)"
expect_eq "5 2 N" "$(printf '%s' "$json" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(len(d), len(d[1]["commands"]), d[1]["kind"])')" "--json has 5 rows and row 2 has 2 commands"

# 5. A file with no steps exits 1.
printf -- '---\nname: empty\n---\n\n# Only a heading\n' > "$tmp/empty.md"
"$cs" steps "$tmp/empty.md" >/dev/null 2>&1; expect_rc 1 $? "a file with no steps exits 1"

# 6. steps by skill name resolves skills/<name>/SKILL.md.
out="$("$cs" steps cli-split 2>&1)"; expect_rc 0 $? "steps by skill name exits 0"
expect_grep "^file: $root/skills/cli-split/SKILL.md$" "$out" "skill name resolves to its SKILL.md"

# 7. changed: a future date finds nothing (exit 1); an old reference file finds skills.
"$cs" changed --since 2999-01-01 >/dev/null 2>&1; expect_rc 1 $? "changed since a future date exits 1"
touch -t 200001010000 "$tmp/old-proposal.md"
out="$("$cs" changed --since "$tmp/old-proposal.md" 2>&1)"; expect_rc 0 $? "changed since an old file exits 0"
expect_grep $'^[0-9]+\tcli-split\tskills/cli-split/' "$out" "changed lists cli-split"
n="$(ls -d "$root"/skills/*/SKILL.md | wc -l | tr -d ' ')"
expect_grep "^$n skills changed since " "$out" "an old file finds every skill ($n)"

echo "$pass checks passed"
if [ "$fail" -gt 0 ]; then echo "$fail checks failed"; exit 1; fi
