#!/usr/bin/env bash
# tests/ctlhq-benchmark-checklist/run.sh: checks for bin/ctlhq-benchmark-checklist
# (skills/benchmark-checklist/bin/ctlhq-benchmark-checklist). Prints "N checks passed" and exits 1 when
# any check fails. Writes only to a temp folder.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
bc="$root/bin/ctlhq-benchmark-checklist"
real="$root/skills/benchmark-checklist/bin/ctlhq-benchmark-checklist"
pass=0
fail=0
ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL: $1"; }
expect_rc() { if [ "$1" -eq "$2" ]; then ok; else bad "$3 (expected exit $1, got $2)"; fi; }
expect_eq() { if [ "$1" = "$2" ]; then ok; else bad "$3 (expected '$1', got '$2')"; fi; }
expect_grep() { if printf '%s\n' "$2" | grep -Eq -- "$1"; then ok; else bad "$3 (no line matches: $1)"; fi; }
expect_fgrep() { if printf '%s\n' "$2" | grep -Fq -- "$1"; then ok; else bad "$3 (no line contains: $1)"; fi; }
expect_nogrep() { if printf '%s\n' "$2" | grep -Eq -- "$1"; then bad "$3 (a line matches: $1)"; else ok; fi; }
count() { printf '%s\n' "$2" | grep -Ec -- "$1"; }

tmp="$(mktemp -d "${TMPDIR:-/tmp}/benchmark-checklist-test.XXXXXX")"
tmp="$(cd "$tmp" && pwd)" || exit 1  # TMPDIR may end in a slash
[ -n "$tmp" ] && [ -d "$tmp" ] || { echo "FAIL: no temp folder"; exit 1; }
trap 'rm -rf "$tmp"' EXIT
TAB="$(printf '\t')"
# run <args...>: sets out, err, rc.
run() { out="$("$bc" "$@" 2>"$tmp/err")"; rc=$?; err="$(cat "$tmp/err")"; }
# answer <tsv> <ids...>: record a short answer for each id.
answer() { local f="$1"; shift; for i in "$@"; do "$bc" record "$f" "$i" "answer $i" >/dev/null 2>&1; done; }

# 1. --help, -h, no command, unknown command.
run --help; expect_rc 0 "$rc" "--help exits 0"
expect_grep '^ctlhq-benchmark-checklist: ' "$(printf '%s\n' "$out" | head -1)" "--help first line is 'ctlhq-benchmark-checklist: ...'"
for c in print record status env report --skill; do expect_fgrep "ctlhq-benchmark-checklist $c" "$out" "--help names $c"; done
run -h; expect_rc 0 "$rc" "-h exits 0"
run; expect_rc 2 "$rc" "no command exits 2"
expect_grep '^ctlhq-benchmark-checklist: ' "$(printf '%s\n' "$err" | head -1)" "no command prints the help on stderr"
run bogus; expect_rc 2 "$rc" "unknown command exits 2"; expect_fgrep "unknown command 'bogus'" "$err" "unknown command named"

# 2. print: the seven questions of the real skill, ids 1 to 7, bold markers removed.
run print; expect_rc 0 "$rc" "print exits 0"
expect_eq 7 "$(printf '%s\n' "$out" | grep -c '')" "print lists 7 items"
expect_eq "1 2 3 4 5 6 7" "$(printf '%s\n' "$out" | sed 's/\..*//' | tr '\n' ' ' | sed 's/ $//')" "ids are 1 to 7 in order"
expect_grep '^1\. Why not double\? Name the limiter\.' "$out" "item 1 text"
expect_grep '^7\. Did it even happen\? ' "$out" "item 7 text"
expect_eq 0 "$(count '\*\*' "$out")" "print strips ** markers"
run print extra; expect_rc 2 "$rc" "print with an argument exits 2"

# 3. --skill with a fixture: front matter, sub-items, continuation lines, fences, Tool section, duplicates.
fx="$tmp/SKILL.md"
cat > "$fx" <<'MD'
---
name: fixture
description: "a fixture: 1. not an item"
---

# Fixture

1. **First.** Body of the first.
   continued on a second line.
   - Sub one. More.
   - Sub two
2. Second item. It has two sentences.

```
3. inside a fence, not an item
```

## Tool

9. a numbered line under Tool, not an item

## More

3. Third item
2. Duplicate id two
MD
run --skill "$fx" print; expect_rc 0 "$rc" "--skill fixture print exits 0"
expect_eq "1|  1a|  1b|2|3" "$(printf '%s\n' "$out" | sed 's/\. .*//' | tr '\n' '|' | sed 's/|$//')" "fixture ids are 1, 1a, 1b, 2, 3"
expect_grep '^1\. First\. Body of the first\. continued on a second line\.$' "$out" "a continuation line joins its item"
expect_grep '^  1a\. Sub one\. More\.$' "$out" "an indented bullet becomes sub-item 1a"
expect_nogrep 'inside a fence|under Tool' "$out" "fenced and Tool-section lines are not items"
expect_fgrep 'warning: duplicate item id 2' "$err" "a duplicate id is warned about on stderr"
expect_grep '^2\. Second item\.' "$out" "the first of a duplicate id is kept"
run --skill="$fx" print; expect_rc 0 "$rc" "--skill=PATH form works"
run print --skill "$fx"; expect_eq 5 "$(printf '%s\n' "$out" | grep -c '')" "--skill after the command works"
run --skill; expect_rc 2 "$rc" "--skill without a path exits 2"
run --skill "$tmp/nosuch.md" print; expect_rc 2 "$rc" "--skill to a missing file exits 2"
expect_fgrep 'checklist not found' "$err" "missing SKILL.md named"
printf '# Empty\n\nNo list here.\n' > "$tmp/none.md"
run --skill "$tmp/none.md" print; expect_rc 2 "$rc" "a SKILL.md without numbered items exits 2"
expect_fgrep 'no numbered checklist items found' "$err" "no items named"

# 4. record: header once, joined words, tabs and newlines flattened, verdict rules, errors.
t="$tmp/bench.tsv"
run record "$t" 1 bound by JSON parsing; expect_rc 0 "$rc" "record exits 0"
expect_eq "recorded 1 in $t" "$out" "record confirms the id and file"
expect_eq "ts${TAB}id${TAB}answer" "$(sed -n 1p "$t")" "record writes the header on first use"
expect_grep "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z${TAB}1${TAB}bound by JSON parsing\$" "$(sed -n 2p "$t")" "answer words joined with spaces, UTC ts"
run record "$t" 2 "$(printf 'a\tb\nc')"; expect_rc 0 "$rc" "record with tab and newline exits 0"
expect_eq "a b c" "$(sed -n 3p "$t" | cut -f3)" "tabs and newlines in the answer become spaces"
expect_eq 1 "$(grep -c '^ts' "$t")" "header appears once"
run record "$t" 9 x; expect_rc 2 "$rc" "unknown id exits 2"
expect_fgrep "unknown id '9'. Valid ids: 1, 2, 3, 4, 5, 6, 7, verdict" "$err" "unknown id lists the valid ids"
run record "$t" 1 "  "; expect_rc 2 "$rc" "blank answer exits 2"; expect_fgrep 'the answer is empty' "$err" "blank answer named"
run record "$t" 1; expect_rc 2 "$rc" "record without an answer exits 2"
run record "$t" verdict Faster; expect_rc 0 "$rc" "verdict Faster (any case) exits 0"
expect_eq "verdict${TAB}faster" "$(tail -1 "$t" | cut -f2,3)" "verdict is stored lower case"
run record "$t" verdict no measurable difference; expect_rc 0 "$rc" "multi-word verdict exits 0"
run record "$t" verdict quicker; expect_rc 2 "$rc" "unknown verdict exits 2"
expect_fgrep 'verdict must be one of: faster, slower, no measurable difference, inconclusive' "$err" "verdict choices listed"
mkdir "$tmp/adir"
run record "$tmp/adir" 1 x; expect_rc 1 "$rc" "record into a folder exits 1"; expect_fgrep 'cannot write' "$err" "write failure named"
# Every word after <file.tsv> <id> is answer text, even one equal to an option (--help, -h,
# --skill, --only).
run record "$tmp/opt.tsv" 1 profiled with node --cpu-prof, see --help; expect_rc 0 "$rc" "record with an answer word --help exits 0"
expect_eq "profiled with node --cpu-prof, see --help" "$(sed -n 2p "$tmp/opt.tsv" | cut -f3)" "record keeps the answer word --help"
run record "$tmp/opt.tsv" 2 -h --only 4,7 --skill x --skill=y; expect_rc 0 "$rc" "record with answer words -h, --only, --skill exits 0"
expect_eq "-h --only 4,7 --skill x --skill=y" "$(sed -n 3p "$tmp/opt.tsv" | cut -f3)" "record keeps -h, --only, and --skill answer words"
run record --help; expect_rc 0 "$rc" "--help before the answer still prints the help"
expect_grep '^ctlhq-benchmark-checklist: ' "$(printf '%s\n' "$out" | head -1)" "record --help prints the help"
run --skill "$fx" record "$tmp/fx.tsv" 1a sub answer; expect_rc 0 "$rc" "record accepts a sub-item id from --skill"

# 5. status: missing file, partial, complete, --only.
s="$tmp/status.tsv"
run status "$s"; expect_rc 1 "$rc" "status on a missing file exits 1"
expect_eq "0 of 7 answered in $s" "$(printf '%s\n' "$out" | head -1)" "missing file: 0 of 7 answered"
expect_fgrep 'does not exist yet; nothing answered' "$err" "missing file noted on stderr"
expect_eq 7 "$(count '^unanswered: ' "$out")" "missing file lists 7 unanswered"
answer "$s" 1 3 4
run status "$s"; expect_rc 1 "$rc" "partial status exits 1"
expect_eq "3 of 7 answered in $s" "$(printf '%s\n' "$out" | head -1)" "partial: 3 of 7 answered"
expect_eq "unanswered: 2  Was it tuned?" "$(printf '%s\n' "$out" | sed -n 2p)" "unanswered line names the bold title"
expect_nogrep '^unanswered: (1|3|4) ' "$out" "answered ids are not listed"
answer "$s" 7
run status "$s" --only 4,7; expect_rc 0 "$rc" "--only 4,7 with 4 and 7 answered exits 0"
expect_eq "2 of 2 answered in $s (ids 4, 7)" "$out" "--only names the ids"
run status "$s" --only=4,5; expect_rc 1 "$rc" "--only=4,5 with 5 unanswered exits 1"
expect_grep '^unanswered: 5  Does it reproduce\?$' "$out" "--only lists only the unanswered id in scope"
run --only 4,7 status "$s"; expect_rc 0 "$rc" "--only before the command works"
run status "$s" --only 4,99; expect_rc 2 "$rc" "--only with an unknown id exits 2"
run status "$s" --only ","; expect_rc 2 "$rc" "--only with no ids exits 2"
run status "$s" --only; expect_rc 2 "$rc" "--only without a value exits 2"
run report "$s" --only 4,7; expect_rc 2 "$rc" "--only on another command exits 2"; expect_fgrep '--only belongs to status' "$err" "--only misuse named"
run status; expect_rc 2 "$rc" "status without a file exits 2"
answer "$s" 2 5 6
run status "$s"; expect_rc 0 "$rc" "all answered exits 0"
expect_eq "7 of 7 answered in $s" "$out" "all answered: 7 of 7, no unanswered lines"
printf 'ts\tid\tanswer\nbroken line\n\n2026\t1\n' > "$tmp/junk.tsv"
run status "$tmp/junk.tsv"; expect_rc 1 "$rc" "status ignores short and malformed rows"
expect_eq "0 of 7 answered in $tmp/junk.tsv" "$(printf '%s\n' "$out" | head -1)" "malformed rows count as unanswered"

# 6. report: gaps, verdict downgrade, exit rule, last answer wins.
r="$tmp/report.tsv"
run report "$r"; expect_rc 1 "$rc" "report on a missing file exits 1"
expect_eq "inconclusive (unanswered: 1, 2, 4, 5, 7; no verdict recorded)" "$out" "report on nothing names every gap"
"$bc" record "$r" 1 "bound by JSON parsing on one core" >/dev/null 2>&1
"$bc" record "$r" 5 "p50 41 ms to 33 ms, median of 7 runs, range 32 to 35 ms" >/dev/null 2>&1
answer "$r" 2 4 7
"$bc" record "$r" verdict faster >/dev/null 2>&1
run report "$r"; expect_rc 0 "$rc" "report with 1, 2, 4, 5, 7 and a verdict exits 0"
expect_eq "faster: p50 41 ms to 33 ms, median of 7 runs, range 32 to 35 ms, bound by JSON parsing on one core" "$out" "report line: verdict, answer 5, answer 1"
"$bc" record "$r" verdict slower >/dev/null 2>&1
run report "$r"; expect_grep '^slower: ' "$out" "the last recorded verdict wins"
r2="$tmp/r2.tsv"; answer "$r2" 1 4 5 7; "$bc" record "$r2" verdict faster >/dev/null 2>&1
run report "$r2"; expect_rc 0 "$rc" "missing 2 alone still exits 0"
expect_eq "inconclusive: answer 5, answer 1 (unanswered: 2)" "$out" "missing 2 makes the verdict inconclusive"
r3="$tmp/r3.tsv"; answer "$r3" 1 2 4 7; "$bc" record "$r3" verdict faster >/dev/null 2>&1
run report "$r3"; expect_rc 1 "$rc" "missing 5 exits 1"
expect_eq "faster: answer 1 (unanswered: 5)" "$out" "missing 5 keeps the verdict and names the gap"
r4="$tmp/r4.tsv"; answer "$r4" 1 2 4 5 7
run report "$r4"; expect_rc 0 "$rc" "no verdict but every needed id exits 0"
expect_eq "inconclusive: answer 5, answer 1 (no verdict recorded)" "$out" "no verdict means inconclusive"
run report "$tmp/adir"; expect_rc 1 "$rc" "report on a folder exits 1"
run report; expect_rc 2 "$rc" "report without a file exits 2"
run report "$r" extra; expect_rc 2 "$rc" "report with two files exits 2"

# 7. env: the real machine, plus a stubbed load average for both branches.
run env; rc_env=$rc
expect_grep '^load [0-9]+\.[0-9]{2} \(1 min\), [0-9]+\.[0-9]{2} \(5 min\), [0-9]+\.[0-9]{2} \(15 min\); cores [0-9]+$' "$(printf '%s\n' "$out" | head -1)" "env prints three load averages and the core count"
if { [ "$rc_env" -eq 0 ] && ! printf '%s' "$out" | grep -q '^busy:'; } || { [ "$rc_env" -eq 1 ] && printf '%s' "$out" | grep -q '^busy:'; }; then ok; else bad "env exit $rc_env agrees with the busy line"; fi
run env extra; expect_rc 2 "$rc" "env with an argument exits 2"
stub_env() { # load1 cores
	python3 - "$real" "$1" "$2" <<'PY'
import os, runpy, sys
path, load, cores = sys.argv[1], float(sys.argv[2]), int(sys.argv[3])
os.getloadavg = lambda: (load, 0.5, 0.25)
os.cpu_count = lambda: cores
sys.argv = ["ctlhq-benchmark-checklist", "env"]
runpy.run_path(path, run_name="__main__")
PY
}
out="$(stub_env 9.5 4 2>&1)"; expect_rc 1 $? "env with load 9.5 on 4 cores exits 1"
expect_grep '^busy: the 1 minute load 9\.50 exceeds 4 cores\. ' "$out" "busy warning names load and cores"
out="$(stub_env 4.0 4 2>&1)"; expect_rc 0 $? "env with load equal to the cores exits 0"
expect_eq "load 4.00 (1 min), 0.50 (5 min), 0.25 (15 min); cores 4" "$out" "env line format with a stubbed load"

# 8. The symlink in bin/ and the real file behave the same; a relative --skill path works.
expect_eq "$("$real" print 2>&1)" "$("$bc" print 2>&1)" "bin/ symlink and the skill's tool print the same"
( cd "$tmp" && "$bc" --skill SKILL.md print >/dev/null 2>&1 ); expect_rc 0 $? "relative --skill from another cwd exits 0"

# 9. Positive control: a copy whose report never downgrades the verdict must fail check 6.
mkdir -p "$tmp/mut/bin"
cp "$root/skills/benchmark-checklist/SKILL.md" "$tmp/mut/SKILL.md"
sed 's/^        verdict = "inconclusive"$/        pass/' "$real" > "$tmp/mut/bin/ctlhq-benchmark-checklist"
chmod +x "$tmp/mut/bin/ctlhq-benchmark-checklist"
if cmp -s "$real" "$tmp/mut/bin/ctlhq-benchmark-checklist"; then bad "positive control: the planted defect did not change the tool"; else ok; fi
out="$("$tmp/mut/bin/ctlhq-benchmark-checklist" report "$r2" 2>/dev/null)"
expect_eq "faster: answer 5, answer 1 (unanswered: 2)" "$out" "positive control: the mutant keeps 'faster', so check 6 would catch it"

echo "$pass checks passed"
if [ "$fail" -gt 0 ]; then
	echo "$fail checks failed"
	exit 1
fi
