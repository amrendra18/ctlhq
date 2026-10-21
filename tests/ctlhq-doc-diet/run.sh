#!/usr/bin/env bash
# tests/ctlhq-doc-diet/run.sh: checks for skills/garden/bin/ctlhq-doc-diet through bin/ctlhq-doc-diet.
# Builds a scratch git repository; prints "N checks passed" and exits 1 when any check fails.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
dd="$root/bin/ctlhq-doc-diet"
pass=0
fail=0
ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL: $1"; }
expect_rc() { # expected actual label
	if [ "$1" -eq "$2" ]; then ok; else bad "$3 (expected exit $1, got $2)"; fi
}
expect_eq() { # expected actual label
	if [ "$1" = "$2" ]; then ok; else bad "$3 (expected '$1', got '$2')"; fi
}
expect_grep() { # pattern text label
	if printf '%s\n' "$2" | grep -Eq -- "$1"; then ok; else bad "$3 (no line matches: $1)"; fi
}
expect_nogrep() { # pattern text label
	if printf '%s\n' "$2" | grep -Eq -- "$1"; then bad "$3 (a line matches: $1)"; else ok; fi
}
# Every table line starts with "| # |" (header) or "| <n> |" (row) or is the separator.
tables_numbered() { # text label
	local bad_lines
	bad_lines="$(printf '%s\n' "$1" | grep '^|' | grep -Ev '^\| # \||^\|---\||^\| [0-9]+ \|')"
	if [ -z "$bad_lines" ]; then ok; else bad "$2 (table line without # column: $bad_lines)"; fi
}

tmp="$(mktemp -d "${TMPDIR:-/tmp}/ctlhq-doc-diet.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
repo="$tmp/repo"
g() { git -C "$repo" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false "$@"; }

# Fixture: five tracked Markdown files, one ignored Markdown file, a .local/ folder, a cache.
mkdir -p "$repo/docs" "$repo/.local" "$repo/__pycache__"
g init -q 2>/dev/null || git init -q "$repo"
printf '.local/\n__pycache__/\nignored.md\n' > "$repo/.gitignore"
printf '# Demo\n\n## Setup\n\nSee [the guide](docs/guide.md) and PLAN.md.\n' > "$repo/README.md"
printf '# Guide\n\n## Setup\n\nInstall it.\n\n```\n## Not a heading\n```\n' > "$repo/docs/guide.md"
printf '# Plan\n\n- [x] ship the parser\n- [ ] write the docs\n* [X] add tests\n\n```\n- [x] inside a fence\n```\n' > "$repo/PLAN.md"
printf '# Orphan\n\none two three four five six\n' > "$repo/orphan.md"
printf '# Old notes\n\nold\n' > "$repo/old.md"
printf '# Ignored\n\n## Setup\n' > "$repo/ignored.md"
printf 'scratch data\n' > "$repo/.local/notes.txt"
printf 'xxxxxxxxxx' > "$repo/__pycache__/a.pyc"
g add -A
g commit -q -m init
touch -t 202001010000 "$repo/old.md"

# 1. --help.
out="$("$dd" --help 2>&1)"; rc=$?
expect_rc 0 "$rc" "--help exits 0"
expect_grep '^ctlhq-doc-diet: ' "$(printf '%s\n' "$out" | head -1)" "--help first line is 'ctlhq-doc-diet: ...'"

# 2. words: 5 tracked files (ignored.md excluded), largest first, total line.
out="$("$dd" words "$repo" 2>&1)"; rc=$?
expect_rc 0 "$rc" "words exits 0"
expect_grep '^words: 5 Markdown files, [0-9]+ words$' "$out" "words header counts 5 files"
expect_nogrep 'ignored\.md' "$out" "words respects .gitignore"
expect_grep '^\| 1 \| [0-9]+ \| PLAN\.md \|$' "$out" "largest file (PLAN.md) is row 1"
tables_numbered "$out" "words table has a # column"
total="$("$dd" --json words "$repo" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["total_words"] == sum(r["words"] for r in d["rows"]), d["count"])')"
expect_eq "True 5" "$total" "--json words total equals the row sum"

# 3. orphans: orphan.md and old.md; README, PLAN (named), guide (linked) not listed.
out="$("$dd" orphans "$repo" 2>&1)"; rc=$?
expect_rc 0 "$rc" "orphans exits 0"
expect_grep '^orphans: 2 Markdown files' "$out" "orphans header counts 2"
expect_grep '\| orphan\.md \|$' "$out" "orphan.md is an orphan"
expect_grep '\| old\.md \|$' "$out" "old.md is an orphan"
expect_nogrep 'guide\.md|PLAN\.md|README\.md' "$out" "linked, named, and keep-list files are not orphans"
expect_grep '^why: nothing links to or names these files' "$(printf '%s\n' "$out" | sed -n 2p)" "orphans: a why line right under the header"
expect_grep '^fix: read each file; fold its live facts into the owning document, or propose deleting it' "$(printf '%s\n' "$out" | sed -n 3p)" "orphans: a fix line under the why line"
fix="$("$dd" --json orphans "$repo" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(bool(d["why"]), d["fix"].startswith("read each file"))')"
expect_eq "True True" "$fix" "--json orphans has why and fix fields"
tables_numbered "$out" "orphans table has a # column"

# 4. dupes: "Setup" in README.md and docs/guide.md; fenced heading and ignored file skipped.
out="$("$dd" dupes "$repo" 2>&1)"; rc=$?
expect_rc 0 "$rc" "dupes exits 0"
expect_grep '^dupes: 1 heading in more than one Markdown file$' "$out" "dupes header counts 1"
expect_grep '^\| 1 \| 2 \| Setup \| README\.md:3, docs/guide\.md:3 \|$' "$out" "Setup row names both files and lines"
expect_nogrep 'Not a heading|ignored' "$out" "fenced heading and ignored file skipped"
expect_grep '^why: one fact in two places drifts apart' "$out" "dupes: a why line"
expect_grep '^fix: read the places listed; when they hold the same fact, keep it in the owning document' "$out" "dupes: a fix line"
tables_numbered "$out" "dupes table has a # column"

# 5. done: two checked boxes in PLAN.md with line numbers; open box and fenced box skipped.
out="$("$dd" done "$repo" 2>&1)"; rc=$?
expect_rc 0 "$rc" "done exits 0"
expect_grep '^done: 2 checked boxes in PLAN\.md' "$out" "done header counts 2"
expect_grep '^\| 1 \| PLAN\.md:3 \| ship the parser \|$' "$out" "first checked box with line 3"
expect_grep '^\| 2 \| PLAN\.md:5 \| add tests \|$' "$out" "capital X box with line 5"
expect_nogrep 'write the docs|inside a fence' "$out" "open and fenced boxes skipped"
expect_grep '^why: a checked box is finished work' "$out" "done: a why line"
expect_grep '^fix: fold what shipped into README\.md, then delete the checked boxes' "$out" "done: a fix line"
tables_numbered "$out" "done table has a # column"

# 6. stale: only old.md (touched to 2020, named by nobody).
out="$("$dd" stale "$repo" 2>&1)"; rc=$?
expect_rc 0 "$rc" "stale exits 0"
expect_grep '^stale: 1 tracked file not modified in 90 days' "$out" "stale header counts 1 at 90 days"
expect_grep '^\| 1 \| [0-9]+ \| 2020-01-01 \| old\.md \|$' "$out" "old.md is stale with its date"
tables_numbered "$out" "stale table has a # column"
out="$("$dd" stale "$repo" --days 100000 2>&1)"; rc=$?
expect_rc 0 "$rc" "stale --days 100000 exits 0"
expect_grep '^stale: 0 tracked files not modified in 100000 days' "$out" "a wide window finds nothing"
expect_nogrep '^(why|fix): ' "$out" "an empty section prints no why or fix line"
expect_eq "False" "$("$dd" --json stale "$repo" --days 100000 | python3 -c 'import json,sys; print("fix" in json.load(sys.stdin))')" "--json: an empty section has no fix field"
expect_grep '^fix: read each file; propose deleting it, or link it' "$("$dd" stale "$repo")" "stale: a fix line"
expect_nogrep '^(why|fix): ' "$("$dd" words "$repo")" "words prints no why or fix line"

# 7. sizes: .local/ and __pycache__/ found; a linked worktree listed with its branch.
g worktree add -q -b side "$tmp/wt" 2>/dev/null
out="$("$dd" sizes "$repo" 2>&1)"; rc=$?
expect_rc 0 "$rc" "sizes exits 0"
expect_grep '^sizes: 2 folders and 1 linked worktree, ' "$out" "sizes header counts 2 folders and 1 worktree"
expect_grep '\| 13 B \| local \| \.local \|$' "$out" ".local/ listed with 13 B"
expect_grep '\| 10 B \| cache \| __pycache__ \|$' "$out" "__pycache__/ listed as a cache with 10 B"
expect_grep '\| worktree \| .*/wt \|$' "$out" "linked worktree listed"
tables_numbered "$out" "sizes table has a # column"
expect_grep '^fix: propose deleting a cache or build folder \(rm -r <path>, after the operator.s yes\); run ctlhq-worktree-audit before proposing a worktree' "$out" "sizes: a fix line names ctlhq-worktree-audit"
branch="$("$dd" --json sizes "$repo" | python3 -c 'import json,sys; print([r["branch"] for r in json.load(sys.stdin)["rows"] if r["kind"] == "worktree"][0])')"
expect_eq "side" "$branch" "--json sizes names the worktree branch"

# 8. Full report: every section, from inside the repository with no DIR.
out="$(cd "$repo" && "$dd" 2>&1)"; rc=$?
expect_rc 0 "$rc" "full report exits 0"
for s in words orphans dupes done stale sizes; do
	expect_grep "^$s: " "$out" "full report has the $s section"
done
tables_numbered "$out" "every table in the full report has a # column"
keys="$("$dd" --json "$repo" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(",".join(k for k in ("words","orphans","dupes","done","stale","sizes") if k in d), d["days"])')"
expect_eq "words,orphans,dupes,done,stale,sizes 90" "$keys" "--json full report has all six sections"

# 9. Read-only: the scratch repository is unchanged.
expect_eq "" "$(g status --porcelain)" "the repository has no changes after all runs"
if [ -f "$repo/.local/notes.txt" ] && [ -f "$repo/old.md" ]; then ok; else bad "no file was deleted"; fi

# 10. Exit codes 1 and 2.
mkdir -p "$tmp/plain"
err="$("$dd" words "$tmp/plain" 2>&1 >/dev/null)"; expect_rc 1 $? "a folder outside git exits 1"
expect_grep "^ctlhq-doc-diet: not a git repository: .*/plain\$" "$err" "a folder outside git is named"
expect_grep '^why: ctlhq-doc-diet counts tracked files only' "$err" "a folder outside git says why"
expect_grep '^fix: ctlhq-doc-diet words <path to the repository>, or cd into the repository and run ctlhq-doc-diet words$' "$err" "a folder outside git gets a fix line with the command filled in"
py="$(command -v python3)"
err="$(PATH=/var/empty "$py" "$dd" words "$repo" 2>&1 >/dev/null)"; expect_rc 1 $? "no git on PATH exits 1"
expect_grep '^fix: install git' "$err" "no git on PATH gets a fix line"
"$dd" bogus-option --nope >/dev/null 2>&1; expect_rc 2 $? "an unknown word and option exit 2"
err="$("$dd" words --nope 2>&1)"; expect_rc 2 $? "an unknown option exits 2"
expect_grep '^ctlhq-doc-diet: unknown option --nope$' "$err" "an unknown option is named"
expect_grep '^fix: use --json or --days N' "$err" "an unknown option gets a fix line"
err="$("$dd" words "$tmp/missing" 2>&1)"; expect_rc 2 $? "a missing folder exits 2"
expect_grep "^ctlhq-doc-diet: not a command or a folder: $tmp/missing\$" "$err" "a missing folder is named"
expect_grep '^fix: use one of words, orphans, dupes, done, stale, sizes, or the path of a folder that exists$' "$err" "a missing folder gets a fix line"
err="$("$dd" words "$repo" --days 5 2>&1)"; expect_rc 2 $? "--days with words exits 2"
expect_grep "^fix: ctlhq-doc-diet stale $repo --days 5, or drop --days\$" "$err" "--days with words gets a fix line with the values filled in"
err="$("$dd" stale "$repo" --days 0 2>&1)"; expect_rc 2 $? "--days 0 exits 2"
expect_grep '^fix: ctlhq-doc-diet stale --days 30$' "$err" "--days 0 gets a fix line"
err="$("$dd" words "$repo" "$repo" 2>&1)"; expect_rc 2 $? "two folders exit 2"
expect_grep '^fix: pass at most one command and one folder' "$err" "two folders get a fix line"

echo "$pass checks passed"
if [ "$fail" -gt 0 ]; then
	echo "$fail checks failed"
	exit 1
fi
