#!/usr/bin/env bash
# tests/ctlhq-reply-lint/run.sh: checks for bin/ctlhq-reply-lint on synthetic replies.
# Prints "N checks passed" and exits 1 when any check fails. Writes only to a
# temporary folder (TMPDIR honoured); never touches ~/.ctlhq or the repository.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
rl="$root/bin/ctlhq-reply-lint"
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
expect_nogrep() {
	if printf '%s\n' "$2" | grep -Eq -- "$1"; then bad "$3 (a line matches: $1)"; else ok; fi
}
count() { printf '%s\n' "$2" | grep -Ec -- "$1"; }

tmp="$(mktemp -d "${TMPDIR:-/tmp}/ctlhq-reply-lint-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

# A clean reply: glossed label, expanded abbreviation, backticked token, numbered list
# and table, status line, code block content ignored, Next step line.
cat >"$tmp/clean.md" <<'MD'
The lint tool is ready for review.

Status: implemented and tested with `tests/ctlhq-reply-lint/run.sh` (exit 0).

1. Phase D3 (the new app frame) now opens the Work folder.
2. The Model Context Protocol (MCP) server starts with the app.
3. The `S6` check stays as it was, and MCP needs no second gloss.

| # | file | lines |
|---|---|---|
| 1 | bin/ctlhq-reply-lint | 300 |

```
D34 XYZ — this code block is ignored, and so is “this”.
```

Next step: none from you.
MD

# A reply that triggers each of the 13 rules exactly once (status-line needs over 120 words,
# so --max-words 100 also trips max-words).
{
	echo "The D34 change went in and QRS now works."
	echo "The bug is fixed."
	echo "Here is a “quote” here."
	echo "A dash — here."
	echo "I hope this helps."
	echo "Great question about the plan."
	echo
	echo "- one"
	echo "- two"
	echo "- three"
	echo
	echo "| file | lines |"
	echo "|---|---|"
	echo "| a | 1 |"
	echo
	echo "This sentence is deliberately written to be very long so that it goes well past the limit of twenty five words that the reply rules set for one sentence."
	for i in 1 2 3 4 5 6 7 8 9 10; do echo "Short line number $i keeps the count of words in this reply growing."; done
} >"$tmp/bad.md"

# 1. --help.
out="$("$rl" --help 2>&1)"; rc=$?
expect_rc 0 "$rc" "--help exits 0"
expect_grep '^ctlhq-reply-lint: ' "$(printf '%s\n' "$out" | head -1)" "--help first line is 'ctlhq-reply-lint: ...'"
expect_grep 'Stop hook' "$out" "--help documents the Stop hook"

# 2. Clean reply: no findings, exit 0, from a file and from stdin.
out="$("$rl" "$tmp/clean.md" 2>&1)"; rc=$?
expect_rc 0 "$rc" "clean reply exits 0"
expect_eq "0 failures, 0 warnings" "$out" "clean reply has no findings"
out="$("$rl" <"$tmp/clean.md" 2>&1)"; rc=$?
expect_rc 0 "$rc" "clean reply on stdin exits 0"

# 3. Bad reply: every rule once, 6 failures and 7 warnings, exit 1.
out="$("$rl" --max-words 100 "$tmp/bad.md" 2>&1)"; rc=$?
expect_rc 1 "$rc" "bad reply exits 1"
for rule in table-number long-dash curly-quote next-step max-words label-gloss abbreviation \
	sentence-length numbered-list status-line claim-evidence chatbot-phrase sycophantic-tone; do
	expect_eq 1 "$(count "^[0-9]+: $rule: " "$out")" "rule $rule fires once"
done
expect_eq "6 failures, 7 warnings" "$(printf '%s\n' "$out" | tail -1)" "summary line counts"
expect_grep '^1: label-gloss: fail: D34 ' "$out" "label-gloss names D34 on line 1"
expect_grep '^1: abbreviation: warning: QRS ' "$out" "abbreviation is a warning naming QRS on line 1"
expect_grep '^2: claim-evidence: warning: ' "$out" "claim-evidence is a warning on line 2"

# 4. --json: an array with the same 13 rows; summary on stderr.
json="$("$rl" --json --max-words 100 "$tmp/bad.md" 2>/dev/null)"; rc=$?
expect_rc 1 "$rc" "--json bad reply exits 1"
expect_eq "13 6" "$(printf '%s' "$json" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(len(d), sum(1 for f in d if f["severity"]=="fail"))')" "--json has 13 rows, 6 failures"
err="$("$rl" --json --max-words 100 "$tmp/bad.md" 2>&1 >/dev/null)"
expect_eq "6 failures, 7 warnings" "$err" "--json summary goes to stderr"

# 5. Options: --no-next-step, --allow, --max-words default 400.
out="$("$rl" --no-next-step --allow D34,QRS "$tmp/bad.md" 2>&1)"
expect_eq 0 "$(count ': (next-step|label-gloss|abbreviation): ' "$out")" "--no-next-step and --allow silence three rules"
expect_eq 0 "$(count ': max-words: ' "$out")" "default limit 400 is not reached"
# An unexpanded abbreviation is a warning, and no list exempts it.
printf 'The run used 77 MB over HTTPS and QZX.\n\nNext step: none from you.\n' >"$tmp/abbr.md"
out="$("$rl" "$tmp/abbr.md" 2>&1)"; rc=$?
expect_rc 0 "$rc" "abbreviations alone exit 0"
expect_eq 3 "$(count ': abbreviation: warning: (MB|HTTPS|QZX) ' "$out")" "each abbreviation is still reported as a warning"
expect_eq 0 "$(count ': abbreviation: fail: ' "$out")" "no abbreviation is a failure"
printf 'It is done.\n\nNext step: none from you.\n' >"$tmp/warn.md"
"$rl" "$tmp/warn.md" >/dev/null 2>&1; expect_rc 0 $? "warnings alone exit 0"
printf 'Fixed in 4b22be9 (exit 0).\n\nNext step: none from you.\n' >"$tmp/ev.md"
out="$("$rl" "$tmp/ev.md" 2>&1)"
expect_eq "0 failures, 0 warnings" "$out" "a hash or exit code on the line satisfies claim-evidence"
status() { printf '%s\n\nNext step: none from you.\n' "$1" | "$rl" 2>&1; }
out="$(status 'Status: fixed.')"; expect_rc 1 "$?" "a status-line claim with no evidence fails"
expect_grep "^1: claim-evidence: fail: 'fixed' " "$out" "claim-evidence names 'fixed' as a failure"
out="$(status '1. Status: done.')"; expect_rc 1 "$?" "a status line after a list marker fails the same way"
for s in 'Status: tested (tests/x/run.sh exit 0).' 'Status: tested (tests/x/run.sh).' 'Status: committed 4b22be9.' '**Status.** tested, the gate exited 0.'; do
	expect_eq "0 failures, 0 warnings" "$(status "$s")" "status line with an exit code, hash, or test name: $s"
done
for s in 'Status: implemented. Nothing is committed.' 'Status: proposed, not tested.'; do
	out="$(status "$s")"; expect_rc 0 "$?" "a negated claim word on the status line is no claim: $s"
done
out="$(status 'Status: fixed, not yet committed.')"; expect_rc 1 "$?" "a negation after the claim word leaves the claim"
out="$(status 'Status: no failures, committed.')"; expect_rc 1 "$?" "a negation stops at a comma"
for s in 'The plan says what done means.' 'Reviewer B tested the parser and found 2 bugs.' \
	'Ask the operator whether the draft is ready.' 'The main agent marks the milestone done in PLAN.md section 7.'; do
	out="$(status "$s")"; expect_rc 0 "$?" "a claim word off the status line does not fail: $s"
done
printf 'The lock-wait defect (D34) is open.\n\nNext step: none from you.\n' >"$tmp/gl.md"
out="$("$rl" "$tmp/gl.md" 2>&1)"
expect_eq "0 failures, 0 warnings" "$out" "a label inside a parenthesis counts as glossed"

# 6. --hook: Stop hook JSON on stdin; exit 2 blocks with findings on stderr.
hj="$(python3 -c 'import json,sys; print(json.dumps({"last_assistant_message": open(sys.argv[1]).read()}))' "$tmp/bad.md")"
err="$(printf '%s' "$hj" | "$rl" --hook 2>&1 >/dev/null)"; rc=$?
expect_rc 2 "$rc" "--hook with a failing reply exits 2"
expect_grep 'next-step: fail' "$err" "--hook prints findings on stderr"
hj="$(python3 -c 'import json,sys; print(json.dumps({"last_assistant_message": open(sys.argv[1]).read()}))' "$tmp/clean.md")"
printf '%s' "$hj" | "$rl" --hook >/dev/null 2>&1; expect_rc 0 $? "--hook with a clean reply exits 0"
printf '{"stop_hook_active": true, "last_assistant_message": "x"}' | "$rl" --hook >/dev/null 2>&1
expect_rc 0 $? "--hook exits 0 when stop_hook_active is set"

# 7. Usage errors.
"$rl" --bogus >/dev/null 2>&1; expect_rc 2 $? "unknown option exits 2"
"$rl" --max-words x "$tmp/clean.md" >/dev/null 2>&1; expect_rc 2 $? "--max-words x exits 2"
"$rl" "$tmp/nosuch.md" >/dev/null 2>&1; expect_rc 2 $? "missing file exits 2"
"$rl" "$tmp/clean.md" "$tmp/bad.md" >/dev/null 2>&1; expect_rc 2 $? "two files exit 2"


# Word budget: 400 plain, 600 when a table or list is present.
w500="$(python3 -c "print(' '.join(['word']*500))")"
w650="$(python3 -c "print(' '.join(['word']*650))")"
out="$(printf '%s Next step: none.' "$w500" | "$rl" 2>&1)"; expect_rc 1 "$?" "500 plain words exceed 400"
out="$(printf '| # | a |\n|---|---|\n| 1 | b |\n\n%s Next step: none.' "$w500" | "$rl" 2>&1)"; expect_rc 0 "$?" "500 words with a table fit 600"
out="$(printf '1. a\n2. b\n\n%s Next step: none.' "$w650" | "$rl" 2>&1)"; expect_rc 1 "$?" "650 words with a list exceed 600"
expect_grep 'limit 600, table or list present' "$out" "message names the structured limit"
out="$(printf '1. a\n2. b\n\n%s Next step: none.' "$w500" | "$rl" --max-words-structured 450 2>&1)"; expect_rc 1 "$?" "--max-words-structured lowers the second limit"

# operator-command: a next step for the operator that names an action needs a code block.
out="$(printf 'Status: implemented.\n\nNext step: you run the symlink check in a fresh session.' | "$rl" 2>&1)"; expect_rc 1 "$?" "operator step without a command fails"
expect_grep 'operator-command' "$out" "operator-command named"
out="$(printf 'Status: implemented.\n\n```\nclaude -p hi\n```\n\nNext step: you run the command above.' | "$rl" 2>&1)"; expect_rc 0 "$?" "operator step with a code block passes"
out="$(printf 'Status: implemented.\n\nNext step: none from you. Main agent runs the tests.' | "$rl" 2>&1)"; expect_rc 0 "$?" "main-agent step needs no code block"

# 8. Wave 3 rules: double-meaning, step-actor, vague-noun.
printf 'Status: implemented.\n\nThe gate passed and the build qualifies.\n\nSteps:\n\n1. Run the import test.\n2. Open the report.\n\nThe other thing is open.\n\nNext step: none from you.\n' >"$tmp/w3.md"
out="$("$rl" "$tmp/w3.md" 2>&1)"; expect_rc 0 "$?" "double-meaning and step-actor warn, never block"
expect_grep "^3: double-meaning: warning: 'passed' " "$out" "double-meaning names 'passed' on line 3"
expect_eq 2 "$(count ': step-actor: warning: ' "$out")" "two steps with no actor"
expect_grep "^10: vague-noun: warning: 'thing' " "$out" "vague-noun is a warning on line 10"
expect_eq "0 failures, 4 warnings" "$(printf '%s\n' "$out" | tail -1)" "wave 3 summary counts"
printf 'Status: implemented.\n\nYou run these steps:\n\n1. Run the import test.\n2. The main agent opens the report.\n\nNext step: you run the command above.\n\n```\nbin/test\n```\n' >"$tmp/actor.md"
out="$("$rl" "$tmp/actor.md" 2>&1)"; expect_rc 0 "$?" "a lead-in line naming the actor satisfies step-actor"
printf 'The `pass` field stays.\n\nNext step: none from you.\n' >"$tmp/tick.md"
out="$("$rl" "$tmp/tick.md" 2>&1)"; expect_eq "0 failures, 0 warnings" "$out" "a backticked word is not a double-meaning label"

# 9. --approval: an approval question asked in chat.
printf 'Approve commit 4b22be9 for scope_3?\n\nNext step: you answer yes or no.\n' >"$tmp/ap-bad.md"
out="$("$rl" --approval "$tmp/ap-bad.md" 2>&1)"; expect_rc 1 "$?" "approval text with a hash fails"
expect_grep '^1: approval-first-sentence: fail: ' "$out" "first sentence must address the operator"
expect_eq 2 "$(count ': approval-id: fail: ' "$out")" "hash and scope id both flagged"
printf 'You will see the import page open with your files listed.\n\nShip the importer now or wait for the parser fix?\n\nNext step: you answer yes or no.\n' >"$tmp/ap-ok.md"
out="$("$rl" --approval "$tmp/ap-ok.md" 2>&1)"; expect_rc 0 "$?" "a plain approval question exits 0"
"$rl" "$tmp/ap-bad.md" >/dev/null 2>&1; expect_rc 0 "$?" "without --approval the approval rules stay off"
printf 'You get the report today.\n\nShould the main agent ship the importer now or wait two more weeks for the parser fix to land?\n\nNext step: you answer yes or no.\n' | "$rl" --approval >"$tmp/ap-long.out" 2>&1
expect_rc 1 "$?" "a long question fails"
expect_grep 'approval-budget: fail: question of 19 words \(limit 15\)' "$(cat "$tmp/ap-long.out")" "question budget 15"
printf '{"question":"Approve the importer now?","what_changes":"It ships today."}\n' >"$tmp/req.json"
out="$("$rl" --approval "$tmp/req.json" 2>&1)"; expect_rc 1 "$?" "a JSON object is read as chat text, not as a request file"
expect_grep '^1: approval-first-sentence: fail: ' "$out" "JSON text gets the chat approval rules"
expect_eq 0 "$(count 'what_changes' "$out")" "no request-file rule runs"
printf '{}' | "$rl" --approval --hook >/dev/null 2>&1; expect_rc 2 "$?" "--approval with --hook exits 2"
expect_grep 'approval-budget' "$("$rl" --help)" "--help documents --approval"


# --hook-json: the Codex Stop hook shape (same input as --hook; JSON on stdout, exit 0).
hj() { python3 -I -c 'import json,sys; print(json.dumps({"hook_event_name":"Stop","session_id":"s1","last_assistant_message": sys.argv[1]}))' "$1" | "$rl" --hook-json; }
out="$(hj 'Done. no next')"; expect_rc 0 "$?" "--hook-json exits 0 on a failing reply"
expect_grep '"decision": "block"' "$out" "--hook-json blocks a failing reply"
out="$(hj 'Status: implemented. Next step: none from you.')"; expect_eq '{"continue": true}' "$out" "--hook-json continues on a clean reply"
out="$(printf '{"stop_hook_active": true, "last_assistant_message": "x"}' | "$rl" --hook-json)"; expect_eq '{"continue": true}' "$out" "--hook-json continues when the stop hook is already active"
# vague-pronoun: a block that opens with It, They, or This/That plus a verb warns; a named noun does not.
printf 'It builds the skill.\n\nThis skill builds a folder.\n\n1. They run fast.\n\n| # | note |\n|---|---|\n| 1 | That is wrong |\n\nNext step: none from you.\n' >"$tmp/pron.md"
out="$("$rl" "$tmp/pron.md" 2>&1)"; rc=$?
expect_rc 0 "$rc" "pronoun warnings alone exit 0"
expect_eq 3 "$(count ': vague-pronoun: warning: ' "$out")" "It, They, and That is each warn once"
expect_eq 0 "$(count '^3: vague-pronoun' "$out")" "This skill builds names the thing and does not warn"

# 10. Turn warnings. next-step-open: the reply reports a finished item, the plan has a next step,
# BLOCKED.md has no open row, and nobody asks a question. repeat-reply: same next step line as the
# previous reply, no new fact, no operator message since. Both are warnings (exit 0); under the
# hooks they are sent back once per operator message.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
mkdir -p "$tmp/t"; export TMPDIR="$tmp/t"
proj="$tmp/proj"
mkdir -p "$proj"
git -C "$proj" init -q
cat >"$proj/PLAN.md" <<'MD'
# Plan

## 7. Milestone status

| # | Milestone | Done when | State |
|---|---|---|---|
| M0 | Thin journey | `scripts/verify` exits 0 | done |
| M1 | Import page | `tests/import` exits 0 | planned |
MD
printf '# Blocked\n\n| # | Blocked step | Reason | Command that fails | Owner |\n|---|---|---|---|---|\n\nNo open blockers.\n' >"$proj/BLOCKED.md"
nso() { "$rl" --repo "$proj" "$1" 2>&1; }
printf 'The thin journey is committed in 4b22be9 (exit 0).\n\nNext step: none from you.\n' >"$tmp/stop.md"
out="$(nso "$tmp/stop.md")"; rc=$?
expect_rc 0 "$rc" "next-step-open is a warning, never a failure"
expect_grep '^3: next-step-open: warning: this reply reports a finished item, PLAN.md line 8 has a next step \(Import page, planned\)' "$out" "next-step-open names the plan row on the next step line"
expect_eq "0 failures, 1 warnings" "$(printf '%s\n' "$out" | tail -1)" "next-step-open is the only finding"
out="$("$rl" "$tmp/stop.md" 2>&1)"
expect_eq "0 failures, 0 warnings" "$out" "quiet case: without --repo the rule does not run"
printf 'The setting lives in `config.toml` under the server section.\n\nNext step: none from you.\n' >"$tmp/casual.md"
expect_eq 0 "$(count ': next-step-open: ' "$(nso "$tmp/casual.md")")" "quiet case: a plain answer reports no finished item"
printf 'The thin journey is committed in 4b22be9 (exit 0).\n\nShould the main agent start the import page now?\n\nNext step: none from you.\n' >"$tmp/ask.md"
expect_eq 0 "$(count ': next-step-open: ' "$(nso "$tmp/ask.md")")" "quiet case: the reply asks a question"
printf 'The thin journey is committed in 4b22be9 (exit 0).\n\nNext step: you answer yes or no on the import page scope.\n' >"$tmp/yours.md"
expect_eq 0 "$(count ': next-step-open: ' "$(nso "$tmp/yours.md")")" "quiet case: the next step line hands the step to the operator"
printf 'The thin journey is committed in 4b22be9 (exit 0). The import builder is still running.\n\nNext step: mine, when the import builder reports.\n' >"$tmp/wait.md"
expect_eq 0 "$(count ': next-step-open: ' "$(nso "$tmp/wait.md")")" "quiet case: the next step line waits on running work"
printf 'The thin journey is committed in 4b22be9 (exit 0). Nothing is waiting on you.\n\nNext step: none from you.\n' >"$tmp/nowait.md"
expect_eq 1 "$(count ': next-step-open: ' "$(nso "$tmp/nowait.md")")" "'Nothing is waiting on you' does not silence the warning"
printf 'The thin journey is committed in 4b22be9 (exit 0).\n\nNext step: I merge after the review is done.\n' >"$tmp/afterdone.md"
expect_eq 1 "$(count ': next-step-open: ' "$(nso "$tmp/afterdone.md")")" "'after ... done' does not silence the warning"
mkdir -p "$tmp/noplan"; git -C "$tmp/noplan" init -q
expect_eq 0 "$(count ': next-step-open: ' "$("$rl" --repo "$tmp/noplan" "$tmp/stop.md" 2>&1)")" "quiet case: a repository with no PLAN.md"
cp "$proj/BLOCKED.md" "$tmp/blocked.bak"
printf '# Blocked\n\n| # | Blocked step | Reason | Command that fails | Owner |\n|---|---|---|---|---|\n| 1 | screen capture | not done: needs Screen Recording for Terminal | scripts/verify shot | operator |\n' >"$proj/BLOCKED.md"
expect_eq 0 "$(count ': next-step-open: ' "$(nso "$tmp/stop.md")")" "quiet case: BLOCKED.md has an open row ('not done' stays open)"
cp "$tmp/blocked.bak" "$proj/BLOCKED.md"
sed -i.bak 's/| planned |/| done |/' "$proj/PLAN.md"; rm -f "$proj/PLAN.md.bak"
expect_eq 0 "$(count ': next-step-open: ' "$(nso "$tmp/stop.md")")" "quiet case: every milestone is done"
sed -i.bak 's/`tests\/import` exits 0 | done |/`tests\/import` exits 0 | in progress |/' "$proj/PLAN.md"; rm -f "$proj/PLAN.md.bak"
hook_in() { python3 -c 'import json,sys; d={"session_id": sys.argv[3], "last_assistant_message": open(sys.argv[1]).read()}
if sys.argv[2]: d["cwd"] = sys.argv[2]
if len(sys.argv) > 4 and sys.argv[4]: d["transcript_path"] = sys.argv[4]
if len(sys.argv) > 5: d["stop_hook_active"] = True
print(json.dumps(d))' "$@"; }
err="$(hook_in "$tmp/stop.md" "$proj" s1 | "$rl" --hook 2>&1 >/dev/null)"; rc=$?
expect_rc 2 "$rc" "--hook sends next-step-open back once (exit 2)"
expect_grep 'warning, sent once' "$err" "--hook says the warning is sent once"
expect_grep 'next-step-open: warning: .*\(Import page, in progress\)' "$err" "--hook names the in-progress row from the hook cwd"
expect_eq 1 "$(ls "$TMPDIR/ctlhq-reply-lint/sent" | wc -l | tr -d ' ')" "--hook writes one sent marker under the temp folder"
expect_eq 0 "$(ls -A "$proj/.local/reply-lint" 2>/dev/null | wc -l | tr -d ' ')" "--hook writes nothing into the project"
hook_in "$tmp/stop.md" "$proj" s1 "" active | "$rl" --hook >/dev/null 2>&1; expect_rc 0 $? "--hook lets the second stop through (stop_hook_active)"
hook_in "$tmp/stop.md" "$proj" s1 | "$rl" --hook >/dev/null 2>&1; expect_rc 0 $? "--hook lets the second stop through without stop_hook_active (marker)"
out="$(hook_in "$tmp/stop.md" "$proj" s2 | "$rl" --hook-json)"
expect_grep '"decision": "block"' "$out" "--hook-json sends next-step-open back once"
expect_grep 'warning, sent once' "$out" "--hook-json reason says the warning is sent once"
out="$(hook_in "$tmp/stop.md" "$proj" s2 | "$rl" --hook-json)"; expect_eq '{"continue": true}' "$out" "--hook-json second stop goes through with no stop_hook_active"
out="$(hook_in "$tmp/wait.md" "$proj" s3 | "$rl" --hook-json)"; expect_eq '{"continue": true}' "$out" "--hook-json stays quiet for a wait reply"

printf 'The import builder is still running.\n\nNext step: mine, when it reports.\n' >"$tmp/prev.md"
printf 'Same state: the import builder is still running.\n\nNext step: Mine, when it reports.\n' >"$tmp/again.md"
out="$("$rl" --previous "$tmp/prev.md" "$tmp/again.md" 2>&1)"; rc=$?
expect_rc 0 "$rc" "repeat-reply is a warning, never a failure"
expect_grep '^3: repeat-reply: warning: same next step line as the previous reply and no new fact \(2 new words' "$out" "repeat-reply counts the new words"
expect_eq "0 failures, 1 warnings" "$(printf '%s\n' "$out" | tail -1)" "repeat-reply is the only finding"
printf 'The import builder finished: `tests/import` exited 0 at 4b22be9.\n\nNext step: mine, when it reports.\n' >"$tmp/news.md"
expect_eq 0 "$(count ': repeat-reply: ' "$("$rl" --previous "$tmp/prev.md" "$tmp/news.md" 2>&1)")" "quiet case: a new number, path, or code is a new fact"
printf 'The reviewer read the import page and found two broken links in the header menu and footer area.\n\nNext step: mine, when it reports.\n' >"$tmp/words.md"
expect_eq 0 "$(count ': repeat-reply: ' "$("$rl" --previous "$tmp/prev.md" "$tmp/words.md" 2>&1)")" "quiet case: 10 or more new words are a new fact"
printf 'Same state: the import builder is still running.\n\nNext step: mine, rerun the import test.\n' >"$tmp/other.md"
expect_eq 0 "$(count ': repeat-reply: ' "$("$rl" --previous "$tmp/prev.md" "$tmp/other.md" 2>&1)")" "quiet case: a different next step line"
"$rl" --previous "$tmp/nosuch.md" "$tmp/again.md" >/dev/null 2>&1; expect_rc 2 $? "--previous with a missing file exits 2"
printf '{}' | "$rl" --hook --repo "$proj" >/dev/null 2>&1; expect_rc 2 $? "--hook with --repo exits 2"

# The hooks read the transcript: the previous reply (the last assistant text before the newest
# operator or system turn) and the newest operator message, in Claude Code and Codex formats.
python3 - "$tmp" "$tmp/prev.md" "$tmp/again.md" <<'PY'
import json, os, sys
tmp, prev, cur = sys.argv[1], open(sys.argv[2]).read(), open(sys.argv[3]).read()
def user(ts, text):
    return {"type": "user", "timestamp": ts, "sessionId": "s9", "cwd": tmp, "isSidechain": False, "uuid": "u" + ts,
            "parentUuid": None, "userType": "external", "message": {"role": "user", "content": text}}
def assistant(ts, mid, text):
    return {"type": "assistant", "timestamp": ts, "sessionId": "s9", "cwd": tmp, "isSidechain": False, "uuid": "a" + ts,
            "message": {"id": mid, "role": "assistant", "content": [{"type": "text", "text": text}]}}
def claude(name, between, first="Build the import page."):
    rows = [user("2026-10-19T10:00:00.000Z", first),
            assistant("2026-10-19T10:00:05.000Z", "m1", "Starting the import builder."),
            user("2026-10-19T10:01:00.000Z", "<task-notification>builder progress</task-notification>"),
            assistant("2026-10-19T10:01:05.000Z", "m2", prev),
            user("2026-10-19T10:02:00.000Z", between),
            assistant("2026-10-19T10:02:05.000Z", "m3", cur)]
    with open(os.path.join(tmp, name), "w") as fh:
        for r in rows:
            fh.write(json.dumps(r) + "\n")
claude("claude.jsonl", "<task-notification>builder progress</task-notification>")
claude("claude-op.jsonl", "Keep going with the import page.")
claude("claude-ask.jsonl", "<task-notification>builder progress</task-notification>", "What is left on the import page?")
def cx(kind, ts, payload):
    return {"timestamp": ts, "type": kind, "payload": payload}
def msg(ts, role, text):
    kind = "output_text" if role == "assistant" else "input_text"
    return cx("response_item", ts, {"type": "message", "role": role, "content": [{"type": kind, "text": text}]})
def um(ts, text):
    return cx("event_msg", ts, {"type": "user_message", "message": text})
rows = [cx("session_meta", "2026-10-19T10:00:00.000Z", {"id": "cccccccc-0000-0000-0000-000000000010", "timestamp": "2026-10-19T10:00:00.000Z", "cwd": tmp, "originator": "codex_cli", "source": "cli"}),
        um("2026-10-19T10:00:01.000Z", "Build the import page."),
        msg("2026-10-19T10:00:05.000Z", "assistant", prev),
        msg("2026-10-19T10:01:00.000Z", "user", "<subagent_notification>builder progress</subagent_notification>"),
        msg("2026-10-19T10:01:05.000Z", "assistant", cur)]
with open(os.path.join(tmp, "rollout-2026-10-19T10-00-00-cccccccc-0000-0000-0000-000000000010.jsonl"), "w") as fh:
    for r in rows:
        fh.write(json.dumps(r, separators=(",", ":")) + "\n")
PY
err="$(hook_in "$tmp/again.md" "" t1 "$tmp/claude.jsonl" | "$rl" --hook 2>&1 >/dev/null)"; rc=$?
expect_rc 2 "$rc" "--hook sends repeat-reply back once, previous reply from a Claude Code transcript"
expect_grep 'repeat-reply: warning: ' "$err" "--hook names repeat-reply"
hook_in "$tmp/again.md" "" t1 "$tmp/claude.jsonl" | "$rl" --hook >/dev/null 2>&1; expect_rc 0 $? "the second stop for the same operator message goes through (marker in the temp folder)"
hook_in "$tmp/news.md" "" t2 "$tmp/claude.jsonl" | "$rl" --hook >/dev/null 2>&1; expect_rc 0 $? "quiet case: --hook with a new fact against the transcript exits 0"
hook_in "$tmp/again.md" "" t3 "$tmp/claude-op.jsonl" | "$rl" --hook >/dev/null 2>&1; expect_rc 0 $? "quiet case: an operator message came after the previous reply"
hook_in "$tmp/stop.md" "$proj" t4 "$tmp/claude-ask.jsonl" | "$rl" --hook >/dev/null 2>&1; expect_rc 0 $? "quiet case: the newest operator message asks a question"
hook_in "$tmp/stop.md" "$proj" t5 "$tmp/claude-op.jsonl" | "$rl" --hook >/dev/null 2>&1; expect_rc 2 $? "next-step-open fires when the newest operator message is not a question"
cxp="$tmp/rollout-2026-10-19T10-00-00-cccccccc-0000-0000-0000-000000000010.jsonl"
out="$(hook_in "$tmp/again.md" "" t6 "$cxp" | "$rl" --hook-json)"
expect_grep '"decision": "block".*repeat-reply' "$out" "--hook-json reads the previous reply from a Codex transcript"
out="$(hook_in "$tmp/again.md" "" t6 "$cxp" | "$rl" --hook-json)"; expect_eq '{"continue": true}' "$out" "--hook-json second stop on the Codex transcript goes through"
expect_grep 'Turn warnings' "$("$rl" --help)" "--help documents the turn warnings"

cat >"$tmp/mistake-proof.md" <<'MD'
You corrected the commit message rule twice, so the lesson belongs in a check.

Status: proposed, nothing changed yet.

1. The first correction was a long dash in the commit message.
2. The second correction was the same long dash one commit later.

The `/mistake-proof` skill turns a repeated correction into a lint, a type, or a test. Only you can start it.

```
/mistake-proof
```

Next step: you paste the command above, or you tell me to skip it.
MD
out="$("$rl" "$tmp/mistake-proof.md" 2>&1)"; rc=$?
expect_rc 0 "$rc" "the /mistake-proof offer with its code block exits 0"
expect_eq "0 failures, 0 warnings" "$out" "the /mistake-proof offer has no findings"

while IFS= read -r line; do
	[ -n "$line" ] || continue
	out="$(printf '%s\n\nNext step: none from you.\n' "$line" | "$rl" 2>&1)"; rc=$?
	expect_rc 1 "$rc" "flagged: $line"
	expect_grep '^1: question-elsewhere: fail: ' "$out" "named question-elsewhere: $line"
done <<'TXT'
You answer questions 1 to 3 from my last message.
Can you answer questions 1 to 3 from my last message?
Please answer what I asked in my last message.
Please answer my earlier question.
Please answer questions 1 to 3 in my message above.
Answer the questions from earlier.
Answer the questions above.
Will you answer the questions above?
You answer questions 1 to 5 above.
You answer questions 1 to 4 from my last two messages.
You answer decisions 1 to 3 from my last summary, yes or no.
You reply yes or no to my last 3 decisions.
You review the branch, then answer question 4 from my earlier message.
May the builder replace the installed build, as asked above?
As I asked you earlier, may I push?
Keep the two folders separate, as asked in my last reply?
The operator answers questions 1 to 3 from my last message.
Next step: operator answers the questions above.
The operator decides decision 2 from my last message.
The operator approves decision 2 from my last message.
You decide questions 1 to 3 from my last message.
You approve decision 2 from my last message.
Questions 1 to 4 from my earlier message stay open.
Questions 1 to 4 from my last message are still open.
Questions 1 to 4 from my last two messages are still open.
Decisions 1 and 2 from my previous reply are still open.
Two questions are still open from my last reply.
Your six questions from my last message are still open too.
The two open decisions from my last reply.
The one left is the open decision 1 from my last message.
TXT
printf 'You answer questions 1 to 3 from my last\nmessage.\n\nNext step: none from you.\n' >"$tmp/wrapped.md"
out="$("$rl" "$tmp/wrapped.md" 2>&1)"; rc=$?
expect_rc 1 "$rc" "a pointer that wraps over two lines is flagged"
expect_grep '^1: question-elsewhere: fail: ' "$out" "a wrapped pointer reports its first line"
expect_grep "$root/bin/ctlhq-asks list" "$out" "the refusal gives the full path of the list command"
expect_grep "$root/bin/ctlhq-asks add" "$out" "the refusal says how to add a missing question"

while IFS= read -r line; do
	[ -n "$line" ] || continue
	out="$(printf '%s\n\nNext step: none from you.\n' "$line" | "$rl" 2>&1)"
	expect_nogrep 'question-elsewhere' "$out" "not flagged: $line"
done <<'TXT'
Questions 1 to 3 are still open.
Are questions 1 to 3 from my last message still open?
Decision 1 from my last message is still open: should I make the edit myself? I recommend yes.
No questions are open from my last message.
None of the questions from my last message is open.
The question from my last message is no longer open.
Question 1 from my previous reply is not open.
The open question from my last message is closed.
Decisions 1 to 3 from my earlier summary stay open.
The open file holds the decision from my last commit message.
Open-source users read the question from my last reply.
You answer questions 1 and 2.
I also wrote "as asked above" and "from my last message", which sends you hunting.
You answer "questions 1 to 3 from my last message" with the old form.
The rule flags “questions 1 to 3 are open” in a reply.
> You answer questions 1 to 3 from my last message.
The check refuses `you answer questions 1 to 3 from my last message` in a reply.
I dropped my earlier question about fixing the error message.
I settled three questions from earlier records, so none of them goes to you.
Ended its turn, as asked.
You asked earlier whether the push waits.
You also asked earlier whether the push waits.
They asked earlier whether the push waits.
The operator asked earlier for a shorter list.
Main asked earlier for a shorter list.
The reviewer asked above whether the push waits.
I ran the tests as asked earlier.
I ran the tests as asked before the merge.
Should the wait be one minute? I recommend yes (asked earlier).
Decision: run the install as above? I recommend yes.
Decision 6: add the check (table above) to the build? I recommend yes.
The plan records the scheduling decision above.
My answer to question 4 is yes.
The answer to question 4 from my last message is yes.
Answer to question 2: yes.
Answer for question 2 from my last message: yes.
Answer on question 2: yes.
Answer: yes to question 2 from my last message.
Answer: question 3 from my last message is closed.
Reply: question 3 from my last message is closed.
I have no answer to question 2 yet.
This reply answers question 2.
The logs confirm question 3 from my last message is closed.
The builder's reply to question 3 from my last message is in the log.
You asked me to answer question 3 from my last message.
You gave the answer to question 3 from my last message.
You do not need to answer question 3 from my last message.
Your answer to question 4 from my last message is in the plan.
If you reply, question 3 from my last message closes.
When you confirm the plan, I will close question 3 from my last message.
The skill keeps questions 4 to 8 from the shared list.
Correction: the decision in my last reply named the wrong hash.
No questions remain from my last message.
All questions from my last message are now closed.
I withdraw my last two questions.
The decision is recorded in my last commit message.
Questions 1 and 2 from my last message are replaced by the questions below.
That covers decision 1 from my earlier message.
Please hold your answers to my last 5 questions until the plan is back.
My earlier decision still stands.
Question 1 is no longer open.
None of questions 1 to 3 is open.
No decisions are pending from my last reply.
Only questions 1 and 2 were open, and both are closed now.
Your question 5 is waiting for my reply.
Your question 3 is open and I answer it below.
I am waiting on the test to answer your question 3.
Every answer holds except question 3.
Decision 8 in the plan says this stays open.
The plan's decision 4 waits on the install.
The open file holds question 3.
The test waits for question 3 to finish.
If you reply, question 3 closes.
You can reply later, and decision 2 is recorded.
When the operator answers, the plan from my last reply changes.
If the operator decides, my earlier decision stays.
The operator's answer to question 3 from my last message is in the plan.
The operator approved the plan from my last message.
You approved the plan from my last message.
The operator asked me to answer question 3 from my last message.
You run the command from my last reply.
You start the sessions with the prompt from my earlier reply.
Will you run the commit block from my previous reply yourself?
TXT
printf '1 - May I push?\n2 - Keep it?\n\nQuestions 1 and 2 are open.\n\nNext step: you answer questions 1 and 2.\n' >"$tmp/own-list.md"
out="$("$rl" "$tmp/own-list.md" 2>&1)"
expect_nogrep 'question-elsewhere' "$out" "a reply with its own list is free in any list form"
printf '1. May I push?\n\nNext step: you answer the question above.\n' >"$tmp/own-above.md"
out="$("$rl" "$tmp/own-above.md" 2>&1)"
expect_nogrep 'question-elsewhere' "$out" "a pointer above is free when this reply holds a question"
printf 'Next step: you answer the three questions above with yes or no:\n\n1. May I push?\n' >"$tmp/own-below.md"
out="$("$rl" "$tmp/own-below.md" 2>&1)"
expect_nogrep 'question-elsewhere' "$out" "a pointer above is free when the reply's question sits below"
printf 'Decision 1: push or hold.\n\nNext step: you answer decision 1 above.\n' >"$tmp/own-decision.md"
out="$("$rl" "$tmp/own-decision.md" 2>&1)"
expect_nogrep 'question-elsewhere' "$out" "a pointer above is free when the reply names a decision with no question mark"
printf 'The build finished.\n\nNext step: you answer the questions above.\n' >"$tmp/no-question.md"
out="$("$rl" "$tmp/no-question.md" 2>&1)"
expect_grep 'question-elsewhere' "$out" "a pointer above fires when the reply holds no question"
printf '```\nyou answer questions 1 to 3 from my last message\n```\n\nNext step: none from you.\n' >"$tmp/fenced.md"
out="$("$rl" "$tmp/fenced.md" 2>&1)"
expect_nogrep 'question-elsewhere' "$out" "fenced code is not flagged"

pointer='You answer questions 1 to 3 from my last message.\n\nNext step: none from you.'
err="$(printf '{"last_assistant_message": "%s"}' "$pointer" | "$rl" --hook 2>&1 >/dev/null)"; rc=$?
expect_rc 2 "$rc" "--hook blocks a pointer"
expect_grep 'question-elsewhere: fail' "$err" "--hook names the rule"
out="$(printf '{"last_assistant_message": "%s"}' "$pointer" | "$rl" --hook-json 2>/dev/null)"; rc=$?
expect_rc 0 "$rc" "--hook-json exits 0 on a pointer"
expect_grep '"decision": "block"' "$out" "--hook-json blocks a pointer"
expect_grep 'question-elsewhere' "$out" "--hook-json names the rule"

for unit in 'question ' 'question 1 ' 'you answer '; do
	python3 -I -c 'import sys; print(sys.argv[1] * 20000)' "$unit" >"$tmp/long.md"
	start=$SECONDS
	"$rl" "$tmp/long.md" >/dev/null 2>&1
	[ $((SECONDS - start)) -lt 20 ] && ok || bad "20000 repeats of '$unit' in one sentence take under 20 s"
done

printf 'Open questions: 1\n\nctlhq-1: May I push the branch?\n\nNext step: you answer the open questions.\n' >"$tmp/plain.md"
out="$("$rl" "$tmp/plain.md" 2>&1)"; rc=$?
expect_rc 0 "$rc" "a plain list and its next step exit 0: $out"
printf 'Next step: you open the page in the browser.\n' >"$tmp/open.md"
out="$("$rl" "$tmp/open.md" 2>&1)"; rc=$?
expect_rc 1 "$rc" "you open a page still needs a command block"
expect_grep 'operator-command' "$out" "you open a page still names operator-command"

question='May I push the branch to the remote now that the review is finished, knowing that this step sends the commits to GitHub, where every reader can see them, and that nothing else depends on it today and tomorrow?'
{
	printf 'Open questions: 16\n\n'
	for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16; do printf 'ctlhq-%s: %s\n\nA second paragraph of the same question.\n\n' "$i" "$question"; done
	printf 'End of open questions.\n\nNext step: you answer the open questions.\n'
} >"$tmp/long-list.md"
out="$("$rl" "$tmp/long-list.md" 2>&1)"; rc=$?
expect_rc 0 "$rc" "a long pasted list exits 0"
expect_nogrep 'max-words' "$out" "a long pasted list is not held to the word limit"
{ for i in $(seq 1 500); do printf 'word '; done; printf '\n\n'; cat "$tmp/long-list.md"; } >"$tmp/long-prose.md"
out="$("$rl" "$tmp/long-prose.md" 2>&1)"
expect_grep 'max-words: fail: 50[0-9] words' "$out" "text before the list still counts, and the list does not"
{ printf 'Open questions: 1\n\nctlhq-1: May I push?\n\nEnd of open questions.\n\n'; for i in $(seq 1 500); do printf 'word '; done; printf '\n\nNext step: none from you.\n'; } >"$tmp/after-list.md"
out="$("$rl" "$tmp/after-list.md" 2>&1)"
expect_grep 'max-words: fail: 50[0-9] words' "$out" "text after the list still counts"
{ printf 'Open questions: 1\n\n'; for i in $(seq 1 500); do printf 'word '; done; printf '\n\nNext step: none from you.\n'; } >"$tmp/no-end.md"
out="$("$rl" "$tmp/no-end.md" 2>&1)"
expect_grep 'max-words: fail' "$out" "a heading with no end line is checked as usual"
for stored in 'May I start S6 now?' 'May I push — now?' 'You answer questions 1 to 3 from my last message.' 'Run this?\n\n```\nsudo true'; do
	printf "Open questions: 1\n\nctlhq-1: $stored\n\nEnd of open questions.\n\nNext step: you answer ctlhq-1.\n" >"$tmp/stored.md"
	out="$("$rl" "$tmp/stored.md" 2>&1)"; rc=$?
	expect_rc 0 "$rc" "stored text cannot block a reply: $stored: $out"
done
printf 'Open questions: 1\n\nctlhq-1: May I push?\n\nEnd of open questions.\n\nNext step: you answer the questions above.\n' >"$tmp/list-above.md"
out="$("$rl" "$tmp/list-above.md" 2>&1)"; rc=$?
expect_rc 0 "$rc" "a pointer above the pasted list exits 0: $out"
printf 'Open questions: 1\n\ncrewtalk-1: Run this block?\n\n```\nsudo true\n```\n\nEnd of open questions.\n\nNext step: you run the block in crewtalk-1.\n' >"$tmp/list-block.md"
out="$("$rl" "$tmp/list-block.md" 2>&1)"; rc=$?
expect_rc 0 "$rc" "a command block inside the pasted list counts for the next step: $out"
printf 'Open questions: 1\n\nctlhq-1: May I push?\n\nEnd of open questions.\n\nThe S6 work — done.\n\nNext step: none from you.\n' >"$tmp/stored-after.md"
out="$("$rl" "$tmp/stored-after.md" 2>&1)"
expect_grep '^7: long-dash' "$out" "a long dash after the list is still found, on its own line number"
expect_grep 'label-gloss' "$out" "a label after the list is still found"

long_question='May I push the whole branch to the public remote now that the long review of every commit on it has finished?'
printf 'You get the branch on the remote once you say yes.\n\nOpen questions: 1\n\nctlhq-1: %s\n\nEnd of open questions.\n\nNext step: you answer ctlhq-1.\n' "$long_question" >"$tmp/ap-list.md"
out="$("$rl" --approval "$tmp/ap-list.md" 2>&1)"; rc=$?
expect_rc 0 "$rc" "--approval accepts a pasted list and its fixed names: $out"
printf 'You get the branch on the remote once you say yes.\n\nOpen questions: 1\n\nctlhq-1: May I push?\n\nEnd of open questions.\n\nNext step: you answer other-7.\n' >"$tmp/ap-other.md"
out="$("$rl" --approval "$tmp/ap-other.md" 2>&1)"; rc=$?
expect_rc 1 "$rc" "--approval still refuses a name that the pasted list does not hold"
expect_grep "approval-id: fail: 'other-7'" "$out" "the refusal names the unlisted id"

echo "$pass checks passed"
if [ "$fail" -gt 0 ]; then
	echo "$fail checks failed"
	exit 1
fi
