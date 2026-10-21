#!/usr/bin/env bash
# tests/ctlhq-no-comments/run.sh: checks for skills/no-comments/bin/ctlhq-no-comments through bin/ctlhq-no-comments.
# Covers file mode for every language family, directory walks, each keep-list tag, the flags
# --all, --removed, --strict, --require-expiry, --diff BASE, --diff=BASE, a diff on stdin, and
# exits 0, 1, 2. --diff runs against a scratch git repository in a mktemp folder.
# Prints "N checks passed" and exits 1 when any check fails. Read-only for the repository.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
nc="$root/bin/ctlhq-no-comments"
tmp="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/no-comments-test.XXXXXX")" && pwd -P)"
trap 'rm -rf "$tmp"' EXIT
pass=0
fail=0
ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL: $1"; }
expect_rc() { if [ "$1" -eq "$2" ]; then ok; else bad "$3 (expected exit $1, got $2)"; fi; }
expect_eq() { if [ "$1" = "$2" ]; then ok; else bad "$3 (expected '$1', got '$2')"; fi; }
expect_grep() { if printf '%s\n' "$2" | grep -Eq -- "$1"; then ok; else bad "$3 (no line matches: $1)"; fi; }
expect_no() { if printf '%s\n' "$2" | grep -Eq -- "$1"; then bad "$3 (a line matches: $1)"; else ok; fi; }
cd "$tmp" || exit 1

# 1. --help.
out="$("$nc" --help 2>&1)"; expect_rc 0 $? "--help exits 0"
expect_grep '^ctlhq-no-comments: ' "$(printf '%s\n' "$out" | head -1)" "--help first line is 'ctlhq-no-comments: ...'"
for word in --all --removed --strict --require-expiry --diff '\[license\]' '\[prettier-ignore\]' '\[suppression\]' '\[doc-comment\]' '\[issue-link\]'; do
	expect_grep "$word" "$out" "--help names $word"
done
expect_eq "$out" "$("$nc" -h 2>&1)" "-h prints the same help"

# 2. Python: shebang skipped, strings skipped, every tag, empty comment, docstring.
cat > a.py <<'PY'
#!/usr/bin/env python3
# Copyright 2024 Example Corp
import os  # noqa: F401
x = "# not a comment"
y = 'also # not'


def f():
    """Docstring here."""
    return 1  # plain comment


# see https://github.com/a/b/issues/12
#
z = 2  # type: ignore[attr-defined] expires:2026-12-31 approved-by:cai
w = 3  # noqa: E501 expires:2026-12-31 approved-by:cai long generated line
s = """
# inside a triple-quoted string
"""
PY
want='a.py:2: Copyright 2024 Example Corp [license]
a.py:3: noqa: F401 [suppression]
a.py:9: Docstring here. [doc-comment]
a.py:10: plain comment
a.py:13: see https://github.com/a/b/issues/12 [issue-link]
a.py:14: (empty comment)
a.py:15: type: ignore[attr-defined] expires:2026-12-31 approved-by:cai [suppression]
a.py:16: noqa: E501 expires:2026-12-31 approved-by:cai long generated line [suppression]
8 comments in 1 files, 6 keep-list candidates'
want_py="$want"
out="$("$nc" a.py 2>&1)"; rc=$?
expect_eq "$want" "$out" "python file: exact findings and summary"
expect_rc 1 "$rc" "an untagged comment exits 1"
expect_no '^a\.py:1:' "$out" "the shebang is skipped"
expect_no 'not a comment|inside a triple' "$out" "markers inside strings are skipped"

# 3. --all reports a marker inside a string literal.
out="$("$nc" --all a.py 2>&1)"
expect_grep "^a\.py:5: not'$" "$out" "--all reports the marker inside 'also # not'"
expect_grep '^a\.py:18: inside a triple-quoted string$' "$out" "--all reports the marker inside a triple-quoted string"
expect_grep '^10 comments in 1 files, 6 keep-list candidates$' "$out" "--all summary counts the string markers"

# 4. --require-expiry.
out="$("$nc" --require-expiry a.py 2>&1)"; rc=$?
expect_grep '^a\.py:3: noqa: F401 \[suppression; missing expires, approved-by, reason\]$' "$out" "bare noqa lacks all three parts"
expect_grep '^a\.py:15: .*\[suppression; missing reason\]$' "$out" "attr-defined is a rule id, not a reason"
expect_grep '^a\.py:16: .*long generated line \[suppression\]$' "$out" "a complete suppression keeps the plain tag"
expect_grep '^8 comments in 1 files, 6 keep-list candidates, 2 incomplete suppressions$' "$out" "--require-expiry summary adds the incomplete count"
expect_grep '^  fix: add "expires:<YYYY-MM-DD> approved-by:<name> <reason>" to the comment at a\.py:3, because' "$out" "an incomplete suppression gets a fix line naming every missing part and the file:line"
expect_grep '^  fix: add "<reason>" to the comment at a\.py:15, because' "$out" "the fix line names only the missing part"
expect_eq 2 "$(printf '%s\n' "$out" | grep -c '^  fix: ')" "one fix line per incomplete suppression, none for a complete one"
expect_no '^  fix: ' "$("$nc" a.py 2>&1)" "no fix lines without --require-expiry"
printf 'x = 1  # noqa: E501\n' > onlysup.py
"$nc" onlysup.py >/dev/null 2>&1; expect_rc 0 $? "only tagged comments exit 0"
"$nc" --require-expiry onlysup.py >/dev/null 2>&1; expect_rc 1 $? "--require-expiry: an incomplete suppression alone exits 1"
printf 'x = 1  # noqa: E501 expires:2027-01-01 approved-by:cai generated table\n' > goodsup.py
"$nc" --require-expiry goodsup.py >/dev/null 2>&1; expect_rc 0 $? "--require-expiry: a complete suppression exits 0"

# 5. --strict.
"$nc" --strict onlysup.py >/dev/null 2>&1; expect_rc 1 $? "--strict: a tagged comment exits 1"
printf 'x = 1\n' > clean.py
out="$("$nc" --strict clean.py 2>&1)"; rc=$?
expect_rc 0 "$rc" "--strict on a clean file exits 0"
expect_eq "0 comments in 1 files, 0 keep-list candidates" "$out" "clean file summary"

# 6. C family: URL after a colon, doc blocks, a block comment as one finding, template literal, ///.
cat > b.ts <<'TS'
const u = "http://example.com"; // trailing note
/** Doc block. */
/* multi
 * line */
// prettier-ignore
const t = `
// inside template
`;
/// triple doc
const k = { url: http://x }; // after colon url
TS
want='b.ts:1: trailing note
b.ts:2: Doc block. [doc-comment]
b.ts:3: multi line
b.ts:5: prettier-ignore [prettier-ignore]
b.ts:9: triple doc [doc-comment]
b.ts:10: after colon url
6 comments in 1 files, 3 keep-list candidates'
expect_eq "$want" "$("$nc" b.ts 2>&1)" "typescript file: exact findings"

# 7. Other families: sh hash rule, rust lifetimes and char literals, sql, lua, haskell, markdown.
printf '#!/bin/sh\necho a#b $#\n# real comment\n' > c.sh
printf 'fn f<'"'"'a>(x: &'"'"'a str) -> char { '"'"'"'"'"' } // rust note\n' > d.rs
printf -- '-- sql line\nSELECT 1; /* sql block */\n' > e.sql
printf -- '--[[ lua\nblock ]]\nlocal x = 1 -- lua line\n' > f.lua
printf -- '{- hs block -}\nmain = 1 -- hs line\n' > g.hs
printf '<!-- md comment -->\ntext\n' > h.md
printf 'key: "a # b" # yaml note\nurl: http://x/#anchor\n' > j.yaml
expect_eq "c.sh:3: real comment" "$("$nc" c.sh | sed '$d')" "sh: a#b and \$# are not comments"
expect_eq "d.rs:1: rust note" "$("$nc" d.rs | sed '$d')" "rust: lifetimes and a quote char literal do not open a string"
expect_eq "e.sql:1: sql line|e.sql:2: sql block" "$("$nc" e.sql | sed '$d' | paste -sd'|' -)" "sql: -- and /* */"
expect_eq "f.lua:1: lua block|f.lua:3: lua line" "$("$nc" f.lua | sed '$d' | paste -sd'|' -)" "lua: --[[ ]] block and -- line"
expect_eq "g.hs:1: hs block|g.hs:2: hs line" "$("$nc" g.hs | sed '$d' | paste -sd'|' -)" "haskell: {- -} block and -- line"
expect_eq "h.md:1: md comment" "$("$nc" h.md | sed '$d')" "markdown: <!-- -->"
expect_eq "j.yaml:1: yaml note" "$("$nc" j.yaml | sed '$d')" "yaml: string and #anchor are not comments"

# 8. CSS has no // line comments, so a protocol-relative url() is not a comment.
printf '.a { background: url(//cdn.example.com/x.png); }\n/* css block */\n' > k.css
out="$("$nc" k.css 2>&1)"
expect_no '^k\.css:1:' "$out" "css: url(//host) is not a comment"
expect_grep '^k\.css:2: css block$' "$out" "css: /* */ block is reported"

# 9. Unknown extension, missing file, long comment truncation, directory walk.
: > notes.txt; err="$("$nc" notes.txt 2>&1 >/dev/null)"; rc=$?
expect_rc 0 "$rc" "an explicit unknown-language file alone exits 0"
expect_grep '^skipped \(unknown language\): notes\.txt; ctlhq-no-comments --help lists the extensions it reads$' "$err" "an explicit unknown-language file is noted on stderr with where to look"
err="$("$nc" missing.py 2>&1)"; rc=$?
expect_rc 2 "$rc" "a missing file exits 2 (known-bad input)"
expect_grep '^ctlhq-no-comments: cannot read missing\.py' "$err" "a missing file is named on stderr"
expect_grep '^why: ' "$err" "a missing file says why it stops"
expect_grep '^fix: check the path with `ls \.`' "$err" "a missing file gets a fix line with the folder filled in"
python3 -c "print('# ' + 'w' * 400)" > long.py
line="$("$nc" long.py | head -1)"
expect_eq 311 "${#line}" "a long comment is cut to 300 characters plus the path prefix"
expect_grep '\.\.\.$' "$line" "a cut comment ends with ..."
mkdir -p tree/sub tree/node_modules/pkg tree/.git
printf '# in tree\n' > tree/sub/x.py
printf '// vendored\n' > tree/node_modules/pkg/y.js
printf '# git internals\n' > tree/.git/z.sh
printf '# not code\n' > tree/readme.txt
out="$("$nc" tree 2>&1)"
expect_eq "tree/sub/x.py:1: in tree|1 comments in 1 files, 0 keep-list candidates" "$(printf '%s\n' "$out" | paste -sd'|' -)" "directory walk skips node_modules, .git, and unknown extensions silently"

# 10. A unified diff on stdin: added lines only, new line numbers, deleted and unknown files skipped.
cat > p.diff <<'DIFF'
diff --git a/src/app.py b/src/app.py
--- a/src/app.py
+++ b/src/app.py
@@ -1,4 +1,5 @@
 import os
-# old comment
+# new comment
+x = 1  # noqa: E501
 # context comment
 y = 2
diff --git a/gone.js b/gone.js
--- a/gone.js
+++ /dev/null
@@ -1,2 +0,0 @@
-// removed file comment
-const a = 1;
diff --git a/notes.txt b/notes.txt
--- a/notes.txt
+++ b/notes.txt
@@ -1 +1 @@
-# txt
+# txt2
DIFF
want='src/app.py:2: new comment
src/app.py:3: noqa: E501 [suppression]
2 comments in 1 files, 1 keep-list candidates'
out="$("$nc" < p.diff 2>&1)"; rc=$?
expect_eq "$want" "$out" "stdin diff: added comments only, context and removed lines ignored"
expect_rc 1 "$rc" "stdin diff with an untagged added comment exits 1"
expect_eq "$want" "$("$nc" - < p.diff 2>&1)" "'-' reads the diff from stdin"
want='src/app.py:2: old comment
gone.js:1: removed file comment
2 comments removed in 2 files, 0 keep-list candidates'
expect_eq "$want" "$("$nc" --removed < p.diff 2>&1)" "--removed: removed lines with old line numbers, deleted file included"
printf 'diff --git a/q.py b/q.py\n--- a/q.py\n+++ b/q.py\n@@ -1,3 +1,3 @@\n """Block start.\n-old\n+new\n end"""\n' > block.diff
expect_grep '^0 comments in 1 files' "$("$nc" < block.diff)" "a string literal edited in a diff is not a comment"
printf 'diff --git a/q.ts b/q.ts\n--- a/q.ts\n+++ b/q.ts\n@@ -1,3 +1,3 @@\n /* block\n-old\n+new\n */\n' > block2.diff
expect_grep '^q\.ts:2: block new$' "$("$nc" < block2.diff)" "a block comment touched by an added line is reported at the added line"
err="$(echo hello | "$nc" 2>&1)"; rc=$?
expect_rc 2 "$rc" "stdin that is not a diff exits 2"
expect_grep 'not a unified diff' "$err" "stdin that is not a diff is explained"
expect_grep '^fix: pipe a diff \(git diff main \| ctlhq-no-comments\)' "$err" "stdin that is not a diff gets a fix line"
printf '' | "$nc" >/dev/null 2>&1; expect_rc 2 $? "empty stdin exits 2"

# 11. --diff BASE against a scratch git repository.
g="$tmp/repo"; mkdir -p "$g"
git -C "$g" init -q
printf 'x = 1\n' > "$g/m.py"; printf 'let a = 1;\n' > "$g/n.js"
git -C "$g" add m.py n.js
git -C "$g" -c user.name=t -c user.email=t@example.com -c commit.gpgsign=false commit -qm base
printf 'x = 1\n# added py comment\n' > "$g/m.py"; printf 'let a = 1; // added js comment\n' > "$g/n.js"
out="$(cd "$g" && "$nc" --diff HEAD 2>&1)"; rc=$?
expect_eq "m.py:2: added py comment|n.js:1: added js comment|2 comments in 2 files, 0 keep-list candidates" "$(printf '%s\n' "$out" | paste -sd'|' -)" "--diff HEAD reports the working-tree additions"
expect_rc 1 "$rc" "--diff HEAD with untagged additions exits 1"
expect_eq "$out" "$(cd "$g" && "$nc" --diff=HEAD 2>&1)" "--diff=HEAD equals --diff HEAD"
out="$(cd "$g" && "$nc" --diff HEAD -- n.js 2>&1)"
expect_eq "n.js:1: added js comment|1 comments in 1 files, 0 keep-list candidates" "$(printf '%s\n' "$out" | paste -sd'|' -)" "--diff HEAD -- FILE limits the diff"
printf 'x = 1\n' > "$g/m.py"; printf 'let a = 1;\n' > "$g/n.js"
out="$(cd "$g" && "$nc" --diff HEAD 2>&1)"; rc=$?
expect_eq "0 comments in 0 files, 0 keep-list candidates" "$out" "--diff with no changes"
expect_rc 0 "$rc" "--diff with no changes exits 0"
printf '# about to go\nx = 1\n' > "$g/m.py"; git -C "$g" add m.py
git -C "$g" -c user.name=t -c user.email=t@example.com -c commit.gpgsign=false commit -qm two
printf 'x = 1\n' > "$g/m.py"
expect_grep '^m\.py:1: about to go$' "$(cd "$g" && "$nc" --diff HEAD --removed 2>&1)" "--diff HEAD --removed reports a deleted comment"
err="$(cd "$g" && "$nc" --diff no-such-ref 2>&1)"; rc=$?
expect_rc 2 "$rc" "--diff with an unknown ref exits 2"
expect_grep 'no-such-ref' "$err" "--diff with an unknown ref shows git's error"
expect_grep '^ctlhq-no-comments: --diff no-such-ref: no branch, tag, or commit' "$err" "--diff with an unknown ref says what is wrong"
expect_grep '^fix: list the names with `git branch -a`' "$err" "--diff with an unknown ref gets a fix line"
err="$(cd "$tmp/tree" && "$nc" --diff HEAD 2>&1)"; expect_rc 2 $? "--diff outside a git repository exits 2"
expect_grep "^ctlhq-no-comments: --diff HEAD needs a git repository, and $tmp/tree is not inside one\$" "$err" "--diff outside a repository names the base and the folder"
expect_grep '^why: --diff runs `git diff HEAD`' "$err" "--diff outside a repository says why"
expect_grep '^fix: cd to the repository root and rerun, or scan files instead: ctlhq-no-comments \.$' "$err" "--diff outside a repository gets a fix line"
expect_no 'usage: git' "$err" "--diff outside a repository does not pass git's usage text through"
py="$(command -v python3)"
err="$(cd "$tmp/tree" && PATH=/var/empty "$py" "$nc" --diff HEAD 2>&1)"; expect_rc 2 $? "--diff with no git on PATH exits 2"
expect_grep '^ctlhq-no-comments: --diff HEAD needs git, and git cannot run' "$err" "--diff with no git says git cannot run"
expect_grep '^fix: install git \(on macOS: xcode-select --install\), or scan files instead: ctlhq-no-comments \.$' "$err" "--diff with no git gets a fix line"
err="$(cd "$tmp/tree" && "$nc" --diff HEAD -- sub 2>&1)"
expect_grep '^fix: .*scan files instead: ctlhq-no-comments sub$' "$err" "the fix line names the files given after --"

# 12. Usage errors.
err="$("$nc" --diff 2>&1)"; expect_rc 2 $? "--diff without a base exits 2"
expect_grep '^fix: ctlhq-no-comments --diff main$' "$err" "--diff without a base gets a fix line"
err="$("$nc" --removed a.py 2>&1)"; rc=$?
expect_rc 2 "$rc" "--removed with files exits 2"
expect_grep 'needs --diff BASE or a unified diff' "$err" "--removed with files is explained"
expect_grep '^fix: ctlhq-no-comments --removed --diff main -- a\.py$' "$err" "--removed with files gets a fix line with the files filled in"
err="$("$nc" --bogus a.py 2>&1)"; expect_rc 2 $? "unknown option exits 2"
expect_grep '^ctlhq-no-comments: unknown option --bogus$' "$err" "unknown option is named"
expect_grep '^fix: use one of --all, --removed, --strict, --require-expiry, --diff BASE' "$err" "unknown option gets a fix line"
err="$("$nc" < /dev/null 2>&1)"; expect_rc 2 $? "empty stdin is a usage error"
expect_grep '^fix: ' "$err" "empty stdin gets a fix line"

# 13. Positive controls: planted defects in a copy of the tool must break the checks above.
mkdir -p mutant
mutate() { # sed-expression: write a defective copy to mutant/ctlhq-no-comments and check the defect landed
	sed "$1" "$nc" > mutant/ctlhq-no-comments; chmod +x mutant/ctlhq-no-comments
	if cmp -s "$nc" mutant/ctlhq-no-comments; then bad "control: planted defect '$1' did not change the tool"; else ok; fi
}
mutate 's/self.track_strings = True/self.track_strings = False/'
if [ "$(mutant/ctlhq-no-comments a.py 2>&1)" != "$want_py" ]; then ok; else bad "control: dropping string tracking is caught by the python exact-output check"; fi
mutate 's/return 1 if problems > 0 else 0/return 0/'
mutant/ctlhq-no-comments a.py >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 0 ]; then ok; else bad "control: a tool that always exits 0 is caught by the exit-1 check"; fi
mutate 's/if hit:/if True:/'
if [ "$(mutant/ctlhq-no-comments < p.diff 2>&1 | tail -1)" != "2 comments in 1 files, 1 keep-list candidates" ]; then ok; else bad "control: reporting context lines is caught by the stdin diff check"; fi

echo "$pass checks passed"
[ "$fail" -eq 0 ] || { echo "$fail checks failed"; exit 1; }
