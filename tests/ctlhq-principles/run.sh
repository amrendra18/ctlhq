#!/usr/bin/env bash
# tests/ctlhq-principles/run.sh: checks for bin/ctlhq-principles. Read-only on the repository:
# planted defects run against a copy of the tool, the principle skills, and the ctlhq-mode
# SKILL.md in a temp folder. Prints "N checks passed" and exits 1 when any check fails.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
fp="$root/bin/ctlhq-principles"
mode="$root/skills/ctlhq-mode/SKILL.md"
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

tmp="$(mktemp -d "${TMPDIR:-/tmp}/ctlhq-principles-test.XXXXXX")"
tmp="$(cd "$tmp" && pwd)" || exit 1  # TMPDIR may end in a slash
[ -n "$tmp" ] && [ -d "$tmp" ] || { echo "FAIL: no temp folder"; exit 1; }
trap 'rm -rf "$tmp"' EXIT
# run <tool> <args...>: sets out, err, rc.
run() { local t="$1"; shift; out="$("$t" "$@" 2>"$tmp/err")"; rc=$?; err="$(cat "$tmp/err")"; }
# fresh: a copy of the tool and its inputs at $tmp/r; prints the copied tool's path.
fresh() {
	rm -rf "$tmp/r"; mkdir -p "$tmp/r/bin" "$tmp/r/skills/ctlhq-mode"
	cp "$root/bin/ctlhq-principles" "$tmp/r/bin/"
	cp -R "$root"/skills/principle-* "$tmp/r/skills/"
	cp "$mode" "$tmp/r/skills/ctlhq-mode/SKILL.md"
	printf '%s' "$tmp/r/bin/ctlhq-principles"
}

# 1. --help and usage errors.
run "$fp" --help; expect_rc 0 "$rc" "--help exits 0"
expect_grep '^ctlhq-principles: ' "$(printf '%s\n' "$out" | head -1)" "--help first line is 'ctlhq-principles: ...'"
for w in '--all' 'check <SKILL.md>' '<name>'; do expect_fgrep "$w" "$out" "--help names $w"; done
run "$fp" -h; expect_rc 0 "$rc" "-h exits 0"
run "$fp" a b; expect_rc 2 "$rc" "two names exit 2"; expect_fgrep 'give at most one name, or --all' "$err" "two names named"
run "$fp" --bogus; expect_rc 2 "$rc" "unknown option exits 2"; expect_fgrep 'unknown option --bogus' "$err" "unknown option named"
run "$fp" no-such-principle; expect_rc 2 "$rc" "unknown principle exits 2"
expect_fgrep "unknown principle 'no-such-principle'. Valid names:" "$err" "unknown principle lists the valid names"
expect_grep '^  core: laziness-protocol, ' "$err" "valid names grouped, core first"
run "$fp" check; expect_rc 2 "$rc" "check without a path exits 2"
run "$fp" check a b; expect_rc 2 "$rc" "check with two paths exits 2"

# 2. The index from the real repository: 24 principles under 5 groups in ctlhq-mode's order.
run "$fp"; expect_rc 0 "$rc" "index exits 0"
expect_eq 24 "$(count '^  [a-z0-9-]+: ' "$out")" "index lists 24 principles"
expect_eq "core architecture verification delegation meta" "$(printf '%s\n' "$out" | grep -v '^  ' | tr '\n' ' ' | sed 's/ $//')" "five group headings in order"
expect_eq "laziness-protocol encode-lessons-in-structure" "$(printf '%s\n' "$out" | grep '^  ' | sed -n '1p;$p' | sed 's/^  //; s/:.*//' | tr '\n' ' ' | sed 's/ $//')" "index starts and ends where the ctlhq-mode list does"
expect_eq 24 "$(sed -n '/^## Coding principles$/,/^## /p' "$mode" | grep -c '^- \*\*')" "the ctlhq-mode list has 24 bullets"
expect_grep '^  sequence-verifiable-units: ' "$out" "an explicit (**principle-name**) in ctlhq-mode gives the name"
expect_eq 0 "$(count 'not ported yet|no description in front matter' "$out")" "every principle is ported with a description"
expect_grep '^  laziness-protocol: Apply when refactoring' "$out" "a description is printed after the name"

# 3. One principle: body without front matter; the principle- prefix is optional.
run "$fp" test-behavior-not-implementation; expect_rc 0 "$rc" "one principle exits 0"
expect_eq "# Test Behavior, Not Implementation" "$(printf '%s\n' "$out" | head -1)" "body starts at the H1, front matter dropped"
expect_nogrep '^description: ' "$out" "no front matter key in the body"
expect_eq "$out" "$("$fp" principle-test-behavior-not-implementation 2>/dev/null)" "principle- prefix gives the same body"
body_lines="$(printf '%s\n' "$out" | grep -c '')"
file_lines="$(awk 'NR == 1 && /^---$/ { f = 1; next } f && /^---$/ { f = 0; next } !f' "$root/skills/principle-test-behavior-not-implementation/SKILL.md" | sed '/./,$!d' | grep -c '')"
expect_eq "$file_lines" "$body_lines" "body has every line after the front matter"

# 4. --all: 24 headers in index order, blank line between bodies.
run "$fp" --all; expect_rc 0 "$rc" "--all exits 0"
expect_eq 24 "$(count '^==== principle-[a-z0-9-]+  \(skills/principle-[a-z0-9-]+/SKILL\.md\)$' "$out")" "--all prints 24 headers"
expect_eq "==== principle-laziness-protocol  (skills/principle-laziness-protocol/SKILL.md)" "$(printf '%s\n' "$out" | head -1)" "--all starts with the first index entry"

# 5. check on the real ctlhq-mode skill.
run "$fp" check "$mode"; expect_rc 0 "$rc" "check on the ctlhq-mode skill exits 0"
expect_eq "ok: 24 principles in 5 groups; folders and $mode agree" "$out" "check ok line"
run "$fp" check "$tmp/nosuch.md"; expect_rc 1 "$rc" "check on a missing file exits 1"; expect_fgrep 'cannot read' "$err" "missing file named"
printf '# No principles\n\nText.\n' > "$tmp/plain.md"
run "$fp" check "$tmp/plain.md"; expect_rc 1 "$rc" "check on a file without a Coding principles section exits 1"
expect_fgrep "no '## Coding principles' section with bullet entries found" "$err" "missing section named"

# 6. Planted index edits in a copy of the ctlhq-mode skill: the index follows the list.
t="$(fresh)"; m="$tmp/r/skills/ctlhq-mode/SKILL.md"
awk '/^- \*\*Laziness Protocol\.\*\*/ { held = $0; next } held && /^- \*\*Foundational Thinking\.\*\*/ { print; print held; held = ""; next } { print }' "$mode" > "$m"
run "$t"; expect_rc 0 "$rc" "a reordered list exits 0"
expect_eq "foundational-thinking laziness-protocol" "$(printf '%s\n' "$out" | grep '^  ' | head -2 | sed 's/^  //; s/:.*//' | tr '\n' ' ' | sed 's/ $//')" "the index follows the new order"
awk '/^- \*\*Build the Lever\.\*\*/ { held = $0; next } /^\*\*Architecture\*\*/ { print; getline; print; print held; next } { print }' "$mode" > "$m"
expect_eq 2 "$(diff "$mode" "$m" | grep -c '^[<>] - \*\*Build the Lever\.')" "the regroup fixture moved Build the Lever"
run "$t"; expect_rc 0 "$rc" "a moved entry exits 0"
expect_eq "architecture" "$(printf '%s\n' "$out" | awk '/^[a-z]/ { g = $1 } /^  build-the-lever:/ { print g }')" "the index shows the entry under its new group"
sed '/^- \*\*Attack the Premise\.\*\*/d' "$mode" > "$m"
run "$t" check "$m"; expect_rc 1 "$rc" "a missing list entry exits 1"
expect_fgrep 'folder without an index entry: skills/principle-attack-the-premise' "$out" "the folder without an entry is named"
expect_eq "1 difference(s): 23 index entries vs 24 folders" "$(printf '%s\n' "$out" | tail -1)" "difference summary line"
sed 's/^- \*\*Attack the Premise\.\*\*/- **Attack the Premises.**/' "$mode" > "$m"
run "$t" check "$m"; expect_rc 1 "$rc" "a renamed entry exits 1"
expect_fgrep 'index entry without a folder: attack-the-premises (expected skills/principle-attack-the-premises/SKILL.md)' "$out" "the unknown entry is named"
sed 's/^- \*\*Attack the Premises\.\*\*/- **Attack the Premises.** (**principle-attack-the-premise**)/' "$m" > "$m.2"; mv "$m.2" "$m"
run "$t" check "$m"; expect_rc 0 "$rc" "an explicit (**principle-name**) overrides the title"

# 7. Planted tree defects: a missing folder, an extra folder, a missing description.
t="$(fresh)"
rm -rf "$tmp/r/skills/principle-attack-the-premise"
run "$t"; expect_rc 0 "$rc" "index with an unported principle exits 0"
expect_fgrep '  attack-the-premise: (not ported yet)' "$out" "unported principle marked"
run "$t" attack-the-premise; expect_rc 1 "$rc" "body of an unported principle exits 1"
expect_fgrep 'attack-the-premise: (not ported yet) expected at skills/principle-attack-the-premise/SKILL.md' "$err" "unported body names the path"
run "$t" --all; expect_rc 1 "$rc" "--all with an unported principle exits 1"
expect_eq 23 "$(count '^==== ' "$out")" "--all still prints the other 23"
run "$t" check "$tmp/r/skills/ctlhq-mode/SKILL.md"; expect_rc 1 "$rc" "check with a missing folder exits 1"
expect_fgrep 'index entry without a folder: attack-the-premise (expected skills/principle-attack-the-premise/SKILL.md)' "$out" "missing folder named"
t="$(fresh)"
mkdir -p "$tmp/r/skills/principle-extra"; printf -- '---\nname: principle-extra\n---\n# Extra\n' > "$tmp/r/skills/principle-extra/SKILL.md"
mkdir -p "$tmp/r/skills/principle-empty-folder"
run "$t" check "$tmp/r/skills/ctlhq-mode/SKILL.md"; expect_rc 1 "$rc" "check with an extra folder exits 1"
expect_fgrep 'folder without an index entry: skills/principle-extra' "$out" "extra folder named"
expect_nogrep 'principle-empty-folder' "$out" "a folder without SKILL.md is ignored"
t="$(fresh)"; s="$tmp/r/skills/principle-laziness-protocol/SKILL.md"
printf -- '---\nname: principle-laziness-protocol\n---\n# Body\n' > "$s"
run "$t"; expect_fgrep '  laziness-protocol: (no description in front matter)' "$out" "missing description marked"
printf -- '---\nname: x\ndescription: >\n  folded first\n  and second\n---\n# Body\n' > "$s"
run "$t"; expect_fgrep '  laziness-protocol: folded first and second' "$out" "a folded description is joined"
printf -- '---\ndescription: "quoted \\"inner\\" text"\n---\n# Body\n' > "$s"
run "$t"; expect_fgrep '  laziness-protocol: quoted "inner" text' "$out" "a quoted description is unquoted"
printf '# No front matter\nLine.\n' > "$s"
run "$t" laziness-protocol; expect_eq "# No front matter|Line." "$(printf '%s\n' "$out" | tr '\n' '|' | sed 's/|$//')" "a body without front matter prints whole"

# 8. A malformed list: every command exits 1, --help still exits 0.
t="$(fresh)"; m="$tmp/r/skills/ctlhq-mode/SKILL.md"
sed '/^## Coding principles$/d' "$mode" > "$m"
run "$t"; expect_rc 1 "$rc" "a missing section exits 1"; expect_fgrep "no '## Coding principles' section" "$err" "missing section named"
run "$t" laziness-protocol; expect_rc 1 "$rc" "one principle exits 1 without the section"
run "$t" --help; expect_rc 0 "$rc" "--help works without the section"
sed 's/^- \*\*Fix Root Causes\.\*\*/- **Laziness Protocol.**/' "$mode" > "$m"
run "$t"; expect_rc 1 "$rc" "a duplicate name exits 1"; expect_fgrep 'laziness-protocol appears twice' "$err" "duplicate named"
run "$t" check "$m"; expect_rc 1 "$rc" "check on a duplicate name exits 1"
awk '{ print } /^- \*\*Encode Lessons in Structure\.\*\*/ { print "**Core**"; print ""; print "- **Extra Core.** x" }' "$mode" > "$m"
run "$t"; expect_rc 1 "$rc" "a split group exits 1"; expect_fgrep 'group core is split' "$err" "split group named"
awk '/^\*\*Core\*\*$/ { next } { print }' "$mode" > "$m"
run "$t"; expect_rc 1 "$rc" "an entry above the first group heading exits 1"; expect_fgrep 'laziness-protocol has no bold group heading above it' "$err" "the entry without a group is named"

# 9. Positive control: a copy that skips the split-group test must accept section 8's split group.
t="$(fresh)"; m="$tmp/r/skills/ctlhq-mode/SKILL.md"
awk '{ print } /^- \*\*Encode Lessons in Structure\.\*\*/ { print "**Core**"; print ""; print "- **Extra Core.** x" }' "$mode" > "$m"
sed 's/^        elif any(g == group for g, _ in groups):$/        elif False:/' "$root/bin/ctlhq-principles" > "$t"
if cmp -s "$t" "$root/bin/ctlhq-principles"; then bad "positive control: the planted defect did not change the tool"; else ok; fi
run "$t"; expect_rc 0 "$rc" "positive control: the mutant accepts the split group, so section 8 would catch it"

echo "$pass checks passed"
if [ "$fail" -gt 0 ]; then
	echo "$fail checks failed"
	exit 1
fi
