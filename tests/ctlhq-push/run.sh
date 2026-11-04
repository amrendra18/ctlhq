#!/usr/bin/env bash
# tests/ctlhq-push/run.sh: checks for bin/ctlhq-push in a scratch git repository. No
# network: the address checks push with GIT_SSH_COMMAND=false, so ssh fails at once. The message
# checks push through a stand-in for ssh that hands each push to a scratch bare repository.
# The allowed owner comes from a scratch HOME's .ctlhq/first-push.toml, never the real one.
# Prints "N checks passed" and exits 1 when any check fails.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
fp="$root/bin/ctlhq-push"
pass=0
fail=0
ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL: $1"; }
expect_rc() { if [ "$1" -eq "$2" ]; then ok; else bad "$3 (expected exit $1, got $2)"; fi; }
expect_grep() { if printf '%s\n' "$2" | grep -Eq -- "$1"; then ok; else bad "$3 (no line matches: $1)"; fi; }

# A hook or caller may export these; they would point the scratch commands at a real repository.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR GIT_PREFIX
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_SSH_COMMAND=false
unset FIRST_PUSH_CONFIG
tmp="$(mktemp -d "${TMPDIR:-/tmp}/ctlhq-push-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home"
mkdir -p "$HOME/.ctlhq"
settings="$HOME/.ctlhq/first-push.toml"
printf '# ctlhq-first-push settings\nother = "x"\ngithub_owner = "acme"\n' >"$settings"
repo="$tmp/repo"
mkdir -p "$repo"
git -C "$repo" init -q -b main
git -C "$repo" -c user.name=T -c user.email=t@example.invalid -c commit.gpgsign=false commit -q --allow-empty -m first
git -C "$repo" remote add mine git@github.com:acme/widgets.git
git -C "$repo" remote add other git@github.com:someone-else/repo.git
git -C "$repo" remote add near git@github.com:acmex/repo.git
git -C "$repo" remote add local "$tmp/bare.git"
git -C "$repo" remote add mixed git@github.com:acme/a.git
git -C "$repo" remote set-url --add --push mixed git@github.com:acme/a.git
git -C "$repo" remote set-url --add --push mixed https://gitlab.com/acme/a.git

out="$("$fp" -C "$repo" mine main 2>&1)"; rc=$?
expect_rc 1 "$rc" "own GitHub repo is pushed (ssh fails offline)"
expect_grep '^pushing: mine main -> git@github.com:acme/widgets.git \(owner acme from .*/\.ctlhq/first-push\.toml\)$' "$out" "push line names the address, the owner, and the settings file"
for remote in other near local mixed; do
  out="$("$fp" -C "$repo" "$remote" main 2>&1)"; rc=$?
  expect_rc 3 "$rc" "remote $remote refused"
  expect_grep '^fix: ' "$out" "remote $remote refusal has a fix line"
done
for option in -f --force --force-with-lease --mirror --all --tags --delete -d --no-verify --repo=x --exec=x --receive-pack=x -o; do
  "$fp" -C "$repo" "$option" mine main >/dev/null 2>&1
  expect_rc 2 "$?" "option $option refused"
done
for refspec in +main :main ':refs/heads/x' -main; do
  "$fp" -C "$repo" mine "$refspec" >/dev/null 2>&1
  expect_rc 2 "$?" "refspec $refspec refused"
done
"$fp" -C "$repo" git@github.com:acme/widgets.git main >/dev/null 2>&1
expect_rc 2 "$?" "an address instead of a remote name is refused"
"$fp" -C "$repo" mine >/dev/null 2>&1
expect_rc 2 "$?" "a missing refspec is refused"
for args in "-C" "mine main -C"; do
  out="$("$fp" $args 2>&1)"; rc=$?
  expect_rc 2 "$rc" "'ctlhq-push $args' is refused"
  expect_grep '^ctlhq-push: -C needs a folder\.$' "$out" "'ctlhq-push $args' says -C needs a folder"
done
"$fp" -C "$repo" nosuch main >/dev/null 2>&1
expect_rc 4 "$?" "an unknown remote is refused"
"$fp" -C "$tmp" mine main >/dev/null 2>&1
expect_rc 4 "$?" "a folder that is not a work tree is refused"
for address in git@github.com:acme/x.git ssh://git@github.com/acme/x ssh://git@ssh.github.com:443/acme/x.git https://github.com/acme/x.git; do
  git -C "$repo" remote set-url mine "$address"
  out="$("$fp" -C "$repo" mine main 2>&1)"
  expect_grep "^pushing: mine main -> $address \\(owner acme from .*/\\.ctlhq/first-push\\.toml\\)\$" "$out" "address form $address allowed"
done
for address in https://github.com/acme/x/../../evil/y https://github.com.evil.example/acme/x git@github.com:acme/x.git/extra; do
  git -C "$repo" remote set-url mine "$address"
  "$fp" -C "$repo" mine main >/dev/null 2>&1
  expect_rc 3 "$?" "address $address refused"
done

# The owner setting: unset, malformed, unreadable, letter case, a trailing comment, and FIRST_PUSH_CONFIG.
git -C "$repo" remote set-url mine git@github.com:acme/widgets.git
owner_fix='^fix: Add the line github_owner = "<your GitHub account>" to ~/\.ctlhq/first-push\.toml, then run this command again\.$'
printf 'other = "x"\n' >"$settings"
out="$("$fp" -C "$repo" mine main 2>&1)"; rc=$?
expect_rc 3 "$rc" "no github_owner line is refused"
expect_grep '^ctlhq-push: no github_owner is set in ~/\.ctlhq/first-push\.toml' "$out" "unset owner names the file and the key"
expect_grep "$owner_fix" "$out" "unset owner has the fix line"
rm "$settings"
out="$("$fp" -C "$repo" mine main 2>&1)"; rc=$?
expect_rc 3 "$rc" "a missing settings file is refused"
expect_grep "$owner_fix" "$out" "missing settings file has the fix line"
for value in 'acme' '"ac/me"' '"-acme"' '""' '"acme" "x"' 'acme # x' '"acme" x # y'; do
  printf 'github_owner = %s\n' "$value" >"$settings"
  out="$("$fp" -C "$repo" mine main 2>&1)"; rc=$?
  expect_rc 3 "$rc" "github_owner = $value is refused"
  expect_grep 'github_owner in ~/\.ctlhq/first-push\.toml is not a GitHub account name in double quotes' "$out" "github_owner = $value is named as malformed"
done
printf '\377\376\n' >"$settings"
out="$("$fp" -C "$repo" mine main 2>&1)"; rc=$?
expect_rc 3 "$rc" "a settings file that is not UTF-8 is refused"
expect_grep "$owner_fix" "$out" "a settings file that is not UTF-8 has the fix line"
printf 'github_owner = "someone-else"\n' >"$settings"
"$fp" -C "$repo" mine main >/dev/null 2>&1
expect_rc 3 "$?" "another configured owner refuses the acme remote"
git -C "$repo" remote set-url mine git@github.com:someone-else/repo.git
out="$("$fp" -C "$repo" mine main 2>&1)"; rc=$?
expect_rc 1 "$rc" "the configured owner is the one allowed"
expect_grep '^pushing: mine main -> git@github.com:someone-else/repo.git \(owner someone-else from .*/\.ctlhq/first-push\.toml\)$' "$out" "the configured owner's address is pushed"
printf 'github_owner = "acme"\n' >"$settings"
printf 'github_owner = "someone-else"\n' >"$tmp/other.toml"
FIRST_PUSH_CONFIG="$tmp/other.toml" "$fp" -C "$repo" mine main >/dev/null 2>&1
expect_rc 3 "$?" "FIRST_PUSH_CONFIG cannot name another owner; the push stays refused"
git -C "$repo" remote set-url mine https://github.com/ACME/widgets.git
out="$("$fp" -C "$repo" mine main 2>&1)"; rc=$?
expect_rc 1 "$rc" "an address with the owner in other letter case is pushed"
printf 'github_owner = "Acme"  # my account\n' >"$settings"
git -C "$repo" remote set-url mine git@github.com:acme/widgets.git
out="$("$fp" -C "$repo" mine main 2>&1)"; rc=$?
expect_rc 1 "$rc" "an owner with a trailing comment and other letter case is accepted"
expect_grep '^pushing: mine main -> git@github.com:acme/widgets.git \(owner Acme from .*/\.ctlhq/first-push\.toml\)$' "$out" "the push line shows the owner as written in the settings file"
git -C "$repo" remote set-url mine git@github.com:acmex/widgets.git
"$fp" -C "$repo" mine main >/dev/null 2>&1
expect_rc 3 "$?" "letter case does not widen the owner to a longer name"
out="$("$fp" --help)"
expect_grep 'github_owner = "<your GitHub account>"' "$out" "--help names the setting"
expect_grep '~/\.ctlhq/first-push\.toml' "$out" "--help names the settings file"
expect_grep '^FIRST_PUSH_CONFIG is ignored' "$out" "--help says FIRST_PUSH_CONFIG is ignored"

# Owner letter case folds ASCII only: a long s in the address is a different owner.
printf 'github_owner = "kims"\n' >"$settings"
git -C "$repo" remote set-url mine "$(printf 'git@github.com:Kim\305\277/x.git')"
"$fp" -C "$repo" mine main >/dev/null 2>&1; expect_rc 3 "$?" "a long s in the address is not the owner's s"

# The message check at push. A stand-in for ssh hands each push to a bare repository in a scratch
# folder, so the address stays the allowed GitHub form and nothing leaves the machine.
printf 'github_owner = "acme"\n' >"$settings"
remotes="$tmp/remotes"
mkdir -p "$remotes/acme"
cat >"$tmp/stand-in-ssh" <<'SSH'
#!/bin/sh
while [ $# -gt 1 ]; do shift; done
cd "$STAND_IN_REMOTES" && exec sh -c "$1"
SSH
chmod +x "$tmp/stand-in-ssh"
export STAND_IN_REMOTES="$remotes" GIT_SSH_VARIANT=simple GIT_SSH_COMMAND="'$tmp/stand-in-ssh'"
bare="$remotes/acme/widgets.git"
expect_eq() { if [ "$1" = "$2" ]; then ok; else bad "$3 (expected '$1', got '$2')"; fi; }
expect_nogrep() { if printf '%s\n' "$2" | grep -Eq -- "$1"; then bad "$3 (a line matches: $1)"; else ok; fi; }
fresh() {
  rm -rf "$bare" "$tmp/msg"
  git init -q --bare -b main "$bare"
  git init -q -b main "$tmp/msg"
  m="$tmp/msg"
  git -C "$m" config user.name T
  git -C "$m" config user.email t@example.invalid
  git -C "$m" config commit.gpgsign false
  git -C "$m" remote add mine git@github.com:acme/widgets.git
  git -C "$m" commit -q --allow-empty -m "Add the first file"
}
refs() { git -C "$bare" for-each-ref --format='%(refname) %(objectname)'; }
note="Answer the round 2 findings"

fresh
git -C "$m" commit -q --allow-empty -m "Change the second file"
out="$("$fp" -C "$m" mine main 2>&1)"; expect_rc 0 $? "a clean range pushes"
expect_eq "refs/heads/main $(git -C "$m" rev-parse main)" "$(refs)" "the clean range moved the remote's main"
expect_grep '^pushed$' "$out" "a clean push prints pushed"

git -C "$m" commit -q --allow-empty -m "$note"
sha="$(git -C "$m" rev-parse main)"
before="$(refs)"
out="$("$fp" -C "$m" mine main 2>&1)"; expect_rc 6 $? "a flagged commit in the new range exits 6"
expect_eq "$before" "$(refs)" "a flagged commit moves no remote ref"
expect_grep "^${sha:0:12}: line 1: review$" "$out" "the refusal names the commit, the line and the rule"
expect_grep '^flagged: 1 of 1$' "$out" "the refusal counts the new commits"
expect_grep '^why: ' "$out" "the refusal has a why: line"
expect_grep "^fix: 1\\. .*git fetch mine '\\+refs/heads/\\*:refs/remotes/mine/\\*'" "$out" "the first step of the fix is the fetch"
expect_grep "^fix: 2\\. .*git reset --soft $(git -C "$m" rev-parse main~1), .*ctlhq-commit" "$out" "the second step names the exact commit, then ctlhq-commit"
expect_grep '^fix: .*BLOCKED\.md' "$out" "the refusal says what to do when the reset is refused"
expect_grep '^fix: .*ctlhq-message-check --help' "$out" "the refusal points to the ways out"
expect_nogrep '^pushing: ' "$out" "a refused push never says it is pushing"

fresh
git -C "$m" commit -q --allow-empty -m "$note"
git -C "$m" push -q mine main
git -C "$m" commit -q --allow-empty -m "Change the third file"
"$fp" -C "$m" mine main >/dev/null 2>&1; expect_rc 0 $? "a flagged commit the remote holds does not stop a push"
expect_eq "refs/heads/main $(git -C "$m" rev-parse main)" "$(refs)" "the push past a held flagged commit moved the remote's main"

fresh
git -C "$m" switch -q -c scratch
git -C "$m" commit -q --allow-empty -m "$note"
git -C "$m" switch -q main
git -C "$m" commit -q --allow-empty -m "Change the third file"
"$fp" -C "$m" mine main >/dev/null 2>&1; expect_rc 0 $? "a flagged commit on another local branch does not stop a clean push"
expect_eq "refs/heads/main $(git -C "$m" rev-parse main)" "$(refs)" "the clean branch reached the remote"
before="$(refs)"
"$fp" -C "$m" mine scratch >/dev/null 2>&1; expect_rc 6 $? "a flagged commit on a named source exits 6, with HEAD on a clean branch"
"$fp" -C "$m" mine main scratch >/dev/null 2>&1; expect_rc 6 $? "one flagged source among two refuses the whole push"
"$fp" -C "$m" mine "$(git -C "$m" rev-parse scratch):refs/heads/clean" >/dev/null 2>&1; expect_rc 6 $? "a flagged commit named by its hash exits 6"
expect_eq "$before" "$(refs)" "the refused sources moved no remote ref"

fresh
git -C "$m" commit -q --allow-empty -m "$note"
git -C "$m" tag -a v1 -m "First release"
git -C "$m" reset -q --hard HEAD~1
"$fp" -C "$m" mine v1 >/dev/null 2>&1; expect_rc 6 $? "a flagged commit behind an annotated tag exits 6"
expect_eq "" "$(refs)" "the refused tag moved no remote ref"
git -C "$m" tag m2 HEAD
"$fp" -C "$m" mine m2 >/dev/null 2>&1; expect_rc 0 $? "the branch rule leaves a tag name alone"

fresh
git -C "$m" switch -q -c m2-safety
out="$("$fp" -C "$m" mine m2-safety 2>&1)"; expect_rc 6 $? "branch m2-safety exits 6"
expect_eq "" "$(refs)" "branch m2-safety moves no remote ref"
expect_grep '^branch: m2-safety$' "$out" "the refusal names the branch"
expect_grep '^fix: rename the branch' "$out" "the branch refusal gives the check's fix"
for refspec in HEAD refs/heads/m2-safety HEAD:m2-safety main:m2-safety main:refs/heads/m2-safety; do
  "$fp" -C "$m" mine "$refspec" >/dev/null 2>&1; expect_rc 6 $? "refspec $refspec reaches branch m2-safety and exits 6"
done
expect_eq "" "$(refs)" "no refspec reached branch m2-safety"
"$fp" -C "$m" mine m2-safety:clean-name >/dev/null 2>&1; expect_rc 0 $? "a local name that stays local does not stop the push"
expect_eq "refs/heads/clean-name $(git -C "$m" rev-parse m2-safety)" "$(refs)" "the remote holds only the clean name"

fresh
printf 'zebrafinch\n' >"$HOME/.ctlhq/message-words.txt"
git -C "$m" switch -q -c zebrafinch-work
out="$("$fp" -C "$m" mine zebrafinch-work 2>&1)"; expect_rc 6 $? "a listed word in a branch name exits 6"
expect_nogrep 'zebrafinch' "$out" "the refusal never prints a listed word in a branch name"
git -C "$m" switch -q main
git -C "$m" commit -q --allow-empty -m "Tell zebrafinch about it"
out="$("$fp" -C "$m" mine main 2>&1)"; expect_rc 6 $? "a listed word in a commit message exits 6"
expect_grep ': line 1: extra-word$' "$out" "the refusal names the extra-word rule"
expect_nogrep 'zebrafinch' "$out" "the refusal never prints a listed word in a message"
rm "$HOME/.ctlhq/message-words.txt"

fresh
for refspec in nosuch 'refs/heads/*:refs/heads/*' 'tag v1'; do
  out="$("$fp" -C "$m" mine $refspec 2>&1)"; expect_rc 6 $? "source '$refspec' that names no commit exits 6"
  expect_grep 'did not run' "$out" "source '$refspec': the line says the check did not run"
done
expect_eq "" "$(refs)" "a source that names no commit moves no remote ref"

fresh
checkout="$tmp/checkout"
mkdir -p "$checkout"
cp "$fp" "$checkout/ctlhq-push"
out="$("$checkout/ctlhq-push" -C "$m" mine main 2>&1)"; expect_rc 6 $? "a missing check exits 6"
expect_grep 'did not run' "$out" "a missing check: the line says the check did not run"
stub() { printf '#!/usr/bin/env python3\nimport sys\n%s\n' "$1" >"$checkout/ctlhq-message-check"; chmod +x "$checkout/ctlhq-message-check"; }
stub "sys.exit(2)"
out="$("$checkout/ctlhq-push" -C "$m" mine main 2>&1)"; expect_rc 6 $? "a check that exits 2 gives exit 6"
expect_grep 'did not run \(exit 2\)' "$out" "exit 2: the line says the check did not run"
stub "sys.exit(1)"
out="$("$checkout/ctlhq-push" -C "$m" mine main 2>&1)"; expect_rc 6 $? "a check that exits 1 with no finding gives exit 6"
expect_grep 'did not run \(exit 1\)' "$out" "exit 1 with no finding: the line says the check did not run"
stub "sys.exit(0"
"$checkout/ctlhq-push" -C "$m" mine main >/dev/null 2>&1; expect_rc 6 $? "a check with a syntax error gives exit 6"
expect_eq "" "$(refs)" "a check that did not run moves no remote ref"
stub "sys.exit(0)"
"$checkout/ctlhq-push" -C "$m" mine main >/dev/null 2>&1; expect_rc 0 $? "a checkout's own ctlhq-push uses that checkout's check"
expect_grep '^  3\. .*ctlhq-message-check' "$("$fp" --help)" "--help names the check as a step"
expect_grep 'Tag names, tag messages and other ref names are not read' "$("$fp" --help)" "--help says what the check leaves out"
expect_grep '; 6 the$' "$("$fp" --help)" "--help lists exit 6"

# Each refusal prints a fix that works. These follow the printed step, then push again.
next_commit() { git -C "$m" commit -q --allow-empty -m "Change the next file"; }
printed_base() { printf '%s\n' "$1" | sed -n 's/.*git reset --soft \([0-9a-f]\{40\}\).*/\1/p'; }
fetch_all() { git -C "$m" fetch -q mine '+refs/heads/*:refs/remotes/mine/*'; }

fresh
git -C "$m" commit -q --allow-empty -m "$note"
git -C "$m" push -q mine main
git -C "$m" remote add public git@github.com:acme/public.git
git init -q --bare -b main "$remotes/acme/public.git"
out="$("$fp" -C "$m" public main 2>&1)"; expect_rc 6 $? "a flagged commit another remote holds exits 6 on a fresh remote"
expect_eq "" "$(git -C "$remotes/acme/public.git" for-each-ref)" "the fresh remote gets no ref"
expect_grep '^fix: 2\. .*rewritten by the operator' "$out" "a commit another remote holds goes to the operator"
expect_nogrep 'git reset' "$out" "a commit another remote holds gets no reset line"
rm -rf "$remotes/acme/public.git"

fresh
git -C "$m" commit -q --allow-empty -m "$note"
git -C "$m" push -q mine main
git -C "$m" update-ref -d refs/remotes/mine/main
next_commit
"$fp" -C "$m" mine main >/dev/null 2>&1; expect_rc 6 $? "a held commit with its tracking ref gone exits 6"
fetch_all
"$fp" -C "$m" mine main >/dev/null 2>&1; expect_rc 0 $? "the printed fetch clears a missing tracking ref"

fresh
git -C "$m" config --unset-all remote.mine.fetch
git -C "$m" commit -q --allow-empty -m "$note"
git -C "$m" push -q mine main
next_commit
"$fp" -C "$m" mine main >/dev/null 2>&1; expect_rc 6 $? "a held commit with no fetch rule exits 6"
fetch_all
"$fp" -C "$m" mine main >/dev/null 2>&1; expect_rc 0 $? "the printed fetch clears a remote with no fetch rule"

fresh
git -C "$m" commit -q --allow-empty -m "Add the second file"
keep="$(git -C "$m" rev-parse HEAD)"
git -C "$m" commit -q --allow-empty -m "$note"
next_commit
out="$("$fp" -C "$m" mine main 2>&1)"; expect_rc 6 $? "a flagged commit between clean ones exits 6"
expect_eq "$keep" "$(printed_base "$out")" "the fix names the parent of the oldest flagged commit"
git -C "$m" reset -q --soft "$(printed_base "$out")"
next_commit
"$fp" -C "$m" mine main >/dev/null 2>&1; expect_rc 0 $? "the printed reset leaves a push the remote takes"

fresh
base="$(git -C "$m" rev-parse HEAD)"
git -C "$m" switch -q -c side
git -C "$m" commit -q --allow-empty -m "$note"
git -C "$m" switch -q main
next_commit
git -C "$m" push -q mine main
git -C "$m" merge -q --no-ff -m "Merge the side work" side
out="$("$fp" -C "$m" mine main 2>&1)"; expect_rc 6 $? "a flagged side branch under a merge exits 6"
expect_eq "$(git -C "$m" rev-parse mine/main)" "$(printed_base "$out")" "with a merge, the fix names the remote branch's commit"
git -C "$m" reset -q --soft "$(printed_base "$out")"
next_commit
"$fp" -C "$m" mine main >/dev/null 2>&1; expect_rc 0 $? "the printed reset past a merge leaves a push the remote takes"

fresh
git -C "$m" switch -q -c side
git -C "$m" commit -q --allow-empty -m "$note"
git -C "$m" switch -q main
next_commit
git -C "$m" switch -q -c fresh-work
git -C "$m" merge -q --no-ff -m "Merge the side work" side
git -C "$m" push -q mine main:refs/heads/held
out="$("$fp" -C "$m" mine fresh-work 2>&1)"; expect_rc 6 $? "a merge on a new branch with no one commit under it exits 6"
expect_grep '^fix: 2\. .*rewritten by the operator' "$out" "a merge with no one commit under it goes to the operator"
expect_nogrep 'git reset' "$out" "a merge with no one commit under it gets no reset line"

fresh
git -C "$m" update-ref -d HEAD
git -C "$m" commit -q --allow-empty -m "$note"
out="$("$fp" -C "$m" mine main 2>&1)"; expect_rc 6 $? "a flagged first commit exits 6"
expect_grep '^fix: 2\. .*git update-ref -d HEAD, .*ctlhq-commit' "$out" "a flagged first commit gets the fix for a commit with no parent"
expect_nogrep 'git reset' "$out" "a flagged first commit gets no reset line"
git -C "$m" update-ref -d HEAD
next_commit
"$fp" -C "$m" mine main >/dev/null 2>&1; expect_rc 0 $? "the printed fix for a first commit leaves a push the remote takes"

fresh
git -C "$m" switch -q -c scratch
git -C "$m" commit -q --allow-empty -m "$note"
git -C "$m" switch -q main
out="$("$fp" -C "$m" mine scratch 2>&1)"; expect_rc 6 $? "a flagged branch that is not checked out exits 6"
expect_grep '^fix: 2\. .*git switch scratch, then .*git reset --soft' "$out" "the fix switches to that branch before the reset"
printf 'zebrafinch\n' >"$HOME/.ctlhq/message-words.txt"
git -C "$m" branch zebrafinch-work scratch
out="$("$fp" -C "$m" mine zebrafinch-work:refs/heads/clean 2>&1)"; expect_rc 6 $? "a flagged branch with a listed name exits 6"
expect_grep '^fix: 2\. .*switch to this source branch, then ' "$out" "the fix still says to switch"
expect_nogrep 'zebrafinch' "$out" "the fix never prints a listed word in a local branch name"
rm "$HOME/.ctlhq/message-words.txt"
out="$("$fp" -C "$m" mine "$(git -C "$m" rev-parse scratch):refs/heads/clean" 2>&1)"; expect_rc 6 $? "a flagged hash exits 6"
expect_grep '^fix: 2\. .*rewritten by the operator' "$out" "a hash has no branch to reset, so it goes to the operator"

fresh
git -C "$m" push -q mine main
git -C "$m" switch -q -c away
git -C "$m" commit -q --allow-empty -m "Change the remote branch"
git -C "$m" push -q mine away:main
git -C "$m" switch -q main
git -C "$m" commit -q --allow-empty -m "$note"
out="$("$fp" -C "$m" mine main 2>&1)"; expect_rc 6 $? "a flagged commit behind the remote branch exits 6"
expect_grep '^fix: 2\. .*rewritten by the operator' "$out" "a branch the remote moved past goes to the operator"
expect_nogrep 'git reset' "$out" "a branch the remote moved past gets no reset line"

fresh
git -C "$m" tag v3
"$fp" -C "$m" mine v3:m2 >/dev/null 2>&1; expect_rc 0 $? "a tag source with a bare target is a tag, as in Git"
expect_eq "refs/tags/m2 $(git -C "$m" rev-parse v3)" "$(refs)" "the bare target became a tag"

fresh
git -C "$m" switch -q -c m2-safety
git -C "$m" push -q mine m2-safety
out="$("$fp" -C "$m" mine m2-safety 2>&1)"; expect_rc 6 $? "a branch name the remote already holds exits 6"
expect_grep '^fix: mine already holds this name.*operator' "$out" "the refusal says the old name stays with the operator"

fresh
ln -s "$tmp/nowhere" "$HOME/.ctlhq/message-words.txt"
git -C "$m" switch -q -c second
out="$("$fp" -C "$m" mine main second 2>&1)"; expect_rc 6 $? "a broken word list exits 6"
expect_eq 1 "$(printf '%s\n' "$out" | grep -c 'did not run')" "a broken word list prints one refusal"
rm "$HOME/.ctlhq/message-words.txt"

fresh
git -C "$m" update-ref -d HEAD
git -C "$m" commit -q --allow-empty -m "$note"
git -C "$m" switch -q --detach
out="$("$fp" -C "$m" mine HEAD:refs/heads/clean 2>&1)"; expect_rc 6 $? "a flagged first commit on a detached HEAD exits 6"
expect_grep '^fix: 2\. .*rewritten by the operator' "$out" "a flagged first commit on a detached HEAD goes to the operator"
expect_nogrep 'update-ref' "$out" "a detached HEAD never gets the line that would remove .git/HEAD"

fresh
git -C "$m" commit -q --allow-empty -m "$note"
git -C "$m" push -q mine main
shallow="$tmp/shallow"
rm -rf "$shallow"
git clone -q --depth 1 -o mine "file://$bare" "$shallow"
git -C "$shallow" remote set-url mine git@github.com:acme/widgets.git
git -C "$shallow" symbolic-ref -d refs/remotes/mine/HEAD 2>/dev/null
git -C "$shallow" update-ref -d refs/remotes/mine/main
out="$("$fp" -C "$shallow" mine main 2>&1)"; expect_rc 6 $? "a flagged commit at a shallow clone's edge exits 6"
expect_grep '^fix: 2\. .*rewritten by the operator' "$out" "a commit at a shallow clone's edge goes to the operator"
expect_nogrep 'update-ref' "$out" "a shallow clone never gets the line for a first commit"

echo "$pass checks passed"
[ "$fail" -eq 0 ]
