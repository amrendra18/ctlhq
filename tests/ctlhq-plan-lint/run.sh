#!/usr/bin/env bash
# tests/ctlhq-plan-lint/run.sh: checks for bin/ctlhq-plan-lint (skills/ctlhq-mode/bin/ctlhq-plan-lint, which runs
# skills/ctlhq-mode/scripts/check-plan.mjs on node). Prints "N checks passed" and exits 1 when
# any check fails. Writes only to a temp folder. Needs node on PATH.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
cp_="$root/bin/ctlhq-plan-lint"
pass=0
fail=0
ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL: $1"; }
expect_rc() { if [ "$1" -eq "$2" ]; then ok; else bad "$3 (expected exit $1, got $2)"; fi; }
expect_eq() { if [ "$1" = "$2" ]; then ok; else bad "$3 (expected '$1', got '$2')"; fi; }
expect_grep() { if printf '%s\n' "$2" | grep -Eq -- "$1"; then ok; else bad "$3 (no line matches: $1)"; fi; }
expect_fgrep() { if printf '%s\n' "$2" | grep -Fq -- "$1"; then ok; else bad "$3 (no line contains: $1)"; fi; }
expect_nogrep() { if printf '%s\n' "$2" | grep -Eq -- "$1"; then bad "$3 (a line matches: $1)"; else ok; fi; }

if ! command -v node >/dev/null 2>&1; then
	echo "FAIL: node is not on PATH; ctlhq-plan-lint needs it"
	echo "0 checks passed"
	exit 1
fi

tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-plan-test.XXXXXX")"
tmp="$(cd "$tmp" && pwd)" || exit 1  # TMPDIR may end in a slash
[ -n "$tmp" ] && [ -d "$tmp" ] || { echo "FAIL: no temp folder"; exit 1; }
trap 'rm -rf "$tmp"' EXIT
RULE='Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.'

# A plan that satisfies every rule (the same skeleton as scripts/check-plan.test.ts).
valid() {
	cat <<PLAN
# Demo

## How to read this
One box is one unit of work and names the evidence. Check a box only when its evidence exists. See playbooks/.
$RULE

## Program checklist
### Arm the program
### Spawn owners
### PR mechanics
### Verdict and merge
### Boot recipe
\`git show origin/main:\` /loop 1h status message

## PR 1
**Depends on.** None.
**Files.**
- [ ] Do the thing.
**Build.**
- [ ] Do the thing.
**You see.**
- [ ] Do the thing.
**Verify, unit.** $RULE
- [ ] Check the thing.
**Verify, live.** $RULE Ten lanes on \`example-model\` at the PR head
PLAN
	for i in 1 2 3 4 5 6 7 8 9 10; do
		echo "- [ ] Lane $i. Save \`lane-$i.png\`. Pass when evidence exists."
	done
	cat <<PLAN
**Verify, perf.** $RULE
- [ ] Metric. Recorded.
- [ ] Probe. Recorded.
- [ ] Baseline. Recorded.
- [ ] Rule. Recorded.
**Review gate.** None.
**Merge.**
- [ ] Merge when approved.

## Close the program
Close.

## Appendix Prototype evidence
Recorded.
PLAN
}
good="$tmp/good.md"
valid > "$good"

# run <file>: sets out (stdout), err (stderr), rc.
run() {
	out="$("$cp_" "$1" 2>"$tmp/err")"; rc=$?
	err="$(cat "$tmp/err")"
}
# variant <name> <sed expression>: a copy of the valid plan with one planted defect.
variant() { sed "$2" "$good" > "$tmp/$1.md"; printf '%s' "$tmp/$1.md"; }

# 1. --help and usage errors.
out="$("$cp_" --help 2>&1)"; expect_rc 0 $? "--help exits 0"
expect_grep '^ctlhq-plan-lint: ' "$(printf '%s\n' "$out" | head -1)" "--help first line is 'ctlhq-plan-lint: ...'"
expect_fgrep 'Exit 0 when the plan is clean, 1 when it found problems, 2 on a usage error.' "$out" "--help documents exits 0, 1, 2"
"$cp_" -h >/dev/null 2>&1; expect_rc 0 $? "-h exits 0"
"$cp_" "$good" --help >/dev/null 2>&1; expect_rc 0 $? "--help anywhere exits 0"
out="$(node "$root/skills/ctlhq-mode/scripts/check-plan.mjs" --help 2>&1)"; expect_rc 0 $? "the script run directly with --help exits 0"
expect_eq 'Usage: node check-plan.mjs [--project] <plan.md>|The full help: bin/ctlhq-plan-lint --help' "$(printf '%s\n' "$out" | paste -sd '|' -)" "the script run directly with --help prints its usage and points at the wrapper"
err="$("$cp_" 2>&1 >/dev/null)"; expect_rc 2 $? "no argument exits 2"
expect_grep '^ctlhq-plan-lint: expected one existing plan file' "$err" "no argument names the problem"
expect_grep '^fix: ctlhq-plan-lint <path to plan\.md>' "$err" "no argument gets a fix line"
"$cp_" "$tmp/nosuch.md" >/dev/null 2>&1; expect_rc 2 $? "missing plan file exits 2"
"$cp_" "$good" "$good" >/dev/null 2>&1; expect_rc 2 $? "two files exit 2"
"$cp_" "$tmp" >/dev/null 2>&1; expect_rc 2 $? "a folder as the plan exits 2"

# 2. The valid plan: exit 0, the per-PR report line, the summary, nothing on stderr.
run "$good"
expect_rc 0 "$rc" "valid plan exits 0"
expect_eq "PR 1  boxes=19  files=1 build=1 you-see=1 verify-unit=1 verify-live=10 verify-perf=4 review-gate=0 merge=1" "$(printf '%s\n' "$out" | head -1)" "per-PR box report"
expect_eq "1 PR sections, 0 problems" "$(printf '%s\n' "$out" | tail -1)" "summary line"
expect_eq "" "$err" "valid plan prints nothing on stderr"
( cd "$tmp" && "$cp_" good.md >/dev/null 2>&1 ); expect_rc 0 $? "relative path from another cwd exits 0"

# 3. Front matter is skipped; CRLF line endings are accepted.
{ printf -- '---\ntitle: x: y\n---\n'; cat "$good"; } > "$tmp/fm.md"
run "$tmp/fm.md"; expect_rc 0 "$rc" "front matter (with a colon) is skipped"
sed 's/$/\r/' "$good" > "$tmp/crlf.md"
run "$tmp/crlf.md"; expect_rc 0 "$rc" "CRLF plan exits 0"

# 4. Prose rules: long dash, curly quote, mid-sentence colon; code and links are exempt.
run "$(variant dash 's/^Close\.$/Close \xe2\x80\x94 now./')"
expect_rc 1 "$rc" "em dash exits 1"
expect_grep 'dash\.md:[0-9]+: long dash$' "$err" "em dash reported as file:line: long dash"
run "$(variant curly 's/^Close\.$/Close \xe2\x80\x9cnow\xe2\x80\x9d./')"
expect_rc 1 "$rc" "curly quote exits 1"
expect_grep ': curly quote$' "$err" "curly quote reported"
run "$(variant colon 's/^Close\.$/Close: now./')"
expect_rc 1 "$rc" "mid-sentence colon exits 1"
expect_grep "colon\.md:$(grep -n '^Close\.$' "$good" | cut -d: -f1): mid-sentence colon$" "$err" "colon reported with its line number"
run "$(variant inline 's/^Close\.$/Close `a: b` and [x](http:\/\/h\/a: b)./')"
expect_rc 0 "$rc" "colon inside inline code or a link target is exempt"
printf '```\nA colon: here \xe2\x80\x94 and a dash.\n```\n' >> "$(variant fenced 's/x/x/')"
run "$tmp/fenced.md"
expect_rc 0 "$rc" "prose rules skip fenced code"

# 5. Missing skeleton sections.
run "$(variant noh1 's/^# Demo$/Demo/')"
expect_rc 1 "$rc" "no H1 exits 1"; expect_grep ':1: no H1 title$' "$err" "no H1 reported"
run "$(variant nohow 's/^## How to read this$/## Reading/')"
expect_rc 1 "$rc" "no How to read this exits 1"; expect_fgrep 'no "## How to read this" section' "$err" "missing How to read this reported"
run "$(variant howmarker 's/One box is one unit of work and //')"
expect_rc 1 "$rc" "How to read this missing a marker exits 1"; expect_fgrep 'How to read this lacks "One box is one unit of work"' "$err" "missing marker named"
awk '/^# Demo$/ { print; for (i = 1; i <= 10; i++) print "intro line " i; next } { print }' "$good" > "$tmp/intro.md"
run "$tmp/intro.md"
expect_rc 1 "$rc" "ten intro lines exit 1"; expect_fgrep 'intro is 10 lines, under ten required' "$err" "long intro reported"
run "$(variant noprog 's/^## Program checklist$/## Program/')"
expect_rc 1 "$rc" "no Program checklist exits 1"; expect_fgrep 'no "## Program checklist" section' "$err" "missing Program checklist reported"
run "$(variant h3order '/^### Spawn owners$/d; /^### Boot recipe$/a\
### Spawn owners
')"
expect_rc 1 "$rc" "Program checklist H3 out of order exits 1"; expect_fgrep 'Program checklist lacks "### PR mechanics" in order' "$err" "out-of-order H3 named"
run "$(variant loop 's/ \/loop 1h//')"
expect_rc 1 "$rc" "missing /loop 1h marker exits 1"; expect_fgrep 'Program checklist lacks "/loop 1h"' "$err" "missing program marker named"
run "$(variant noclose 's/^## Close the program$/## Closing/')"
expect_rc 1 "$rc" "no Close the program exits 1"; expect_fgrep 'no "## Close the program" section' "$err" "missing Close the program reported"
expect_fgrep 'no PR sections between Program checklist and Close the program' "$err" "no PR sections reported"
run "$(variant noappendix 's/^## Appendix Prototype evidence$/## Appendix Notes/')"
expect_rc 1 "$rc" "no Prototype evidence appendix exits 1"; expect_fgrep 'no "## Appendix ... Prototype evidence" section' "$err" "missing appendix reported"
printf '\n## Afterword\nText.\n' >> "$(variant tail 's/x/x/')"
run "$tmp/tail.md"
expect_rc 1 "$rc" "non-appendix section after Close exits 1"; expect_fgrep '"## Afterword" after Close the program is not an appendix' "$err" "non-appendix section named"

# 6. PR section sub-blocks.
run "$(variant nobuild '/^\*\*Build\.\*\*$/,/^- \[ \] Do the thing\.$/d')"
expect_rc 1 "$rc" "missing Build block exits 1"; expect_fgrep 'PR 1: sub-blocks are [Depends on., Files., You see.' "$err" "sub-block list printed"
run "$(variant depends 's/^\*\*Depends on\.\*\* None\.$/**Depends on.**/')"
expect_rc 1 "$rc" "empty Depends on exits 1"; expect_fgrep 'PR 1: Depends on names nothing' "$err" "empty Depends on reported"
run "$(variant nobox '/^\*\*Merge\.\*\*$/{n;d;}')"
expect_rc 1 "$rc" "Merge with no box exits 1"; expect_fgrep 'PR 1: Merge. has no box' "$err" "boxless block named"
run "$(variant norule 's/^\*\*Verify, unit\.\*\* .*/**Verify, unit.** Check it./')"
expect_rc 1 "$rc" "Verify, unit without the rule exits 1"; expect_fgrep 'PR 1: Verify, unit. does not open with the rule' "$err" "missing rule reported"

# 7. Verify, live lanes.
run "$(variant nolanes 's/ Ten lanes on `example-model` at the PR head//')"
expect_rc 1 "$rc" "live block without the lanes sentence exits 1"; expect_fgrep 'Verify, live lacks "Ten lanes on' "$err" "missing lanes sentence reported"
run "$(variant placeholder 's/`example-model`/`<swarm-workers model>`/')"
expect_rc 1 "$rc" "unfilled model placeholder exits 1"
run "$(variant nine '/^- \[ \] Lane 10\./d')"
expect_rc 1 "$rc" "nine lanes exit 1"; expect_fgrep 'PR 1: lanes are [1,2,3,4,5,6,7,8,9], expected 1 to 10' "$err" "lane numbers listed"
run "$(variant shot 's/^- \[ \] Lane 3\. Save `lane-3.png`\./- [ ] Lane 3. Look at it./')"
expect_rc 1 "$rc" "lane without a screenshot exits 1"; expect_fgrep 'PR 1: lane 3 names no screenshot' "$err" "lane without screenshot named"
run "$(variant pred 's/^\(- \[ \] Lane 4\. Save `lane-4.png`\.\) Pass when evidence exists\./\1 Done./')"
expect_rc 1 "$rc" "lane without a pass predicate exits 1"; expect_fgrep 'PR 1: lane 4 has no pass predicate' "$err" "lane without predicate named"
run "$(variant notlane '/^- \[ \] Lane 10\./a\
- [ ] Extra check.
')"
expect_rc 1 "$rc" "a non-lane box in live exits 1"; expect_fgrep 'PR 1: live box is not a lane' "$err" "non-lane box reported"
run "$(variant checked 's/^- \[ \] Lane \([0-9]*\)\./- [x] Lane \1./')"
expect_rc 0 "$rc" "checked boxes [x] count as boxes"

# 8. Verify, perf and Review gate.
run "$(variant perf '/^- \[ \] Baseline\. Recorded\.$/d')"
expect_rc 1 "$rc" "perf without Baseline exits 1"; expect_fgrep 'PR 1: perf boxes are [Metric., Probe., Rule.], expected [Metric., Probe., Baseline., Rule.]' "$err" "perf items listed"
run "$(variant gatebox '/^\*\*Review gate\.\*\* None\.$/a\
- [ ] Operator looks.
')"
expect_rc 1 "$rc" "Review gate None with a box exits 1"; expect_fgrep 'PR 1: Review gate says None but has boxes' "$err" "None with boxes reported"
run "$(variant gatefull 's/^\*\*Review gate\.\*\* None\.$/**Review gate.** Operator review.\
- [ ] The operator watches the video and checks the screenshot./')"
expect_rc 0 "$rc" "a full Review gate with screenshot, video, operator exits 0"
expect_fgrep 'review-gate=1' "$out" "full Review gate counted in the report"
run "$(variant gatebad 's/^\*\*Review gate\.\*\* None\.$/**Review gate.** Operator review.\
- [ ] The operator checks the screenshot./')"
expect_rc 1 "$rc" "Review gate without video exits 1"; expect_fgrep 'PR 1: Review gate lacks "video"' "$err" "missing gate word named"
run "$(variant gatenobox 's/^\*\*Review gate\.\*\* None\.$/**Review gate.** Operator review of the screenshot and video./')"
expect_rc 1 "$rc" "Review gate with no box exits 1"; expect_fgrep 'PR 1: Review gate has no box' "$err" "gate without box reported"

# 9. Two PR sections are both checked and reported.
awk '/^## Close the program$/ { while ((getline l < f) > 0) if (l ~ /^## PR 1$/) p = 1; else if (l ~ /^## Close/) p = 0; else if (p) b = b l "\n"; printf "## PR 2\n%s", b } { print }' f="$good" "$good" > "$tmp/two.md"
run "$tmp/two.md"
expect_rc 0 "$rc" "two valid PR sections exit 0"
expect_eq "2 PR sections, 0 problems" "$(printf '%s\n' "$out" | tail -1)" "two PR sections counted"
expect_grep '^PR 2  boxes=19 ' "$out" "PR 2 reported"

# 10. Headings inside fenced code are not sections (closing fence rules from check-plan.test.ts).
printf '```markdown\n## Example only\n```\n' >> "$(variant fence1 's/x/x/')"
run "$tmp/fence1.md"; expect_rc 0 "$rc" "a heading inside a fence is ignored"
printf '````markdown\n```\n## Example only\n````\n' >> "$(variant fence2 's/x/x/')"
run "$tmp/fence2.md"; expect_rc 0 "$rc" "a shorter inner fence does not close a longer one"
printf '```markdown\n## Example only\n```  \n## Example only\n' >> "$(variant fence3 's/x/x/')"
run "$tmp/fence3.md"; expect_rc 1 "$rc" "a heading after a closed fence is a section"

# 11. Several problems: every one is listed and counted.
run "$(variant many 's/^Close\.$/Close: now \xe2\x80\x94 ok./; s/^\*\*Depends on\.\*\* None\.$/**Depends on.**/')"
expect_rc 1 "$rc" "several problems exit 1"
expect_eq 7 "$(printf '%s\n' "$err" | grep -c '')" "one why line, then three problem lines with a fix line each, on stderr"
expect_eq "1 PR sections, 3 problems" "$(printf '%s\n' "$out" | tail -1)" "summary counts three problems"
expect_eq 0 "$(printf '%s\n' "$err" | grep -Evc '^[^:]+:[0-9]+: |^  fix: |^why: ')" "every stderr line is a why line, a file:line: problem, or a fix line"
expect_eq 3 "$(printf '%s\n' "$err" | grep -Ec '^[^:]+:[0-9]+: ')" "three problem lines"
expect_eq 3 "$(printf '%s\n' "$err" | awk '/^[^:]+:[0-9]+: / { want = 1; next } want && /^  fix: [^ ]/ { n++ } { want = 0 } END { print n + 0 }')" "a fix line right under every problem line"
expect_grep '^why: ctlhq-mode owners run the plan box by box' "$(printf '%s\n' "$err" | head -1)" "the why line comes first"

# 11b. Fix lines name the action and the skeleton line to copy (planted cases).
skel="$root/skills/ctlhq-mode/playbooks/multi-phase-plan.md"
skel_line() { grep -nF -- "$1" "$skel" | head -1 | cut -d: -f1; }
run "$(variant fixcolon 's/^Close\.$/Close: now./')"
expect_grep '^  fix: "Close: now\.": end the sentence before the colon, or use a comma' "$err" "colon fix quotes the matched text"
run "$(variant fixhow 's/^## How to read this$/## Reading/')"
expect_grep "^  fix: add it under the title; copy it from skills/ctlhq-mode/playbooks/multi-phase-plan\.md:$(skel_line '## How to read this')\$" "$err" "missing section fix names the skeleton line"
run "$(variant fixclose 's/^## Close the program$/## Closing/')"
expect_grep "copy it from skills/ctlhq-mode/playbooks/multi-phase-plan\.md:$(skel_line '## Close the program')\$" "$err" "missing Close fix names the skeleton line"
run "$(variant fixdepends 's/^\*\*Depends on\.\*\* None\.$/**Depends on.**/')"
expect_grep '^  fix: write "\*\*Depends on\.\*\* None\." or name the PR ids' "$err" "empty Depends on fix"
run "$(variant fixnine '/^- \[ \] Lane 10\./d')"
expect_grep '^  fix: add "- \[ \] Lane <n>\. .*" for lane 10;' "$err" "lane fix names the missing lane number"
run "$(variant fixshot 's/^- \[ \] Lane 3\. Save `lane-3.png`\./- [ ] Lane 3. Look at it./')"
expect_grep '^  fix: add "Save `<file>\.png`\." to lane 3 on line [0-9]+$' "$err" "screenshot fix names the lane and line"
run "$(variant fixrule 's/^\*\*Verify, unit\.\*\* .*/**Verify, unit.** Check it./')"
expect_grep '^  fix: start line [0-9]+ with "\*\*Verify, unit\.\*\* Tests alone are not sufficient verification\.' "$err" "rule fix gives the exact opening"
run "$(variant fixperf '/^- \[ \] Baseline\. Recorded\.$/d')"
expect_grep '^  fix: write four boxes in this order' "$err" "perf fix lists the order"
printf '\n## Afterword\nText.\n' >> "$(variant fixtail 's/x/x/')"
run "$tmp/fixtail.md"
expect_grep '^  fix: rename it "## Appendix <letter>\. Afterword", or move it above "## Close the program"$' "$err" "non-appendix fix names the rename"

# 11c. Every other problem type: a planted case, and the exact fix line right under the problem.
# expect_fix <problem text> <fix text> <label>: the line after the first stderr line holding the
# problem text must be "  fix: <fix text>".
expect_fix() {
	local got
	got="$(printf '%s\n' "$err" | P="$1" awk 'found { print; exit } index($0, ENVIRON["P"]) { found = 1 }')"
	expect_eq "  fix: $2" "$got" "$3"
}
sk="skills/ctlhq-mode/playbooks/multi-phase-plan.md"
good_line() { grep -n -- "$1" "$good" | head -1 | cut -d: -f1; }
run "$(variant fxdash 's/^Close\.$/Close \xe2\x80\x94 now./')"
expect_fix ': long dash' 'replace the dash with a period, a comma, a colon at the end of a line, or parentheses' "long dash fix"
run "$(variant fxcurly 's/^Close\.$/Close \xe2\x80\x9cnow\xe2\x80\x9d./')"
expect_fix ': curly quote' "replace it with a straight quote (' or \")" "curly quote fix"
run "$(variant fxnoh1 's/^# Demo$/Demo/')"
expect_fix ':1: no H1 title' "add a title line \"# <Program> plan\" as the first line ($sk:$(skel_line '# <Program> plan'))" "no H1 fix names the skeleton title line"
awk '/^# Demo$/ { print; for (i = 1; i <= 10; i++) print "intro line " i; next } { print }' "$good" > "$tmp/fxintro.md"
run "$tmp/fxintro.md"
expect_fix 'intro is 10 lines, under ten required' 'cut the text between the title and "## How to read this" to at most 9 lines, or move it into an appendix' "long intro fix"
run "$(variant fxhowmarker 's/One box is one unit of work and //')"
expect_fix 'How to read this lacks "One box is one unit of work"' "add the sentence that holds it; copy it from $sk:$(skel_line 'One box is one unit of work')" "How to read this marker fix names the skeleton line"
run "$(variant fxnoprog 's/^## Program checklist$/## Program/')"
expect_fix 'no "## Program checklist" section' "add it after \"## How to read this\"; copy it from $sk:$(skel_line '## Program checklist')" "missing Program checklist fix names the skeleton line"
run "$(variant fxh3order '/^### Spawn owners$/d; /^### Boot recipe$/a\
### Spawn owners
')"
expect_fix 'Program checklist lacks "### PR mechanics" in order' "the order is \"### Arm the program\", \"### Spawn owners\", \"### PR mechanics\", \"### Verdict and merge\", \"### Boot recipe\"; copy it from $sk:$(skel_line '### PR mechanics')" "out-of-order H3 fix gives the order and the skeleton line"
run "$(variant fxloop 's/ \/loop 1h//')"
expect_fix 'Program checklist lacks "/loop 1h"' "add the box that holds it; copy it from $sk:$(skel_line '/loop 1h')" "missing program marker fix names the skeleton line"
run "$(variant fxnoclose 's/^## Close the program$/## Closing/')"
expect_fix 'no PR sections between Program checklist and Close the program' "add one \"## <Task as a verb phrase> (<PR id>)\" section per PR between them; copy it from $sk:$(skel_line '**Depends on.**')" "no PR sections fix names the skeleton PR block"
run "$(variant fxnobuild '/^\*\*Build\.\*\*$/,/^- \[ \] Do the thing\.$/d')"
expect_fix 'PR 1: sub-blocks are [' "add **Build.** so they run in the expected order; copy it from $sk:$(skel_line '**Depends on.**')" "missing sub-block fix names the block to add"
run "$(variant fxnobox '/^\*\*Merge\.\*\*$/{n;d;}')"
expect_fix 'PR 1: Merge. has no box' 'add at least one "- [ ] <step and its evidence>" line under **Merge.**' "boxless block fix"
run "$(variant fxnolanes 's/ Ten lanes on `example-model` at the PR head//')"
expect_fix 'Verify, live lacks "Ten lanes on' 'add that sentence after the rule, with the model `ctlhq-models get swarm-workers` prints in the backticks' "missing lanes sentence fix names the model command"
run "$(variant fxnotlane '/^- \[ \] Lane 10\./a\
- [ ] Extra check.
')"
expect_fix 'PR 1: live box is not a lane' 'start it with "Lane <n>. " (1 to 10), or move it to another block' "non-lane box fix"
run "$(variant fxpred 's/^\(- \[ \] Lane 4\. Save `lane-4.png`\.\) Pass when evidence exists\./\1 Done./')"
expect_fix 'PR 1: lane 4 has no pass predicate' "add \"Pass when <what you see>.\" to lane 4 on line $(good_line '^- \[ \] Lane 4\.')" "pass predicate fix names the lane and line"
run "$(variant fxgatebox '/^\*\*Review gate\.\*\* None\.$/a\
- [ ] Operator looks.
')"
expect_fix 'PR 1: Review gate says None but has boxes' "remove the boxes under line $(good_line '^\*\*Review gate\.\*\*'), or replace \"None.\" with the review and keep the boxes" "None with boxes fix names the line"
run "$(variant fxgatenobox 's/^\*\*Review gate\.\*\* None\.$/**Review gate.** Operator review of the screenshot and video./')"
expect_fix 'PR 1: Review gate has no box' 'add a "- [ ] ..." box in which the operator reviews the screenshots and a video before merge, or write "**Review gate.** None. <PR id> is not review-gated."' "gate without box fix"
run "$(variant fxgatebad 's/^\*\*Review gate\.\*\* None\.$/**Review gate.** Operator review.\
- [ ] The operator checks the screenshot./')"
expect_fix 'PR 1: Review gate lacks "video"' "name the video in a Review gate box; copy it from $sk:$(skel_line '**Review gate.**')" "missing gate word fix names the word and the skeleton line"
run "$(variant fxnoappendix 's/^## Appendix Prototype evidence$/## Appendix Notes/')"
expect_fix 'no "## Appendix ... Prototype evidence" section' "add it after \"## Close the program\"; copy it from $sk:$(skel_line 'Prototype evidence')" "missing appendix fix names the skeleton line"
# Control: expect_fix catches a fix line that does not match.
run "$(variant fxcontrol 's/^Close\.$/Close \xe2\x80\x94 now./')"
fails_before=$fail
expect_fix ': long dash' 'a fix text the tool never prints' "control (expected to fail)" >/dev/null
if [ "$fail" -eq $((fails_before + 1)) ]; then fail=$fails_before; ok; else bad "control: expect_fix did not catch a wrong fix text"; fi

# 12. An empty plan.
: > "$tmp/empty.md"
run "$tmp/empty.md"; expect_rc 1 "$rc" "an empty plan exits 1"
expect_fgrep 'no H1 title' "$err" "an empty plan reports no H1"

# 13. Positive control: a copy of check-plan.mjs with the colon rule removed must miss check 4's colon.
mkdir -p "$tmp/mut/bin" "$tmp/mut/scripts"
cp "$root/skills/ctlhq-mode/bin/ctlhq-plan-lint" "$tmp/mut/bin/"
sed '/mid-sentence colon/d' "$root/skills/ctlhq-mode/scripts/check-plan.mjs" > "$tmp/mut/scripts/check-plan.mjs"
if cmp -s "$tmp/mut/scripts/check-plan.mjs" "$root/skills/ctlhq-mode/scripts/check-plan.mjs"; then bad "positive control: the planted defect did not change check-plan.mjs"; else ok; fi
"$tmp/mut/bin/ctlhq-plan-lint" "$tmp/colon.md" >/dev/null 2>&1
expect_rc 0 $? "positive control: the mutant passes the colon plan, so check 4 would catch the defect"

# 14. Project mode: a project PLAN.md written from skills/run-method/references/PLAN-template.md.
proj="$here/project-plan.md"
# pvariant <name> <sed expression>: a copy of the clean project plan with one planted defect.
pvariant() { sed "$2" "$proj" > "$tmp/$1.md"; printf '%s' "$tmp/$1.md"; }
prun() { out="$("$cp_" --project "$1" 2>"$tmp/err")"; rc=$?; err="$(cat "$tmp/err")"; }
out="$("$cp_" --help 2>&1)"
expect_fgrep 'A file named PLAN.md, or any file with --project, is a project plan.' "$out" "--help explains how project mode is chosen"
expect_fgrep 'Project mode checks a PLAN.md written from skills/run-method/references/PLAN-template.md.' "$out" "--help explains project mode"
"$cp_" --project >/dev/null 2>&1; expect_rc 2 $? "--project without a file exits 2"
prun "$proj"
expect_rc 0 "$rc" "clean project plan exits 0"
expect_eq "project plan: 2 milestones, 2 repeated jobs, 2 workstreams, 0 problems" "$out" "project summary line"
expect_eq "" "$err" "clean project plan prints nothing on stderr"
mkdir -p "$tmp/named"; cp "$proj" "$tmp/named/PLAN.md"
out="$("$cp_" "$tmp/named/PLAN.md" 2>/dev/null)"; expect_rc 0 $? "a file named PLAN.md is checked in project mode without --project"
expect_grep '^project plan: ' "$out" "PLAN.md detection prints the project summary"
"$cp_" "$proj" >/dev/null 2>"$tmp/err"; expect_rc 1 $? "the project plan under another name, without --project, is a multi-phase plan"
expect_fgrep 'a project plan is checked with ctlhq-plan-lint --project' "$(cat "$tmp/err")" "multi-phase mode points to --project when both skeleton sections are missing"
run "$(variant hintless 's/x/x/')"; expect_nogrep 'ctlhq-plan-lint --project' "$err" "a real multi-phase plan gets no --project hint"
prun "$(pvariant pcolon 's/^None\.$/Note: none./')"
expect_rc 0 "$rc" "project mode allows a mid-sentence colon"
prun "$(pvariant pdash 's/^None\.$/None \xe2\x80\x94 yet./')"
expect_rc 1 "$rc" "project mode rejects a long dash"; expect_grep 'pdash\.md:[0-9]+: long dash$' "$err" "long dash reported in project mode"
prun "$(pvariant phole 's/^None\.$/<topics the operator deferred>/')"
expect_rc 1 "$rc" "an unfilled placeholder exits 1"
expect_fix 'unfilled placeholder "<topics the operator deferred>"' 'replace "<topics the operator deferred>" with the real value, or delete the line' "placeholder fix"
prun "$(pvariant pcodehole 's/^None\.$/Run `jot <word>`./')"
expect_rc 1 "$rc" "a placeholder inside inline code is still unfilled"
prun "$(pvariant pm0hole 's/`scripts\/verify fast --feature add-note`/`scripts\/verify fast --feature <journey>`/')"
expect_rc 1 "$rc" "the template M0 row with <journey> left inside backticks exits 1"
expect_fgrep 'unfilled placeholder "<journey>"' "$err" "placeholder inside the M0 command reported"

# 14b. Each required part: a planted gap exits 1 with the problem and its fix line.
tpl="skills/run-method/references/PLAN-template.md"
tpl_line() { grep -nF -- "$1" "$root/$tpl" | head -1 | cut -d: -f1; }
prun "$(pvariant pnowhat 's/^## 1\. What, why, how$/## 1. Summary/')"
expect_rc 1 "$rc" "no What, why, how exits 1"
expect_fix 'no "What, why, how" section' "add it under the title; copy it from $tpl:$(tpl_line '## 1. What, why, how')" "What, why, how fix names the template line"
prun "$(pvariant pnowhy '/^\*\*Why\.\*\*/d')"
expect_rc 1 "$rc" "no Why line exits 1"
expect_fix 'What, why, how lacks **Why.**' "add a line that starts with \"**Why.**\"; copy it from $tpl:$(tpl_line '**Why.**')" "missing Why fix"
prun "$(pvariant pemptyhow 's/^\*\*How\.\*\* .*/**How.**/')"
expect_rc 1 "$rc" "an empty How line exits 1"; expect_fgrep 'What, why, how: **How.** says nothing' "$err" "empty How reported"
prun "$(pvariant pnocomplete 's/^## 3\. Complete, in plain words$/## 3. Done/')"
expect_rc 1 "$rc" "no Complete, in plain words exits 1"; expect_fgrep 'no "Complete, in plain words" section' "$err" "missing Complete reported"
prun "$(pvariant pemptycomplete '/^The user runs `jot list`/d')"
expect_rc 1 "$rc" "an empty Complete, in plain words exits 1"; expect_fgrep '"Complete, in plain words" section is empty' "$err" "empty Complete reported"
prun "$(pvariant pemptynotpart '/^1\. Sync between machines/d')"
expect_rc 1 "$rc" "an empty Not part of complete exits 1"; expect_fgrep '"Not part of complete" section is empty' "$err" "empty Not part of complete reported"
prun "$(pvariant pnonotpart 's/^### Not part of complete$/### Later/')"
expect_rc 1 "$rc" "no Not part of complete exits 1"; expect_fgrep 'no "Not part of complete" section' "$err" "missing Not part of complete reported"
prun "$(pvariant pnojobs 's/^### 5\.2\. Repeated jobs$/### 5.2. Jobs/')"
expect_rc 1 "$rc" "no Repeated jobs section exits 1"
expect_fix 'no "Repeated jobs" section' "add it before the milestones; copy it from $tpl:$(tpl_line '### 5.2. Repeated jobs')" "Repeated jobs fix names the template line"
prun "$(pvariant pjobtable '/^| 1 | Prove/d; /^| 2 | Full gate/d; /^| # | Job |/,/^| --- /d')"
expect_rc 1 "$rc" "Repeated jobs without its table exits 1"; expect_fgrep 'Repeated jobs has no table with Job, Command, and Check columns' "$err" "missing jobs table reported"
prun "$(pvariant pjobrows '/^| 1 | Prove/d; /^| 2 | Full gate/d')"
expect_rc 1 "$rc" "an empty Repeated jobs table exits 1"; expect_fgrep 'Repeated jobs table has no rows' "$err" "empty jobs table reported"
prun "$(pvariant pjobcmd 's/^| 2 | Full gate | `.\/scripts\/check full` |/| 2 | Full gate | the full gate |/')"
expect_rc 1 "$rc" "a repeated job without a command exits 1"
expect_fix 'repeated job 2 names no command' "put the exact command in backticks in the Command cell on line $(grep -n '^| 2 | Full gate' "$proj" | cut -d: -f1)" "job command fix names the line"
prun "$(pvariant pjobcheck 's/^\(| 2 | Full gate | `.\/scripts\/check full` |\) Exit 0\. |/\1  |/')"
expect_rc 1 "$rc" "a repeated job without a check exits 1"; expect_fgrep 'repeated job 2 has no check that proves it done' "$err" "missing job check reported"
prun "$(pvariant pjobok 's/^\(| 2 | Full gate | `.\/scripts\/check full` |\) Exit 0\. |/\1 ok |/')"
expect_rc 1 "$rc" "a check cell without an exit code or number exits 1"
prun "$(pvariant pnostreams 's/^### 5\.3\. Workstreams and waves$/### 5.3. Team/')"
expect_rc 1 "$rc" "no Workstreams and waves exits 1"
expect_fix 'no "Workstreams and waves" section' "add it before the milestones; copy it from $tpl:$(tpl_line '### 5.3. Workstreams and waves')" "workstreams fix names the template line"
prun "$(pvariant pstreamtable 's/^| # | Wave | Workstream | Owns these files | Depends on |$/| # | Name | Files | Depends on | Note |/')"
expect_rc 1 "$rc" "a workstream table without Wave and Owns exits 1"; expect_fgrep 'Workstreams and waves has no table with Wave, Workstream, and Owns columns' "$err" "wrong workstream table reported"
prun "$(pvariant pstreamowns 's/^| 2 | M1 wave 1 | list | `src\/list.py`, `tests\/list\/` |/| 2 | M1 wave 1 | list | the list code |/')"
expect_rc 1 "$rc" "a workstream that owns no file exits 1"; expect_fgrep 'workstream 2 owns no file' "$err" "workstream without files reported"
prun "$(pvariant pclash 's/`src\/list.py`, `tests\/list\/`/`src\/search.py`/')"
expect_rc 1 "$rc" "two workstreams of one wave owning one file exit 1"
expect_fix 'workstreams 1 and 2 in wave "M1 wave 1" both own `src/search.py`' 'give each file one owner: move it to one row, or put the two rows in different waves' "ownership clash fix"
prun "$(pvariant pclashdir 's/`src\/list.py`, `tests\/list\/`/`tests\/search\/unit.py`/')"
expect_rc 1 "$rc" "a file inside a folder another workstream owns exits 1"; expect_fgrep 'both own `tests/search/` and `tests/search/unit.py`' "$err" "folder clash reported"
prun "$(pvariant pwavecase 's/`src\/list.py`, `tests\/list\/`/`src\/search.py`/; s/^| 2 | M1 wave 1 |/| 2 | M1 Wave 1 |/')"
expect_rc 1 "$rc" "wave names differing only in case are one wave"
prun "$(pvariant pwaves 's/`src\/list.py`, `tests\/list\/`/`src\/search.py`/; s/^| 2 | M1 wave 1 |/| 2 | M1 wave 2 |/')"
expect_rc 0 "$rc" "the same file in different waves is allowed"
prun "$(pvariant pnoaudit 's/^### 5\.4\. Audit rule$/### 5.4. Review/')"
expect_rc 1 "$rc" "no Audit rule exits 1"
expect_fix 'no "Audit rule" section' "add it before the milestones; copy it from $tpl:$(tpl_line '### 5.4. Audit rule')" "audit rule fix names the template line"
prun "$(pvariant pnostop '/^\*\*Stop\.\*\*/d')"
expect_rc 1 "$rc" "an Audit rule without Stop exits 1"
expect_fix 'Audit rule lacks **Stop.**' "add a line that starts with \"**Stop.**\"; copy it from $tpl:$(tpl_line '**Stop.**')" "missing Stop fix"
prun "$(pvariant pnoseverity '/^\*\*Severity scale\.\*\*/d')"
expect_rc 1 "$rc" "an Audit rule without the severity scale exits 1"; expect_fgrep 'Audit rule lacks **Severity scale.**' "$err" "missing severity scale reported"
prun "$(pvariant pnobar '/^\*\*Bar\.\*\*/d')"
expect_rc 1 "$rc" "an Audit rule without a bar exits 1"; expect_fgrep 'Audit rule lacks **Bar.**' "$err" "missing bar reported"

# 14c. The milestone table: shape, M0 harness, Done when command and exit codes, State.
prun "$(pvariant pnotable '/^| # | Milestone | Done when | State |$/,/^| M1 /d')"
expect_rc 1 "$rc" "no milestone table exits 1"
expect_fix 'no milestone table' "add the table \"| # | Milestone | Done when | State |\" under \"## 7. Milestone status\"; copy it from $tpl:$(tpl_line '| # | Milestone | Done when | State |')" "missing milestone table fix"
prun "$(pvariant pshape 's/^| # | Milestone | Done when | State |$/| Milestone | Done when | State | Commit |/')"
expect_rc 1 "$rc" "a milestone table with other columns exits 1"
expect_fgrep 'milestone table columns are [Milestone | Done when | State | Commit], expected [# | Milestone | Done when | State]' "$err" "wrong milestone columns listed"
prun "$(pvariant pnorows '/^| M[01] /d')"
expect_rc 1 "$rc" "a milestone table with no rows exits 1"; expect_fgrep 'milestone table has no rows' "$err" "empty milestone table reported"
prun "$(pvariant pnom0 '/^| M0 /d')"
expect_rc 1 "$rc" "a plan without M0 exits 1"
expect_fix 'the first milestone is "M1", expected M0' "add M0 first, the harness plus one real user journey on the real surface; copy it from $tpl:$(tpl_line '| M0 |')" "missing M0 fix"
prun "$(pvariant pnoharness 's/^| M0 | Harness and the add journey | .* | done |$/| M0 | Harness and the add journey | `pytest tests\/add` exits 0. | done |/')"
expect_rc 1 "$rc" "an M0 that does not run the harness exits 1"
expect_fix 'milestone M0: Done when does not run the harness `scripts/verify` on one journey' 'M0 is the harness plus one real user journey on the real surface; name `scripts/verify fast --feature` with the journey name, and its exit codes (verify-setup writes the harness)' "M0 harness fix"
prun "$(pvariant pm0help 's/`scripts\/verify fast --feature add-note` exits 0/`scripts\/verify --help` exits 0/')"
expect_rc 1 "$rc" "an M0 that runs only scripts/verify --help exits 1"
prun "$(pvariant pnocmd 's/`scripts\/verify fast --feature search` exits 0; `.\/scripts\/check full` exits 0\./search works and exits 0./')"
expect_rc 1 "$rc" "a Done when without a command exits 1"; expect_fgrep 'milestone M1: Done when names no command' "$err" "Done when without a command reported"
prun "$(pvariant pnoexit 's/`scripts\/verify fast --feature search` exits 0; `.\/scripts\/check full` exits 0\./`scripts\/verify fast --feature search` shows the note./')"
expect_rc 1 "$rc" "a Done when without an exit code exits 1"
expect_fix 'milestone M1: Done when names no exit code' "say which exit code proves it, for example \"exits 0\", in the Done when cell on line $(grep -n '^| M1 ' "$proj" | cut -d: -f1)" "Done when exit code fix names the line"
prun "$(pvariant pstate 's/| in progress |$/| building |/')"
expect_rc 1 "$rc" "an unknown State exits 1"; expect_fgrep 'milestone M1: State "building" is not one of planned, in progress, done, blocked' "$err" "unknown State reported"
prun "$(pvariant pnumber 's/^| M1 /| one /')"
expect_rc 1 "$rc" "a milestone number that is not M<n> exits 1"; expect_fgrep 'milestone number "one" is not M<n>' "$err" "bad milestone number reported"
prun "$(pvariant pplain 's/^| M\([01]\) /| \1 /')"
expect_rc 0 "$rc" "plain milestone numbers 0 and 1 are accepted"
prun "$(pvariant pnoledger 's/^## 10\. Approvals ledger$/## 10. Notes/')"
expect_rc 1 "$rc" "no Approvals ledger exits 1"; expect_fgrep 'no "Approvals ledger" section' "$err" "missing ledger reported"
prun "$(pvariant pledgertable '/^| # | Date and time |/,/^| 1 | 2026-10-19 10:00 /d')"
expect_rc 1 "$rc" "a ledger without its table exits 1"; expect_fgrep 'Approvals ledger has no table with an approved column' "$err" "missing ledger table reported"

# 14d. Every project-mode stderr line is a why line, a problem, or a fix line; several gaps are all counted.
prun "$(pvariant pmany '/^\*\*Stop\.\*\*/d; s/| in progress |$/| building |/')"
expect_rc 1 "$rc" "two gaps exit 1"
expect_eq "project plan: 2 milestones, 2 repeated jobs, 2 workstreams, 2 problems" "$out" "project summary counts two problems"
expect_grep '^why: run-method builds and resumes from PLAN\.md' "$(printf '%s\n' "$err" | head -1)" "project why line comes first"
expect_eq 0 "$(printf '%s\n' "$err" | grep -Evc '^[^:]+:[0-9]+: |^  fix: |^why: ')" "every project stderr line is a why, problem, or fix line"

# 14e. The template holds every required part: on the raw template, every problem is a placeholder.
prun "$root/$tpl"
expect_rc 1 "$rc" "the raw template exits 1 (its placeholders are unfilled)"
expect_eq 0 "$(printf '%s\n' "$err" | grep -E '^[^:]+:[0-9]+: ' | grep -Evc 'unfilled placeholder|milestone M1: Done when names no command')" "the raw template fails only on placeholders and the M1 placeholder row"

# 14f. Positive control: a copy without the M0 harness rule passes the plan whose M0 skips the harness.
mkdir -p "$tmp/pmut/ctlhq-mode/bin" "$tmp/pmut/ctlhq-mode/scripts" "$tmp/pmut/run-method/references"
cp "$root/skills/ctlhq-mode/bin/ctlhq-plan-lint" "$tmp/pmut/ctlhq-mode/bin/"
cp "$root/$tpl" "$tmp/pmut/run-method/references/"
sed '/does not run the harness/d' "$root/skills/ctlhq-mode/scripts/check-plan.mjs" > "$tmp/pmut/ctlhq-mode/scripts/check-plan.mjs"
if cmp -s "$tmp/pmut/ctlhq-mode/scripts/check-plan.mjs" "$root/skills/ctlhq-mode/scripts/check-plan.mjs"; then bad "project positive control: the planted defect did not change check-plan.mjs"; else ok; fi
"$tmp/pmut/ctlhq-mode/bin/ctlhq-plan-lint" --project "$tmp/pnoharness.md" >/dev/null 2>&1
expect_rc 0 $? "project positive control: the mutant passes the M0-without-harness plan, so check 14c would catch the defect"

echo "$pass checks passed"
if [ "$fail" -gt 0 ]; then
	echo "$fail checks failed"
	exit 1
fi
