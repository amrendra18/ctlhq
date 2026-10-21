#!/usr/bin/env bash
# tests/ctlhq-orch/run.sh: checks for the bash wrapper skills/ctlhq-mode/bin/ctlhq-orch through bin/ctlhq-orch.
# Bun is not installed here, so the bun code itself (skills/ctlhq-mode/scripts/orch/*.ts) is
# untested by this script; its own tests are scripts/orch/orch.test.ts, run with bun test.
# Covered: the help text (and that it lists every command, option, and verdict the TypeScript
# source defines), exit 127 with the install line when bun is missing, and argument handling
# through a stub bun on PATH (target path, arguments kept verbatim, exit code passed back,
# stdin and environment passed through, symlinks resolved).
# Prints "N checks passed" and exits 1 when any check fails. Read-only for the repository.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
tool="$root/bin/ctlhq-orch"
target="$root/skills/ctlhq-mode/scripts/orch/orch.ts"
src="$root/skills/ctlhq-mode/scripts/orch"
tmp="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/orch-test.XXXXXX")" && pwd -P)"
trap 'rm -rf "$tmp"' EXIT
pass=0
fail=0
ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); [ -n "${quiet:-}" ] || echo "FAIL: $1"; }
expect_rc() { if [ "$1" -eq "$2" ]; then ok; else bad "$3 (expected exit $1, got $2)"; fi; }
expect_eq() { if [ "$1" = "$2" ]; then ok; else bad "$3 (expected '$1', got '$2')"; fi; }
expect_grep() { if printf '%s\n' "$2" | grep -Eq -- "$1"; then ok; else bad "$3 (no line matches: $1)"; fi; }

nobun="/usr/bin:/bin"
if PATH="$nobun" command -v bun >/dev/null 2>&1; then bad "setup: bun is on $nobun, so the missing-bun checks cannot run"; fi
mkdir -p "$tmp/stubs"
cat > "$tmp/stubs/bun" <<'SH'
#!/bin/sh
for a in "$@"; do printf '%s\n' "$a"; done > "$STUB_DIR/args"
printf '%s' "${ORCH_STORE:-}" > "$STUB_DIR/env"
cat > "$STUB_DIR/stdin"
exit "${STUB_RC:-0}"
SH
chmod +x "$tmp/stubs/bun"
export STUB_DIR="$tmp"
stubpath="$tmp/stubs:/usr/bin:/bin"

# wrapper_checks <wrapper> <expected bun target>: every wrapper behaviour; used on the real
# wrapper and, for the positive controls, on planted defective copies.
wrapper_checks() {
	local w="$1" t="$2" out err rc
	# Help.
	out="$(PATH="$nobun" "$w" --help 2>&1)"; rc=$?
	expect_rc 0 "$rc" "--help exits 0 without bun"
	expect_grep '^ctlhq-orch: .*Needs bun\.$' "$(printf '%s\n' "$out" | head -1)" "--help first line is 'ctlhq-orch: ...'"
	expect_eq "$out" "$(PATH="$nobun" "$w" -h 2>&1)" "-h prints the same help"
	expect_eq "$out" "$(PATH="$nobun" "$w" unit add u1 -h 2>&1)" "-h after a command prints the wrapper help"
	expect_grep '^  127  bun is not installed' "$out" "--help documents exit 127"
	expect_grep '^Install bun with: curl -fsSL https://bun.sh/install \| bash$' "$out" "--help prints the install line"
	# Missing bun.
	out="$(PATH="$nobun" "$w" init 2>"$tmp/err")"; rc=$?; err="$(cat "$tmp/err")"
	expect_rc 127 "$rc" "without bun, a command exits 127"
	expect_eq "ctlhq-orch needs bun. Install it with: curl -fsSL https://bun.sh/install | bash" "$err" "without bun, stderr is the install line"
	expect_eq "" "$out" "without bun, stdout is empty"
	PATH="$nobun" "$w" >/dev/null 2>&1; expect_rc 127 $? "without bun, no arguments exits 127"
	# Stub bun: target, arguments verbatim, exit code, stdin, environment.
	rm -f "$tmp/args"
	printf 'piped input\n' | PATH="$stubpath" ORCH_STORE="$tmp/store dir" "$w" --store "$tmp/s" unit add 'id with space' --track '*' '' 2>/dev/null; rc=$?
	expect_rc 0 "$rc" "with bun, the exit code of bun is returned (0)"
	expect_eq "$(printf '%s\n' "$t" --store "$tmp/s" unit add 'id with space' --track '*' '')" "$(cat "$tmp/args" 2>/dev/null)" "bun gets the script path, then every argument verbatim"
	expect_eq "piped input" "$(cat "$tmp/stdin" 2>/dev/null)" "stdin reaches bun"
	expect_eq "$tmp/store dir" "$(cat "$tmp/env" 2>/dev/null)" "ORCH_STORE reaches bun"
	for code in 1 2 7; do
		STUB_RC=$code PATH="$stubpath" "$w" status </dev/null >/dev/null 2>&1; expect_rc "$code" $? "with bun, bun's exit $code is returned"
	done
	rm -f "$tmp/args"
	PATH="$stubpath" "$w" </dev/null >/dev/null 2>&1
	expect_eq "$t" "$(cat "$tmp/args" 2>/dev/null)" "no arguments: bun gets only the script path"
}

# 1-3. The real wrapper, through the bin/ symlink and directly.
wrapper_checks "$tool" "$target"
[ -f "$target" ] && ok || bad "the bun target $target exists"
real="$root/skills/ctlhq-mode/bin/ctlhq-orch"
rm -f "$tmp/args"; PATH="$stubpath" "$real" init </dev/null >/dev/null 2>&1
expect_eq "$target|init" "$(paste -sd'|' "$tmp/args" 2>/dev/null)" "the wrapper run by its real path finds the same target"
mkdir -p "$tmp/l1" "$tmp/l2"
ln -s "$tool" "$tmp/l2/orch-abs"
ln -s ../l2/orch-abs "$tmp/l1/ctlhq-orch"
rm -f "$tmp/args"; PATH="$stubpath" "$tmp/l1/ctlhq-orch" init </dev/null >/dev/null 2>&1
expect_eq "$target|init" "$(paste -sd'|' "$tmp/args" 2>/dev/null)" "a chain of relative and absolute symlinks resolves to the same target"
rm -f "$tmp/args"; (cd "$tmp" && PATH="$tmp/l1:$stubpath" ctlhq-orch init </dev/null >/dev/null 2>&1)
expect_eq "$target|init" "$(paste -sd'|' "$tmp/args" 2>/dev/null)" "the wrapper found on PATH resolves to the same target"

# 4. The help lists every command, option, and verdict the TypeScript source defines.
help="$("$tool" --help)"
help_checks() { # help-text: compare with the source
	local h="$1" missing
	missing="$(HELP="$h" python3 - "$src/orch.ts" <<'PY'
import os, re, sys
src = open(sys.argv[1]).read()
help_lines = os.environ["HELP"].split("\n")
for parent, name in re.findall(r'leaf\(\s*(\w+),\s*"([a-z]+)', src):
    cmd = name if parent == "program" else parent + " " + name
    if not any(re.match(r"^  " + re.escape(cmd) + r"( |$)", l) for l in help_lines):
        print(cmd)
PY
)"
	expect_eq "" "$missing" "every leaf command in orch.ts is in the help"
	missing="$(grep -oE '"--[a-z-]+' "$src/orch.ts" | tr -d '"' | sort -u | while read -r o; do
		printf '%s\n' "$h" | grep -q -- "$o" || echo "$o"; done)"
	expect_eq "" "$missing" "every option in orch.ts is in the help"
	missing="$(sed -n '/^export type Verdict =/,/;$/p' "$src/store.ts" | grep -oE '"[a-z-]+"' | tr -d '"' | while read -r v; do
		printf '%s\n' "$h" | grep '^Verdicts:' | grep -q -- "$v" || echo "$v"; done)"
	expect_eq "" "$missing" "every verdict in store.ts is in the help"
}
help_checks "$help"
grep -q 'error.exitCode === 0 ? 0 : 1' "$src/orch.ts" && ok || bad "orch.ts maps a commander usage error to exit 1, as the help says"
grep -q 'return 2;' "$src/orch.ts" && ok || bad "orch.ts returns 2 for a missing row, as the help says"
expect_grep '^  1    usage error' "$help" "--help documents exit 1"
expect_grep '^  2    a row is not found' "$help" "--help documents exit 2"

# 5. Positive controls: planted defects must make the checks above fail.
control() { # label wrapper-or-help kind
	local p0=$pass f0=$fail
	quiet=1
	if [ "$3" = wrapper ]; then wrapper_checks "$2" "$mt"; else help_checks "$2"; fi
	quiet=
	local caught=$((fail - f0))
	pass=$p0; fail=$f0
	if [ "$caught" -gt 0 ]; then ok; else bad "control: $1 is not caught"; fi
}
mk="$tmp/mut/skills/ctlhq-mode"; mkdir -p "$mk/bin" "$mk/scripts/orch"; : > "$mk/scripts/orch/orch.ts"
mt="$mk/scripts/orch/orch.ts"
mutate() { # sed-expression
	sed "$1" "$real" > "$mk/bin/ctlhq-orch"; chmod +x "$mk/bin/ctlhq-orch"
	if cmp -s "$real" "$mk/bin/ctlhq-orch"; then bad "control: planted defect '$1' did not change the wrapper"; else ok; fi
}
mutate 's/exit 127/exit 1/'; control "exit 1 instead of 127 without bun" "$mk/bin/ctlhq-orch" wrapper
mutate 's/exec bun "\$scripts\/orch\/orch.ts" "\$@"/exec bun "$scripts\/orch\/orch.ts" $*/'; control "unquoted arguments" "$mk/bin/ctlhq-orch" wrapper
mutate 's/	-h|--help) usage; exit 0 ;;/	--help) usage; exit 0 ;;/'; control "no -h" "$mk/bin/ctlhq-orch" wrapper
control "a help without the inbox drain line" "$(printf '%s\n' "$help" | grep -v 'inbox drain')" help
control "a help without --peek" "$(printf '%s\n' "$help" | sed 's/ \[--peek\]//')" help

echo "$pass checks passed"
[ "$fail" -eq 0 ] || { echo "$fail checks failed"; exit 1; }
