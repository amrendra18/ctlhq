#!/usr/bin/env bash
# tests/ctlhq-push/run.sh: checks for bin/ctlhq-push in a scratch git repository. No
# network: allowed addresses are pushed with GIT_SSH_COMMAND=false, so ssh fails at once.
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
printf '# ctlhq-first-push settings\npublic_terms = ["Acme Corp"]\ngithub_owner = "acme"\n' >"$settings"
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
printf 'public_terms = ["Acme Corp"]\n' >"$settings"
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
echo "$pass checks passed"
[ "$fail" -eq 0 ]
