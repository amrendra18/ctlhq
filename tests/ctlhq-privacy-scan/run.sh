#!/usr/bin/env bash
# tests/ctlhq-privacy-scan/run.sh: checks for skills/prepare-public-repo/bin/ctlhq-privacy-scan through
# bin/ctlhq-privacy-scan. Prints "N checks passed" and exits 1 when any check fails. Writes only to a
# temp folder.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
ts="$root/bin/ctlhq-privacy-scan"
pass=0
fail=0
ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL: $1"; }
expect_rc() { if [ "$1" -eq "$2" ]; then ok; else bad "$3 (expected exit $1, got $2)"; fi; }
expect_eq() { if [ "$1" = "$2" ]; then ok; else bad "$3 (expected '$1', got '$2')"; fi; }
expect_fgrep() { if printf '%s\n' "$2" | grep -Fqx -- "$1"; then ok; else bad "$3 (no line is: $1)"; fi; }
expect_has() { if printf '%s\n' "$2" | grep -Fq -- "$1"; then ok; else bad "$3 (no line holds: $1)"; fi; }
expect_nogrep() { if printf '%s\n' "$2" | grep -Fqi -- "$1"; then bad "$3 (a line holds: $1)"; else ok; fi; }

tmp="$(mktemp -d "${TMPDIR:-/tmp}/privacy-scan-test.XXXXXX")"
tmp="$(cd "$tmp" && pwd)" || exit 1
[ -n "$tmp" ] && [ -d "$tmp" ] || { echo "FAIL: no temp folder"; exit 1; }
trap 'rm -rf "$tmp"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 HOME="$tmp/home"
unset FIRST_PUSH_CONFIG
mkdir -p "$HOME"
run() { out="$("$ts" "$@" 2>"$tmp/err")"; rc=$?; err="$(cat "$tmp/err")"; }

# The planted private words are built from pieces so this file never holds them whole.
one="quok""kalantern"
two="mar""mosetwig"
upper_one="$(printf '%s' "$one" | tr '[:lower:]' '[:upper:]')"
repo="$tmp/repo"
mkdir -p "$repo/docs" "$repo/.local/first-commit" "$repo/ignored"
git -C "$repo" init -q
printf '.local/\nignored/\n' >"$repo/.gitignore"
printf '# a comment line\n\n  %s  \n%s\n' "$one" "$two" >"$repo/.local/first-commit/private-values.txt"
printf 'clean\nthe %s here\n' "$upper_one" >"$repo/docs/a.md"
printf 'clean\n' >"$repo/docs/$one-notes.md"
printf 'x = "%s" + "%s"\nan %s\n%s\n' "${two:0:4}" "${two:4}" "${one:0:5}" "${one:5}" >"$repo/docs/b.py"
printf 'and %s again\n' "$two" >"$repo/docs/untracked.md"
printf '%s\n' "$one" >"$repo/ignored/c.md"
printf '\000\001 %s\n' "$one" >"$repo/docs/d.bin"
printf 'gone\n' >"$repo/docs/deleted.md"
git -C "$repo" add .gitignore docs/a.md "docs/$one-notes.md" docs/b.py docs/d.bin docs/deleted.md
rm "$repo/docs/deleted.md"

# 1. --help and usage errors.
run --help; expect_rc 0 "$rc" "--help exits 0"
expect_eq "ctlhq-privacy-scan:" "$(printf '%s\n' "$out" | head -1 | cut -d' ' -f1)" "--help first line starts 'ctlhq-privacy-scan:'"
run --bogus; expect_rc 2 "$rc" "an unknown option exits 2"
run --words; expect_rc 2 "$rc" "--words without a value exits 2"
run --root "$tmp"; expect_rc 3 "$rc" "a folder outside Git exits 3"
run --root "$repo" --words "$tmp/none.txt"; expect_rc 2 "$rc" "a missing word list exits 2"
printf '# only a comment\n\n' >"$tmp/empty.txt"
run --root "$repo" --words "$tmp/empty.txt"; expect_rc 2 "$rc" "a word list with no private word exits 2"

# 2. Plain scan with the default word list: tracked and untracked files, paths masked, word numbers
#    skip comment and blank lines, ignored and binary files are not read, a deleted file is skipped.
run --root "$repo"
expect_rc 1 "$rc" "hits exit 1"
expect_eq "docs/a.md:2: private word 1
docs/<private word 1>-notes.md: private word 1 in path
docs/untracked.md:1: private word 2" "$out" "exactly the path hit, the content hit in any case, and the untracked hit"
expect_eq "privacy-scan: 5 files, 3 hits, 1 binary files skipped, 0 unreadable files" "$err" "the summary counts files, hits, and binary files"

# 3. Joined mode adds the split forms, with the line where each starts.
run --root "$repo" --joined
expect_rc 1 "$rc" "joined hits exit 1"
expect_fgrep "docs/b.py:1: private word 2 joined" "$out" "pieces joined by quotes and + are found"
expect_fgrep "docs/b.py:2: private word 1 joined" "$out" "pieces across a line break are found on the first line"
expect_eq 5 "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" "joined mode adds only the two split forms"

# 4. No output ever holds a private word, in any letter case.
for t in "$one" "$two"; do
	expect_nogrep "$t" "$out$err" "the private word is never printed"
done

# 5. A clean tree exits 0, and --words names another list.
printf 'zzzzunused\n' >"$tmp/other.txt"
run --root "$repo" --words "$tmp/other.txt" --joined
expect_rc 0 "$rc" "no hits exit 0"
expect_eq "" "$out" "no hits print nothing on stdout"

# 6. Text and private words are matched after NFC and case folding, as ctlhq-first-push matches.
#    Private word 3 holds a sharp s, written "SS" in the text. Private word 4 is NFC, written
#    in NFD in the text.
sharp_s="$(printf '\303\237')"
three="gro${sharp_s}""zank"
four="pl$(printf '\303\251')""vix"
upper_two="$(printf '%s' "$two" | tr '[:lower:]' '[:upper:]')"
repo2="$tmp/repo2"
mkdir -p "$repo2/docs" "$repo2/.local/first-commit" "$tmp/home2/.ctlhq"
git -C "$repo2" init -q
printf '.local/\n' >"$repo2/.gitignore"
printf '%s\n%s\n%s\n%s\n' "$one" "$two" "$three" "$four" >"$repo2/.local/first-commit/private-values.txt"
printf 'GROSSZANK\nPLE\314\201VIX\n%s\n' "$upper_two" >"$repo2/docs/n.md"
printf 'clean\n' >"$repo2/docs/GROSSZANK-x.md"
run --root "$repo2"
expect_rc 1 "$rc" "normalized hits exit 1"
expect_fgrep "docs/n.md:1: private word 3" "$out" "a folded sharp s matches"
expect_fgrep "docs/n.md:2: private word 4" "$out" "NFD text matches an NFC private word"
expect_fgrep "docs/<private word 3>-x.md: private word 3 in path" "$out" "a path is masked with the word number when its case folds differently"

# 7. The owner's GitHub address and LICENSE are not reported; public_terms drops a private word
#    and keeps the other word numbers.
printf 'clone https://github.com/%s/x and git@github.com:%s/y.git\n' "$upper_one" "$one" >"$repo2/docs/j.md"
printf 'https://github.com/%sextra/z\nthe %s\n' "$one" "$one" >>"$repo2/docs/j.md"
printf 'clean\n' >"$repo2/docs/github.com:$one.md"
printf 'a %s inside LICENSE\n' "$one" >"$repo2/LICENSE"
run --root "$repo2"
expect_fgrep "docs/j.md:1: private word 1" "$out" "without a first-push.toml the owner's address is reported"
expect_fgrep "docs/github.com:<private word 1>.md: private word 1 in path" "$out" "without a first-push.toml the owner's address in a path is reported"
printf 'github_owner = "%s"  # the account\n' "$one" >"$tmp/home2/.ctlhq/first-push.toml"
HOME="$tmp/home2" run --root "$repo2"
expect_eq "docs/<private word 3>-x.md: private word 3 in path
docs/j.md:2: private word 1
docs/j.md:3: private word 1
docs/n.md:1: private word 3
docs/n.md:2: private word 4
docs/n.md:3: private word 2" "$out" "the owner's address in any case or form, and LICENSE, are skipped; a longer account name is reported"
printf 'public_terms = ["%s"]\n' "$upper_two" >>"$tmp/home2/.ctlhq/first-push.toml"
HOME="$tmp/home2" run --root "$repo2"
expect_rc 1 "$rc" "the other private words still exit 1"
expect_nogrep "private word 2" "$out" "a public private word is not reported"
expect_fgrep "docs/n.md:2: private word 4" "$out" "the other word numbers stay the same"
printf 'public_terms = ["%s"]\n' "$four" >"$tmp/public.toml"
HOME="$tmp/home2" FIRST_PUSH_CONFIG="$tmp/public.toml" run --root "$repo2"
expect_nogrep "private word 4" "$out" "FIRST_PUSH_CONFIG names the public_terms file"
expect_fgrep "docs/n.md:3: private word 2" "$out" "only the public_terms file that FIRST_PUSH_CONFIG names counts"
printf 'github_owner = "%s"\n' "$one" >"$tmp/home2/.ctlhq/first-push.toml"

# 8. Joined mode treats "_" and string-piece joins such as "." as separators.
printf 'x = %s_%s\ny = %s . %s\n' "${one:0:4}" "${one:4}" "'${two:0:3}'" "'${two:3}'" >"$repo2/docs/k.py"
HOME="$tmp/home2" run --root "$repo2" --joined
expect_fgrep "docs/k.py:1: private word 1 joined" "$out" "pieces joined by _ are found"
expect_fgrep "docs/k.py:2: private word 2 joined" "$out" "pieces joined by . are found"

# 9. An unreadable file is named with its path masked, exits 4, and the scan goes on.
printf '%s\n' "$one" >"$repo2/docs/$one-locked.md"
chmod 000 "$repo2/docs/$one-locked.md"
HOME="$tmp/home2" run --root "$repo2"
chmod 644 "$repo2/docs/$one-locked.md"
expect_rc 4 "$rc" "an unreadable file exits 4"
expect_fgrep "ctlhq-privacy-scan: docs/<private word 1>-locked.md: cannot be read (Permission denied)" "$err" "the unreadable file is named with its path masked"
expect_fgrep "docs/n.md:1: private word 3" "$out" "the other files are still scanned"
expect_fgrep "privacy-scan: 6 files, 7 hits, 0 binary files skipped, 1 unreadable files" "$err" "the summary counts the unreadable file"

# 10. No error message holds a private word, and none names a path the caller typed.
mkdir -p "$tmp/$one-notgit"
run --root "$tmp/$one-notgit"; expect_rc 3 "$rc" "a folder outside Git exits 3"
expect_nogrep "$one" "$err" "the not-a-work-tree error holds no private word"
expect_nogrep "$tmp" "$err" "the not-a-work-tree error names no path"
run --root "$repo2" --words "$tmp/$one-missing.txt"; expect_rc 2 "$rc" "a missing --words file exits 2"
expect_nogrep "$one" "$err" "the missing-list error holds no private word"
printf '\377%s\n' "$one" >"$tmp/$one-bad.txt"
run --root "$repo2" --words "$tmp/$one-bad.txt"; expect_rc 2 "$rc" "a word list that is not UTF-8 exits 2"
expect_nogrep "$one" "$err" "the not-UTF-8 error holds no private word"
printf '%s\n' "$one" >"$tmp/$one-locked.txt"
chmod 000 "$tmp/$one-locked.txt"
run --root "$repo2" --words "$tmp/$one-locked.txt"; rc_locked=$rc; err_locked="$err"
chmod 644 "$tmp/$one-locked.txt"
expect_rc 2 "$rc_locked" "an unreadable word list exits 2"
expect_nogrep "$one" "$err_locked" "the unreadable-list error holds no private word"
mkdir -p "$tmp/$one-home/.ctlhq"
printf 'github_owner = %s\n' "$one" >"$tmp/$one-home/.ctlhq/first-push.toml"
HOME="$tmp/$one-home" run --root "$repo2"; expect_rc 2 "$rc" "an unreadable github_owner line exits 2"
expect_fgrep "ctlhq-privacy-scan: github_owner in ~/.ctlhq/first-push.toml is not a GitHub account name in double quotes" "$err" "the settings path is shown with ~"
expect_nogrep "$one" "$err" "the github_owner error holds no private word"
printf 'public_terms = [oops]\n' >"$tmp/$one-cfg.toml"
FIRST_PUSH_CONFIG="$tmp/$one-cfg.toml" run --root "$repo2"; expect_rc 2 "$rc" "an unreadable public_terms line exits 2"
expect_has "<private word 1>-cfg.toml" "$err" "the public_terms error masks the private word in its path"
expect_nogrep "$one" "$err" "the public_terms error holds no private word"

# 11. A private word split by a separator in a path is found with --joined and masked in every printed path.
split_one="${one:0:4}_${one:4}"
repo3="$tmp/repo3"
mkdir -p "$repo3/docs"
git -C "$repo3" init -q
printf '%s\n' "$one" >"$tmp/words3.txt"
printf 'clean\n' >"$repo3/docs/$split_one-p.md"
printf 'the %s\n' "$one" >"$repo3/docs/$split_one-q.md"
run --root "$repo3" --words "$tmp/words3.txt" --joined
expect_rc 1 "$rc" "a joined private word in a path exits 1"
expect_eq "docs/<private word 1>-p.md: private word 1 joined in path
docs/<private word 1>-q.md: private word 1 joined in path
docs/<private word 1>-q.md:1: private word 1" "$out" "the joined path hit is reported and the path is masked"
run --root "$repo3" --words "$tmp/words3.txt"
expect_eq "docs/<private word 1>-q.md:1: private word 1" "$out" "without --joined the path is still masked"
expect_nogrep "$split_one" "$out$err" "the split form is never printed"

echo "$pass checks passed"
[ "$fail" -eq 0 ] || exit 1
