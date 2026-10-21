#!/bin/sh
# Main-agent review script for one milestone. Run from OUTSIDE the repository
# (for example from the scratchpad) with a throwaway state folder.
# Every check prints "want" next to "got" and its own exit code. The script never
# writes into the repository. Capture each command's exit code directly; never
# read $? after a pipe.
set -u
REPO="${1:?repo path}"
MILESTONE="${2:?milestone name}"
STATE="$(mktemp -d)/state"
TOOL="$REPO/bin/<tool>"            # the built entry point
export <TOOL>_STATE_DIR="$STATE"     # never the real data folder

echo "== $MILESTONE review $(date '+%Y-%m-%d %H:%M')"
echo "== 1. files and tests present (want: every file from the Done when line)"
for f in <path/one> <path/two>; do [ -f "$REPO/$f" ] && echo "ok  $f" || echo "MISSING $f"; done
echo "== 2. stubs, TODOs, home paths (want: no output)"
grep -rn 'TODO\|FIXME\|NotImplemented\|/Users/[a-z]' "$REPO/src" "$REPO/tests" "$REPO/README.md" "$REPO/PLAN.md" 2>/dev/null
echo "== 3. check lanes from outside the repo (want: exit 0 each)"
(cd "$REPO" && ./scripts/check);      echo "fast lane exit $?"
(cd "$REPO" && ./scripts/check full); echo "full lane exit $?"
echo "== 4. hand journey on real data with a throwaway state folder"
"$TOOL" init --state-dir "$STATE";                echo "init exit $? (want 0)"
"$TOOL" <command that proves the milestone>;      echo "exit $? (want 0)"
echo "== 5. privacy grep of results (want: no output)"
"$TOOL" <command> | grep -n '/Users/[a-z]\|/home/[a-z]'
echo "== 6. sibling repositories unchanged (want: all clean)"
for r in <../sibling-one> <../sibling-two>; do echo "$r: $(cd "$REPO/$r" && git status --short | wc -l | tr -d ' ') changed"; done
echo "== 7. line budget (want: under <N>)"
cat "$REPO"/src/**/*.<ext> 2>/dev/null | wc -l
echo "== 8. git status (want: only the expected A and M lines)"
(cd "$REPO" && git status --short)
echo "== 9. real data folder absent (want: absent)"
[ -e "<real data folder>" ] && echo "PRESENT: real data folder was written" || echo "absent"
rm -rf "$(dirname "$STATE")"
