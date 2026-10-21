#!/usr/bin/env bash
# tests/ctlhq-unslop/run.sh: checks for skills/unslop/bin/ctlhq-unslop through bin/ctlhq-unslop.
# One fixture line per checked rule (7 8 9 13 14 17 18 19 20 22 23 24 26 29 31 33 34), a
# fixture of text the rules must not flag (code, links, front matter, the documented skip
# words), and the flags --rules and --list-rules, stdin, directories, and exits 0, 1, 2.
# Prints "N checks passed" and exits 1 when any check fails. Read-only for the repository.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
us="$root/bin/ctlhq-unslop"
tmp="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/unslop-test.XXXXXX")" && pwd -P)"
trap 'rm -rf "$tmp"' EXIT
pass=0
fail=0
ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL: $1"; }
expect_rc() { if [ "$1" -eq "$2" ]; then ok; else bad "$3 (expected exit $1, got $2)"; fi; }
expect_eq() { if [ "$1" = "$2" ]; then ok; else bad "$3 (expected '$1', got '$2')"; fi; }
expect_grep() { if printf '%s\n' "$2" | grep -Eq -- "$1"; then ok; else bad "$3 (no line matches: $1)"; fi; }
expect_no() { if printf '%s\n' "$2" | grep -Eq -- "$1"; then bad "$3 (a line matches: $1)"; else ok; fi; }
cd "$tmp" || exit 1

# 1. --help and --list-rules.
out="$("$us" --help 2>&1)"; expect_rc 0 $? "--help exits 0"
expect_grep '^ctlhq-unslop: ' "$(printf '%s\n' "$out" | head -1)" "--help first line is 'ctlhq-unslop: ...'"
expect_grep -- '--rules' "$out" "--help names --rules"
expect_grep -- '--list-rules' "$out" "--help names --list-rules"
out="$("$us" --list-rules 2>&1)"; expect_rc 0 $? "--list-rules exits 0"
checked="7 8 9 13 14 17 18 19 20 22 23 24 26 29 31 33 34"
got="$(printf '%s\n' "$out" | sed -n '/^checked by this tool:/,/^left to judgment/p' | grep -E '^ +[0-9]+  ' | awk '{print $1}' | tr '\n' ' ' | sed 's/ $//')"
expect_eq "$checked" "$got" "--list-rules lists the 17 checked rules"
got="$(printf '%s\n' "$out" | sed -n '/^left to judgment/,/^note:/p' | grep -E '^ +[0-9]+  ' | awk '{print $1}' | tr '\n' ' ' | sed 's/ $//')"
expect_eq "3 5 10 11 12 15 16 25 27 28 30 32" "$got" "--list-rules lists the 12 judgment-only rules"
expect_grep '^note: rule 8 skips "features"' "$out" "--list-rules prints the not-flagged note"

# 2. One fixture line per checked rule. Each line must give exactly its rule.
cat > pos.md <<'MD'
We delve into the code.
The file serves as the index.
It is not just fast but also small.
Plain text — with a long dash.
Plain text - with a hyphen dash.
Note that this: matters a lot.
## The Quick Brown Fox Jumps
- ✅ shipped item
He said “yes” to it.
I hope this helps.
Great question about it.
We run it in order to test.
That could potentially break.
The paradigm stays put.
The file was deleted.
We utilize the cache.
Input → output.
| Name | Value |
|------|-------|
| a    | b     |
MD
want="1:7 2:8 3:9 4:13 5:13 6:14 7:17 8:18 9:19 9:19 10:20 11:22 12:23 13:24 14:26 15:29 16:31 17:33 18:34"
out="$("$us" pos.md 2>&1)"; rc=$?
expect_rc 1 "$rc" "findings exit 1"
got="$(printf '%s\n' "$out" | sed -n 's/^pos\.md:\([0-9]*\): rule \([0-9]*\) .*/\1:\2/p' | tr '\n' ' ' | sed 's/ $//')"
expect_eq "$want" "$got" "each positive fixture line gives its rule and no other"
expect_eq "19 findings in 1 file(s)" "$(printf '%s\n' "$out" | tail -1)" "positive summary line"
for r in $checked; do
	expect_grep "^pos\.md:[0-9]+: rule $r " "$out" "rule $r fires on its fixture line"
done
expect_grep '^pos\.md:1: rule 7 AI vocabulary: delve$' "$out" "finding shape is path:line: rule N <name>: <matched text>"
expect_grep '^pos\.md:3: rule 9 not just X but Y: not just fast but$' "$out" "rule 9 prints the matched span"
expect_grep "^pos\.md:18: rule 34 table without a number column: first column is 'Name'" "$out" "rule 34 names the first column"

# 3. More forms of the same rules.
printf '## Done ✨\nA – B\nx -> y\nx => y\nNot only red but blue.\nWe Delve here.\nA -- B\n' > more.md
want="1:18 2:13 3:33 4:33 5:9 6:7 7:13"
got="$("$us" more.md 2>&1 | sed -n 's/^more\.md:\([0-9]*\): rule \([0-9]*\) .*/\1:\2/p' | tr '\n' ' ' | sed 's/ $//')"
expect_eq "$want" "$got" "heading emoji, en dash, -> and =>, not only, capital Delve, double hyphen"

# 4. Text the rules must not flag.
cat > neg.md <<'MD'
---
title: "Front: matter — delve"
---
Run `delve --serve-as` in code.
```
We delve — utilize → paradigm
```
~~~
in order to: leverage
~~~
````
```
We delve inside a nested fence.
```
````
See [the docs](https://example.com/delve—x) now.
Visit https://example.com/a—b today.
- a bullet item - with a hyphen
Meet at 10:30 today.
## Sentence case heading here
It features a cache.
A vector, a primitive, a harness, scaffolding, the surface, a wedge, evacuate.
The tool is used daily and the file is needed.
It was finished by the time we left.
| # | Name |
|---|------|
| 1 | a    |
| Step | What |
|------|------|
| 1 | a |
Emoji in prose ✅ is fine.
A well-known co-author.
MD
out="$("$us" neg.md 2>&1)"; rc=$?
expect_eq "0 findings in 1 file(s)" "$out" "the must-not-flag fixture gives no finding"
expect_rc 0 "$rc" "a clean file exits 0"

# 5. Double-backtick inline code is inline code too.
printf 'Run ``delve`` now.\n' > dbl.md
out="$("$us" dbl.md 2>&1)"
expect_eq "0 findings in 1 file(s)" "$out" "double-backtick inline code \`\`delve\`\` is skipped"
printf 'Run ``a `delve` b`` now.\n' > dbl2.md
expect_eq "0 findings in 1 file(s)" "$("$us" dbl2.md 2>&1)" "a backtick-wrapped span inside double backticks is skipped"

# 6. --rules.
out="$("$us" --rules 7 pos.md 2>&1)"; rc=$?
expect_eq "pos.md:1: rule 7 AI vocabulary: delve|1 findings in 1 file(s)" "$(printf '%s\n' "$out" | paste -sd'|' -)" "--rules 7 reports only rule 7"
expect_rc 1 "$rc" "--rules 7 with a hit exits 1"
expect_eq "3 findings in 1 file(s)" "$("$us" --rules 13,14 pos.md | tail -1)" "--rules 13,14 reports both rules"
expect_eq "2 findings in 1 file(s)" "$("$us" --rules 13, pos.md | tail -1)" "--rules accepts a trailing comma"
"$us" --rules 20 neg.md >/dev/null 2>&1; expect_rc 0 $? "--rules on a clean file exits 0"
err="$("$us" --rules 99 pos.md 2>&1)"; rc=$?
expect_rc 2 "$rc" "--rules with an unchecked rule exits 2"
expect_grep '^not checked by this tool: \[99\]$' "$err" "--rules names the unchecked rule"
"$us" --rules 10 pos.md >/dev/null 2>&1; expect_rc 2 $? "--rules with a judgment-only rule exits 2"
"$us" --rules x pos.md >/dev/null 2>&1; expect_rc 2 $? "--rules with a non-number exits 2"
"$us" --rules >/dev/null 2>&1; expect_rc 2 $? "--rules without a list exits 2"

# 7. Inputs: stdin, '-', directories, several files, missing and undecodable files.
out="$(printf 'We delve.\n' | "$us" 2>&1)"; rc=$?
expect_eq "<stdin>:1: rule 7 AI vocabulary: delve|1 findings in 1 file(s)" "$(printf '%s\n' "$out" | paste -sd'|' -)" "stdin is read as <stdin>"
expect_rc 1 "$rc" "stdin with a hit exits 1"
expect_eq "0 findings in 1 file(s)" "$(printf 'Plain.\n' | "$us" - 2>&1)" "'-' reads stdin"
expect_eq "0 findings in 1 file(s)" "$(printf '' | "$us" 2>&1)" "empty stdin is clean"
mkdir -p tree/sub
cp pos.md tree/sub/a.md; cp neg.md tree/b.md; printf 'We delve.\n' > tree/c.txt
out="$("$us" tree 2>&1)"
expect_eq "19 findings in 2 file(s)" "$(printf '%s\n' "$out" | tail -1)" "a directory walks *.md only"
expect_no 'c\.txt' "$out" "a directory skips non-Markdown files"
expect_eq "19 findings in 2 file(s)" "$("$us" pos.md neg.md | tail -1)" "two files are summed"
err="$("$us" missing.md 2>&1)"; rc=$?
expect_rc 2 "$rc" "a missing file exits 2 (known-bad input)"
expect_grep '^missing\.md: cannot read' "$err" "a missing file is named"
printf '\377\376 bad\n' > bin.md
"$us" bin.md >/dev/null 2>&1; expect_rc 2 $? "a file that is not UTF-8 exits 2"
"$us" --bogus pos.md >/dev/null 2>&1; expect_rc 2 $? "unknown option exits 2"

# 8. Positive controls: planted defects in a copy of the tool must break the checks above.
mkdir -p mutant
mutate() { # sed-expression: write a defective copy to mutant/ctlhq-unslop and check the defect landed
	sed "$1" "$us" > mutant/ctlhq-unslop; chmod +x mutant/ctlhq-unslop
	if cmp -s "$us" mutant/ctlhq-unslop; then bad "control: planted defect '$1' did not change the tool"; else ok; fi
}
mutate 's/^        prose = strip_prose(raw)$/        prose = raw/'
if [ "$(mutant/ctlhq-unslop neg.md 2>&1 | tail -1)" != "0 findings in 1 file(s)" ]; then ok; else bad "control: dropping inline-code and link stripping is caught by the must-not-flag check"; fi
mutate 's/"delve", "delves",//'
if ! mutant/ctlhq-unslop pos.md 2>&1 | grep -q '^pos\.md:1: rule 7'; then ok; else bad "control: a missing vocabulary word is caught by the rule 7 check"; fi
mutate 's/return 1 if findings else 0/return 0/'
mutant/ctlhq-unslop pos.md >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 0 ]; then ok; else bad "control: a tool that always exits 0 is caught by the exit-1 check"; fi

echo "$pass checks passed"
[ "$fail" -eq 0 ] || { echo "$fail checks failed"; exit 1; }
