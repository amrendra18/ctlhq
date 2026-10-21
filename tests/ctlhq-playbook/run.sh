#!/usr/bin/env bash
# tests/ctlhq-playbook/run.sh: checks for skills/ctlhq-mode/bin/ctlhq-playbook through bin/ctlhq-playbook.
# Prints "N checks passed" and exits 1 when any check fails. Read-only.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
pb="$root/bin/ctlhq-playbook"
books="$root/skills/ctlhq-mode/playbooks"
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
count() { printf '%s\n' "$2" | grep -Ec -- "$1"; }

# 1. --help.
out="$("$pb" --help 2>&1)"; rc=$?
expect_rc 0 "$rc" "--help exits 0"
expect_grep '^ctlhq-playbook: ' "$(printf '%s\n' "$out" | head -1)" "--help first line is 'ctlhq-playbook: ...'"

# 2. list: 23 rows in SKILL.md order, every file present.
out="$("$pb" list 2>&1)"; rc=$?
expect_rc 0 "$rc" "list exits 0"
expect_eq 23 "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" "list prints 23 rows"
expect_grep '^Investigation +playbooks/investigation.md$' "$(printf '%s\n' "$out" | head -1)" "first row is Investigation"
expect_grep '^Opening a PR +playbooks/opening-a-pr.md$' "$(printf '%s\n' "$out" | tail -1)" "last row is Opening a PR"
expect_eq 0 "$(count '\(missing\)' "$out")" "no row is marked missing"
json="$("$pb" --json list 2>/dev/null)"
expect_eq "23 23" "$(printf '%s' "$json" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(len(d), sum(1 for r in d if r["exists"]))')" "--json list has 23 rows, all existing"

# 3. path: kebab, prefix, ambiguous, unknown, file stem.
out="$("$pb" path bug-fix 2>&1)"; expect_rc 0 $? "path bug-fix exits 0"
expect_eq "$books/bug-fix.md" "$out" "path bug-fix (kebab) resolves"
out="$("$pb" path feat 2>&1)"; expect_rc 0 $? "path feat exits 0"
expect_eq "$books/feature.md" "$out" "path feat (prefix) resolves"
err="$("$pb" path autopilot 2>&1 >/dev/null)"; rc=$?
expect_rc 2 "$rc" "path autopilot (ambiguous) exits 2"
expect_grep "^ambiguous title 'autopilot', 2 candidates:" "$err" "ambiguous lists 2 candidates"
expect_grep '^  Autopilot-full ' "$err" "candidate Autopilot-full listed"
expect_grep '^  Autopilot-stack ' "$err" "candidate Autopilot-stack listed"
err="$("$pb" path nosuch 2>&1 >/dev/null)"; expect_rc 2 $? "path nosuch exits 2"
expect_eq "unknown playbook 'nosuch': no title, kebab name, or file stem in the Playbooks section of SKILL.md matches it. Run \`ctlhq-playbook list\`." "$err" "unknown title names what, why, and the fix"
err="$("$pb" steps nosuch 2>&1 >/dev/null)"; expect_rc 2 $? "steps nosuch exits 2"
expect_grep "^unknown playbook 'nosuch': no title, kebab name, or file stem .* Run \`ctlhq-playbook list\`\.$" "$err" "steps with an unknown title gives the same message"
out="$("$pb" path multi-phase-plan 2>&1)"; expect_eq "$books/multi-phase-plan.md" "$out" "path by file stem resolves"

# 4. steps feature: 8 numbered steps verbatim, then the Reply line.
out="$("$pb" steps feature 2>&1)"; rc=$?
expect_rc 0 "$rc" "steps feature exits 0"
expect_eq 8 "$(count '^[0-9]+\. ' "$out")" "feature has 8 numbered steps"
expect_grep '^1\. `how` over the affected subsystem\.$' "$out" "feature step 1 verbatim"
expect_grep '^   - \*\*Blocking first steps\.\*\* Gates run before fan-out\.$' "$out" "feature step 3 keeps its indented items"
expect_grep '^\*\*Reply:\*\* what you built' "$out" "feature Reply line present"

# 5. steps investigation --checkpoint: 4 steps, the n/a line appended, Reply last.
out="$("$pb" steps investigation --checkpoint 2>&1)"; rc=$?
expect_rc 0 "$rc" "steps investigation --checkpoint exits 0"
expect_eq 4 "$(count '^[0-9]+\. ' "$out")" "investigation has 4 numbered steps"
expect_eq 1 "$(count '^throughput checkpoint: n/a, read-only investigation$' "$out")" "n/a checkpoint line appended once"
expect_grep '^\*\*Reply:\*\* the investigation output' "$(printf '%s\n' "$out" | tail -1)" "Reply is the last line"

# 6. steps shipping: 6 steps and a Reply.
out="$("$pb" steps shipping 2>&1)"; rc=$?
expect_rc 0 "$rc" "steps shipping exits 0"
expect_eq 6 "$(count '^[0-9]+\. ' "$out")" "shipping has 6 numbered steps"
expect_grep '^\*\*Reply:\*\* the verified run' "$out" "shipping Reply line present"

# 7. steps bug-fix --json --checkpoint: 6 steps, 4 checkpoint items, 1 reply; n runs 1..11. Feature carries the items itself (checked in 7b).
json="$("$pb" steps bug-fix --json --checkpoint 2>/dev/null)"; rc=$?
expect_rc 0 "$rc" "steps feature --json --checkpoint exits 0"
expect_eq "7 4 1 1 12 True" "$(printf '%s' "$json" | python3 -c '
import json, sys
d = json.load(sys.stdin)
k = lambda kind: sum(1 for i in d if i["kind"] == kind)
print(k("step"), k("checkpoint"), k("reply"), d[0]["n"], d[-1]["n"], all(i["text"].strip() for i in d))
')" "--json shape: 7 steps, 4 checkpoint items, 1 reply, n 1..12, no empty text"
expect_eq 'Check ownership before any work.' "$(printf '%s' "$json" | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["text"][:32])')" "--json step 1 text drops the number"

# 7b. steps feature --checkpoint: Feature already carries the four items, so nothing is appended.
fout="$("$pb" steps feature --checkpoint 2>/dev/null)"
expect_eq 1 "$(count 'Blocking first steps' "$fout")" "feature --checkpoint lists the checkpoint items once"

# 8. steps opening-a-pr: no numbered list, falls back to the 10 bold-labelled paragraphs.
out="$("$pb" steps opening-a-pr 2>/dev/null)"
err="$("$pb" steps opening-a-pr 2>&1 >/dev/null)"
"$pb" steps opening-a-pr >/dev/null 2>&1; expect_rc 0 $? "steps opening-a-pr exits 0"
expect_grep 'no numbered list; using its 10 bold-labelled paragraphs' "$err" "fallback is announced on stderr"
expect_eq 10 "$(count '^\*\*[A-Z]' "$out")" "opening-a-pr yields 10 labelled items"
expect_grep '^- `## Why`: ' "$out" "the Descriptions bullets ride along"

# 9. Usage errors.
"$pb" >/dev/null 2>&1; expect_rc 2 $? "no command exits 2"
"$pb" steps >/dev/null 2>&1; expect_rc 2 $? "steps without a title exits 2"
"$pb" bogus >/dev/null 2>&1; expect_rc 2 $? "unknown command exits 2"
"$pb" --bogus list >/dev/null 2>&1; expect_rc 2 $? "unknown option exits 2"
"$pb" list extra >/dev/null 2>&1; expect_rc 2 $? "list with a title exits 2"

# 10. Every listed playbook resolves and yields at least one step.
for k in $(printf '%s' "$("$pb" --json list 2>/dev/null)" | python3 -c 'import json,sys; print(" ".join(r["kebab"] for r in json.load(sys.stdin)))'); do
	p="$("$pb" path "$k" 2>/dev/null)"; rc=$?
	if [ "$rc" -eq 0 ] && [ -f "$p" ]; then ok; else bad "path $k (exit $rc, $p)"; fi
	n="$("$pb" steps "$k" --json 2>/dev/null | python3 -c 'import json,sys; print(sum(1 for i in json.load(sys.stdin) if i["kind"]=="step"))' 2>/dev/null)"
	if [ -n "$n" ] && [ "$n" -ge 1 ]; then ok; else bad "steps $k returned no step"; fi
done

echo "$pass checks passed"
if [ "$fail" -gt 0 ]; then
	echo "$fail checks failed"
	exit 1
fi
