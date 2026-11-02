#!/usr/bin/env bash
set -u
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
wf="$root/.github/workflows/gate.yml"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/ci-workflow-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
pass=0
fail=0
ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL: $1"; }
expect_rc() { if [ "$1" -eq "$2" ]; then ok; else bad "$3 (expected exit $1, got $2)"; fi; }

commands=("bin/ctlhq-test" "bin/ctlhq-check" "bin/ctlhq-no-comments --diff origin/main...HEAD --strict")
runs() { sed -En 's/^[[:space:]]*(- )?run:[[:space:]]*//p' "$1"; }
missing() {
	local cmd n=0
	for cmd in "${commands[@]}"; do
		runs "$1" | grep -qxF -- "$cmd" || { echo "$cmd"; n=$((n + 1)); }
	done
	return "$n"
}

out="$(missing "$wf")"; expect_rc 0 $? "the workflow runs all three commands (missing: $out)"
grep -Eq '^on: push$|^  push:' "$wf"; expect_rc 0 $? "the workflow runs on push"
grep -Eq '^    runs-on: macos-' "$wf"; expect_rc 0 $? "the job runs on a macOS runner"
grep -Eq '^ +fetch-depth: 0$' "$wf"; expect_rc 0 $? "checkout fetches origin/main for the comment check"
uses="$(grep -E '^[[:space:]]*(- )?uses:' "$wf")"
[ -n "$uses" ]; expect_rc 0 $? "the workflow uses at least one action"
unpinned="$(printf '%s\n' "$uses" | grep -Ev '@[0-9a-f]{40}$')"
[ -z "$unpinned" ]; expect_rc 0 $? "every action is pinned to a full commit hash ($unpinned)"

for cmd in "${commands[@]}"; do
	grep -vxF -- "      - run: $cmd" "$wf" > "$tmp/copy.yml"
	out="$(missing "$tmp/copy.yml")"; rc=$?
	expect_rc 1 "$rc" "control: a copy without '$cmd' is caught (missing: $out)"
done

if [ "$fail" -gt 0 ]; then
	echo "$fail checks failed, $pass checks passed"
	exit 1
fi
echo "$pass checks passed"
