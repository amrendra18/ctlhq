#!/usr/bin/env bash
# tests/ctlhq-research-folder/run.sh: checks for skills/research-folder/bin/ctlhq-research-folder through
# bin/ctlhq-research-folder. Writes only to a mktemp folder. Prints "N checks passed"; exits 1 on any failure.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
rf="$root/bin/ctlhq-research-folder"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/research-folder-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
tmp="$(cd "$tmp" && pwd)"  # TMPDIR may end in a slash
pass=0
fail=0
ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL: $1"; }
expect_rc() { if [ "$1" -eq "$2" ]; then ok; else bad "$3 (expected exit $1, got $2)"; fi; }
expect_eq() { if [ "$1" = "$2" ]; then ok; else bad "$3 (expected '$1', got '$2')"; fi; }
expect_grep() { if printf '%s\n' "$2" | grep -Eq -- "$1"; then ok; else bad "$3 (no line matches: $1)"; fi; }
expect_no() { if printf '%s\n' "$2" | grep -Eq -- "$1"; then bad "$3 (unexpected line: $1)"; else ok; fi; }

# 1. --help; no arguments is a usage error.
out="$("$rf" --help 2>&1)"; expect_rc 0 $? "--help exits 0"
expect_grep '^ctlhq-research-folder: ' "$(printf '%s\n' "$out" | head -1)" "--help first line is 'ctlhq-research-folder: ...'"
err="$("$rf" 2>&1)"; expect_rc 2 $? "no arguments exits 2"
expect_grep '^fix: ctlhq-research-folder init <dir> <topic>, or ctlhq-research-folder check <dir>' "$err" "no arguments gets a fix line"
err="$("$rf" nosuch x 2>&1)"; expect_rc 2 $? "unknown subcommand exits 2"
expect_grep "^ctlhq-research-folder: unknown subcommand 'nosuch'\$" "$err" "unknown subcommand is named"
expect_grep '^why: ctlhq-research-folder has two: init and check$' "$err" "unknown subcommand says why"
expect_grep '^fix: ctlhq-research-folder init <dir> <topic>, or ctlhq-research-folder check <dir>$' "$err" "unknown subcommand gets a fix line"
expect_grep 'Labels: \[high\] seen in a primary source' "$("$rf" --help)" "--help defines the three labels"

# 2. init writes the skeleton; a fresh skeleton checks clean.
d="$tmp/study"
out="$("$rf" init "$d" Prior art for tools)"; expect_rc 0 $? "init exits 0"
expect_eq 6 "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" "init prints 6 paths"
for f in README.md 01-question.md 02-findings.md 03-prior-art.md 04-sources-and-gaps.md; do
	[ -f "$d/$f" ] && ok || bad "init wrote $f"
done
[ -d "$d/reference" ] && ok || bad "init made reference/"
expect_grep '^# Prior art for tools: research$' "$(cat "$d/README.md")" "topic in the index title"
out="$("$rf" check "$d")"; expect_rc 0 $? "fresh skeleton checks clean"
expect_eq "5 files, 0 problems" "$out" "clean summary line"

# 3. init refuses a non-empty folder and writes nothing.
err="$("$rf" init "$d" again 2>&1)"; expect_rc 2 $? "init on a non-empty folder exits 2"
expect_grep "^fix: pick a new folder, or check the one there: ctlhq-research-folder check $d\$" "$err" "init on a non-empty folder gets a fix line"
err="$("$rf" init "$tmp/x" 2>&1)"; expect_rc 2 $? "init without a topic exits 2"
expect_grep "^fix: ctlhq-research-folder init $tmp/x <topic>\$" "$err" "init without a topic gets a fix line with the folder filled in"
[ -e "$tmp/x" ] && bad "init without a topic wrote nothing" || ok

# 4. Each rule fires.
printf -- '- a claim without a label\n2. labelled claim [medium]\n```\n- inside a fence\n```\n' >> "$d/02-findings.md"
printf '| 2 | auth | ours | theirs | missing | |\n' >> "$d/03-prior-art.md"
printf -- '- a source line needs no label\n' >> "$d/04-sources-and-gaps.md"
printf 'copied text\n' > "$d/reference/paper.md"
printf 'Source: https://example.org/post (retrieved 2026-10-16)\n\nbody\n' > "$d/reference/post.md"
printf '%%PDF-1.4 \x00\x01\x02' > "$d/reference/spec.pdf"
printf 'notes\n' > "$d/scratch.md"
out="$("$rf" check "$d")"; expect_rc 1 $? "problems exit 1"
expect_grep $'^#\tfile\tline\tproblem\twhy\tfix$' "$out" "problem table header"
expect_eq 0 "$(printf '%s\n' "$out" | sed '1d;$d' | awk -F'\t' 'NF != 6 || $5 == "" || $6 == ""' | wc -l | tr -d ' ')" "every problem row has six cells with a why and a fix"
expect_grep $'\t02-findings.md\t4\t.*\tend 02-findings.md line 4 with \\[high\\], \\[medium\\], or \\[low\\]' "$out" "label fix names the file and line"
expect_grep $'\tscratch.md\t-\t.*\trename it with: mv '"$d"'/scratch.md '"$d"$'/05-scratch.md \\(the next free number\\)' "$out" "rename fix names the next free number"
expect_grep $'\tREADME.md\t-\tindex does not name reference/paper.md\t.*\tadd "\\| 5 \\| reference/paper.md \\| <what it holds> \\|" to the README.md table$' "$out" "index fix gives the next row number after the last README row"
expect_grep $'\tREADME.md\t-\tindex does not name scratch.md\t.*\tadd "\\| [6-9] \\| 05-scratch.md \\|' "$out" "index fix counts on and names the renamed path"
expect_grep $'\treference/paper.md\t-\t.*\tadd "Source: <url> \\(retrieved <YYYY-MM-DD>\\)" as line 1 of reference/paper.md' "$out" "Source fix names the file"
expect_grep $'\treference/spec.pdf\t-\t.*\twrite "Source: <url> \\(retrieved <YYYY-MM-DD>\\)" to reference/spec.pdf.source$' "$out" "sidecar fix names the sidecar path"
expect_grep $'^[0-9]+\t02-findings.md\t4\tclaim has no confidence label' "$out" "unlabelled list item flagged with its line"
expect_no $'\t02-findings.md\t5\t' "$out" "labelled item passes"
expect_no $'\t02-findings.md\t7\t' "$out" "fenced line skipped"
expect_grep $'\t03-prior-art.md\t6\tclaim has no confidence label' "$out" "unlabelled table row flagged"
expect_no $'\t03-prior-art.md\t3\t' "$out" "table header row skipped"
expect_no $'\t04-sources-and-gaps.md\t' "$out" "sources file needs no labels"
expect_grep $'\treference/paper.md\t-\treference copy has no .Source:. line' "$out" "reference copy without attribution flagged"
expect_no $'\treference/post.md\t-\treference copy' "$out" "reference copy with Source: passes"
expect_grep $'\treference/spec.pdf\t-\tnon-text reference copy has no spec.pdf.source sidecar' "$out" "PDF without sidecar flagged"
expect_grep $'\tREADME.md\t-\tindex does not name reference/post.md' "$out" "index must name reference copies"
expect_grep $'\tscratch.md\t-\ttop-level file is not numbered' "$out" "unnumbered top-level file flagged"

# 5. Fixes clear the problems; --json; missing sources file; missing folder.
printf 'Source: https://example.org/spec.pdf (retrieved 2026-10-16)\n' > "$d/reference/spec.pdf.source"
printf 'Source: https://example.org/paper (retrieved 2026-10-16), license CC BY 4.0\n' | cat - "$d/reference/paper.md" > "$tmp/p" && mv "$tmp/p" "$d/reference/paper.md"
rm "$d/scratch.md"
sed -i.bak -e 's/^- a claim without a label$/- a claim with a label [high]/' "$d/02-findings.md" && rm "$d/02-findings.md.bak"
sed -i.bak -e 's/| missing | |$/| missing | [low] |/' "$d/03-prior-art.md" && rm "$d/03-prior-art.md.bak"
printf -- '- reference/paper.md, reference/post.md, reference/spec.pdf, reference/spec.pdf.source\n' >> "$d/README.md"
out="$("$rf" check "$d")"; expect_rc 0 $? "fixed folder checks clean"
expect_eq "9 files, 0 problems" "$out" "clean after fixes"
mv "$d/04-sources-and-gaps.md" "$d/04-notes.md"; sed -i.bak 's/04-sources-and-gaps.md/04-notes.md/' "$d/README.md" && rm "$d/README.md.bak"
json="$("$rf" check --json "$d")"; expect_rc 1 $? "missing sources file exits 1"
expect_grep 'no sources-and-gaps file' "$json" "--json names the missing sources file"
expect_eq "True" "$(printf '%s' "$json" | python3 -c 'import json,sys; p=json.load(sys.stdin)["problems"]; print(all(x["why"] and x["fix"] for x in p) and any(x["fix"].startswith("create 05-sources-and-gaps.md") for x in p))')" "--json problems carry why and fix; the sources fix names the next free number"
err="$("$rf" check "$tmp/none" 2>&1)"; expect_rc 2 $? "missing folder exits 2"
expect_grep "^fix: create it with: ctlhq-research-folder init $tmp/none <topic>" "$err" "missing folder gets a fix line"
err="$("$rf" check 2>&1)"; expect_rc 2 $? "check without a folder exits 2"
expect_grep '^fix: ctlhq-research-folder check docs/research/<topic>$' "$err" "check without a folder gets a fix line"
printf '\xff\xfe bad\n' > "$d/02-findings.md"
err="$("$rf" check "$d" 2>&1)"; expect_rc 2 $? "a numbered file that is not UTF-8 exits 2"
expect_grep "^ctlhq-research-folder: $d/02-findings.md is not UTF-8 text\$" "$err" "a file that is not UTF-8 is named"
expect_grep "^fix: save $d/02-findings.md as UTF-8" "$err" "a file that is not UTF-8 gets a fix line"

# 6. A Source: line needs a URL and a retrieved date (planted cases).
s="$tmp/srcfmt"
"$rf" init "$s" Source format >/dev/null
printf 'Source: somewhere\n' > "$s/reference/none.md"
printf 'notes\nSource: https://example.org/a\n' > "$s/reference/nodate.md"
printf 'Source: the author (retrieved 2026-10-01)\n' > "$s/reference/nourl.md"
printf '**Source:** https://example.org/b (retrieved 2026-10-01)\n' > "$s/reference/good.md"
printf -- '- reference/none.md, reference/nodate.md, reference/nourl.md, reference/good.md\n' >> "$s/README.md"
out="$("$rf" check "$s")"; expect_rc 1 $? "a Source: line without a URL or a date exits 1"
expect_grep $'\treference/none.md\t1\tSource: line lacks a URL and a retrieved date\t' "$out" "a Source: line with neither part is flagged at its line"
expect_grep $'\treference/nodate.md\t2\tSource: line lacks a retrieved date\t.*\trewrite reference/nodate.md line 2 as "Source: <url> \\(retrieved <YYYY-MM-DD>\\)", plus the license when known$' "$out" "a Source: line without a date gets a fix with the file and line"
expect_grep $'\treference/nourl.md\t1\tSource: line lacks a URL\t' "$out" "a Source: line without a URL is flagged"
expect_no $'\treference/good.md\t' "$out" "a full Source: line in bold passes"
expect_grep '^9 files, 3 problems$' "$out" "only the three planted lines are problems"

echo "$pass checks passed"
[ "$fail" -eq 0 ] || { echo "$fail checks failed"; exit 1; }
