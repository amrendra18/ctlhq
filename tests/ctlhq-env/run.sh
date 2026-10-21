#!/usr/bin/env bash
# tests/ctlhq-env/run.sh: checks for bin/ctlhq-env against fake tart and utmctl binaries.
# Prints "N checks passed" and exits 1 when any check fails. Starts no virtual machine.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
env_tool="$root/bin/ctlhq-env"
tmpbase="${TMPDIR:-/tmp}"; tmp="$(cd "$(mktemp -d "${tmpbase%/}/ctlhq-env-test.XXXXXX")" && pwd -P)"
trap 'rm -rf "$tmp"' EXIT
pass=0
fail=0
ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL: $1"; }
expect_rc() { # expected actual label
	if [ "$1" -eq "$2" ]; then ok; else bad "$3 (expected exit $1, got $2)"; fi
}
expect_eq() { # expected actual label
	if [ "$1" = "$2" ]; then ok; else bad "$3"; printf '  expected:\n%s\n  got:\n%s\n' "$1" "$2"; fi
}
expect_grep() { # pattern text label
	if printf '%s\n' "$2" | grep -Eq -- "$1"; then ok; else bad "$3 (no line matches: $1)"; fi
}
expect_no_grep() { # pattern text label
	if printf '%s\n' "$2" | grep -Eq -- "$1"; then bad "$3 (a line matches: $1)"; else ok; fi
}

# Fake tart and utmctl: each call appends "<name> <args>" to $FAKE_LOG. $FAKE_RULES holds
# "<glob><TAB><exit><TAB><stdout>" lines; the first glob that matches the call line wins.
mkdir -p "$tmp/bin" "$tmp/nobin"
cat > "$tmp/bin/tart" <<'FAKE'
#!/usr/bin/env bash
line="$(basename "$0") $*"
printf '%s\n' "$line" >> "$FAKE_LOG"
if [ -n "${FAKE_RULES:-}" ] && [ -f "$FAKE_RULES" ]; then
	while IFS=$'\t' read -r pat code out; do
		[ -n "$pat" ] || continue
		# shellcheck disable=SC2254
		case "$line" in $pat) printf '%b' "$out"; exit "$code" ;; esac
	done < "$FAKE_RULES"
fi
exit 0
FAKE
cp "$tmp/bin/tart" "$tmp/bin/utmctl"
cp "$tmp/bin/tart" "$tmp/bin/screencapture"
chmod +x "$tmp/bin/tart" "$tmp/bin/utmctl" "$tmp/bin/screencapture"
export FAKE_LOG="$tmp/calls.log" FAKE_RULES="$tmp/rules.tsv"
export CTLHQ_ENV_STATE="$tmp/state" CTLHQ_ENV_RUN_GRACE=2
unset CTLHQ_ENV_TART CTLHQ_ENV_UTMCTL CTLHQ_ENV_WAIT
PATH="$tmp/bin:/usr/bin:/bin"
export PATH
png_b64="iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="

reset() { : > "$FAKE_LOG"; printf '%s' "${1:-}" > "$FAKE_RULES"; }
calls() { cat "$FAKE_LOG"; }
fe() { "$env_tool" "$@"; }
TAB="$(printf '\t')"
list_running="[{\"Source\":\"local\",\"Name\":\"ubuntu\",\"Running\":true,\"State\":\"running\"},{\"Source\":\"OCI\",\"Name\":\"ghcr.io/cirruslabs/ubuntu:latest\",\"Running\":false,\"State\":\"stopped\"}]"
list_stopped="[{\"Source\":\"local\",\"Name\":\"ubuntu\",\"Running\":false,\"State\":\"stopped\"}]"
list_snap="[{\"Source\":\"local\",\"Name\":\"ubuntu\",\"Running\":true,\"State\":\"running\"},{\"Source\":\"local\",\"Name\":\"ubuntu-snap-before\",\"Running\":false,\"State\":\"stopped\"}]"

# 1. --help: first line, both real providers marked unproven, sources cited.
out="$(fe --help 2>&1)"; rc=$?
expect_rc 0 "$rc" "--help exits 0"
expect_grep '^ctlhq-env: ' "$(printf '%s\n' "$out" | head -1)" "--help first line is 'ctlhq-env: ...'"
expect_eq 2 "$(printf '%s\n' "$out" | grep -c 'UNPROVEN UNTIL THE HOST')" "tart and utm are both marked unproven until the host"
expect_grep 'https://tart.run/quick-start/' "$out" "--help cites the Tart documentation"
expect_grep 'https://docs.getutm.app/scripting/scripting/' "$out" "--help cites the UTM scripting documentation"
expect_grep 'utmapp/UTM/blob/v5.0.8/utmctl/UTMCtl.swift' "$out" "--help cites the utmctl source"

# 2. Recipes parse: five recipes with every required key.
out="$(fe list 2>&1)"; rc=$?
expect_rc 0 "$rc" "list exits 0"
expect_eq 5 "$(printf '%s\n' "$out" | grep -Ec '^[0-9]+\. ')" "list numbers 5 recipes"
json="$(fe --json list 2>/dev/null)"
expect_eq "macos-clean:tart:macos nas:tart:linux peer:tart:linux ubuntu:tart:linux windows:utm:windows" \
	"$(printf '%s' "$json" | python3 -c '
import json, sys
rows = json.load(sys.stdin)
keys = ("name", "provider", "guest", "image", "cpu", "memory_mb", "disk_gb", "network", "summary", "not_covered")
assert all(all(k in r for k in keys) and r["not_covered"] for r in rows), "missing key"
print(" ".join(r["name"] + ":" + r["provider"] + ":" + r["guest"] for r in rows))')" "list --json: names, providers, guests"
reset
fe list >/dev/null 2>&1
expect_eq "" "$(calls)" "list without --provider calls no provider"

# 3. Bad recipes exit 1 with the reason.
mkdir -p "$tmp/envs-bad"
printf 'name = "broken"\ncpu = [1, 2\n' > "$tmp/envs-bad/broken.toml"
err="$(fe --envs "$tmp/envs-bad" list 2>&1 >/dev/null)"; rc=$?
expect_rc 1 "$rc" "unterminated array exits 1"
expect_grep 'broken.toml: line [0-9]+: ' "$err" "parse error names the line"
rm "$tmp/envs-bad/broken.toml"
cp "$root/envs/ubuntu.toml" "$tmp/envs-bad/ubuntu.toml"
printf 'colour = "red"\n' >> "$tmp/envs-bad/ubuntu.toml"
err="$(fe --envs "$tmp/envs-bad" up ubuntu 2>&1 >/dev/null)"; rc=$?
expect_rc 1 "$rc" "unknown key exits 1"
expect_grep 'unknown key colour' "$err" "unknown key is named"
sed -e 's/^guest = .*/guest = "windows"/' -e '/^screenshot_cmd/d' "$root/envs/ubuntu.toml" > "$tmp/envs-bad/ubuntu.toml"
err="$(fe --envs "$tmp/envs-bad" up ubuntu 2>&1 >/dev/null)"; rc=$?
expect_rc 1 "$rc" "tart with a Windows guest exits 1"
expect_grep 'tart runs macOS and Linux guests only' "$err" "tart with Windows is refused"
grep -v '^disk_gb' "$root/envs/ubuntu.toml" > "$tmp/envs-bad/ubuntu.toml"
err="$(fe --envs "$tmp/envs-bad" up ubuntu 2>&1 >/dev/null)"; rc=$?
expect_rc 1 "$rc" "missing disk_gb exits 1"
expect_grep 'missing disk_gb' "$err" "missing key is named"

# 4. tart up on an absent machine: clone, set, run, ip, provision.
reset "tart list *${TAB}0${TAB}[]
tart ip *${TAB}0${TAB}192.168.64.5\n
"
out="$(fe up ubuntu 2>&1)"; rc=$?
expect_rc 0 "$rc" "tart up ubuntu exits 0"
expect_eq "tart list --format json
tart clone ghcr.io/cirruslabs/ubuntu:latest ubuntu
tart set ubuntu --cpu 4 --memory 4096 --disk-size 40
tart run --no-graphics ubuntu
tart ip ubuntu --wait 120
tart exec ubuntu sh -c sudo -n true" "$(calls)" "tart up ubuntu makes the expected calls"
expect_grep '^ubuntu: running \(tart\)  ip 192\.168\.64\.5$' "$out" "tart up prints state and IP"
expect_grep '^does not cover: ' "$out" "tart up prints what the recipe does not cover"
expect_grep 'ctlhq-env snapshot ubuntu <tag>' "$out" "tart up reminds about the snapshot before risky tests"
reset "tart list *${TAB}0${TAB}[]
tart ip *${TAB}0${TAB}192.168.64.6\n
"
fe up nas >/dev/null 2>&1; rc=$?
expect_rc 0 "$rc" "tart up nas exits 0"
expect_eq 6 "$(grep -c '^tart exec nas sh -c ' "$FAKE_LOG")" "tart up nas runs its 6 provision commands"
expect_grep "^tart exec nas sh -c printf '\[share\]\\\\n   path = /srv/share" "$(calls)" "TOML escapes reach the guest command"
reset "tart list *${TAB}0${TAB}[]
tart ip *${TAB}0${TAB}192.168.64.7\n
"
fe up macos-clean >/dev/null 2>&1
expect_grep '^tart set macos-clean --cpu 4 --memory 8192 --disk-size 80$' "$(calls)" "macos-clean sets its own size"
cp "$root/envs/ubuntu.toml" "$tmp/envs-bad/ubuntu.toml"
sed -i '' 's/^network = .*/network = "bridged:en0"/' "$tmp/envs-bad/ubuntu.toml"
reset "tart list *${TAB}0${TAB}[]
tart ip *${TAB}0${TAB}192.168.64.8\n
"
fe --envs "$tmp/envs-bad" up ubuntu >/dev/null 2>&1
expect_grep '^tart run --no-graphics --net-bridged=en0 ubuntu$' "$(calls)" "bridged network adds --net-bridged"

# 5. tart up on a running machine: no clone, no run.
reset "tart list *${TAB}0${TAB}$list_running
tart ip *${TAB}0${TAB}192.168.64.5\n
"
out="$(fe up ubuntu 2>&1)"; rc=$?
expect_rc 0 "$rc" "tart up on a running machine exits 0"
expect_eq "tart list --format json
tart ip ubuntu" "$(calls)" "tart up on a running machine only asks for the IP"

# 6. tart down.
reset "tart list *${TAB}0${TAB}$list_running
"
fe down ubuntu >/dev/null 2>&1; rc=$?
expect_rc 0 "$rc" "tart down exits 0"
expect_eq "tart list --format json
tart stop --timeout 60 ubuntu" "$(calls)" "tart down makes the expected calls"
reset "tart list *${TAB}0${TAB}$list_stopped
"
out="$(fe down ubuntu 2>&1)"; rc=$?
expect_rc 0 "$rc" "tart down on a stopped machine exits 0"
expect_eq "tart list --format json" "$(calls)" "tart down on a stopped machine does not stop again"
reset "tart list *${TAB}0${TAB}[]
"
err="$(fe down ubuntu 2>&1 >/dev/null)"; rc=$?
expect_rc 1 "$rc" "tart down on an absent machine exits 1"
expect_grep 'ubuntu is absent' "$err" "tart down names the absent machine"

# 7. tart snapshot: stop, clone, start again; a reused tag replaces the old clone.
reset "tart list *${TAB}0${TAB}$list_running
tart ip *${TAB}0${TAB}192.168.64.5\n
"
fe snapshot ubuntu before >/dev/null 2>&1; rc=$?
expect_rc 0 "$rc" "tart snapshot exits 0"
expect_eq "tart list --format json
tart stop --timeout 60 ubuntu
tart clone ubuntu ubuntu-snap-before
tart run --no-graphics ubuntu
tart ip ubuntu --wait 120" "$(calls)" "tart snapshot makes the expected calls"
reset "tart list *${TAB}0${TAB}$list_snap
tart ip *${TAB}0${TAB}192.168.64.5\n
"
fe snapshot ubuntu before >/dev/null 2>&1
expect_eq "tart list --format json
tart stop --timeout 60 ubuntu
tart delete ubuntu-snap-before
tart clone ubuntu ubuntu-snap-before
tart run --no-graphics ubuntu
tart ip ubuntu --wait 120" "$(calls)" "tart snapshot with a used tag deletes the old clone first"

# 8. tart restore.
reset "tart list *${TAB}0${TAB}$list_snap
tart ip *${TAB}0${TAB}192.168.64.5\n
"
fe restore ubuntu before >/dev/null 2>&1; rc=$?
expect_rc 0 "$rc" "tart restore exits 0"
expect_eq "tart list --format json
tart stop --timeout 60 ubuntu
tart delete ubuntu
tart clone ubuntu-snap-before ubuntu
tart run --no-graphics ubuntu
tart ip ubuntu --wait 120" "$(calls)" "tart restore makes the expected calls"
reset "tart list *${TAB}0${TAB}$list_snap
"
err="$(fe restore ubuntu nosuch 2>&1 >/dev/null)"; rc=$?
expect_rc 1 "$rc" "tart restore of an unknown tag exits 1"
expect_grep "no snapshot 'nosuch' \(snapshots: before\)" "$err" "unknown tag lists the known tags"
expect_eq "tart list --format json" "$(calls)" "unknown tag changes nothing"

# 9. tart exec: output and exit code pass through.
reset "tart exec ubuntu uname *${TAB}0${TAB}Linux\n
tart exec ubuntu false${TAB}7${TAB}
"
out="$(fe exec ubuntu -- uname -a 2>/dev/null)"; rc=$?
expect_rc 0 "$rc" "tart exec exits 0"
expect_eq "Linux" "$out" "tart exec passes the output through"
expect_eq "tart exec ubuntu uname -a" "$(calls)" "tart exec makes the expected call"
fe exec ubuntu -- false >/dev/null 2>&1; rc=$?
expect_rc 7 "$rc" "tart exec returns the command's exit code"
json="$(fe --json exec ubuntu -- uname -a 2>/dev/null)"
expect_eq "0 Linux" "$(printf '%s' "$json" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["exit"], d["stdout"].strip())')" "tart exec --json captures the output"

# 10. tart screenshot and status.
reset "tart exec macos-clean sh -c *${TAB}0${TAB}$png_b64\n
"
fe screenshot macos-clean --out "$tmp/shots/mac.png" >/dev/null 2>&1; rc=$?
expect_rc 0 "$rc" "tart screenshot exits 0"
expect_eq "tart exec macos-clean sh -c screencapture -x -t png /tmp/ctlhq-env-screen.png && base64 -i /tmp/ctlhq-env-screen.png" \
	"$(calls)" "tart screenshot runs the recipe's screenshot_cmd"
expect_eq "89504e470d0a1a0a" "$(head -c 8 "$tmp/shots/mac.png" | od -An -tx1 | tr -d ' \n')" "tart screenshot writes a PNG"
reset "tart exec macos-clean sh -c *${TAB}0${TAB}not-an-image\n
"
fe screenshot macos-clean --out "$tmp/shots/bad.png" >/dev/null 2>&1; rc=$?
expect_rc 1 "$rc" "screenshot output that is not a PNG exits 1"
reset
err="$(fe screenshot ubuntu --out "$tmp/shots/u.png" 2>&1 >/dev/null)"; rc=$?
expect_rc 1 "$rc" "screenshot of a recipe without screenshot_cmd exits 1"
expect_grep 'has no screenshot_cmd' "$err" "missing screenshot_cmd is named"
expect_eq "" "$(calls)" "missing screenshot_cmd makes no call"
reset "tart list *${TAB}0${TAB}$list_running
tart ip *${TAB}0${TAB}192.168.64.5\n
"
out="$(fe status ubuntu 2>&1)"; rc=$?
expect_rc 0 "$rc" "tart status exits 0"
expect_eq "tart list --format json
tart ip ubuntu" "$(calls)" "tart status makes the expected calls"
expect_grep '^ubuntu: running \(tart\)  ip 192\.168\.64\.5$' "$out" "tart status prints state and IP"
reset "tart list *${TAB}0${TAB}$list_running
"
out="$(fe --provider tart list 2>&1)"; rc=$?
expect_rc 0 "$rc" "list --provider tart exits 0"
expect_eq "tart list --format json" "$(calls)" "list --provider tart asks tart once"
expect_grep '^4\. ubuntu .* running ' "$out" "list --provider tart shows ubuntu running"

# 11. A failing call surfaces its exit code and stops the run.
reset "tart list *${TAB}0${TAB}[]
tart clone *${TAB}3${TAB}
"
err="$(fe up ubuntu 2>&1 >/dev/null)"; rc=$?
expect_rc 3 "$rc" "a failing tart clone exits 3"
expect_grep 'step 2 failed: tart clone ghcr.io/cirruslabs/ubuntu:latest ubuntu exited 3' "$err" "the failed call is named with its exit code"
expect_eq "tart list --format json
tart clone ghcr.io/cirruslabs/ubuntu:latest ubuntu" "$(calls)" "no call runs after the failure"
reset "tart list *${TAB}0${TAB}[]
tart run *${TAB}5${TAB}VM is locked\n
"
err="$(fe up ubuntu 2>&1 >/dev/null)"; rc=$?
expect_rc 5 "$rc" "a failing background tart run exits 5"
expect_grep 'tart run --no-graphics ubuntu exited 5: VM is locked' "$err" "the run log tail is shown"
reset "tart list *${TAB}0${TAB}[]
tart ip *${TAB}0${TAB}192.168.64.5\n
tart exec *${TAB}1${TAB}
"
fe up ubuntu >/dev/null 2>&1; rc=$?
expect_rc 1 "$rc" "a failing provision command exits 1"
json="$(fe --json up ubuntu 2>/dev/null)"
expect_eq "1 1" "$(printf '%s' "$json" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["exit"], d["steps"][-1]["exit"])')" "--json reports the failed step's exit code"

# 12. A missing binary exits 127 with an install hint.
reset
err="$(PATH="$tmp/nobin:/usr/bin:/bin" "$env_tool" up ubuntu 2>&1 >/dev/null)"; rc=$?
expect_rc 127 "$rc" "missing tart exits 127"
expect_grep 'tart not found on PATH\. Install it with: brew install cirruslabs/cli/tart' "$err" "missing tart gives the install hint"
err="$(CTLHQ_ENV_UTMCTL="$tmp/nobin/utmctl" "$env_tool" up windows 2>&1 >/dev/null)"; rc=$?
expect_rc 127 "$rc" "missing utmctl exits 127"
expect_grep 'https://mac\.getutm\.app' "$err" "missing utmctl gives the install hint"
if [ ! -e /Applications/UTM.app/Contents/MacOS/utmctl ]; then
	PATH="$tmp/nobin:/usr/bin:/bin" "$env_tool" up windows >/dev/null 2>&1; rc=$?
	expect_rc 127 "$rc" "utmctl missing from PATH and from /Applications exits 127"
fi
expect_eq "" "$(calls)" "a missing binary makes no call"

# 13. utm: every command against the fake utmctl.
reset "utmctl status *${TAB}1${TAB}
utmctl ip-address *${TAB}0${TAB}10.0.2.15\n
"
out="$(fe up windows 2>&1)"; rc=$?
expect_rc 0 "$rc" "utm up exits 0"
expect_eq "utmctl status windows
utmctl clone ctlhq-windows-template --name windows
utmctl start windows --hide
utmctl ip-address windows" "$(calls)" "utm up makes the expected calls"
expect_grep 'utmctl cannot set CPU, memory, disk, or network' "$out" "utm up says the template holds the size"
reset "utmctl status *${TAB}0${TAB}started\n
"
fe down windows >/dev/null 2>&1; rc=$?
expect_rc 0 "$rc" "utm down exits 0"
expect_eq "utmctl status windows
utmctl stop windows" "$(calls)" "utm down makes the expected calls"
reset "utmctl status *${TAB}0${TAB}started\n
utmctl snapshot list *${TAB}0${TAB}[]\n
"
fe snapshot windows t1 >/dev/null 2>&1; rc=$?
expect_rc 0 "$rc" "utm snapshot exits 0"
expect_eq "utmctl status windows
utmctl snapshot list windows --json
utmctl snapshot create windows --name t1" "$(calls)" "utm snapshot makes the expected calls"
reset "utmctl status *${TAB}0${TAB}started\n
utmctl snapshot list *${TAB}0${TAB}[{\"name\": \"t1\", \"id\": \"A\"}]\n
"
fe snapshot windows t1 >/dev/null 2>&1
expect_eq "utmctl status windows
utmctl snapshot list windows --json
utmctl snapshot overwrite windows --snapshot t1" "$(calls)" "utm snapshot with a used tag overwrites it"
fe restore windows t1 >/dev/null 2>&1; rc=$?
expect_rc 0 "$rc" "utm restore exits 0"
expect_eq "utmctl status windows
utmctl snapshot list windows --json
utmctl snapshot overwrite windows --snapshot t1
utmctl status windows
utmctl snapshot list windows --json
utmctl snapshot restore windows --snapshot t1" "$(calls)" "utm restore makes the expected calls"
reset "utmctl status *${TAB}0${TAB}started\n
utmctl snapshot list *${TAB}0${TAB}[\"old\"]\n
"
err="$(fe restore windows t1 2>&1 >/dev/null)"; rc=$?
expect_rc 1 "$rc" "utm restore of an unknown tag exits 1"
expect_grep "no snapshot 't1' \(snapshots: old\)" "$err" "utm reads the older name-list JSON too"
reset "utmctl exec windows --cmd cmd.exe *${TAB}4${TAB}Microsoft Windows\n
"
out="$(fe exec windows -- cmd.exe /c ver 2>/dev/null)"; rc=$?
expect_rc 4 "$rc" "utm exec returns the command's exit code"
expect_eq "Microsoft Windows" "$out" "utm exec passes the output through"
expect_eq "utmctl exec windows --cmd cmd.exe /c ver" "$(calls)" "utm exec makes the expected call"
reset "utmctl exec windows --cmd *${TAB}0${TAB}$png_b64\n
"
fe screenshot windows --out "$tmp/shots/win.png" >/dev/null 2>&1; rc=$?
expect_rc 0 "$rc" "utm screenshot exits 0"
expect_grep '^utmctl exec windows --cmd C:\\Windows\\System32\\WindowsPowerShell\\v1\.0\\powershell\.exe -NoProfile -NonInteractive -Command Add-Type ' "$(calls)" "utm screenshot runs PowerShell"
expect_eq "89504e470d0a1a0a" "$(head -c 8 "$tmp/shots/win.png" | od -An -tx1 | tr -d ' \n')" "utm screenshot writes a PNG"
reset "utmctl status *${TAB}0${TAB}started\n
utmctl ip-address *${TAB}0${TAB}10.0.2.15\n
"
out="$(fe status windows 2>&1)"; rc=$?
expect_rc 0 "$rc" "utm status exits 0"
expect_eq "utmctl status windows
utmctl ip-address windows" "$(calls)" "utm status makes the expected calls"
expect_grep '^windows: running \(utm\)  ip 10\.0\.2\.15$' "$out" "utm status prints state and IP"
reset "utmctl status *${TAB}1${TAB}
utmctl clone *${TAB}0${TAB}
utmctl start *${TAB}9${TAB}
"
err="$(fe up windows 2>&1 >/dev/null)"; rc=$?
expect_rc 9 "$rc" "a failing utmctl start exits 9"
expect_grep 'step 3 failed: utmctl start windows --hide exited 9' "$err" "the failed utmctl call is named"
reset "utmctl list${TAB}0${TAB}UUID                                 Status   Name\n0F3C-1 stopped  windows\n
"
out="$(fe --provider utm list 2>&1)"; rc=$?
expect_rc 0 "$rc" "list --provider utm exits 0"
expect_eq "utmctl list" "$(calls)" "list --provider utm asks utmctl once"
expect_grep '^5\. windows .* stopped ' "$out" "list --provider utm shows windows stopped"

# 14. fake provider: up, snapshot, restore, down round trip; it never calls a binary.
reset
fake_dir="$CTLHQ_ENV_STATE/fake"
out="$(fe --provider fake up ubuntu 2>&1)"; rc=$?
expect_rc 0 "$rc" "fake up exits 0"
expect_grep '^fake provider: no real machine was started' "$out" "fake up says it is the fake provider"
expect_grep '^ubuntu: running \(fake\)' "$out" "fake up reports the fake state"
expect_grep '^A real run with tart would take 6 steps:$' "$out" "fake up prints the real run's step count"
expect_grep '^  2\. tart clone ghcr\.io/cirruslabs/ubuntu:latest ubuntu$' "$out" "fake up prints the real clone step"
out="$(fe --provider fake snapshot ubuntu before 2>&1)"; rc=$?
expect_rc 0 "$rc" "fake snapshot exits 0"
expect_grep '^  3\. tart clone ubuntu ubuntu-snap-before$' "$out" "fake snapshot prints the real clone step"
out="$(fe --provider fake restore ubuntu before 2>&1)"; rc=$?
expect_rc 0 "$rc" "fake restore exits 0"
expect_grep '^  4\. tart clone ubuntu-snap-before ubuntu$' "$out" "fake restore prints the real clone-back step"
fe --provider fake restore ubuntu nosuch >/dev/null 2>&1; rc=$?
expect_rc 1 "$rc" "fake restore of an unknown tag exits 1"
out="$(fe --provider fake down ubuntu 2>&1)"; rc=$?
expect_rc 0 "$rc" "fake down exits 0"
expect_grep '^ubuntu: stopped \(fake\)$' "$out" "fake down stops the fake machine"
expect_eq "stopped before" "$(python3 -c 'import json,sys; m=json.load(open(sys.argv[1]))["machines"]["ubuntu"]; print(m["state"], ",".join(m["snapshots"]))' "$fake_dir/state.json")" "fake state holds the stopped machine and its snapshot"
expect_eq "up:0:absent:running snapshot:0:running:running restore:0:running:running restore:1:running:running down:0:running:stopped" \
	"$(python3 -c '
import json, sys
rows = [json.loads(l) for l in open(sys.argv[1])]
print(" ".join(":".join(str(r[k]) for k in ("op", "exit", "state_before", "state_after")) for r in rows))' "$fake_dir/calls.jsonl")" "fake log records every call in order"
expect_eq "" "$(calls)" "the fake provider calls no binary"
err="$(fe --provider fake exec ubuntu -- true 2>&1 >/dev/null)"; rc=$?
expect_rc 1 "$rc" "fake exec on a stopped machine exits 1"
expect_grep 'ubuntu is stopped \(fake\)' "$err" "fake exec names the stopped machine"
fe --provider fake down nas >/dev/null 2>&1; rc=$?
expect_rc 1 "$rc" "fake down of an absent machine exits 1"
fe --provider fake snapshot nas t1 >/dev/null 2>&1; rc=$?
expect_rc 1 "$rc" "fake snapshot of an absent machine exits 1"
fe --provider fake up ubuntu >/dev/null 2>&1
printf '{"exec": {"exit": 3, "stdout": "scripted out\\n"}, "up": {"exit": 9}}' > "$fake_dir/script.json"
out="$(fe --provider fake exec ubuntu -- whoami 2>/dev/null)"; rc=$?
expect_rc 3 "$rc" "fake exec returns the scripted exit code"
expect_eq "scripted out" "$out" "fake exec prints the scripted output"
fe --provider fake up nas >/dev/null 2>&1; rc=$?
expect_rc 9 "$rc" "a scripted fake up failure exits 9"
expect_eq "absent" "$(fe --provider fake --json status nas 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["state"])')" "a scripted failure leaves the state unchanged"
rm "$fake_dir/script.json"
fe --provider fake screenshot macos-clean --out "$tmp/shots/f.png" >/dev/null 2>&1; rc=$?
expect_rc 1 "$rc" "fake screenshot of a machine that is not up exits 1"
fe --provider fake up macos-clean >/dev/null 2>&1
fe --provider fake screenshot macos-clean --out "$tmp/shots/f.png" >/dev/null 2>&1; rc=$?
expect_rc 0 "$rc" "fake screenshot exits 0"
expect_eq "89504e470d0a1a0a" "$(head -c 8 "$tmp/shots/f.png" | od -An -tx1 | tr -d ' \n')" "fake screenshot writes a PNG"
out="$(fe --provider fake up windows 2>&1)"
expect_grep '^A real run with utm would take 4 steps:$' "$out" "fake up of a utm recipe prints the utmctl steps"
expect_eq "" "$(calls)" "the fake provider still calls no binary"

# 15. local provider.
out="$(fe --provider local up ubuntu 2>&1)"; rc=$?
expect_rc 0 "$rc" "local up exits 0"
expect_grep 'local provider: up does nothing' "$out" "local up says it does nothing"
out="$(fe --provider local down ubuntu 2>&1)"; rc=$?
expect_rc 0 "$rc" "local down exits 0"
expect_grep 'local provider: down does nothing' "$out" "local down says it does nothing"
out="$(fe --provider local exec ubuntu -- echo hello 2>/dev/null)"; rc=$?
expect_rc 0 "$rc" "local exec exits 0"
expect_eq "hello" "$out" "local exec runs on this machine"
fe --provider local exec ubuntu -- sh -c 'exit 6' >/dev/null 2>&1; rc=$?
expect_rc 6 "$rc" "local exec returns the command's exit code"
fe --provider local exec ubuntu -- no-such-command-here >/dev/null 2>&1; rc=$?
expect_rc 127 "$rc" "local exec of a missing command exits 127"
fe --provider local snapshot ubuntu t1 >/dev/null 2>&1; rc=$?
expect_rc 1 "$rc" "local snapshot exits 1"
reset
fe --provider local screenshot ubuntu --out "$tmp/shots/local.png" >/dev/null 2>&1; rc=$?
expect_rc 0 "$rc" "local screenshot exits 0 with a fake screencapture"
expect_eq "screencapture -x -t png $tmp/shots/local.png" "$(calls)" "local screenshot calls screencapture"

# 16. Usage errors exit 2; an unknown recipe exits 1.
fe >/dev/null 2>&1; expect_rc 2 $? "no command exits 2"
fe launch ubuntu >/dev/null 2>&1; expect_rc 2 $? "unknown command exits 2"
fe exec ubuntu >/dev/null 2>&1; expect_rc 2 $? "exec without -- exits 2"
fe screenshot ubuntu >/dev/null 2>&1; expect_rc 2 $? "screenshot without --out exits 2"
fe --provider vbox up ubuntu >/dev/null 2>&1; expect_rc 2 $? "unknown provider exits 2"
fe snapshot ubuntu 'bad tag' >/dev/null 2>&1; expect_rc 2 $? "bad tag exits 2"
fe --provider tart up windows >/dev/null 2>&1; expect_rc 2 $? "tart for the windows recipe exits 2"
fe up nosuch >/dev/null 2>&1; expect_rc 1 $? "unknown recipe exits 1"

if [ "$fail" -gt 0 ]; then
	echo "$fail checks failed, $pass checks passed"
	exit 1
fi
echo "$pass checks passed"
