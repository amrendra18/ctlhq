#!/usr/bin/env bash
# tests/ctlhq-name-check/run.sh: checks for skills/name-options/bin/ctlhq-name-check through bin/ctlhq-name-check.
# Offline: a scratch PATH, projects folder, and ctlhq root, and a local HTTP server on
# 127.0.0.1 for the npm and PyPI lookups. Prints "N checks passed"; exits 1 on any failure.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
nc="$root/bin/ctlhq-name-check"
tmpbase="${TMPDIR:-/tmp}"; tmp="$(mktemp -d "${tmpbase%/}/name-check-test.XXXXXX")"
srv_pid=""
cleanup() { if [ -n "$srv_pid" ]; then kill "$srv_pid" 2>/dev/null; wait "$srv_pid" 2>/dev/null; fi; rm -rf "$tmp"; }
trap cleanup EXIT
pass=0
fail=0
ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL: $1"; }
expect_rc() { if [ "$1" -eq "$2" ]; then ok; else bad "$3 (expected exit $1, got $2)"; fi; }
expect_eq() { if [ "$1" = "$2" ]; then ok; else bad "$3 (expected '$1', got '$2')"; fi; }
expect_grep() { if printf '%s\n' "$2" | grep -Eq -- "$1"; then ok; else bad "$3 (no line matches: $1)"; fi; }
col() { printf '%s\n' "$3" | awk -F'\t' -v n="$1" -v c="$2" '$2==n {print $c; exit}'; }

mkdir -p "$tmp/path" "$tmp/projects/Sampletool" "$tmp/fn/skills/garden/bin" "$tmp/fn/bin"
printf '#!/bin/sh\n' > "$tmp/path/zqtool"; chmod +x "$tmp/path/zqtool"
touch "$tmp/fn/bin/ctlhq-status" "$tmp/fn/skills/garden/bin/ctlhq-doc-diet"
args=(--projects "$tmp/projects" --root "$tmp/fn")
run() { PATH="$tmp/path:/usr/bin:/bin" "$nc" "$@"; }

# 1. --help.
out="$("$nc" --help 2>&1)"; expect_rc 0 $? "--help exits 0"
expect_grep '^ctlhq-name-check: ' "$(printf '%s\n' "$out" | head -1)" "--help first line is 'ctlhq-name-check: ...'"

# 2. Each collision source, and a free name.
out="$(run "${args[@]}" zqtool sampletool garden ctlhq-doc-diet ctlhq-status cd zzfree)"; expect_rc 1 $? "any collision exits 1"
expect_grep $'^#\tname\tcommand\tprojects\tctlhq\tnpm\tpypi\tverdict$' "$out" "header row"
expect_eq "$tmp/path/zqtool" "$(col zqtool 3 "$out")" "command -v finds a program on PATH"
expect_eq "$tmp/projects/Sampletool" "$(col sampletool 4 "$out")" "projects folder matched case-insensitively"
expect_eq "skill skills/garden" "$(col garden 5 "$out")" "ctlhq skill matched"
expect_eq "tool skills/garden/bin/ctlhq-doc-diet" "$(col ctlhq-doc-diet 5 "$out")" "skill-owned tool matched"
expect_eq "tool bin/ctlhq-status" "$(col ctlhq-status 5 "$out")" "collection tool matched"
expect_eq cd "$(col cd 3 "$out")" "shell builtin collides"
expect_eq free "$(col zzfree 8 "$out")" "unused name is free"
expect_eq "not checked" "$(col zzfree 6 "$out")" "npm not checked without --registry"
expect_eq "1	zqtool" "$(printf '%s\n' "$out" | sed -n 2p | cut -f1,2)" "rows numbered in argument order"

# 3. All free exits 0; --json.
run "${args[@]}" zzfree yyfree >/dev/null; expect_rc 0 $? "all free exits 0"
json="$(run "${args[@]}" --json zzfree sampletool)"
expect_eq "free collides" "$(printf '%s' "$json" | python3 -c 'import json,sys; print(" ".join(r["verdict"] for r in json.load(sys.stdin)))')" "--json verdicts"

# 4. Usage errors.
run "${args[@]}" >/dev/null 2>&1; expect_rc 2 $? "no name exits 2"
run "${args[@]}" 'bad name' >/dev/null 2>&1; expect_rc 2 $? "name with a space exits 2"
run "${args[@]}" --bogus x >/dev/null 2>&1; expect_rc 2 $? "unknown option exits 2"

# 5. --registry against a local server: npm taken, PyPI normalised name taken, both 404 free.
mkdir -p "$tmp/www/npm" "$tmp/www/pypi/my-pkg"
echo '{}' > "$tmp/www/npm/takenpkg"; echo '{}' > "$tmp/www/pypi/my-pkg/json"
port="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')"
(cd "$tmp/www" && exec python3 -m http.server "$port" --bind 127.0.0.1 >/dev/null 2>&1) &
srv_pid=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do curl -s "http://127.0.0.1:$port/" >/dev/null 2>&1 && break; sleep 0.3; done
reg() { NAME_CHECK_NPM_URL="http://127.0.0.1:$port/npm/{name}" NAME_CHECK_PYPI_URL="http://127.0.0.1:$port/pypi/{name}/json" run "${args[@]}" --registry "$@"; }
out="$(reg takenpkg My_Pkg zzfree)"; expect_rc 1 $? "registry hit exits 1"
expect_eq taken "$(col takenpkg 6 "$out")" "npm 200 is taken"
expect_eq taken "$(col My_Pkg 7 "$out")" "PyPI name normalised (My_Pkg -> my-pkg) and taken"
expect_eq "free free free" "$(col zzfree 6 "$out") $(col zzfree 7 "$out") $(col zzfree 8 "$out")" "404 on both registries is free"

# 6. Registry unreachable: exit 3 when nothing else collides, 1 when something does.
down() { NAME_CHECK_NPM_URL="http://127.0.0.1:9/{name}" NAME_CHECK_PYPI_URL="http://127.0.0.1:9/{name}" run "${args[@]}" --registry --timeout 2 "$@"; }
err="$(down zzfree 2>&1 >/dev/null)"; expect_rc 3 $? "unreachable registry, no collision exits 3"
expect_grep '^ctlhq-name-check: registry unreachable: .*incomplete' "$err" "exit 3 says the check is incomplete"
out="$(down zzfree 2>/dev/null)"
expect_eq "unknown" "$(col zzfree 8 "$out")" "unreachable registry, no collision: verdict unknown, not free"
out="$(down sampletool 2>/dev/null)"; expect_rc 1 $? "collision wins over unreachable (exit 1)"
expect_eq unreachable "$(col sampletool 6 "$out")" "unreachable cell shown"

echo "$pass checks passed"
[ "$fail" -eq 0 ] || { echo "$fail checks failed"; exit 1; }
