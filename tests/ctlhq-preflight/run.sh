#!/usr/bin/env bash
# tests/ctlhq-preflight/run.sh: checks for bin/ctlhq-preflight with a hand-made repository folder and a private ssh-agent.
# Prints "N checks passed" and exits 1 when any check fails. Writes only to temp folders. It never
# talks to the real ssh-agent: SSH_AUTH_SOCK is unset first and only ever points at the test's own agent.
set -u
unset SSH_AUTH_SOCK SSH_AGENT_PID FIRST_PUSH_CONFIG
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
pf="$root/bin/ctlhq-preflight"
pass=0
fail=0
ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL: $1"; }
expect_rc() { if [ "$1" -eq "$2" ]; then ok; else bad "$3 (expected exit $1, got $2)"; fi; }
expect_eq() { if [ "$1" = "$2" ]; then ok; else bad "$3 (expected '$1', got '$2')"; fi; }
expect_grep() { if printf '%s\n' "$2" | grep -Eq -- "$1"; then ok; else bad "$3 (no line matches: $1)"; fi; }
expect_nogrep() { if printf '%s\n' "$2" | grep -Eq -- "$1"; then bad "$3 (a line matches: $1)"; else ok; fi; }
line_of() { printf '%s\n' "$2" | grep -E -A1 -- "$1"; }  # a check line and the line under it

tmp="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/ctlhq-preflight-test.XXXXXX")" && pwd -P)"
export HOME="$tmp/home"   # the push owner setting is read from here, never the real home folder
mkdir -p "$HOME/.ctlhq"
settings="$HOME/.ctlhq/first-push.toml"
printf 'public_terms = ["Acme Corp"]\ngithub_owner = "acme"\n' >"$settings"
sockdir="$(mktemp -d /tmp/fpf.XXXXXX)"   # Unix socket paths must stay short
agents=""
site_pid=""
cleanup() {
	for a in $agents; do kill "$a" 2>/dev/null; done
	[ -n "$site_pid" ] && kill "$site_pid" 2>/dev/null
	chmod -R u+w "$tmp" 2>/dev/null
	rm -rf "$tmp" "$sockdir"
}
trap cleanup EXIT

# A repository folder made by hand (no git command), with a signing key path in its config.
repo="$tmp/repo"
mkdir -p "$repo/.git/objects" "$repo/.git/refs/heads"
echo 'ref: refs/heads/main' >"$repo/.git/HEAD"
printf '[core]\n\trepositoryformatversion = 0\n\tbare = false\n[user]\n\tsigningkey = /keys/test signing.pub\n' >"$repo/.git/config"
mkdir -p "$tmp/plain"

# Two private agents: one holding a throwaway key, one empty.
start_agent() { # socket path; prints the agent pid
	ssh-agent -a "$1" -s 2>/dev/null | sed -n 's/^SSH_AGENT_PID=\([0-9]*\);.*/\1/p'
}
full="$sockdir/full"; empty="$sockdir/empty"
apid="$(start_agent "$full")"; agents="$agents $apid"
epid="$(start_agent "$empty")"; agents="$agents $epid"
ssh-keygen -q -t ed25519 -N '' -C 'SECRET-COMMENT-ctlhq-test' -f "$tmp/key"
if [ -S "$full" ] && [ -S "$empty" ]; then
	SSH_AUTH_SOCK="$full" ssh-add "$tmp/key" >/dev/null 2>&1
	ok
else
	bad "the private ssh-agents started"
fi

python3 -u -m http.server 0 --bind 127.0.0.1 --directory "$tmp/plain" >"$tmp/site.log" 2>&1 & site_pid=$!
disown "$site_pid"
port=""
for _ in $(seq 1 50); do port="$(sed -n 's/.*port \([0-9]*\).*/\1/p' "$tmp/site.log" | head -1)"; [ -n "$port" ] && break; sleep 0.1; done
dead="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')"

run() { (cd "$repo" && SSH_AUTH_SOCK="$full" "$pf" "$@" 2>&1); }

# 1. --help and usage errors.
out="$("$pf" --help 2>&1)"; expect_rc 0 $? "--help exits 0"
expect_grep '^ctlhq-preflight: ' "$(printf '%s\n' "$out" | head -1)" "--help first line is 'ctlhq-preflight: ...'"
expect_grep '^Operator rule \(home/AGENTS\.md, Before work\): "Run the permission preflight before the first milestone' "$out" "--help quotes the rule and cites home/AGENTS.md"
"$pf" --bogus >/dev/null 2>&1; expect_rc 2 $? "unknown option exits 2"
"$pf" --min-disk lots >/dev/null 2>&1; expect_rc 2 $? "bad --min-disk exits 2"
"$pf" --service ftp://x >/dev/null 2>&1; expect_rc 2 $? "a non-http --service exits 2"
"$pf" --repo "$tmp/nope" >/dev/null 2>&1; expect_rc 2 $? "a missing --repo exits 2"
"$pf" --need , >/dev/null 2>&1; expect_rc 2 $? "an empty --need exits 2"

# 2. Everything ready: exit 0, and the key comment never shows.
out="$(run --min-disk 0 --need git,python3 --service "http://127.0.0.1:$port/")"; rc=$?
expect_rc 0 "$rc" "all ready exits 0"
expect_grep '^1\. ready +git work tree ' "$out" "git work tree ready"
expect_grep '^2\. ready +\.git writable ' "$out" ".git writable ready"
expect_grep '^3\. ready +signing key +ssh-agent holds 1 key$' "$out" "signing key ready with a count only"
expect_grep '^4\. ready +free disk +[0-9.]+ GiB free on .*, need 0 GiB$' "$out" "free disk ready"
expect_grep '^5\. ready +tool git ' "$out" "tool git ready"
expect_grep '^7\. ready +loopback ' "$out" "loopback ready"
expect_grep "^8\. ready +service http://127.0.0.1:$port/ +answered 200$" "$out" "service ready"
expect_grep '^ready 8 \| missing 0$' "$out" "summary line"
expect_nogrep 'SECRET-COMMENT' "$out" "the key comment is never printed"
expect_nogrep 'SECRET-COMMENT' "$(run --json)" "the key comment is never printed in --json"

# 3. Planted failures, each with its fix line.
out="$(run --min-disk 100000 --need nosuchtool-ctlhq --service "http://127.0.0.1:$dead/")"; rc=$?
expect_rc 1 "$rc" "missing checks exit 1"
expect_grep '^ +fix: free [0-9.]+ GiB more on ' "$(line_of 'missing +free disk' "$out")" "low disk names its fix"
expect_grep '^ +fix: install nosuchtool-ctlhq, or add the folder that holds it to PATH$' "$(line_of 'missing +tool nosuchtool-ctlhq' "$out")" "a missing tool names its fix"
expect_grep "fix: start the service at http://127.0.0.1:$dead/, for example: bin/ctlhq-serve start" "$(line_of "missing +service" "$out")" "a dead service names its fix"
expect_grep '^ready [0-9]+ \| missing 3$' "$out" "summary counts 3 missing"
out="$(run --min-disk 0 --need git --service "http://127.0.0.1:$port/nothing-here")"
expect_grep "ready +service .* answered 404$" "$out" "control: a 404 still counts as answering"

# 4. Signing key: empty agent, unset socket, and a socket with no agent.
out="$(cd "$repo" && SSH_AUTH_SOCK="$empty" "$pf" --min-disk 0 --need git 2>&1)"; expect_rc 1 $? "an empty agent exits 1"
expect_grep "^ +fix: ssh-add '/keys/test signing'$" "$(line_of 'missing +signing key +ssh-agent holds 0 keys' "$out")" "empty agent: fix adds the configured key without .pub"
out="$(cd "$repo" && "$pf" --min-disk 0 --need git 2>&1)"
expect_grep "fix: eval \"\\\$\(ssh-agent -s\)\" && ssh-add '/keys/test signing'" "$(line_of 'missing +signing key +SSH_AUTH_SOCK is not set' "$out")" "no socket: fix starts an agent"
out="$(cd "$repo" && SSH_AUTH_SOCK="$sockdir/none" "$pf" --min-disk 0 --need git 2>&1)"
expect_grep "missing +signing key +no ssh-agent answers at $sockdir/none" "$out" "a socket with no agent is reported"

# 5. Git: no work tree, and a read-only .git.
out="$(cd "$tmp/plain" && SSH_AUTH_SOCK="$full" "$pf" --min-disk 0 --need git 2>&1)"; expect_rc 1 $? "no work tree exits 1"
expect_grep "fix: cd into the project's repository, or run: git -C $tmp/plain init" "$(line_of 'missing +git work tree' "$out")" "no work tree names its fix"
expect_grep 'missing +\.git writable +skipped: no git work tree' "$out" ".git check is skipped without a work tree"
chmod a-w "$repo/.git/objects"
out="$(run --min-disk 0 --need git)"; rc=$?
chmod u+w "$repo/.git/objects"
expect_rc 1 "$rc" "a read-only objects/ exits 1"
expect_grep "fix: add $repo/.git/objects to the sandbox writable roots" "$(line_of 'missing +\.git writable' "$out")" "read-only objects/ names the folder and the fix"
expect_eq "" "$(find "$repo/.git" -name '.ctlhq-preflight-*')" "the write test leaves no file behind"

# 6. Loopback blocked (bind raises, as a sandbox does): reported with its fix.
out="$(cd "$repo" && SSH_AUTH_SOCK="$full" python3 - "$pf" <<'PY' 2>&1
import importlib.util, socket, sys
from importlib.machinery import SourceFileLoader
loader = SourceFileLoader("pf", sys.argv[1])
spec = importlib.util.spec_from_loader("pf", loader)
pf = importlib.util.module_from_spec(spec)
loader.exec_module(pf)
def denied(self, addr):
    raise PermissionError(1, "Operation not permitted")
socket.socket.bind = denied
sys.exit(pf.main(["--min-disk", "0", "--need", "git"]))
PY
)"; expect_rc 1 $? "blocked loopback exits 1"
expect_grep 'fix: allow binding and connecting on 127.0.0.1 in the sandbox' "$(line_of 'missing +loopback +127.0.0.1 failed: Operation not permitted' "$out")" "blocked loopback names its fix"

# 7. --json shape.
res="$(run --json --min-disk 100000 --need git | python3 -c '
import json, sys
d = json.load(sys.stdin); c = d["checks"]
print(d["missing"], d["ready"] + d["missing"] == len(c), [x["n"] for x in c] == list(range(1, len(c) + 1)),
      all(x["fix"] for x in c if x["state"] == "missing"), all(not x["fix"] for x in c if x["state"] == "ready"))
')"
expect_eq "1 True True True True" "$res" "--json: counts, numbering, and a fix on every missing check only"

# 8. Push guard (--push-guard): read from a scratch system settings file through GIT_CONFIG_SYSTEM,
# never the real one, with the owner from the scratch home's settings file. Without --push-guard there is no push guard line at all.
expect_nogrep 'push guard' "$(run --min-disk 0 --need git)" "without --push-guard there is no push guard check"
expect_grep 'push-guard' "$("$pf" --help)" "--help names --push-guard"
guard_full() {
	printf '[url "https://github.com/acme/"]\n\tpushInsteadOf = https://github.com/acme/\n'
	printf '[url "git@github.com:acme/"]\n\tpushInsteadOf = git@github.com:acme/\n'
	printf '[url "push-blocked://not-your-repo/"]\n\tpushInsteadOf = https://github.com/\n\tpushInsteadOf = git@github.com:\n\tpushInsteadOf = ssh://git@github.com/\n'
}
guard_full >"$tmp/sys-ready.cfg"
guard_full | grep -v 'ssh://git@github.com/' >"$tmp/sys-partial.cfg"
: >"$tmp/sys-empty.cfg"
grun() { # system settings file, then preflight arguments
	local f="$1"; shift
	(cd "$repo" && env -u GIT_CONFIG_NOSYSTEM GIT_CONFIG_SYSTEM="$f" SSH_AUTH_SOCK="$full" "$pf" "$@" 2>&1)
}
out="$(grun "$tmp/sys-ready.cfg" --min-disk 0 --need git --push-guard)"; expect_rc 0 $? "a full push guard exits 0"
expect_grep "^7\. ready +push guard +5 of 5 rules in $tmp/sys-ready.cfg$" "$out" "a full push guard is ready"
out="$(grun "$tmp/sys-partial.cfg" --min-disk 0 --need git --push-guard)"; expect_rc 1 $? "a partial push guard exits 1"
expect_grep "missing +push guard +4 of 5 rules in $tmp/sys-partial.cfg" "$out" "a partial push guard is missing"
fixl="$(line_of 'missing +push guard' "$out" | tail -1)"
expect_grep 'fix: as root, add the missing rules: sudo git config --system --add url\.push-blocked://not-your-repo/\.pushInsteadOf ssh://git@github\.com/ \(see ctlhq-preflight --help, check 8\)$' "$fixl" "a partial push guard names the one missing rule and the plan"
expect_nogrep 'acme' "$fixl" "a partial push guard does not re-add rules that are present"
out="$(grun "$tmp/sys-empty.cfg" --min-disk 0 --need git --push-guard)"; expect_rc 1 $? "an empty system settings file exits 1"
expect_grep "missing +push guard +0 of 5 rules in $tmp/sys-empty.cfg" "$out" "an empty system settings file is missing"
expect_grep 'ctlhq-preflight --help, check 8' "$(line_of 'missing +push guard' "$out")" "the missing case points to the plan"
out="$(grun "$tmp/nope.cfg" --min-disk 0 --need git --push-guard)"; expect_rc 1 $? "an absent system settings file exits 1"
expect_grep "missing +push guard +0 of 5 rules" "$out" "an absent system settings file is missing"
printf '[broken\n' >"$tmp/sys-bad.cfg"
out="$(grun "$tmp/sys-bad.cfg" --min-disk 0 --need git --push-guard)"; expect_rc 1 $? "an unreadable system settings file exits 1"
expect_grep "missing +push guard +cannot read $tmp/sys-bad.cfg: " "$out" "an unreadable system settings file is reported"
out="$(cd "$repo" && GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_SYSTEM="$tmp/sys-ready.cfg" SSH_AUTH_SOCK="$full" "$pf" --min-disk 0 --need git --push-guard 2>&1)"
expect_grep 'fix: unset GIT_CONFIG_NOSYSTEM, then rerun' "$(line_of 'missing +push guard +GIT_CONFIG_NOSYSTEM is set' "$out")" "GIT_CONFIG_NOSYSTEM turns the guard off and is reported"
owner_fix='fix: Add the line github_owner = "<your GitHub account>" to ~/\.ctlhq/first-push\.toml, then run this command again\.$'
printf 'public_terms = ["Acme Corp"]\n' >"$settings"
out="$(grun "$tmp/sys-ready.cfg" --min-disk 0 --need git --push-guard)"; expect_rc 1 $? "an unset owner exits 1"
expect_grep 'missing +push guard +not configured: no github_owner in ~/\.ctlhq/first-push\.toml$' "$out" "an unset owner says not configured"
expect_grep "$owner_fix" "$(line_of 'missing +push guard' "$out")" "an unset owner names the file and the key in its fix"
rm "$settings"
out="$(grun "$tmp/sys-ready.cfg" --min-disk 0 --need git --push-guard)"
expect_grep 'missing +push guard +not configured: no github_owner' "$out" "a missing settings file says not configured"
printf 'github_owner = acme\n' >"$settings"
out="$(grun "$tmp/sys-ready.cfg" --min-disk 0 --need git --push-guard)"
expect_grep 'missing +push guard +not configured: github_owner in ~/\.ctlhq/first-push\.toml is not a GitHub account name' "$out" "an unquoted owner says not configured"
printf 'github_owner = "other-owner"\n' >"$settings"
out="$(grun "$tmp/sys-ready.cfg" --min-disk 0 --need git --push-guard)"
expect_grep 'missing +push guard +3 of 5 rules' "$out" "rules for another owner do not count"
expect_grep 'url\.https://github\.com/other-owner/\.pushInsteadOf https://github\.com/other-owner/' "$(line_of 'missing +push guard' "$out")" "the fix adds the rules for the configured owner"
printf 'github_owner = "acme"\n' >"$tmp/sys-owner.toml"
out="$(cd "$repo" && env -u GIT_CONFIG_NOSYSTEM GIT_CONFIG_SYSTEM="$tmp/sys-ready.cfg" FIRST_PUSH_CONFIG="$tmp/sys-owner.toml" SSH_AUTH_SOCK="$full" "$pf" --min-disk 0 --need git --push-guard 2>&1)"
expect_grep 'missing +push guard +3 of 5 rules' "$out" "FIRST_PUSH_CONFIG is ignored; the owner comes from ~/.ctlhq/first-push.toml"
printf 'github_owner = "ACME"  # my account\n' >"$settings"
out="$(grun "$tmp/sys-ready.cfg" --min-disk 0 --need git --push-guard)"
expect_grep "ready +push guard +5 of 5 rules in $tmp/sys-ready.cfg; letter case differs from github_owner, and git matches addresses exactly$" "$out" "an owner with a trailing comment and other letter case matches the rules"
printf 'github_owner = "acme"\n' >"$settings"
expect_grep 'FIRST_PUSH_CONFIG is ignored' "$("$pf" --help)" "--help says FIRST_PUSH_CONFIG is ignored"
expect_grep 'github_owner = "<your GitHub account>"' "$("$pf" --help)" "--help names the setting"
res="$(grun "$tmp/sys-partial.cfg" --json --min-disk 0 --need git --push-guard | python3 -c '
import json, sys
c = [x for x in json.load(sys.stdin)["checks"] if x["check"] == "push guard"]
print(len(c), c[0]["state"], "ctlhq-preflight --help, check 8" in c[0]["fix"])
')"
expect_eq "1 missing True" "$res" "--json carries the push guard check"

echo "$pass checks passed"
if [ "$fail" -gt 0 ]; then
	echo "$fail checks failed"
	exit 1
fi
