#!/usr/bin/env bash
# tests/validate-foundation/run.sh: checks for skills/project-foundation/scripts/validate_foundation.py,
# the four-document mode and the --single-file mode (README.md plus AGENTS.md).
# Synthetic fixtures. Prints "N checks passed" and exits 1 when any check fails.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
vf="${VALIDATE_FOUNDATION:-$root/skills/project-foundation/scripts/validate_foundation.py}"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/validate-foundation-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
pass=0
fail=0
ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL: $1"; }
expect_rc() { if [ "$1" -eq "$2" ]; then ok; else bad "$3 (expected exit $1, got $2)"; fi; }
expect_eq() { if [ "$1" = "$2" ]; then ok; else bad "$3 (expected '$1', got '$2')"; fi; }
expect_grep() { if printf '%s\n' "$2" | grep -Eq -- "$1"; then ok; else bad "$3 (no line matches: $1)"; fi; }

# Fixtures: a personal project with README.md and AGENTS.md only.
mkdir -p "$tmp/one"
printf '# Tool\n\nWhat it does.\n\n## Requirements\n\n- **REQ-01:** It runs.\n\n## Plan\n\nREQ-01 first. See [agents](AGENTS.md).\n' > "$tmp/one/README.md"
printf '# Agents\n\nRead README.md first.\n' > "$tmp/one/AGENTS.md"

# 1. --single-file accepts README.md plus AGENTS.md.
out="$(python3 "$vf" --single-file "$tmp/one")"; expect_rc 0 $? "--single-file with README.md and AGENTS.md exits 0"
expect_grep '^RESULT: PASS ' "$out" "--single-file result line"

# 2. The same folder without the flag needs the four documents (control).
out="$(python3 "$vf" "$tmp/one")"; expect_rc 1 $? "four-document mode on the same folder exits 1"
expect_eq 3 "$(printf '%s\n' "$out" | grep -c '^FAIL: missing required file: ')" "three of the four documents missing"

# 3. --single-file still checks its two files.
rm "$tmp/one/AGENTS.md"
out="$(python3 "$vf" --single-file "$tmp/one")"; expect_rc 1 $? "--single-file without AGENTS.md exits 1"
expect_grep '^FAIL: missing required file: AGENTS.md$' "$out" "missing AGENTS.md named"
printf '# Agents\n\nTODO\n' > "$tmp/one/AGENTS.md"
out="$(python3 "$vf" --single-file "$tmp/one")"; expect_rc 1 $? "--single-file with a TODO exits 1"
expect_grep "^FAIL: AGENTS.md:3 contains unresolved marker 'TODO'$" "$out" "marker found in AGENTS.md"
printf '# Agents\n\nRead README.md.\n' > "$tmp/one/AGENTS.md"
printf '# Tool\n\n- **REQ-01:** a\n- **REQ-01:** b\n\nSee [gone](gone.md).\n' > "$tmp/one/README.md"
out="$(python3 "$vf" --single-file "$tmp/one")"; expect_rc 1 $? "--single-file with a duplicate id and a broken link exits 1"
expect_grep 'defines requirement identifiers more than once: REQ-01' "$out" "duplicate id in README.md found"
expect_grep '^FAIL: README.md has unresolved local link: gone.md$' "$out" "broken link in README.md found"

# 4. Four-document mode accepts a full set.
mkdir -p "$tmp/four"
printf '# Agents\n\nRules.\n' > "$tmp/four/AGENTS.md"
printf '# Product\n\n- **REQ-01:** It runs.\n' > "$tmp/four/PRD.md"
printf '# Plan\n\nREQ-01 first.\n' > "$tmp/four/ENGINEERING_PLAN.md"
printf '# Principles\n\nSmall.\n' > "$tmp/four/ENGINEERING_PRINCIPLES.md"
out="$(python3 "$vf" "$tmp/four")"; expect_rc 0 $? "four documents exit 0"
expect_grep '^RESULT: PASS \(0 warning' "$out" "four documents, no warnings"

echo "$pass checks passed"
[ "$fail" -eq 0 ] || { echo "$fail checks failed"; exit 1; }
