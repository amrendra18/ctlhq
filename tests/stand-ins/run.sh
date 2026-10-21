#!/usr/bin/env bash
# tests/stand-ins/run.sh: checks for the three stand-ins in this folder (fake claude, fake gh,
# throwaway signing key), and for ctlhq-watch-pr's own TypeScript replayed on recorded GitHub
# responses through the fake gh (node runs it with tests/stand-ins/watch-pr-replay.mjs,
# because bun is not installed here).
# Every check group runs once on the real stand-in and then once per planted defect (a
# changed copy of the stand-in, or of a recording); each planted defect must make its group
# fail. The last check proves every group has at least one planted defect.
# Safety: every ssh-agent here is private (ssh-agent -a <socket under a temporary folder>),
# SSH_AUTH_SOCK is set only on single commands, all agents are killed at the end, and the
# operator's own agent key count must be the same before and after. Git configuration is
# local to scratch repositories; the global and system files are not read.
# Prints "N checks passed" and exits 1 when any check fails. Read-only for the repository.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
si="$here"
fix="$here/fixtures"
wpsrc="$root/skills/ctlhq-mode/scripts/watch-pr"
driver="$here/watch-pr-replay.mjs"
tmp="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/stand-ins-test.XXXXXX")" && pwd -P)"
# Agent sockets need a short path (macOS allows 104 bytes), so keys live under /tmp.
keys="$(cd "$(mktemp -d /tmp/sk.XXXXXX)" && pwd -P)"
sleeper=""
cleanup() {
	local pid
	for pid in $(ps -axo pid=,command= | awk -v k=" -a $keys/" 'index($0, k) && /ssh-agent/ {print $1}'); do
		kill "$pid" 2>/dev/null
	done
	[ -n "$sleeper" ] && kill "$sleeper" 2>/dev/null
	rm -rf "$tmp" "$keys"
}
trap cleanup EXIT
pass=0
fail=0
ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); [ -n "${quiet:-}" ] || echo "FAIL: $1"; }
expect_rc() { if [ "$1" -eq "$2" ]; then ok; else bad "$3 (expected exit $1, got $2)"; fi; }
expect_eq() { if [ "$1" = "$2" ]; then ok; else bad "$3 (expected '$1', got '$2')"; fi; }
expect_grep() { if printf '%s\n' "$2" | grep -Eq -- "$1"; then ok; else bad "$3 (no line matches: $1)"; fi; }
expect_has() { if printf '%s' "$2" | grep -Fq -- "$1"; then ok; else bad "$3 (missing: $1)"; fi; }

# The operator's agent: read with the inherited SSH_AUTH_SOCK only, never changed.
op_keys() {
	local out rc
	out="$(ssh-add -l 2>/dev/null)"; rc=$?
	case "$rc" in 0) printf '%s\n' "$out" | grep -c . ;; 1) echo 0 ;; *) echo "no-agent" ;; esac
}
op_before="$(op_keys)"
echo "operator agent keys before: $op_before"

n=0
newdir() { n=$((n + 1)); mkdir -p "$tmp/m/$n"; printf '%s' "$tmp/m/$n"; }
# plant SRC DEST OLD NEW: copy SRC to DEST with the one occurrence of OLD replaced by NEW.
plant() {
	mkdir -p "$(dirname "$2")"
	python3 - "$1" "$2" "$3" "$4" <<'PY'
import sys
src, dest, old, new = sys.argv[1:]
text = open(src, encoding="utf-8").read()
if text.count(old) != 1:
    sys.exit(f"plant: {old!r} occurs {text.count(old)} times in {src}")
open(dest, "w", encoding="utf-8").write(text.replace(old, new))
PY
	local rc=$?
	[ -x "$1" ] && chmod +x "$2"
	if [ "$rc" -eq 0 ]; then ok; else bad "plant into $2"; fi
}
# control LABEL GROUP ARGS...: GROUP must fail at least one check on the planted defect.
control() {
	local p0=$pass f0=$fail caught
	quiet=1; "$2" "${@:3}"; quiet=
	caught=$((fail - f0)); pass=$p0; fail=$f0
	if [ "$caught" -gt 0 ]; then ok; else bad "control: $1 is not caught by $2"; fi
	echo "$2" >> "$tmp/controlled"
}
noproxy=(env -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY -u http_proxy -u https_proxy -u all_proxy -u NO_PROXY -u no_proxy GH_HOST=unroutable.invalid)
nonet=(sandbox-exec -p '(version 1)(allow default)(deny network*)')
command -v sandbox-exec >/dev/null 2>&1 || bad "setup: sandbox-exec is missing, so the no-network sandbox checks cannot run"
netcall='    import urllib.request; urllib.request.urlopen("https://" + os.environ.get("GH_HOST", "api.github.com"), timeout=5)
'

# ---------------------------------------------------------------- fake claude
crec="$fix/claude"
fc() { local t="$1"; shift; FAKE_CLAUDE_RECORDINGS="$crec" "$t" "$@"; }
g_claude_help() {
	local out rc; out="$("$1" --help)"; rc=$?
	expect_rc 0 "$rc" "claude --help exits 0"
	expect_grep '^claude: ' "$(printf '%s\n' "$out" | head -1)" "claude --help first line is 'claude: ...'"
}
g_claude_text() {
	local out rc; out="$(fc "$1" -p "Say hello in five words." </dev/null)"; rc=$?
	expect_rc 0 "$rc" "claude -p with a recorded prompt exits 0"
	expect_eq "Hello there, nice to meet." "$out" "text output is the recorded result"
}
g_claude_match() {
	local out; out="$(fc "$1" -p "$(printf 'Read PLAN.md.\nList the milestones in one line.')" </dev/null)"
	expect_eq "M0, M1." "$out" "a multi-line prompt picks its own recording, not the first file"
}
g_claude_stdin() {
	local out; out="$(printf 'Say hello in five words.\n' | fc "$1" -p 2>/dev/null)"
	expect_eq "Hello there, nice to meet." "$out" "the prompt is read from stdin when no argument is given"
}
g_claude_json() {
	local out; out="$(fc "$1" -p "Say hello in five words." --output-format json </dev/null)"
	expect_eq "result|Hello there, nice to meet.|0.0012" "$(printf '%s' "$out" | python3 -c 'import json,sys; v=json.load(sys.stdin); print(v["type"], v["result"], v["total_cost_usd"], sep="|")' 2>/dev/null)" "--output-format json prints the result event"
}
g_claude_stream() {
	local out rc
	out="$(fc "$1" -p "Read PLAN.md.
List the milestones in one line." --output-format stream-json --verbose </dev/null)"; rc=$?
	expect_rc 0 "$rc" "stream-json --verbose exits 0"
	expect_eq "$(cat "$crec/plan.stream.jsonl")" "$out" "stream-json prints every recorded line unchanged"
	out="$(fc "$1" --verbose --output-format=stream-json -p "Say hello in five words." </dev/null)"
	expect_eq "$(cat "$crec/hello.stream.jsonl")" "$out" "--output-format=VALUE and options before -p work"
}
g_claude_verbose() {
	local out rc; out="$(fc "$1" -p "Say hello in five words." --output-format stream-json </dev/null 2>"$tmp/err")"; rc=$?
	expect_rc 1 "$rc" "stream-json without --verbose exits 1, as the real tool does"
	expect_has "requires --verbose" "$(cat "$tmp/err")" "stream-json without --verbose says it needs --verbose"
	expect_eq "" "$out" "stream-json without --verbose prints nothing on stdout"
}
g_claude_model() {
	local out
	out="$(fc "$1" -p "Say hello in five words." --model sonnet </dev/null 2>/dev/null)"
	expect_eq "Hello there, nice to meet." "$out" "--model NAME is accepted"
	out="$(fc "$1" --model=claude-opus-4-5 -p "Say hello in five words." </dev/null 2>/dev/null)"
	expect_eq "Hello there, nice to meet." "$out" "--model=NAME is accepted"
}
g_claude_unmatched() {
	local out rc sha
	sha="$(printf '%s' "No such prompt" | shasum -a 256 | cut -c1-12)"
	out="$(fc "$1" -p "No such prompt" </dev/null 2>"$tmp/err")"; rc=$?
	expect_rc 1 "$rc" "an unmatched prompt exits 1"
	expect_has "$crec/$sha.prompt and $crec/$sha.stream.jsonl" "$(cat "$tmp/err")" "an unmatched prompt names the recording files to add"
	expect_eq "" "$out" "an unmatched prompt prints nothing on stdout"
}
g_claude_error() {
	fc "$1" -p "Trigger an error." </dev/null >/dev/null 2>&1; expect_rc 1 $? "a recorded result with is_error true exits 1"
}
g_claude_unknown() {
	fc "$1" -p --bogus </dev/null >/dev/null 2>&1; expect_rc 2 $? "an unknown option exits 2"
}
g_claude_noprint() {
	fc "$1" "Say hello in five words." </dev/null >/dev/null 2>&1; expect_rc 2 $? "a call without -p exits 2"
}
g_claude_norec() {
	env -u FAKE_CLAUDE_RECORDINGS "$1" -p "Say hello in five words." </dev/null >/dev/null 2>&1; expect_rc 2 $? "FAKE_CLAUDE_RECORDINGS unset exits 2"
}
g_claude_broken() {
	local d="$tmp/broken-claude" rc
	mkdir -p "$d"; printf 'Broken.\n' > "$d/b.prompt"
	{ head -1 "$crec/hello.stream.jsonl"; tail -1 "$crec/hello.stream.jsonl"; sed -n 2p "$crec/hello.stream.jsonl"; } > "$d/b.stream.jsonl"
	FAKE_CLAUDE_RECORDINGS="$d" "$1" -p "Broken." </dev/null >/dev/null 2>"$tmp/err"; rc=$?
	expect_rc 1 "$rc" "a recording whose last event is not the result exits 1"
	expect_has "broken recording" "$(cat "$tmp/err")" "a broken recording is named as broken"
}
g_claude_log() {
	: > "$tmp/claude.log"
	FAKE_CLAUDE_LOG="$tmp/claude.log" fc "$1" -p "Say hello in five words." --model sonnet </dev/null >/dev/null 2>&1
	expect_eq "hello|-p,Say hello in five words.,--model,sonnet" "$(python3 -c 'import json,sys; v=json.loads(open(sys.argv[1]).readline()); print(v["recording"], ",".join(v["argv"]), sep="|")' "$tmp/claude.log" 2>/dev/null)" "FAKE_CLAUDE_LOG records the argv and the recording used"
}
g_claude_static() {
	expect_eq "" "$(grep -En '^[[:space:]]*(import|from)[[:space:]]+(socket|ssl|urllib|http|subprocess|asyncio)' "$1")" "fake claude imports no network or process module"
}
g_claude_sandbox() {
	local out; out="$("${noproxy[@]}" FAKE_CLAUDE_RECORDINGS="$crec" "${nonet[@]}" "$1" -p "Say hello in five words." </dev/null 2>/dev/null)"
	expect_eq "Hello there, nice to meet." "$out" "fake claude answers with network access denied by the OS sandbox"
}
claude_groups="g_claude_help g_claude_text g_claude_match g_claude_stdin g_claude_json g_claude_stream g_claude_verbose g_claude_model g_claude_unmatched g_claude_error g_claude_unknown g_claude_noprint g_claude_norec g_claude_broken g_claude_log g_claude_static g_claude_sandbox"
fcl="$si/claude/claude"
for g in $claude_groups; do "$g" "$fcl"; done
pc() { # label group old new
	local d; d="$(newdir)"; plant "$fcl" "$d/claude" "$3" "$4"; control "$1" "$2" "$d/claude"
}
pc "a help first line without 'claude: '" g_claude_help '"""claude: a fake' '"""Claude: a fake'
pc "text output prints the whole event" g_claude_text 'print(result.get("result", ""))' 'print(json.dumps(result))'
pc "any recording matches" g_claude_match 'if text == prompt:' 'if True:'
pc "stdin ignored" g_claude_stdin 'sys.stdin.read()' '""'
pc "json prints the first event" g_claude_json 'print(json.dumps(result))' 'print(json.dumps(events[0]))'
pc "stream drops the first line" g_claude_stream 'for line in lines:' 'for line in lines[1:]:'
pc "stream-json allowed without --verbose" g_claude_verbose 'and not opts["verbose"]' 'and False'
pc "--model NAME rejected" g_claude_model 'elif arg in ("--output-format", "--model"):' 'elif arg in ("--output-format",):'
pc "unmatched prompt names no file" g_claude_unmatched 'add {stem}.prompt and {stem}.stream.jsonl' 'add a recording'
pc "is_error ignored" g_claude_error 'return 1 if result.get("is_error") else 0' 'return 0'
pc "unknown options taken as the prompt" g_claude_unknown 'elif arg.startswith("-") and arg != "-":' 'elif False:'
pc "no -p allowed" g_claude_noprint 'if not opts["print"]:' 'if False:'
pc "unset recordings exits 1" g_claude_norec 'return fail(2, "FAKE_CLAUDE_RECORDINGS' 'return fail(1, "FAKE_CLAUDE_RECORDINGS'
pc "a result before the last event allowed" g_claude_broken 'if not results or events[-1] is not results[-1]:' 'if not results:'
pc "log without the recording name" g_claude_log '"recording": name}' '"recording": None}'
pc "a socket import" g_claude_static 'import json
' 'import json
import socket
'
pc "a network call" g_claude_sandbox 'def main(argv) -> int:
' "def main(argv) -> int:
$netcall"

# ---------------------------------------------------------------- fake gh
grec="$fix/gh"
rgh() { local d="$1"; shift; PATH="$d:/usr/bin:/bin" FAKE_GH_RECORDINGS="$grec" gh "$@" </dev/null; }
g_gh_help() {
	local out rc; out="$(PATH="$1:/usr/bin:/bin" gh --help)"; rc=$?
	expect_rc 0 "$rc" "gh --help exits 0"
	expect_grep '^gh: ' "$(printf '%s\n' "$out" | head -1)" "gh --help first line is 'gh: ...'"
}
g_gh_view() {
	local out rc; out="$(rgh "$1" pr view 5 --repo acme/widgets --json number,url)"; rc=$?
	expect_rc 0 "$rc" "gh pr view N --repo --json exits 0"
	expect_eq '{"number": 5, "url": "https://github.com/acme/widgets/pull/5"}' "$out" "--json keeps only the requested fields"
}
g_gh_field() {
	local rc; rgh "$1" pr view 5 --repo acme/widgets --json number,nosuch >/dev/null 2>"$tmp/err"; rc=$?
	expect_rc 1 "$rc" "a --json field the recording lacks exits 1"
	expect_has "has no field nosuch" "$(cat "$tmp/err")" "a missing --json field is named"
}
g_gh_missing() {
	local rc; rgh "$1" pr view 8 --repo acme/widgets --json number >/dev/null 2>"$tmp/err"; rc=$?
	expect_rc 1 "$rc" "a call with no recording exits 1"
	expect_has "add $grec/acme/widgets/pr-view-8.json" "$(cat "$tmp/err")" "a call with no recording names the file to add"
}
g_gh_sidecar() {
	local out rc; out="$(rgh "$1" pr checks 6 --repo acme/widgets --json name,state,description,link,workflow,bucket 2>"$tmp/err")"; rc=$?
	expect_rc 1 "$rc" "the .exit sidecar sets the exit code"
	expect_has "no checks reported on the 'feature-b' branch" "$(cat "$tmp/err")" "the .stderr sidecar is printed"
	expect_eq "" "$out" "an empty recording prints nothing"
}
g_gh_limit() {
	local out; out="$(rgh "$1" pr list --repo acme/widgets --state open --limit 2 --json number,headRefName)"
	expect_eq '[{"number": 5, "headRefName": "feature-a"}, {"number": 6, "headRefName": "feature-b"}]' "$out" "--limit and --json apply to a recorded list"
}
g_gh_cursor() {
	local q='query ReviewThreads($owner: String!, $repo: String!, $pr: Int!, $after: String) { x }' out
	out="$(rgh "$1" api graphql -f "query=$q" -f owner=acme -f repo=widgets -F pr=5 -f 'after=Y3Vyc29yOnYyOjE=')"
	expect_eq 'PRRT_1|None' "$(printf '%s' "$out" | python3 -c 'import json,sys; t=json.load(sys.stdin)["data"]["repository"]["pullRequest"]["reviewThreads"]; print(t["nodes"][0]["id"], t["pageInfo"]["endCursor"], sep="|")' 2>/dev/null)" "a graphql call with an after page token replays the second page"
}
g_gh_current() {
	local out
	out="$(env -u GH_REPO PATH="$1:/usr/bin:/bin" FAKE_GH_RECORDINGS="$grec" gh pr view --json number,url </dev/null 2>/dev/null)"
	expect_eq '{"number": 5, "url": "https://github.com/acme/widgets/pull/5"}' "$out" "pr view with no number and no repo reads pr-view.json at the top"
	out="$(GH_REPO=acme/widgets rgh "$1" pr view 6 --json number 2>/dev/null)"
	expect_eq '{"number": 6}' "$out" "pr view without --repo uses GH_REPO"
}
g_gh_unsupported() {
	rgh "$1" auth status >/dev/null 2>&1; expect_rc 2 $? "gh auth status (not a ctlhq-watch-pr call) exits 2"
	rgh "$1" pr merge 5 --repo acme/widgets >/dev/null 2>&1; expect_rc 2 $? "gh pr merge (not a ctlhq-watch-pr call) exits 2"
}
g_gh_norec() {
	env -u FAKE_GH_RECORDINGS PATH="$1:/usr/bin:/bin" gh pr view 5 --json number </dev/null >/dev/null 2>&1; expect_rc 2 $? "FAKE_GH_RECORDINGS unset exits 2"
}
g_gh_log() {
	: > "$tmp/gh.log"
	FAKE_GH_LOG="$tmp/gh.log" rgh "$1" pr view 5 --repo acme/widgets --json number >/dev/null 2>&1
	FAKE_GH_LOG="$tmp/gh.log" rgh "$1" pr view 8 --repo acme/widgets --json number >/dev/null 2>&1
	expect_eq '["pr", "view", "8", "--repo", "acme/widgets", "--json", "number"]' "$(sed -n 2p "$tmp/gh.log")" "FAKE_GH_LOG records every call, missing ones too"
}
g_gh_static() {
	expect_eq "" "$(grep -En '^[[:space:]]*(import|from)[[:space:]]+(socket|ssl|urllib|http|subprocess|asyncio)' "$1/gh")" "fake gh imports no network or process module"
}
g_gh_noroute() {
	local out; out="$("${noproxy[@]}" PATH="$1:/usr/bin:/bin" FAKE_GH_RECORDINGS="$grec" gh pr view 5 --repo acme/widgets --json number </dev/null 2>/dev/null)"
	expect_eq '{"number": 5}' "$out" "fake gh answers with proxies unset and GH_HOST=unroutable.invalid"
}
g_gh_sandbox() {
	local out; out="$(PATH="$1:/usr/bin:/bin" FAKE_GH_RECORDINGS="$grec" "${nonet[@]}" "$1/gh" pr view 5 --repo acme/widgets --json number </dev/null 2>/dev/null)"
	expect_eq '{"number": 5}' "$out" "fake gh answers with network access denied by the OS sandbox"
}
gh_groups="g_gh_help g_gh_view g_gh_field g_gh_missing g_gh_sidecar g_gh_limit g_gh_cursor g_gh_current g_gh_unsupported g_gh_norec g_gh_log g_gh_static g_gh_noroute g_gh_sandbox"
fgh="$si/gh/gh"
for g in $gh_groups; do "$g" "$si/gh"; done
pg() { # label group old new: the group runs on a planted copy of gh
	local d; d="$(newdir)"; plant "$fgh" "$d/gh" "$3" "$4"; control "$1" "$2" "$d"
}
pg "a help first line without 'gh: '" g_gh_help '"""gh: a fake' '"""Fake gh: a fake'
pg "--json ignored" g_gh_view 'return {f: value[f] for f in fields}' 'return value'
pg "missing fields not named" g_gh_field 'if lost:' 'if False:'
pg "a missing recording not named" g_gh_missing 'f"no recording for this call; add {path}"' '"no recording for this call"'
pg ".exit sidecar ignored" g_gh_sidecar '".exit"' '".code"'
pg "--limit ignored" g_gh_limit 'value = value[:limit]' 'value = value'
pg "the after page token dropped from the file name" g_gh_cursor 'if k not in ("query", "owner", "repo")]' 'if k not in ("query", "owner", "repo", "after")]'
pg "no-repo calls read a subfolder" g_gh_current '    if repo is None:
        return root' '    if repo is None:
        return root / "current"'
pg "unsupported calls look for a recording" g_gh_unsupported 'raise Usage("unsupported call: gh " + " ".join(argv))' 'return root / "unsupported.json", None, None'
pg "unset recordings exits 1" g_gh_norec 'return fail(2, "FAKE_GH_RECORDINGS' 'return fail(1, "FAKE_GH_RECORDINGS'
pg "no log line" g_gh_log 'handle.write(json.dumps(argv) + "\n")' 'pass'
pg "a socket import" g_gh_static 'import json
' 'import json
import socket
'
pg "a network call to GH_HOST" g_gh_noroute 'def main(argv) -> int:
' "def main(argv) -> int:
$netcall"
pg "a network call under the sandbox" g_gh_sandbox 'def main(argv) -> int:
' "def main(argv) -> int:
$netcall"

# ---------------------------------------------------------------- ctlhq-watch-pr on recorded responses
nodebin="$(command -v node 2>/dev/null)"
[ -n "$nodebin" ] && ok || bad "setup: node is not installed, so ctlhq-watch-pr cannot be replayed"
nodepath="$(dirname "${nodebin:-/usr/bin/node}"):/usr/bin:/bin"
wplog="$tmp/wp.log"; : > "$wplog"
# wp GHDIR REC ARGS...: run ctlhq-watch-pr's code from a folder that is not a git repository.
wp() { local d="$1" r="$2"; shift 2; (cd "$tmp" && PATH="$d:$nodepath" FAKE_GH_RECORDINGS="$r" FAKE_GH_LOG="$wplog" node "$driver" "$wpsrc" "$@" </dev/null 2>/dev/null); }
kind() { python3 -c 'import json,sys; v=json.loads(sys.stdin.read().strip().splitlines()[-1]); b=v.get("blocker") or {}; print(v["kind"], b.get("kind", "-"), ",".join(str(r["context"]["number"]) for r in v.get("rows", [])) or "-")' 2>/dev/null; }
g_wp_ready() {
	local out rc; out="$(wp "$1" "$2" --owner acme --repo widgets --pr 5)"; rc=$?
	expect_rc 0 "$rc" "ctlhq-watch-pr on a clean recorded PR exits 0"
	expect_eq "READY - -" "$(printf '%s' "$out" | kind)" "ctlhq-watch-pr on a clean recorded PR says READY"
}
g_wp_failing() {
	local out rc before; before="$(grep -c 'query PrCheckRollup' "$wplog")"
	out="$(wp "$1" "$2" --owner acme --repo widgets --pr 6)"; rc=$?
	expect_rc 4 "$rc" "ctlhq-watch-pr on a PR with a failed check exits 4"
	expect_eq "BLOCKER failing-checks -" "$(printf '%s' "$out" | kind)" "ctlhq-watch-pr names the failing-checks blocker"
	expect_eq 2 "$(( $(grep -c 'query PrCheckRollup' "$wplog") - before ))" "an unusable gh pr checks falls back to two GraphQL rollup pages"
}
g_wp_threads() {
	local out rc; out="$(wp "$1" "$2" --owner acme --repo widgets --pr 7)"; rc=$?
	expect_rc 3 "$rc" "ctlhq-watch-pr on a PR with an open review thread exits 3"
	expect_has "Please add a test." "$out" "the open thread's comment is in the verdict"
}
g_wp_stack() {
	local out rc; out="$(wp "$1" "$2" --owner acme --repo widgets --pr 6 --stack --status-only)"; rc=$?
	expect_rc 0 "$rc" "ctlhq-watch-pr --stack --status-only exits 0"
	expect_eq "STATUS - 5,6,7" "$(printf '%s' "$out" | kind)" "the stack from pr list is 5, 6, 7, bottom to top, without the unrelated 9"
}
g_wp_current() {
	local out rc; out="$(GH_REPO= wp "$1" "$2" --status-only)"; rc=$?
	expect_rc 0 "$rc" "ctlhq-watch-pr with no PR number finds the current PR"
	expect_eq "STATUS - 5" "$(printf '%s' "$out" | kind)" "the current PR comes from gh pr view --json number,url"
}
g_wp_missing() {
	local out rc; out="$(wp "$1" "$2" --owner acme --repo widgets --pr 8)"; rc=$?
	expect_rc 7 "$rc" "ctlhq-watch-pr on a PR with no recording exits 7 (status query failed)"
	expect_has "pr-view-8.json" "$out" "the ctlhq-watch-pr verdict names the missing recording"
}
g_wp_shapes() { # SRC_DIR LOG: every gh call shape in ctlhq-watch-pr's source was replayed
	local missing
	missing="$(python3 - "$1/github.ts" "$2" <<'PY'
import json, re, sys
src = open(sys.argv[1], encoding="utf-8").read()
want = {f"{a} {b}" for a, b in re.findall(r'"gh",\s*"([a-z]+)",\s*"([a-z]+)"', src)}
want |= {f"graphql {q}" for q in re.findall(r'query ([A-Za-z]+)\(', src)}
got = set()
for line in open(sys.argv[2], encoding="utf-8"):
    argv = json.loads(line)
    got.add(" ".join(argv[:2]))
    for arg in argv:
        m = re.match(r"query=\s*query ([A-Za-z]+)\(", arg)
        if m:
            got.add("graphql " + m.group(1))
    if any(a.startswith("after=") for a in argv):
        got.add("graphql after")
want.add("graphql after")
print(" ".join(sorted(want - got)) if want else "no gh calls found in the source")
PY
)"
	expect_eq "" "$missing" "every gh call shape in github.ts (and a paginated graphql call) was replayed"
}
g_wp_offline() {
	local out rc
	out="$(cd "$tmp" && "${noproxy[@]}" PATH="$1:$nodepath" FAKE_GH_RECORDINGS="$2" "${nonet[@]}" node "$driver" "$wpsrc" --owner acme --repo widgets --pr 5 </dev/null 2>/dev/null)"; rc=$?
	expect_rc 0 "$rc" "ctlhq-watch-pr on recorded responses works with no network route and the OS sandbox denying network"
	expect_eq "READY - -" "$(printf '%s' "$out" | kind)" "ctlhq-watch-pr says READY with network denied"
}
wp_groups="g_wp_ready g_wp_failing g_wp_threads g_wp_stack g_wp_current g_wp_missing g_wp_offline"
for g in $wp_groups; do "$g" "$si/gh" "$grec"; done
g_wp_shapes "$wpsrc" "$wplog"
wp_groups="$wp_groups g_wp_shapes"
# Planted defects in a recording copy.
prec() { # label group file old new
	local d; d="$(newdir)"; cp -R "$grec" "$d/rec"
	plant "$d/rec/acme/widgets/$3" "$d/rec/acme/widgets/$3" "$4" "$5"; control "$1" "$2" "$si/gh" "$d/rec"
}
prec "a conflicting PR 5" g_wp_ready pr-view-5.json '"mergeable":"MERGEABLE"' '"mergeable":"CONFLICTING"'
prec "a one-page rollup" g_wp_failing graphql-PrCheckRollup-pr-6.json '"hasNextPage":true' '"hasNextPage":false'
prec "a resolved thread" g_wp_threads graphql-ReviewThreads-pr-7.json '"isResolved":false' '"isResolved":true'
prec "PR 7 off the stack" g_wp_stack pr-list-open.json '"baseRefName":"feature-b"' '"baseRefName":"main"'
# Planted defects in the fake gh.
pw() { # label group old new
	local d; d="$(newdir)"; plant "$fgh" "$d/gh" "$3" "$4"; control "$1" "$2" "$d" "$grec"
}
pw "no-repo calls read a subfolder" g_wp_current '    if repo is None:
        return root' '    if repo is None:
        return root / "current"'
pw "a missing recording not named" g_wp_missing 'f"no recording for this call; add {path}"' '"no recording for this call"'
pw "a network call" g_wp_offline 'def main(argv) -> int:
' "def main(argv) -> int:
$netcall"
d="$(newdir)"; plant "$wpsrc/github.ts" "$d/github.ts" 'const argv: [string, ...string[]] = ["gh", "pr", "view"];' 'const argv: [string, ...string[]] = ["gh", "pr", "edit"];'
control "a gh call shape the replay never made" g_wp_shapes "$d" "$wplog"

# ---------------------------------------------------------------- signing key
nk() { "$1/new-key" --parent "$keys" 2>/dev/null | head -1; }
envval() { sed -n "s/^export $2='\(.*\)'$/\1/p" "$1/env" 2>/dev/null; }
agent_keys() { local out rc; out="$(SSH_AUTH_SOCK="$1/agent.sock" ssh-add -l 2>/dev/null)"; rc=$?; case $rc in 0) printf '%s\n' "$out" | grep -c . ;; 1) echo 0 ;; *) echo "no-agent" ;; esac; }
# scratch_commit KEYDIR REPO: a signed commit in a new scratch repository; config is local.
sgit() { local k="$1"; shift; GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 SSH_AUTH_SOCK="$k/agent.sock" git "$@"; }
scratch_commit() {
	local k="$1" r="$2" signers="${3:-$1/allowed_signers}"
	mkdir -p "$r" && sgit "$k" -C "$r" init -q && {
		sgit "$k" -C "$r" config user.name "Stand-in Test"
		sgit "$k" -C "$r" config user.email "throwaway-signing@example.invalid"
		sgit "$k" -C "$r" config gpg.format ssh
		# key:: gives git the public key only, so only the private agent can sign.
		sgit "$k" -C "$r" config user.signingkey "key::$(cat "$k/key.pub" 2>/dev/null)"
		sgit "$k" -C "$r" config gpg.ssh.allowedSignersFile "$signers"
		sgit "$k" -C "$r" config commit.gpgsign true
		echo hello > "$r/file.txt"; sgit "$k" -C "$r" add file.txt
		sgit "$k" -C "$r" commit -q -m "signed by a throwaway key" >/dev/null 2>&1
	}
}
real_stop() { [ -n "$1" ] && [ -d "$1" ] && "$si/signing-key/stop" "$1" >/dev/null 2>&1; }
g_sk_help() {
	local rc first
	first="$("$1/new-key" --help | head -1)"; expect_grep '^new-key: ' "$first" "new-key --help first line is 'new-key: ...'"
	first="$("$1/stop" --help | head -1)"; expect_grep '^stop: ' "$first" "stop --help first line is 'stop: ...'"
}
g_sk_make() {
	local k pid cmd fp
	k="$(nk "$1")"
	[ -n "$k" ] && [ -f "$k/key" ] && [ -f "$k/key.pub" ] && [ -f "$k/env" ] && [ -f "$k/.fake-signing-key" ] && [ -s "$k/allowed_signers" ] && ok || bad "new-key makes key, key.pub, env, allowed_signers, and its marker"
	pid="$(envval "$k" SSH_AGENT_PID)"; cmd="$(ps -p "${pid:-0}" -o command= 2>/dev/null)"
	expect_has "ssh-agent -a $k/agent.sock" "$cmd" "env's SSH_AGENT_PID is the private ssh-agent on the folder's socket"
	expect_eq "$k/agent.sock" "$(envval "$k" SSH_AUTH_SOCK)" "env's SSH_AUTH_SOCK is the folder's socket"
	expect_eq 1 "$(agent_keys "$k")" "the private agent holds exactly one key"
	fp="$(ssh-keygen -lf "$k/key.pub" 2>/dev/null | awk '{print $2}')"
	expect_has "${fp:-no-fingerprint}" "$(SSH_AUTH_SOCK="$k/agent.sock" ssh-add -l 2>/dev/null)" "the private agent's key is the throwaway key"
	expect_eq "$op_before" "$(op_keys)" "the operator's agent key count is unchanged while a throwaway key is loaded"
	real_stop "$k"
}
g_sk_commit() { # DIR [allowed signers override]
	local k r out
	k="$(nk "$1")"; r="$tmp/repo-$RANDOM$RANDOM"
	scratch_commit "$k" "$r"; expect_rc 0 $? "a scratch repository commits with gpg.format ssh and the throwaway key"
	if [ -n "${2:-}" ]; then sgit "$k" -C "$r" config gpg.ssh.allowedSignersFile "$2"; fi
	out="$(sgit "$k" -C "$r" verify-commit HEAD 2>&1)"; expect_rc 0 $? "git verify-commit accepts the commit"
	expect_has 'Good "git" signature for throwaway-signing@example.invalid' "$out" "the signature verifies against the scratch allowed signers file"
	expect_eq "" "$(sgit "$k" -C "$r" config --show-origin --get-regexp '^(user|gpg|commit)\.' | grep -v '^file:.git/config	')" "all signing configuration is in the scratch repository's .git/config"
	real_stop "$k"
}
g_sk_stop() {
	local k pid r
	k="$(nk "$1")"; pid="$(envval "$k" SSH_AGENT_PID)"; r="$tmp/repo-$RANDOM$RANDOM"
	"$1/stop" "$k" >/dev/null 2>&1; expect_rc 0 $? "stop exits 0"
	[ ! -e "$k" ] && ok || bad "stop deletes the folder"
	sleep 0.2; kill -0 "${pid:-0}" 2>/dev/null && bad "stop kills the private agent (pid $pid still runs)" || ok
	scratch_commit "$k" "$r" && bad "after stop, a signed commit with that socket still works" || ok
}
g_sk_only_mine() {
	local a b pidb
	a="$(nk "$1")"; b="$(nk "$1")"; pidb="$(envval "$b" SSH_AGENT_PID)"
	"$1/stop" "$a" >/dev/null 2>&1
	kill -0 "${pidb:-0}" 2>/dev/null && ok || bad "stopping one key leaves another key's agent running"
	expect_eq 1 "$(agent_keys "$b")" "the other agent still holds its key"
	expect_eq "$op_before" "$(op_keys)" "stop leaves the operator's agent key count unchanged"
	real_stop "$a"; real_stop "$b"
}
g_sk_marker() {
	local d="$tmp/nomark-$RANDOM$RANDOM"
	mkdir -p "$d"; echo "keep" > "$d/keep.txt"; : > "$d/env"
	"$1/stop" "$d" >/dev/null 2>&1; expect_rc 1 $? "stop refuses a folder without the new-key marker"
	[ -f "$d/keep.txt" ] && ok || bad "stop keeps a folder without the marker"
}
g_sk_pid() {
	local k real
	sleep 60 >/dev/null 2>&1 & sleeper=$!; disown "$sleeper"
	k="$(nk "$1")"; real="$(envval "$k" SSH_AGENT_PID)"
	sed "s/^export SSH_AGENT_PID=.*/export SSH_AGENT_PID='$sleeper'/" "$k/env" > "$k/env.new" && mv "$k/env.new" "$k/env"
	"$1/stop" "$k" >/dev/null 2>&1; expect_rc 1 $? "stop refuses when the env pid is not this folder's ssh-agent"
	kill -0 "$sleeper" 2>/dev/null && ok || bad "stop does not kill a process that is not its agent"
	[ -d "$k" ] && ok || bad "stop keeps the folder when it refuses"
	kill "$sleeper" 2>/dev/null; sleeper=""
	[ -n "$real" ] && kill "$real" 2>/dev/null
	rm -rf "$k"
}
g_sk_cleanup() {
	local long="$keys/$(printf 'L%.0s' $(seq 1 90))" rc
	mkdir -p "$long"
	"$1/new-key" --parent "$long" >/dev/null 2>"$tmp/err"; rc=$?
	expect_rc 1 "$rc" "new-key with a socket path over 100 bytes exits 1"
	expect_eq "" "$(ls -A "$long")" "a failed new-key leaves no folder behind"
	expect_has "socket path is too long" "$(cat "$tmp/err")" "a failed new-key says why"
}
g_sk_usage() {
	"$1/new-key" --bogus >/dev/null 2>&1; expect_rc 2 $? "new-key with an unknown argument exits 2"
	"$1/stop" >/dev/null 2>&1; expect_rc 2 $? "stop with no folder exits 2"
}
sk_groups="g_sk_help g_sk_make g_sk_commit g_sk_stop g_sk_only_mine g_sk_marker g_sk_pid g_sk_cleanup g_sk_usage"
for g in $sk_groups; do "$g" "$si/signing-key"; done
ps_() { # label group file old new: the group runs on a folder holding a planted new-key or stop
	local d; d="$(newdir)"; cp "$si/signing-key/new-key" "$si/signing-key/stop" "$d/"
	plant "$si/signing-key/$3" "$d/$3" "$4" "$5"; control "$1" "$2" "$d"
}
ps_ "a new-key help line without 'new-key: '" g_sk_help new-key '# new-key: make' '# New key: make'
ps_ "a stop help line without 'stop: '" g_sk_help stop '# stop: kill' '# Stop: kill'
ps_ "no key loaded into the agent" g_sk_make new-key 'SSH_AUTH_SOCK="$sock" ssh-add -q "$dir/key"' 'true'
ps_ "no allowed signers file" g_sk_make new-key '"$(cut -d'"' '"' -f1,2 "$dir/key.pub")" > "$dir/allowed_signers"' '"$(cut -d'"' '"' -f1,2 "$dir/key.pub")" > /dev/null'
ps_ "a wrong pid in env" g_sk_make new-key "printf \"export SSH_AGENT_PID='%s'\\n\" \"\$pid\"" "printf \"export SSH_AGENT_PID='%s'\\n\" \"\$\$\""
ps_ "no key loaded, so the commit cannot sign" g_sk_commit new-key 'SSH_AUTH_SOCK="$sock" ssh-add -q "$dir/key"' 'true'
other="$(nk "$si/signing-key")"
control "allowed signers that list another key" g_sk_commit "$si/signing-key" "$other/allowed_signers"
ps_ "stop that does not kill" g_sk_stop stop 'kill "$pid" || {' 'true || {'
ps_ "stop that kills every agent under the parent folder" g_sk_only_mine stop 'kill "$pid" || {' 'pkill -f "ssh-agent -a $(dirname "$dir")/" || {'
ps_ "stop without the marker check" g_sk_marker stop '[ -f "$dir/.fake-signing-key" ] ||' 'true ||'
ps_ "stop without the process check" g_sk_pid stop '*ssh-agent*" -a $dir/agent.sock"*) kill' '*) kill'
ps_ "new-key that keeps a failed folder" g_sk_cleanup new-key '	rm -rf "$dir"
	echo "new-key: $1" >&2' '	echo "new-key: $1" >&2'
ps_ "new-key that accepts unknown arguments" g_sk_usage new-key '[--parent DIR])" >&2; exit 2 ;;' '[--parent DIR])" >&2; exit 0 ;;'
ps_ "stop that accepts no folder" g_sk_usage stop '>&2; exit 2; }
[ -d "$1" ]' '>&2; exit 0; }
[ -d "$1" ]'
real_stop "$other"

# ---------------------------------------------------------------- operator agent, every group controlled
g_operator() { expect_eq "$op_before" "$1" "the operator's agent key count is the same before and after"; }
op_after="$(op_keys)"
g_operator "$op_after"
control "a planted different count" g_operator "planted-$op_before"
all_groups="$claude_groups $gh_groups $wp_groups $sk_groups g_operator"
missing=""
for g in $all_groups; do grep -qx "$g" "$tmp/controlled" || missing="$missing $g"; done
expect_eq "" "$missing" "every check group has at least one planted-defect control"
echo "operator agent keys after: $op_after"
echo "$pass checks passed"
[ "$fail" -eq 0 ] || { echo "$fail checks failed"; exit 1; }
