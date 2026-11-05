#!/usr/bin/env bash
# tests/ctlhq-commit/run.sh: checks for bin/ctlhq-commit in a scratch git repository
# (commit.gpgsign false, global git config ignored). Prints "N checks passed" and exits 1
# when any check fails. Writes only to a temp folder; never commits in this repository.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
fc="$root/bin/ctlhq-commit"
pass=0
fail=0
ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL: $1"; }
expect_rc() { if [ "$1" -eq "$2" ]; then ok; else bad "$3 (expected exit $1, got $2)"; fi; }
expect_eq() { if [ "$1" = "$2" ]; then ok; else bad "$3 (expected '$1', got '$2')"; fi; }
expect_grep() { if printf '%s\n' "$2" | grep -Eq -- "$1"; then ok; else bad "$3 (no line matches: $1)"; fi; }
expect_nogrep() { if printf '%s\n' "$2" | grep -Eq -- "$1"; then bad "$3 (a line matches: $1)"; else ok; fi; }

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
unset CLAUDECODE CODEX_THREAD_ID AI_AGENT CTLHQ_CO_AUTHOR CTLHQ_COMMIT_CONFIG
trailer="Co-Authored-By: Test Agent <agent@example.invalid>"
export CTLHQ_CO_AUTHOR="$trailer"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/ctlhq-commit-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home"
mkdir -p "$HOME"
repo="$tmp/repo"
mkdir -p "$repo"
git -C "$repo" init -q
git -C "$repo" config user.name "Test User"
git -C "$repo" config user.email "test@example.invalid"
git -C "$repo" config commit.gpgsign false
printf '.local/\n' > "$repo/.gitignore"
cd "$repo" || exit 1
four=(--subject "Add a.txt" --why "Need a file." --changes "a.txt holds one line." --test-plan "Read a.txt." --risks "None known.")
commits() { git -C "$repo" rev-list --count HEAD 2>/dev/null || echo 0; }

# 1. --help and usage errors.
out="$("$fc" --help 2>&1)"; expect_rc 0 $? "--help exits 0"
expect_grep '^ctlhq-commit: ' "$(printf '%s\n' "$out" | head -1)" "--help first line is 'ctlhq-commit: ...'"
expect_grep 'Commit only through the sequence' "$out" "--help quotes the commit-sequence rule"
printf 'one\n' > a.txt
"$fc" "${four[@]}" >/dev/null 2>&1; expect_rc 2 $? "no -- exits 2"
err="$("$fc" "${four[@]}" -- 2>&1)"; expect_rc 2 $? "no paths after -- exits 2"
expect_grep 'git add is by name' "$err" "no-paths refusal says add is by name"
"$fc" "${four[@]}" -- . >/dev/null 2>&1; expect_rc 2 $? "path '.' exits 2"
"$fc" "${four[@]}" -- -A >/dev/null 2>&1; expect_rc 2 $? "path '-A' exits 2"
"$fc" --subject x -- a.txt >/dev/null 2>&1; expect_rc 2 $? "missing sections exits 2"
"$fc" "${four[@]}" --message-file /dev/null -- a.txt >/dev/null 2>&1; expect_rc 2 $? "--message-file with section flags exits 2"
expect_eq 0 "$(commits)" "no commit after usage errors"

# 2. Gate not green.
"$fc" --gate gate "${four[@]}" -- a.txt >/dev/null 2>&1; expect_rc 3 $? "missing gate file exits 3"
mkdir -p .local/gate
printf '1\n' > .local/gate/gate.exit
printf '2026-10-16T10:00:00Z\t2026-10-16T10:00:05Z\t1\tmake test\n' > .local/gate/gate.meta
err="$("$fc" --gate gate "${four[@]}" -- a.txt 2>&1)"; expect_rc 3 $? "gate exit 1 exits 3"
expect_grep 'exit 1, not 0' "$err" "refusal prints the exit it found"
expect_grep 'make test' "$err" "refusal prints the meta line"
expect_eq 0 "$(commits)" "no commit after gate refusal"

# 2b. Before the first commit: a green exit needs a recorded tree ID that matches the files on disk.
rgate="$root/bin/ctlhq-run-gate"
printf '0\n' > .local/gate/gate.exit
err="$("$fc" --gate gate "${four[@]}" -- a.txt 2>&1)"; expect_rc 3 $? "a green exit with no tree record exits 3"
expect_grep 'gate\.tree' "$err" "the refusal names the missing tree record"
expect_grep '^why: ' "$err" "the missing-record refusal has a why: line"
expect_grep '^fix: rerun `/.*/ctlhq-run-gate -C /' "$err" "the missing-record refusal says to rerun the gate"
printf 'head none\ntracked x\nuntracked y\n' > .local/gate/gate.tree
err="$("$fc" --gate gate "${four[@]}" -- a.txt 2>&1)"; expect_rc 3 $? "a record in the round-1 three-line format exits 3"
expect_grep 'no tree line' "$err" "the refusal says the record has no tree line"
"$rgate" --force -- test -f a.txt >/dev/null; expect_rc 0 $? "the gate runs in a repository with no commits"
expect_eq "$(printf 'exit 0\ntree %s' "$("$rgate" --tree)")" "$(cat .local/gate/gate.tree)" "the record holds the run's exit and the tree ID, with no commits yet"
printf 'edited\n' > a.txt
err="$("$fc" --gate gate "${four[@]}" -- a.txt 2>&1)"; expect_rc 3 $? "an untracked file edited after the gate exits 3"
expect_grep 'the files on disk differ from the ones it tested' "$err" "the refusal says the files differ"
expect_grep '^fix: rerun `/.*/ctlhq-run-gate -C /.* -- test -f a\.txt`' "$err" "the fix line repeats the gate's own command"
expect_eq "" "$(git ls-files)" "the late refusal unstages the named paths again"
"$rgate" --force -- test -f a.txt >/dev/null; printf 'one\n' > a.txt
err="$("$fc" --gate gate "${four[@]}" -- a.txt 2>&1)"; expect_rc 3 $? "a staged file edited after the gate exits 3, with no commits yet"
"$rgate" --force -- test -f a.txt >/dev/null
printf 'exit 1\ntree %s\n' "$("$rgate" --tree)" > .local/gate/gate.tree
err="$("$fc" --gate gate "${four[@]}" -- a.txt 2>&1)"; expect_rc 3 $? "a record from a failing run of this tree exits 3, though .exit says 0"
expect_grep 'gate\.tree says exit 1' "$err" "the refusal says the record and .exit come from different runs"
printf 'u\n' > unreadable.txt; chmod 000 unreadable.txt
"$rgate" --force -- true >/dev/null 2>"$tmp/rg.err"
expect_grep '^error ' "$(cat .local/gate/gate.tree)" "a run with no tree ID records the reason"
err="$("$fc" --gate gate "${four[@]}" -- a.txt 2>&1)"; expect_rc 3 $? "a run with no tree ID exits 3"
expect_grep 'could not record its tree: .*unreadable\.txt' "$err" "the refusal prints why there is no tree ID"
chmod 644 unreadable.txt; rm unreadable.txt
expect_eq 0 "$(commits)" "no commit after a stale gate"

# 3. A trailer is kept, not refused; block 8 checks it.

# 4. Successful commit after a green gate on the same tree: four sections, clean tree, hash printed.
"$rgate" --force -- test -f a.txt >/dev/null
out="$("$fc" --gate gate "${four[@]}" -- a.txt .gitignore 2>&1)"; rc=$?
expect_rc 0 "$rc" "green gate commit exits 0"
expect_eq 1 "$(commits)" "one commit exists"
head="$(git rev-parse HEAD)"
expect_grep "^hash: $head$" "$out" "prints the full hash"
expect_grep '^subject: Add a.txt$' "$out" "prints the subject"
expect_grep '^signature: unsigned$' "$out" "signature state is unsigned"
expect_grep '^tree: clean$' "$out" "tree is clean"
expect_eq "committed $head" "$(printf '%s\n' "$out" | tail -1)" "last line is 'committed <hash>'"
body="$(git log -1 --format=%B)"
expect_eq "$(printf 'Add a.txt\n\nWhy:\nNeed a file.\n\nChanges:\na.txt holds one line.\n\nTest Plan:\nRead a.txt.\n\nRisks:\nNone known.\n\n%s' "$trailer")" "$body" "message has subject, four sections, and the co-author trailer"
msgfile="$(printf '%s\n' "$out" | sed -n 's/^message file: //p')"
expect_grep '^\.local/commit/[0-9]{8}T[0-9]{6}Z(-[0-9]+)?\.txt$' "$msgfile" "message file lives in .local/commit/<timestamp>.txt"
[ -f "$repo/$msgfile" ] && ok || bad "message file exists on disk"
expect_eq "$(printf 'a.txt\n.gitignore' | sort)" "$(git show --name-only --format= HEAD | sort)" "only the named paths are committed"
receipt() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); g=d["gate"] or {}; print(d["hash"], d["subject"], d["signature"], d["tree"], g.get("name"), g.get("exit"), "test -f a.txt" in (g.get("meta") or ""), d["exit"], ",".join(d["paths"]), sep="|")' "$1"; }
expect_grep "^receipt: \.local/commits/$head\.json$" "$out" "prints the receipt path"
[ -f "$repo/.local/commits/$head.json" ] && ok || bad "the receipt exists at .local/commits/<hash>.json"
expect_eq "$head|Add a.txt|unsigned|clean|gate|0|True|0|a.txt,.gitignore" "$(receipt "$repo/.local/commits/$head.json")" "the receipt holds hash, subject, signature, tree, gate name, exit, and meta line"
expect_eq "" "$(git status --porcelain)" "the receipt leaves the tree clean (.local stays ignored)"
expect_eq "" "$(git ls-files -- .local)" "no receipt is tracked by git"
expect_eq 1 "$(commits)" "the receipt needs no receipt commit"

# 4b. After a commit: a tracked edit or a new untracked file after the gate is refused,
# whatever paths the commit names.
"$rgate" --force -- true >/dev/null
printf 'edit\n' >> a.txt
err="$("$fc" --gate gate "${four[@]}" -- .gitignore 2>&1)"; expect_rc 3 $? "a tracked edit after the gate exits 3, even when the commit names another path"
expect_grep 'the files on disk differ' "$err" "the tracked-edit refusal says so"
git checkout -q -- a.txt
printf 'n\n' > new.txt
err="$("$fc" --gate gate "${four[@]}" -- new.txt 2>&1)"; expect_rc 3 $? "a new untracked file after the gate exits 3"
expect_grep 'the files on disk differ' "$err" "the new-file refusal says so"
expect_eq "" "$(git diff --cached --name-only)" "the late refusal leaves nothing staged after a commit"
rm new.txt
expect_eq 1 "$(commits)" "no commit after the stale-gate refusals"

# 5. Dirty tree afterwards: exit 1 without --allow-dirty, 0 with it.
printf 'two\n' >> a.txt
printf 'b\n' > b.txt
printf 'stray\n' > stray.txt
err="$("$fc" "${four[@]}" -- a.txt 2>&1)"; expect_rc 1 $? "dirty tree afterwards exits 1"
expect_grep '^tree: dirty \(2 paths\), not clean$' "$err" "dirty state names the count"
expect_eq 2 "$(commits)" "the commit still exists"
h2="$(git rev-parse HEAD)"
expect_eq "$h2|Add a.txt|unsigned|dirty|None|None|False|1|a.txt" "$(receipt "$repo/.local/commits/$h2.json")" "a dirty-tree commit still gets a receipt with tree dirty, no gate, and exit 1"
printf 'c\n' > c.txt
out="$("$fc" --allow-dirty "${four[@]}" -- c.txt 2>&1)"; expect_rc 0 $? "--allow-dirty exits 0"
expect_grep 'accepted by --allow-dirty' "$out" "--allow-dirty says it accepted the dirt"
expect_grep '^  \?\? stray\.txt$' "$out" "--allow-dirty prints the dirty paths"
expect_eq 3 "$(commits)" "third commit exists"
err="$("$fc" --allow-dirty --gate gate "${four[@]}" -- b.txt 2>&1)"; expect_rc 3 $? "a gate from before files changed exits 3"
expect_grep 'the files on disk differ' "$err" "the refusal says the files differ"
expect_eq 3 "$(commits)" "no commit after the stale-gate refusal"

# 6. --message-file verbatim plus the trailer; a path git rejects exits 1.
printf 'Verbatim subject\n\nWhy:\nx\n' > "$tmp/msg.txt"
"$fc" --allow-dirty --message-file "$tmp/msg.txt" -- b.txt >/dev/null 2>&1; expect_rc 0 $? "--message-file commit exits 0"
expect_eq "$(printf '%s\n\n%s' "$(cat "$tmp/msg.txt")" "$trailer")" "$(git log -1 --format=%B)" "--message-file is taken verbatim, with the trailer appended"
"$fc" --allow-dirty "${four[@]}" -- no-such-file >/dev/null 2>&1; expect_rc 1 $? "git add of a missing path exits 1"

# 7. Outside a work tree exits 1.
mkdir -p "$tmp/plain"
(cd "$tmp/plain" && "$fc" "${four[@]}" -- a.txt >/dev/null 2>&1); expect_rc 1 $? "outside a git work tree exits 1"

# 8. A Co-Authored-By trailer in the message is kept, and no second one is added.
printf 'three\n' >> b.txt
printf 'Add three\n\nBody.\n\nCo-Authored-By: Someone <x@example.invalid>\n' > "$tmp/msg-trailer.txt"
"$fc" --allow-dirty --message-file "$tmp/msg-trailer.txt" -- b.txt >/dev/null 2>&1; expect_rc 0 $? "a message with a trailer commits"
body="$(git log -1 --format=%B)"
expect_grep '^Co-Authored-By: Someone' "$body" "the trailer is in the commit"
expect_eq 1 "$(printf '%s\n' "$body" | grep -ci '^co-authored-by:')" "a message with its own trailer gets no second one"

# 9. Deletions of named paths are staged; unnamed deletions are left alone.
printf 'x\n' > keep.txt; mkdir -p old/sub; printf '1\n' > old/a.py; printf '2\n' > old/sub/b.py
printf '3\n' > gone.txt; printf '4\n' > unnamed.txt
"$fc" --allow-dirty "${four[@]}" -- keep.txt old gone.txt unnamed.txt >/dev/null 2>&1; expect_rc 0 $? "setup commit for deletions exits 0"
rm -r old gone.txt unnamed.txt; mkdir new; printf '1\n' > new/a.py
out="$("$fc" --allow-dirty "${four[@]}" -- old gone.txt new 2>&1)"; expect_rc 0 $? "a commit naming deleted paths exits 0"
expect_eq "" "$(git ls-files -- old gone.txt)" "named deleted file and folder are no longer tracked"
expect_eq "$(printf 'D\tgone.txt\nA\tnew/a.py\nD\told/a.py\nD\told/sub/b.py')" "$(git show --name-status --no-renames --format= HEAD | sort -k2)" "the commit records the deletions and the new file"
expect_eq "unnamed.txt" "$(git ls-files -- unnamed.txt)" "an unnamed deleted path stays tracked"
expect_eq "$(printf ' D unnamed.txt')" "$(git status --porcelain -- unnamed.txt)" "the unnamed deletion is left unstaged"
printf '6\n' > staged-gone.txt; "$fc" --allow-dirty "${four[@]}" -- staged-gone.txt >/dev/null 2>&1
git rm -q staged-gone.txt
"$fc" --allow-dirty "${four[@]}" -- staged-gone.txt >/dev/null 2>&1; expect_rc 0 $? "a path already staged as deleted commits"
expect_eq "" "$(git ls-files -- staged-gone.txt)" "the staged deletion is committed"

printf '6\n' > keep.txt; "$fc" --allow-dirty "${four[@]}" -- keep.txt >/dev/null 2>&1; git rm -q --cached keep.txt
idx="$(git ls-files -s)"
err="$("$fc" --allow-dirty "${four[@]}" -- keep.txt 2>&1)"; expect_rc 3 $? "a staged deletion of a file git does not ignore exits 3"
expect_eq "$idx" "$(git ls-files -s)" "the refused file leaves the index unchanged"
expect_grep 'add the path to \.gitignore and name \.gitignore after -- too; to keep it tracked, run `git -C /.* add <path>`' "$err" "the refusal names both ways out and says to name .gitignore"
git reset -q -- keep.txt
printf '7\n' > untrack.txt; "$fc" --allow-dirty "${four[@]}" -- untrack.txt >/dev/null 2>&1
git rm -q --cached untrack.txt; printf 'untrack.txt\n' >> .gitignore
out="$("$fc" --allow-dirty "${four[@]}" -- untrack.txt .gitignore 2>&1)"; expect_rc 0 $? "a staged deletion of an ignored file still on disk commits"
expect_eq "" "$(git ls-tree --name-only HEAD -- untrack.txt)" "the ignored file is no longer tracked in HEAD"
expect_eq "7" "$(cat untrack.txt 2>/dev/null)" "the ignored file stays on disk"

printf '8\n' > swap; "$fc" --allow-dirty "${four[@]}" -- swap >/dev/null 2>&1
git rm -q --cached swap; rm swap; mkdir swap; printf '9\n' > swap/y
out="$("$fc" --allow-dirty "${four[@]}" -- swap 2>&1)"; expect_rc 0 $? "a file replaced by a folder commits"
expect_eq "swap/y" "$(git ls-tree -r --name-only HEAD -- swap)" "the folder's file replaces the file in HEAD"

mkdir keepdir; printf '1\n' > keepdir/k; "$fc" --allow-dirty "${four[@]}" -- keepdir >/dev/null 2>&1
git rm -rq --cached keepdir; printf 'keepdir/\n' >> .gitignore
out="$("$fc" --allow-dirty "${four[@]}" -- keepdir/ .gitignore 2>&1)"; expect_rc 0 $? "an ignored folder staged as deleted commits"
expect_eq "" "$(git ls-tree -r --name-only HEAD -- keepdir)" "the ignored folder is no longer tracked in HEAD"
expect_eq "1" "$(cat keepdir/k 2>/dev/null)" "the ignored folder stays on disk"

mkdir fd; printf '1\n' > fd/a; "$fc" --allow-dirty "${four[@]}" -- fd >/dev/null 2>&1
git rm -rq --cached fd; rm -r fd; printf '2\n' > fd
out="$("$fc" --allow-dirty "${four[@]}" -- fd 2>&1)"; expect_rc 0 $? "a folder replaced by a file commits"
expect_eq "fd" "$(git ls-tree -r --name-only HEAD -- fd)" "the file replaces the folder in HEAD"

mkdir part; printf '1\n' > part/k; "$fc" --allow-dirty "${four[@]}" -- part >/dev/null 2>&1
git rm -rq --cached part; printf 'part/k\n' >> .gitignore; printf '2\n' > part/new
out="$("$fc" --allow-dirty "${four[@]}" -- part .gitignore 2>&1)"; expect_rc 0 $? "a folder staged as deleted whose only tracked file is ignored commits as on disk"
expect_eq "part/new" "$(git ls-tree -r --name-only HEAD -- part)" "the folder's new file is committed and its ignored file is not"
expect_eq "" "$(git status --porcelain -- part)" "nothing in the folder is left uncommitted"

mkdir vendor; printf '1\n' > vendor/lib.js; printf 'a\n' > notes.txt; "$fc" --allow-dirty "${four[@]}" -- vendor notes.txt >/dev/null 2>&1
git rm -rq --cached vendor; printf 'b\n' >> notes.txt; idx="$(git ls-files -s)"
err="$("$fc" --allow-dirty "${four[@]}" -- vendor notes.txt 2>&1)"; expect_rc 3 $? "a folder staged as deleted with a file git does not ignore exits 3"
expect_grep '^ctlhq-commit: vendor/lib\.js: staged as deleted' "$err" "the refusal names the file inside the folder"
expect_eq "$idx" "$(git ls-files -s)" "the index is unchanged after the folder refusal"
git reset -q -- vendor; git checkout -q -- notes.txt

# 10. A named path still dirty after the commit exits 1, even with --allow-dirty.
git rm -q --cached unnamed.txt; "$fc" --allow-dirty "${four[@]}" -- unnamed.txt >/dev/null 2>&1
printf '5\n' > hooked.txt; "$fc" --allow-dirty "${four[@]}" -- hooked.txt >/dev/null 2>&1
printf '#!/bin/sh\ngit reset -q HEAD -- hooked.txt\n' > .git/hooks/pre-commit; chmod +x .git/hooks/pre-commit
rm hooked.txt; printf 'y\n' >> keep.txt
err="$("$fc" --allow-dirty "${four[@]}" -- hooked.txt keep.txt 2>&1)"; expect_rc 1 $? "a named deletion a hook unstaged exits 1 with --allow-dirty"
expect_grep 'named path.*not committed' "$err" "the refusal says a named path was not committed"
expect_grep '^ +D hooked\.txt$' "$err" "the refusal lists the path"
expect_grep '^fix: ' "$err" "the refusal has a fix: line"
rm .git/hooks/pre-commit; git rm -q --cached hooked.txt; "$fc" --allow-dirty "${four[@]}" -- hooked.txt >/dev/null 2>&1

# 11. Co-author sources: --co-author wins over CTLHQ_CO_AUTHOR; a trailer in the message wins over both.
last_trailer() { git log -1 --format=%B | grep -i '^co-authored-by:'; }
step() { printf '%s\n' "$1" >> keep.txt; }
step a; out="$("$fc" --allow-dirty --co-author "Co-Authored-By: Flag Name <flag@example.invalid>" "${four[@]}" -- keep.txt 2>&1)"; expect_rc 0 $? "--co-author commit exits 0"
expect_eq "Co-Authored-By: Flag Name <flag@example.invalid>" "$(last_trailer)" "--co-author wins over CTLHQ_CO_AUTHOR"
expect_grep '^co-author: Co-Authored-By: Flag Name <flag@example.invalid> \(from --co-author\)$' "$out" "the source is printed"
step b; out="$("$fc" --allow-dirty "${four[@]}" -- keep.txt 2>&1)"; expect_eq "$trailer" "$(last_trailer)" "CTLHQ_CO_AUTHOR is used without --co-author"
expect_grep '\(from CTLHQ_CO_AUTHOR\)$' "$out" "the environment source is printed"
step c; printf 'Own trailer\n\nBody.\n\nCo-Authored-By: Message Name <msg@example.invalid>\n' > "$tmp/msg-own.txt"
out="$("$fc" --allow-dirty --co-author "Co-Authored-By: Flag Name <flag@example.invalid>" --message-file "$tmp/msg-own.txt" -- keep.txt 2>&1)"; expect_rc 0 $? "a message trailer with --co-author exits 0"
expect_eq "Co-Authored-By: Message Name <msg@example.invalid>" "$(last_trailer)" "the message's own trailer wins over --co-author"
expect_grep "^co-author: kept the message's own" "$out" "the kept trailer is reported"
step d; printf 'Subject\n\nBody.\n\nSigned-off-by: T <t@example.invalid>\n' > "$tmp/msg-signed.txt"
"$fc" --allow-dirty --message-file "$tmp/msg-signed.txt" -- keep.txt >/dev/null 2>&1
expect_eq "$(printf 'Subject\n\nBody.\n\nSigned-off-by: T <t@example.invalid>\n%s' "$trailer")" "$(git log -1 --format=%B)" "the trailer joins an existing trailer block"

# 12. Refusals: no trailer anywhere (a config file is never read), a bad line shape. No commit is made.
n="$(commits)"
step e
cfg="$tmp/commit.toml"
printf '[co_author]\nclaude = "Co-Authored-By: Claude Test <claude@example.invalid>"\n' > "$cfg"
mkdir -p "$tmp/home/.ctlhq"; cp "$cfg" "$tmp/home/.ctlhq/commit.toml"
err="$(CTLHQ_CO_AUTHOR= AI_AGENT=claude-code_2-1-300_agent CLAUDECODE=1 CTLHQ_COMMIT_CONFIG="$cfg" HOME="$tmp/home" "$fc" "${four[@]}" -- keep.txt 2>&1)"; expect_rc 5 $? "no trailer exits 5, even with a config file present"
expect_grep '^ctlhq-commit: no Co-Authored-By line' "$err" "the refusal says what is wrong"
expect_grep '^why: ' "$err" "the refusal has a why: line"
expect_grep '^fix: add the Co-Authored-By line your agent gives for its current model to the message, or pass --co-author' "$err" "the refusal has the fix: line"
expect_grep 'Claude Code' "$err" "AI_AGENT claude-code names Claude Code"
err="$(CTLHQ_CO_AUTHOR= "$fc" "${four[@]}" -- keep.txt 2>&1)"; expect_rc 5 $? "no trailer and no agent exits 5"
expect_grep '^fix: add the Co-Authored-By line your agent gives' "$err" "the generic refusal has the fix: line"
err="$(CTLHQ_CO_AUTHOR= CODEX_THREAD_ID=t1 "$fc" "${four[@]}" -- keep.txt 2>&1)"; expect_rc 5 $? "no trailer under Codex exits 5"
expect_grep 'Codex' "$err" "CODEX_THREAD_ID names Codex"
err="$(CTLHQ_CO_AUTHOR="Claude <x@example.invalid>" "$fc" "${four[@]}" -- keep.txt 2>&1)"; expect_rc 5 $? "a line without Co-Authored-By: exits 5"
expect_grep 'CTLHQ_CO_AUTHOR' "$err" "the shape refusal names the source"
"$fc" --co-author "Co-Authored-By: No Email" "${four[@]}" -- keep.txt >/dev/null 2>&1; expect_rc 5 $? "a line without <email> exits 5"
"$fc" --co-author "Co-Authored-By: Two <a@example.invalid>
x" "${four[@]}" -- keep.txt >/dev/null 2>&1; expect_rc 5 $? "a two-line value exits 5"
"$fc" "${four[@]}" --co-author >/dev/null 2>&1; expect_rc 2 $? "--co-author without a value exits 2"
expect_eq "$n" "$(commits)" "no commit after co-author refusals"
out="$("$fc" --help 2>&1)"
if printf '%s\n' "$out" | grep -q 'commit.toml\|CTLHQ_COMMIT_CONFIG'; then bad "--help no longer names a config file"; else ok; fi

# 13. A commit in a linked worktree writes its receipt in the main work tree's .local/commits.
git worktree add -q "$tmp/wt" -b side 2>/dev/null
printf 'side\n' > "$tmp/wt/side.txt"
out="$(cd "$tmp/wt" && "$fc" --allow-dirty "${four[@]}" -- side.txt 2>&1)"; expect_rc 0 $? "a worktree commit exits 0"
hw="$(git -C "$tmp/wt" rev-parse HEAD)"
[ -f "$repo/.local/commits/$hw.json" ] && ok || bad "the worktree receipt lands in the main work tree"
[ -e "$tmp/wt/.local/commits/$hw.json" ] && bad "no receipt inside the linked worktree" || ok
expect_grep "^receipt: $repo/\.local/commits/$hw\.json$|^receipt: .*/repo/\.local/commits/$hw\.json$" "$out" "the printed receipt path names the main work tree"
expect_grep 'commits/<full hash>.json' "$("$fc" --help)" "--help documents the receipt"
mv "$repo/.local/commits" "$repo/.local/commits.saved"; printf 'not a folder\n' > "$repo/.local/commits"
printf 'more\n' >> "$tmp/wt/side.txt"
out="$(cd "$tmp/wt" && "$fc" --allow-dirty "${four[@]}" -- side.txt 2>&1)"; expect_rc 0 $? "a receipt that cannot be written keeps exit 0 for the commit"
expect_grep '^receipt: not written \(.*\); the commit [0-9a-f]{12} exists, its receipt is missing$' "$out" "the missing receipt is reported"
expect_eq "committed $(git -C "$tmp/wt" rev-parse HEAD)" "$(printf '%s\n' "$out" | tail -1)" "the run still ends with 'committed <hash>'"
rm "$repo/.local/commits"; mv "$repo/.local/commits.saved" "$repo/.local/commits"

# 14. Staged changes outside the named paths are refused before anything is staged.
r2="$tmp/staged"; git init -q "$r2"; cd "$r2" || exit 1
git config user.name t; git config user.email t@example.invalid; git config commit.gpgsign false
printf '.local/\n' > .gitignore; printf 'good\n' > a.txt; printf 'good\n' > b.txt
git add b.txt
err="$("$fc" "${four[@]}" -- a.txt .gitignore 2>&1)"; expect_rc 3 $? "a staged unnamed file exits 3 before the first commit"
expect_eq "b.txt" "$(git ls-files)" "the refusal stages nothing"
git rm -q --cached b.txt
"$fc" "${four[@]}" -- a.txt b.txt .gitignore >/dev/null 2>&1; expect_rc 0 $? "naming every staged path commits"
base="$(git rev-parse HEAD)"
printf 'BAD\n' > b.txt; git add b.txt; printf 'good\n' > b.txt; printf 'new\n' > a.txt
"$rgate" --force -- sh -c '! grep -q BAD a.txt b.txt' >/dev/null
err="$("$fc" --gate gate "${four[@]}" -- a.txt 2>&1)"; expect_rc 3 $? "P1: staged content on an unnamed path exits 3"
expect_grep '^  b\.txt$' "$err" "the refusal lists the staged path"
expect_grep '^why: git commit takes the whole index' "$err" "the refusal has a why: line"
expect_grep '^fix: name them after --, or unstage them with `git -C /.* reset -q -- <path>`' "$err" "the refusal has a fix: line"
expect_eq "b.txt" "$(git diff --cached --name-only)" "the refusal leaves the index as it was"
expect_eq "$base" "$(git rev-parse HEAD)" "no commit after the P1 refusal"
printf 'other\n' > b.txt; git add b.txt
err="$("$fc" "${four[@]}" -- a.txt 2>&1)"; expect_rc 3 $? "P1b: a staged unnamed change that matches the disk exits 3"
expect_grep '^  b\.txt$' "$err" "the P1b refusal lists the path"
git reset -q -- b.txt; printf 'good\n' > b.txt; git rm -q --cached b.txt
err="$("$fc" --gate gate "${four[@]}" -- a.txt 2>&1)"; expect_rc 3 $? "P2: a staged deletion of an unnamed file exits 3"
expect_grep '^  b\.txt$' "$err" "the deletion refusal lists the path"
expect_eq "$base" "$(git rev-parse HEAD)" "no commit after the P1b and P2 refusals"
git reset -q -- b.txt
mkdir -p d/e; printf 'x\n' > d/e/x.txt; git add d/e/x.txt a.txt
err="$(cd d && "$fc" --allow-dirty "${four[@]}" -- e 2>&1)"; expect_rc 3 $? "from a subfolder, a staged file outside the named folder exits 3"
expect_grep '^  a\.txt$' "$err" "the refusal names the path from the top of the work tree"
out="$(cd d && "$fc" --allow-dirty "${four[@]}" -- e ../a.txt 2>&1)"; expect_rc 0 $? "a staged file inside a folder named from a subfolder commits"
expect_eq "$(printf 'a.txt\nd/e/x.txt')" "$(git show --name-only --format= HEAD | sort)" "the commit holds the named paths"

# 15. One gate run covers several commits of the files it tested.
printf 'one\n' >> a.txt; printf 'two\n' >> b.txt
"$rgate" --force -- true >/dev/null
"$fc" --gate gate --allow-dirty "${four[@]}" -- a.txt >/dev/null 2>&1; expect_rc 0 $? "the first commit after one gate run exits 0"
out="$("$fc" --gate gate "${four[@]}" -- b.txt 2>&1)"; expect_rc 0 $? "a second commit of the gated files, unchanged since, exits 0"
expect_grep '^tree: clean$' "$out" "the split commits leave the tree clean"

# 16. Named paths are names, never patterns: a glob or pathspec magic matches no file and stages nothing.
fresh() { r="$tmp/$1"; git init -q "$r"; cd "$r" || exit 1; git config user.name t; git config user.email t@example.invalid; git config commit.gpgsign false
  printf '.local/\n' > .gitignore; printf 'a\n' > a.txt; printf 'b\n' > b.txt; mkdir src; printf 'x\n' > src/x.py; printf 'y\n' > src/y.py; git add -A; git commit -qm base; }
index_sum() { cksum < .git/index; }
fresh g1; printf 'x2\n' > src/x.py; printf 'a2\n' > a.txt; "$rgate" --force -- true >/dev/null; h="$(git rev-parse HEAD)"; i="$(index_sum)"
for spec in 'src/*.py' ':/' ':!a.txt' 'a?txt'; do
  err="$("$fc" --gate gate "${four[@]}" -- "$spec" 2>&1)"; expect_rc 1 $? "G1-G3, G5: the named pattern '$spec' exits 1"
  expect_grep "^ctlhq-commit: .*not on disk and not tracked" "$err" "the '$spec' refusal says there is no such path"
done
expect_eq "$h" "$(git rev-parse HEAD)" "no commit after the pattern refusals"
expect_eq "$i" "$(index_sum)" "the pattern refusals leave the index as it was"
fresh g4; printf 'good\n' > f1.txt; git add f1.txt; git commit -qm f1; printf 'BAD\n' > f1.txt; git add f1.txt; printf 'good\n' > f1.txt; printf 'lit\n' > 'f[1].txt'
"$rgate" --force -- true >/dev/null
err="$("$fc" --gate gate --allow-dirty "${four[@]}" -- 'f[1].txt' 2>&1)"; expect_rc 3 $? "G4: a file named 'f[1].txt' does not cover a staged f1.txt"
expect_grep '^  f1\.txt$' "$err" "the G4 refusal lists f1.txt"
expect_eq "BAD" "$(git show :f1.txt)" "the G4 refusal leaves the staged f1.txt alone"
git reset -q -- f1.txt
out="$("$fc" --gate gate "${four[@]}" -- 'f[1].txt' 2>&1)"; expect_rc 0 $? "a file named 'f[1].txt' commits by its own name"
expect_eq 'f[1].txt' "$(git show --name-only --format= HEAD)" "the commit holds only 'f[1].txt'"
git --literal-pathspecs rm -q --cached -- 'f[1].txt'; printf 'f\\[1\\].txt\n' >> .gitignore
out="$("$fc" "${four[@]}" -- 'f[1].txt' .gitignore 2>&1)"; expect_rc 0 $? "an ignored 'f[1].txt' staged as deleted commits next to a tracked f1.txt"
expect_eq 'f1.txt' "$(git ls-tree --name-only HEAD | grep '^f')" "HEAD keeps f1.txt and drops 'f[1].txt'"

# 17. Final guard: the index tree must match the gate's tree on every path the commit changes,
# and the commit must hold that index tree.
fresh a1; printf 'STAGED\n' > a.txt; git add a.txt; printf 'disk\n' > a.txt; git update-index --assume-unchanged a.txt
"$rgate" --force -- sh -c '! grep -q STAGED a.txt' >/dev/null; h="$(git rev-parse HEAD)"
err="$("$fc" --gate gate --allow-dirty "${four[@]}" -- a.txt 2>&1)"; expect_rc 3 $? "A1: staged content the gate never saw exits 3"
expect_grep 'the commit would hold content for these paths that differs from the tree it tested' "$err" "the guard refusal says why"
expect_grep '^  a\.txt$' "$err" "the guard refusal names the path"
expect_grep '^fix: stage the files as they are on disk .*--no-assume-unchanged' "$err" "the guard refusal's fix: line names the assume-unchanged mark"
expect_eq "$h" "$(git rev-parse HEAD)" "no commit after the guard refusal"
expect_eq "STAGED" "$(git show :a.txt)" "the guard refusal leaves the user's staged copy"
fresh h1; printf '#!/bin/sh\nprintf "HOOKED\\n" > a.txt; git add a.txt\n' > .git/hooks/pre-commit; chmod +x .git/hooks/pre-commit
printf 'a2\n' > a.txt; "$rgate" --force -- true >/dev/null
err="$("$fc" --gate gate "${four[@]}" -- a.txt 2>&1)"; expect_rc 1 $? "H1: a hook that rewrites a named file exits 1"
expect_grep "^ctlhq-commit: the commit [0-9a-f]{12} exists, but it differs from the index ctlhq-commit checked" "$err" "the H1 refusal says the commit differs"
expect_grep '^  M a\.txt$' "$err" "the H1 refusal names the changed path"
expect_grep '^fix: the commit [0-9a-f]{12} exists\. ' "$err" "the H1 fix line says the commit exists"
expect_grep 'undo it with `git -C /.* reset --soft HEAD~1`' "$err" "the H1 fix line gives the one-commit undo when HEAD's parent is the commit from before"
expect_eq "changed by a hook|1" "$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d["tree"], d["exit"], sep="|")' ".local/commits/$(git rev-parse HEAD).json")" "the H1 receipt says a hook changed the commit"
fresh h2; printf '#!/bin/sh\nprintf "HOOKED\\n" > b.txt; git add b.txt\n' > .git/hooks/pre-commit; chmod +x .git/hooks/pre-commit
printf 'a2\n' > a.txt; "$rgate" --force -- true >/dev/null
err="$("$fc" --gate gate "${four[@]}" -- a.txt 2>&1)"; expect_rc 1 $? "H2: a hook that stages an unnamed file exits 1"
expect_grep '^  M b\.txt$' "$err" "the H2 refusal names the unnamed path"

# 18. A refusal after staging puts the index back byte for byte.
fresh r1; printf 'a\nl2\nl3\n' > a.txt; git commit -qam three; printf 'A\nl2\nL3\n' > a.txt
git update-index --cacheinfo "100644,$(printf 'A\nl2\nl3\n' | git hash-object -w --stdin),a.txt"
"$rgate" --force -- true >/dev/null; printf 'new\n' > c.txt; i="$(index_sum)"
"$fc" --gate gate "${four[@]}" -- a.txt >/dev/null 2>&1; expect_rc 3 $? "R1: a late refusal with a partly staged file exits 3"
expect_eq "$i" "$(index_sum)" "R1: the index is byte for byte as it was"
expect_eq "$(printf 'A\nl2\nl3')" "$(git show :a.txt)" "R1: the partly staged copy is kept"
r="$tmp/r2"; git init -q "$r"; cd "$r" || exit 1; printf '.local/\n' > .gitignore; printf 'a\n' > a.txt; git add a.txt .gitignore
"$rgate" --force -- true >/dev/null; printf 'z\n' > z.txt; i="$(index_sum)"
"$fc" --gate gate "${four[@]}" -- a.txt .gitignore >/dev/null 2>&1; expect_rc 3 $? "R2: a late refusal before the first commit exits 3"
expect_eq "$i" "$(index_sum)" "R2: the index is byte for byte as it was"
expect_eq "$(printf '.gitignore\na.txt')" "$(git ls-files)" "R2: the user's staged files stay staged"

# 19. A gate killed with SIGKILL after an edit leaves the older record, and the commit is refused.
fresh k1; printf 'a2\n' > a.txt; "$rgate" --force -- true >/dev/null; printf 'a3\n' > a.txt
before="$(cat .local/gate/gate.exit .local/gate/gate.tree)"
"$rgate" --force -- sh -c "echo \$\$ > '$tmp/k1.pid'; exec sleep 30" >/dev/null 2>&1 & gpid=$!
n=0; while [ ! -s "$tmp/k1.pid" ] && [ $n -lt 100 ]; do sleep 0.1; n=$((n + 1)); done
kill -KILL "$gpid"; wait "$gpid" 2>/dev/null; kill -KILL "$(cat "$tmp/k1.pid")" 2>/dev/null
expect_eq "$before" "$(cat .local/gate/gate.exit .local/gate/gate.tree)" "a killed gate run leaves the older exit and tree record"
err="$("$fc" --gate gate "${four[@]}" -- a.txt 2>&1)"; expect_rc 3 $? "the commit after an edit and a killed gate run exits 3"
expect_grep 'the files on disk differ from the ones it tested' "$err" "the killed-run refusal says the files differ"

# 20. A submodule's staged commit counts as a staged change, whatever the ignore settings say.
ssrc="$tmp/ssrc"; git init -q "$ssrc"
(cd "$ssrc" && git config user.name t && git config user.email t@example.invalid && printf '1\n' > f && git add f && git commit -qm 1 && printf '2\n' > f && git commit -qam 2)
c1="$(git -C "$ssrc" rev-parse HEAD~1)"; c2="$(git -C "$ssrc" rev-parse HEAD)"
for mode in diffcfg gitmodules; do
  fresh "sub-$mode"; git -c protocol.file.allow=always submodule add -q "$ssrc" sub >/dev/null 2>&1; git -C sub checkout -q "$c1"; git add sub; git commit -qm sub
  case $mode in diffcfg) git config diff.ignoreSubmodules all;; gitmodules) git config -f .gitmodules submodule.sub.ignore all; git commit -qam ign;; esac
  git update-index --cacheinfo "160000,$c2,sub"; printf 'a2\n' > a.txt; h="$(git rev-parse HEAD)"
  err="$("$fc" "${four[@]}" -- a.txt 2>&1)"; expect_rc 3 $? "sub2 ($mode): a staged submodule commit outside the named paths exits 3 without --gate"
  expect_grep '^  sub$' "$err" "the sub2 ($mode) refusal names the submodule"
  expect_eq "$h" "$(git rev-parse HEAD)" "no commit after the sub2 ($mode) refusal"
done

# 21. After staging, the commit may change only named paths, with or without --gate.
fresh shim; printf 'a2\n' > a.txt; printf 'e\n' > extra.txt; "$rgate" --force -- true >/dev/null
realgit="$(command -v git)"; mkdir -p "$tmp/shimbin"
printf '#!/bin/sh\n"%s" "$@"; rc=$?\ncase " $* " in *" add -A "*) [ -z "${GIT_INDEX_FILE:-}" ] && "%s" add extra.txt;; esac\nexit $rc\n' "$realgit" "$realgit" > "$tmp/shimbin/git"; chmod +x "$tmp/shimbin/git"
h="$(git rev-parse HEAD)"; i="$(index_sum)"
err="$(PATH="$tmp/shimbin:$PATH" "$fc" "${four[@]}" -- a.txt 2>&1)"; expect_rc 3 $? "a path staged by something else after the tool's own git add exits 3 without --gate"
expect_grep '^ctlhq-commit: the commit would change paths outside the named paths' "$err" "the late unnamed-path refusal says why"
expect_grep '^  extra\.txt$' "$err" "the late unnamed-path refusal names the path"
err="$(PATH="$tmp/shimbin:$PATH" "$fc" --gate gate "${four[@]}" -- a.txt 2>&1)"; expect_rc 3 $? "the same with --gate exits 3, though the gate tested extra.txt"
expect_grep '^  extra\.txt$' "$err" "the --gate refusal names the path"
expect_eq "$h" "$(git rev-parse HEAD)" "no commit after the late unnamed-path refusals"
expect_eq "$i" "$(index_sum)" "the late unnamed-path refusals put the index back"

# 22. Without --gate, a staged copy that differs from the file on disk is refused.
for named in a.txt src; do
  p=a.txt; [ "$named" = src ] && p=src/x.py
  fresh "au-$named"; git update-index --cacheinfo "100644,$(printf 'EVIL\n' | git hash-object -w --stdin),$p"; git update-index --assume-unchanged "$p"; printf 'y2\n' > src/y.py
  h="$(git rev-parse HEAD)"
  err="$("$fc" "${four[@]}" -- "$named" src/y.py 2>&1)"; expect_rc 3 $? "au ($named): an assume-unchanged staged copy exits 3 without --gate"
  expect_grep 'differs from the files on disk; refusing to commit' "$err" "the au ($named) refusal says why"
  expect_grep "^  $p\$" "$err" "the au ($named) refusal names the path"
  expect_grep '^fix: stage the files as they are on disk .*--no-assume-unchanged --no-skip-worktree' "$err" "the au ($named) fix: line clears both marks"
  expect_eq "$h" "$(git rev-parse HEAD)" "no commit after the au ($named) refusal"
  expect_eq "EVIL" "$(git show ":$p")" "the au ($named) refusal keeps the user's staged copy"
done

# 23. A file marked skip-worktree inside a named folder: its staged copy differs from the disk.
for g in gate nogate; do
  fresh "skip-$g"; git update-index --cacheinfo "100644,$(printf 'EVIL\n' | git hash-object -w --stdin),src/x.py"; git update-index --skip-worktree src/x.py; printf 'y2\n' > src/y.py
  "$rgate" --force -- true >/dev/null; h="$(git rev-parse HEAD)"
  if [ $g = gate ]; then err="$("$fc" --gate gate "${four[@]}" -- src 2>&1)"; rc=$?; else err="$("$fc" "${four[@]}" -- src 2>&1)"; rc=$?; fi
  expect_rc 3 $rc "K4 ($g): a skip-worktree file with a different staged copy exits 3"
  expect_grep '^  src/x\.py$' "$err" "the K4 ($g) refusal names the path"
  expect_eq "$h" "$(git rev-parse HEAD)" "no commit after the K4 ($g) refusal"
done
fresh skip-gone; git update-index --cacheinfo "100644,$(printf 'EVIL\n' | git hash-object -w --stdin),src/x.py"; git update-index --skip-worktree src/x.py; rm src/x.py; printf 'y2\n' > src/y.py
"$rgate" --force -- true >/dev/null; h="$(git rev-parse HEAD)"
err="$("$fc" --gate gate "${four[@]}" -- src 2>&1)"; expect_rc 3 $? "K5: a skip-worktree file missing from disk with a different staged copy exits 3"
expect_grep '^  src/x\.py$' "$err" "the K5 refusal names the path"
expect_eq "$h" "$(git rev-parse HEAD)" "no commit after the K5 refusal"

# 24. A sparse checkout still commits a path inside the cone after a gate.
fresh sparse; mkdir docs; printf 'd\n' > docs/d.md; git add docs; git commit -qm docs; git sparse-checkout set src 2>/dev/null
printf 'x2\n' > src/x.py; "$rgate" --force -- true >/dev/null
out="$("$fc" --gate gate "${four[@]}" -- src/x.py 2>&1)"; expect_rc 0 $? "a sparse checkout commits a path inside the cone"
expect_eq "docs/d.md" "$(git ls-tree -r --name-only HEAD docs)" "the sparse commit keeps the file outside the cone"
expect_grep '^tree: clean$' "$out" "the sparse commit leaves the tree clean"
fresh sparse-nocone; git sparse-checkout set --no-cone src 2>/dev/null
printf 'x2\n' > src/x.py; "$rgate" --force -- true >/dev/null
out="$("$fc" --gate gate "${four[@]}" -- src/x.py 2>&1)"; expect_rc 0 $? "S1: a non-cone sparse checkout whose .gitignore is outside the patterns commits"
expect_eq "$(printf '.gitignore\na.txt\nb.txt')" "$(git ls-tree --name-only HEAD | grep -v src)" "S1: the commit keeps the files outside the patterns"

# 25. An interrupt during the pre-commit hook puts the index back.
fresh intr; printf 'b2\n' > b.txt; git add b.txt; printf 'b3\n' > b.txt; printf 'a2\n' > a.txt
printf '#!/bin/sh\ntouch .git/hook-started\nsleep 5\n' > .git/hooks/pre-commit; chmod +x .git/hooks/pre-commit
h="$(git rev-parse HEAD)"; i="$(index_sum)"
for sig in INT TERM; do
  rm -f .git/hook-started
  rc="$(python3 - "$fc" "$sig" "${four[@]}" <<'PY'
import os, signal, subprocess, sys, time
fc, sig, four = sys.argv[1], getattr(signal, "SIG" + sys.argv[2]), sys.argv[3:]
p = subprocess.Popen([fc, *four, "--", "a.txt", "b.txt"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                     preexec_fn=lambda: signal.signal(signal.SIGINT, signal.SIG_DFL))
for _ in range(200):
    if os.path.exists(".git/hook-started"):
        break
    time.sleep(0.05)
p.send_signal(sig)
print(p.wait())
PY
)"
  case $sig in INT) expect_eq "-2" "$rc" "SIGINT during the pre-commit hook ends the run as Ctrl-C does";; TERM) expect_eq "143" "$rc" "SIGTERM during the pre-commit hook exits 143";; esac
  expect_eq "$h" "$(git rev-parse HEAD)" "no commit after SIG$sig during the pre-commit hook"
  expect_eq "$i" "$(index_sum)" "SIG$sig during the pre-commit hook puts the index back byte for byte"
  expect_eq "b2" "$(git show :b.txt)" "SIG$sig keeps the user's partly staged b.txt"
done
rm .git/hooks/pre-commit

# 26. A file name that is not UTF-8 (byte 0xff) inside a named folder.
fresh bytes; ff="$(printf '\377')"
git update-index --add --cacheinfo "100644,$(printf 'q\n' | git hash-object -w --stdin),src/$ff.txt"; git commit -qm bytes
printf 'x2\n' > src/x.py; "$rgate" --force -- true >/dev/null
out="$("$fc" --gate gate "${four[@]}" -- src 2>&1)"; expect_rc 0 $? "U1: a file name with byte 0xff inside a named folder commits"
expect_eq "committed $(git rev-parse HEAD)" "$(printf '%s\n' "$out" | tail -1)" "U1: the run ends with 'committed <hash>'"
git update-index --add --cacheinfo "100644,$(printf 'r\n' | git hash-object -w --stdin),$ff.txt"; printf 'a2\n' > a.txt
err="$("$fc" "${four[@]}" -- a.txt 2>&1)"; expect_rc 3 $? "a staged unnamed file with byte 0xff in its name exits 3"
case "$err" in *Traceback*) bad "the 0xff refusal prints no Python traceback";; *) ok;; esac

# 27. A split index with sharedIndexExpire=now stays readable after a late refusal.
fresh split; git config core.splitIndex true; git config splitIndex.maxPercentChange 0; git config splitIndex.sharedIndexExpire now; git update-index --split-index
printf 'b2\n' > b.txt; git add b.txt; printf 'b3\n' > b.txt; printf 'a2\n' > a.txt
"$rgate" --force -- true >/dev/null; printf 'c\n' > c.txt; i="$(git ls-files -s | cksum)"
"$fc" --gate gate "${four[@]}" -- a.txt b.txt >/dev/null 2>&1; expect_rc 3 $? "X2: a late refusal with a split index exits 3"
git ls-files -s >/dev/null 2>"$tmp/x2.err"; expect_eq "" "$(cat "$tmp/x2.err")" "X2: the restored split index is readable with sharedIndexExpire=now"
expect_eq "$i" "$(git ls-files -s 2>/dev/null | cksum)" "X2: the restored index holds the same entries"

# 28. The undo hint names the commit from before the run when a hook made another commit.
fresh undo; h0="$(git rev-parse HEAD)"; printf 'z\n' > z.txt; printf 'a2\n' > a.txt
printf '#!/bin/sh\n[ -e .git/extra-done ] && exit 0\ntouch .git/extra-done\ngit add z.txt\ngit commit -q -m extra --no-verify\n' > .git/hooks/post-commit; chmod +x .git/hooks/post-commit
err="$("$fc" "${four[@]}" -- a.txt 2>&1)"; expect_rc 1 $? "a post-commit hook that makes another commit exits 1"
fixl="$(printf '%s\n' "$err" | grep '^fix: ')"
expect_grep "HEAD's parent is not ${h0:0:12}" "$fixl" "the fix: line says HEAD's parent is not the commit from before the run"
expect_grep "git -C /.* reset --soft ${h0:0:12}" "$fixl" "the fix: line names that earlier commit"
case "$fixl" in *HEAD~1*) bad "the fix: line leaves out git reset --soft HEAD~1";; *) ok;; esac

fresh review; r="$(pwd -P)"; printf 'a2\n' > a.txt; h="$(git rev-parse HEAD)"; i="$(index_sum)"
mkdir -p .local/reviews; : > .local/reviews/empty.md; printf ' \n\t\n' > .local/reviews/blank.md; mkdir .local/reviews/folder.md; printf 'r\n' > .local/reviews/locked.md; chmod 000 .local/reviews/locked.md
for case in 'missing.md|does not exist' 'folder.md|is not a regular file' 'locked.md|cannot be read' 'empty.md|is empty' 'blank.md|is empty'; do
  f="${case%%|*}"; why="${case#*|}"
  err="$("$fc" --review ".local/reviews/$f" "${four[@]}" -- a.txt 2>&1)"; expect_rc 3 $? "R1: a review file that $why exits 3"
  expect_grep "^ctlhq-commit: review file $r/\.local/reviews/$f $why( \(.*\))?; refusing to commit$" "$err" "R1: the '$f' refusal names the file and why"
  expect_grep '^fix: save the reviewer' "$err" "R1: the '$f' refusal has a fix: line"
  expect_eq "$i" "$(index_sum)" "R1: the '$f' refusal leaves the index unchanged"
done
chmod 644 .local/reviews/locked.md
expect_eq "$h" "$(git rev-parse HEAD)" "R1: no commit after the review refusals"
printf 'accept\n' > .local/reviews/a.md
out="$("$fc" --review .local/reviews/a.md "${four[@]}" -- a.txt 2>&1)"; expect_rc 0 $? "R2: a saved review file commits"
expect_grep "^review: \.local/reviews/a\.md$" "$out" "R2: the review path is printed relative to the repository"
review_of() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["review"])' ".local/commits/$1.json"; }
expect_eq ".local/reviews/a.md" "$(review_of "$(git rev-parse HEAD)")" "R2: the receipt records the review file's path, as it does the message file's"
"$fc" --review "" "${four[@]}" -- a.txt >/dev/null 2>&1; expect_rc 2 $? "R2: an empty --review value is a usage error"
printf 'a3\n' > a.txt; "$fc" "${four[@]}" -- a.txt >/dev/null 2>&1
expect_eq "None" "$(review_of "$(git rev-parse HEAD)")" "R3: without --review the receipt's review is null"
expect_grep '\[--review FILE\]' "$("$fc" --help)" "R4: --help lists --review"

# 29. The message check: a flagged message is refused before anything is staged, and the check fails closed.
msgs="$root/tests/ctlhq-message-check/fixtures"
fresh msg; printf 'a2\n' > a.txt; printf 'b2\n' > b.txt; git add b.txt; h="$(git rev-parse HEAD)"; i="$(index_sum)"; before="$(ls .local/commit 2>/dev/null | wc -l)"
err="$("$fc" --message-file "$msgs/bad-example.txt" -- a.txt b.txt 2>&1)"; expect_rc 6 $? "MSG1: a flagged message file exits 6"
expect_grep '^line 1: label: ' "$err" "MSG1: the refusal names the line and the rule"
expect_grep '^line 10: review: - blind review' "$err" "MSG1: the refusal prints the text of each line"
expect_grep '^why: ' "$err" "MSG1: the refusal has a why: line"
expect_grep '^fix: .*PLAN\.md section 10' "$err" "MSG1: the refusal says where the note belongs"
expect_eq "$i" "$(index_sum)" "MSG1: the index stays byte for byte"
expect_eq "$h" "$(git rev-parse HEAD)" "MSG1: no commit after the refusal"
expect_eq "$before" "$(ls .local/commit 2>/dev/null | wc -l)" "MSG1: no message file is kept for a refused message"
git reset -q b.txt; git checkout -q b.txt
err="$("$fc" --subject "Add a.txt" --why "Commit review: accept." --changes c --test-plan t --risks r -- a.txt 2>&1)"; expect_rc 6 $? "MSG2: a flagged --why exits 6"
expect_grep '^line 4: review: ' "$err" "MSG2: the refusal numbers the built message's lines"
expect_eq "" "$(git diff --cached --name-only)" "MSG2: nothing is staged"
printf 'a3\n' > a.txt
mkdir -p .local/reviews; printf 'accept\n' > .local/reviews/msg.md
out="$("$fc" --message-file "$msgs/clean-good-example.txt" --review .local/reviews/msg.md -- a.txt 2>&1)"; expect_rc 0 $? "MSG3: the good example commits"
expect_grep '^committed ' "$out" "MSG3: the commit exists"
expect_eq ".local/reviews/msg.md" "$(review_of "$(git rev-parse HEAD)")" "MSG3: the receipt holds the review path"
printf 'a3b\n' > a.txt; mkdir -p "$HOME/.ctlhq"; printf 'Zebrafinch\n' > "$HOME/.ctlhq/message-words.txt"
err="$("$fc" --subject "the zebrafinch change" --why w --changes c --test-plan t --risks r -- a.txt 2>&1)"; expect_rc 6 $? "MSG3b: a word from the list exits 6"
expect_grep '^line 1: extra-word: the \*+ change$' "$err" "MSG3b: the refusal names the line, with the word starred out"
expect_eq 0 "$(printf '%s\n' "$err" | grep -ci zebrafinch)" "MSG3b: the refusal never prints the word"
rm "$HOME/.ctlhq/message-words.txt"; ln -s "$tmp/nowhere" "$HOME/.ctlhq/message-words.txt"
err="$("$fc" --subject "plain" --why w --changes c --test-plan t --risks r -- a.txt 2>&1)"; expect_rc 6 $? "MSG3c: a dangling word list exits 6"
expect_grep 'check did not run.*message-words\.txt' "$err" "MSG3c: the line says the check did not run, and names the list"
expect_grep '^fix: .*word list' "$err" "MSG3c: the fix line names a broken word list"
expect_grep '^fix: .*`/.*/ctlhq-message-check --help`' "$err" "MSG3c: the fix line gives the check's full path"
rm "$HOME/.ctlhq/message-words.txt"; git checkout -q a.txt

checkout="$tmp/checkout/bin"; mkdir -p "$checkout"
cp "$fc" "$root/bin/ctlhq-run-gate" "$checkout/"
stub() { printf '#!/usr/bin/env python3\nimport sys\nsys.stdin.read()\n%s\n' "$1" > "$checkout/ctlhq-message-check"; chmod +x "$checkout/ctlhq-message-check"; }
fresh stub; printf 'a2\n' > a.txt; h="$(git rev-parse HEAD)"; i="$(index_sum)"
err="$("$checkout/ctlhq-commit" --message-file "$msgs/clean-good-example.txt" -- a.txt 2>&1)"; expect_rc 6 $? "MSG4: a missing check exits 6"
expect_grep 'check did not run' "$err" "MSG4: the line says the check did not run"
expect_eq "$i" "$(index_sum)" "MSG4: the index stays byte for byte"
for code in 2 3; do
  stub "sys.exit($code)"
  err="$("$checkout/ctlhq-commit" --message-file "$msgs/clean-good-example.txt" -- a.txt 2>&1)"; expect_rc 6 $? "MSG5: a check that exits $code gives exit 6"
  expect_grep 'check did not run' "$err" "MSG5: exit $code: the line says the check did not run"
done
stub "sys.exit(1)"
err="$("$checkout/ctlhq-commit" --message-file "$msgs/clean-good-example.txt" -- a.txt 2>&1)"; expect_rc 6 $? "MSG6: a check that exits 1 with no finding gives exit 6"
expect_grep 'check did not run' "$err" "MSG6: exit 1 with no finding: the line says the check did not run"
expect_grep 'did not run \(exit 1\): it printed no reason; refusing' "$err" "MSG6: the line says the check gave no reason"
printf '#!/usr/bin/env python3\nthis is not python\n' > "$checkout/ctlhq-message-check"
err="$("$checkout/ctlhq-commit" --message-file "$msgs/clean-good-example.txt" -- a.txt 2>&1)"; expect_rc 6 $? "MSG7: a check with a syntax error gives exit 6"
expect_grep 'check did not run' "$err" "MSG7: a syntax error: the line says the check did not run"
expect_eq "$i" "$(index_sum)" "MSG7: the index stays byte for byte"
expect_eq "$h" "$(git rev-parse HEAD)" "MSG7: no commit when the check did not run"
stub "sys.exit(0)"
"$checkout/ctlhq-commit" --message-file "$msgs/bad-example.txt" -- a.txt >/dev/null 2>&1; expect_rc 0 $? "MSG8: a checkout's own bin/ctlhq-commit uses that checkout's check"
expect_eq "fix: answer the milestone 2 pull-request reviews" "$(git log -1 --format=%s)" "MSG8: the fixed check let the commit through"
expect_grep '6 the message check' "$("$fc" --help)" "MSG9: --help lists exit 6"
printf 'fix the \377 byte\n' > .local/not-utf8.txt
err="$("$fc" --message-file .local/not-utf8.txt -- a.txt 2>&1)"; expect_rc 2 $? "MSG10: a message file that is not UTF-8 exits 2"
expect_grep 'not-utf8\.txt is not UTF-8 text' "$err" "MSG10: the line names the file and the cause"
expect_nogrep 'Traceback' "$err" "MSG10: no Python traceback"

fresh tz; printf 'a2\n' > a.txt
TZ=Asia/Kolkata "$fc" "${four[@]}" -- a.txt >/dev/null 2>&1; expect_rc 0 $? "T1: a commit in Asia/Kolkata exits 0"
expect_eq "+0000 +0000" "$(git log -1 --format='%ad %cd' --date=format:%z)" "T1: without --tz both dates record UTC"
printf 'a3\n' > a.txt
TZ=Asia/Kolkata "$fc" --tz local "${four[@]}" -- a.txt >/dev/null 2>&1; expect_rc 0 $? "T2: a commit with --tz local exits 0"
expect_eq "+0530 +0530" "$(git log -1 --format='%ad %cd' --date=format:%z)" "T2: --tz local keeps the machine's zone in both dates"
printf 'a4\n' > a.txt; h="$(git rev-parse HEAD)"
err="$("$fc" --tz Europe/Berlin "${four[@]}" -- a.txt 2>&1)"; expect_rc 2 $? "T3: --tz Europe/Berlin exits 2"
expect_grep '^usage: ctlhq-commit ' "$err" "T3: the refusal prints the usage line"
expect_eq "$h" "$(git rev-parse HEAD)" "T3: no commit after the --tz refusal"
expect_grep '\[--tz local\]' "$("$fc" --help)" "T4: --help lists --tz local"

fresh anyfolder
outside="$tmp/outside"; mkdir -p "$outside"
mkdir -p .local/in
printf 'Add one\n\nWhy:\nIt is needed.\n\nChanges:\nOne file.\n\nTest Plan:\nRead it.\n\nRisks:\nNone known.\n' > .local/in/m.txt
printf 'reviewed\n' > .local/in/r.md
printf 'c1\n' > "c one.txt"
printf 'c one.txt\n' > .local/in/p.txt
"$rgate" -C "$PWD" --force -- true >/dev/null
here_repo="$PWD"
out="$(cd "$outside" && "$fc" -C "$here_repo" --gate gate --review .local/in/r.md --message-file .local/in/m.txt --paths-file .local/in/p.txt 2>&1)"; expect_rc 0 $? "C1: -C with relative --review, --message-file and --paths-file commits from another folder"
expect_eq "c one.txt" "$(git show --name-only --format= HEAD)" "C1: the path with a space is committed under its whole name"
expect_grep '^review: \.local/in/r\.md$' "$out" "C1: the review file resolves inside DIR"
expect_nogrep '^folder: ' "$out" "C1: the run prints no folder line, because fix: lines name their folder"
expect_eq "" "$(ls -A "$outside")" "C1: nothing is written in the folder the tool started from"
err="$(cd "$outside" && "$fc" -C "$tmp/no-such-folder" "${four[@]}" -- a.txt 2>&1)"; expect_rc 2 $? "C2: a missing DIR exits 2"
expect_grep 'no-such-folder' "$err" "C2: the refusal names the folder"
expect_nogrep 'Traceback' "$err" "C2: no Python traceback"
err="$("$fc" -C 2>&1)"; expect_rc 2 $? "C3: -C with no value exits 2"
expect_grep '^usage: ctlhq-commit -C DIR|\[-C DIR\]' "$err" "C3: the refusal prints the usage line with -C"
printf 'c4\n' > "c 4.txt"; printf 'c 4.txt\n' > .local/in/p.txt
(cd "$outside" && "$fc" --review .local/in/r.md --message-file .local/in/m.txt --paths-file .local/in/p.txt -C "$here_repo" >/dev/null 2>&1); expect_rc 0 $? "C4: -C after other options still resolves their relative files in DIR, as ctlhq-push accepts it"
expect_eq "c 4.txt" "$(git show --name-only --format= HEAD)" "C4: the commit holds the path from the file in DIR"
err="$("$fc" -C "$here_repo" -C "$here_repo" "${four[@]}" -- a.txt 2>&1)"; expect_rc 2 $? "C5: a second -C exits 2"
expect_grep '^ctlhq-commit: -C given twice' "$err" "C5: the refusal says -C came twice"
(cd "$outside" && "$fc" -C "$outside" "${four[@]}" -- a.txt >/dev/null 2>&1); expect_rc 1 $? "C6: -C on a folder outside a work tree exits 1"
mkdir -p "sub dir"; printf 's\n' > "sub dir/in sub.txt"
(cd "$outside" && "$fc" -C "$here_repo/sub dir" "${four[@]}" -- "in sub.txt" >/dev/null 2>&1); expect_rc 0 $? "C7: -C on a subfolder reads paths from that subfolder"
expect_eq "sub dir/in sub.txt" "$(git show --name-only --format= HEAD)" "C7: the path is the one inside the subfolder"
printf 'two\n' > a2.txt; printf 'three\n' > "b 3.txt"; printf 'b 3.txt\n' > .local/in/p.txt
"$fc" "${four[@]}" --paths-file .local/in/p.txt -- a2.txt >/dev/null 2>&1; expect_rc 0 $? "P1: --paths-file adds to the paths after --"
expect_eq "$(printf 'a2.txt\nb 3.txt')" "$(git show --name-only --format= HEAD | sort)" "P1: both the file's path and the path after -- are committed"
printf 'four\n' > c4.txt; printf 'c4.txt' > .local/in/p.txt
"$fc" "${four[@]}" --paths-file .local/in/p.txt -- >/dev/null 2>&1; expect_rc 0 $? "P2: a file with no final newline works, with an empty list after --"
head_p="$(git rev-parse HEAD)"; printf 'five\n' > d5.txt
for bad_entry in . .. -A --all '*' --cached; do
  printf 'd5.txt\n%s\n' "$bad_entry" > .local/in/p.txt
  err="$("$fc" "${four[@]}" --paths-file .local/in/p.txt 2>&1)"; expect_rc 2 $? "P3: the entry '$bad_entry' in a paths file exits 2"
  expect_grep 'git add is by name' "$err" "P3: the '$bad_entry' refusal says add is by name"
done
: > .local/in/p.txt
err="$("$fc" "${four[@]}" --paths-file .local/in/p.txt -- d5.txt 2>&1)"; expect_rc 2 $? "P4: an empty paths file exits 2, even with paths after --"
expect_grep 'p\.txt is empty' "$err" "P4: the refusal names the file"
printf 'd5.txt\n\nb 3.txt\n' > .local/in/p.txt
err="$("$fc" "${four[@]}" --paths-file .local/in/p.txt 2>&1)"; expect_rc 2 $? "P5: a blank line in a paths file exits 2"
expect_grep 'line 2 is empty' "$err" "P5: the refusal names the line"
printf '\n' > .local/in/p.txt
"$fc" "${four[@]}" --paths-file .local/in/p.txt >/dev/null 2>&1; expect_rc 2 $? "P6: a paths file with only a newline exits 2"
err="$("$fc" "${four[@]}" --paths-file .local/in/none.txt 2>&1)"; expect_rc 2 $? "P7: a missing paths file exits 2"
expect_grep 'cannot read --paths-file' "$err" "P7: the refusal says the file cannot be read"
"$fc" "${four[@]}" --paths-file >/dev/null 2>&1; expect_rc 2 $? "P8: --paths-file with no value exits 2"
printf 'no-such-file.txt\n' > .local/in/p.txt
err="$("$fc" "${four[@]}" --paths-file .local/in/p.txt 2>&1)"; expect_rc 1 $? "P9: a named path that does not exist exits 1, as after --"
expect_grep 'no-such-file\.txt: not on disk' "$err" "P9: the refusal names the path"
printf 'pat/*.txt\n' > .local/in/p.txt; mkdir -p pat; printf 'g\n' > pat/g.txt
"$fc" "${four[@]}" --paths-file .local/in/p.txt >/dev/null 2>&1; expect_rc 1 $? "P10: a pattern in a paths file matches nothing, because a path is a plain name"
rm -rf pat
expect_eq "$head_p" "$(git rev-parse HEAD)" "P: no commit after the paths-file refusals"
expect_eq "" "$(git diff --cached --name-only)" "P: nothing stays staged after the refusals"
printf 'd5.txt\n' > .local/in/p.txt
"$fc" "${four[@]}" --paths-file .local/in/p.txt >/dev/null 2>&1; expect_rc 0 $? "P11: a named path alone in the file commits with no -- at all"
expect_grep '\-\-paths-file FILE' "$("$fc" --help)" "P12: --help lists --paths-file"
expect_grep '^  ctlhq-commit \[-C DIR\]' "$("$fc" --help)" "P12: --help lists -C"

fresh wholetree
top_n="$PWD"; printf 'n1\n' > n1.txt; h_n="$(git rev-parse HEAD)"; mkdir -p .local
for form in ./ .// ./. ././ ../ ../.. src/.. ./src/../ "$top_n" "$top_n/" "$top_n/." "$top_n/src/.." "../$(basename "$top_n")"; do
  err="$("$fc" "${four[@]}" -- "$form" 2>&1)"; expect_rc 2 $? "N1: the path '$form' after -- exits 2"
  expect_grep 'git add is by name' "$err" "N1: the '$form' refusal says add is by name"
  printf '%s\n' "$form" > .local/p.txt
  "$fc" "${four[@]}" --paths-file .local/p.txt >/dev/null 2>&1; expect_rc 2 $? "N2: the entry '$form' in a paths file exits 2"
done
for form in ./ ../ .. "$top_n" "../../$(basename "$top_n")" ../src/..; do
  "$fc" -C src "${four[@]}" -- "$form" >/dev/null 2>&1; expect_rc 2 $? "N3: from a subfolder, the path '$form' exits 2"
done
expect_eq "$h_n" "$(git rev-parse HEAD)" "N: no commit after the whole-tree refusals"
expect_eq "" "$(git diff --cached --name-only)" "N: nothing stays staged after the whole-tree refusals"
printf 'x2\n' > src/x.py; printf 'src/x.py\n' > .local/p.txt
"$fc" --allow-dirty "${four[@]}" -- ./src/x.py >/dev/null 2>&1; expect_rc 0 $? "N4: a named file written with ./ still commits"
expect_eq "src/x.py" "$(git show --name-only --format= HEAD)" "N4: only that file is committed"
printf 'y2\n' > src/y.py
"$fc" -C src --allow-dirty "${four[@]}" -- ../src >/dev/null 2>&1; expect_rc 0 $? "N5: a named folder reached through .. still commits"
expect_eq "src/y.py" "$(git show --name-only --format= HEAD)" "N5: only that folder's change is committed"
ln -s . self
"$fc" --allow-dirty "${four[@]}" -- self >/dev/null 2>&1; expect_rc 0 $? "N6: a symbolic link to the top, named by name, commits as a link"
expect_eq "self" "$(git show --name-only --format= HEAD)" "N6: only the link is committed, with n1.txt left out"

fresh byteslist; mkdir -p .local; ff="$(printf '\377')"
git update-index --add --cacheinfo "100644,$(printf 'q\n' | git hash-object -w --stdin),$ff.txt"; git commit -qm bytes
printf '%s.txt\n' "$ff" > .local/p.txt
err="$("$fc" "${four[@]}" --paths-file .local/p.txt 2>&1)"; expect_rc 0 $? "N7: a paths-file entry with byte 0xff reaches git unchanged, so its deletion commits"
expect_nogrep 'Traceback' "$err" "N7: no Python traceback"
expect_eq "" "$(git ls-files -- "$ff.txt")" "N7: the file with byte 0xff is gone from the index"

printf 'p\n' > n1.txt; printf 'q\n' > n2.txt; printf 'n1.txt\n' > .local/p1.txt; printf 'n2.txt\n' > .local/p2.txt; h_t="$(git rev-parse HEAD)"
err="$("$fc" --allow-dirty "${four[@]}" --paths-file .local/p1.txt --paths-file .local/p2.txt 2>&1)"; expect_rc 2 $? "A2: a second --paths-file exits 2"
expect_grep '^ctlhq-commit: --paths-file given twice' "$err" "A2: the refusal says it came twice"
printf 'n1.txt\0' > .local/p.txt
err="$("$fc" "${four[@]}" --paths-file .local/p.txt 2>&1)"; expect_rc 2 $? "A4: a NUL byte in a paths file exits 2"
expect_grep 'line 1 holds a NUL byte' "$err" "A4: the refusal names the line"
expect_nogrep 'Traceback' "$err" "A4: no Python traceback"
printf 'n1.txt\nn2.txt\0' > .local/p.txt
err="$("$fc" "${four[@]}" --paths-file .local/p.txt 2>&1)"; expect_rc 2 $? "A4: a NUL byte on a later line exits 2"
expect_grep 'line 2 holds a NUL byte' "$err" "A4: the refusal names the later line"
expect_eq "$h_t" "$(git rev-parse HEAD)" "A2, A4: no commit after the refusals"
expect_eq "" "$(git diff --cached --name-only)" "A2, A4: nothing staged after the refusals"
expect_grep 'made only of "\." and "\.\." parts' "$("$fc" --help | tr '\n' ' ' | tr -s ' ')" "A3: --help says which paths the dot rule refuses"
"$fc" "${four[@]}" -- "" >/dev/null 2>&1; expect_rc 2 $? "A3: an empty path after -- exits 2"

fresh fixlines; top_f="$(pwd -P)"; away="$tmp/away place"; mkdir -p "$away" sub .local; printf '#!/bin/sh\nexit 0\n' > sub/check.sh; chmod +x sub/check.sh; git add -A; git commit -qm check
ln -s "$top_f" "$tmp/toplink"; printf 'n\n' > n.txt; h_f="$(git rev-parse HEAD)"
err="$("$fc" -C "$top_f" "${four[@]}" -- "$tmp/toplink" 2>&1)"; expect_rc 2 $? "A5: a link outside the work tree that points at the top exits 2"
expect_grep 'top of the work tree' "$err" "A5: the refusal says it is the top"
expect_eq "" "$(git diff --cached --name-only)" "A5: nothing is staged, not even for a moment's refusal"
(cd "$away" && "$rgate" -C "$top_f/sub" --force -- ./check.sh >/dev/null); expect_rc 0 $? "F1: a gate runs in a subfolder"
printf 'n2\n' > n.txt
err="$(cd "$away" && "$fc" -C "$top_f" --gate gate "${four[@]}" -- n.txt 2>&1)"; expect_rc 3 $? "F1: an edit after the gate exits 3"
line="$(printf '%s\n' "$err" | sed -n 's/^fix: rerun `\(.*\)`, then run ctlhq-commit again\.$/\1/p')"
expect_grep "^$root/bin/ctlhq-run-gate -C $top_f/sub -- \./check\.sh$" "$line" "F1: the fix line names the tool's full path and the gate's own folder"
(cd "$away" && eval "${line/ -- / --force -- }" >/dev/null 2>&1); expect_rc 0 $? "F1: the fix line runs as written from another folder"
"$fc" -C "$top_f" --gate gate "${four[@]}" -- n.txt >/dev/null 2>&1; expect_rc 0 $? "F1: after the fix line, the commit goes through"
printf 'n3\n' > n.txt; printf 's\n' > s.txt; git add s.txt
err="$(cd "$away" && "$fc" -C "$top_f" --allow-dirty "${four[@]}" -- n.txt 2>&1)"; expect_rc 3 $? "F2: a staged path outside the named paths exits 3"
line="$(printf '%s\n' "$err" | sed -n 's/^fix: .*unstage them with `\(.*\)`, then run.*$/\1/p')"
(cd "$away" && eval "${line/<path>/s.txt}"); expect_rc 0 $? "F2: the fix line runs as written from another folder"
expect_eq "" "$(git diff --cached --name-only)" "F2: the fix line unstaged the path"
rm s.txt; git checkout -q -- n.txt
err="$(cd "$away" && "$fc" -C "$top_f" --gate never "${four[@]}" -- n.txt 2>&1)"; expect_rc 3 $? "F3: a gate that never ran exits 3"
expect_grep "run \`$root/bin/ctlhq-run-gate -C $top_f --name never -- <command>\` first" "$err" "F3: the line names the tool's full path, the folder and the gate"

echo "$pass checks passed"
if [ "$fail" -gt 0 ]; then echo "$fail checks failed"; exit 1; fi
exit 0
