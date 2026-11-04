#!/usr/bin/env bash
# tests/skill-contract/run.sh: free contract checks over every skills/*/SKILL.md, every
# skills/*/playbooks/*.md, and every agents/*.md, through tests/skill-contract/check_contract.py.
# Part 1 plants one of each defect in a temp fixture and requires the checker to report each
# one as file:line (the positive controls), and to stay quiet on the look-alikes that are fine.
# Part 2 runs the checker on this repository and fails on any problem it reports.
# Prints "N checks passed" and exits 1 when any check fails. Writes only under a temp folder.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
chk="$here/check_contract.py"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/skill-contract-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
pass=0
fail=0
ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL: $1"; }
expect_rc() { if [ "$1" -eq "$2" ]; then ok; else bad "$3 (expected exit $1, got $2)"; fi; }
expect_eq() { if [ "$1" = "$2" ]; then ok; else bad "$3 (expected '$1', got '$2')"; fi; }
expect_grep() { if printf '%s\n' "$2" | grep -Eq -- "$1"; then ok; else bad "$3 (no line matches: $1)"; fi; }
expect_nogrep() { if printf '%s\n' "$2" | grep -Eq -- "$1"; then bad "$3 (a line matches: $1)"; else ok; fi; }

# 0. Usage.
out="$(python3 "$chk" --help 2>&1)"; expect_rc 0 $? "--help exits 0"
expect_grep '^check_contract.py: ' "$(printf '%s\n' "$out" | head -1)" "--help first line is 'check_contract.py: ...'"
python3 "$chk" --bogus >/dev/null 2>&1; expect_rc 2 $? "unknown argument exits 2"
python3 "$chk" --root "$tmp/nowhere" >/dev/null 2>&1; expect_rc 2 $? "missing --root folder exits 2"

# 1. Fixture: one tool that answers --help, one that does not, three skills, one playbook, one agent.
fx="$tmp/fx"
mkdir -p "$fx/bin" "$fx/skills/alpha/references" "$fx/skills/beta" "$fx/skills/ctlhq-mode/playbooks" "$fx/agents"
cat >"$fx/bin/good" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "--help" ]; then
	printf 'good: a fixture tool.\n\nCommands:\n  run      do the thing\n\nOptions:\n  --json   print JSON\n'
	exit 0
fi
exit 0
EOF
printf '#!/usr/bin/env bash\necho "nohelp: no" >&2\nexit 2\n' >"$fx/bin/nohelp"
chmod +x "$fx/bin/good" "$fx/bin/nohelp"
printf '# real\n\nDEFECT-12 run `cd x && sidecar run` here.\n' >"$fx/skills/alpha/references/real.md"
printf -- '---\nname: beta\nmetadata:\n  separate-tools: sidecar\n---\n# beta\n\n```\nsidecar run --fast\n```\n' >"$fx/skills/beta/SKILL.md"
printf '# ctlhq-mode\n\nUse `playbooks/real.md`.\n' >"$fx/skills/ctlhq-mode/SKILL.md"
printf '1. Step.\n' >"$fx/skills/ctlhq-mode/playbooks/real.md"
cat >"$fx/skills/alpha/SKILL.md" <<'EOF'
---
name: alpha
---
# alpha

## 1. Steps

Fine look-alikes: run `bin/good run --json`, read `references/real.md` and `references/<topic>.md`.
Also `skills/ctlhq-mode/playbooks/real.md`, `/loop`, `/alpha`, the `ctlhq-mode` skill, ctlhq-agent.
Also the project-local skill, the verification skill, `$HOME/projects/widget/bin/widget`, and /Users/x/tmp/file.
Also the name `sidecar` alone, and `sidecar.md is a file`.
Also the **alpha** skill's section 1, alpha's section 1, section 1 of `alpha`, the `alpha` skill, section 1, `alpha` section 1, and the plan's section 10.

```
bin/good run --json    # a fenced line that is fine
```

Planted defects:
DEFECT-1 run `bin/nosuch` here.
DEFECT-2 run `ctlhq-ghost` here.
DEFECT-3 run `bin/nohelp` here.
DEFECT-4 run `good walk` here.
DEFECT-5 run `good run --nope` here.
DEFECT-6 read `playbooks/missing.md` here.
DEFECT-7 read `references/missing.md` here.
DEFECT-8 use `/ghost-skill` here.
DEFECT-9 use the `phantom` skill here.
DEFECT-13 read the **alpha** skill's section 9 here.
DEFECT-14 read **alpha** section 8 here.
```
good stroll            # DEFECT-10 a fenced line with an unknown subcommand
```
DEFECT-11 run `sidecar run` here.
EOF
printf '# ctlhq-agent\n\nRead the `alpha` skill, then call ctlhq-mode.\n' >"$fx/agents/ctlhq-agent.md"

out="$(python3 "$chk" --root "$fx" 2>&1)"; rc=$?
expect_rc 1 "$rc" "fixture with planted defects exits 1"
ln() { grep -n -- "$1" "$fx/skills/alpha/SKILL.md" | head -1 | cut -d: -f1; }
f=skills/alpha/SKILL.md
expect_grep "^$f:$(ln DEFECT-1): command \`bin/nosuch\` not found" "$out" "control 1: missing bin/ tool reported with file:line"
expect_grep "^$f:$(ln DEFECT-2): command \`ctlhq-ghost\` not found" "$out" "control 2: missing ctlhq-* command reported"
expect_grep "^$f:$(ln DEFECT-3): command \`bin/nohelp --help\` exits 2" "$out" "control 3: tool whose --help fails reported"
expect_grep "^$f:$(ln DEFECT-4): \`good walk\`: subcommand \`walk\` is not in \`good --help\`" "$out" "control 4: unknown subcommand reported"
expect_grep "^$f:$(ln DEFECT-5): \`good --nope\`: flag not in \`good --help\`" "$out" "control 5: unknown flag reported"
expect_grep "^$f:$(ln DEFECT-6): playbook path \`playbooks/missing.md\` does not exist" "$out" "control 6: missing playbook reported"
expect_grep "^$f:$(ln DEFECT-7): references path \`references/missing.md\` does not exist" "$out" "control 7: missing references file reported"
expect_grep "^$f:$(ln DEFECT-8): skill \`ghost-skill\` \(named as /ghost-skill\) does not exist" "$out" "control 8: unknown /skill reported"
expect_grep "^$f:$(ln DEFECT-9): skill \`phantom\` \(named as the phantom skill\) does not exist" "$out" "control 9: unknown 'the X skill' reported"
expect_grep "^$f:$(ln DEFECT-10): \`good stroll\`: subcommand \`stroll\` is not in \`good --help\`" "$out" "control 10: unknown subcommand on a fenced line reported"
expect_grep "^$f:$(ln DEFECT-11): \`sidecar\` is a separate tool that skills/alpha/SKILL.md does not name" "$out" "control 11: a separate tool the skill's front matter does not name is reported"
expect_grep "^skills/alpha/references/real.md:3: \`sidecar\` is a separate tool" "$out" "control 12: a call in a references file after && is reported"
expect_grep "^$f:$(ln DEFECT-13): \`the \*\*alpha\*\* skill's section 9\`: skills/alpha/SKILL.md has no \`## 9\.\` heading" "$out" "control 13: a section number the named skill does not have reported"
expect_grep "^$f:$(ln DEFECT-14): \`\*\*alpha\*\* section 8\`: skills/alpha/SKILL.md has no \`## 8\.\` heading" "$out" "control 14: a section the bare marked form names is checked too"
expect_eq 14 "$(printf '%s\n' "$out" | grep -c '^skills/\|^agents/')" "exactly the 14 planted problems are reported (no false positives on the look-alikes)"
expect_grep '^14 problems, [0-9]+ checks passed$' "$(printf '%s\n' "$out" | tail -1)" "summary line counts 14 problems"

cp "$fx/skills/alpha/SKILL.md" "$tmp/alpha.md"
printf -- '---\nname: alpha\nmetadata:\n  separate-tools: sidecar\n---\n' >"$fx/skills/alpha/SKILL.md"
sed '1,3d' "$tmp/alpha.md" >>"$fx/skills/alpha/SKILL.md"
out="$(python3 "$chk" --root "$fx" 2>&1)"
expect_nogrep 'sidecar' "$out" "a named separate tool is accepted in SKILL.md and references/"
expect_grep '^12 problems, [0-9]+ checks passed$' "$(printf '%s\n' "$out" | tail -1)" "only the 12 other planted problems remain"
cp "$tmp/alpha.md" "$fx/skills/alpha/SKILL.md"
expect_nogrep 'widget|/Users/x|project-local|verification|`loop`|`alpha`|ctlhq-agent|ctlhq-mode|real\.md|<topic>' "$out" "look-alikes are not reported"

# 2. The same fixture with the defect lines removed is clean.
grep -v 'DEFECT-\|^good stroll' "$fx/skills/alpha/SKILL.md" >"$tmp/clean.md"
printf '# real\n' >"$fx/skills/alpha/references/real.md"
# Drop the now-empty trailing fence pair.
python3 - "$tmp/clean.md" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read().rstrip("\n").split("\n")
while len(s) >= 2 and s[-1] == "```" and s[-2] == "```":
    s = s[:-2]
open(p, "w").write("\n".join(s) + "\n")
PY
cp "$tmp/clean.md" "$fx/skills/alpha/SKILL.md"
out="$(python3 "$chk" --root "$fx" 2>&1)"; rc=$?
expect_rc 0 "$rc" "clean fixture exits 0"
expect_grep '^[0-9]+ checks passed$' "$out" "clean fixture prints only 'N checks passed'"

lf="$tmp/lists"
mkdir -p "$lf/skills/flow" "$lf/skills/block"
printf -- '---\nname: flow\nmetadata:\n  separate-tools: [sidecar, other]\n---\n# flow\n' >"$lf/skills/flow/SKILL.md"
printf -- '---\nname: block\nmetadata:\n  separate-tools:\n    - sidecar\n---\n# block\n' >"$lf/skills/block/SKILL.md"
out="$(python3 "$chk" --root "$lf" 2>&1)"; rc=$?
expect_rc 1 "$rc" "separate-tools written as a YAML list exits 1"
expect_grep '^skills/flow/SKILL.md:4: separate-tools must be names separated by spaces$' "$out" "control 15: a list in brackets is reported with file:line"
expect_grep '^skills/block/SKILL.md:4: separate-tools must be names separated by spaces$' "$out" "control 16: a list on the lines after separate-tools: is reported with file:line"

# 3. This repository: every SKILL.md, playbook, and agent file.
out="$(python3 "$chk" --root "$root" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then
	ok
	echo "repository: $out"
else
	printf '%s\n' "$out" | grep -v 'checks passed$' | while IFS= read -r line; do echo "FAIL: $line"; done
	n="$(printf '%s\n' "$out" | grep -vc 'checks passed$')"
	fail=$((fail + n))
	echo "repository: $(printf '%s\n' "$out" | tail -1)"
fi

expect_grep 'throwaway home folder, with no push, no write to the real home folder, and no call to a paid or external service' "$(grep '^> Break this change' "$root/skills/interrogate/SKILL.md")" "the /interrogate adversary brief limits what its runs may touch"

if [ "$fail" -gt 0 ]; then
	echo "$fail checks failed, $pass checks passed"
	exit 1
fi
echo "$pass checks passed"
