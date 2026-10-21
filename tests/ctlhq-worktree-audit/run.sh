#!/usr/bin/env bash
# tests/ctlhq-worktree-audit/run.sh: checks for skills/ctlhq-mode/bin/ctlhq-worktree-audit (and the script
# it runs, skills/ctlhq-mode/scripts/worktree-audit.sh) through bin/ctlhq-worktree-audit.
# Builds scratch git repositories with worktrees in a mktemp folder. Every audit run passes
# --no-fetch except check 9c, whose origin is a missing local folder, so no run uses the
# network. HOME points at the
# scratch folder (for git config and the Claude Code and Codex transcript folders), and PATH
# holds stub gh, rg, and origin commands (rg because it may be missing, gh so no network call
# is made, origin to prove the audit never runs it), then /usr/bin:/bin.
# Prints "N checks passed" and exits 1 when any check fails. Read-only for the repository.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
wa="$root/bin/ctlhq-worktree-audit"
tmp="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/worktree-audit-test.XXXXXX")" && pwd -P)"
trap 'rm -rf "$tmp"' EXIT
pass=0
fail=0
ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL: $1"; }
expect_rc() { if [ "$1" -eq "$2" ]; then ok; else bad "$3 (expected exit $1, got $2)"; fi; }
expect_eq() { if [ "$1" = "$2" ]; then ok; else bad "$3 (expected '$1', got '$2')"; fi; }
expect_grep() { if printf '%s\n' "$2" | grep -Eq -- "$1"; then ok; else bad "$3 (no line matches: $1)"; fi; }
expect_no() { if printf '%s\n' "$2" | grep -Eq -- "$1"; then bad "$3 (a line matches: $1)"; else ok; fi; }

# Scratch environment: HOME, git config, stub gh and rg, a minimal PATH.
export HOME="$tmp/home" GIT_CONFIG_NOSYSTEM=1
mkdir -p "$HOME" "$tmp/stubs"
printf '[user]\n\tname = t\n\temail = t@example.com\n[commit]\n\tgpgsign = false\n[init]\n\tdefaultBranch = main\n' > "$HOME/.gitconfig"
cat > "$tmp/stubs/gh" <<'SH'
#!/bin/sh
echo "gh $*" >> "$HOME/gh.log"
[ -f "$HOME/gh.fail" ] && exit 1
cat "$HOME/gh.json"
SH
cat > "$tmp/stubs/rg" <<'SH'
#!/bin/bash
: > "$HOME/rg.pats"; dirs=()
while [ $# -gt 0 ]; do
	case "$1" in
	-l|-F) shift ;;
	-e) printf '%s\n' "$2" >> "$HOME/rg.pats"; shift 2 ;;
	*) dirs+=("$1"); shift ;;
	esac
done
grep -rlF -f "$HOME/rg.pats" "${dirs[@]}"
SH
cat > "$tmp/stubs/origin" <<'SH'
#!/bin/sh
echo "origin $*" >> "$HOME/origin.log"
echo '[{"number":99,"status":"merged","headRef":"wip-br"}]'
SH
chmod +x "$tmp/stubs/gh" "$tmp/stubs/rg" "$tmp/stubs/origin"
export PATH="$tmp/stubs:/usr/bin:/bin"
g() { git "$@" >/dev/null 2>&1 || bad "setup: git $*"; }
commit() { # dir file [extra env]: add a file and commit it
	(cd "$1" && echo "$2" > "$2" && git add "$2" && git commit -qm "$2") >/dev/null 2>&1 || bad "setup: commit $2 in $1"
}

g init -q --bare "$tmp/origin.git"
m="$tmp/main"; g init -q "$m"
commit "$m" a.txt
g -C "$m" remote add origin "$tmp/origin.git"
g -C "$m" push -q origin main
g -C "$m" fetch -q origin
g -C "$m" remote set-head origin main
wt() { g -C "$m" worktree add -q "$tmp/$1" -b "$2"; }
wt wt-merged merged-br
wt wt-wip wip-br; commit "$tmp/wt-wip" b.txt; echo more >> "$tmp/wt-wip/a.txt"
wt wt-scratch scratch-br; commit "$tmp/wt-scratch" s.txt
dd if=/dev/zero of="$tmp/wt-scratch/big.bin" bs=1024 count=3000 2>/dev/null
wt wt-openpr open-br; commit "$tmp/wt-openpr" o.txt; g -C "$tmp/wt-openpr" push -q origin open-br
wt wt-mergedpr sq-br; commit "$tmp/wt-mergedpr" q.txt
wt wt-closedpr closed-br; commit "$tmp/wt-closedpr" x.txt
wt wt-ahead ahead-br; commit "$tmp/wt-ahead" h.txt; g -C "$tmp/wt-ahead" push -q origin ahead-br; commit "$tmp/wt-ahead" h2.txt
wt wt-behind behind-br; commit "$tmp/wt-behind" k.txt; g -C "$tmp/wt-behind" push -q origin behind-br; g -C "$tmp/wt-behind" reset -q --hard HEAD~1
wt wt-diverged diverged-br; commit "$tmp/wt-diverged" d.txt; g -C "$tmp/wt-diverged" push -q origin diverged-br; g -C "$tmp/wt-diverged" reset -q --hard HEAD~1; commit "$tmp/wt-diverged" d2.txt; commit "$tmp/wt-diverged" d3.txt
g -C "$m" fetch -q origin
g -C "$m" worktree add -q --detach "$tmp/wt-detached"
wt wt-old old-br
(cd "$tmp/wt-old" && echo z > z.txt && git add z.txt && GIT_COMMITTER_DATE="$(( $(date +%s) - 30 * 86400 )) +0000" git commit -qm old) >/dev/null 2>&1 || bad "setup: old commit"
wt wt-recent recent-br; commit "$tmp/wt-recent" r.txt
trd="$HOME/.claude/projects/$(printf '%s' "$m" | sed 's#/#-#g')"; mkdir -p "$trd"
printf '{"cwd":"%s/wt-recent/src"}\n' "$tmp" > "$trd/chat1.jsonl"
printf '{"cwd":"%s/wt-merged-other/"}\n' "$tmp" > "$trd/chat3.jsonl"
cxd="$HOME/.codex/sessions/2026/10/10"; mkdir -p "$cxd"
printf '{"type":"session_meta","payload":{"cwd":"%s/wt-old"}}\n' "$tmp" > "$cxd/rollout-chat2.jsonl"
own="$HOME/.claude/projects/$(printf '%s' "$tmp/wt-behind" | sed 's#[/._]#-#g')"; mkdir -p "$own"
printf '{"cwd":"%s/wt-behind"}\n' "$tmp" > "$own/chat4.jsonl"
old_ts=$(( $(date +%s) - 10 * 86400 ))
python3 -c 'import os, sys; os.utime(sys.argv[1], (int(sys.argv[2]), int(sys.argv[2])))' "$cxd/rollout-chat2.jsonl" "$old_ts"
old_day="$(python3 -c 'import sys, time; print(time.strftime("%Y-%m-%d", time.localtime(int(sys.argv[1]))))' "$old_ts")"
today="$(date '+%Y-%m-%d')"
printf '[{"number":11,"state":"OPEN","headRefName":"open-br"},{"number":12,"state":"MERGED","headRefName":"sq-br"},{"number":13,"state":"CLOSED","headRefName":"closed-br"}]' > "$HOME/gh.json"
before_list="$(git -C "$m" worktree list --porcelain)"
before_wip="$(git -C "$tmp/wt-wip" status --porcelain)"

row() { printf '%s\n' "$1" | awk -F'\t' -v w="$tmp/$2" '$9 == w'; }
col() { # table worktree "n n ...": the named columns of that worktree's row, space-separated
	printf '%s\n' "$1" | awk -F'\t' -v w="$tmp/$2" -v cs="$3" '$9 == w {n = split(cs, c, " "); s = ""; for (i = 1; i <= n; i++) s = s (i > 1 ? " " : "") $(c[i]); print s}'
}

# 1. --help through the wrapper.
out="$("$wa" --help 2>&1)"; expect_rc 0 $? "--help exits 0"
expect_grep '^ctlhq-worktree-audit: ' "$(printf '%s\n' "$out" | head -1)" "--help first line is 'ctlhq-worktree-audit: ...'"
for word in '-b <ref>' '--no-fetch' '--recent-days <n>' 'hold-wip' 'hold-open-pr' 'verify-recent-chat' 'safe' 'review' 'behind<n>' 'Exit 0'; do
	expect_grep "$word" "$out" "--help names $word"
done
expect_eq "$out" "$("$wa" -h 2>&1)" "-h prints the same help"
expect_eq "$out" "$("$wa" --no-fetch -h 2>&1)" "-h after another flag still prints help"

# 2. Default base: origin/HEAD, with a warning; the table shape.
out="$(cd "$m" && "$wa" --no-fetch 2>"$tmp/err")"; rc=$?
expect_rc 0 "$rc" "audit exits 0 after the table"
expect_eq "warn: no -b given; MERGED checks against origin/main" "$(cat "$tmp/err")" "no -b warns and names origin/HEAD's branch"
expect_eq "# base: origin/main" "$(printf '%s\n' "$out" | sed -n 1p)" "first line names the base"
expect_eq "$(printf 'SIZE\tAGE\tMERGED\tDIRTY\tREMOTE\tPR\tLAST_CHAT\tBUCKET\tWORKTREE')" "$(printf '%s\n' "$out" | sed -n 2p)" "column header"
expect_eq "" "$(row "$out" main)" "the main worktree is not listed"
expect_eq "$tmp/wt-scratch" "$(printf '%s\n' "$out" | sed -n 3p | cut -f9)" "rows are sorted by size, largest first"
expect_eq 9 "$(printf '%s\n' "$out" | sed -n 3p | awk -F'\t' '{print NF}')" "a row has 9 tab-separated columns"

# 3. Buckets and columns per worktree.
expect_eq "YES clean no-remote - - safe" "$(col "$out" wt-merged '3 4 5 6 7 8')" "wt-merged: commit in the base gives safe"
expect_eq "wip:1 hold-wip" "$(col "$out" wt-wip '4 8')" "wt-wip: a tracked edit gives hold-wip"
expect_eq "scratch:1 review" "$(col "$out" wt-scratch '4 8')" "wt-scratch: only untracked files give scratch and review"
expect_grep '^[0-9.]+M$' "$(col "$out" wt-scratch 1)" "wt-scratch SIZE is in megabytes"
expect_eq "pushed #11/open hold-open-pr" "$(col "$out" wt-openpr '5 6 8')" "wt-openpr: pushed, open PR gives hold-open-pr"
expect_eq "no #12/merged safe" "$(col "$out" wt-mergedpr '3 6 8')" "wt-mergedpr: a squash-merged PR gives safe"
expect_eq "#13/closed review" "$(col "$out" wt-closedpr '6 8')" "wt-closedpr: a PR closed without merge gives review"
expect_eq "ahead1 review" "$(col "$out" wt-ahead '5 8')" "wt-ahead: one local commit past origin gives ahead1"
expect_eq "detached -" "$(col "$out" wt-detached '5 6')" "wt-detached: REMOTE detached, PR -"
expect_eq "30d" "$(col "$out" wt-old 2)" "AGE counts days since the HEAD commit"
expect_eq "0d" "$(col "$out" wt-merged 2)" "AGE of a fresh commit is 0d"
expect_eq "$today verify-recent-chat" "$(col "$out" wt-recent '7 8')" "a Claude Code transcript from today in the main worktree's folder gives LAST_CHAT and verify-recent-chat"
expect_eq "$old_day review" "$(col "$out" wt-old '7 8')" "a 10-day-old Codex transcript shows its date but stays out of verify-recent-chat"
expect_eq "$today verify-recent-chat" "$(col "$out" wt-behind '7 8')" "a Claude Code transcript in the worktree's own folder gives LAST_CHAT"
expect_eq "#12/merged" "$(col "$out" wt-mergedpr 6)" "PR state comes from gh even when a program named origin is on PATH"
[ ! -e "$HOME/origin.log" ] && ok || bad "the audit never runs a program named origin from PATH"
expect_eq "-" "$(col "$out" wt-merged 7)" "a transcript for wt-merged-other does not match wt-merged"
expect_grep 'pr list --author @me --state all' "$(cat "$HOME/gh.log")" "PR state comes from gh pr list --author @me --state all"
expect_eq "behind1" "$(col "$out" wt-behind 5)" "wt-behind: one origin commit not local gives behind1"
expect_eq "ahead2-behind1" "$(col "$out" wt-diverged 5)" "wt-diverged: two local and one origin-only commit give ahead2-behind1"

# 4. --recent-days.
out="$(cd "$m" && "$wa" --no-fetch --recent-days 20 2>/dev/null)"
expect_eq "verify-recent-chat" "$(col "$out" wt-old 8)" "--recent-days 20 puts the 10-day-old chat in verify-recent-chat"
out="$(cd "$m" && "$wa" --no-fetch --recent-days 0 2>/dev/null)"
expect_eq "verify-recent-chat" "$(col "$out" wt-recent 8)" "--recent-days 0 still counts a chat from today"

# 5. -b and --base, repo-path argument, run from a linked worktree.
out="$("$wa" --no-fetch -b main "$m" 2>"$tmp/err")"; rc=$?
expect_rc 0 "$rc" "-b main with a repo path exits 0"
expect_eq "# base: main" "$(printf '%s\n' "$out" | head -1)" "-b sets the base"
expect_eq "" "$(cat "$tmp/err")" "-b gives no warning"
expect_eq "$out" "$("$wa" --no-fetch --base main "$m" 2>/dev/null)" "--base equals -b"
out2="$(cd "$tmp/wt-wip" && "$wa" --no-fetch -b main 2>/dev/null)"
expect_eq "$(printf '%s\n' "$out" | sort)" "$(printf '%s\n' "$out2" | sort)" "running inside a linked worktree audits the same repository"
g -C "$m" checkout -q -b local-base
commit "$m" lb.txt
expect_eq "YES" "$(col "$("$wa" --no-fetch -b local-base "$m" 2>/dev/null)" wt-merged 3)" "MERGED follows the -b ref"
g -C "$m" checkout -q main

# 6. --no-fetch leaves the remote-tracking ref alone.
g clone -q "$tmp/origin.git" "$tmp/other"; commit "$tmp/other" new.txt; g -C "$tmp/other" push -q origin main
before="$(git -C "$m" rev-parse origin/main)"
(cd "$m" && "$wa" --no-fetch >/dev/null 2>&1)
expect_eq "$before" "$(git -C "$m" rev-parse origin/main)" "--no-fetch does not move origin/main"

# 7. PR lookup failure: no PR data, the open-PR worktree falls back to review.
touch "$HOME/gh.fail"
out="$(cd "$m" && "$wa" --no-fetch 2>/dev/null)"; rc=$?
rm -f "$HOME/gh.fail"
expect_rc 0 "$rc" "a failing gh still prints the table"
expect_eq "- review" "$(col "$out" wt-openpr '6 8')" "control: without PR data wt-openpr is review (the bucket depends on gh)"

# 8. A worktree path that holds a space.
g -C "$m" worktree add -q "$tmp/wt space" -b space-br
out="$(cd "$m" && "$wa" --no-fetch 2>/dev/null)"
expect_eq "0d clean no-remote safe" "$(col "$out" "wt space" '2 4 5 8')" "a worktree path with a space is listed whole, with its own AGE, DIRTY, and REMOTE"
expect_eq "" "$(row "$out" wt)" "a worktree path with a space is not cut at the space"
g -C "$m" worktree remove "$tmp/wt space"

# 9. Exit 1 cases.
mkdir -p "$tmp/plain"
err="$(cd "$tmp/plain" && "$wa" --no-fetch 2>&1)"; rc=$?
expect_rc 1 "$rc" "outside a git repository with no path exits 1"
expect_grep 'not in a git repo' "$err" "outside a git repository is explained"
err="$("$wa" --no-fetch "$tmp/plain" 2>&1)"; rc=$?
expect_rc 1 "$rc" "a repo path that is not a git repository exits 1"
expect_grep 'not a git repo' "$err" "a non-repository path is named"
"$wa" --no-fetch "$tmp/does-not-exist" >/dev/null 2>&1; expect_rc 1 $? "a missing repo path exits 1"
g init -q "$tmp/noorigin"; commit "$tmp/noorigin" n.txt
err="$("$wa" --no-fetch "$tmp/noorigin" 2>&1)"; rc=$?
expect_rc 1 "$rc" "a repository without origin and no -b exits 1"
expect_grep 'no base ref' "$err" "a missing base is explained"
expect_grep '^# base: main$' "$("$wa" --no-fetch -b main "$tmp/noorigin" 2>/dev/null)" "a repository without origin works with -b main"
err="$("$wa" --no-fetch -b no-such-ref "$m" 2>&1)"; rc=$?
expect_rc 1 "$rc" "-b with an unknown ref exits 1"
expect_grep 'base ref not found: no-such-ref' "$err" "-b with an unknown ref is named"

# 9b. Every error prints three lines: "ctlhq-worktree-audit: <what>", "why: <why>", "fix: <command>".
# expect_err <err> <what pattern> <exact fix line> <label>
expect_err() {
	expect_eq 3 "$(printf '%s\n' "$1" | grep -c '')" "$4: three lines"
	expect_grep "^ctlhq-worktree-audit: $2" "$(printf '%s\n' "$1" | sed -n 1p)" "$4: the what line"
	expect_grep '^why: [^ ]' "$(printf '%s\n' "$1" | sed -n 2p)" "$4: a why line"
	expect_eq "fix: $3" "$(printf '%s\n' "$1" | sed -n 3p)" "$4: the fix line"
}
err="$(cd "$tmp/plain" && "$wa" --no-fetch 2>&1)"
expect_err "$err" "not in a git repo: $tmp/plain\$" "ctlhq-worktree-audit <path to the repository>" "outside a repository"
err="$("$wa" --no-fetch "$tmp/plain" 2>&1)"
expect_err "$err" "not a git repo: $tmp/plain\$" "ctlhq-worktree-audit <path to the repository>" "a non-repository path"
err="$("$wa" --no-fetch "$tmp/does-not-exist" 2>&1)"
expect_err "$err" "repo path not found: $tmp/does-not-exist\$" "ctlhq-worktree-audit <path to the repository>" "a missing repo path"
err="$("$wa" --no-fetch "$tmp/noorigin" 2>&1)"
expect_err "$err" "no base ref in $tmp/noorigin: origin/HEAD, origin/main, and origin/master are all missing\$" \
	"ctlhq-worktree-audit -b main $tmp/noorigin (or another ref that \`git -C $tmp/noorigin branch -a\` lists)" "no base ref"
err="$("$wa" --no-fetch -b no-such-ref "$m" 2>&1)"
expect_err "$err" "base ref not found: no-such-ref\$" "ctlhq-worktree-audit -b <ref> $m with a ref that \`git -C $m branch -a\` lists" "an unknown -b ref"
err="$("$wa" --no-fetch -b origin/nope "$m" 2>&1)"
expect_err "$err" "base ref not found: origin/nope\$" "ctlhq-worktree-audit -b <ref> $m with a ref that \`git -C $m branch -a\` lists, or drop --no-fetch so the audit fetches it" "an unknown origin ref with --no-fetch"
err="$("$wa" --no-fetch -b 2>&1)"
expect_err "$err" "-b needs a ref\$" "ctlhq-worktree-audit -b <ref> [repo-path], for example -b origin/main" "-b without a ref"
err="$("$wa" --no-fetch --base 2>&1)"
expect_err "$err" "--base needs a ref\$" "ctlhq-worktree-audit --base <ref> [repo-path], for example --base origin/main" "--base without a ref"
err="$("$wa" --no-fetch --recent-days 2>&1)"
expect_err "$err" "--recent-days needs a number of days\$" "ctlhq-worktree-audit --recent-days 4 [repo-path]" "--recent-days without a number"
err="$("$wa" --no-fetch --recent-days abc "$m" 2>&1)"
expect_err "$err" "--recent-days needs a whole number, got: abc\$" "ctlhq-worktree-audit --recent-days 4 [repo-path]" "--recent-days abc"
err="$("$wa" --no-fetch --bogus "$m" 2>&1)"
expect_err "$err" "unknown option: --bogus\$" "ctlhq-worktree-audit --help" "an unknown option"
q_space="$(printf '%q' "$tmp/no origin")"
g init -q "$tmp/no origin"; commit "$tmp/no origin" n.txt
err="$("$wa" --no-fetch "$tmp/no origin" 2>&1)"
expect_err "$err" "no base ref in $tmp/no origin: " "ctlhq-worktree-audit -b main $q_space (or another ref that \`git -C $q_space branch -a\` lists)" "a repo path with a space is quoted in the fix"

# 9c. A failed fetch of the base warns with a fix line and still prints the table.
g init -q "$tmp/deadorigin"; commit "$tmp/deadorigin" f.txt
g -C "$tmp/deadorigin" remote add origin "$tmp/no-such-origin.git"
g -C "$tmp/deadorigin" update-ref refs/remotes/origin/main HEAD
out="$("$wa" -b origin/main "$tmp/deadorigin" 2>"$tmp/err")"; rc=$?
expect_rc 0 "$rc" "a failed fetch still exits 0"
expect_eq "# base: origin/main" "$(printf '%s\n' "$out" | head -1)" "a failed fetch still prints the table"
expect_eq "$(printf 'warn: could not fetch origin/main; merged column may be stale\nfix: git -C %s fetch origin (to see the error), or pass --no-fetch' "$tmp/deadorigin")" "$(cat "$tmp/err")" "a failed fetch prints a warn line and a fix line"
out="$("$wa" --help 2>&1)"
expect_grep 'Every error prints three lines on stderr: "ctlhq-worktree-audit: <what>", "why: <why>", and' "$out" "--help documents the error lines"

# 10. Usage errors exit 2.
"$wa" --no-fetch -b >/dev/null 2>&1; expect_rc 2 $? "-b without a ref exits 2"
"$wa" --no-fetch --recent-days >/dev/null 2>&1; expect_rc 2 $? "--recent-days without a number exits 2"
err="$("$wa" --no-fetch --recent-days abc "$m" 2>&1)"; rc=$?
expect_rc 2 "$rc" "--recent-days abc exits 2"
expect_grep 'needs a whole number, got: abc' "$err" "--recent-days abc is explained"
"$wa" --no-fetch --recent-days -3 "$m" >/dev/null 2>&1; expect_rc 2 $? "--recent-days -3 exits 2"
"$wa" --no-fetch --bogus "$m" >/dev/null 2>&1; expect_rc 2 $? "unknown option exits 2"

# 11. Never deletes or edits anything.
expect_eq "$before_list" "$(git -C "$m" worktree list --porcelain)" "the worktree list is unchanged"
expect_eq "$before_wip" "$(git -C "$tmp/wt-wip" status --porcelain)" "uncommitted work in wt-wip is unchanged"

# 12. Positive control: a copy whose loop no longer skips the main worktree must fail check 2.
mk="$tmp/mutant/skills/x"; mkdir -p "$mk/bin" "$mk/scripts"
cp "$root/skills/ctlhq-mode/bin/ctlhq-worktree-audit" "$mk/bin/ctlhq-worktree-audit"
sed 's/^	\[ "\$wt" = "\$main_wt" \] && continue$/	:/' "$root/skills/ctlhq-mode/scripts/worktree-audit.sh" > "$mk/scripts/worktree-audit.sh"
if cmp -s "$root/skills/ctlhq-mode/scripts/worktree-audit.sh" "$mk/scripts/worktree-audit.sh"; then bad "control: planted defect did not change the script"; else ok; fi
out="$(cd "$m" && "$mk/bin/ctlhq-worktree-audit" --no-fetch 2>/dev/null)"
if [ -n "$(row "$out" main)" ]; then ok; else bad "control: listing the main worktree is caught by the main-worktree check"; fi

echo "$pass checks passed"
[ "$fail" -eq 0 ] || { echo "$fail checks failed"; exit 1; }
