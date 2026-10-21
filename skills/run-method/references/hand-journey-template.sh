#!/bin/sh
# Operator acceptance script (sign-off 3). Lives outside the repository.
# Runs the by-machine steps on the real data and prints "want" next to "got".
# Ends by listing the by-hand steps. The operator says in their own words
# whether each step did what it says. Nothing here counts as acceptance.
set -u
TOOL="<absolute path to the built tool>"
STAMP="journey-$(date +%s)"
echo "== before: repositories clean?"
for r in <repo one> <repo two>; do echo "$r: $(cd "$r" && git status --short | wc -l | tr -d ' ') changed (want 0)"; done
step() { n="$1"; want="$2"; shift 2; echo; echo "== Step $n: $* (want exit $want)"; start=$(date +%s); "$@"; code=$?; echo "exit $code (want $want), $(( $(date +%s) - start )) s"; }
step 1 0 "$TOOL" --version
step 2 0 "$TOOL" <first real command>
step 3 0 "$TOOL" <command that uses $STAMP so the result is fresh>
step 4 <n> "$TOOL" <command that must refuse, with its exit code>
echo
echo "== after: repositories still clean?"
for r in <repo one> <repo two>; do echo "$r: $(cd "$r" && git status --short | wc -l | tr -d ' ') changed (want 0)"; done
echo
echo "By hand:"
echo "  Step 5: <open a fresh agent session and ask it X; look for Y>"
echo "  Step 6: <...>"
echo "Say in your own words whether each step did what it says."
