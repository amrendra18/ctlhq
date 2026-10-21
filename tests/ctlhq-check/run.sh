#!/usr/bin/env bash
# tests/ctlhq-check/run.sh: checks bin/ctlhq-check against a synthetic --target tree. A clean
# fixture must exit 0; then one planted defect per check (1 to 5) must exit 1 and print its line
# (the positive controls). Also --no-tools, --skill, usage errors, removed options, and this
# repository with --no-tools. Prints "N checks passed" and exits 1 when any check fails.
# Writes only under a temp folder.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
fc="$root/bin/ctlhq-check"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/ctlhq-check-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
pass=0
fail=0
ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL: $1"; }
expect_rc() { if [ "$1" -eq "$2" ]; then ok; else bad "$3 (expected exit $1, got $2)"; fi; }
expect_grep() { if printf '%s\n' "$2" | grep -Eq -- "$1"; then ok; else bad "$3 (no line matches: $1)"; fi; }
expect_no() { if printf '%s\n' "$2" | grep -Eq -- "$1"; then bad "$3 (a line matches: $1)"; else ok; fi; }
# The brand word and the old host name are built from pieces so the brand-word scan of this
# repository (check 2) does not flag this file.
OLD_BRAND="p""stack"
OLD_HOST="Cur""sor"
ASK="Ask""Question"

tgt="$tmp/tgt"
skill_md() { # name
	printf -- '---\nname: %s\ndescription: a fixture skill.\n---\n# %s\n\nSome words about the skill here.\n\n## Steps\n\n1. Read the input file first.\n2. Write the output file next.\n\n- one bullet line\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\n```\ncode line\n```\n' "$1" "$1"
}
stub() { # name: a tool that answers --help; `check` exits 1 when the target holds FAIL-<name>
	cat >"$tgt/bin/$1" <<EOF
#!/usr/bin/env bash
d="\$(cd "\$(dirname "\$0")/.." && pwd)"
if [ "\${1:-}" = "--help" ]; then echo "$1: fixture stub"; exit 0; fi
if [ -e "\$d/FAIL-$1" ]; then echo "fixture difference"; echo "1 difference"; exit 1; fi
exit 0
EOF
	chmod +x "$tgt/bin/$1"
}
# fresh: a clean target. LICENSE and the Credits section of README.md may name the brand.
fresh() {
	rm -rf "$tgt"
	mkdir -p "$tgt/skills/ctlhq-mode" "$tgt/skills/alpha" "$tgt/bin"
	skill_md ctlhq-mode >"$tgt/skills/ctlhq-mode/SKILL.md"
	skill_md alpha >"$tgt/skills/alpha/SKILL.md"
	printf '# ctlhq\n\nA fixture.\n\n## Install\n\nSteps.\n\n## What it changes on your machine\n\nLinks.\n\n## Uninstall\n\nSteps.\n\n## Credits\n\nFrom %s, a %s plugin.\n\n## License\n\nMIT.\n' "$OLD_BRAND" "$OLD_HOST" >"$tgt/README.md"
	printf 'Copyright (c) 2026 the %s author\n' "$OLD_BRAND" >"$tgt/LICENSE"
	stub ctlhq-principles
}
run() { out="$("$fc" --target "$tgt" "$@" 2>&1)"; rc=$?; }
line_of() { grep -n -F -- "$1" "$tgt/$2" | head -1 | cut -d: -f1; }

# 0. Usage.
out="$("$fc" --help 2>&1)"; expect_rc 0 $? "--help exits 0"
expect_grep '^ctlhq-check: ' "$(printf '%s\n' "$out" | head -1)" "--help first line is 'ctlhq-check: ...'"
expect_no 'eval' "$out" "--help names no eval"
expect_no "plugi""ns-main|--source|--only" "$out" "--help names no port source and no source options"
"$fc" --bogus >/dev/null 2>&1; expect_rc 2 $? "an unknown option exits 2"
"$fc" --target >/dev/null 2>&1; expect_rc 2 $? "--target without a value exits 2"
for opt in --source --only; do "$fc" "$opt" x >/dev/null 2>&1; expect_rc 2 $? "the removed option $opt exits 2"; done

# 1. Clean fixture.
fresh; run
expect_rc 0 "$rc" "clean fixture exits 0"
expect_grep '^broken links 0 \| brand leftovers 0 \| tools 1/1 help ok \| help lines 1/1 \| bin names off prefix 0 \| tool sections missing 0 \| readme sections missing 0 \| readme sections empty 0 \| principles 0$' "$out" "clean summary line, with no source or eval count"
expect_no '^brand leftover' "$out" "check 2: LICENSE and the README Credits section may hold the brand"
expect_no 'source' "$out" "no line mentions a source"

# 2. One planted defect per check.
fresh; printf '\nSee [the notes](nowhere.md).\n' >>"$tgt/skills/alpha/SKILL.md"; run
expect_rc 1 "$rc" "check 1 control (broken link): exits 1"
expect_grep "^broken link: skills/alpha/SKILL.md:$(line_of nowhere.md skills/alpha/SKILL.md)  nowhere.md$" "$out" "check 1: a broken link is reported with file:line"

fresh; printf '\nPorted from %s.\n' "$OLD_BRAND" >>"$tgt/skills/alpha/SKILL.md"; run
expect_rc 1 "$rc" "check 2 control (brand leftover): exits 1"
expect_grep "^brand leftover: skills/alpha/SKILL.md:$(line_of 'Ported from' skills/alpha/SKILL.md)  " "$out" "check 2: a brand leftover is reported with file:line"

fresh; mkdir -p "$tgt/docs/debriefs"; printf '# Debrief\n\nThe agent read the %s source file.\n' "$OLD_BRAND" >"$tgt/docs/debriefs/session.md"; run
expect_rc 1 "$rc" "check 2 control (brand word in docs/debriefs): exits 1"
expect_grep '^brand leftover: docs/debriefs/session.md:3  ' "$out" "check 2: docs/debriefs has no exemption"

fresh; printf '# Notes\n\nChanges from %s.\n' "$OLD_BRAND" >"$tgt/NOTES.md"; run
expect_rc 1 "$rc" "check 2 control (brand word in another Markdown file): exits 1"
expect_grep '^brand leftover: NOTES.md:3  ' "$out" "check 2: a top-level Markdown file has no exemption"

fresh; printf '\nAsk the operator (%s in %s).\n' "$ASK" "$OLD_HOST" >>"$tgt/skills/alpha/SKILL.md"; run
expect_rc 1 "$rc" "check 2 control (the old host name in a skill): exits 1"
expect_grep "^brand leftover: skills/alpha/SKILL.md:$(line_of "$ASK" skills/alpha/SKILL.md)  " "$out" "check 2: the old host name is reported with file:line"
fresh; printf '\nThe %s folder.\n' "$(printf '%s' "$OLD_HOST" | tr '[:lower:]' '[:upper:]')" >>"$tgt/skills/alpha/SKILL.md"; run
expect_rc 1 "$rc" "check 2 control (the old host name in capitals): exits 1"
fresh; lower="$(printf '%s' "$OLD_HOST" | tr '[:upper:]' '[:lower:]')"
mkdir -p "$tgt/skills/ctlhq-mode/scripts/watch-pr"
printf 'let %s = 0;\n' "$lower" >"$tgt/skills/ctlhq-mode/scripts/check-plan.mjs"
printf 'const %s = page.endCursor;\n' "$lower" >"$tgt/skills/ctlhq-mode/scripts/watch-pr/github.ts"
printf '\nRead endCursor and call g_gh_%s.\n' "$lower" >>"$tgt/skills/alpha/SKILL.md"; run
expect_rc 0 "$rc" "check 2: the two paging-variable paths, endCursor, and g_gh_ names exit 0"
expect_no '^brand leftover' "$out" "check 2: no brand leftover for the allowed paths and words"

fresh; printf '\nA %s plugin.\n' "$OLD_HOST" >>"$tgt/README.md"; run
expect_rc 1 "$rc" "check 2 control (the old host name in README.md after the Credits section): exits 1"
expect_grep "^brand leftover: README.md:$(line_of 'A '"$OLD_HOST"' plugin' README.md)  " "$out" "check 2: README.md outside Credits is reported with file:line"
fresh; sed -i.bak "s/^A fixture\.\$/A fixture, from $OLD_BRAND./" "$tgt/README.md"; rm "$tgt/README.md.bak"; run
expect_rc 1 "$rc" "check 2 control (the brand word in README.md before the Credits section): exits 1"
expect_grep '^brand leftover: README.md:3  ' "$out" "check 2: README.md line 3 is reported"

# This project's old names and the old host's own tool and plugin names, built from pieces too.
OLD_NAMES="missi""on-control fna""tic FNA""TIC des""lop ${OLD_HOST}-team-kit control-""cli control-""ui general""Purpose"
OLD_NAMES="$OLD_NAMES $ASK plugi""ns-main"
for w in $OLD_NAMES; do
	fresh; printf '\nRun %s here.\n' "$w" >>"$tgt/skills/alpha/SKILL.md"; run
	expect_rc 1 "$rc" "check 2 control (old name $w in a skill): exits 1"
	expect_grep "^brand leftover: skills/alpha/SKILL.md:$(line_of "Run $w here" skills/alpha/SKILL.md)  " "$out" "check 2: the old name $w is reported with file:line"
done
fresh; mkdir -p "$tgt/skills/ctlhq-mode/scripts"
printf 'see %s-team-kit\n' "$(printf '%s' "$OLD_HOST" | tr '[:upper:]' '[:lower:]')" >"$tgt/skills/ctlhq-mode/scripts/check-plan.mjs"; run
expect_grep '^brand leftover: skills/ctlhq-mode/scripts/check-plan.mjs:1  ' "$out" "check 2: the old host's plugin name is reported in a path that may hold the host name"
fresh; sed -i.bak "s/^From .*/& $OLD_NAMES./" "$tgt/README.md"; rm "$tgt/README.md.bak"
printf 'Copyright (c) 2026 %s\n' "$OLD_NAMES" >>"$tgt/LICENSE"; run
expect_rc 0 "$rc" "check 2: LICENSE and the README Credits section may hold the old names"
fresh; printf '\nUse remote-control-uid and control-client.\n' >>"$tgt/skills/alpha/SKILL.md"; run
expect_rc 0 "$rc" "check 2: words that only start with an old tool name are not reported"
fresh; printf '\nAsk with AskUserQuestion.\n' >>"$tgt/skills/alpha/SKILL.md"; run
expect_rc 0 "$rc" "check 2: AskUserQuestion is not reported"

# Check 5: README.md has the Install, What it changes on your machine, and Uninstall sections.
for h in 'Install' 'What it changes on your machine' 'Uninstall'; do
	fresh; grep -v -x -F "## $h" "$tgt/README.md" >"$tgt/README.tmp"; mv "$tgt/README.tmp" "$tgt/README.md"; run
	expect_rc 1 "$rc" "check 5 control (no '## $h' heading): exits 1"
	expect_grep "^README section missing: ## $h\$" "$out" "check 5: the missing '## $h' heading is named"
	expect_grep '\| readme sections missing 1 \|' "$out" "check 5: the summary counts 1 missing section for '## $h'"
done
fresh; sed -i.bak 's/^## Uninstall$/### Uninstall/' "$tgt/README.md"; rm "$tgt/README.md.bak"; run
expect_rc 1 "$rc" "check 5 control (Uninstall as a level-3 heading): exits 1"
expect_grep '^README section missing: ## Uninstall$' "$out" "check 5: only a level-2 heading counts"
fresh; rm "$tgt/README.md"; run
expect_rc 1 "$rc" "check 5 control (no README.md): exits 1"
expect_grep '\| readme sections missing 3 \|' "$out" "check 5: no README.md counts 3 missing sections"
fresh; printf '# ctlhq\n\n```markdown\n## Install\n\n## What it changes on your machine\n\n## Uninstall\n```\n' >"$tgt/README.md"; run
expect_rc 1 "$rc" "check 5 control (the three headings only inside fenced code): exits 1"
expect_grep '\| readme sections missing 3 \|' "$out" "check 5: headings inside fenced code do not count"
fresh; printf '# ctlhq\n\n## Install\n\n## What it changes on your machine\n\nLinks.\n\n## Uninstall\n\n' >"$tgt/README.md"; run
expect_rc 1 "$rc" "check 5 control (Install and Uninstall with no body): exits 1"
expect_grep '^README section empty: ## Install$' "$out" "check 5: an empty Install section is named"
expect_grep '^README section empty: ## Uninstall$' "$out" "check 5: an empty last section is named"
expect_no 'section empty: ## What it changes' "$out" "check 5: a section with a body is not called empty"
expect_grep '\| readme sections missing 0 \| readme sections empty 2 \|' "$out" "check 5: the summary counts 2 empty sections"
fresh; printf '\n````markdown\n```\n## Uninstall\n```\n````\n' >>"$tgt/README.md"; run
expect_rc 0 "$rc" "check 5: a heading inside a longer fence, after a shorter inner fence, is skipped"
fresh; sed -i.bak 's/^## Credits$/```text\
## Credits\
```/' "$tgt/README.md"; rm "$tgt/README.md.bak"; run
expect_rc 1 "$rc" "check 2 control (a '## Credits' line inside fenced code, the brand word after it): exits 1"
expect_grep "^brand leftover: README.md:$(line_of "From $OLD_BRAND" README.md)  " "$out" "check 2: a Credits heading inside fenced code exempts nothing"

fresh; mkdir -p "$tgt/docs/notes"; printf '# Setup\n\nOpen %s.\n' "$OLD_HOST" >"$tgt/docs/notes/01-setup.md"; run
expect_rc 1 "$rc" "check 2 control (the old host name in a docs file): exits 1"

fresh; mkdir -p "$tgt/docs/research"; printf '# Notes\n\nSee [the source](gone.md).\n' >"$tgt/docs/research/notes.md"; run
expect_rc 1 "$rc" "check 1 control (broken link in docs/research): exits 1"
expect_grep '^broken link: docs/research/notes.md:3  gone.md$' "$out" "check 1: docs/research has no exemption"

fresh; printf '#!/usr/bin/env bash\necho "broken: no help" >&2\nexit 3\n' >"$tgt/bin/ctlhq-broken"; chmod +x "$tgt/bin/ctlhq-broken"; run
expect_rc 1 "$rc" "check 3 control (--help fails): exits 1"
expect_grep '^tool --help failed \(3\): bin/ctlhq-broken  broken: no help$' "$out" "check 3: a tool whose --help fails is reported"
expect_grep '\| tools 1/2 help ok \|' "$out" "check 3: the summary counts 1/2"
run --no-tools
expect_rc 0 "$rc" "--no-tools skips check 3"
expect_grep '\| tools 0/0 help ok \| help lines 0/0 \| ' "$out" "--no-tools: no tool runs"

fresh; printf '#!/usr/bin/env bash\necho "Usage: wrong"\n' >"$tgt/bin/ctlhq-badline"; chmod +x "$tgt/bin/ctlhq-badline"; run
expect_rc 1 "$rc" "check 4 control (help first line): exits 1"
expect_grep "^help first line is not 'ctlhq-badline: \.\.\.': bin/ctlhq-badline  'Usage: wrong'$" "$out" "check 4: a help first line out of shape is reported"

fresh; printf '#!/usr/bin/env bash\necho "first-push: old name"\n' >"$tgt/bin/first-push"; chmod +x "$tgt/bin/first-push"
ln -s first-push "$tgt/bin/old-link"; run
expect_rc 1 "$rc" "check 4 control (a bin/ name without the ctlhq- prefix): exits 1"
expect_grep '^bin name does not start with ctlhq-: bin/first-push$' "$out" "check 4: a bin/ file without the prefix is reported"
expect_grep '^bin name does not start with ctlhq-: bin/old-link$' "$out" "check 4: a bin/ link without the prefix is reported"
expect_grep '\| bin names off prefix 2 \|' "$out" "check 4: the summary counts 2 names without the prefix"
run --no-tools
expect_rc 1 "$rc" "check 4: --no-tools still checks bin/ names"

fresh; mkdir -p "$tgt/skills/alpha/bin"; run
expect_rc 1 "$rc" "check 4 control (Tool section): exits 1"
expect_grep "^no '## Tool' section although bin/ exists: skills/alpha/SKILL.md$" "$out" "check 4: a skill with bin/ and no Tool section is reported"
printf '\n## Tool\n\nNone yet.\n' >>"$tgt/skills/alpha/SKILL.md"; run
expect_no "no '## Tool' section" "$out" "check 4: a Tool section clears it"

fresh; touch "$tgt/FAIL-ctlhq-principles"; run
expect_rc 1 "$rc" "check 4 control (principles differ): exits 1"
expect_grep '^principles: fixture difference$' "$out" "check 4: a principles difference is reported"
expect_grep '\| principles 1$' "$out" "check 4: the summary counts 1 principles problem"
fresh; rm "$tgt/bin/ctlhq-principles"; run
expect_rc 1 "$rc" "check 4 control (no principles tool): exits 1"
expect_grep '^principles: bin/ctlhq-principles not found$' "$out" "check 4: a missing ctlhq-principles is reported"

# 3. --skill checks one skill.
fresh
out="$("$fc" --skill alpha --target "$tgt" 2>&1)"; rc=$?
expect_rc 0 "$rc" "--skill on a clean skill exits 0"
expect_grep '^ok: skill alpha, no bin/$' "$out" "--skill prints ok"
sed -i.bak 's/^name: alpha$/name: other/' "$tgt/skills/alpha/SKILL.md"
out="$("$fc" --skill alpha --target "$tgt" 2>&1)"; rc=$?
expect_rc 1 "$rc" "--skill control (name differs): exits 1"
expect_grep "^frontmatter name 'other' differs from the folder 'alpha': skills/alpha/SKILL.md$" "$out" "--skill reports the frontmatter name"

# 4. This repository, without running tools.
out="$("$fc" --target "$root" --no-tools 2>&1)"; rc=$?
expect_rc 0 "$rc" "this repository with --no-tools exits 0"
if [ "$rc" -ne 0 ]; then printf '%s\n' "$out" | tail -5 | sed 's/^/  /'; fi
expect_no 'eval case' "$out" "this repository: no eval case line or count"

if [ "$fail" -gt 0 ]; then
	echo "$fail checks failed, $pass checks passed"
	exit 1
fi
# A Git work tree: ignored files (such as a PLAN.md linked in from a private folder) are not
# checked; the same file unignored is.
fresh
git -C "$tgt" init -q
printf '/PLAN.md\n' > "$tgt/.gitignore"
printf '# PLAN\n\nPorted from %s.\n' "$OLD_BRAND" > "$tgt/PLAN.md"
out="$("$fc" --target "$tgt" --no-tools 2>&1)"; rc=$?
expect_rc 0 "$rc" "git target: an ignored file with the brand word exits 0"
expect_no '^brand leftover: PLAN.md' "$out" "git target: the ignored PLAN.md is not checked"
: > "$tgt/.gitignore"
out="$("$fc" --target "$tgt" --no-tools 2>&1)"; rc=$?
expect_rc 1 "$rc" "git target: the same file unignored exits 1"
expect_grep '^brand leftover: PLAN.md:3  ' "$out" "git target: the unignored PLAN.md is checked"

echo "$pass checks passed"
