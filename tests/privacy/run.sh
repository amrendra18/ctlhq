#!/usr/bin/env bash
# tests/privacy/run.sh: scans every path and file that `git ls-files` lists for personal values.
#
# Usage: tests/privacy/run.sh [--root DIR] [--help]
#
# Always looks for home folders written as /Users/<name>/ or /home/<name>/, after any prefix
# (such as /System/Volumes/Data/Users/<name>/ or /Volumes/Data/Users/<name>/), in any letter
# case, and in the JSON-escaped form \/Users\/<name>\/. A few placeholder names are allowed (see
# ALLOWED_NAMES). The name must be followed by a slash, and a name that starts with a dot
# (such as /home/.config/) is not a home folder. Session ids and ~/projects/<name> paths are
# not shapes; the word list covers the known ones.
#
# Private words come from the layers: every layer listed in $HOME/.ctlhq/layers.toml (read
# with bin/ctlhq-install's own parser) that holds privacy/private-terms.txt adds its words.
# PRIVACY_TERMS=<file> replaces that lookup, for runs without a layers file. With neither,
# only the path shapes run. In a word file each non-blank line that does not start with "#"
# is one word, matched case-insensitively wherever no letter stands directly before or after
# it, so digits and underscores count as boundaries ("<word>2" and "<word>_v2" match,
# "x<word>" does not).
#
# The owner's own GitHub address is not a private word. Before the word check, every
# github.com/<owner> and github.com:<owner> is removed from the line or name, in any letter
# case. <owner> is the github_owner line of $HOME/.ctlhq/first-push.toml, read with
# bin/ctlhq-push's own parser. Without that file or that line nothing is removed.
#
# Both checks run on every tracked path (each file and folder name) and on file content.
# In a path, a home folder is a folder: Users/<name>/ or home/<name>/. Output
# never prints a private word or a home folder name: a path shows them as "<private word>"
# and "<name>", so this output is safe to paste anywhere.
#
# A file with a NUL byte is read as UTF-16 (by its byte-order mark, else by where its NUL
# bytes fall) when that gives text. Other binary files are skipped, and stderr gets the line
# "privacy: binary files skipped (not UTF-8 or UTF-16 text): N".
#
# Exempt: LICENSE, and in README.md the "## Credits" section, found the way bin/ctlhq-check
# finds it: the heading line outside fenced code up to the next "## " heading.
#
# Before the scan, positive controls run against a scratch repository with a scratch HOME:
# planted words and paths in content and in names must each be reported, and neither a word
# nor a name may be printed.
#
# Exit 0 with no hits, 1 when a control fails or the scan finds hits (one "file:line: kind"
# or "path: kind in name" line each), 2 on a usage error, an unreadable layers.toml or
# github_owner line, or a PRIVACY_TERMS file that does not exist. Writes only under a temp folder.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"

usage() { echo "usage: tests/privacy/run.sh [--root DIR] [--help]" >&2; exit 2; }
while [ $# -gt 0 ]; do
	case "$1" in
	--root) [ $# -ge 2 ] || usage; root="$2"; shift 2 ;;
	-h | --help) sed -n '2,44p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
	*) usage ;;
	esac
done
git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "privacy: not a Git work tree: $root" >&2; exit 2; }

# scan ROOT: prints one hit line per hit and the skipped count on stderr; exits 0 with no
# hits, 1 with any, 2 when layers.toml cannot be read.
scan() {
	python3 -I - "$1" "$here/../../bin/ctlhq-install" "$here/../../bin/ctlhq-check" "$here/../../bin/ctlhq-push" <<'PY'
import os
import re
import subprocess
import sys
import unicodedata
from importlib.machinery import SourceFileLoader
from importlib.util import module_from_spec, spec_from_loader
from pathlib import Path

ALLOWED_NAMES = {"you", "<you>", "x", "example", "name", "<name>", "<user>", "$user", "${user}"}
SLASH = r"(?:/|\\/)"
PATH_SHAPE = re.compile(SLASH + r"(?:users|home)" + SLASH
                        + r"(\$\{[A-Za-z_]+\}|<[^<>/\\\s]+>|\$?[A-Za-z0-9_-][A-Za-z0-9._-]*)" + SLASH, re.I)
# In file content a home folder may also end the path (a line end, a quote, "=", ":"), as long as
# nothing path-like stands before it; "$root/home/x" is a repository folder, not a home folder.
CONTENT_SHAPE = re.compile(r"(?<![A-Za-z0-9_.~$}\\-])" + SLASH + r"(?:users|home)" + SLASH
                           + r"(\$\{[A-Za-z_]+\}|<[^<>/\\\s]+>|\$?[A-Za-z0-9_-][A-Za-z0-9._-]*)(?![A-Za-z0-9._-])", re.I)
TEXT_CONTROLS = set("\t\n\r\f\v")

root, installer, checker, pusher = sys.argv[1:5]


def load(name, path):
    loader = SourceFileLoader(name, path)
    module = module_from_spec(spec_from_loader(loader.name, loader))
    loader.exec_module(module)
    return module


def term_files():
    if os.environ.get("PRIVACY_TERMS"):
        given = Path(os.environ["PRIVACY_TERMS"])
        if not given.is_file():
            print(f"privacy: PRIVACY_TERMS names no file: {given}", file=sys.stderr)
            sys.exit(2)
        return [given]
    install = load("ctlhq_install", installer)
    home = Path(os.path.realpath(os.path.expanduser("~")))
    if not (home / install.SETTINGS).is_file():
        return []
    try:
        layers = install.load_settings(home).layers
    except ValueError as e:
        print(f"privacy: {e}", file=sys.stderr)
        sys.exit(2)
    return [layer / "privacy" / "private-terms.txt" for layer in layers]


words = []
for terms_file in term_files():
    if terms_file.is_file():
        with open(terms_file, encoding="utf-8") as fh:
            words += [w.strip() for w in fh if w.strip() and not w.strip().startswith("#")]
word_re = None
if words:
    alternatives = "|".join(re.escape(w) for w in sorted(words, key=len, reverse=True))
    word_re = re.compile(r"(?<![^\W\d_])(?:" + alternatives + r")(?![^\W\d_])", re.I)

push = load("ctlhq_push", pusher)
try:
    owner = push.read_github_owner(push.settings_file())
except ValueError as e:
    print(f"privacy: {e}", file=sys.stderr)
    sys.exit(2)
owner_re = re.compile(rf"github\.com[/:](?ai:{re.escape(owner)})(?![\w-])", re.I) if owner else None


def unowned(text):
    """text without the owner's own GitHub address."""
    return owner_re.sub("", text) if owner_re else text


def private_homes(text):
    return [m for m in PATH_SHAPE.finditer(text) if m.group(1).lower() not in ALLOWED_NAMES]


def content_homes(text):
    return private_homes(text) + [m for m in CONTENT_SHAPE.finditer(text) if m.group(1).lower() not in ALLOWED_NAMES]


def shown(rel):
    """rel with every private word and home folder name replaced, so it is safe to print."""
    text = "/" + rel
    for m in reversed(private_homes(text)):
        text = text[:m.start(1)] + "<name>" + text[m.end(1):]
    if word_re:
        text = word_re.sub("<private word>", text)
    return text[1:]


def utf16_text(data):
    """The text of a UTF-16 file, or None when data is not UTF-16 text."""
    if data[:2] in (b"\xff\xfe", b"\xfe\xff"):
        encoding = "utf-16"
    else:
        odd_nuls = data[1::2].count(0)
        encoding = "utf-16-le" if odd_nuls >= data[0::2].count(0) else "utf-16-be"
    try:
        text = data.decode(encoding)
    except UnicodeDecodeError:
        return None
    for c in text:
        if c not in TEXT_CONTROLS and unicodedata.category(c) in ("Cc", "Cs", "Co", "Cn"):
            return None
    return text


def readme_exempt(lines):
    """0-based indexes of the README credit section, as bin/ctlhq-check finds it."""
    check = load("ctlhq_check", checker)
    credits = check.level2_sections(lines).get(check.CREDITS, range(1, 1))
    return range(credits.start - 1, credits.stop - 1)


listed = subprocess.run(["git", "-C", root, "ls-files", "-z"], capture_output=True, check=True).stdout
hits = []
named = set()
skipped = 0
for rel in sorted(p for p in listed.decode("utf-8", "replace").split("\0") if p):
    if rel == "LICENSE":
        continue
    parts = rel.split("/")
    for depth in range(1, len(parts) + 1):
        prefix = "/".join(parts[:depth])
        if word_re and prefix not in named and word_re.search(unowned(parts[depth - 1])):
            named.add(prefix)
            hits.append(f"{shown(prefix)}: private word in name")
    for m in private_homes("/" + rel):
        folder = ("/" + rel)[1:m.end()]
        if folder not in named:
            named.add(folder)
            hits.append(f"{shown(folder)}: home-folder path in name")
    path = os.path.join(root, rel)
    if os.path.islink(path):
        lines = [os.readlink(path)]
    elif os.path.isfile(path):
        with open(path, "rb") as fh:
            data = fh.read()
        text = utf16_text(data) if b"\0" in data else data.decode("utf-8", "replace")
        if text is None:
            skipped += 1
            continue
        lines = text.splitlines()
    else:
        continue
    skip = readme_exempt(lines) if rel == "README.md" else range(0)
    for i, line in enumerate(lines):
        if i in skip:
            continue
        if content_homes(line):
            hits.append(f"{shown(rel)}:{i + 1}: home-folder path")
        if word_re and word_re.search(unowned(line)):
            hits.append(f"{shown(rel)}:{i + 1}: private word")

for h in hits:
    print(h)
print(f"privacy: binary files skipped (not UTF-8 or UTF-16 text): {skipped}", file=sys.stderr)
sys.exit(1 if hits else 0)
PY
}

tmp="$(mktemp -d "${TMPDIR:-/tmp}/privacy-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
fail=0
control() { echo "privacy: control failed: $1"; fail=1; }
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
terms_override="${PRIVACY_TERMS-}"
unset PRIVACY_TERMS
encode() { python3 -I -c 'import sys; open(sys.argv[1], "wb").write(sys.argv[2].encode(sys.argv[3]))' "$@"; }

# The planted values are built from pieces so this file never matches its own scan.
planted_word="zeb""rafinch"
upper_word="$(printf '%s' "$planted_word" | tr '[:lower:]' '[:upper:]')"
person="planted-""person"
owner="${planted_word}42"
upper_owner="$(printf '%s' "$owner" | tr '[:lower:]' '[:upper:]')"
users="Us""ers"
planted_path="/$users/$person/notes.txt"
repo="$tmp/repo"
layer="$tmp/layer"
mkdir -p "$repo/docs" "$repo/$planted_word" "$repo/fixtures/$users/$person" "$tmp/home/.ctlhq" "$tmp/empty-home" "$tmp/bad-home/.ctlhq" "$tmp/no-owner-home/.ctlhq" "$tmp/bad-owner-home/.ctlhq" "$layer/skills" "$layer/privacy"
git -C "$repo" init -q
printf '# Demo\n\nPlain text.\n' >"$repo/README.md"
printf 'one\nthe %s project\n' "$upper_word" >"$repo/docs/a.md"
printf 'open %s now\nsee /Users/you/x and /home/<name>/y\n' "$planted_path" >"$repo/docs/b.md"
{
	printf '/System/Volumes/Data/%s/%s/x\n' "$users" "$person"
	printf '/Volumes/Data/%s/%s/z\n' "$users" "$person"
	printf '/users/%s/x\n' "$person"
	printf '"\\/%s\\/%s\\/x"\n' "$users" "$person"
	printf '/HOME/%s/x\n' "$person"
	printf '"\\/%s\\/<you>\\/x" and /USERS/you/x and /home/.config/x\n' "$users"
} >"$repo/docs/c.md"
printf '%s2\n%s_v2\nx%s\n' "$planted_word" "$planted_word" "$planted_word" >"$repo/docs/d.md"
{
	printf 'cd /%s/%s\n' "$users" "$person"
	printf '{"path": "/%s/%s"}\n' "$users" "$person"
	printf 'HOME=/home/%s: set\n' "$person"
	printf '| /%s/%s | cell |\n' "$users" "$person"
	printf 'cat "$root/home/AGENTS.md" and $tmp/home/.ctlhq and /Users/you\n'
} >"$repo/docs/i.md"
{
	printf 'clone https://github.com/%s/x and git@github.com:%s/y.git\n' "$upper_owner" "$owner"
	printf 'the %s and https://github.com/%s/x\n' "$planted_word" "$owner"
	printf 'https://github.com/%sextra/z\n' "$owner"
} >"$repo/docs/j.md"
printf 'clean\n' >"$repo/docs/github.com:$owner.md"
printf 'clean\n' >"$repo/docs/$upper_word-notes.md"
printf 'clean\n' >"$repo/$planted_word/readme.md"
printf 'clean\n' >"$repo/fixtures/$users/$person/x.md"
encode "$repo/docs/e.txt" "first
the $planted_word
" utf-16
encode "$repo/docs/f.txt" "$planted_word
" utf-16-le
encode "$repo/docs/g.txt" "x
$planted_word
" utf-16-be
printf '\211PNG\r\n\032\n\000\000\000\rIHDR %s\n' "$planted_word" >"$repo/docs/h.bin"
printf 'a %s inside LICENSE\n' "$planted_word" >"$repo/LICENSE"
printf '# a comment line\n\n%s\n' "$planted_word" >"$layer/privacy/private-terms.txt"
printf 'layers = ["%s", "%s"]\n' "$(cd "$here/../.." && pwd)" "$layer" >"$tmp/home/.ctlhq/layers.toml"
printf 'layers = "not a list"\n' >"$tmp/bad-home/.ctlhq/layers.toml"
printf 'github_owner = "%s"  # the account\n' "$owner" >"$tmp/home/.ctlhq/first-push.toml"
printf 'other = "x"\n' >"$tmp/no-owner-home/.ctlhq/first-push.toml"
printf 'github_owner = %s\n' "$owner" >"$tmp/bad-owner-home/.ctlhq/first-push.toml"
git -C "$repo" add -A

expected='docs/<private word>-notes.md: private word in name
docs/a.md:2: private word
docs/b.md:1: home-folder path
docs/c.md:1: home-folder path
docs/c.md:2: home-folder path
docs/c.md:3: home-folder path
docs/c.md:4: home-folder path
docs/c.md:5: home-folder path
docs/d.md:1: private word
docs/d.md:2: private word
docs/e.txt:2: private word
docs/f.txt:1: private word
docs/g.txt:2: private word
docs/i.md:1: home-folder path
docs/i.md:2: home-folder path
docs/i.md:3: home-folder path
docs/i.md:4: home-folder path
docs/j.md:2: private word
docs/j.md:3: private word
fixtures/Users/<name>/: home-folder path in name
<private word>: private word in name'
out="$(HOME="$tmp/home" scan "$repo" 2>"$tmp/err")"; rc=$?
[ "$rc" -eq 1 ] || control "planted words and paths exit 1 (got $rc)"
[ "$(printf '%s\n' "$out" | LC_ALL=C sort)" = "$(printf '%s\n' "$expected" | LC_ALL=C sort)" ] ||
	control "content, name, shape, boundary, and UTF-16 hits are exactly the expected 21 (got: $out)"
printf '%s\n' "$out" | grep -qi "$planted_word" && control "the planted word is never printed"
printf '%s\n' "$out" | grep -q "$person" && control "the planted home folder name is never printed"
printf '%s\n' "$out" | grep -q 'docs/d.md:3' && control "a word with a letter before it does not match"
printf '%s\n' "$out" | grep -q 'docs/c.md:6' && control "placeholder home paths and dot folders are allowed in every form"
printf '%s\n' "$out" | grep -q 'LICENSE' && control "LICENSE is exempt"
printf '%s\n' "$out" | grep -q 'docs/j.md:1' && control "the word inside the owner's GitHub address is not reported, in any case or the SSH form"
printf '%s\n' "$out" | grep -q '^docs/github' && control "the word inside the owner's GitHub address in a file name is not reported"
grep -qx 'privacy: binary files skipped (not UTF-8 or UTF-16 text): 1' "$tmp/err" || control "the binary file is counted as skipped (got: $(cat "$tmp/err"))"

out="$(HOME="$tmp/empty-home" scan "$repo" 2>/dev/null)"; rc=$?
[ "$rc" -eq 1 ] || control "without a word list the planted paths still exit 1 (got $rc)"
printf '%s\n' "$out" | grep -q 'private word' && control "without a layers file no word is reported"
printf '%s\n' "$out" | grep -qx 'fixtures/Users/<name>/: home-folder path in name' || control "without a word list a home folder in a path is reported"

out="$(HOME="$tmp/empty-home" PRIVACY_TERMS="$layer/privacy/private-terms.txt" scan "$repo" 2>/dev/null)"
printf '%s\n' "$out" | grep -qx 'docs/a.md:2: private word' || control "PRIVACY_TERMS supplies the words without a layers file"
printf '%s\n' "$out" | grep -qx 'docs/j.md:1: private word' || control "without a first-push.toml the owner's address line is reported"
out="$(HOME="$tmp/no-owner-home" PRIVACY_TERMS="$layer/privacy/private-terms.txt" scan "$repo" 2>/dev/null)"
printf '%s\n' "$out" | grep -qx 'docs/j.md:1: private word' || control "without a github_owner line the owner's address line is reported"

HOME="$tmp/bad-owner-home" scan "$repo" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] || control "an unreadable github_owner line exits 2 (got $rc)"

HOME="$tmp/empty-home" PRIVACY_TERMS="$tmp/no-such-file" scan "$repo" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] || control "a PRIVACY_TERMS file that does not exist exits 2 (got $rc)"

HOME="$tmp/bad-home" scan "$repo" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] || control "an unreadable layers.toml exits 2 (got $rc)"

git -C "$repo" rm -rq --cached docs fixtures "$planted_word"
rm -rf "${repo:?}/docs" "${repo:?}/fixtures" "${repo:?}/${planted_word:?}"
printf '# Demo\n\n## Credits\n\nThanks to %s.\n\n## Next\n\n%s again\n' "$planted_word" "$planted_word" >"$repo/README.md"
git -C "$repo" add -A
out="$(HOME="$tmp/home" scan "$repo" 2>/dev/null)"; rc=$?
[ "$rc" -eq 1 ] || control "a word after the credit section exits 1 (got $rc)"
[ "$out" = "README.md:9: private word" ] || control "only the line after the '## Credits' section is reported (got: $out)"
printf '# Demo\n\n```text\n## Credits\n```\n\nThanks to %s.\n' "$planted_word" >"$repo/README.md"
out="$(HOME="$tmp/home" scan "$repo" 2>/dev/null)"
[ "$out" = "README.md:7: private word" ] || control "a '## Credits' line inside fenced code exempts nothing (got: $out)"

printf 'clean text\n' >"$repo/README.md"
git -C "$repo" add -A
HOME="$tmp/home" scan "$repo" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] || control "a clean repository exits 0 (got $rc)"

[ "$fail" -eq 0 ] || exit 1

out="$(PRIVACY_TERMS="$terms_override" scan "$root")"; rc=$?
[ "$rc" -eq 2 ] && exit 2
if [ "$rc" -ne 0 ]; then
	printf '%s\n' "$out"
	echo "privacy: $(printf '%s\n' "$out" | wc -l | tr -d ' ') hits"
	exit 1
fi
echo "privacy: 0 hits"
