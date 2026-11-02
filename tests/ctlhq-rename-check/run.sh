#!/usr/bin/env bash
set -u
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
rc_tool="$root/bin/ctlhq-rename-check"
pass=0
fail=0
ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL: $1"; }
expect_rc() { if [ "$1" -eq "$2" ]; then ok; else bad "$3 (expected exit $1, got $2)"; fi; }
expect_eq() { if [ "$1" = "$2" ]; then ok; else bad "$3 (expected '$1', got '$2')"; fi; }
expect_grep() { if printf '%s\n' "$2" | grep -Eq -- "$1"; then ok; else bad "$3 (no line matches: $1)"; fi; }
count() { printf '%s\n' "$2" | grep -Ec -- "$1"; }

tmp="$(mktemp -d "${TMPDIR:-/tmp}/ctlhq-rename-check-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

out="$("$rc_tool" --help 2>&1)"; expect_rc 0 $? "--help exits 0"
expect_grep '^ctlhq-rename-check: ' "$(printf '%s\n' "$out" | head -1)" "--help first line is 'ctlhq-rename-check: ...'"
expect_grep '--allow FILE' "$out" "--help documents --allow"
"$rc_tool" >/dev/null 2>&1; expect_rc 2 $? "no name exits 2"
"$rc_tool" --bogus old >/dev/null 2>&1; expect_rc 2 $? "an unknown option exits 2"
"$rc_tool" ' - ' >/dev/null 2>&1; expect_rc 2 $? "a name with no letters or digits exits 2"
mkdir -p "$tmp/plain"
"$rc_tool" --root "$tmp/plain" old >/dev/null 2>&1; expect_rc 2 $? "a folder outside a Git repository exits 2"
(cd "$tmp/plain" && "$rc_tool" old >/dev/null 2>&1); expect_rc 2 $? "a working folder outside a Git repository exits 2"

fx="$tmp/fx"
mkdir -p "$fx/docs" "$fx/src"
git -C "$fx" init -q
printf '# Notes\n\nBright Loom keeps your zebra notes.\n' >"$fx/README.md"
printf 'How to start.\n' >"$fx/docs/bright-loom.md"
printf '[paths]\nbright_loom_home = "/opt/app"\n' >"$fx/config.toml"
printf 'const width = 2;\n// brightloom used tabs here\n' >"$fx/src/app.js"
printf 'import os\n\nif os.environ.get("BRIGHT_LOOM_HOME"):\n    pass\n' >"$fx/src/compat.py"
printf 'MIT License\n\nCopyright the Bright-Loom authors\n' >"$fx/LICENSE"
printf 'A bright day at the loom.\n' >"$fx/src/clean.txt"
git -C "$fx" add -A
out="$("$rc_tool" --root "$fx" bright-loom 2>&1)"; rc=$?
expect_rc 1 "$rc" "6 planted forms exit 1"
expect_eq 6 "$(count '^[^ ]+:[0-9]+: (content|path): ' "$out")" "6 planted forms give 6 hit lines"
expect_grep '^README\.md:3: content: Bright Loom$' "$out" "content hit"
expect_grep '^docs/bright-loom\.md:0: path: bright-loom$' "$out" "file name hit"
expect_grep '^config\.toml:2: content: bright_loom$' "$out" "config key hit"
expect_grep '^src/app\.js:2: content: brightloom$' "$out" "comment hit"
expect_grep '^src/compat\.py:3: content: BRIGHT_LOOM$' "$out" "compatibility branch hit"
expect_grep '^LICENSE:3: content: Bright-Loom$' "$out" "LICENSE line hit"
expect_eq "6 hits, 0 allowed" "$(printf '%s\n' "$out" | tail -1)" "summary line counts"
expect_eq 0 "$(count 'clean\.txt|zebra' "$out")" "the two halves alone and the rest of a line stay out"
out="$(cd "$fx/src" && "$rc_tool" BRIGHT-LOOM 2>&1)"; rc=$?
expect_rc 1 "$rc" "the working folder's repository is searched, in any case"
expect_eq "6 hits, 0 allowed" "$(printf '%s\n' "$out" | tail -1)" "the whole repository is searched from a subfolder"
out="$("$rc_tool" --root "$fx" bright-loom zebra 2>&1)"
expect_eq "7 hits, 0 allowed" "$(printf '%s\n' "$out" | tail -1)" "each name is searched"

cl="$tmp/clean"
mkdir -p "$cl"
git -C "$cl" init -q
printf 'A bright day at the loom.\n' >"$cl/README.md"
git -C "$cl" add -A
out="$("$rc_tool" --root "$cl" bright-loom 2>&1)"; rc=$?
expect_rc 0 "$rc" "a clean tree exits 0"
expect_eq "0 hits, 0 allowed" "$out" "a clean tree prints only the summary"

printf '# Kept on purpose.\nLICENSE  the copyright line names the old project\n' >"$tmp/allow.txt"
out="$("$rc_tool" --root "$fx" --allow "$tmp/allow.txt" bright-loom 2>&1)"; rc=$?
expect_rc 1 "$rc" "one allowed path leaves 5 hits and exit 1"
expect_grep '^LICENSE:3: content: Bright-Loom \(allowed: the copyright line names the old project\)$' "$out" "the allowed hit is listed with its reason"
expect_eq "5 hits, 1 allowed" "$(printf '%s\n' "$out" | tail -1)" "the allowed hit does not count"
printf 'LICENSE\tthe copyright line\nsrc/  old layout kept for one release\nREADME.md  history\nconfig.toml  old key read once\ndocs/bright-loom.md  old link target\n' >"$tmp/allow-all.txt"
out="$("$rc_tool" --root "$fx" --allow "$tmp/allow-all.txt" bright-loom 2>&1)"; rc=$?
expect_rc 0 "$rc" "every hit allowed exits 0"
expect_eq "0 hits, 6 allowed" "$(printf '%s\n' "$out" | tail -1)" "a folder entry covers the files under it"
printf 'LICENSE\n' >"$tmp/noreason.txt"
"$rc_tool" --root "$fx" --allow "$tmp/noreason.txt" bright-loom >/dev/null 2>&1; expect_rc 2 $? "an allow line with no reason exits 2"
"$rc_tool" --root "$fx" --allow "$tmp/nosuch.txt" bright-loom >/dev/null 2>&1; expect_rc 2 $? "a missing allow file exits 2"

un="$tmp/untracked"
mkdir -p "$un"
git -C "$un" init -q
printf 'ignored.txt\n' >"$un/.gitignore"
printf 'A bright day at the loom.\n' >"$un/README.md"
git -C "$un" add -A
printf 'bright-loom\n' >"$un/ignored.txt"
out="$("$rc_tool" --root "$un" bright-loom 2>&1)"; rc=$?
expect_rc 0 "$rc" "a name only in an ignored file exits 0"
expect_eq "0 hits, 0 allowed" "$out" "an ignored file is not read"
printf 'Bright Loom notes.\n' >"$un/notes.txt"
out="$("$rc_tool" --root "$un" bright-loom 2>&1)"; rc=$?
expect_rc 1 "$rc" "a name only in an untracked file exits 1"
expect_grep '^notes\.txt:1: content: Bright Loom$' "$out" "an untracked file that Git does not ignore is read"
expect_eq "1 hits, 0 allowed" "$(printf '%s\n' "$out" | tail -1)" "the untracked file gives 1 hit"

ln="$tmp/links"
mkdir -p "$ln/docs"
git -C "$ln" init -q
printf 'Bright Loom keeps your notes.\n' >"$ln/docs/notes.md"
ln -s docs/notes.md "$ln/alias.md"
ln -s bright-loom/start.md "$ln/start.md"
git -C "$ln" add -A
out="$("$rc_tool" --root "$ln" bright-loom 2>&1)"
expect_grep '^start\.md:1: content: bright-loom$' "$out" "a link's target text is searched"
expect_eq 0 "$(count '^alias\.md:' "$out")" "a link is not followed into the file it points to"
expect_eq "2 hits, 0 allowed" "$(printf '%s\n' "$out" | tail -1)" "the linked file counts once, under its own path"

s4="$root/tests/scenarios/s4-incomplete-change"
"$s4/setup" "$tmp/s4-start" >/dev/null; expect_rc 0 $? "s4 setup builds the start state"
out="$("$s4/grade" "$tmp/s4-start" 2>&1)"; rc=$?
expect_rc 1 "$rc" "the s4 grader fails the start state"
expect_grep '^6 hits, 0 allowed$' "$out" "the s4 start state has 6 hits"
"$s4/setup" --renamed "$tmp/s4-renamed" >/dev/null; expect_rc 0 $? "s4 setup builds the renamed state"
out="$("$s4/grade" "$tmp/s4-renamed" 2>&1)"; rc=$?
expect_rc 0 "$rc" "the s4 grader passes a finished rename"
expect_eq "0 hits, 0 allowed" "$out" "a finished rename prints only the summary"
git -C "$tmp/s4-renamed" rm -rq .
out="$("$s4/grade" "$tmp/s4-renamed" 2>&1)"; rc=$?
expect_rc 1 "$rc" "the s4 grader fails a tree with neither name"
expect_grep '^the new name tarnby appears nowhere$' "$out" "the grader names the missing new name"

echo "$pass checks passed"
if [ "$fail" -gt 0 ]; then
	echo "$fail checks failed"
	exit 1
fi
