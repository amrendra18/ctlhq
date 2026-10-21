#!/usr/bin/env bash
# tests/ctlhq-doctor/run.sh: checks for bin/ctlhq-doctor on this machine.
# Prints "N checks passed" and exits 1 when any check fails. Writes only under
# a temporary folder (TMPDIR honoured); never touches ~/.ctlhq.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
doctor="$root/bin/ctlhq-doctor"
pass=0
fail=0
ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL: $1"; }
expect_rc() { # expected actual label
	if [ "$1" -eq "$2" ]; then ok; else bad "$3 (expected exit $1, got $2)"; fi
}
expect_grep() { # pattern text label
	if printf '%s\n' "$2" | grep -Eq -- "$1"; then ok; else bad "$3 (no line matches: $1)"; fi
}
tmp="$(mktemp -d "${TMPDIR:-/tmp}/ctlhq-doctor-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

# 1. --help answers with the name line and exit 0.
out="$("$doctor" --help 2>&1)"; rc=$?
expect_rc 0 "$rc" "--help exits 0"
expect_grep '^ctlhq-doctor: ' "$(printf '%s\n' "$out" | head -1)" "--help first line is 'ctlhq-doctor: ...'"

# 2. The default run exits 0 on this machine (required checks pass).
out="$("$doctor" 2>&1)"; rc=$?
expect_rc 0 "$rc" "default run exits 0"
expect_grep '^ok +python3 ' "$out" "python3 is ok"
expect_grep '^ok +bash ' "$out" "bash is ok"
expect_grep '^ok +git ' "$out" "git is ok"
expect_grep '^ok +repo root +'"$root" "$out" "repo root is ok"
expect_grep '^ok +bin/\* --help +([0-9]+) of \1 answer' "$out" "every bin/ tool answers --help"
expect_grep '^summary: required [0-9]+/[0-9]+ ok, optional [0-9]+/[0-9]+ ok.*; exit 0$' "$out" "summary line"

# 3. bun and gh: missing with an install line here; ok when a machine has them.
if command -v bun >/dev/null 2>&1; then
	expect_grep '^ok +bun ' "$out" "bun is ok (installed on this machine)"
else
	expect_grep '^missing +bun +install: curl -fsSL https://bun.sh/install \| bash +needed by ctlhq-watch-pr, ctlhq-orch' "$out" "bun missing with install line and needed-by"
fi
if command -v gh >/dev/null 2>&1; then
	expect_grep '^ok +gh ' "$out" "gh is ok (installed on this machine)"
else
	expect_grep '^missing +gh +install: (brew install gh|apt-get install -y gh) +needed by ctlhq-watch-pr' "$out" "gh missing with install line and needed-by"
fi

# 4. --json parses and carries the same verdict.
json="$("$doctor" --json 2>/dev/null)"; rc=$?
expect_rc 0 "$rc" "--json exits 0"
verdict="$(printf '%s' "$json" | python3 -c '
import json, sys
d = json.load(sys.stdin)
names = [c["name"] for c in d["checks"]]
bun = next(c for c in d["checks"] if c["name"] == "bun")
print(d["summary"]["exit"], len(d["tools"]) > 0, "python3" in names and "models.toml" in names,
      bun["status"] in ("ok", "missing"), bool(bun["install"]) or bun["status"] == "ok")
' 2>&1)"
expect_grep '^0 True True True True$' "$verdict" "--json shape: exit 0, tools listed, checks named, bun has install line"

# 5. A valid models file is ok; the original is never changed (copy validated).
"$root/bin/ctlhq-models" --file "$tmp/valid.toml" init >/dev/null 2>&1
cp "$tmp/valid.toml" "$tmp/valid.before"
out="$("$doctor" --no-tools --models "$tmp/valid.toml" 2>&1)"; rc=$?
expect_rc 0 "$rc" "--models valid exits 0"
expect_grep '^ok +models.toml +'"$tmp"'/valid.toml valid' "$out" "valid models file is ok"
if cmp -s "$tmp/valid.toml" "$tmp/valid.before"; then ok; else bad "doctor changed the models file it validated"; fi

# 6. An invalid models file is reported as invalid and stays optional (exit 0).
printf 'budget = "huge"\n' > "$tmp/bad.toml"
out="$("$doctor" --no-tools --models "$tmp/bad.toml" 2>&1)"; rc=$?
expect_rc 0 "$rc" "--models invalid still exits 0 (optional)"
expect_grep '^invalid +models.toml +'"$tmp"'/bad.toml: ' "$out" "invalid models file is reported"

# 7. A missing models file prints the create line.
out="$("$doctor" --no-tools --models "$tmp/none.toml" 2>&1)"; rc=$?
expect_rc 0 "$rc" "--models missing exits 0"
expect_grep '^missing +models.toml +.*create: ctlhq-models init' "$out" "missing models file names ctlhq-models init"

# 8. Usage errors exit 2.
"$doctor" --bogus >/dev/null 2>&1; expect_rc 2 $? "--bogus exits 2"
"$doctor" --models >/dev/null 2>&1; expect_rc 2 $? "--models without a path exits 2"
"$doctor" extra >/dev/null 2>&1; expect_rc 2 $? "stray argument exits 2"

# 9. node is required at 22.18 or newer; Google Chrome and first-commit are reported. The doctor
# runs with a PATH of this folder only, so the machine's own node and first-commit stay out.
fake="$tmp/fakebin"
mkdir -p "$fake"
for t in python3 bash git; do ln -s "$(command -v "$t")" "$fake/$t"; done
fakenode() { printf '#!/bin/sh\necho v%s\n' "$1" >"$fake/node"; chmod +x "$fake/node"; }
dr() { out="$(PATH="$fake" CTLHQ_CHROME="$1" "$doctor" --no-tools --models "$tmp/none.toml" 2>&1)"; rc=$?; }
dr "$tmp/no-chrome"
expect_rc 1 "$rc" "without node the doctor exits 1"
expect_grep '^missing +node +install: .+ +needed by ctlhq-plan-lint, ctlhq-browser, ctlhq-icon-sheet, the ctlhq-plan-lint and stand-ins tests$' "$out" "a missing node is reported with its install line"
fakenode 22.17.9; dr "$tmp/no-chrome"
expect_rc 1 "$rc" "node 22.17.9 exits 1"
expect_grep '^old +node +22\.17\.9 \(.*\); needs 22\.18 or newer; install: ' "$out" "node 22.17.9 is old"
fakenode 22.18.0; dr "$tmp/no-chrome"
expect_rc 0 "$rc" "node 22.18.0 exits 0 without Chrome and first-commit"
expect_grep '^ok +node +22\.18\.0 ' "$out" "node 22.18.0 is ok"
expect_grep '^missing +Google Chrome +install: .+ +needed by ctlhq-browser, ctlhq-icon-sheet, and their tests$' "$out" "a missing Chrome is reported"
expect_grep '^missing +first-commit +install: install first-commit from https://github.com/amrendra18/first-commit and put it on PATH +needed by /start-project and /run-method only$' "$out" "a missing first-commit names the repository placeholder and its two skills"
expect_grep '^missing +bun +install: .+ +needed by ctlhq-watch-pr, ctlhq-orch, and the TypeScript unit tests \(the bun-tests row of ctlhq-test\)$' "$out" "a missing bun names the unit tests it runs"
printf '#!/bin/sh\necho "Google Chrome 130.0.6723.58"\n' >"$tmp/chrome"
printf '#!/bin/sh\ntouch "%s"\n' "$tmp/first-commit-ran" >"$fake/first-commit"
chmod +x "$tmp/chrome" "$fake/first-commit"
dr "$tmp/chrome"
expect_grep '^ok +Google Chrome +130\.0\.6723 \('"$tmp"'/chrome\)' "$out" "CTLHQ_CHROME names the Chrome that is reported"
expect_grep '^ok +first-commit +found \('"$fake"'/first-commit\)' "$out" "first-commit on PATH is found"
if [ -e "$tmp/first-commit-ran" ]; then bad "the doctor never runs first-commit"; else ok; fi

echo "$pass checks passed"
if [ "$fail" -gt 0 ]; then
	echo "$fail checks failed"
	exit 1
fi
