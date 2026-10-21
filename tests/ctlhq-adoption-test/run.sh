#!/usr/bin/env bash
# tests/ctlhq-adoption-test/run.sh: checks for skills/adoption-test/bin/ctlhq-adoption-test through bin/ctlhq-adoption-test.
# Prints "N checks passed" and exits 1 when any check fails. Writes only under a
# temporary folder (TMPDIR honoured); never touches ~/.ctlhq or the repository.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
at="$root/bin/ctlhq-adoption-test"
pass=0
fail=0
ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL: $1"; }
expect_rc() { # expected actual label
	if [ "$1" -eq "$2" ]; then ok; else bad "$3 (expected exit $1, got $2)"; fi
}
expect_eq() { # expected actual label
	if [ "$1" = "$2" ]; then ok; else bad "$3 (expected '$1', got '$2')"; fi
}
expect_grep() { # pattern text label
	if printf '%s\n' "$2" | grep -Eq -- "$1"; then ok; else bad "$3 (no line matches: $1)"; fi
}
expect_no_grep() { # pattern text label
	if printf '%s\n' "$2" | grep -Eq -- "$1"; then bad "$3 (a line matches: $1)"; else ok; fi
}
count() { printf '%s\n' "$2" | grep -Ec -- "$1"; }
tmp="$(mktemp -d "${TMPDIR:-/tmp}/ctlhq-adoption-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
tab="$(printf '\t')"

# 1. --help.
out="$("$at" --help 2>&1)"; rc=$?
expect_rc 0 "$rc" "--help exits 0"
expect_grep '^ctlhq-adoption-test: ' "$(printf '%s\n' "$out" | head -1)" "--help first line is 'ctlhq-adoption-test: ...'"
expect_grep 'AGENTS.md' "$out" "--help quotes the AGENTS.md rule it encodes"

# 2. Fixture README: three fenced blocks, one of them (json) not a command block.
cat > "$tmp/README.md" <<'EOF'
# Demo

Install it:

```sh
$ git clone https://example.invalid/demo.git
cd demo
# build everything
make install \
  PREFIX=/usr/local
```

Run it:

```console
$ ./demo --version
demo 1.0
```

The output looks like this:

```json
{"ok": true}
```
EOF
out="$("$at" commands "$tmp/README.md" 2>&1)"; rc=$?
expect_rc 0 "$rc" "commands exits 0 on the fixture"
expect_eq 4 "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" "commands lists 4 commands"
expect_eq "1${tab}6${tab}git clone https://example.invalid/demo.git" "$(printf '%s\n' "$out" | head -1)" "command 1 is the git clone with the prompt stripped and README line 6"
expect_grep "^2${tab}7${tab}cd demo\$" "$out" "command 2 is cd demo"
expect_grep "^3${tab}9${tab}make install PREFIX=/usr/local\$" "$out" "command 3 joins the backslash continuation"
expect_grep "^4${tab}16${tab}\./demo --version\$" "$out" "command 4 is ./demo --version from the console block"
expect_no_grep 'demo 1\.0' "$out" "console output line is not a command"
expect_no_grep '"ok"' "$out" "json block is not a command block"
expect_no_grep 'build everything' "$out" "comment line is not a command"

# 3. commands: an untagged block keeps known commands only; no commands exits 1; missing file exits 2.
printf '# Plain\n\n```\nnpm install\nSome prose line.\n$ npm test\n```\n' > "$tmp/PLAIN.md"
out="$("$at" commands "$tmp/PLAIN.md" 2>&1)"; rc=$?
expect_rc 0 "$rc" "commands on an untagged block exits 0"
expect_eq 2 "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" "untagged block yields the 2 command lines"
expect_no_grep 'Some prose' "$out" "prose in an untagged block is not a command"
printf '# Tree\n\n```\nbin/       one command per tool\nskills/x/  one skill\nbin/tool --help\n```\n' > "$tmp/TREE.md"
out="$("$at" commands "$tmp/TREE.md" 2>&1)"
expect_eq "1${tab}6${tab}bin/tool --help" "$out" "a layout tree line ending in / is not a command"
printf '# None\n\nJust words.\n\n```json\n{}\n```\n' > "$tmp/NONE.md"
"$at" commands "$tmp/NONE.md" >/dev/null 2>&1; expect_rc 1 $? "commands with no command exits 1"
"$at" commands "$tmp/missing.md" >/dev/null 2>&1; expect_rc 2 $? "commands on a missing file exits 2"

# 4. log: refuses a bad severity or line, writes the header once, keeps rows single-line.
log="$tmp/friction.tsv"
"$at" log "$log" README.md 12 severe "not a severity" >/dev/null 2>&1; expect_rc 2 $? "log with a bad severity exits 2"
if [ -e "$log" ]; then bad "log with a bad severity must not create the file"; else ok; fi
"$at" log "$log" README.md twelve blocker "bad line" >/dev/null 2>&1; expect_rc 2 $? "log with a non-integer line exits 2"
"$at" log "$log" README.md 12 blocker "make install fails:" "no rule to make target" >/dev/null 2>&1; expect_rc 0 $? "log blocker exits 0"
"$at" log "$log" README.md 16 confusing "demo --version prints 0.9, README says 1.0" >/dev/null 2>&1; expect_rc 0 $? "log confusing exits 0"
"$at" log "$log" docs/usage.md - cosmetic "file named in README does not exist" >/dev/null 2>&1; expect_rc 0 $? "log with line - exits 0"
"$at" log "$log" README.md 3 cosmetic "typo: instal" >/dev/null 2>&1; expect_rc 0 $? "log cosmetic exits 0"
expect_eq 5 "$(wc -l < "$log" | tr -d ' ')" "log has a header and 4 rows"
expect_eq "timestamp${tab}file${tab}line${tab}severity${tab}what_happened" "$(head -1 "$log")" "log header is the five columns"
expect_eq 1 "$(grep -c '^timestamp' "$log")" "header written once"
expect_grep "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z${tab}README.md${tab}12${tab}blocker${tab}make install fails: no rule to make target\$" "$(sed -n 2p "$log")" "row 1 has a UTC timestamp and the joined text"
expect_grep "^[^${tab}]*${tab}docs/usage.md${tab}-${tab}cosmetic${tab}" "$(sed -n 4p "$log")" "row 3 keeps the - line"

# 5. tier: mixed severities give milestones complete (exit 2); --list orders blocker first.
out="$("$at" tier "$log" 2>&1)"; rc=$?
expect_rc 2 "$rc" "tier with a blocker exits 2"
expect_grep "^blocker${tab}1\$" "$out" "tier counts 1 blocker"
expect_grep "^confusing${tab}1\$" "$out" "tier counts 1 confusing"
expect_grep "^cosmetic${tab}2\$" "$out" "tier counts 2 cosmetic"
expect_grep "^rows${tab}4\$" "$out" "tier counts 4 rows"
expect_grep "^tier${tab}milestones complete\$" "$out" "tier is milestones complete"
expect_grep "^next${tab}usable needs 0 blockers; 1 open\$" "$out" "next names the blocker count"
expect_eq 6 "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" "tier without --list prints 6 lines"
out="$("$at" tier --list "$log" 2>&1)"; rc=$?
expect_rc 2 "$rc" "tier --list keeps exit 2"
expect_eq 10 "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" "tier --list prints 6 lines plus 4 rows"
expect_eq "blocker confusing cosmetic cosmetic" "$(printf '%s\n' "$out" | tail -4 | cut -f1 | tr '\n' ' ' | sed 's/ $//')" "--list orders blocker, confusing, cosmetic"
expect_grep "^blocker${tab}README.md:12${tab}make install fails: no rule to make target\$" "$(printf '%s\n' "$out" | sed -n 7p)" "fix list row is severity, file:line, what happened"

# 6. tier: usable (exit 1), integrated on an empty log (exit 0), missing log and a bad row (exit 3).
usable="$tmp/usable.tsv"
"$at" log "$usable" README.md 16 confusing "version mismatch" >/dev/null 2>&1
"$at" log "$usable" README.md 3 cosmetic "typo" >/dev/null 2>&1
out="$("$at" tier "$usable" 2>&1)"; rc=$?
expect_rc 1 "$rc" "tier without a blocker exits 1"
expect_grep "^tier${tab}usable\$" "$out" "tier is usable"
expect_grep "^next${tab}integrated needs 0 confusing and 0 cosmetic; 2 open\$" "$out" "next names the open rows"
: > "$tmp/empty.tsv"
out="$("$at" tier "$tmp/empty.tsv" 2>&1)"; rc=$?
expect_rc 0 "$rc" "tier on an empty log exits 0"
expect_grep "^tier${tab}integrated\$" "$out" "empty log is integrated"
expect_grep "^rows${tab}0\$" "$out" "empty log has 0 rows"
"$at" tier "$tmp/nolog.tsv" >/dev/null 2>&1; expect_rc 3 $? "tier on a missing log exits 3"
printf 'timestamp\tfile\tline\tseverity\twhat_happened\n2026-01-01T00:00:00Z\tREADME.md\t1\tsevere\tx\n' > "$tmp/bad.tsv"
err="$("$at" tier "$tmp/bad.tsv" 2>&1 >/dev/null)"; rc=$?
expect_rc 3 "$rc" "tier on a bad severity row exits 3"
expect_grep 'row 2 has severity' "$err" "bad row is named with its row number"
"$at" tier >/dev/null 2>&1; expect_rc 3 $? "tier without a path exits 3"

# 7. checkout: a scratch repository, a non-empty dest, a plain folder, a missing repo.
repo="$tmp/repo"
mkdir -p "$repo"
git -C "$repo" init -q
printf '# Hello\n' > "$repo/README.md"
git -C "$repo" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false add README.md
git -C "$repo" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false commit -q -m init
printf 'uncommitted\n' > "$repo/scratch.txt"
out="$("$at" checkout "$repo" "$tmp/co" 2>&1)"; rc=$?
expect_rc 0 "$rc" "checkout of a repository exits 0"
expect_eq "$(cd "$tmp/co" && pwd -P)" "$out" "checkout prints the absolute dest path"
if [ -f "$tmp/co/README.md" ]; then ok; else bad "checkout has the committed README"; fi
if [ -e "$tmp/co/scratch.txt" ]; then bad "checkout must not carry the uncommitted file"; else ok; fi
if [ -d "$tmp/co/.git" ]; then ok; else bad "checkout is a git clone"; fi
"$at" checkout "$repo" "$tmp/co" >/dev/null 2>&1; expect_rc 2 $? "checkout into a non-empty dest exits 2"
mkdir -p "$tmp/co-empty"
out="$("$at" checkout "$repo" "$tmp/co-empty" 2>&1)"; rc=$?
expect_rc 0 "$rc" "checkout into an existing empty dest exits 0"
mkdir -p "$tmp/plain/sub"
printf 'x\n' > "$tmp/plain/sub/file.txt"
out="$("$at" checkout "$tmp/plain" "$tmp/plain-copy" 2>&1)"; rc=$?
expect_rc 0 "$rc" "checkout of a plain folder exits 0"
if [ -f "$tmp/plain-copy/sub/file.txt" ]; then ok; else bad "plain copy carries the nested file"; fi
"$at" checkout "$tmp/nosuch" "$tmp/x" >/dev/null 2>&1; expect_rc 2 $? "checkout of a missing repo exits 2"
if [ -e "$tmp/x" ]; then bad "a refused checkout must not create dest"; else ok; fi

# 8. Usage errors.
"$at" >/dev/null 2>&1; expect_rc 2 $? "no command exits 2"
"$at" bogus >/dev/null 2>&1; expect_rc 2 $? "unknown command exits 2"
"$at" commands >/dev/null 2>&1; expect_rc 2 $? "commands without a path exits 2"
"$at" log "$tmp/l.tsv" README.md 1 blocker >/dev/null 2>&1; expect_rc 2 $? "log without what happened exits 2"
"$at" checkout "$repo" >/dev/null 2>&1; expect_rc 2 $? "checkout without dest exits 2"

echo "$pass checks passed"
if [ "$fail" -gt 0 ]; then
	echo "$fail checks failed"
	exit 1
fi
