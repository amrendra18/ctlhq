#!/usr/bin/env bash
# tests/ctlhq-run-gate/run.sh: checks for bin/ctlhq-run-gate in a scratch git repository.
# Prints "N checks passed" and exits 1 when any check fails. Writes only to a temp folder.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
rg="$root/bin/ctlhq-run-gate"
pass=0
fail=0
ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL: $1"; }
expect_rc() { if [ "$1" -eq "$2" ]; then ok; else bad "$3 (expected exit $1, got $2)"; fi; }
expect_eq() { if [ "$1" = "$2" ]; then ok; else bad "$3 (expected '$1', got '$2')"; fi; }
expect_grep() { if printf '%s\n' "$2" | grep -Eq -- "$1"; then ok; else bad "$3 (no line matches: $1)"; fi; }
expect_nogrep() { if printf '%s\n' "$2" | grep -Eq -- "$1"; then bad "$3 (a line matches: $1)"; else ok; fi; }

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
tmp="$(mktemp -d "${TMPDIR:-/tmp}/run-gate-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
repo="$tmp/repo"
mkdir -p "$repo/sub"
git -C "$repo" init -q
gate="$repo/.local/gate"
cd "$repo/sub" || exit 1

# 1. --help and usage errors.
out="$("$rg" --help 2>&1)"; expect_rc 0 $? "--help exits 0"
expect_grep '^ctlhq-run-gate: ' "$(printf '%s\n' "$out" | head -1)" "--help first line is 'ctlhq-run-gate: ...'"
expect_grep 'never through tail or grep' "$out" "--help quotes the AGENTS.md rule"
"$rg" >/dev/null 2>&1; expect_rc 2 $? "no arguments exits 2"
"$rg" --force -- >/dev/null 2>&1; expect_rc 2 $? "no command after -- exits 2"
"$rg" --bogus -- true >/dev/null 2>&1; expect_rc 2 $? "unknown option exits 2"
"$rg" --name 'a/b' --force -- true >/dev/null 2>&1; expect_rc 2 $? "bad --name exits 2"
"$rg" --tail x --force -- true >/dev/null 2>&1; expect_rc 2 $? "bad --tail exits 2"

# 2. Passing command: files at the work-tree top, exit line first, streams apart.
out="$("$rg" --force --name ok -- sh -c 'echo out-one; echo err-one >&2; echo out-two')"; rc=$?
expect_rc 0 "$rc" "passing command exits 0"
expect_eq "exit 0" "$(printf '%s\n' "$out" | head -1)" "first line is 'exit 0'"
expect_eq "--- stdout (last 20) ---" "$(printf '%s\n' "$out" | sed -n 2p)" "second line is the stdout header"
expect_eq "out-one" "$(printf '%s\n' "$out" | sed -n 3p)" "stdout tail follows its header"
expect_eq "--- stderr (last 20) ---" "$(printf '%s\n' "$out" | sed -n 5p)" "stderr header after the stdout tail"
expect_eq "err-one" "$(printf '%s\n' "$out" | sed -n 6p)" "stderr tail follows its header"
expect_eq "$(printf 'out-one\nout-two')" "$(cat "$gate/ok.out")" "ok.out holds stdout only"
expect_eq "err-one" "$(cat "$gate/ok.err")" "ok.err holds stderr only"
expect_eq "0" "$(cat "$gate/ok.exit")" "ok.exit holds 0"
meta="$(cat "$gate/ok.meta")"
expect_eq 1 "$(printf '%s\n' "$meta" | wc -l | tr -d ' ')" "ok.meta is one line"
expect_eq 4 "$(printf '%s\n' "$meta" | awk -F'\t' '{print NF}')" "ok.meta has 4 TSV fields"
expect_grep '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z	[0-9-]{10}T[0-9:]{8}Z	0	sh -c ' "$meta" "ok.meta holds start, end, exit, command"
[ -d "$repo/sub/.local" ] && bad "no .local/ in the subfolder" || ok

# 3. Failing command: exit passthrough, default name "gate", && chain stops.
out="$("$rg" --force -- sh -c 'echo partial; echo boom >&2; exit 3')"; rc=$?
expect_rc 3 "$rc" "failing command exit 3 passes through"
expect_eq "exit 3" "$(printf '%s\n' "$out" | head -1)" "first line is 'exit 3'"
expect_eq "3" "$(cat "$gate/gate.exit")" "default name writes gate.exit"
expect_eq "boom" "$(cat "$gate/gate.err")" "gate.err holds stderr"
expect_eq "partial" "$(cat "$gate/gate.out")" "gate.out holds stdout"
"$rg" --force -- false >/dev/null && bad "&& must not run after a failing gate" || ok
"$rg" --force --name missing -- /nonexistent/cmd >/dev/null 2>&1; expect_rc 127 $? "a command that cannot start exits 127"

# 4. --tail limits each tail.
out="$("$rg" --force --name tail --tail 2 -- sh -c 'for i in 1 2 3 4 5; do echo o$i; echo e$i >&2; done')"
expect_eq "$(printf 'exit 0\n--- stdout (last 2) ---\no4\no5\n--- stderr (last 2) ---\ne4\ne5')" "$out" "--tail 2 prints two lines of each stream"
expect_eq 5 "$(wc -l < "$gate/tail.out" | tr -d ' ')" "tail.out keeps all 5 lines"

# 5. Load refusal with --max-load 0, override with --force.
rm -f "$gate/load".*
err="$("$rg" --max-load 0 --name load -- true 2>&1 >/dev/null)"; rc=$?
expect_rc 125 "$rc" "--max-load 0 refuses with exit 125"
expect_eq 1 "$(printf '%s\n' "$err" | wc -l | tr -d ' ')" "refusal is one line"
expect_grep '^ctlhq-run-gate: refused, 1-minute load ' "$err" "refusal names the load"
[ -e "$gate/load.exit" ] && bad "refusal writes no .exit file" || ok
out="$("$rg" --max-load 0 --force --name load -- true)"; rc=$?
expect_rc 0 "$rc" "--force overrides the load check"
expect_eq "0" "$(cat "$gate/load.exit")" "forced run writes load.exit"
"$rg" --max-load 100000 --name high -- true >/dev/null; expect_rc 0 $? "a high --max-load lets the command run"

# 6. Tree ID: recorded with the run's exit, the same as --tree, blind to the gate's own files.
g() { git -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false -c protocol.file.allow=always "$@"; }
now="$("$rg" --tree)"; expect_rc 0 $? "--tree exits 0 in a work tree"
expect_grep '^[0-9a-f]{40}$' "$now" "--tree prints one tree ID"
expect_eq "$(printf 'exit 0\ntree %s' "$now")" "$(cat "$gate/ok.tree" 2>/dev/null)" "ok.tree holds the exit and the tree ID, and the gate's own files under .local/ never change it (.local/ is not ignored here)"
"$rg" --force --name red -- false >/dev/null
expect_eq "$(printf 'exit 1\ntree %s' "$now")" "$(cat "$gate/red.tree" 2>/dev/null)" "a failing run records its own exit next to its tree"
expect_eq "" "$(ls -A "$gate" | grep '^\.')" "no temporary files are left in .local/gate"
"$rg" --force --name during -- sh -c 'printf x > made-during-run.txt' >/dev/null
[ "$(sed -n 2p "$gate/during.tree")" != "tree $("$rg" --tree)" ] && ok || bad "a file made during the run shows as a different tree"
rm made-during-run.txt
expect_eq "$(sed -n 2p "$gate/during.tree")" "tree $("$rg" --tree)" "the tree ID is taken before the command starts"
printf 'a\n' > f.txt
after_new="$("$rg" --tree)"
[ "$now" != "$after_new" ] && ok || bad "a new untracked file changes the tree ID"
index_sum() { cksum < "$(git rev-parse --git-path index)" 2>/dev/null; }
git add f.txt
before_index="$(index_sum)"
expect_eq "$after_new" "$("$rg" --tree)" "staging a file leaves the tree ID alone; only the files on disk count"
expect_eq "$before_index" "$(index_sum)" "--tree never writes the real index"
printf 'b\n' > f.txt
[ "$after_new" != "$("$rg" --tree)" ] && ok || bad "editing a staged file with no commits yet changes the tree ID"
printf 'a\n' > f.txt
g commit -qm one
expect_eq "$after_new" "$("$rg" --tree)" "a commit of the same files leaves the tree ID alone"
clean="$("$rg" --tree)"
printf 'c\n' > f.txt
[ "$clean" != "$("$rg" --tree)" ] && ok || bad "editing a committed file changes the tree ID"
chmod +x f.txt
exec_tree="$("$rg" --tree)"; chmod -x f.txt
[ "$exec_tree" != "$("$rg" --tree)" ] && ok || bad "a mode change changes the tree ID"
printf 'a\n' > f.txt
nest="$repo/sub/nested"; git init -q "$nest"; printf '1\n' > "$nest/n.txt"; g -C "$nest" add n.txt; g -C "$nest" commit -qm n1
with_nested="$("$rg" --tree)"
printf '2\n' > "$nest/n.txt"
expect_eq "$with_nested" "$("$rg" --tree)" "an uncommitted edit inside a nested repository leaves the tree ID alone (git records its commit)"
g -C "$nest" commit -qam n2
[ "$with_nested" != "$("$rg" --tree)" ] && ok || bad "a nested repository whose HEAD moved changes the tree ID"
rm -rf "$nest"
src="$tmp/subsrc"; git init -q "$src"; printf '1\n' > "$src/s.txt"; g -C "$src" add s.txt; g -C "$src" commit -qm s1
sm="$tmp/sm"; git init -q "$sm"
(cd "$sm" && g submodule add -q "$src" lib >/dev/null 2>&1 && git config -f .gitmodules submodule.lib.ignore all && git config diff.ignoreSubmodules all && g add .gitmodules && g commit -qm sm)
sm_tree="$(cd "$sm" && "$rg" --tree)"
expect_eq "$(git -C "$sm" rev-parse 'HEAD^{tree}')" "$sm_tree" "a clean repository with a submodule gives the commit's tree"
printf '2\n' > "$sm/lib/s.txt"; g -C "$sm/lib" commit -qam s2
[ "$sm_tree" != "$(cd "$sm" && "$rg" --tree)" ] && ok || bad "a submodule whose HEAD moved changes the tree ID, even with ignore = all"
git init -q "$tmp/sm/empty"
(cd "$sm" && "$rg" --force -- true >/dev/null 2>"$tmp/sm.err")
expect_grep '^error git .*add.*empty' "$(sed -n 2p "$sm/.local/gate/gate.tree")" "a run with no tree ID records the reason in place of the tree line"
expect_grep 'no tree ID' "$(cat "$tmp/sm.err")" "a run with no tree ID says so on stderr"
expect_eq "exit 0" "$(sed -n 1p "$sm/.local/gate/gate.tree")" "the reason sits next to the run's exit"
au="$tmp/au"; git init -q "$au"; printf 'a\n' > "$au/a.txt"; g -C "$au" add a.txt; g -C "$au" commit -qm a
git -C "$au" update-index --assume-unchanged a.txt
au_tree="$(cd "$au" && "$rg" --tree)"; printf 'EDIT\n' > "$au/a.txt"
[ "$au_tree" != "$(cd "$au" && "$rg" --tree)" ] && ok || bad "A2: an edit to a file marked assume-unchanged changes the tree ID"
(cd "$au" && "$rg" --force -- true >/dev/null)
expect_eq "tree $(printf 'EDIT\n' | git -C "$au" hash-object --stdin)" "tree $(git -C "$au" ls-tree "$(sed -n 2p "$au/.local/gate/gate.tree" | cut -d' ' -f2)" a.txt | awk '{print $3}')" "A1: the gate records the assume-unchanged file as it is on disk"
git -C "$au" update-index --no-assume-unchanged a.txt; git -C "$au" config core.splitIndex true; git -C "$au" update-index --split-index
shared="$(ls "$au/.git" | grep '^sharedindex\.')"
(cd "$au" && "$rg" --tree >/dev/null)
expect_eq "$shared" "$(ls "$au/.git" | grep '^sharedindex\.')" "with a split index, --tree adds no shared index file to .git"
sk="$tmp/sk"; git init -q "$sk"; printf 'x\n' > "$sk/x.txt"; printf 'y\n' > "$sk/y.txt"; g -C "$sk" add x.txt y.txt; g -C "$sk" commit -qm x
disk_tree="$(cd "$sk" && "$rg" --tree)"
git -C "$sk" update-index --cacheinfo "100644,$(printf 'EVIL\n' | git -C "$sk" hash-object -w --stdin),x.txt"; git -C "$sk" update-index --skip-worktree x.txt
expect_eq "$disk_tree" "$(cd "$sk" && "$rg" --tree)" "K4: a file marked skip-worktree counts as it is on disk, not as its staged copy"
expect_eq "S x.txt" "$(git -C "$sk" ls-files -v x.txt)" "--tree leaves the skip-worktree mark in the real index"
rm "$sk/x.txt"
expect_eq "$(git -C "$sk" ls-tree HEAD y.txt | git -C "$sk" mktree)" "$(cd "$sk" && "$rg" --tree)" "K5: a skip-worktree file missing from disk, with a staged copy that differs from HEAD, counts as deleted"
git -C "$sk" update-index --cacheinfo "100644,$(git -C "$sk" rev-parse HEAD:x.txt),x.txt"; git -C "$sk" update-index --skip-worktree x.txt
expect_eq "$disk_tree" "$(cd "$sk" && "$rg" --tree)" "a skip-worktree file missing from disk whose staged copy matches HEAD counts as staged"
expect_grep 'in a sparse checkout, .git add. leaves paths outside the cone' "$("$rg" --help | tr '\n' ' ' | tr -s ' ')" "--help names the sparse-checkout exception"
"$rg" --tree extra >/dev/null 2>&1; expect_rc 2 $? "--tree with other arguments exits 2"
mkdir -p "$tmp/plain"
(cd "$tmp/plain" && "$rg" --tree >/dev/null 2>&1); expect_rc 1 $? "--tree outside a work tree exits 1"
(cd "$tmp/plain" && "$rg" --force -- true >/dev/null 2>&1); expect_rc 0 $? "a gate outside a work tree still runs"
[ -e "$tmp/plain/.local/gate/gate.tree" ] && bad "no .tree file outside a work tree" || ok
expect_grep '\.tree' "$("$rg" --help)" "--help documents the .tree file"

echo "$pass checks passed"
if [ "$fail" -gt 0 ]; then echo "$fail checks failed"; exit 1; fi
exit 0
