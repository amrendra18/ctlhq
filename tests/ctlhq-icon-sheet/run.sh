#!/usr/bin/env bash
# tests/ctlhq-icon-sheet/run.sh: checks for bin/ctlhq-icon-sheet (skills/design-options/bin/ctlhq-icon-sheet) on the
# fixture marks (marks/1-block.svg, marks/2-ring.svg) and palettes (palettes.json) in this folder.
# Part 1 needs no Chrome: usage errors exit 2, and marks or palettes that break the rules exit 1,
# each with a fix line. Part 2 renders with Chrome: the concepts round, the palette and typeface
# round, and an export; it prints a SKIP line instead when Chrome is missing.
# Prints "N checks passed" and exits 1 when any check fails. Writes only to a temp folder.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
is="$root/bin/ctlhq-icon-sheet"
png="$here/png.py"
pass=0
fail=0
ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL: $1"; }
expect_rc() { if [ "$1" -eq "$2" ]; then ok; else bad "$3 (expected exit $1, got $2)"; fi; }
expect_eq() { if [ "$1" = "$2" ]; then ok; else bad "$3 (expected '$1', got '$2')"; fi; }
expect_grep() { if printf '%s\n' "$2" | grep -Eq -- "$1"; then ok; else bad "$3 (no line matches: $1)"; fi; }
expect_nogrep() { if printf '%s\n' "$2" | grep -Eq -- "$1"; then bad "$3 (a line matches: $1)"; else ok; fi; }

tmp="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/icon-sheet-test.XXXXXX")" && pwd -P)"
trap 'rm -rf "$tmp"' EXIT
export TMPDIR="$tmp/t"   # Chrome profiles the tool starts land here, so leftovers are countable
mkdir -p "$TMPDIR"
marks="$here/marks"
pal="$here/palettes.json"
nochrome="$tmp/no-chrome"

# 1. Usage errors exit 2 with a fix line.
out="$("$is" --help 2>&1)"; expect_rc 0 $? "--help exits 0"
expect_grep '^ctlhq-icon-sheet: ' "$(printf '%s\n' "$out" | head -1)" "--help first line is 'ctlhq-icon-sheet: ...'"
usage() { # usage <label> <args...>: requires exit 2 and a fix line
	local label="$1" out rc
	shift
	out="$("$is" "$@" 2>&1)"; rc=$?
	expect_rc 2 "$rc" "$label exits 2"
	expect_grep '^fix: ' "$out" "$label prints a fix line"
}
usage "no subcommand"
usage "an unknown subcommand" paint --marks "$marks" --out "$tmp/x"
usage "an unknown option" review --marks "$marks" --out "$tmp/x" --colour red
usage "review without --out" review --marks "$marks"
usage "a missing marks folder" review --marks "$tmp/nowhere" --out "$tmp/x"
usage "--fonts without --palettes" review --marks "$marks" --out "$tmp/x" --fonts Futura
usage "--mark on review" review --marks "$marks" --mark "$marks/1-block.svg" --out "$tmp/x"
usage "export without --palette" export --mark "$marks/1-block.svg" --palettes "$pal" --out "$tmp/x"
usage "a missing palettes file" export --mark "$marks/1-block.svg" --palette red --palettes "$tmp/none.json" --out "$tmp/x"
[ -e "$tmp/x" ] && bad "no output folder is made on a usage error" || ok

# 2. Rule checks run before Chrome starts (--chrome points nowhere): exit 1, the rule named, a fix line.
rule() { # rule <label> <pattern> <args...>
	local label="$1" pat="$2" out rc
	shift 2
	out="$("$is" "$@" --chrome "$nochrome" 2>&1)"; rc=$?
	expect_rc 1 "$rc" "$label exits 1"
	expect_grep "$pat" "$out" "$label is named"
	expect_grep '^fix: ' "$out" "$label prints a fix line"
}
mk() { mkdir -p "$tmp/$1"; printf '%s\n' "$3" >"$tmp/$1/$2"; }
mk text 1-a.svg '<svg viewBox="0 0 64 64"><text fill="currentColor">Q</text></svg>'
rule "a mark with text" 'holds a <text> element' review --marks "$tmp/text" --out "$tmp/y"
mk nobox 1-a.svg '<svg width="64" height="64"><rect width="9" height="9" fill="currentColor"/></svg>'
rule "a mark without viewBox" 'has no viewBox' review --marks "$tmp/nobox" --out "$tmp/y"
mk fixed 1-a.svg '<svg viewBox="0 0 64 64"><rect width="9" height="9" fill="#ff0000"/></svg>'
rule "a mark with fixed colours only" 'uses no palette colour' review --marks "$tmp/fixed" --out "$tmp/y"
mkdir -p "$tmp/empty"
rule "an empty marks folder" 'no \.svg file' review --marks "$tmp/empty" --out "$tmp/y"
mk dup 1-a.svg '<svg viewBox="0 0 64 64"><rect width="9" height="9" fill="currentColor"/></svg>'
mk dup 1-b.svg '<svg viewBox="0 0 64 64"><circle r="9" fill="currentColor"/></svg>'
rule "two marks with one number" 'share the number 1' review --marks "$tmp/dup" --out "$tmp/y"
printf '[{"id": "red", "name": "Red", "accent": "red", "ink": "#000", "paper": "#fff"}]\n' >"$tmp/badcolour.json"
rule "a palette colour by name" 'accent "red"' review --marks "$marks" --palettes "$tmp/badcolour.json" --out "$tmp/y"
printf '[{"id": "red",\n' >"$tmp/notjson.json"
rule "a palettes file that is not JSON" 'not JSON' review --marks "$marks" --palettes "$tmp/notjson.json" --out "$tmp/y"
rule "an unknown palette id" 'no palette "blue"' export --mark "$marks/1-block.svg" --palette blue --palettes "$pal" --out "$tmp/y"
[ -e "$tmp/y" ] && bad "no output folder is made when a rule check fails" || ok
touch "$tmp/a-file"
out="$("$is" review --marks "$marks" --out "$tmp/a-file" 2>&1)"; expect_rc 2 $? "--out naming a file is a usage error before Chrome starts"
expect_grep '^fix: ' "$out" "--out naming a file prints a fix line"

chrome="${CTLHQ_CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
if [ ! -x "$chrome" ]; then
	echo "SKIP: Chrome not found at $chrome; the rendering checks did not run"
else
	px() { python3 "$png" pixel "$@"; }
	# Ctrl-C mid-run: exit 130, no misleading DevTools message, no Chrome left from this run.
	"$is" review --marks "$marks" --palettes "$pal" --out "$tmp/int" >"$tmp/int.log" 2>&1 &
	ipid=$!
	# Interrupt as soon as the first sample is written, so Chrome is mid-render.
	for _ in $(seq 1 200); do [ -n "$(ls "$tmp/int/png" 2>/dev/null)" ] && break; sleep 0.05; done
	kill -INT "$ipid"
	wait "$ipid"; expect_rc 130 $? "Ctrl-C during review exits 130"
	expect_nogrep 'DevTools' "$(cat "$tmp/int.log")" "Ctrl-C prints no DevTools connection error"
	sleep 1
	expect_eq "" "$(pgrep -f "$tmp/int" || true)" "Ctrl-C leaves no process of the interrupted run"
	size_of() { python3 "$png" size "$1"; }
	sizes_ok() { # sizes_ok <label> <file:size>...: each file exists and is a PNG of that square size
		local label="$1" item f s wrong=""
		shift
		for item in "$@"; do
			f="${item%:*}"; s="${item##*:}"
			[ "$(size_of "$f" 2>/dev/null)" = "${s}x${s}" ] || wrong="$wrong ${f##*/}"
		done
		expect_eq "" "$wrong" "$label: every PNG exists at its size"
	}

	# 3. Concepts round.
	c="$tmp/concepts"
	out="$("$is" review --marks "$marks" --out "$c" 2>&1)"; expect_rc 0 $? "concepts review exits 0"
	expect_grep 'index.html: 2 concept cards' "$out" "concepts review reports 2 cards"
	page="$(cat "$c/index.html" 2>/dev/null)"
	expect_grep '<h3>Concept 1</h3><span class="idea">A rounded block with a corner dot</span>' "$page" "card 1 is numbered and shows the mark's title"
	expect_grep '<h3>Concept 2</h3><span class="idea">A ring around an ink dot</span>' "$page" "card 2 is numbered and shows the mark's title"
	expect_nogrep 'Palette 1|Typeface 1' "$page" "control: the concepts round has no palette or typeface card"
	list=()
	for m in 1-block 2-ring; do
		list+=("$c/png/$m-128.png:128")
		for t in light dark; do for s in 16 24 32 48 64; do list+=("$c/png/$m-$t-$s.png:$s"); done; done
	done
	sizes_ok "concepts round (${#list[@]} PNGs)" "${list[@]}"
	expect_eq "22" "$(find "$c/png" -name '*.png' | wc -l | tr -d ' ')" "concepts round wrote exactly 22 PNGs"
	expect_eq "255,255,255,255" "$(px "$c/png/1-block-light-64.png" 0 0)" "the light tile corner is opaque white"
	expect_eq "17,20,24,255" "$(px "$c/png/1-block-dark-64.png" 0 0)" "the dark tile corner is opaque #111418"
	expect_eq "31,41,55,255" "$(px "$c/png/1-block-light-64.png" 32 40)" "the mark on the light tile is the neutral accent #1f2937"
	expect_eq "0" "$(px "$c/png/1-block-128.png" 0 0 | cut -d, -f4)" "the 128 px sample corner is transparent"
	expect_eq "1200x" "$(size_of "$c/review.png" | sed 's/x.*/x/')" "review.png is a PNG 1200 px wide"

	# 4. Palette and typeface round.
	p="$tmp/palettes"
	out="$("$is" review --marks "$marks" --palettes "$pal" --fonts "Futura,system-ui" --name "Fixture Name" --out "$p" 2>&1)"
	expect_rc 0 $? "palette review exits 0"
	expect_grep '4 palette cards, 2 typeface cards' "$out" "palette review reports 4 palette and 2 typeface cards"
	page="$(cat "$p/index.html" 2>/dev/null)"
	for id in concept-1-palette-1 concept-1-palette-2 concept-2-palette-1 concept-2-palette-2 typeface-1 typeface-2; do
		expect_grep "id=\"$id\"" "$page" "the page has card $id"
	done
	expect_grep '<h3>Palette 2</h3><span class="idea">Test Night</span>' "$page" "palette cards are numbered and named"
	expect_grep '<h3>Typeface 1</h3><span class="idea">Futura</span>' "$page" "typeface cards are numbered and named"
	expect_grep '>Fixture Name</span>' "$page" "the typeface cards show --name"
	list=()
	for m in 1-block 2-ring; do for q in red night; do
		list+=("$p/png/$m-$q-128.png:128")
		for t in light dark; do for s in 16 24 32 48 64; do list+=("$p/png/$m-$q-$t-$s.png:$s"); done; done
	done; done
	sizes_ok "palette round (${#list[@]} PNGs)" "${list[@]}"
	expect_eq "208,16,16,255" "$(px "$p/png/1-block-red-light-64.png" 32 40)" "palette red draws the mark in #d01010"
	expect_eq "48,192,240,255" "$(px "$p/png/1-block-night-light-64.png" 32 40)" "control: palette night draws the same mark in #30c0f0"
	expect_eq "1200x" "$(size_of "$p/review.png" | sed 's/x.*/x/')" "palette review.png is a PNG 1200 px wide"

	# 5. Export.
	e="$tmp/export"
	out="$("$is" export --mark "$marks/1-block.svg" --palette red --palettes "$pal" --out "$e" 2>&1)"; expect_rc 0 $? "export exits 0"
	list=()
	for s in 16 32 64 128 256 512 1024; do list+=("$e/icon-$s.png:$s"); done
	sizes_ok "export" "${list[@]}"
	corners=""
	for s in 16 32 64 128 256 512 1024; do
		last=$((s - 1))
		corners="$corners $(px "$e/icon-$s.png" 0 0 | cut -d, -f4)$(px "$e/icon-$s.png" "$last" "$last" | cut -d, -f4)"
	done
	expect_eq " 00 00 00 00 00 00 00" "$corners" "every export PNG has transparent corners"
	expect_eq "208,16,16,255" "$(px "$e/icon-1024.png" 512 640)" "control: the 1024 px export draws the mark in the palette accent"
	expect_eq "16 32 48" "$(python3 "$png" ico "$e/favicon.ico" 2>&1)" "favicon.ico holds 16, 32 and 48 px images"
	expect_grep '--accent:#d01010' "$(cat "$e/icon.svg" 2>/dev/null)" "icon.svg has the palette written in"
	if [ "$(uname)" = "Darwin" ] && [ -x /usr/bin/iconutil ]; then
		expect_eq "icns" "$(head -c 4 "$e/AppIcon.icns" 2>/dev/null)" "AppIcon.icns exists and starts with the icns tag"
	else
		expect_grep '^note: .*AppIcon.icns skipped' "$out" "without iconutil, a note line says AppIcon.icns was skipped"
	fi

	# 6. No Chrome profile is left behind.
	expect_eq "0" "$(find "$TMPDIR" -maxdepth 1 -name 'ctlhq-browser-*' | wc -l | tr -d ' ')" "no Chrome profile left by the runs above"
fi

echo "$pass checks passed"
if [ "$fail" -gt 0 ]; then
	echo "$fail checks failed"
	exit 1
fi
