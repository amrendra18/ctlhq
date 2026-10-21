#!/usr/bin/env bash
# tests/ctlhq-serve/run.sh: checks for bin/ctlhq-serve with local servers on 127.0.0.1.
# Prints "N checks passed" and exits 1 when any check fails. Writes only to a temp folder.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
fs="$root/bin/ctlhq-serve"
pass=0
fail=0
ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL: $1"; }
expect_rc() { if [ "$1" -eq "$2" ]; then ok; else bad "$3 (expected exit $1, got $2)"; fi; }
expect_eq() { if [ "$1" = "$2" ]; then ok; else bad "$3 (expected '$1', got '$2')"; fi; }
expect_grep() { if printf '%s\n' "$2" | grep -Eq -- "$1"; then ok; else bad "$3 (no line matches: $1)"; fi; }
alive() { kill -0 "$1" 2>/dev/null; }
group_alive() { python3 -c 'import os,sys
try: os.killpg(int(sys.argv[1]), 0)
except ProcessLookupError: sys.exit(1)' "$1"; }
free_port() { python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()'; }
field() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$1" "$2"; }

tmp="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/ctlhq-serve-test.XXXXXX")" && pwd -P)"
decoy=""
cleanup() {
	for f in "$tmp"/work/.local/serve/*.json; do
		[ -f "$f" ] && (cd "$tmp/work" && "$fs" stop --name "$(basename "$f" .json)" --grace 1 >/dev/null 2>&1)
	done
	[ -n "$decoy" ] && kill "$decoy" 2>/dev/null
	rm -rf "$tmp"
}
trap cleanup EXIT
mkdir -p "$tmp/work" "$tmp/site"
echo hello >"$tmp/site/index.html"
cd "$tmp/work" || exit 1
if git rev-parse --show-toplevel >/dev/null 2>&1; then echo "FAIL: the temp folder is inside a git work tree"; exit 1; fi
sd="$tmp/work/.local/serve"
sleep 300 & decoy=$!
disown "$decoy"

# 1. --help and usage errors.
out="$("$fs" --help 2>&1)"; expect_rc 0 $? "--help exits 0"
expect_grep '^ctlhq-serve: ' "$(printf '%s\n' "$out" | head -1)" "--help first line is 'ctlhq-serve: ...'"
"$fs" >/dev/null 2>&1; expect_rc 2 $? "no subcommand exits 2"
"$fs" restart --name a >/dev/null 2>&1; expect_rc 2 $? "unknown subcommand exits 2"
"$fs" start --name a --cwd . --ready-url http://127.0.0.1:1/ >/dev/null 2>&1; expect_rc 2 $? "start without a command exits 2"
"$fs" start --name a --cwd . -- true >/dev/null 2>&1; expect_rc 2 $? "start without --ready-url exits 2"
"$fs" start --name 'a/b' --cwd . --ready-url http://127.0.0.1:1/ -- true >/dev/null 2>&1; expect_rc 2 $? "bad --name exits 2"
"$fs" health >/dev/null 2>&1; expect_rc 2 $? "health without --name exits 2"
"$fs" start --name a --cwd "$tmp/nope" --ready-url http://127.0.0.1:1/ -- true >/dev/null 2>&1; expect_rc 2 $? "a missing --cwd exits 2"

# 2. start waits until ready; health, list.
p1="$(free_port)"
out="$("$fs" start --name web --cwd "$tmp/site" --ready-url "http://127.0.0.1:$p1/" -- python3 -m http.server "$p1" --bind 127.0.0.1 2>&1)"; rc=$?
expect_rc 0 "$rc" "start exits 0 once the server answers"
expect_grep "^ready web pid [0-9]+ http://127.0.0.1:$p1/$" "$out" "start prints the ready line"
[ -f "$sd/web.json" ] && [ -f "$sd/web.log" ] && ok || bad "state and log are under .local/serve/ of the current folder"
pid1="$(field "$sd/web.json" pid)"
expect_eq "hello" "$(curl -s "http://127.0.0.1:$p1/")" "the server keeps serving after start returns"
out="$("$fs" health --name web 2>&1)"; expect_rc 0 $? "health exits 0 for a live server"
expect_grep "^healthy web: http://127.0.0.1:$p1/ answered 200$" "$out" "health names the answer"
out="$("$fs" list 2>&1)"; expect_rc 0 $? "list exits 0"
expect_grep "^web +running +pid $pid1 " "$out" "list shows web running"
expect_eq "web running" "$("$fs" list --json | python3 -c 'import json,sys; r=json.load(sys.stdin)[0]; print(r["name"], r["state"])')" "list --json"
"$fs" start --name web --cwd "$tmp/site" --ready-url "http://127.0.0.1:$p1/" -- true >/dev/null 2>&1; expect_rc 1 $? "a second start of a running name exits 1"

# 3. stop kills only its own group: the server is gone, the decoy still runs.
out="$("$fs" stop --name web 2>&1)"; expect_rc 0 $? "stop exits 0"
expect_grep "^stopped web: stopped process group $pid1$" "$out" "stop names the group"
group_alive "$pid1" && bad "the server group is gone after stop" || ok
alive "$decoy" && ok || bad "control: a process the tool did not start still runs after stop"
[ -f "$sd/web.json" ] && bad "stop removes the state file" || ok
"$fs" health --name web >/dev/null 2>&1; expect_rc 1 $? "health of a stopped name exits 1"
"$fs" stop --name web >/dev/null 2>&1; expect_rc 1 $? "stop of an unknown name exits 1"

# 4. stop reaches a child the server started in its group.
p2="$(free_port)"
"$fs" start --name kids --cwd "$tmp/site" --ready-url "http://127.0.0.1:$p2/" -- sh -c "python3 -m http.server $p2 --bind 127.0.0.1 & wait" >/dev/null 2>&1; expect_rc 0 $? "start of a server with a child exits 0"
pg="$(field "$sd/kids.json" pgid)"
kids="$(pgrep -g "$pg" | wc -l | tr -d ' ')"
if [ "$kids" -ge 2 ]; then ok; else bad "control: the group holds the shell and its child before stop (got $kids)"; fi
"$fs" stop --name kids >/dev/null 2>&1; expect_rc 0 $? "stop kids exits 0"
expect_eq 0 "$(pgrep -g "$pg" | wc -l | tr -d ' ')" "no process of the group is left"

# 5. A server that ignores SIGTERM gets SIGKILL after --grace.
p3="$(free_port)"
"$fs" start --name stubborn --cwd "$tmp/site" --ready-url "http://127.0.0.1:$p3/" -- sh -c "trap '' TERM; exec python3 -m http.server $p3 --bind 127.0.0.1" >/dev/null 2>&1
out="$("$fs" stop --name stubborn --grace 0.5 2>&1)"; expect_rc 0 $? "stop of a SIGTERM-proof server exits 0"
expect_grep 'needed SIGKILL' "$out" "stop says it needed SIGKILL"

# 6. A server that never becomes ready times out with exit 1, and its process is stopped.
dead="$(free_port)"
start=$(date +%s)
err="$("$fs" start --name never --cwd "$tmp/site" --timeout 1.5 --ready-url "http://127.0.0.1:$dead/" -- sleep 300 2>&1)"; rc=$?
took=$(( $(date +%s) - start ))
expect_rc 1 "$rc" "a never-ready server exits 1"
expect_grep '^ctlhq-serve: never not ready after 1.5 s: ' "$err" "the timeout is named"
if [ "$took" -le 6 ]; then ok; else bad "the timeout ends the wait (took $took s)"; fi
npg="$(printf '%s\n' "$err" | sed -n 's/.*stopped process group \([0-9]*\).*/\1/p')"
[ -n "$npg" ] && ! group_alive "$npg" && ok || bad "the never-ready process is gone ($npg)"
[ -f "$sd/never.json" ] && bad "no state is left for a never-ready server" || ok

# 7. A server that exits before ready exits 1 and shows its log.
err="$("$fs" start --name boom --cwd "$tmp/site" --ready-url "http://127.0.0.1:$dead/" -- sh -c 'echo boom-line; exit 3' 2>&1)"; rc=$?
expect_rc 1 "$rc" "a server that exits early gives exit 1"
expect_grep 'boom exited with code 3 before' "$err" "the early exit code is named"
expect_grep '^  log: boom-line$' "$err" "the log tail is shown"

# 8. A dead server fails health; list shows it dead; stop clears it.
p4="$(free_port)"
"$fs" start --name dies --cwd "$tmp/site" --ready-url "http://127.0.0.1:$p4/" -- python3 -m http.server "$p4" --bind 127.0.0.1 >/dev/null 2>&1
"$fs" health --name dies >/dev/null 2>&1; expect_rc 0 $? "control: health exits 0 before the kill"
kill -9 "$(field "$sd/dies.json" pid)"; sleep 0.3
out="$("$fs" health --name dies 2>&1)"; expect_rc 1 $? "health of a killed server exits 1"
expect_grep '^unhealthy dies: process [0-9]+ is not running$' "$out" "health names the dead process"
expect_grep '^dies +dead ' "$("$fs" list)" "list shows dies dead"
out="$("$fs" stop --name dies 2>&1)"; expect_rc 0 $? "stop of a dead server exits 0"
expect_grep 'not running' "$out" "stop says it was not running"

# 9. A live process whose server stopped answering fails health.
p5="$(free_port)"
"$fs" start --name mute --cwd "$tmp/site" --timeout 3 --ready-url "http://127.0.0.1:$p5/" -- sh -c "python3 -m http.server $p5 --bind 127.0.0.1 & echo \$! > '$tmp/mute.child'; sleep 300" >/dev/null 2>&1
kill -9 "$(cat "$tmp/mute.child")"; sleep 0.3
out="$("$fs" health --name mute --timeout 1 2>&1)"; expect_rc 1 $? "health exits 1 when the URL stops answering"
expect_grep "^unhealthy mute: http://127.0.0.1:$p5/ did not answer" "$out" "health names the silent URL"
"$fs" stop --name mute >/dev/null 2>&1

# 10. A reused process number is never signalled.
printf '{"name":"reuse","pid":%s,"pgid":%s,"proc_start":"Thu Jan  1 00:00:00 1970","cwd":"%s","cmd":["x"],"ready_url":"http://127.0.0.1:%s/","started":"x","log":"x"}\n' "$decoy" "$decoy" "$tmp" "$dead" >"$sd/reuse.json"
out="$("$fs" stop --name reuse 2>&1)"; expect_rc 0 $? "stop of a reused number exits 0"
expect_grep 'now belongs to another process; nothing signalled' "$out" "stop refuses to signal a stranger"
alive "$decoy" && ok || bad "the stranger process still runs"

echo "$pass checks passed"
if [ "$fail" -gt 0 ]; then
	echo "$fail checks failed"
	exit 1
fi
