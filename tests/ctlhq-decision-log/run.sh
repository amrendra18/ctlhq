#!/usr/bin/env bash
# tests/ctlhq-decision-log/run.sh: checks for bin/ctlhq-decision-log (skills/show-me-your-work/bin/ctlhq-decision-log
# wrapping skills/show-me-your-work/scripts/log.sh). Prints "N checks passed" and exits 1 when
# any check fails. Writes only to a temp folder.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
dl="$root/bin/ctlhq-decision-log"
pass=0
fail=0
ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL: $1"; }
expect_rc() { if [ "$1" -eq "$2" ]; then ok; else bad "$3 (expected exit $1, got $2)"; fi; }
expect_eq() { if [ "$1" = "$2" ]; then ok; else bad "$3 (expected '$1', got '$2')"; fi; }
expect_grep() { if printf '%s\n' "$2" | grep -Eq -- "$1"; then ok; else bad "$3 (no line matches: $1)"; fi; }

tmp="$(mktemp -d "${TMPDIR:-/tmp}/decision-log-test.XXXXXX")"
tmp="$(cd "$tmp" && pwd)" || exit 1  # TMPDIR may end in a slash
[ -n "$tmp" ] && [ -d "$tmp" ] || { echo "FAIL: no temp folder"; exit 1; }
trap 'rm -rf "$tmp"' EXIT
cell() { awk -F'\t' -v r="$2" -v c="$3" 'NR == r { print $c }' "$1"; }  # file row column
TAB="$(printf '\t')"
NL="
"

# 1. --help, -h, and the first line.
out="$("$dl" --help 2>&1)"; expect_rc 0 $? "--help exits 0"
expect_grep '^ctlhq-decision-log: ' "$(printf '%s\n' "$out" | head -1)" "--help first line is 'ctlhq-decision-log: ...'"
expect_grep 'usage: ctlhq-decision-log <logfile> <phase> <decision> <why> <evidence> <result>' "$out" "--help shows the six arguments"
"$dl" -h >/dev/null 2>&1; expect_rc 0 $? "-h exits 0"
logsh="$root/skills/show-me-your-work/scripts/log.sh"
out="$("$logsh" --help 2>&1)"; expect_rc 0 $? "log.sh --help exits 0"
expect_grep '^usage: log.sh <logfile> <phase> <decision> <why> <evidence> <result>$' "$out" "log.sh --help prints its usage"
"$logsh" -h >/dev/null 2>&1; expect_rc 0 $? "log.sh -h exits 0"
"$logsh" >/dev/null 2>&1; expect_rc 1 $? "log.sh with no arguments still exits 1"

# 2. Wrong argument count: exit 1 (documented), what, why, and fix on stderr, nothing written.
err="$("$dl" 2>&1 >/dev/null)"; expect_rc 1 $? "no arguments exits 1"
expect_grep '^ctlhq-decision-log: got 0 of 6 arguments; missing logfile, phase, decision, why, evidence, result$' "$err" "no arguments names all six missing cells"
err="$("$dl" "$tmp/three.tsv" a b 2>&1 >/dev/null)"; expect_rc 1 $? "three arguments exits 1"
expect_grep '^ctlhq-decision-log: got 3 of 6 arguments; missing why, evidence, result$' "$err" "three arguments names the three missing cells"
expect_grep '^why: ' "$err" "a wrong count says why"
expect_grep "^fix: quote each cell that holds spaces, for example: ctlhq-decision-log $tmp/three.tsv build \"chose X\" " "$err" "a wrong count gets a fix line with the log path filled in"
err="$("$dl" "$tmp/five.tsv" a b c d 2>&1 >/dev/null)"; expect_rc 1 $? "five arguments exits 1"
expect_grep '^ctlhq-decision-log: got 5 of 6 arguments; missing result$' "$err" "five arguments names the missing cell"
err="$("$dl" "$tmp/seven.tsv" a b c d e f 2>&1 >/dev/null)"; expect_rc 1 $? "seven arguments exits 1"
expect_grep '^ctlhq-decision-log: got 7 arguments, 1 more than the 6 it takes$' "$err" "seven arguments says how many extra"
expect_grep '^fix: quote each cell that holds spaces' "$err" "seven arguments gets a fix line"
[ ! -e "$tmp/three.tsv" ] && [ ! -e "$tmp/five.tsv" ] && [ ! -e "$tmp/seven.tsv" ] && ok || bad "a wrong argument count writes no file"

# 3. First write: header plus one row, six cells, UTC timestamp.
log="$tmp/log.tsv"
out="$("$dl" "$log" plan "pick sqlite" "one file" "bench.tsv" "kept" 2>&1)"; expect_rc 0 $? "first row exits 0"
expect_eq "" "$out" "a written row prints nothing"
expect_eq "ts${TAB}phase${TAB}decision${TAB}why${TAB}evidence${TAB}result" "$(sed -n 1p "$log")" "header is written on first use"
expect_eq 2 "$(wc -l < "$log" | tr -d ' ')" "first use writes 2 lines"
expect_eq 6 "$(awk -F'\t' 'NR == 2 { print NF }' "$log")" "the row has six cells"
expect_grep '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' "$(cell "$log" 2 1)" "ts is UTC ISO 8601"
expect_eq "pick sqlite" "$(cell "$log" 2 3)" "decision cell kept as written"

# 4. Second write: no second header.
"$dl" "$log" build "b" "c" "d" "e" >/dev/null 2>&1; expect_rc 0 $? "second row exits 0"
expect_eq 3 "$(wc -l < "$log" | tr -d ' ')" "second row adds one line"
expect_eq 1 "$(grep -c '^ts' "$log")" "header appears once"

# 5. Tabs, newlines, and carriage returns become spaces.
clean="$tmp/clean.tsv"
"$dl" "$clean" "a${TAB}b" "line1${NL}line2" "x$(printf '\r')y" e f >/dev/null 2>&1; expect_rc 0 $? "row with tabs and newlines exits 0"
expect_eq 2 "$(wc -l < "$clean" | tr -d ' ')" "tabs and newlines do not add lines"
expect_eq 6 "$(awk -F'\t' 'NR == 2 { print NF }' "$clean")" "tabs do not add cells"
expect_eq "a b|line1 line2|x y" "$(cell "$clean" 2 2)|$(cell "$clean" 2 3)|$(cell "$clean" 2 4)" "tab, newline, and CR become spaces"

# 6. Formula cells (=, +, -, @) get a leading single quote; others do not.
f="$tmp/formula.tsv"
"$dl" "$f" "=SUM(A1)" "+1" "-cmd" "@me" "plain" >/dev/null 2>&1; expect_rc 0 $? "formula row exits 0"
expect_eq "'=SUM(A1)|'+1|'-cmd|'@me|plain" "$(cell "$f" 2 2)|$(cell "$f" 2 3)|$(cell "$f" 2 4)|$(cell "$f" 2 5)|$(cell "$f" 2 6)" "formula cells are quoted, plain cells are not"
"$dl" "$f" "a=b" "1+1" "x-y" "me@x" "" >/dev/null 2>&1
expect_eq "a=b|1+1|x-y|me@x|" "$(cell "$f" 3 2)|$(cell "$f" 3 3)|$(cell "$f" 3 4)|$(cell "$f" 3 5)|$(cell "$f" 3 6)" "a formula character after the first is not quoted; empty cell stays empty"

# 7. Missing parent folders are created; an empty existing file gets the header.
deep="$tmp/a/b/c/log.tsv"
"$dl" "$deep" p d w e r >/dev/null 2>&1; expect_rc 0 $? "nested missing folders exit 0"
expect_eq 2 "$(wc -l < "$deep" 2>/dev/null | tr -d ' ')" "nested log has header and row"
: > "$tmp/empty.tsv"
"$dl" "$tmp/empty.tsv" p d w e r >/dev/null 2>&1
expect_eq "ts" "$(cut -f1 "$tmp/empty.tsv" | head -1)" "an empty existing file gets the header"

# 8. A relative log path works from another folder (symlink resolution finds scripts/).
( cd "$tmp" && "$dl" rel.tsv p d w e r >/dev/null 2>&1 ); expect_rc 0 $? "relative path from another cwd exits 0"
expect_eq 2 "$(wc -l < "$tmp/rel.tsv" | tr -d ' ')" "relative path writes into the cwd"

# 9. A log path that is a folder fails with a non-zero exit and writes nothing.
mkdir "$tmp/adir"
err="$("$dl" "$tmp/adir" p d w e r 2>&1 >/dev/null)"; rc=$?
if [ "$rc" -ne 0 ]; then ok; else bad "a folder as the log path exits non-zero (got 0)"; fi
expect_grep "^ctlhq-decision-log: $tmp/adir is a folder, and the log must be a file\$" "$err" "a folder as the log path is named"
expect_grep "^fix: pass a file path, for example: ctlhq-decision-log $tmp/adir/decisions.tsv " "$err" "a folder as the log path gets a fix line"
: > "$tmp/ro.tsv"; chmod 444 "$tmp/ro.tsv"
err="$("$dl" "$tmp/ro.tsv" p d w e r 2>&1 >/dev/null)"; expect_rc 1 $? "a read-only log exits 1"
expect_grep "^ctlhq-decision-log: cannot write $tmp/ro.tsv\$" "$err" "a read-only log is named"
expect_grep "^fix: .*ls -ld $tmp/ro.tsv" "$err" "a read-only log gets a fix line"
expect_eq 0 "$(wc -c < "$tmp/ro.tsv" | tr -d ' ')" "a read-only log is left unchanged"
mkdir "$tmp/rodir"; chmod 555 "$tmp/rodir"
err="$("$dl" "$tmp/rodir/sub/log.tsv" p d w e r 2>&1 >/dev/null)"; expect_rc 1 $? "a log under a read-only folder exits 1"
expect_grep "^why: the folder $tmp/rodir is read-only for you\$" "$err" "a read-only folder is named in the why line"
chmod 755 "$tmp/rodir"

# 10. Positive control: a copy of log.sh with the formula quoting removed must fail check 6.
mut="$tmp/mutant/skills/show-me-your-work"
mkdir -p "$mut/bin" "$mut/scripts"
cp "$root/skills/show-me-your-work/bin/ctlhq-decision-log" "$mut/bin/"
sed 's/=\*|+\*|-\*|@\*) printf "'"'"'%s" "\$v" ;;/=*|+*|-*|@*) printf "%s" "$v" ;;/' \
	"$root/skills/show-me-your-work/scripts/log.sh" > "$mut/scripts/log.sh"
chmod +x "$mut/bin/ctlhq-decision-log" "$mut/scripts/log.sh"
if cmp -s "$mut/scripts/log.sh" "$root/skills/show-me-your-work/scripts/log.sh"; then
	bad "positive control: the planted defect did not change log.sh"
else
	ok
fi
"$mut/bin/ctlhq-decision-log" "$tmp/mut.tsv" "=SUM(A1)" b c d e >/dev/null 2>&1
expect_eq "=SUM(A1)" "$(cell "$tmp/mut.tsv" 2 2)" "positive control: the mutant writes the formula unquoted, so check 6 would catch it"

echo "$pass checks passed"
if [ "$fail" -gt 0 ]; then
	echo "$fail checks failed"
	exit 1
fi
