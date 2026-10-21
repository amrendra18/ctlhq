#!/usr/bin/env bash
# tests/ctlhq-browser/run.sh: checks for bin/ctlhq-browser against a local test site on 127.0.0.1.
# Prints "N checks passed" and exits 1 when any check fails. Writes only to a temp folder.
# Every wait polls for its condition with a generous deadline, so a loaded machine gets more
# time; nothing is retried, so a condition that never comes true still fails.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
fb="$root/bin/ctlhq-browser"
pass=0
fail=0
ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL: $1"; }
expect_rc() { if [ "$1" -eq "$2" ]; then ok; else bad "$3 (expected exit $1, got $2)"; fi; }
expect_eq() { if [ "$1" = "$2" ]; then ok; else bad "$3 (expected '$1', got '$2')"; fi; }
expect_grep() { if printf '%s\n' "$2" | grep -Eq -- "$1"; then ok; else bad "$3 (no line matches: $1)"; fi; }
expect_nogrep() { if printf '%s\n' "$2" | grep -Eq -- "$1"; then bad "$3 (a line matches: $1)"; else ok; fi; }

chrome="${CTLHQ_CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
tmp="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/ctlhq-browser-test.XXXXXX")" && pwd -P)"
site_pid=""
ext_pid=""
cleanup() {
	[ -n "$site_pid" ] && kill "$site_pid" 2>/dev/null
	[ -n "$ext_pid" ] && kill "$ext_pid" 2>/dev/null && wait "$ext_pid" 2>/dev/null
	rm -rf "$tmp"
}
trap cleanup EXIT
export TMPDIR="$tmp/t"   # the tool's own Chrome profiles land here, so leftovers are countable
mkdir -p "$TMPDIR"
# wait_for <seconds> <what> <command...>: run the command every 0.1 s until it succeeds; after
# <seconds> print a FAIL line naming <what> and return 1.
wait_for() {
	local secs="$1" what="$2" end
	shift 2
	end=$(( $(date +%s) + secs ))
	until "$@"; do
		if [ "$(date +%s)" -ge "$end" ]; then echo "FAIL: $what did not happen within $secs s"; return 1; fi
		sleep 0.1
	done
}
leftovers() { # processes and profiles of Chromes the tool started
	local procs dirs
	procs="$(pgrep -f "$TMPDIR/ctlhq-browser-" | wc -l | tr -d ' ')"
	dirs="$(find "$TMPDIR" -maxdepth 1 -name 'ctlhq-browser-*' | wc -l | tr -d ' ')"
	echo "$procs $dirs"
}

python3 "$here/pages.py" "$tmp/port" & site_pid=$!
wait_for 60 "the test site writing its port" test -s "$tmp/port" || { echo "0 checks passed"; exit 1; }
port="$(cat "$tmp/port")"
site="http://127.0.0.1:$port"

# An outside Chrome the tool did not start; it runs through every check below and must survive them all.
"$chrome" --headless --remote-debugging-port=0 --user-data-dir="$tmp/ext" --no-first-run --no-default-browser-check --use-mock-keychain about:blank >/dev/null 2>&1 & ext_pid=$!
wait_for 120 "the outside Chrome opening its debugging port" test -s "$tmp/ext/DevToolsActivePort" || { echo "0 checks passed"; exit 1; }
eport="$(head -1 "$tmp/ext/DevToolsActivePort")"

# 1. --help and usage errors.
out="$("$fb" --help 2>&1)"; expect_rc 0 $? "--help exits 0"
expect_grep '^ctlhq-browser: ' "$(printf '%s\n' "$out" | head -1)" "--help first line is 'ctlhq-browser: ...'"
"$fb" >/dev/null 2>&1; expect_rc 2 $? "no subcommand exits 2"
"$fb" paint "$site/" >/dev/null 2>&1; expect_rc 2 $? "unknown subcommand exits 2"
"$fb" screenshot "$site/" >/dev/null 2>&1; expect_rc 2 $? "screenshot without --out exits 2"
"$fb" trace "$site/" --out "$tmp/x.json" >/dev/null 2>&1; expect_rc 2 $? "trace without --seconds exits 2"
"$fb" screenshot "$site/" --size big --out "$tmp/x.png" >/dev/null 2>&1; expect_rc 2 $? "bad --size exits 2"
"$fb" console not-a-url >/dev/null 2>&1; expect_rc 2 $? "a bad URL exits 2"

png_size() { python3 -c 'import struct,sys; b=open(sys.argv[1],"rb").read(24); print("%dx%d" % struct.unpack(">II", b[16:24]) if b[:8]==b"\x89PNG\r\n\x1a\n" else "not-png")' "$1"; }

# 2. screenshot at a window size; control: another size gives other dimensions.
"$fb" screenshot "$site/" --size 800x600 --out "$tmp/shots/a.png" 2>/dev/null; expect_rc 0 $? "screenshot exits 0"
expect_eq 800x600 "$(png_size "$tmp/shots/a.png")" "screenshot is an 800x600 PNG"
"$fb" screenshot "$site/clean" --size 640x480 --out "$tmp/shots/b.png" 2>/dev/null
expect_eq 640x480 "$(png_size "$tmp/shots/b.png")" "control: --size 640x480 gives a 640x480 PNG"

# 3. console: the planted error is reported and exits 1; control: the clean page exits 0 with no error.
out="$("$fb" console "$site/" 2>/dev/null)"; expect_rc 1 $? "console on the planted page exits 1"
expect_grep '"level":"error","source":"console","text":"planted-console-error 42"' "$out" "planted console error reported"
expect_grep '"level":"warning","source":"console","text":"planted-console-warning"' "$out" "planted warning reported"
expect_grep '"source":"log:network".*missing\.png' "$out" "the 404 image is reported from the browser log"
expect_eq "" "$(printf '%s\n' "$out" | python3 -c 'import json,sys; [json.loads(l) for l in sys.stdin if l.strip()]' 2>&1)" "every console line is JSON"
out="$("$fb" console "$site/clean" 2>/dev/null)"; expect_rc 0 $? "control: console on the clean page exits 0"
expect_nogrep '"level":"error"' "$out" "control: clean page has no error line"

# 4. network: the slow request is slow; control: the document itself is fast; the 404 is recorded.
"$fb" network "$site/" --out "$tmp/net.json" 2>/dev/null; expect_rc 0 $? "network exits 0"
res="$(python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
by = {r["url"].rsplit("/", 1)[-1]: r for r in d["requests"]}
print(by["slow.js"]["duration_ms"] >= 700, by[""]["duration_ms"] < 700, by["missing.png"]["status"], by[""]["status"])
' "$tmp/net.json" 2>&1)"
expect_eq "True True 404 200" "$res" "slow.js took 700 ms or more, the document under 700 ms, 404 and 200 recorded"

# 5. trace: valid trace JSON with the page's performance mark; control: the clean page has no mark.
"$fb" trace "$site/" --seconds 1 --out "$tmp/trace.json" 2>/dev/null; expect_rc 0 $? "trace exits 0"
marks() { python3 -c '
import json, sys
d = json.load(open(sys.argv[1])); ev = d["traceEvents"] if isinstance(d, dict) else d
print(len(ev) > 100, sum(1 for e in ev if e.get("name") == "ctlhq-mark"))
' "$1" 2>&1; }
res="$(marks "$tmp/trace.json")"
expect_grep '^True [1-9]' "$res" "trace has over 100 events and the ctlhq-mark event ($res)"
"$fb" trace "$site/clean" --seconds 1 --out "$tmp/trace-clean.json" 2>/dev/null
expect_eq "True 0" "$(marks "$tmp/trace-clean.json")" "control: the clean page trace has no ctlhq-mark"

# 6. heap: the growing array shows as 5,000 or more CtlhqGrowing objects; control: none on the clean page.
growing() { python3 -c '
import json, sys
d = json.load(open(sys.argv[1])); m = d["snapshot"]["meta"]; f = m["node_fields"]; n = len(f)
ti, ni = f.index("type"), f.index("name"); types = m["node_types"][0]; s = d["strings"]; nodes = d["nodes"]
print(sum(1 for i in range(0, len(nodes), n) if s[nodes[i + ni]] == "CtlhqGrowing" and types[nodes[i + ti]] == "object"))
' "$1" 2>&1; }
"$fb" heap "$site/" --out "$tmp/a.heapsnapshot" 2>/dev/null; expect_rc 0 $? "heap exits 0"
res="$(growing "$tmp/a.heapsnapshot")"
if [ "$res" -ge 5000 ] 2>/dev/null; then ok; else bad "heap holds 5000 or more CtlhqGrowing objects (got $res)"; fi
"$fb" heap "$site/clean" --out "$tmp/b.heapsnapshot" 2>/dev/null
expect_eq 0 "$(growing "$tmp/b.heapsnapshot")" "control: the clean page heap has no CtlhqGrowing object"

# 7. A page that does not load exits 1 and names the error.
dead="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')"
err="$("$fb" screenshot "http://127.0.0.1:$dead/" --out "$tmp/dead.png" 2>&1)"; expect_rc 1 $? "a dead server exits 1"
expect_grep 'did not load: net::ERR_CONNECTION_REFUSED' "$err" "the load error is named"
[ -e "$tmp/dead.png" ] && bad "no file is written for a dead server" || ok

# 8. Every Chrome the tool started is gone, and so is its profile.
expect_eq "0 0" "$(leftovers)" "no Chrome process or profile left by the runs above"

# 8b. A helper process left in Chrome's process group is killed with the group.
cat >"$tmp/chrome-wrapper" <<WRAP
#!/bin/sh
sleep 300 &
echo \$! >"$tmp/helper.pid"
exec "$chrome" "\$@"
WRAP
chmod +x "$tmp/chrome-wrapper"
"$fb" --chrome "$tmp/chrome-wrapper" screenshot "$site/clean" --out "$tmp/w.png" 2>/dev/null; expect_rc 0 $? "a run through the wrapper exits 0"
[ -s "$tmp/helper.pid" ] && ok || bad "control: the wrapper started its helper"
kill -0 "$(cat "$tmp/helper.pid" 2>/dev/null || echo 0)" 2>/dev/null && bad "the helper in Chrome's group is gone after the run" || ok
kill -0 "$ext_pid" 2>/dev/null && ok || bad "the outside Chrome still runs after the tool's own runs"

# 9. SIGTERM during a run: exit 143, Chrome and profile gone.
"$fb" screenshot "$site/clean" --wait 60 --out "$tmp/never.png" 2>/dev/null & run_pid=$!
own_tab_open() { # the tool's own Chrome lists a tab at $site/clean, so the run is past navigation
	local f
	for f in "$TMPDIR"/ctlhq-browser-*/DevToolsActivePort; do
		[ -s "$f" ] || continue
		curl -s --max-time 5 "http://127.0.0.1:$(head -1 "$f")/json/list" | grep -Fq "\"url\": \"$site/clean\"" && return 0
	done
	return 1
}
wait_for 120 "the tool's Chrome opening $site/clean" own_tab_open || bad "the SIGTERM run reached its page"
running="$(leftovers)"
kill -TERM "$run_pid"; wait "$run_pid"; rc=$?
expect_rc 143 "$rc" "SIGTERM mid-run exits 143"
expect_grep '^[1-9][0-9]* 1$' "$running" "control: the tool's Chrome was running before SIGTERM ($running)"
expect_eq "0 0" "$(leftovers)" "no Chrome process or profile left after SIGTERM"

# 10. --attach uses the outside Chrome, closes only its own tab, and leaves that Chrome running.
tabs() { curl -s "http://127.0.0.1:$eport/json/list" | python3 -c 'import json,sys; print(sum(1 for t in json.load(sys.stdin) if t["type"]=="page"))'; }
before="$(tabs)"
out="$("$fb" --attach "$eport" console "$site/" 2>/dev/null)"; expect_rc 1 $? "--attach console exits 1 on the planted page"
expect_grep 'planted-console-error' "$out" "--attach reports the planted error"
kill -0 "$ext_pid" 2>/dev/null && ok || bad "the outside Chrome still runs after --attach"
tabs_back() { [ "$(tabs)" = "$before" ]; }
wait_for 30 "the outside Chrome's tab count returning to $before" tabs_back
expect_eq "$before" "$(tabs)" "--attach closed its own tab only"
expect_eq "0 0" "$(leftovers)" "--attach started no Chrome of its own"
"$fb" --attach "$dead" console "$site/" >/dev/null 2>&1; expect_rc 1 $? "control: --attach to a port with no Chrome exits 1"

echo "$pass checks passed"
if [ "$fail" -gt 0 ]; then
	echo "$fail checks failed"
	exit 1
fi
