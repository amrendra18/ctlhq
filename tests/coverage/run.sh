#!/usr/bin/env bash
# tests/coverage/run.sh: checks `bin/ctlhq-coverage`, which builds the coverage table at
# runtime from skills/, bin/, and tests/, plus tests/coverage/reasons.tsv.
# Part 1 runs the command on a temp fixture repository, once clean and once per planted defect
# (the positive controls: a new skill with no test or reason; a stale reason; a deleted test;
# and malformed reason rows). Part 2 checks this repository exits 0.
# Prints "N checks passed" and exits 1 when any check fails. Writes only under a temp folder.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
cov="$root/bin/ctlhq-coverage"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/coverage-check.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
pass=0
fail=0
ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL: $1"; }
expect_rc() { if [ "$1" -eq "$2" ]; then ok; else bad "$3 (expected exit $1, got $2)"; fi; }
expect_eq() { if [ "$1" = "$2" ]; then ok; else bad "$3 (expected '$1', got '$2')"; fi; }
expect_grep() { if printf '%s\n' "$2" | grep -Eq -- "$1"; then ok; else bad "$3 (no line matches: $1)"; fi; }

# 0. Usage.
out="$("$cov" --help 2>&1)"; expect_rc 0 $? "--help exits 0"
expect_grep '^ctlhq-coverage: ' "$(printf '%s\n' "$out" | head -1)" "--help first line is 'ctlhq-coverage: ...'"
expect_grep '^  ctlhq-coverage \[--json\] \[--root DIR\]$' "$out" "--help shows the usage line"
"$cov" --bogus >/dev/null 2>&1; expect_rc 2 $? "an unknown option exits 2"
"$cov" --root "$tmp/nosuch" >/dev/null 2>&1; expect_rc 2 $? "a missing --root exits 2"

# 1. Fixture repository.
#    skills: alpha (tests/alpha/run.sh), beta (ships bin/btool, which has a test),
#            gamma (no test: its reason is in the reasons file)
#    tools:  xtool (tests/xtool/run.sh), btool (link into skills/beta/bin), ytool (its text names
#            tests/shared/run.sh)
#    ignored: bin/__pycache__, bin/.hidden
fx="$tmp/fx"
mkdir -p "$fx/skills/alpha" "$fx/skills/beta/bin" "$fx/skills/gamma" "$fx/bin/__pycache__" \
	"$fx/tests/alpha" "$fx/tests/xtool" "$fx/tests/btool" "$fx/tests/shared" "$fx/tests/coverage"
for s in alpha beta gamma; do printf -- '---\nname: %s\n---\n' "$s" >"$fx/skills/$s/SKILL.md"; done
printf '#!/bin/sh\n' >"$fx/skills/beta/bin/btool"
ln -s ../skills/beta/bin/btool "$fx/bin/btool"
printf '#!/bin/sh\n' >"$fx/bin/xtool"
printf '#!/bin/sh\n# tested by tests/shared/run.sh\n' >"$fx/bin/ytool"
printf '#!/bin/sh\n' >"$fx/bin/.hidden"
touch "$fx/tests/alpha/run.sh" "$fx/tests/xtool/run.sh" "$fx/tests/btool/run.sh" "$fx/tests/shared/run.sh"
reasons="$fx/tests/coverage/reasons.tsv"
printf 'item\tkind\treason\ngamma\tskill\tjudgment skill with no command\n' >"$reasons"
cp "$reasons" "$tmp/reasons.good"

out="$("$cov" --root "$fx" 2>&1)"; rc=$?
expect_rc 0 "$rc" "clean fixture exits 0"
expect_grep '^\| # \| item \| kind \| tests \| reason \| status \|$' "$out" "numbered table header"
expect_eq 6 "$(printf '%s\n' "$out" | grep -c '^| [0-9]')" "6 numbered rows: 3 skills and 3 tools (no __pycache__, no dotfile)"
expect_grep '^\| [0-9]+ \| alpha \| skill \| tests/alpha/run.sh \| - \| covered \|$' "$out" "a skill is covered by tests/<skill>/run.sh"
expect_grep '^\| [0-9]+ \| beta \| skill \| tests/btool/run.sh \| - \| covered \|$' "$out" "a skill is covered by the test of the tool it ships"
expect_grep '^\| [0-9]+ \| gamma \| skill \| - \| judgment skill with no command \| reason \|$' "$out" "a skill with no test shows its reason"
expect_grep '^\| [0-9]+ \| xtool \| tool \| tests/xtool/run.sh \| - \| covered \|$' "$out" "a tool is covered by tests/<tool>/run.sh"
expect_grep '^\| [0-9]+ \| ytool \| tool \| tests/shared/run.sh \| - \| covered \|$' "$out" "a test the tool names covers it"
expect_grep '^items 6 \(3 skills, 3 tools\) \| covered 5 \| reason 1 \| problems 0$' "$out" "summary line"
json="$("$cov" --root "$fx" --json 2>&1)"; rc=$?
expect_rc 0 "$rc" "--json exits 0"
expect_eq "6 0 covered tests/coverage/reasons.tsv" "$(printf '%s' "$json" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(len(d["items"]), len(d["problems"]), [i for i in d["items"] if i["item"] == "xtool"][0]["status"], d["reasons_file"])')" "--json lists 6 items, 0 problems, xtool covered, the reasons file"

# variant <label> <expected line regex>: run on the fixture as it stands now; expect exit 1.
variant() {
	local o r
	o="$("$cov" --root "$fx" 2>&1)"; r=$?
	expect_rc 1 "$r" "control $1: exits 1"
	expect_grep "$2" "$o" "control $1: reported"
}
restore() { cp "$tmp/reasons.good" "$reasons"; }

# 2. Planted defects.
mkdir -p "$fx/skills/delta"; printf -- '---\nname: delta\n---\n' >"$fx/skills/delta/SKILL.md"
variant "new skill with no row" '^problem: skill `delta` has no test and no reason in tests/coverage/reasons.tsv$'
o="$("$cov" --root "$fx" 2>&1)"
expect_grep '^\| [0-9]+ \| delta \| skill \| - \| - \| missing \|$' "$o" "control new skill: its row says missing"
rm -rf "$fx/skills/delta"

printf 'alpha\tskill\tno test yet\n' >>"$reasons"
variant "stale reason" '^problem: reasons.tsv:3: stale reason: skill `alpha` is covered \(tests/alpha/run.sh\); delete the row$'
restore

rm "$fx/tests/xtool/run.sh"
variant "deleted test" '^problem: tool `xtool` has no test and no reason in tests/coverage/reasons.tsv$'
touch "$fx/tests/xtool/run.sh"

printf 'ghost\ttool\tgone\n' >>"$reasons"
variant "reason for nothing" '^problem: reasons.tsv:3: stale reason: tool `ghost` does not exist \(bin/ghost\); delete the row$'
restore
printf 'gamma\tskill\tagain\n' >>"$reasons"
variant "duplicate reason" '^problem: reasons.tsv:3: second row for skill `gamma` \(first on line 2\)$'
restore
printf 'gamma\tagent\tr\n' >>"$reasons"
variant "bad kind" '^problem: reasons.tsv:3: kind `agent` must be skill or tool$'
restore
printf 'gamma\tskill\n' >>"$reasons"
variant "two cells" '^problem: reasons.tsv:3: row has 2 cells, needs 3 \(item, kind, reason\)$'
restore
printf 'item\tkind\treason\ngamma\tskill\t \n' >"$reasons"
variant "empty reason" '^problem: reasons.tsv:2: `gamma`: the reason is empty$'
restore
sed -i.bak '1s/reason/why/' "$reasons"
variant "bad header" '^problem: reasons.tsv:1: header must be: item kind reason$'
restore
rm "$reasons"
variant "no reasons file" '^problem: skill `gamma` has no test and no reason in tests/coverage/reasons.tsv$'
restore
out="$("$cov" --root "$fx" 2>&1)"; expect_rc 0 $? "fixture is clean again after the controls"

# 3. A test that checks every SKILL.md (tests/skill-contract/run.sh) covers every skill, so the
#    reason row for gamma turns stale; with that row gone, the fixture is clean again.
mkdir -p "$fx/tests/skill-contract"; touch "$fx/tests/skill-contract/run.sh"
variant "skill-contract covers every skill" '^problem: reasons.tsv:2: stale reason: skill `gamma` is covered \(tests/skill-contract/run.sh\); delete the row$'
printf 'item\tkind\treason\n' >"$reasons"
out="$("$cov" --root "$fx" 2>&1)"; rc=$?
expect_rc 0 "$rc" "with skill-contract and no reason rows, the fixture exits 0"
expect_grep '^\| [0-9]+ \| gamma \| skill \| tests/skill-contract/run.sh \| - \| covered \|$' "$out" "gamma is covered by skill-contract"
expect_grep '^\| [0-9]+ \| alpha \| skill \| tests/alpha/run.sh, tests/skill-contract/run.sh \| - \| covered \|$' "$out" "alpha lists its own test and skill-contract"
expect_grep '^\| [0-9]+ \| xtool \| tool \| tests/xtool/run.sh \| - \| covered \|$' "$out" "skill-contract does not cover tools"

# 4. This repository.
out="$("$cov" 2>&1)"; rc=$?
expect_rc 0 "$rc" "this repository: ctlhq-coverage exits 0"
if [ "$rc" -ne 0 ]; then printf '%s\n' "$out" | grep '^problem: ' | sed 's/^/  /'; fi
nskills="$(find "$root/skills" -mindepth 2 -maxdepth 2 -name SKILL.md | wc -l | tr -d ' ')"
ntools="$(ls "$root/bin" | grep -v '^__pycache__$' | wc -l | tr -d ' ')"
expect_grep "^items $((nskills + ntools)) \\($nskills skills, $ntools tools\\) " "$out" "this repository: one row per skill ($nskills) and per tool ($ntools)"
[ -f "$root/tests/coverage/reasons.tsv" ] && ok || bad "tests/coverage/reasons.tsv exists"
[ -e "$root/evals" ] && bad "evals/ is deleted (the reasons file moved to tests/coverage/)" || ok
echo "repository: $(printf '%s\n' "$out" | grep '^items ')"

if [ "$fail" -gt 0 ]; then
	echo "$fail checks failed, $pass checks passed"
	exit 1
fi
echo "$pass checks passed"
