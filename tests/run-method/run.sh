#!/usr/bin/env bash
set -u
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
doc="$root/skills/run-method/references/hooks-and-permissions.md"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/run-method-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
pass=0
fail=0
ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL: $1"; }
expect_rc() { if [ "$1" -eq "$2" ]; then ok; else bad "$3 (expected exit $1, got $2)"; fi; }
expect_eq() { if [ "$1" = "$2" ]; then ok; else bad "$3 (expected '$1', got '$2')"; fi; }

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
mkdir -p "$tmp/bin"
printf '#!/bin/sh\n[ "$1 $2" = "setup --revision" ] && git init -q -b main && printf ".local/\\n" >> .gitignore\nexit 0\n' > "$tmp/bin/first-commit"
chmod +x "$tmp/bin/first-commit"

block() {
	awk -v want="$1" '/^## 3\. /{s=1; next} /^## /{s=0} s && /^```sh$/{n++; on=(n==want); next} s && /^```$/{on=0} on' "$doc" \
		| sed -e 's|^  cd /path/to/repo$|  cd "$PROJECT"|' -e 's|^  REV=<.*>$|  REV=0000000000000000000000000000000000000000|'
}

new_project() {
	rm -rf "$tmp/p"; mkdir -p "$tmp/p"
	cp "$root/skills/run-method/references/PLAN-template.md" "$tmp/p/PLAN.md"
	printf '# Demo\n' > "$tmp/p/README.md"
	printf 'node_modules/\n' > "$tmp/p/.gitignore"
}

for n in 1 2; do
	block "$n" > "$tmp/block$n.sh"
	new_project
	for run in 1 2; do
		PROJECT="$tmp/p" PATH="$tmp/bin:$PATH" bash "$tmp/block$n.sh" >/dev/null 2>"$tmp/err"
		expect_rc 0 $? "block $n run $run exits 0 ($(head -1 "$tmp/err"))"
	done
	expect_eq 1 "$(grep -cxF '/PLAN.md' "$tmp/p/.gitignore")" "block $n run twice: .gitignore lists /PLAN.md once"
	expect_eq 1 "$(grep -cxF 'node_modules/' "$tmp/p/.gitignore")" "block $n keeps the line .gitignore held before"
	git -C "$tmp/p" check-ignore -q PLAN.md; expect_rc 0 $? "block $n: git ignores PLAN.md, the start-project section 6 step 3 check"
done

sed "s%grep -qsxF '/PLAN.md' .gitignore || %%" "$tmp/block2.sh" > "$tmp/unguarded.sh"
if cmp -s "$tmp/block2.sh" "$tmp/unguarded.sh"; then bad "control: removing the grep guard changed nothing"; else ok; fi
new_project
for run in 1 2; do PROJECT="$tmp/p" bash "$tmp/unguarded.sh" >/dev/null 2>&1; done
expect_eq 2 "$(grep -cxF '/PLAN.md' "$tmp/p/.gitignore")" "control: without the grep guard two runs list /PLAN.md twice"

if [ "$fail" -gt 0 ]; then
	echo "$fail checks failed, $pass checks passed"
	exit 1
fi
echo "$pass checks passed"
