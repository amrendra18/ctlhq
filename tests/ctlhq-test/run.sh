#!/usr/bin/env bash
# tests/ctlhq-test/run.sh: checks for bin/ctlhq-test against a synthetic tests/ folder.
# The real suite is never run from here, so ctlhq-test cannot call itself.
# Prints "N checks passed" and exits 1 when any check fails.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
ft="$root/bin/ctlhq-test"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
pass=0
fail=0
ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL: $1"; }
expect_rc() { if [ "$1" -eq "$2" ]; then ok; else bad "$3 (expected exit $1, got $2)"; fi; }
expect_eq() { if [ "$1" = "$2" ]; then ok; else bad "$3 (expected '$1', got '$2')"; fi; }
expect_grep() { if printf '%s\n' "$2" | grep -Eq -- "$1"; then ok; else bad "$3 (no line matches: $1)"; fi; }

# Fixture: four scripts. "liar" prints a success line but exits 3, so only the real exit code tells.
mk() { mkdir -p "$tmp/repo/tests/$1"; printf '#!/usr/bin/env bash\n%s\n' "$2" > "$tmp/repo/tests/$1/run.sh"; }
mk alpha 'echo "first line"; echo "3 checks passed"; exit 0'
mk beta 'for i in $(seq 1 20); do echo "line $i"; done; echo "2 checks failed"; exit 1'
mk liar 'echo "5 checks passed" | tail -1; exit 3'
mk slow 'sleep 30; echo never'
mkdir -p "$tmp/repo/tests/no-script"
mkdir -p "$tmp/empty/tests"

# 1. --help
out="$("$ft" --help 2>&1)"; rc=$?
expect_rc 0 "$rc" "--help exits 0"
expect_grep '^ctlhq-test: ' "$(printf '%s\n' "$out" | head -1)" "--help first line is 'ctlhq-test: ...'"

# 2. All passing scripts: exit 0, numbered line, summary.
out="$("$ft" --root "$tmp/repo" --only alpha 2>&1)"; rc=$?
expect_rc 0 "$rc" "--only alpha exits 0"
expect_grep '^1\. alpha  exit 0  [0-9.]+ s  3 checks passed$' "$out" "alpha line shows exit 0 and the last output line"
expect_grep '^scripts 1 \| exit 0: 1 \| non-zero: 0 \| skipped: 0 \| seconds [0-9.]+$' "$out" "summary for one passing script"

# 3. Mixed run with a timeout: exit 1, every script numbered in name order.
start=$(date +%s)
out="$("$ft" --root "$tmp/repo" --timeout 2 2>&1)"; rc=$?
took=$(( $(date +%s) - start ))
expect_rc 1 "$rc" "mixed run exits 1"
expect_grep '^1\. alpha +exit 0 ' "$out" "line 1 is alpha"
expect_grep '^2\. beta +exit 1 .* 2 checks failed$' "$out" "line 2 is beta with exit 1"
expect_grep '^3\. liar +exit 3 .* 5 checks passed$' "$out" "liar shows exit 3 despite its success text"
expect_grep '^4\. slow +exit timeout ' "$out" "slow script shows exit timeout"
expect_grep '^scripts 4 \| exit 0: 1 \| non-zero: 3 \| ' "$out" "summary counts 3 non-zero"
expect_grep '^     line 20$' "$out" "a failing script prints its tail, indented"
if printf '%s\n' "$out" | grep -q '^     line 5$'; then bad "tail is limited to 15 lines"; else ok; fi
if printf '%s\n' "$out" | grep -q 'no-script'; then bad "a folder without run.sh is skipped"; else ok; fi
if [ "$took" -lt 20 ]; then ok; else bad "timeout stops the script and its children (took ${took} s)"; fi

# 4. --json
json="$("$ft" --root "$tmp/repo" --only alpha --only liar --json 2>/dev/null)"; rc=$?
expect_rc 1 "$rc" "--json with a failing script exits 1"
expect_eq "2 alpha:0 liar:3" "$(printf '%s' "$json" | python3 -I -c 'import json,sys; d=json.load(sys.stdin); print(len(d), " ".join("%s:%s" % (r["name"], r["exit"]) for r in d))')" "--json rows carry name and exit"

# 5. Usage errors and nothing found.
"$ft" --root "$tmp/repo" --only nosuch >/dev/null 2>&1; expect_rc 2 $? "unknown --only name exits 2"
"$ft" --bogus >/dev/null 2>&1; expect_rc 2 $? "unknown option exits 2"
"$ft" --timeout soon >/dev/null 2>&1; expect_rc 2 $? "bad --timeout exits 2"
"$ft" --timeout 0 >/dev/null 2>&1; expect_rc 2 $? "--timeout 0 exits 2"
"$ft" --only >/dev/null 2>&1; expect_rc 2 $? "--only without a value exits 2"
"$ft" --root "$tmp/empty" >/dev/null 2>&1; expect_rc 1 $? "no scripts exits 1"
"$ft" --root "$tmp/missing" >/dev/null 2>&1; expect_rc 1 $? "missing tests/ folder exits 1"

# 6. The bun-tests row runs bun test, then bun run typecheck, in skills/ctlhq-mode/scripts, after a
# locked install when node_modules/ is missing there. Without bun it is skipped and does not fail.
# A fake bun logs its folder and arguments, and fails the command named in FAKE_BUN_FAIL.
bunroot="$tmp/bunrepo"
mkdir -p "$bunroot/tests" "$bunroot/skills/ctlhq-mode/scripts/orch"
cp -R "$tmp/repo/tests/alpha" "$bunroot/tests/"
: >"$bunroot/skills/ctlhq-mode/scripts/orch/orch.test.ts"
scripts_dir="$(cd "$bunroot/skills/ctlhq-mode/scripts" && pwd -P)"
fakebun="$tmp/fakebun"
mkdir -p "$fakebun"
cat >"$fakebun/bun" <<'EOF'
#!/bin/sh
echo "$(pwd -P) $*" >>"$FAKE_BUN_LOG"
if [ "$1" = install ]; then mkdir node_modules; fi
echo "bun $1 done"
if [ "$*" = "${FAKE_BUN_FAIL:-}" ]; then echo "error TS2322: fake type error"; exit 1; fi
exit 0
EOF
chmod +x "$fakebun/bun"
log="$tmp/bun.log"
out="$(PATH="$fakebun:$PATH" FAKE_BUN_LOG="$log" "$ft" --root "$bunroot" 2>&1)"; rc=$?
expect_rc 0 "$rc" "a passing bun test exits 0"
expect_grep '^2\. bun-tests +exit 0 +[0-9.]+ s +bun run done$' "$out" "the bun-tests row comes after the scripts"
expect_eq "$scripts_dir install --frozen-lockfile|$scripts_dir test|$scripts_dir run typecheck" "$(paste -sd '|' "$log")" "without node_modules/ the row installs from the lock file, then runs bun test and the type check, in the scripts folder"
expect_grep '^scripts 2 \| exit 0: 2 \| non-zero: 0 \| skipped: 0 \| ' "$out" "the summary counts the bun-tests row"
: >"$log"
out="$(PATH="$fakebun:$PATH" FAKE_BUN_LOG="$log" FAKE_BUN_FAIL=test "$ft" --root "$bunroot" --only bun-tests 2>&1)"; rc=$?
expect_rc 1 "$rc" "a failing bun test exits 1"
expect_grep '^1\. bun-tests +exit 1 ' "$out" "--only bun-tests runs the row alone"
expect_eq "$scripts_dir test" "$(cat "$log")" "with node_modules/ present the row runs no install, and a failed bun test skips the type check"
: >"$log"
out="$(PATH="$fakebun:$PATH" FAKE_BUN_LOG="$log" FAKE_BUN_FAIL="run typecheck" "$ft" --root "$bunroot" --only bun-tests 2>&1)"; rc=$?
expect_rc 1 "$rc" "a type error exits 1"
expect_grep '^1\. bun-tests +exit 1 .*fake type error$' "$out" "a type error shows on the bun-tests row"
expect_eq "$scripts_dir test|$scripts_dir run typecheck" "$(paste -sd '|' "$log")" "after bun test passes, the row runs bun run typecheck"
nobun="$tmp/nobun"
mkdir -p "$nobun"
for t in python3 bash; do ln -s "$(command -v "$t")" "$nobun/$t"; done
out="$(PATH="$nobun" "$ft" --root "$bunroot" 2>&1)"; rc=$?
expect_rc 0 "$rc" "without bun the run exits 0"
expect_grep '^2\. bun-tests +skipped: bun not installed$' "$out" "without bun the row says skipped"
expect_grep '^scripts 2 \| exit 0: 1 \| non-zero: 0 \| skipped: 1 \| ' "$out" "the summary counts the skipped row apart"
json="$(PATH="$nobun" "$ft" --root "$bunroot" --only bun-tests --json 2>/dev/null)"
expect_eq "bun-tests:skipped" "$(printf '%s' "$json" | python3 -I -c 'import json,sys; print(" ".join("%s:%s" % (r["name"], r["exit"]) for r in json.load(sys.stdin)))')" "--json marks the row skipped"

# 7. The row's locked install resolves nothing by name: package.json pins every package to the exact
# version bun.lock records, and the lock's own copy of package.json says the same.
pins="$(python3 -I - "$root/skills/ctlhq-mode/scripts" <<'PY'
import json, re, sys
from pathlib import Path
d = Path(sys.argv[1])
pkg = json.loads((d / "package.json").read_text())
lock = json.loads(re.sub(r",(\s*[}\]])", r"\1", (d / "bun.lock").read_text()))
ws = lock["workspaces"][""]
for kind in ("dependencies", "devDependencies"):
    for name, spec in sorted(pkg.get(kind, {}).items()):
        locked = lock["packages"][name][0].rsplit("@", 1)[1]
        print(f"{name} {spec} {ws[kind][name]} {locked}")
PY
)"
expect_grep '^bun-types ' "$pins" "the pin check reads bun-types"
printf '%s\n' "$pins" | while read -r name spec lockspec locked; do
	[ "$spec" = "$locked" ] && [ "$lockspec" = "$locked" ] || echo "FAIL: $name is \"$spec\" in package.json and \"$lockspec\" in bun.lock, but bun.lock resolved $locked"
done >"$tmp/pins.out"
if [ -s "$tmp/pins.out" ]; then fail=$((fail + 1)); cat "$tmp/pins.out"; else ok; fi

echo "$pass checks passed"
if [ "$fail" -gt 0 ]; then
	echo "$fail checks failed"
	exit 1
fi
