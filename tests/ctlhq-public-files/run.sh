#!/usr/bin/env bash
set -u
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
tool="$root/bin/ctlhq-public-files"
pass=0
fail=0
ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL: $1"; }
expect_rc() { if [ "$1" -eq "$2" ]; then ok; else bad "$3 (expected exit $1, got $2)"; fi; }
expect_eq() { if [ "$1" = "$2" ]; then ok; else bad "$3 (expected '$1', got '$2')"; fi; }
expect_grep() { if printf '%s\n' "$2" | grep -Eq -- "$1"; then ok; else bad "$3 (no line matches: $1)"; fi; }

tmp="$(mktemp -d "${TMPDIR:-/tmp}/ctlhq-public-files-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

out="$("$tool" --help 2>&1)"; expect_rc 0 $? "--help exits 0"
expect_grep '^ctlhq-public-files: ' "$(printf '%s\n' "$out" | head -1)" "--help first line is 'ctlhq-public-files: ...'"
"$tool" --bogus >/dev/null 2>&1; expect_rc 2 $? "an unknown argument exits 2"
"$tool" --root >/dev/null 2>&1; expect_rc 2 $? "--root with no value exits 2"
"$tool" --root "$tmp/nowhere" >/dev/null 2>&1; expect_rc 2 $? "a missing folder exits 2"
mkdir -p "$tmp/plain"
"$tool" --root "$tmp/plain" >/dev/null 2>&1; expect_rc 2 $? "a folder outside a Git repository exits 2"

add() {
	for f in "$@"; do
		mkdir -p "$(dirname "$f")"
		printf 'x\n' >"$f"
	done
}

clean="$tmp/clean"
git init -q "$clean"
(cd "$clean" && add README.md LICENSE src/plan.go src/baseline.go skills/design-options/SKILL.md \
	references/PLAN-template.md RELEASE_NOTES.md tests/mocks/store.go tests/fixtures/plan.md \
	.old-baseline.json benchmarks/run.sh docs/engineering-baseline.md results/.keep.txt docs/.metrics.tsv \
	internal/mocks/store.go src/mocks/handlers.ts mocks/store.go pkg/render/wireframe.go src/design/tokens.css && git add -A)
out="$("$tool" --root "$clean" 2>&1)"; expect_rc 0 $? "a tree of look-alikes exits 0"
expect_eq "0 to decide, 0 allowed, 19 listed" "$out" "look-alikes print only the count"

fx="$tmp/fx"
git init -q "$fx"
(cd "$fx" && add PLAN.md docs/release-plan.md PRD.md GOAL.md PROMPT.md REPORT.md notes.txt docs/plans/phase-one.txt \
	docs/design/page.png mockup.png src/wireframe-home.html mock/index.html mock/server.go wireframes/flow.txt \
	results/2026/run.csv results/summary.md benchmark-numbers.json metrics.tsv tests/results/run.jsonl \
	CLAUDE.md AGENTS.md .cursorrules .mcp.json .vscode/settings.json .cursor/rules.md a.code-workspace \
	.github/copilot-instructions.md tests/.claude/settings.json \
	README.md gone/PLAN.md && git add -A && rm gone/PLAN.md)
(cd "$fx" && printf 'scratch/\n' >.gitignore && add scratch/PLAN.md untracked/ROADMAP.md && git add .gitignore)
(cd "$fx" && ln -s README.md design.png && printf 'x\n' >"$(printf 'new\nline-plan.md')")
out="$("$tool" --root "$fx" 2>&1)"; rc=$?
expect_rc 1 "$rc" "matches exit 1"
for row in \
	'PLAN.md: planning material' 'docs/release-plan.md: planning material' 'PRD.md: planning material' \
	'GOAL.md: planning material' 'PROMPT.md: planning material' 'REPORT.md: planning material' \
	'notes.txt: planning material' 'docs/plans/phase-one.txt: planning material' \
	'untracked/ROADMAP.md: planning material' \
	'docs/design/page.png: design mock' 'mockup.png: design mock' 'src/wireframe-home.html: design mock' \
	'mock/index.html: design mock' 'mock/server.go: design mock' 'wireframes/flow.txt: design mock' 'design.png: design mock' \
	'results/2026/run.csv: measurement file' 'results/summary.md: measurement file' 'benchmark-numbers.json: measurement file' \
	'metrics.tsv: measurement file' 'tests/results/run.jsonl: measurement file' \
	'CLAUDE.md: tool config' 'AGENTS.md: tool config' '.cursorrules: tool config' '.mcp.json: tool config' \
	'.vscode/settings.json: tool config' '.cursor/rules.md: tool config' 'a.code-workspace: tool config' \
	'.github/copilot-instructions.md: tool config' 'tests/.claude/settings.json: tool config'; do
	expect_eq 1 "$(printf '%s\n' "$out" | grep -Fxc -- "$row")" "reports: $row"
done
expect_grep "^'new\\\\nline-plan\.md': planning material$" "$out" "a control character in a name prints escaped"
expect_eq 0 "$(printf '%s\n' "$out" | grep -c 'scratch/')" "an ignored file is not listed"
expect_eq 0 "$(printf '%s\n' "$out" | grep -c 'gone/')" "a tracked file gone from disk is not listed"
expect_eq 0 "$(printf '%s\n' "$out" | grep -c 'README.md')" "a needed file gets no line"
expect_eq "31 to decide, 0 allowed, 33 listed" "$(printf '%s\n' "$out" | tail -1)" "the count line counts matches and listed files"

mkdir -p "$fx/docs"
sub="$("$tool" --root "$fx/docs" 2>&1 | grep -c '^PLAN.md: ')"
expect_eq 1 "$sub" "--root in a subfolder reads the whole repository, with paths from the top"
wd="$(cd "$fx" && "$tool" 2>&1 | tail -1)"
expect_eq "31 to decide, 0 allowed, 33 listed" "$wd" "with no --root it reads the working folder"

local_mock="$tmp/local-mock"
git init -q "$local_mock"
(cd "$local_mock" && printf '.local/\n' >.gitignore && add .local/mock/index.html)
out="$("$tool" --root "$local_mock" 2>&1)"; expect_rc 0 $? "an ignored .local/mock/index.html exits 0"
expect_eq "0 to decide, 0 allowed, 1 listed" "$out" "an ignored .local/mock/index.html gets no line"
rm "$local_mock/.gitignore"
out="$("$tool" --root "$local_mock" 2>&1)"; expect_rc 1 $? "a .local/mock/index.html Git does not ignore exits 1"
expect_grep '^\.local/mock/index\.html: design mock$' "$out" "a .local/mock/index.html Git does not ignore gets a line"

kept="$tmp/kept"
git init -q "$kept"
(cd "$kept" && add AGENTS.md docs/plans/one.md docs/plans/two.md PRD.md README.md && git add -A)
printf '# method project\n\nAGENTS.md  instructions for contributors who use a coding agent\ndocs/plans/\tthe public roadmap\n' >"$tmp/allow"
out="$("$tool" --root "$kept" --allow "$tmp/allow" 2>&1)"; rc=$?
expect_rc 1 "$rc" "a match with no allow row still exits 1"
expect_eq "AGENTS.md: tool config (allowed: instructions for contributors who use a coding agent)
PRD.md: planning material
docs/plans/one.md: planning material (allowed: the public roadmap)
docs/plans/two.md: planning material (allowed: the public roadmap)
1 to decide, 3 allowed, 5 listed" "$out" "an allow row covers a file and a folder, and prints its reason"
printf 'PRD.md  the requirements strangers read\n' >"$tmp/allow2"
out="$("$tool" --root "$kept" --allow "$tmp/allow" --allow "$tmp/allow2" 2>&1)"; rc=$?
expect_rc 0 "$rc" "every match allowed, from two allow files, exits 0"
expect_eq "0 to decide, 4 allowed, 5 listed" "$(printf '%s\n' "$out" | tail -1)" "two allow files add up"
printf 'AGENTS.md\n' >"$tmp/allow-bad"
out="$("$tool" --root "$kept" --allow "$tmp/allow-bad" 2>&1)"; expect_rc 2 $? "an allow row with no reason exits 2"
expect_grep 'allow-bad:1: write PATH, two spaces or a tab, then the reason' "$out" "an allow row with no reason names the file and line"
"$tool" --root "$kept" --allow "$tmp/no-such-file" >/dev/null 2>&1; expect_rc 2 $? "a missing allow file exits 2"
"$tool" --root "$kept" --allow >/dev/null 2>&1; expect_rc 2 $? "--allow with no value exits 2"

names_only="$tmp/names-only"
git init -q "$names_only"
(cd "$names_only" && printf 'PLAN.md: planning material\n' >ordinary.txt && add sealed-plan.md && git add -A && chmod 000 sealed-plan.md)
out="$("$tool" --root "$names_only" 2>&1)"; rc=$?
chmod 600 "$names_only/sealed-plan.md"
expect_rc 1 "$rc" "a file the tool cannot open still gets its line"
expect_eq "sealed-plan.md: planning material
1 to decide, 0 allowed, 2 listed" "$out" "the tool matches names and reads no content"

stub="$tmp/stub"
mkdir -p "$stub"
real_git="$(command -v git)"
cat >"$stub/git" <<EOF
#!/bin/sh
case " \$* " in
*" ls-files "*) echo "stand-in failure" >&2; exit 128 ;;
esac
exec "$real_git" "\$@"
EOF
chmod +x "$stub/git"
out="$(PATH="$stub:$PATH" "$tool" --root "$fx" 2>&1)"; rc=$?
expect_rc 2 "$rc" "a failed git ls-files exits 2"
expect_grep '^ctlhq-public-files: git ls-files failed in .*stand-in failure$' "$out" "a failed git ls-files prints git's error"

if [ "$fail" -gt 0 ]; then
	echo "$fail checks failed, $pass checks passed"
	exit 1
fi
echo "$pass checks passed"
