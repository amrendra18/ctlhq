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

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
unset CLAUDECODE CODEX_THREAD_ID AI_AGENT CTLHQ_CO_AUTHOR CTLHQ_COMMIT_CONFIG
trailer="Co-Authored-By: Test Agent <agent@example.invalid>"
export CTLHQ_CO_AUTHOR="$trailer"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/ctlhq-commit-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
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
expect_grep '^fix: rerun `ctlhq-run-gate' "$err" "the missing-record refusal says to rerun the gate"
printf 'head none\ntracked x\nuntracked y\n' > .local/gate/gate.tree
err="$("$fc" --gate gate "${four[@]}" -- a.txt 2>&1)"; expect_rc 3 $? "a record in the round-1 three-line format exits 3"
expect_grep 'no tree line' "$err" "the refusal says the record has no tree line"
"$rgate" --force -- test -f a.txt >/dev/null; expect_rc 0 $? "the gate runs in a repository with no commits"
expect_eq "$(printf 'exit 0\ntree %s' "$("$rgate" --tree)")" "$(cat .local/gate/gate.tree)" "the record holds the run's exit and the tree ID, with no commits yet"
printf 'edited\n' > a.txt
err="$("$fc" --gate gate "${four[@]}" -- a.txt 2>&1)"; expect_rc 3 $? "an untracked file edited after the gate exits 3"
expect_grep 'the files on disk differ from the ones it tested' "$err" "the refusal says the files differ"
expect_grep '^fix: rerun `ctlhq-run-gate -- test -f a\.txt`' "$err" "the fix line repeats the gate's own command"
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
expect_grep '^fix: name them after --, or unstage them with `git reset -q -- <path>`' "$err" "the refusal has a fix: line"
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
expect_grep 'undo it with `git reset --soft HEAD~1`' "$err" "the H1 fix line gives the one-commit undo when HEAD's parent is the commit from before"
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
expect_grep "git reset --soft ${h0:0:12}" "$fixl" "the fix: line names that earlier commit"
case "$fixl" in *HEAD~1*) bad "the fix: line leaves out git reset --soft HEAD~1";; *) ok;; esac

echo "$pass checks passed"
if [ "$fail" -gt 0 ]; then echo "$fail checks failed"; exit 1; fi
exit 0
