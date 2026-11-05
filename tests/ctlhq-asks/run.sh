#!/usr/bin/env bash
set -u
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
asks="$root/bin/ctlhq-asks"
pass=0
fail=0
ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL: $1"; }
expect_rc() { if [ "$1" -eq "$2" ]; then ok; else bad "$3 (expected exit $1, got $2)"; fi; }
expect_eq() { if [ "$1" = "$2" ]; then ok; else bad "$3 (expected '$1', got '$2')"; fi; }
expect_grep() { if printf '%s\n' "$2" | grep -Eq -- "$1"; then ok; else bad "$3 (no line matches: $1)"; fi; }
expect_nogrep() { if printf '%s\n' "$2" | grep -Eq -- "$1"; then bad "$3 (a line matches: $1)"; else ok; fi; }

tmp="$(mktemp -d "${TMPDIR:-/tmp}/ctlhq-asks-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home"
mkdir -p "$HOME"
state="$HOME/.ctlhq/asks.json"

out="$("$asks" --help 2>&1)"; rc=$?
expect_rc 0 "$rc" "--help exits 0"
expect_eq "ctlhq-asks: keep one list of open questions for the operator, across projects." "$(printf '%s\n' "$out" | head -1)" "--help opens with name and one line"

out="$("$asks" list 2>&1)"; rc=$?
expect_rc 0 "$rc" "list with no state file exits 0"
expect_eq "No open questions." "$out" "list says when nothing is open"
[ ! -e "$state" ] && ok || bad "list creates no state file"

out="$("$asks" add ctlhq "May I push the branch?" 2>&1)"; rc=$?
expect_rc 0 "$rc" "add exits 0"
expect_eq "ctlhq-1" "$out" "the first question of a project is number 1"
expect_eq "600" "$(stat -f %Lp "$state" 2>/dev/null || stat -c %a "$state")" "only the owner can read the state file"

expect_eq "ctlhq-2" "$("$asks" add ctlhq "Keep the old flag?")" "the next question takes the next number"
expect_eq "crewtalk-1" "$("$asks" add crewtalk "Install the new build?")" "each project counts by itself"

printf 'Run this block?\n\n```\nsudo true\n```\n' >"$tmp/multi.txt"
expect_eq "crewtalk-2" "$("$asks" add crewtalk <"$tmp/multi.txt")" "add reads the text from stdin when none is given"

out="$("$asks" list)"; rc=$?
expect_rc 0 "$rc" "list exits 0"
expect_grep '^Open questions: 4$' "$out" "list opens with the count"
expect_eq "End of open questions." "$(printf '%s\n' "$out" | tail -1)" "list closes with its end line"
expect_grep '^ctlhq-1: May I push the branch\?$' "$out" "list holds the name and full text"
expect_grep '^crewtalk-1: Install the new build\?$' "$out" "list covers every project"
expect_grep '^sudo true$' "$out" "list keeps every line of a question"
expect_eq "ctlhq-1" "$(printf '%s\n' "$out" | sed -n 's/^\(ctlhq-1\): .*/\1/p')" "a name appears once"

printf '%s\n' "$out" >"$tmp/reply.md"
printf '\nNext step: you answer the open questions.\n' >>"$tmp/reply.md"
out="$("$root/bin/ctlhq-reply-lint" "$tmp/reply.md" 2>&1)"; rc=$?
expect_rc 0 "$rc" "ctlhq-reply-lint accepts the list as printed: $out"
printf 'Open questions: 1\n\nctlhq-1: May I push the branch?\n\nNext step: you answer the open questions.\n' >"$tmp/plain.md"
out="$("$root/bin/ctlhq-reply-lint" "$tmp/plain.md" 2>&1)"; rc=$?
expect_rc 0 "$rc" "ctlhq-reply-lint accepts a list with no code block: $out"
s6="$("$asks" add stored 'May I start S6 now?')"
out="$( { "$asks" list; printf '\nNext step: you answer %s.\n' "$s6"; } | "$root/bin/ctlhq-reply-lint" 2>&1)"; rc=$?
expect_rc 0 "$rc" "stored text that a rule would refuse does not block the pasted list: $out"
"$asks" close "$s6" "yes" >/dev/null
out="$( { "$asks" list; printf '\nNext step: you answer the questions above.\n'; } | "$root/bin/ctlhq-reply-lint" 2>&1)"; rc=$?
expect_rc 0 "$rc" "the list and a next step that points above it exit 0: $out"
out="$( { "$asks" list; printf '\nNext step: you run the block in crewtalk-2.\n'; } | "$root/bin/ctlhq-reply-lint" 2>&1)"; rc=$?
expect_rc 0 "$rc" "a command block held in the list counts for the next step: $out"

out="$("$asks" close ctlhq-1 "yes, push it" 2>&1)"; rc=$?
expect_rc 0 "$rc" "close exits 0"
expect_eq "closed ctlhq-1" "$out" "close names what it closed"
out="$("$asks" list)"
expect_nogrep '^ctlhq-1:' "$out" "a closed question leaves the list"
expect_grep '^Open questions: 3$' "$out" "the count drops"
expect_grep '"answer": "yes, push it"' "$(cat "$state")" "close records the answer"

"$asks" close ctlhq-2 "keep it" >/dev/null
expect_eq "ctlhq-3" "$("$asks" add ctlhq "A third question?")" "a closed name is never given out again"

deferred="$("$asks" add ctlhq "Rename the tool?")"
"$asks" close "$deferred" deferred >/dev/null
expect_nogrep "^$deferred:" "$("$asks" list)" "a question closed as deferred leaves the list"
expect_grep '"answer": "deferred"' "$(cat "$state")" "the state keeps the answer deferred"
expect_grep 'deferred' "$("$asks" --help)" "--help says how to defer a question"
expect_nogrep '"added"' "$(cat "$state")" "no unread field is stored"

out="$("$asks" close ctlhq-1 "again" 2>&1)"; rc=$?
expect_rc 1 "$rc" "closing a closed question exits 1"
expect_grep 'ctlhq-1 is already closed' "$out" "the refusal names the question"
expect_grep '"answer": "yes, push it"' "$(cat "$state")" "the first answer stays"
out="$("$asks" close ctlhq-99 "yes" 2>&1)"; rc=$?
expect_rc 1 "$rc" "closing an unknown name exits 1"
expect_grep 'no question named ctlhq-99' "$out" "the refusal names the unknown name"

"$asks" add >/dev/null 2>&1; expect_rc 2 $? "add with no project exits 2"
"$asks" add "Bad Name" "text" >/dev/null 2>&1; expect_rc 2 $? "a project name with a space exits 2"
"$asks" add ctlhq "   " >/dev/null 2>&1; expect_rc 2 $? "blank text exits 2"
"$asks" close ctlhq-3 >/dev/null 2>&1 </dev/null; expect_rc 2 $? "close with no answer exits 2"
"$asks" >/dev/null 2>&1; expect_rc 2 $? "no command exits 2"
"$asks" nonsense >/dev/null 2>&1; expect_rc 2 $? "an unknown command exits 2"

pids=""
for i in 1 2 3 4 5 6 7 8; do
	"$asks" add race "Question $i?" >"$tmp/race.$i" & pids="$pids $!"
done
for p in $pids; do wait "$p"; done
expect_eq "8" "$(cat "$tmp"/race.* | sort -u | wc -l | tr -d ' ')" "8 concurrent adds get 8 different names"
expect_eq "race-8" "$(cat "$tmp"/race.* | sort -t- -k2 -n | tail -1)" "concurrent adds leave no gap"

cp "$state" "$tmp/good.json"
printf 'not json' >"$state"
out="$("$asks" add ctlhq "Lost?" 2>&1)"; rc=$?
expect_rc 1 "$rc" "a damaged state file exits 1"
expect_grep 'cannot read' "$out" "the refusal says the file cannot be read"
expect_eq "not json" "$(cat "$state")" "a damaged state file is left as it was"
"$asks" list >/dev/null 2>&1; expect_rc 1 $? "list on a damaged state file exits 1"
printf '{"asks": 5}' >"$state"
"$asks" list >/dev/null 2>&1; expect_rc 1 $? "a state file of the wrong shape exits 1"
printf '{"asks": [{"name": "a-1"}]}' >"$state"
"$asks" add a "Lost?" >/dev/null 2>&1; expect_rc 1 $? "a row with missing fields exits 1"
python3 -I -c "print('[' * 200000)" >"$state"
out="$("$asks" list 2>&1)"; rc=$?
expect_rc 1 "$rc" "a very deeply nested state file exits 1"
expect_nogrep 'Traceback' "$out" "a very deeply nested state file prints no traceback"
for shape in '{"asks": {}}' '{"asks": [5]}' '{"asks": [{"name": "a", "project": "a", "text": "t", "closed": null, "answer": null}]}'; do
	printf '%s' "$shape" >"$state"
	out="$("$asks" list 2>&1)"; rc=$?
	expect_rc 1 "$rc" "list refuses a state file of the wrong shape: $shape"
	expect_grep 'cannot read' "$out" "the refusal names the file: $shape"
	expect_nogrep 'Traceback' "$out" "list prints no traceback: $shape"
	out="$("$asks" add a "Lost?" 2>&1)"; rc=$?
	expect_rc 1 "$rc" "add refuses a state file of the wrong shape: $shape"
	expect_nogrep 'Traceback' "$out" "add prints no traceback: $shape"
	expect_eq "$shape" "$(cat "$state")" "the file stays as it was: $shape"
done
rm -f "$state"

"$asks" add "$(printf 'nl\n ')" "text" >/dev/null 2>&1; expect_rc 2 $? "a project name with a space and a newline exits 2"
"$asks" add $'nl\n' "text" >/dev/null 2>&1; expect_rc 2 $? "a project name that ends in a newline exits 2"
out="$("$asks" add bytes $'caf\xe9?' 2>&1)"; rc=$?
expect_rc 2 "$rc" "text that is not UTF-8 exits 2"
expect_nogrep 'Traceback' "$out" "text that is not UTF-8 prints no traceback"
out="$(printf 'caf\351?' | "$asks" add bytes 2>&1)"; rc=$?
expect_rc 2 "$rc" "stdin that is not UTF-8 exits 2"
expect_nogrep 'Traceback' "$out" "stdin that is not UTF-8 prints no traceback"
expect_eq "" "$(find "$HOME/.ctlhq" -name '*.tmp')" "a refused add leaves no temporary file"

agents="$(tr -s ' \n' ' ' <"$root/home/AGENTS.md")"
expect_grep 'ctlhq-asks add' "$agents" "the home rule says how to add a question"
expect_grep 'ctlhq-asks close' "$agents" "the home rule says how to close a question"
expect_grep 'ctlhq-asks list' "$agents" "the home rule says how to print the list"
expect_grep 'list. before .Next step' "$agents" "the home rule puts the list before the next step"
expect_grep 'NAME ANSWER., or ANSWER .deferred. to defer it' "$agents" "the home rule says how to defer a question"
expect_grep "section 9 stays the project's own record" "$agents" "the home rule says what section 9 holds"
expect_grep 'coordinator relays a report only if final, blocked, or needing the operator' "$agents" "the home rule names who relays a report"

echo "$pass checks passed"
if [ "$fail" -gt 0 ]; then
	echo "$fail checks failed"
	exit 1
fi
