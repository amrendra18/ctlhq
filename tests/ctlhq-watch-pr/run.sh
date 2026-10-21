#!/usr/bin/env bash
# tests/ctlhq-watch-pr/run.sh: checks for the bash wrapper skills/ctlhq-mode/bin/ctlhq-watch-pr through
# bin/ctlhq-watch-pr. Bun is not installed here, so the bun code itself
# (skills/ctlhq-mode/scripts/watch-pr/*.ts) is untested by this script; its own tests are
# scripts/watch-pr/*.test.ts, run with bun test. gh is never called.
# Covered: the help text (and that it lists every option, verdict, and exit code the TypeScript
# source defines), exit 127 with the install line when bun is missing, and argument handling
# through a stub bun on PATH (target path, arguments kept verbatim, exit code passed back,
# stdin and environment passed through, symlinks resolved).
# Prints "N checks passed" and exits 1 when any check fails. Read-only for the repository.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
tool="$root/bin/ctlhq-watch-pr"
target="$root/skills/ctlhq-mode/scripts/watch-pr/watch-pr"
src="$root/skills/ctlhq-mode/scripts/watch-pr"
tmp="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/watch-pr-test.XXXXXX")" && pwd -P)"
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
printf '%s' "${GH_REPO:-}" > "$STUB_DIR/env"
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
	expect_grep '^ctlhq-watch-pr: .*Needs bun and gh\.$' "$(printf '%s\n' "$out" | head -1)" "--help first line is 'ctlhq-watch-pr: ...'"
	expect_eq "$out" "$(PATH="$nobun" "$w" -h 2>&1)" "-h prints the same help"
	expect_eq "$out" "$(PATH="$nobun" "$w" --pr 5 -h 2>&1)" "-h after a command prints the wrapper help"
	expect_grep '^  127  bun is not installed' "$out" "--help documents exit 127"
	expect_grep '^Install bun with: curl -fsSL https://bun.sh/install \| bash$' "$out" "--help prints the install line"
	# Missing bun.
	out="$(PATH="$nobun" "$w" --pr 5 2>"$tmp/err")"; rc=$?; err="$(cat "$tmp/err")"
	expect_rc 127 "$rc" "without bun, a command exits 127"
	expect_eq "ctlhq-watch-pr needs bun. Install it with: curl -fsSL https://bun.sh/install | bash" "$err" "without bun, stderr is the install line"
	expect_eq "" "$out" "without bun, stdout is empty"
	PATH="$nobun" "$w" >/dev/null 2>&1; expect_rc 127 $? "without bun, no arguments exits 127"
	# Stub bun: target, arguments verbatim, exit code, stdin, environment.
	rm -f "$tmp/args"
	printf 'piped input\n' | PATH="$stubpath" GH_REPO="$tmp/repo dir" "$w" --owner "$tmp/s" --repo 'name with space' --stack-prs '*' '' 2>/dev/null; rc=$?
	expect_rc 0 "$rc" "with bun, the exit code of bun is returned (0)"
	expect_eq "$(printf '%s\n' "$t" --owner "$tmp/s" --repo 'name with space' --stack-prs '*' '')" "$(cat "$tmp/args" 2>/dev/null)" "bun gets the script path, then every argument verbatim"
	expect_eq "piped input" "$(cat "$tmp/stdin" 2>/dev/null)" "stdin reaches bun"
	expect_eq "$tmp/repo dir" "$(cat "$tmp/env" 2>/dev/null)" "GH_REPO reaches bun"
	for code in 2 5 64; do
		STUB_RC=$code PATH="$stubpath" "$w" --status-only </dev/null >/dev/null 2>&1; expect_rc "$code" $? "with bun, bun's exit $code is returned"
	done
	rm -f "$tmp/args"
	PATH="$stubpath" "$w" </dev/null >/dev/null 2>&1
	expect_eq "$t" "$(cat "$tmp/args" 2>/dev/null)" "no arguments: bun gets only the script path"
}

# 1-3. The real wrapper, through the bin/ symlink and directly.
wrapper_checks "$tool" "$target"
[ -f "$target" ] && ok || bad "the bun target $target exists"
real="$root/skills/ctlhq-mode/bin/ctlhq-watch-pr"
rm -f "$tmp/args"; PATH="$stubpath" "$real" --status-only </dev/null >/dev/null 2>&1
expect_eq "$target|--status-only" "$(paste -sd'|' "$tmp/args" 2>/dev/null)" "the wrapper run by its real path finds the same target"
mkdir -p "$tmp/l1" "$tmp/l2"
ln -s "$tool" "$tmp/l2/watch-pr-abs"
ln -s ../l2/watch-pr-abs "$tmp/l1/ctlhq-watch-pr"
rm -f "$tmp/args"; PATH="$stubpath" "$tmp/l1/ctlhq-watch-pr" --status-only </dev/null >/dev/null 2>&1
expect_eq "$target|--status-only" "$(paste -sd'|' "$tmp/args" 2>/dev/null)" "a chain of relative and absolute symlinks resolves to the same target"
rm -f "$tmp/args"; (cd "$tmp" && PATH="$tmp/l1:$stubpath" ctlhq-watch-pr --status-only </dev/null >/dev/null 2>&1)
expect_eq "$target|--status-only" "$(paste -sd'|' "$tmp/args" 2>/dev/null)" "the wrapper found on PATH resolves to the same target"

# 4. The help lists every command, option, and verdict the TypeScript source defines.
help="$("$tool" --help)"
help_checks() { # help-text: compare with the source
	local h="$1" missing
	missing="$(grep -oE '"--[a-z-]+' "$src/cli.ts" | tr -d '"' | sort -u | while read -r o; do
		printf '%s\n' "$h" | grep -Eq -- "^  $o( |$)" || echo "$o"; done)"
	expect_eq "" "$missing" "every option in cli.ts has its own line in the help"
	missing="$(printf '%s\n' "$h" | sed -n 's/^Verdicts: \(.*\) (see .*/\1/p' | tr ',' '\n' | tr -d ' ' | while read -r v; do
		grep -Eq "(Progress|Terminal)<\"$v\"" "$src/types.ts" || echo "$v"; done)"
	[ -n "$(printf '%s\n' "$h" | grep '^Verdicts: ')" ] || missing="no Verdicts line"
	expect_eq "" "$missing" "every verdict the help names is a verdict kind in types.ts"
	missing="$(grep -oE 'exitCode: [0-9]+' "$src/policy.ts" | awk '{print $2}' | sort -u | while read -r c; do
		printf '%s\n' "$h" | grep -Eq "^  $c +[a-zA-Z]" || echo "$c"; done)"
	expect_eq "" "$missing" "every exit code in policy.ts is documented"
}
help_checks "$help"
grep -q 'error.exitCode === 0 ? 0 : 64' "$src/cli.ts" && ok || bad "cli.ts maps a usage error to exit 64, as the help says"
expect_grep '^  64   usage error' "$help" "--help documents exit 64"
expect_grep '^--stack and --queued-stack conflict\. --stack-prs requires --queued-stack\.$' "$help" "--help states the option conflicts"
grep -q 'conflicts("queuedStack")' "$src/cli.ts" && ok || bad "cli.ts declares the --stack and --queued-stack conflict"

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
mk="$tmp/mut/skills/ctlhq-mode"; mkdir -p "$mk/bin" "$mk/scripts/watch-pr"; : > "$mk/scripts/watch-pr/watch-pr"
mt="$mk/scripts/watch-pr/watch-pr"
mutate() { # sed-expression
	sed "$1" "$real" > "$mk/bin/ctlhq-watch-pr"; chmod +x "$mk/bin/ctlhq-watch-pr"
	if cmp -s "$real" "$mk/bin/ctlhq-watch-pr"; then bad "control: planted defect '$1' did not change the wrapper"; else ok; fi
}
mutate 's/exit 127/exit 1/'; control "exit 1 instead of 127 without bun" "$mk/bin/ctlhq-watch-pr" wrapper
mutate 's/exec bun "\$scripts\/watch-pr\/watch-pr" "\$@"/exec bun "$scripts\/watch-pr\/watch-pr" $*/'; control "unquoted arguments" "$mk/bin/ctlhq-watch-pr" wrapper
mutate 's/	-h|--help) usage; exit 0 ;;/	--help) usage; exit 0 ;;/'; control "no -h" "$mk/bin/ctlhq-watch-pr" wrapper
control "a help without the --allow-draft line" "$(printf '%s\n' "$help" | grep -v -- '--allow-draft')" help
control "a help without exit 6" "$(printf '%s\n' "$help" | grep -v '^  6 ')" help
control "a help naming a verdict the source lacks" "$(printf '%s\n' "$help" | sed 's/WAITING, /WAITING, PAUSED, /')" help

echo "$pass checks passed"
[ "$fail" -eq 0 ] || { echo "$fail checks failed"; exit 1; }
