#!/usr/bin/env bash
# tests/ctlhq-audit-report/run.sh: checks for bin/ctlhq-audit-report (skills/project-audit/bin/ctlhq-audit-report) and the texts it enforces.
# Part 1 builds one report that holds the contract and requires exit 0. Part 2 plants one defect per
# variant and requires the checker to refuse it with the right message. Part 3 computes round verdicts
# on the first-commit round counts and on a stalled loop.
# Part 4 checks that the skill and the report contract still say what the tool enforces.
# Prints "N checks passed" and exits 1 when any check fails. Writes only to a temp folder.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
ar="$root/bin/ctlhq-audit-report"
pass=0
fail=0
ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL: $1"; }
expect_rc() { if [ "$1" -eq "$2" ]; then ok; else bad "$3 (expected exit $1, got $2)"; fi; }
expect_grep() { if printf '%s\n' "$2" | grep -Eq -- "$1"; then ok; else bad "$3 (no line matches: $1)"; fi; }
expect_nogrep() { if printf '%s\n' "$2" | grep -Eq -- "$1"; then bad "$3 (a line matches: $1)"; else ok; fi; }

tmp="$(mktemp -d "${TMPDIR:-/tmp}/audit-report-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

# 0. Usage.
out="$("$ar" --help 2>&1)"; expect_rc 0 $? "--help exits 0"
expect_grep '^ctlhq-audit-report: ' "$(printf '%s\n' "$out" | head -1)" "--help first line is 'ctlhq-audit-report: ...'"
"$ar" >/dev/null 2>&1; expect_rc 2 $? "no arguments exits 2"
"$ar" lint x.md >/dev/null 2>&1; expect_rc 2 $? "unknown subcommand exits 2"
"$ar" rounds x.md >/dev/null 2>&1; expect_rc 2 $? "the old rounds subcommand exits 2 (merged into check)"
out="$("$ar" check "$tmp/nowhere.md" 2>&1)"; expect_rc 2 $? "missing file exits 2"
expect_grep '^fix: ' "$out" "missing file prints a fix line"

# 1. A report that holds the contract: 4 findings (0 critical, 1 high, 2 medium, 1 low), round 2.
good="$tmp/good.md"
cat >"$good" <<'MD'
# Audit report

## 1. Audit frame

- Scope: whole repository, standard depth, commit b2c3d4e.
- Round 2. Bar: see section 11.

## 2. Executive result

Fit for local use; one high finding.

## 3. Product and system map

Source: bin/ctlhq-repo-map at b2c3d4e.

## 4. Findings

| # | ID | Title | Severity | Fix kind | Route |
|---|---|---|---|---|---|
| 1 | PA-001 | Save drops edits on a full disk | high | change | fix |
| 2 | PA-002 | No scan for committed tokens | medium | add | milestone |
| 3 | PA-003 | Old export folder still shipped | medium | remove | decision |
| 4 | PA-004 | Help names a renamed flag | low | change | record |

### PA-001: Save drops edits on a full disk

- **Lens:** Security and Reliability
- **Severity:** High
- **Confidence:** High

### PA-002: No scan for committed tokens

- **Severity:** Medium

### PA-003: Old export folder still shipped

- **Severity:** Medium

### PA-004: Help names a renamed flag

- **Severity:** Low

## 5. Simplification and removal plan

None beyond PA-003.

## 6. Test and evidence portfolio

Matrix omitted in this fixture.

## 7. Coverage ledger

All groups checked.

## 8. Open questions and limits

1. PA-003: deleting the export folder removes files users may hold links to. Recommendation: yes, delete it.

## 9. Ordered action plan

1. Fix PA-001.

## 10. Lens scorecard

| # | Lens | Score | Why | Path to 10 |
|---|---|---|---|---|
| 1 | Product and User Experience | 10/10 | none | none needed |

## 11. Rounds and stop

Grant: fixes (PLAN.md section 10, row 12)
Bar: 0 high, 0 medium. Critical counts as high.

| # | Commit | Critical | High | Medium | Low | Serious |
|---|---|---|---|---|---|---|
| 1 | a1b2c3d | 0 | 2 | 12 | 21 | 14 |
| 2 | b2c3d4e | 0 | 1 | 2 | 1 | 3 |

Verdict: continue
MD
out="$("$ar" check "$good" 2>&1)"; expect_rc 0 $? "a report that holds the contract exits 0"
expect_grep '^report contract holds: 4 findings, verdict continue$' "$out" "the good report prints its summary"
expect_grep '^\| 2 \| b2c3d4e \| 0 \| 1 \| 2 \| 1 \| 3 \| fell by 11 \|$' "$out" "check prints the rounds table with the change per round"

# variant NAME OLD NEW: copy the good report with OLD replaced once by NEW (OLD must occur).
variant() {
	python3 - "$good" "$tmp/$1.md" "$2" "$3" <<'PY'
import sys
src, dst, old, new = sys.argv[1:5]
s = open(src).read()
if s.count(old) != 1:
    sys.exit("variant: text not found once: " + old)
open(dst, "w").write(s.replace(old, new))
PY
}
refuse() {  # refuse NAME REGEX LABEL: the checker exits 1 on variant NAME and prints a line matching REGEX.
	local o rc
	o="$("$ar" check "$tmp/$1.md" 2>&1)"; rc=$?
	expect_rc 1 "$rc" "$3: exits 1"
	expect_grep "$2" "$o" "$3: names the problem"
	expect_grep '^  fix: ' "$o" "$3: prints a fix line"
}

# 2. Planted defects, one per variant.
variant no-heading "## 7. Coverage ledger" "## 7. Coverage notes"
refuse no-heading 'no "## 7\. Coverage ledger" heading' "a missing section heading"
variant no-fixkind "| # | ID | Title | Severity | Fix kind | Route |
|---|---|---|---|---|---|" "| # | ID | Title | Severity | Kind | Route |
|---|---|---|---|---|---|"
refuse no-fixkind 'missing: Fix kind' "an index without the Fix kind column"
variant add-fix "| No scan for committed tokens | medium | add | milestone |" "| No scan for committed tokens | medium | add | fix |"
refuse add-fix 'PA-002 adds behavior but is routed to fix' "an add fix routed to fix"
variant record-medium "| Old export folder still shipped | medium | remove | decision |" "| Old export folder still shipped | medium | remove | record |"
refuse record-medium 'PA-003 is medium but routed to record' "a medium finding routed to record"
variant kind-milestone "| Old export folder still shipped | medium | remove | decision |" "| Old export folder still shipped | medium | remove | milestone |"
refuse kind-milestone 'PA-003 is a remove fix but is routed to milestone' "a remove fix routed to milestone"
variant no-grant "Grant: fixes (PLAN.md section 10, row 12)" "The caller asked for fixes."
refuse no-grant 'section 11 has no Grant line' "a missing grant"
variant bad-grant "Grant: fixes (PLAN.md section 10, row 12)" "Grant: maybe"
refuse bad-grant "the Grant line says 'maybe'" "a grant that is neither none nor fixes"
variant no-commit "| 1 | a1b2c3d | 0 | 2 | 12 | 21 | 14 |" "| 1 |  | 0 | 2 | 12 | 21 | 14 |"
refuse no-commit "a rounds row is not" "a round with no commit"
variant bar-words "Bar: 0 high, 0 medium. Critical counts as high." "Bar: 0 high, 0 medium. Low findings are recorded and fixed when cheap."
out="$("$ar" check "$tmp/bar-words.md" 2>&1)"; expect_rc 0 $? "the skill's own bar wording about low findings is accepted"
variant bar-lows "Bar: 0 high, 0 medium. Critical counts as high." "Bar: 0 high, 0 medium. Lows are recorded."
out="$("$ar" check "$tmp/bar-lows.md" 2>&1)"; expect_rc 0 $? "'Lows are recorded' on the bar line is accepted"
variant no-decision "1. PA-003: deleting" "1. The export folder: deleting"
refuse no-decision 'PA-003 is routed to decision but section 8 does not name it' "a decision missing from section 8"
variant bar-all "Bar: 0 high, 0 medium. Critical counts as high." "Bar: 0 findings of any severity."
refuse bar-all 'the bar counts low findings or all findings' "a bar of 0 findings of any severity"
out="$("$ar" check "$tmp/bar-all.md" 2>&1)"
expect_grep 'probe deeper each round' "$out" "the 0-findings refusal gives the reason"
variant bar-low "Bar: 0 high, 0 medium." "Bar: 0 high, 0 medium, 0 low."
refuse bar-low 'the bar counts low findings' "a bar that counts lows"
variant no-bar "Bar: 0 high, 0 medium. Critical counts as high." "The bar was agreed in chat."
refuse no-bar 'section 11 has no Bar line' "a missing bar"
variant bad-sum "| 2 | b2c3d4e | 0 | 1 | 2 | 1 | 3 |" "| 2 | b2c3d4e | 0 | 1 | 2 | 1 | 4 |"
refuse bad-sum 'Serious is 4, but critical plus high plus medium is 3' "a Serious column that is not the sum"
variant drift "| 2 | b2c3d4e | 0 | 1 | 2 | 1 | 3 |" "| 2 | b2c3d4e | 0 | 2 | 2 | 1 | 4 |"
refuse drift 'the last round says 2 high, the findings index holds 1' "a last round that disagrees with the index"
variant bad-verdict "Verdict: continue" "Verdict: bar met"
refuse bad-verdict "the Verdict says 'bar met', the counts give 'continue'" "a verdict chosen against the counts"
variant no-verdict "Verdict: continue" "We keep going."
refuse no-verdict 'section 11 has no Verdict line' "a missing verdict"
variant block-drift "- **Severity:** High" "- **Severity:** Medium"
refuse block-drift 'PA-001 block says Severity medium, the index says high' "a block that disagrees with the index"
variant no-block "### PA-004: Help names a renamed flag" "Help names a renamed flag"
refuse no-block "PA-004 has no '### PA-004' finding block" "an index row with no block"
variant bad-kind "| Save drops edits on a full disk | high | change | fix |" "| Save drops edits on a full disk | high | tweak | fix |"
refuse bad-kind "fix kind 'tweak' is not one of remove, change, add" "an unknown fix kind"
variant bad-number "| 2 | b2c3d4e | 0 | 1 | 2 | 1 | 3 |" "| 3 | b2c3d4e | 0 | 1 | 2 | 1 | 3 |"
refuse bad-number 'round number 3, expected 2' "rounds out of order"

# 3. Round verdicts. rounds_report FILE "ROWS" [BAR] writes a section 11 with the given rows ("commit c h m l" per line).
# The fixture lacks the other sections, so check exits 1, but it still prints the computed verdict first.
rounds_report() {
	{
		printf '## 4. Findings\n\n| # | ID | Title | Severity | Fix kind | Route |\n|---|---|---|---|---|---|\n\n'
		printf '## 11. Rounds and stop\n\nGrant: fixes (test)\nBar: %s\n\n| # | Commit | Critical | High | Medium | Low | Serious |\n|---|---|---|---|---|---|---|\n' "${3:-0 high, 0 medium.}"
		n=0
		printf '%s\n' "$2" | while read -r c cr h m l; do
			[ -n "$c" ] || continue
			n=$((n + 1))
			printf '| %s | %s | %s | %s | %s | %s | %s |\n' "$n" "$c" "$cr" "$h" "$m" "$l" $((cr + h + m))
		done
		printf '\nVerdict: continue\n'
	} >"$1"
}
verdict_of() { "$ar" check "$1" 2>&1 | sed -n 's/^Verdict: //p'; }
# first-commit's audit rounds, high and medium per round 2+12, 2+14, 0+9, 0+5, 0+3, 0+0.
fc="r1 0 2 12 21
r2 0 2 14 23
r3 0 0 9 23
r4 0 0 5 23
r5 0 0 3 26
r6 0 0 0 17"
for k in 1 2 3 4 5; do
	rounds_report "$tmp/fc$k.md" "$(printf '%s\n' "$fc" | head -n "$k")"
	v="$(verdict_of "$tmp/fc$k.md")"
	[ "$v" = "continue" ] && ok || bad "first-commit after round $k: expected continue, got '$v'"
done
rounds_report "$tmp/fc6.md" "$fc"
v="$(verdict_of "$tmp/fc6.md")"; [ "$v" = "bar met" ] && ok || bad "first-commit after round 6: expected 'bar met', got '$v'"
out="$("$ar" check "$tmp/fc2.md" 2>&1)"
expect_grep '^\| 2 \| r2 \| 0 \| 2 \| 14 \| 23 \| 16 \| did not fall \|$' "$out" "round 2 of first-commit shows 'did not fall'"
rounds_report "$tmp/stall.md" "r1 0 0 9 4
r2 0 1 8 6
r3 0 2 8 5"
v="$(verdict_of "$tmp/stall.md")"; [ "$v" = "stop and go to the operator" ] && ok || bad "9, 9, 10: expected stop, got '$v'"
out="$("$ar" check "$tmp/stall.md" 2>&1)"
expect_grep '^why: the serious count failed to fall 2 rounds in a row: 9, 9, 10' "$out" "the stop names the counts"
rounds_report "$tmp/flat2.md" "r1 0 0 5 4
r2 0 0 5 6"
v="$(verdict_of "$tmp/flat2.md")"; [ "$v" = "continue" ] && ok || bad "5, 5 (one round without a fall): expected continue, got '$v'"
rounds_report "$tmp/crit.md" "r1 1 0 0 0"
v="$(verdict_of "$tmp/crit.md")"; [ "$v" = "continue" ] && ok || bad "1 critical under a 0 high bar: expected continue, got '$v'"
rounds_report "$tmp/crit-raised.md" "r1 1 0 0 0" "1 high, 0 medium."
v="$(verdict_of "$tmp/crit-raised.md")"; [ "$v" = "continue" ] && ok || bad "1 critical under a raised bar of 1 high: expected continue, got '$v'"
ro="$tmp/readonly.md"
python3 - "$good" "$ro" <<'PY'
import sys
s = open(sys.argv[1]).read()
s = s.replace("Grant: fixes (PLAN.md section 10, row 12)\nBar: 0 high, 0 medium. Critical counts as high.\n", "Grant: none\n")
s = s.replace("Verdict: continue", "Verdict: report only")
open(sys.argv[2], "w").write(s)
PY
out="$("$ar" check "$ro" 2>&1)"; expect_rc 0 $? "a read-only audit report (Grant: none, no Bar line) exits 0"
expect_grep 'verdict report only$' "$out" "a read-only audit has the verdict 'report only' whatever the counts"
ro0="$tmp/readonly0.md"
python3 - "$ro" "$ro0" <<'PY'
import re, sys
s = open(sys.argv[1]).read()
s = re.sub(r"^\| [1-4] \| PA-00[1-4] .*\n", "", s, flags=re.M)
s = re.sub(r"^### PA-00[1-4].*?(?=^### |^## )", "", s, flags=re.M | re.S)
s = s.replace("1. PA-003: deleting", "1. Deleting")
s = s.replace("| 2 | b2c3d4e | 0 | 1 | 2 | 1 | 3 |", "| 2 | b2c3d4e | 0 | 0 | 0 | 0 | 0 |")
open(sys.argv[2], "w").write(s)
PY
out="$("$ar" check "$ro0" 2>&1)"; expect_rc 0 $? "a read-only audit with 0 findings exits 0"
expect_grep '^report contract holds: 0 findings, verdict report only$' "$out" "0 findings under Grant: none still gives 'report only'"
printf '## 11. Rounds and stop\n\nNo table here.\n' >"$tmp/empty.md"
"$ar" check "$tmp/empty.md" >/dev/null 2>&1; expect_rc 1 $? "a section 11 without a grant or table exits 1"

# 4. The texts say what the tool enforces (mechanical tokens only, so wording can change).
skill="$(cat "$root/skills/project-audit/SKILL.md")"
contract="$(cat "$root/skills/project-audit/references/report-contract.md")"
expect_grep '^## After the report$' "$skill" "the skill has 'After the report'"
expect_grep '^## Rounds and stop$' "$skill" "the skill has 'Rounds and stop'"
expect_grep '0 high and 0 medium' "$skill" "the skill states the default bar"
expect_grep '0 findings of any severity' "$skill" "the skill names the refused bar"
expect_grep '2 rounds in a row' "$skill" "the skill states the stop guard"
expect_grep 'bin/ctlhq-audit-report check' "$skill" "the skill names the checker by its bin/ path"
expect_grep '^\| # \| ID \| Title \| Severity \| Fix kind \| Route \|$' "$contract" "the contract shows the index columns the tool reads"
expect_grep '^\| # \| Commit \| Critical \| High \| Medium \| Low \| Serious \|$' "$contract" "the contract shows the rounds columns the tool reads"
expect_grep '^## 11\. Rounds and stop$' "$contract" "the contract has section 11"
expect_grep '^Grant: ' "$contract" "the contract shows the Grant line"
for lvl in Critical High Medium Low; do
	expect_grep "^\| [0-9] \| $lvl \| .+ \| .+ \|$" "$contract" "the severity scale has a $lvl row with an example"
done
for kind in remove change add; do
	expect_grep "^\| [0-9] \| $kind \| " "$contract" "the fix kind table defines $kind"
done
expect_nogrep 'Stop after the report' "$contract" "the contract no longer ends every audit at the report"
[ -L "$root/bin/ctlhq-audit-report" ] && ok || bad "bin/ctlhq-audit-report is a symlink like bin/ctlhq-repo-map"

echo "$pass checks passed"
[ "$fail" -eq 0 ]
