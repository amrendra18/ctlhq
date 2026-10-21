#!/usr/bin/env bash
# tests/ctlhq-gallery/run.sh: checks for bin/ctlhq-gallery with two synthetic evidence folders.
# Prints "N checks passed" and exits 1 when any check fails. Writes only to a temp folder.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
fg="$root/bin/ctlhq-gallery"
pass=0
fail=0
ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL: $1"; }
expect_rc() { if [ "$1" -eq "$2" ]; then ok; else bad "$3 (expected exit $1, got $2)"; fi; }
expect_eq() { if [ "$1" = "$2" ]; then ok; else bad "$3 (expected '$1', got '$2')"; fi; }
expect_grep() { if printf '%s\n' "$2" | grep -Eq -- "$1"; then ok; else bad "$3 (no line matches: $1)"; fi; }
expect_nogrep() { if printf '%s\n' "$2" | grep -Eiq -- "$1"; then bad "$3 (a line matches: $1)"; else ok; fi; }
state_of() { # page, image name: the data-state of that image's card
	python3 -c '
import re, sys, html
page = open(sys.argv[1]).read()
for m in re.finditer(r"<figure class=\"shot[^\"]*\" data-state=\"([a-z]+)\">.*?<span class=\"name\">(.*?)</span>", page):
    if html.unescape(m.group(2)) == sys.argv[2]:
        print(m.group(1)); break
else:
    print("absent")' "$1" "$2"
}

tmp="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/ctlhq-gallery-test.XXXXXX")" && pwd -P)"
trap 'rm -rf "$tmp"' EXIT
a="$tmp/2026-10-17T10-00-00Z"; b="$tmp/2026-10-17T11-00-00Z"
mkdir -p "$a/screens/editor" "$b/screens/editor" "$tmp/empty/screens"
printf 'PNG-same' >"$a/screens/core.png";        cp "$a/screens/core.png" "$b/screens/core.png"
printf 'PNG-one'  >"$a/screens/editor/open.png"; printf 'PNG-two' >"$b/screens/editor/open.png"
printf 'PNG-old'  >"$a/screens/size.png";        printf 'PNG-older' >"$b/screens/size.png"
printf 'PNG-gone' >"$a/screens/reader.png"
printf 'PNG-new'  >"$b/screens/history.png"
printf 'PNG-odd'  >"$b/screens/<odd> & \"name\".png"
printf 'not an image' >"$b/screens/notes.txt"

# 1. --help and usage errors.
out="$("$fg" --help 2>&1)"; expect_rc 0 $? "--help exits 0"
expect_grep '^ctlhq-gallery: ' "$(printf '%s\n' "$out" | head -1)" "--help first line is 'ctlhq-gallery: ...'"
"$fg" >/dev/null 2>&1; expect_rc 2 $? "no DIR exits 2"
"$fg" "$tmp/nope" >/dev/null 2>&1; expect_rc 2 $? "a missing DIR exits 2"
"$fg" "$b" --previous "$tmp/nope" >/dev/null 2>&1; expect_rc 2 $? "a missing --previous exits 2"
"$fg" "$b" --previous "$b" >/dev/null 2>&1; expect_rc 2 $? "--previous equal to DIR exits 2"
"$fg" "$b" --bogus >/dev/null 2>&1; expect_rc 2 $? "unknown option exits 2"

# 2. Compared with the previous run: changed, new, same, removed.
out="$("$fg" "$b" --previous "$a" 2>&1)"; expect_rc 0 $? "gallery with --previous exits 0"
expect_eq "wrote $b/index.html: 5 images, 2 changed, 2 new, 1 same, 1 removed" "$out" "summary line counts"
page="$b/index.html"
expect_eq changed "$(state_of "$page" editor/open.png)" "a changed image is marked changed"
expect_eq changed "$(state_of "$page" size.png)" "an image whose size changed is marked changed"
expect_eq new "$(state_of "$page" history.png)" "a new image is marked new"
expect_eq same "$(state_of "$page" core.png)" "control: identical bytes are marked same"
expect_eq absent "$(state_of "$page" notes.txt)" "a non-image file is left out"
expect_grep '<li data-state="removed">reader.png</li>' "$(cat "$page")" "a removed image is listed"
expect_eq new "$(state_of "$page" '<odd> & "name".png')" "an odd file name is shown escaped and marked"
expect_nogrep '<odd>' "$(cat "$page")" "the odd name never appears unescaped"
expect_grep 'src="screens/%3Codd%3E%20%26%20%22name%22.png"' "$(cat "$page")" "the odd name's link is URL-quoted"
expect_grep 'src="screens/editor/open.png"' "$(cat "$page")" "images are linked by relative path"

# 3. Static page: no script, nothing from the network, light and dark colours.
html="$(cat "$page")"
expect_nogrep '<script' "$html" "no script tag"
expect_nogrep '(src|href)="(https?:)?//' "$html" "nothing loaded from the network"
expect_grep '@media \(prefers-color-scheme: dark\)' "$html" "dark colours follow the system"
expect_grep 'color-scheme: light dark' "$html" "light and dark declared"

# 4. Without --previous nothing is marked; control: rerunning against an identical copy marks all same.
out="$("$fg" "$a" 2>&1)"; expect_rc 0 $? "gallery without --previous exits 0"
expect_eq "wrote $a/index.html: 4 images, 0 changed, 0 new, 0 same, 0 removed" "$out" "no marks without --previous"
expect_eq unmarked "$(state_of "$a/index.html" core.png)" "an image without a previous run is unmarked"
cp -R "$b" "$tmp/copy"
out="$("$fg" "$tmp/copy" --previous "$b" --title 'Run & copy' 2>&1)"
expect_eq "wrote $tmp/copy/index.html: 5 images, 0 changed, 0 new, 5 same, 0 removed" "$out" "an identical copy is all same"
expect_grep '<h1>Run &amp; copy</h1>' "$(cat "$tmp/copy/index.html")" "--title is shown escaped"

# 5. No screenshots: the page is written and says so; exit 1.
out="$("$fg" "$tmp/empty" 2>&1)"; expect_rc 1 $? "no screenshots exits 1"
expect_grep 'No screenshots under screens/' "$(cat "$tmp/empty/index.html")" "the empty page says so"

echo "$pass checks passed"
if [ "$fail" -gt 0 ]; then
	echo "$fail checks failed"
	exit 1
fi
