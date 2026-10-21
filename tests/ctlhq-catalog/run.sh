#!/usr/bin/env bash
# tests/ctlhq-catalog/run.sh: checks for bin/ctlhq-catalog. build and open write into the
# tool's own repository (.local/catalog/), so they run on a copy in a temp folder: skills/,
# agents/, and a trimmed bin/ (ctlhq-catalog, ctlhq-skills,
# ctlhq-principles, two skill tools, planted tools). The real repository is only read, by one `build --out` run into the
# temp folder (section 2).
# Prints "N checks passed" and exits 1 when any check fails.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
pass=0
fail=0
ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL: $1"; }
expect_rc() { if [ "$1" -eq "$2" ]; then ok; else bad "$3 (expected exit $1, got $2)"; fi; }
expect_eq() { if [ "$1" = "$2" ]; then ok; else bad "$3 (expected '$1', got '$2')"; fi; }
expect_grep() { if printf '%s\n' "$2" | grep -Eq -- "$1"; then ok; else bad "$3 (no line matches: $1)"; fi; }
expect_fgrep() { if printf '%s\n' "$2" | grep -Fq -- "$1"; then ok; else bad "$3 (no line contains: $1)"; fi; }
expect_nogrep() { if printf '%s\n' "$2" | grep -Eq -- "$1"; then bad "$3 (a line matches: $1)"; else ok; fi; }
count() { printf '%s\n' "$2" | grep -Ec -- "$1"; }
sums() { (cd "$1" && cksum .local/catalog/CATALOG.md .local/catalog/skills.html .local/catalog/catalog.html 2>&1); }

tmp="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/ctlhq-catalog-test.XXXXXX")" && pwd -P)"
tmp="$(cd "$tmp" && pwd)" || exit 1  # TMPDIR may end in a slash
[ -n "$tmp" ] && [ -d "$tmp" ] || { echo "FAIL: no temp folder"; exit 1; }
trap 'rm -rf "$tmp"' EXIT
r="$tmp/repo"
fc="$r/bin/ctlhq-catalog"
c="$r/.local/catalog"
# run <args...>: runs the copy's ctlhq-catalog from the copy; sets out, err, rc.
run() { out="$(cd "$r" && "$fc" "$@" 2>"$tmp/err")"; rc=$?; err="$(cat "$tmp/err")"; }
# copy_repo: a fresh copy of the inputs at $r.
copy_repo() {
	rm -rf "$r"; mkdir -p "$r/bin"
	cp -R "$root/skills" "$root/agents" "$r/"
	find "$r/skills" -name __pycache__ -prune -exec rm -rf {} +
	cp "$root/bin/ctlhq-catalog" "$root/bin/ctlhq-skills" "$root/bin/ctlhq-principles" "$r/bin/"
	ln -s ../skills/benchmark-checklist/bin/ctlhq-benchmark-checklist "$r/bin/ctlhq-benchmark-checklist"
	ln -s ../skills/show-me-your-work/bin/ctlhq-decision-log "$r/bin/ctlhq-decision-log"
	printf '#!/bin/sh\necho "zz-fake: a planted tool for the catalog test"\n' > "$r/bin/zz-fake"; chmod +x "$r/bin/zz-fake"
	printf 'not a program\n' > "$r/bin/zz-noexec"; chmod -x "$r/bin/zz-noexec"
	printf '#!/bin/sh\necho hidden\n' > "$r/bin/.hidden"; chmod +x "$r/bin/.hidden"
}

# 1. --help, no command, unknown command (on the real tool; read-only).
real="$root/bin/ctlhq-catalog"
out="$("$real" --help 2>&1)"; expect_rc 0 $? "--help exits 0"
expect_grep '^ctlhq-catalog: ' "$(printf '%s\n' "$out" | head -1)" "--help first line is 'ctlhq-catalog: ...'"
for cmd in build open; do expect_grep "^  ctlhq-catalog $cmd " "$out" "--help names $cmd"; done
"$real" -h >/dev/null 2>&1; expect_rc 0 $? "-h exits 0"
out="$("$real" 2>&1)"; expect_rc 0 $? "no command prints the help and exits 0 (current behavior; see notes)"
expect_grep '^ctlhq-catalog: ' "$(printf '%s\n' "$out" | head -1)" "no command prints the help"
err="$("$real" bogus 2>&1 >/dev/null)"; expect_rc 2 $? "unknown command exits 2"
expect_eq "unknown command bogus" "$err" "unknown command named on stderr"

# 2. build --out on the real repository: three files in the named folder, links that resolve.
real_out="$tmp/real-out"
out="$("$real" build --out "$real_out" 2>&1)"; expect_rc 0 $? "build --out on the real repository exits 0"
expect_eq 3 "$(count '^wrote ' "$out")" "build writes three files"
for f in CATALOG.md skills.html catalog.html; do [ -s "$real_out/$f" ] && ok || bad "build --out writes $f"; done
href="$(grep -o 'href="[^"]*skills/ctlhq-mode/SKILL.md"' "$real_out/skills.html" | head -1 | sed 's/^href="//; s/"$//')"
[ -n "$href" ] && [ -f "$real_out/$href" ] && ok || bad "a skill link in skills.html resolves from the output folder ($href)"

# 3. build on the copy: counts, sections, numbered rows, planted tools.
copy_repo
workflow_dirs() { # skill folders with a SKILL.md, principles excluded (bash 3.2 cannot parse case inside $( ))
	local d
	for d in "$r"/skills/*/; do
		d="$(basename "$d")"
		case "$d" in principle-*) continue ;; esac
		[ -f "$r/skills/$d/SKILL.md" ] && echo "$d"
	done
}
workflow="$(workflow_dirs | grep -c '')"
principles="$(cd "$r/skills" && ls -d principle-*/ | grep -c '')"
agents="$(ls "$r/agents"/*.md | grep -c '')"
playbooks="$(ls "$r/skills/ctlhq-mode/playbooks"/*.md | grep -c '')"
run build; expect_rc 0 "$rc" "build exits 0"
expect_eq "wrote .local/catalog/CATALOG.md: $workflow workflow, $principles principles, $agents agents" "$(printf '%s\n' "$out" | head -1)" "build reports the counts"
expect_eq "wrote .local/catalog/skills.html|wrote .local/catalog/catalog.html" "$(printf '%s\n' "$out" | tail -2 | tr '\n' '|' | sed 's/|$//')" "build reports both HTML files"
cat_md="$(cat "$c/CATALOG.md")"
expect_eq "# ctlhq catalog" "$(printf '%s\n' "$cat_md" | head -1)" "CATALOG.md title"
expect_fgrep "$((workflow + principles)) skills ($workflow workflow, $principles principles), $agents agents, $playbooks playbooks, 7 tools." "$cat_md" "summary line counts skills, agents, playbooks, tools"
expect_eq "## Workflow skills|## Coding principles|## Agents|## Playbooks|## Tools" "$(printf '%s\n' "$cat_md" | grep '^## ' | tr '\n' '|' | sed 's/|$//')" "five sections in order"
expect_eq "$workflow" "$(count '^\| [0-9]+ \| \[`/' "$cat_md")" "one workflow row per workflow skill"
expect_eq "$principles" "$(count '^\| [0-9]+ \| \[`principle-' "$cat_md")" "one principle row per principle"
expect_eq "$agents" "$(count '^\| [0-9]+ \| \[`[a-z-]+`\]\(\.\./\.\./agents/' "$cat_md")" "one agent row per agent"
expect_eq "1 2 3" "$(printf '%s\n' "$cat_md" | grep '^| [0-9]* | \[`/' | head -3 | awk '{ printf "%s ", $2 }' | sed 's/ $//')" "workflow rows are numbered from 1"
tools_table="$(printf '%s\n' "$cat_md" | sed -n '/^## Tools$/,$p' | grep '^| [0-9]')"
expect_eq 7 "$(printf '%s\n' "$tools_table" | grep -c '')" "tools table has one row per bin/ file, dot files skipped"
expect_fgrep '| `zz-fake` | a planted tool for the catalog test |' "$tools_table" "tool row strips the '<name>: ' prefix"
expect_fgrep '| `zz-noexec` | (no --help) |' "$tools_table" "a tool that cannot run shows (no --help)"
expect_nogrep 'hidden' "$tools_table" "a dot file in bin/ is not a tool"
expect_grep '^\| [0-9]+ \| \[`/show-me-your-work`\].* \| `ctlhq-decision-log` \|$' "$cat_md" "a workflow row ends with its tool cell"
expect_grep '^\| [0-9]+ \| \[`/best-of-n`\].* \|  \|$' "$cat_md" "a skill without bin/ has an empty tool cell"
expect_eq "| # | skill | what it does | tool |" "$(printf '%s\n' "$cat_md" | grep '^| # | skill ')" "workflow table has four columns"
expect_eq "| # | principle | group | what it does |" "$(printf '%s\n' "$cat_md" | grep '^| # | principle ')" "principles table has four columns"
expect_eq "| # | agent | what it does |" "$(printf '%s\n' "$cat_md" | grep '^| # | agent ')" "agents table has three columns"
expect_nogrep '\| changes from |renamed from `|wording lines|CHANGES\.' "$cat_md" "CATALOG.md has no change columns or CHANGES pointer"
expect_grep '^\| [0-9]+ \| \[`principle-laziness-protocol`\]\(\.\./\.\./skills/principle-laziness-protocol/SKILL\.md\) \| core \| ' "$cat_md" "a principle row carries its group from the ctlhq-mode index"
expect_eq "principle-laziness-protocol principle-foundational-thinking" "$(printf '%s\n' "$cat_md" | grep -o '^| [0-9]* | \[`principle-[a-z-]*`' | head -2 | sed 's/.*`\(principle-[a-z-]*\)`/\1/' | tr '\n' ' ' | sed 's/ $//')" "principle rows follow the ctlhq-mode index order"

# 4. A planted skill: escaping, tool cell.
mkdir -p "$r/skills/zz-probe/bin"
printf -- '---\nname: zz-probe\ndescription: "Probe a | b <x> and `c<d>` end."\n---\n# zz\n' > "$r/skills/zz-probe/SKILL.md"
printf '#!/bin/sh\necho "zz-tool: t"\n' > "$r/skills/zz-probe/bin/zz-tool"; chmod +x "$r/skills/zz-probe/bin/zz-tool"
run build; expect_rc 0 "$rc" "build with a planted skill exits 0"
row="$(grep '\[`/zz-probe`\]' "$c/CATALOG.md")"
expect_eq "| $((workflow + 1)) | [\`/zz-probe\`](../../skills/zz-probe/SKILL.md) | Probe a \\| b \\<x\\> and \`c<d>\` end. | \`zz-tool\` |" "$row" "planted row: escapes outside code, keeps code, lists the tool"
sk="$(cat "$c/skills.html")"; ch="$(cat "$c/catalog.html")"
expect_eq "<!doctype html>" "$(printf '%s\n' "$sk" | head -1)" "skills.html starts with the doctype"
expect_fgrep '<title>ctlhq skills</title>' "$sk" "skills.html title"
expect_fgrep '<input id="q" type="search"' "$sk" "skills.html has the filter box"
expect_fgrep '<td>Probe a | b &lt;x&gt; and <code>c&lt;d&gt;</code> end.</td>' "$sk" "skills.html escapes the description cell and renders code"
expect_eq "$((workflow + 1))" "$(printf '%s' "$sk" | grep -o 'href="\.\./\.\./skills/[a-z0-9-]*/SKILL.md">/' | grep -c '')" "skills.html lists every workflow skill"
expect_eq "<!doctype html>" "$(printf '%s\n' "$ch" | head -1)" "catalog.html starts with the doctype"
expect_eq 1 "$(printf '%s' "$ch" | grep -o '<h1>' | grep -c '')" "catalog.html has one h1"
expect_eq 4 "$(printf '%s' "$ch" | grep -o '<table>' | grep -c '')" "catalog.html renders the four tables"
expect_fgrep '<td>Probe a | b &lt;x&gt; and <code>c&lt;d&gt;</code> end.</td>' "$ch" "catalog.html unescapes the Markdown escapes and renders code"
expect_eq 4 "$(printf '%s' "$ch" | python3 -c '
import sys
h = sys.stdin.read(); i = h.find("zz-probe"); row = h[h.rfind("<tr>", 0, i):h.find("</tr>", i)]
print(row.count("<td>"))')" "the planted catalog.html row has 4 cells, one per column"

# 5. build again: the same bytes. open: builds, then hands skills.html to `open`.
before="$(sums "$r")"
run build; expect_rc 0 "$rc" "a second build exits 0"
expect_eq "$before" "$(sums "$r")" "a second build writes the same bytes"
mkdir -p "$tmp/fakebin"
printf '#!/bin/sh\necho "$@" >> "%s/open.log"\n' "$tmp" > "$tmp/fakebin/open"; chmod +x "$tmp/fakebin/open"
out="$(cd "$r" && PATH="$tmp/fakebin:$PATH" "$fc" open 2>&1)"; rc=$?
expect_rc 0 "$rc" "open exits 0"
expect_eq "$c/skills.html" "$(cat "$tmp/open.log")" "open hands skills.html to the open command"
expect_eq "opened .local/catalog/skills.html" "$(printf '%s\n' "$out" | tail -1)" "open names the page it opened"
printf '#!/bin/sh\nexit 1\n' > "$tmp/fakebin/open"
err="$(cd "$r" && PATH="$tmp/fakebin:$PATH" "$fc" open 2>&1 >/dev/null)"; rc=$?
expect_rc 1 "$rc" "open exits 1 when the open command fails"
expect_fgrep "could not open $c/skills.html" "$err" "a failed open names the page"

# 6. --out and usage errors.
run build --out "$tmp/elsewhere"; expect_rc 0 "$rc" "build --out exits 0"
expect_grep '^\| 1 \| \[`/[a-z-]+`\]\(\.\./repo/skills/' "$(cat "$tmp/elsewhere/CATALOG.md")" "--out links back into the repository"
run build --out; expect_rc 2 "$rc" "--out without a folder exits 2"
run build extra; expect_rc 2 "$rc" "an extra argument exits 2"
expect_eq "usage: ctlhq-catalog build [--out DIR]" "$err" "the usage line is printed"

# 7. Missing inputs.
copy_repo
sed '/^## Coding principles$/d' "$root/skills/ctlhq-mode/SKILL.md" > "$r/skills/ctlhq-mode/SKILL.md"
run build; expect_rc 1 "$rc" "build without a principles index exits 1"
expect_fgrep "no '## Coding principles' section" "$err" "the ctlhq-principles error is passed on"
[ ! -e "$c" ] && ok || bad "a run without a principles index writes nothing"
# --help needs no inputs.
run --help; expect_rc 0 "$rc" "--help exits 0 without a principles index"
expect_grep '^ctlhq-catalog: ' "$out" "--help without a principles index prints the help"
copy_repo
printf '#!/bin/sh\necho "ctlhq-skills broke" >&2\nexit 1\n' > "$r/bin/ctlhq-skills"
run build; expect_rc 1 "$rc" "build exits 1 when ctlhq-skills fails"
expect_fgrep 'ctlhq-skills broke' "$err" "the ctlhq-skills error is passed on"

# 8. A | inside inline code in a description is escaped too, so the table row keeps its cells in
# catalog.html (and on GitHub), and the code shows a plain |.
copy_repo
mkdir -p "$r/skills/zz-pipe"
printf -- '---\nname: zz-pipe\ndescription: "Run `a|b` now."\n---\n# zz\n' > "$r/skills/zz-pipe/SKILL.md"
(cd "$r" && "$fc" build >/dev/null 2>&1)
cells="$(python3 -c '
import sys
h = open(sys.argv[1]).read(); i = h.find("zz-pipe"); row = h[h.rfind("<tr>", 0, i):h.find("</tr>", i)]
print(row.count("<td>"))' "$c/catalog.html")"
expect_eq 4 "$cells" "a | inside inline code keeps the catalog.html row at 4 cells"
expect_fgrep '<code>a|b</code>' "$(cat "$c/catalog.html")" "catalog.html shows the inline code with a plain |"
expect_fgrep 'Run `a\|b` now.' "$(cat "$c/CATALOG.md")" "CATALOG.md escapes the | inside inline code"

# 9. Positive control: a copy whose md_cell does not escape | must fail section 4's row check.
copy_repo
mkdir -p "$r/skills/zz-probe"
printf -- '---\nname: zz-probe\ndescription: "Probe a | b."\n---\n# zz\n' > "$r/skills/zz-probe/SKILL.md"
sed 's/parts\[i\] = parts\[i\]\.replace("|", "\\\\|")$/pass/' "$root/bin/ctlhq-catalog" > "$fc"
if cmp -s "$fc" "$root/bin/ctlhq-catalog"; then bad "positive control: the planted defect did not change the tool"; else ok; fi
(cd "$r" && "$fc" build >/dev/null 2>&1)
expect_grep '^\| [0-9]+ \| \[`/zz-probe`\]\(\.\./\.\./skills/zz-probe/SKILL\.md\) \| Probe a \| b\. \|' "$(cat "$c/CATALOG.md")" "positive control: the mutant writes an unescaped |, so section 4 would catch it"

echo "$pass checks passed"
if [ "$fail" -gt 0 ]; then
	echo "$fail checks failed"
	exit 1
fi
exit 0
