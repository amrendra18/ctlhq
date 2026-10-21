#!/usr/bin/env bash
# tests/ctlhq-install/run.sh: checks for bin/ctlhq-install.
# Prints "N checks passed" and exits 1 when any check fails. Every run uses --home with a
# scratch folder under a temporary directory (TMPDIR honoured); never touches the real home.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd -P)"
inst="$root/bin/ctlhq-install"
pass=0
fail=0
ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL: $1"; }
expect_rc() { # expected actual label
	if [ "$1" -eq "$2" ]; then ok; else bad "$3 (expected exit $1, got $2)"; fi
}
expect_eq() { # expected actual label
	if [ "$1" = "$2" ]; then ok; else bad "$3 (expected '$1', got '$2')"; fi
}
expect_grep() { # pattern text label
	if printf '%s\n' "$2" | grep -Eq -- "$1"; then ok; else bad "$3 (no line matches: $1)"; fi
}
expect_no_line() { # pattern text label
	if printf '%s\n' "$2" | grep -Eq -- "$1"; then bad "$3 (a line matches: $1)"; else ok; fi
}
tmp="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/ctlhq-install-test.XXXXXX")" && pwd -P)"
trap 'rm -rf "$tmp"' EXIT
H="$tmp/home"
mkdir -p "$H"

# Run against a fixture copy of the repository whose docs/install.tsv holds only one
# exception (recall goes to .agents), so the counts below do not change when the real
# per-host list changes. Fixture skills are kept public skills.
fixture="$tmp/fixture-repo"
mkdir -p "$fixture/docs"
cp -a "$root/skills" "$root/agents" "$root/bin" "$root/home" "$fixture/"
printf 'skill\thosts\nrecall\tclaude,agents\n' > "$fixture/docs/install.tsv"
root="$fixture"
inst="$root/bin/ctlhq-install"

nskills="$(ls "$root"/skills/*/SKILL.md | wc -l | tr -d ' ')"
nagents="$(ls "$root"/agents/*.md | wc -l | tr -d ' ')"
total=$((nskills * 2 + nagents)) # no ~/.codex/AGENTS.md without agents_md = true
links() { find "$H" -type l | wc -l | tr -d ' '; }

# 1. --help and usage errors.
out="$("$inst" --help 2>&1)"; expect_rc 0 $? "--help exits 0"
expect_grep '^ctlhq-install: ' "$(printf '%s\n' "$out" | head -1)" "--help first line is 'ctlhq-install: ...'"
"$inst" --bogus >/dev/null 2>&1; expect_rc 2 $? "unknown flag exits 2"
"$inst" --check --uninstall --home "$H" >/dev/null 2>&1; expect_rc 2 $? "--check with --uninstall exits 2"
"$inst" --home "$tmp/nope" >/dev/null 2>&1; expect_rc 2 $? "missing --home folder exits 2"
"$inst" --home >/dev/null 2>&1; expect_rc 2 $? "--home without a value exits 2"

# 2. --check on an empty home: everything missing, exit 1.
out="$("$inst" --check --home "$H" 2>&1)"; expect_rc 1 $? "--check on empty home exits 1"
expect_grep "^check: 0 ok, $total missing," "$out" "every expected link reported missing"

# 3. --dry-run changes nothing and prints every action.
out="$("$inst" --dry-run --home "$H" 2>&1)"; expect_rc 0 $? "--dry-run exits 0"
expect_eq 0 "$(links)" "--dry-run creates no links"
expect_grep '^would link +~/\.claude/skills/unslop -> ' "$out" "--dry-run prints the unslop link"
expect_grep '^  PATH line, for ~/.zshrc: +export PATH="'"$root"'/bin:\$PATH"$' "$out" "PATH line printed"
expect_grep 'ctlhq-reply-lint --hook' "$out" "Stop hook line printed"
stop="$(printf '%s\n' "$out" | grep -E '^    "Stop": ')"
expect_eq "command|$root/bin/ctlhq-reply-lint --hook|5" "$(printf '{%s}' "$stop" | python3 -c 'import json,sys; h=json.load(sys.stdin)["Stop"][0]["hooks"][0]; print("%s|%s|%s" % (h["type"], h["command"], h["timeout"]))' 2>&1)" \
	"Stop hook line is the settings.json shape: Stop[].hooks[] with type, command, timeout"

# 4. Install: default hosts claude and codex; recall goes to .agents, not .codex; agents linked.
out="$("$inst" --home "$H" 2>&1)"; expect_rc 0 $? "install exits 0"
expect_eq "$total" "$(links)" "install creates 2 links per skill plus agents"
expect_eq "$root/skills/unslop" "$(readlink "$H/.claude/skills/unslop")" "claude link for unslop"
expect_eq "$root/skills/unslop" "$(readlink "$H/.codex/skills/unslop")" "codex link for unslop"
expect_eq "$root/skills/recall" "$(readlink "$H/.agents/skills/recall")" "recall linked into .agents"
[ -e "$H/.codex/skills/recall" ] && bad "recall must not be in .codex" || ok
[ -e "$H/.agents/skills/unslop" ] && bad "unslop must not be in .agents" || ok
expect_eq "$root/agents/ctlhq-agent.md" "$(readlink "$H/.claude/agents/ctlhq-agent.md")" "agent file linked"
expect_grep '^install: 0 ok, ' "$out" "install summary line"

# 5. Idempotent: second run changes nothing; --check is clean.
out="$("$inst" --home "$H" 2>&1)"; expect_rc 0 $? "second install exits 0"
expect_grep "^install: $total ok, 0 linked, 0 repointed" "$out" "second install only finds ok links"
out="$("$inst" --check --home "$H" 2>&1)"; expect_rc 0 $? "--check after install exits 0"
expect_grep '; clean \(' "$out" "--check says clean"

# 6. Drift kinds: copy, broken, elsewhere, wrong, extra, missing.
rm "$H/.claude/skills/unslop"; mkdir "$H/.claude/skills/unslop"; echo mine > "$H/.claude/skills/unslop/note"
ln -sfn "$tmp/moved/skills/why" "$H/.codex/skills/why"
mkdir -p "$tmp/other/tdd"; rm "$H/.claude/skills/tdd"; ln -s "$tmp/other/tdd" "$H/.claude/skills/tdd"
rm "$H/.codex/skills/teach"; ln -s "$root/skills/how" "$H/.codex/skills/teach"
ln -s "$root/skills/recall" "$H/.codex/skills/recall"
rm "$H/.claude/agents/ctlhq-agent.md"
out="$("$inst" --check --home "$H" 2>&1)"; expect_rc 1 $? "--check with drift exits 1"
expect_grep '^copy +~/\.claude/skills/unslop is a real folder' "$out" "copy reported"
expect_grep '^broken +~/\.codex/skills/why -> ' "$out" "link into a missing folder reported"
expect_grep '^elsewhere +~/\.claude/skills/tdd -> ' "$out" "link outside the repository reported"
expect_grep '^wrong +~/\.codex/skills/teach -> ' "$out" "link to another repository item reported"
expect_grep '^extra +~/\.codex/skills/recall ' "$out" "recall in .codex reported extra"
expect_grep '^missing +~/\.claude/agents/ctlhq-agent\.md$' "$out" "missing agent link reported"
expect_grep '6 drift' "$out" "six drift items counted"

# 7. Install without --replace: copy kept, exit 1; the other drift is repaired.
out="$("$inst" --home "$H" 2>&1)"; expect_rc 1 $? "install with a copy in place exits 1"
expect_grep '^copy +~/\.claude/skills/unslop: copy in place, not replaced' "$out" "copy in place reported"
expect_eq "mine" "$(cat "$H/.claude/skills/unslop/note")" "the real folder is untouched"
expect_grep '^repoint +~/\.claude/skills/tdd \(was '"$tmp"'/other/tdd\)' "$out" "elsewhere link repointed and reported"
expect_eq "$root/skills/tdd" "$(readlink "$H/.claude/skills/tdd")" "tdd now points into the repository"
expect_eq "$root/skills/why" "$(readlink "$H/.codex/skills/why")" "broken link repaired"
expect_eq "$root/skills/teach" "$(readlink "$H/.codex/skills/teach")" "wrong link repaired"
[ -L "$H/.codex/skills/recall" ] && bad "extra recall link should be removed" || ok
[ -d "$tmp/other/tdd" ] && ok || bad "the old link target folder must stay"

# 8. --replace moves the copy to ~/.ctlhq-backups/<date>/ and links.
out="$("$inst" --replace --home "$H" 2>&1)"; expect_rc 0 $? "--replace exits 0"
bk="$H/.ctlhq-backups/$(date +%Y-%m-%d)/.claude/skills/unslop"
expect_eq "mine" "$(cat "$bk/note" 2>/dev/null)" "copy moved to the backup folder"
expect_eq "$root/skills/unslop" "$(readlink "$H/.claude/skills/unslop")" "unslop linked after --replace"
"$inst" --check --home "$H" >/dev/null 2>&1; expect_rc 0 $? "--check clean after --replace"
# a second backup on the same day does not overwrite the first
rm "$H/.claude/skills/unslop"; mkdir "$H/.claude/skills/unslop"; echo two > "$H/.claude/skills/unslop/note"
"$inst" --replace --home "$H" >/dev/null 2>&1
expect_eq "mine two" "$(cat "$bk/note") $(cat "$bk.1/note" 2>/dev/null)" "second backup gets a .1 suffix"

# 9. Names the repository does not ship, synced/ and .system/ stay untouched.
mkdir -p "$H/.claude/skills/synced/x" "$H/.codex/skills/.system/y"
ln -s "$tmp/other/tdd" "$H/.claude/skills/not-ours"
ln -s "$root/skills/unslop" "$H/.claude/skills/alias-into-repo"
"$inst" --home "$H" >/dev/null 2>&1
"$inst" --uninstall --home "$H" >/dev/null 2>&1
[ -d "$H/.claude/skills/synced/x" ] && [ -d "$H/.codex/skills/.system/y" ] && ok || bad "synced/ and .system/ untouched"
[ -L "$H/.claude/skills/not-ours" ] && [ -L "$H/.claude/skills/alias-into-repo" ] && ok || bad "unshipped names untouched"

# 10. --uninstall removes only links into this repository.
"$inst" --home "$H" >/dev/null 2>&1
rm "$H/.codex/skills/unslop"; ln -s "$tmp/other/tdd" "$H/.codex/skills/unslop"
out="$("$inst" --uninstall --dry-run --home "$H" 2>&1)"; expect_rc 0 $? "--uninstall --dry-run exits 0"
expect_grep '^would remove +~/\.claude/skills/unslop$' "$out" "dry-run uninstall lists a removal"
[ -L "$H/.claude/skills/unslop" ] && ok || bad "--uninstall --dry-run removes nothing"
out="$("$inst" --uninstall --home "$H" 2>&1)"; expect_rc 0 $? "--uninstall exits 0"
expect_grep '^keep +~/\.codex/skills/unslop -> ' "$out" "foreign link kept and reported"
expect_grep "^uninstall: $((total - 1)) removed, 1 kept" "$out" "uninstall counts"
expect_eq "$tmp/other/tdd" "$(readlink "$H/.codex/skills/unslop")" "foreign link still in place"
[ -d "$H/.ctlhq-backups" ] && ok || bad "backups untouched by uninstall"

# 11. A renamed repository: links point at the old path; reinstall from the new path repairs them.
cp -R "$root/bin" "$root/skills" "$root/agents" "$root/docs" "$root/home" "$tmp/" 2>/dev/null
mkdir -p "$tmp/repo-a"; mv "$tmp/bin" "$tmp/skills" "$tmp/agents" "$tmp/docs" "$tmp/home" "$tmp/repo-a/"
H2="$tmp/home2"; mkdir -p "$H2"
"$tmp/repo-a/bin/ctlhq-install" --home "$H2" >/dev/null 2>&1
mv "$tmp/repo-a" "$tmp/repo-b"
out="$("$tmp/repo-b/bin/ctlhq-install" --check --home "$H2" 2>&1)"; expect_rc 1 $? "--check after a rename exits 1"
expect_grep '^broken +~/\.claude/skills/unslop -> '"$tmp"'/repo-a/skills/unslop$' "$out" "rename shows broken links"
"$tmp/repo-b/bin/ctlhq-install" --home "$H2" >/dev/null 2>&1; expect_rc 0 $? "reinstall after a rename exits 0"
expect_eq "$tmp/repo-b/skills/unslop" "$(readlink "$H2/.claude/skills/unslop")" "reinstall repoints to the new path"
"$tmp/repo-b/bin/ctlhq-install" --check --home "$H2" >/dev/null 2>&1; expect_rc 0 $? "--check clean after reinstall"

# 12. A bad docs/install.tsv row is a usage error.
printf 'skill\thosts\nunslop\tcursor\n' > "$tmp/repo-b/docs/install.tsv"
"$tmp/repo-b/bin/ctlhq-install" --check --home "$H2" >/dev/null 2>&1; expect_rc 2 $? "unknown host in install.tsv exits 2"

# 12b. No docs/install.tsv at all: every skill goes to Claude Code and Codex, none to .agents.
rm "$tmp/repo-b/docs/install.tsv"
H2b="$tmp/home2b"; mkdir -p "$H2b"
"$tmp/repo-b/bin/ctlhq-install" --home "$H2b" >/dev/null 2>&1; expect_rc 0 $? "install without docs/install.tsv exits 0"
expect_eq "$nskills $nskills" "$(find "$H2b/.claude/skills" "$H2b/.codex/skills" -type l | awk -F/ '{ print $(NF-2) }' | sort | uniq -c | awk '{ printf "%s ", $1 }' | sed 's/ $//')" "without docs/install.tsv every skill goes to Claude Code and Codex"
[ ! -e "$H2b/.agents" ] && ok || bad "without docs/install.tsv nothing goes to .agents"

# snap DIR: every path under DIR with its kind, link target or checksum, for "nothing changed".
snap() {
	find "$1" | sort | while IFS= read -r p; do
		if [ -L "$p" ]; then echo "L $p $(readlink "$p")"
		elif [ -f "$p" ]; then echo "F $p $(cksum < "$p")"
		else echo "D $p"; fi
	done
}
settings() { mkdir -p "$1/.ctlhq"; cat > "$1/.ctlhq/layers.toml"; }

# 13. No layers.toml: ~/.codex/AGENTS.md is never written, linked or named; ~/.claude/CLAUDE.md untouched.
H3="$tmp/home3"; mkdir -p "$H3/.claude"
printf '@~/.codex/AGENTS.md\n' > "$H3/.claude/CLAUDE.md"
out="$("$inst" --dry-run --home "$H3" 2>&1)"
printf '%s\n' "$out" | grep -q 'AGENTS\.md' && bad "--dry-run with no layers.toml names no AGENTS.md (got: $(printf '%s\n' "$out" | grep 'AGENTS\.md' | head -1))" || ok
"$inst" --home "$H3" >/dev/null 2>&1; expect_rc 0 $? "install with no layers.toml exits 0"
[ -e "$H3/.codex/AGENTS.md" ] || [ -L "$H3/.codex/AGENTS.md" ] && bad "no layers.toml: ~/.codex/AGENTS.md must not exist" || ok
"$inst" --check --home "$H3" >/dev/null 2>&1; expect_rc 0 $? "--check clean with no AGENTS.md"
expect_eq "@~/.codex/AGENTS.md" "$(cat "$H3/.claude/CLAUDE.md")" "~/.claude/CLAUDE.md untouched"

# 14. layers.toml is read from <home>/.ctlhq/, never from $HOME when --home is given.
fake="$tmp/fake-real-home"; mkdir -p "$fake"
printf 'layers = ["%s/no-such-layer"]\n' "$tmp" | settings "$fake"
out="$(HOME="$fake" "$inst" --check --home "$H3" 2>&1)"; expect_rc 0 $? "--home ignores \$HOME/.ctlhq/layers.toml"
expect_grep "^layer 1 +$root: " "$out" "--home with no layers.toml uses this repository as the only layer"
HOME="$fake" "$inst" --check >/dev/null 2>&1; expect_rc 2 $? "without --home, \$HOME/.ctlhq/layers.toml is read"

# Layer B: a second layer with its own skills, agent, rules file and host table.
LB="$tmp/layer-b"
mkdir -p "$LB/skills/private-one" "$LB/skills/agents-only" "$LB/skills/vendor-skill" "$LB/agents" "$LB/home" "$LB/docs"
for s in private-one agents-only vendor-skill; do printf -- '---\nname: %s\n---\n' "$s" > "$LB/skills/$s/SKILL.md"; done
printf -- '---\nname: b-agent\n---\n' > "$LB/agents/b-agent.md"
printf 'skill\thosts\nagents-only\tagents\n' > "$LB/docs/install.tsv"
printf '## Private rules\n\n- Private line.\n\n<!-- acmetool:human-input:v2 -->\nAsk through acmetool.\n<!-- /acmetool:human-input:v2 -->\n' > "$LB/home/AGENTS.md"

# 15. Two layers link side by side; --check prints one line per layer with its path and link count.
H4="$tmp/home4"; mkdir -p "$H4"
printf 'layers = [\n  "%s",  # public\n  "%s",\n]\nnot_shipped = ["vendor-skill"]\n' "$root" "$LB" | settings "$H4"
out="$("$inst" --home "$H4" 2>&1)"; expect_rc 0 $? "install with two layers exits 0"
expect_eq "$root/skills/unslop" "$(readlink "$H4/.claude/skills/unslop")" "layer 1 skill linked"
expect_eq "$LB/skills/private-one" "$(readlink "$H4/.claude/skills/private-one")" "layer 2 skill linked into .claude"
expect_eq "$LB/skills/private-one" "$(readlink "$H4/.codex/skills/private-one")" "layer 2 skill linked into .codex"
expect_eq "$LB/agents/b-agent.md" "$(readlink "$H4/.claude/agents/b-agent.md")" "layer 2 agent linked"
expect_eq "$root/agents/ctlhq-agent.md" "$(readlink "$H4/.claude/agents/ctlhq-agent.md")" "layer 1 agent linked"
out="$("$inst" --check --home "$H4" 2>&1)"; expect_rc 0 $? "--check with two layers exits 0"
n1="$nskills"; [ -d "$root/skills/vendor-skill" ] && n1=$((n1 - 1)) # not_shipped hides it in layer 1 too
expect_grep "^layer 1 +$root: $n1 skills, $nagents agents, $((n1 * 2 + nagents)) links, $((n1 * 2 + nagents)) ok$" "$out" "--check line for layer 1"
expect_grep "^layer 2 +$LB: 2 skills, 1 agents, 4 links, 4 ok$" "$out" "--check line for layer 2"
expect_grep '; clean \(2 layers, ' "$out" "--check clean over 2 layers"

# 16. A layer's own docs/install.tsv sends a skill to .agents only.
expect_eq "$LB/skills/agents-only" "$(readlink "$H4/.agents/skills/agents-only")" "layer host row: linked into .agents"
[ -e "$H4/.claude/skills/agents-only" ] || [ -e "$H4/.codex/skills/agents-only" ] && bad "agents-only must be only in .agents" || ok

# 17. not_shipped: never linked, checked or removed.
[ -e "$H4/.claude/skills/vendor-skill" ] && bad "a not_shipped skill is never linked" || ok
mkdir -p "$H4/.claude/skills/vendor-skill"; echo vendor-owned > "$H4/.claude/skills/vendor-skill/SKILL.md"
ln -s "$LB/skills/vendor-skill" "$H4/.codex/skills/vendor-skill"
out="$("$inst" --check --home "$H4" 2>&1)"; expect_rc 0 $? "--check ignores not_shipped names"
printf '%s\n' "$out" | grep -q vendor-skill && bad "--check names no not_shipped skill" || ok
"$inst" --home "$H4" >/dev/null 2>&1; expect_rc 0 $? "install leaves not_shipped names alone"
"$inst" --uninstall --home "$H4" >/dev/null 2>&1
expect_eq "vendor-owned" "$(cat "$H4/.claude/skills/vendor-skill/SKILL.md")" "uninstall keeps the not_shipped real folder"
expect_eq "$LB/skills/vendor-skill" "$(readlink "$H4/.codex/skills/vendor-skill")" "uninstall keeps the not_shipped link into a layer"
[ -L "$H4/.claude/skills/private-one" ] && bad "uninstall removes layer 2 links" || ok
[ -L "$H4/.claude/skills/unslop" ] && bad "uninstall removes layer 1 links" || ok

# 18. Per-machine [hosts] rows override the layers' host tables.
"$inst" --home "$H4" >/dev/null 2>&1
printf 'layers = ["%s", "%s"]\nnot_shipped = ["vendor-skill"]\n\n[hosts]\nunslop = ["claude"]\nagents-only = ["claude"]\n' "$root" "$LB" | settings "$H4"
out="$("$inst" --check --home "$H4" 2>&1)"; expect_rc 1 $? "--check after a new [hosts] row exits 1"
expect_grep '^extra +~/\.codex/skills/unslop ' "$out" "[hosts] row turns the codex link into an extra"
"$inst" --home "$H4" >/dev/null 2>&1; expect_rc 0 $? "install with [hosts] rows exits 0"
[ -L "$H4/.codex/skills/unslop" ] && bad "[hosts] unslop = claude removes the codex link" || ok
expect_eq "$root/skills/unslop" "$(readlink "$H4/.claude/skills/unslop")" "[hosts] keeps the claude link"
expect_eq "$LB/skills/agents-only" "$(readlink "$H4/.claude/skills/agents-only")" "[hosts] overrides the layer table: claude"
[ -L "$H4/.agents/skills/agents-only" ] && bad "[hosts] overrides the layer table: no .agents link" || ok
printf 'layers = ["%s"]\n[hosts]\nno-such-skill = ["claude"]\n' "$root" | settings "$H4"
"$inst" --check --home "$H4" >/dev/null 2>&1; expect_rc 2 $? "[hosts] row for a skill no layer ships exits 2"
printf 'layers = ["%s"]\n[hosts]\nunslop = ["other-host"]\n' "$root" | settings "$H4"
"$inst" --check --home "$H4" >/dev/null 2>&1; expect_rc 2 $? "[hosts] row with an unknown host exits 2"

# 19. The same skill or agent name in two layers is refused with exit 1, and nothing changes.
H5="$tmp/home5"; mkdir -p "$H5"
LC="$tmp/layer-c"; mkdir -p "$LC/skills/unslop"; printf -- '---\nname: unslop\n---\n' > "$LC/skills/unslop/SKILL.md"
LD="$tmp/layer-d"; mkdir -p "$LD/agents"; printf -- '---\nname: x\n---\n' > "$LD/agents/ctlhq-agent.md"
"$inst" --home "$H5" >/dev/null 2>&1
for dup in "$LC" "$LD"; do
	printf 'layers = ["%s", "%s"]\nagents_md = true\n' "$root" "$dup" | settings "$H5"
	before="$(snap "$H5")"
	for mode in "" "--dry-run" "--check" "--uninstall" "--replace" "--agents-md"; do
		out="$("$inst" $mode --home "$H5" 2>&1)"; expect_rc 1 $? "duplicate name in $(basename "$dup"), mode '${mode:-install}' exits 1"
	done
	expect_grep "^duplicate +(skill unslop|agent ctlhq-agent\.md) in $root and $dup$" "$out" "duplicate named with both layers ($(basename "$dup"))"
	expect_eq "$before" "$(snap "$H5")" "duplicate in $(basename "$dup"): nothing changed in any mode"
done

# 20. A listed layer that is not a folder holding skills/, agents/ or home/ exits 2 in every mode, nothing changed.
mkdir -p "$tmp/empty-layer/docs"; echo x > "$tmp/plain-file"
for bad_layer in "$tmp/no-such-layer" "$tmp/plain-file" "$tmp/empty-layer" "relative/path"; do
	printf 'layers = ["%s", "%s"]\n' "$root" "$bad_layer" | settings "$H5"
	before="$(snap "$H5")"
	for mode in "" "--dry-run" "--check" "--uninstall" "--replace" "--agents-md"; do
		"$inst" $mode --home "$H5" >/dev/null 2>&1; expect_rc 2 $? "bad layer $(basename "$bad_layer"), mode '${mode:-install}' exits 2"
	done
	expect_eq "$before" "$(snap "$H5")" "bad layer $(basename "$bad_layer"): nothing changed in any mode"
done
printf 'layers = ["%s"]\ncolour = true\n' "$root" | settings "$H5"
"$inst" --check --home "$H5" >/dev/null 2>&1; expect_rc 2 $? "unknown key in layers.toml exits 2"
printf 'layers = ["%s", "%s"]\n' "$root" "$root" | settings "$H5"
"$inst" --check --home "$H5" >/dev/null 2>&1; expect_rc 2 $? "a layer listed twice exits 2"

# 21. agents_md = true writes ~/.codex/AGENTS.md: a generated-file marker naming the sources, then each
#     layer's home/AGENTS.md joined in layer order.
H6="$tmp/home6"; mkdir -p "$H6/.claude"
printf '@~/.codex/AGENTS.md\n' > "$H6/.claude/CLAUDE.md"
printf 'layers = ["%s", "%s"]\nnot_shipped = ["vendor-skill"]\nagents_md = true\n' "$root" "$LB" | settings "$H6"
A="$H6/.codex/AGENTS.md"
"$inst" --home "$H6" >/dev/null 2>&1; expect_rc 0 $? "install with agents_md = true exits 0"
[ -f "$A" ] && [ ! -L "$A" ] && ok || bad "~/.codex/AGENTS.md is a real file"
first="$(head -1 "$A")"
expect_grep '^<!-- generated by ctlhq-install ' "$first" "first line is the generated-file marker"
expect_grep "$root/home/AGENTS\.md" "$first" "marker names layer 1's rules file"
expect_grep "$LB/home/AGENTS\.md" "$first" "marker names layer 2's rules file"
expect_eq "$(cat "$root/home/AGENTS.md"; echo; cat "$LB/home/AGENTS.md")" "$(tail -n +3 "$A")" "body is layer 1 then layer 2, joined by one blank line"
"$inst" --check --home "$H6" >/dev/null 2>&1; expect_rc 0 $? "--check clean after writing the rules file"
out="$("$inst" --home "$H6" 2>&1)"; expect_grep ', 0 written, 0 managed kept ' "$out" "second install leaves the rules file alone"
expect_eq "@~/.codex/AGENTS.md" "$(cat "$H6/.claude/CLAUDE.md")" "~/.claude/CLAUDE.md untouched with agents_md"

# 22. A link at ~/.codex/AGENTS.md is removed before the write; its target stays byte-identical (the leak test).
H7="$tmp/home7"; mkdir -p "$H7/.codex"
printf 'layers = ["%s", "%s"]\nnot_shipped = ["vendor-skill"]\n' "$root" "$LB" | settings "$H7"
cp "$root/home/AGENTS.md" "$tmp/public-rules-before"
ln -s "$root/home/AGENTS.md" "$H7/.codex/AGENTS.md"
"$inst" --home "$H7" >/dev/null 2>&1
out="$("$inst" --check --home "$H7" 2>&1)"; expect_rc 0 $? "agents_md off: a link at AGENTS.md is not checked"
out="$("$inst" --agents-md --dry-run --home "$H7" 2>&1)"; expect_rc 0 $? "--agents-md --dry-run exits 0"
expect_grep '^would remove link ~/\.codex/AGENTS\.md \(was ' "$out" "--dry-run names the link removal"
[ -L "$H7/.codex/AGENTS.md" ] && ok || bad "--agents-md --dry-run keeps the link"
grep -q agents_md "$H7/.ctlhq/layers.toml" && bad "--agents-md --dry-run does not change layers.toml" || ok
out="$("$inst" --agents-md --home "$H7" 2>&1)"; expect_rc 0 $? "--agents-md replaces the link, exits 0"
expect_grep '^remove link ~/\.codex/AGENTS\.md ' "$out" "link removal reported"
[ -L "$H7/.codex/AGENTS.md" ] && bad "the link is gone" || ok
expect_grep '^<!-- generated by ctlhq-install ' "$(head -1 "$H7/.codex/AGENTS.md")" "generated file in place of the link"
cmp -s "$tmp/public-rules-before" "$root/home/AGENTS.md" && ok || bad "old link target is byte-identical after the write"
expect_grep '^agents_md = true$' "$(cat "$H7/.ctlhq/layers.toml")" "--agents-md saves agents_md = true"
expect_grep '^not_shipped = \["vendor-skill"\]$' "$(cat "$H7/.ctlhq/layers.toml")" "--agents-md keeps the other lines"
ln -sfn "$LB/home/AGENTS.md" "$H7/.codex/AGENTS.md"; cp "$LB/home/AGENTS.md" "$tmp/private-rules-before"
out="$("$inst" --check --home "$H7" 2>&1)"; expect_rc 1 $? "--check with a link at AGENTS.md exits 1"
expect_grep '^link +~/\.codex/AGENTS\.md -> ' "$out" "a link at AGENTS.md is reported"
"$inst" --home "$H7" >/dev/null 2>&1; expect_rc 0 $? "install replaces a link into layer 2"
cmp -s "$tmp/private-rules-before" "$LB/home/AGENTS.md" && ok || bad "layer 2 rules file byte-identical after the write"

# 23. A real file without the marker is "copy": exit 1, untouched; --replace backs it up first;
#     --agents-md --replace --dry-run only names the backup.
rm "$H7/.codex/AGENTS.md"; printf 'my own rules\n' > "$H7/.codex/AGENTS.md"
out="$("$inst" --check --home "$H7" 2>&1)"; expect_rc 1 $? "--check with a real AGENTS.md exits 1"
expect_grep '^copy +~/\.codex/AGENTS\.md is a real file without the generated-file marker$' "$out" "real AGENTS.md reported as copy"
out="$("$inst" --home "$H7" 2>&1)"; expect_rc 1 $? "install with a real AGENTS.md exits 1"
expect_grep '^copy +~/\.codex/AGENTS\.md: copy in place, not replaced' "$out" "real AGENTS.md left in place"
expect_eq "my own rules" "$(cat "$H7/.codex/AGENTS.md")" "real AGENTS.md content untouched"
bk7="$H7/.ctlhq-backups/$(date +%Y-%m-%d)/.codex/AGENTS.md"
cp "$H7/.codex/AGENTS.md" "$tmp/own-rules-before"
out="$("$inst" --agents-md --replace --dry-run --home "$H7" 2>&1)"; expect_rc 0 $? "--agents-md --replace --dry-run with a real AGENTS.md exits 0"
expect_grep '^would back up +~/\.codex/AGENTS\.md -> ~/\.ctlhq-backups/[0-9-]+/\.codex/AGENTS\.md$' "$out" "--dry-run names the AGENTS.md backup"
cmp -s "$tmp/own-rules-before" "$H7/.codex/AGENTS.md" && ok || bad "--agents-md --replace --dry-run leaves the real AGENTS.md byte-identical"
[ -f "$H7/.codex/AGENTS.md" ] && [ ! -L "$H7/.codex/AGENTS.md" ] && ok || bad "real AGENTS.md is still a real file after the dry run"
[ -e "$bk7" ] && bad "--agents-md --replace --dry-run writes no backup" || ok
out="$("$inst" --replace --home "$H7" 2>&1)"; expect_rc 0 $? "--replace with a real AGENTS.md exits 0"
expect_eq "my own rules" "$(cat "$bk7" 2>/dev/null)" "real AGENTS.md moved to the dated backup path"
expect_grep '^<!-- generated by ctlhq-install ' "$(head -1 "$H7/.codex/AGENTS.md")" "generated file written after --replace"

# 24. A block another tool manages that differs from the sources is reported, named with the tool, and never overwritten.
cp "$A" "$tmp/generated"
python3 - "$A" <<'PY'
import sys
p = sys.argv[1]
t = open(p).read()
t = t.replace("<!-- acmetool:human-input:v2 -->\nAsk through acmetool.\n<!-- /acmetool:human-input:v2 -->",
              "<!-- acmetool:human-input:v3 -->\nAsk through acmetool, version 3.\n<!-- /acmetool:human-input:v3 -->")
open(p, "w").write(t)
PY
cp "$A" "$tmp/managed-edited"
out="$("$inst" --check --home "$H6" 2>&1)"; expect_rc 1 $? "--check with a new managed block exits 1"
expect_grep '^managed +~/\.codex/AGENTS\.md has a block managed by acmetool that differs' "$out" "managed drift reported with the tool's name"
out="$("$inst" --home "$H6" 2>&1)"; expect_rc 1 $? "install with managed drift exits 1"
expect_grep '^managed +~/\.codex/AGENTS\.md: its block managed by acmetool .*not overwritten' "$out" "install refuses to overwrite the managed block"
expect_grep ', 1 managed kept ' "$out" "install counts the kept block"
cmp -s "$tmp/managed-edited" "$A" && ok || bad "the new managed block is still in the file"
printf '\n<!-- othertool:notes:v1 -->\nx\n<!-- /othertool:notes:v1 -->\n' >> "$A"
out="$("$inst" --check --home "$H6" 2>&1)"; expect_rc 1 $? "an added block from a second tool is drift, exit 1"
expect_grep 'managed by acmetool, othertool that differs' "$out" "every drifted tool is named"
"$inst" --home "$H6" >/dev/null 2>&1; expect_rc 1 $? "an added managed block is also kept, exit 1"
cp "$tmp/generated" "$A"

# 25. Any other drift in the generated file: --check reports it, install rewrites it.
printf 'a hand edit\n' >> "$A"
out="$("$inst" --check --home "$H6" 2>&1)"; expect_rc 1 $? "--check with a hand edit exits 1"
expect_grep '^stale +~/\.codex/AGENTS\.md differs from the layers' "$out" "hand edit reported stale"
out="$("$inst" --home "$H6" 2>&1)"; expect_rc 0 $? "install rewrites a stale file, exit 0"
expect_grep '^write +~/\.codex/AGENTS\.md ' "$out" "rewrite reported"
cmp -s "$tmp/generated" "$A" && ok || bad "rewritten file equals the joined sources"

# 26. --uninstall removes the generated file after a backup and prints the @ line; a real file stays.
out="$("$inst" --uninstall --dry-run --home "$H6" 2>&1)"
expect_grep '^would remove +~/\.codex/AGENTS\.md \(generated' "$out" "--uninstall --dry-run names the generated file"
[ -f "$A" ] && ok || bad "--uninstall --dry-run keeps the generated file"
out="$("$inst" --uninstall --home "$H6" 2>&1)"; expect_rc 0 $? "--uninstall with a generated file exits 0"
[ -e "$A" ] && bad "--uninstall removes the generated file" || ok
cmp -s "$tmp/generated" "$H6/.ctlhq-backups/$(date +%Y-%m-%d)/.codex/AGENTS.md" && ok || bad "generated file backed up before removal"
expect_grep '^  @~/\.codex/AGENTS\.md$' "$out" "--uninstall prints the @ line for ~/.claude/CLAUDE.md"
expect_eq "@~/.codex/AGENTS.md" "$(cat "$H6/.claude/CLAUDE.md")" "--uninstall leaves ~/.claude/CLAUDE.md alone"
expect_grep '^agents_md = true stays in ~/\.ctlhq/layers\.toml\. Delete that line, or a later install writes ~/\.codex/AGENTS\.md again\.$' "$out" "--uninstall says agents_md = true stays in layers.toml"
printf 'my own rules\n' > "$A"
out="$("$inst" --uninstall --home "$H6" 2>&1)"
expect_eq "my own rules" "$(cat "$A" 2>/dev/null)" "--uninstall keeps a real AGENTS.md without the marker"
printf '%s\n' "$out" | grep -q '@~/.codex/AGENTS.md' && bad "no @ line when nothing generated was removed" || ok

# 27. --agents-md with a [hosts] table already in layers.toml saves the setting above the table,
#     so later runs keep checking the rules file.
H7="$tmp/home7"; mkdir -p "$H7"
printf 'layers = ["%s", "%s"]\nnot_shipped = ["vendor-skill"]\n\n[hosts]\nunslop = ["claude"]\n' "$root" "$LB" | settings "$H7"
"$inst" --agents-md --home "$H7" >/dev/null 2>&1; expect_rc 0 $? "--agents-md with a [hosts] table exits 0"
expect_eq "agents_md = true" "$(grep -E '^agents_md' "$H7/.ctlhq/layers.toml")" "--agents-md saved the setting"
before_hosts="$(awk '/^\[hosts\]/{exit} /^agents_md = true$/{print "yes"}' "$H7/.ctlhq/layers.toml")"
expect_eq "yes" "$before_hosts" "agents_md line sits above [hosts]"
expect_grep '^unslop = \["claude"\]$' "$(cat "$H7/.ctlhq/layers.toml")" "[hosts] row kept"
printf 'hand edit\n' >> "$H7/.codex/AGENTS.md"
out="$("$inst" --check --home "$H7" 2>&1)"; expect_rc 1 $? "--check after a hand edit exits 1"
expect_grep '^stale +~/\.codex/AGENTS\.md' "$out" "--check reports the hand edit as stale"

# 28. --agents-md never writes through a layers.toml that is a link; a key set twice is refused.
H8="$tmp/home8"; mkdir -p "$H8/.ctlhq" "$tmp/elsewhere"
printf 'layers = ["%s"]\n' "$root" > "$tmp/elsewhere/layers.toml"
ln -s "$tmp/elsewhere/layers.toml" "$H8/.ctlhq/layers.toml"
"$inst" --agents-md --home "$H8" >/dev/null 2>&1; expect_rc 2 $? "--agents-md with a linked layers.toml exits 2"
expect_eq "layers = [\"$root\"]" "$(cat "$tmp/elsewhere/layers.toml")" "linked layers.toml target unchanged"
[ -e "$H8/.codex/AGENTS.md" ] && bad "nothing written when layers.toml is a link" || ok
printf 'layers = ["%s"]\nagents_md = true\nagents_md = false\n' "$root" | settings "$H6"
"$inst" --check --home "$H6" >/dev/null 2>&1; expect_rc 2 $? "a key set twice exits 2"

# 29. --uninstall prints the @ line also when it removes a rules link into a layer (today's setups);
#     a rules link outside every layer is the user's own, so --uninstall keeps it and prints a keep line.
H9="$tmp/home9"; mkdir -p "$H9/.codex"
ln -s "$root/home/AGENTS.md" "$H9/.codex/AGENTS.md"
out="$("$inst" --uninstall --home "$H9" 2>&1)"; expect_rc 0 $? "--uninstall with a rules link exits 0"
[ -L "$H9/.codex/AGENTS.md" ] && bad "--uninstall removes the rules link into a layer" || ok
expect_grep '^  @~/\.codex/AGENTS\.md$' "$out" "--uninstall prints the @ line after removing the rules link"
printf 'theirs\n' > "$tmp/other-agents.md"; ln -s "$tmp/other-agents.md" "$H9/.codex/AGENTS.md"
out="$("$inst" --uninstall --home "$H9" 2>&1)"; expect_rc 0 $? "--uninstall with a rules link outside every layer exits 0"
expect_grep '^keep +~/\.codex/AGENTS\.md -> '"$tmp"'/other-agents\.md \(outside every layer\)$' "$out" "--uninstall prints a keep line for the outside rules link"
expect_grep '^uninstall: 0 removed, 1 kept, ' "$out" "--uninstall counts the outside rules link as kept"
expect_eq "$tmp/other-agents.md" "$(readlink "$H9/.codex/AGENTS.md")" "--uninstall keeps the outside rules link"
expect_eq "theirs" "$(cat "$tmp/other-agents.md")" "outside rules link target untouched"

# 30. --agents-md with the user's own AGENTS.md and no --replace saves nothing, so later runs stay clean;
#     --agents-md --replace then backs the file up, writes the generated one, and saves the setting.
H10="$tmp/home10"; mkdir -p "$H10/.codex"; printf 'my own rules\n' > "$H10/.codex/AGENTS.md"
out="$("$inst" --agents-md --dry-run --home "$H10" 2>&1)"; expect_rc 1 $? "--agents-md --dry-run with an own AGENTS.md exits 1"
expect_grep '^not set +agents_md = true in ~/\.ctlhq/layers\.toml: ~/\.codex/AGENTS\.md is your own file' "$out" "--dry-run says the setting would not be saved"
expect_no_line '^would set ' "$out" "--dry-run with an own AGENTS.md does not claim it would set agents_md"
out="$("$inst" --agents-md --home "$H10" 2>&1)"; expect_rc 1 $? "--agents-md with an own AGENTS.md exits 1"
expect_grep '^copy +~/\.codex/AGENTS\.md: copy in place, not replaced' "$out" "own AGENTS.md left in place"
expect_grep '^not set +agents_md = true .*--agents-md --replace.*To keep your file, do nothing' "$out" "the message names --replace and leaving the file"
expect_no_line '^set +agents_md' "$out" "no 'set agents_md' line while the own file stays"
grep -q agents_md "$H10/.ctlhq/layers.toml" 2>/dev/null && bad "--agents-md saves nothing while the own file stays" || ok
expect_eq "my own rules" "$(cat "$H10/.codex/AGENTS.md")" "own AGENTS.md content untouched"
"$inst" --home "$H10" >/dev/null 2>&1; expect_rc 0 $? "a later plain install exits 0"
"$inst" --check --home "$H10" >/dev/null 2>&1; expect_rc 0 $? "a later --check is clean"
out="$("$inst" --agents-md --replace --home "$H10" 2>&1)"; expect_rc 0 $? "--agents-md --replace exits 0"
expect_grep '^set +agents_md = true in ~/\.ctlhq/layers\.toml$' "$out" "--agents-md --replace saves the setting"
expect_grep '^agents_md = true$' "$(cat "$H10/.ctlhq/layers.toml")" "layers.toml holds agents_md = true"
expect_eq "my own rules" "$(cat "$H10/.ctlhq-backups/$(date +%Y-%m-%d)/.codex/AGENTS.md" 2>/dev/null)" "own AGENTS.md backed up"
expect_grep '^<!-- generated by ctlhq-install ' "$(head -1 "$H10/.codex/AGENTS.md")" "generated file written"
"$inst" --check --home "$H10" >/dev/null 2>&1; expect_rc 0 $? "--check clean after --agents-md --replace"

# 31. --uninstall lists, and leaves, a link into a layer under a name no layer ships (a renamed skill).
H11="$tmp/home11"; mkdir -p "$H11"
"$inst" --home "$H11" >/dev/null 2>&1
ln -s "$root/skills/how" "$H11/.claude/skills/old-name"
ln -s "$root/agents/ctlhq-agent.md" "$H11/.claude/agents/old-agent.md"
ln -s "$tmp/other/tdd" "$H11/.codex/skills/not-ours"
out="$("$inst" --uninstall --dry-run --home "$H11" 2>&1)"; expect_rc 0 $? "--uninstall --dry-run with leftovers exits 0"
expect_grep '^left +~/\.claude/skills/old-name -> .*delete it yourself' "$out" "--dry-run lists the leftover skill link"
out="$("$inst" --uninstall --home "$H11" 2>&1)"; expect_rc 0 $? "--uninstall with leftovers exits 0"
expect_grep '^left +~/\.claude/skills/old-name -> '"$root"'/skills/how ' "$out" "leftover skill link listed with its target"
expect_grep '^left +~/\.claude/agents/old-agent\.md -> ' "$out" "leftover agent link listed"
expect_no_line 'not-ours' "$out" "a link outside every layer is not listed"
expect_no_line 'agents_md' "$out" "--uninstall without agents_md = true says nothing about it"
expect_grep "^uninstall: $total removed, 0 kept, 2 left for you to delete " "$out" "uninstall counts the leftovers"
[ -L "$H11/.claude/skills/old-name" ] && [ -L "$H11/.claude/agents/old-agent.md" ] && ok || bad "leftover links stay in place"
[ -L "$H11/.claude/skills/how" ] && bad "shipped links removed" || ok

# 32. agents_md off (line deleted, or false) with a generated ~/.codex/AGENTS.md still in place: --check
#     reports it as unwanted; install backs it up, removes it, and prints the @ line. A file without the
#     marker is never touched.
H12="$tmp/home12"; mkdir -p "$H12"; A12="$H12/.codex/AGENTS.md"
printf 'layers = ["%s"]\n' "$root" | settings "$H12"
"$inst" --agents-md --home "$H12" >/dev/null 2>&1; expect_rc 0 $? "--agents-md writes the rules file"
cp "$A12" "$tmp/generated12"
grep -v '^agents_md' "$H12/.ctlhq/layers.toml" >"$tmp/layers12"; settings "$H12" <"$tmp/layers12"
out="$("$inst" --check --home "$H12" 2>&1)"; expect_rc 1 $? "agents_md line deleted: --check with the generated file exits 1"
expect_grep '^unwanted +~/\.codex/AGENTS\.md is a generated file, but agents_md is not true' "$out" "--check reports the generated file as unwanted"
expect_grep ', 1 unwanted; 1 drift ' "$out" "--check counts the unwanted file as drift"
out="$("$inst" --dry-run --home "$H12" 2>&1)"; expect_rc 0 $? "--dry-run with an unwanted rules file exits 0"
expect_grep '^would back up +~/\.codex/AGENTS\.md -> ~/\.ctlhq-backups/' "$out" "--dry-run names the backup"
expect_grep '^dry run: .*, 1 backed up, .*, 1 rules removed ' "$out" "--dry-run counts the rules backup in backed up"
cmp -s "$tmp/generated12" "$A12" && ok || bad "--dry-run keeps the unwanted rules file"
out="$("$inst" --home "$H12" 2>&1)"; expect_rc 0 $? "install with an unwanted rules file exits 0"
[ -e "$A12" ] && bad "install removes the unwanted rules file" || ok
cmp -s "$tmp/generated12" "$H12/.ctlhq-backups/$(date +%Y-%m-%d)/.codex/AGENTS.md" && ok || bad "unwanted rules file backed up before removal"
expect_grep '^  @~/\.codex/AGENTS\.md$' "$out" "install prints the @ line after removing the rules file"
expect_grep '^install: .*, 1 backed up, .*, 1 rules removed ' "$out" "install counts the removed rules file, and its backup in backed up"
"$inst" --check --home "$H12" >/dev/null 2>&1; expect_rc 0 $? "--check clean after the unwanted file is removed"
"$inst" --agents-md --home "$H12" >/dev/null 2>&1
sed 's/^agents_md = true$/agents_md = false/' "$H12/.ctlhq/layers.toml" >"$tmp/layers12"; settings "$H12" <"$tmp/layers12"
out="$("$inst" --check --home "$H12" 2>&1)"; expect_rc 1 $? "agents_md = false: --check with the generated file exits 1"
expect_grep '^unwanted +~/\.codex/AGENTS\.md ' "$out" "agents_md = false: the generated file is unwanted"
"$inst" --home "$H12" >/dev/null 2>&1; expect_rc 0 $? "agents_md = false: install exits 0"
[ -e "$A12" ] && bad "agents_md = false: install removes the generated file" || ok
printf 'my own rules\n' >"$A12"
out="$("$inst" --home "$H12" 2>&1)"; expect_rc 0 $? "agents_md = false with an own AGENTS.md: install exits 0"
expect_eq "my own rules" "$(cat "$A12")" "agents_md = false: an own AGENTS.md is untouched"
expect_no_line 'AGENTS\.md' "$out" "agents_md = false: install names no own AGENTS.md"
"$inst" --check --home "$H12" >/dev/null 2>&1; expect_rc 0 $? "agents_md = false: --check is clean with an own AGENTS.md"

# 33. A link into a layer whose target is gone (an old skill or agent name after a rename) is the
#     installer's own leftover: --check reports it as stale, install removes it, uninstall removes it.
#     A user's link elsewhere, broken or not, and a leftover whose target exists are untouched.
#     So are links that only look like leftovers: a relative link, a link deeper inside a layer,
#     and a link into a layer whose skills/ folder is missing (layerF holds only home/).
H13="$tmp/home13"; mkdir -p "$H13"
layerF="$tmp/layer-no-skills"; mkdir -p "$layerF/home"
printf 'layers = ["%s", "%s"]\n[hosts]\nhow = ["claude"]\n' "$root" "$layerF" | settings "$H13"
"$inst" --home "$H13" >/dev/null 2>&1
ln -s "$root/skills/old-skill-name" "$H13/.claude/skills/old-skill-name"
ln -s "$root/skills/old-skill-name" "$H13/.codex/skills/old-skill-name"
ln -s "$root/agents/ctlhq-comment-reviewer.md" "$H13/.claude/agents/ctlhq-comment-reviewer.md"
mkdir -p "$tmp/mine-skill"
ln -s "$tmp/mine-skill" "$H13/.claude/skills/mine"
ln -s "$tmp/gone-skill" "$H13/.claude/skills/gone-mine"
ln -s "$root/skills/how" "$H13/.claude/skills/renamed-but-present"
ln -s "$(python3 -c 'import os, sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))' "$root/skills/gone-relative" "$H13/.claude/skills")" "$H13/.claude/skills/gone-relative"
ln -s "$root/skills/how/gone-deeper" "$H13/.claude/skills/gone-deeper"
ln -s "$layerF/skills/gone-f" "$H13/.claude/skills/gone-f"
out="$("$inst" --check --home "$H13" 2>&1)"; expect_rc 1 $? "--check with stale links exits 1"
expect_grep '^stale +~/\.claude/skills/old-skill-name -> .*/skills/old-skill-name; its target is gone$' "$out" "--check reports the old skill link as stale"
expect_grep '^stale +~/\.codex/skills/old-skill-name -> ' "$out" "--check reports the old codex skill link as stale"
expect_grep '^stale +~/\.claude/agents/ctlhq-comment-reviewer\.md -> ' "$out" "--check reports the old agent link as stale"
expect_grep '^fix: +run ctlhq-install to remove the 3 stale links$' "$out" "--check prints a fix line for stale links"
expect_grep ' 3 stale' "$out" "--check counts 3 stale links"
expect_no_line 'mine|renamed-but-present' "$out" "--check leaves the user's links and present leftovers out"
expect_no_line 'gone-relative|gone-deeper|gone-f' "$out" "--check does not call a relative, deeper, or missing-folder link stale"
out="$("$inst" --dry-run --home "$H13" 2>&1)"; expect_rc 0 $? "--dry-run with stale links exits 0"
expect_grep '^would remove stale ~/\.claude/skills/old-skill-name ' "$out" "--dry-run names the stale removal"
[ -L "$H13/.claude/skills/old-skill-name" ] && ok || bad "--dry-run keeps the stale link"
out="$("$inst" --home "$H13" 2>&1)"; expect_rc 0 $? "install with stale links exits 0"
expect_grep '^remove stale ~/\.claude/skills/old-skill-name \(was .*/skills/old-skill-name; its target is gone\)$' "$out" "install prints one line per stale removal"
expect_grep '^remove stale ~/\.claude/agents/ctlhq-comment-reviewer\.md ' "$out" "install prints the old agent removal"
expect_grep '^install: .*, 3 stale removed ' "$out" "install counts the stale removals"
[ -L "$H13/.claude/skills/old-skill-name" ] || [ -L "$H13/.codex/skills/old-skill-name" ] || [ -L "$H13/.claude/agents/ctlhq-comment-reviewer.md" ] && bad "install removes every stale link" || ok
[ -L "$H13/.claude/skills/mine" ] && [ -L "$H13/.claude/skills/gone-mine" ] && [ -L "$H13/.claude/skills/renamed-but-present" ] && ok || bad "install keeps the user's links and present leftovers"
for name in gone-relative gone-deeper gone-f; do
	[ -L "$H13/.claude/skills/$name" ] && ok || bad "install keeps the $name link"
done
out="$("$inst" --check --home "$H13" 2>&1)"; expect_rc 0 $? "--check is clean after install removes the stale links"
ln -s "$root/skills/old-skill-name" "$H13/.claude/skills/old-skill-name"
out="$("$inst" --uninstall --home "$H13" 2>&1)"; expect_rc 0 $? "--uninstall with a stale link exits 0"
expect_grep '^remove +~/\.claude/skills/old-skill-name \(its target is gone\)$' "$out" "--uninstall removes the stale link"
[ -L "$H13/.claude/skills/old-skill-name" ] && bad "--uninstall removes the stale link from disk" || ok
expect_grep '^left +~/\.claude/skills/renamed-but-present -> ' "$out" "--uninstall still leaves a leftover whose target exists"
[ -L "$H13/.claude/skills/mine" ] && [ -L "$H13/.claude/skills/gone-mine" ] && ok || bad "--uninstall keeps the user's links"
for name in gone-relative gone-deeper gone-f; do
	expect_grep "^left +~/\.claude/skills/$name -> " "$out" "--uninstall lists the $name link as left"
	[ -L "$H13/.claude/skills/$name" ] && ok || bad "--uninstall keeps the $name link"
done

echo "$pass checks passed"
[ "$fail" -eq 0 ] || { echo "$fail checks failed"; exit 1; }
