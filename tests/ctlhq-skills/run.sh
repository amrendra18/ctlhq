#!/usr/bin/env bash
# tests/ctlhq-skills/run.sh: checks for bin/ctlhq-skills, on the real skills/ tree and on a
# synthetic repository root (the tool copied into a mktemp folder, which it treats as its root).
# Covers every command (list, find, path, show and its aliases help and info), every flag
# (--agents, --json, --full), and exits 0, 1, 2. Read-only for the repository.
# Prints "N checks passed" and exits 1 when any check fails.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
fs="$root/bin/ctlhq-skills"
tmpbase="${TMPDIR:-/tmp}"; tmp="$(cd "$(mktemp -d "${tmpbase%/}/ctlhq-skills-test.XXXXXX")" && pwd -P)"
trap 'chmod -R u+rw "$tmp" 2>/dev/null; rm -rf "$tmp"' EXIT
pass=0
fail=0
ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL: $1"; }
expect_rc() { if [ "$1" -eq "$2" ]; then ok; else bad "$3 (expected exit $1, got $2)"; fi; }
expect_eq() { if [ "$1" = "$2" ]; then ok; else bad "$3 (expected '$1', got '$2')"; fi; }
expect_grep() { if printf '%s\n' "$2" | grep -Eq -- "$1"; then ok; else bad "$3 (no line matches: $1)"; fi; }
expect_no() { if printf '%s\n' "$2" | grep -Eq -- "$1"; then bad "$3 (a line matches: $1)"; else ok; fi; }
lines() { printf '%s\n' "$1" | grep -c .; }
py() { python3 -c "$1"; }

nskills=$(ls "$root"/skills/*/SKILL.md | wc -l | tr -d ' ')
nagents=$(ls "$root"/agents/*.md | wc -l | tr -d ' ')

# 1. --help and -h.
out="$("$fs" --help 2>&1)"; expect_rc 0 $? "--help exits 0"
expect_grep '^ctlhq-skills: ' "$(printf '%s\n' "$out" | head -1)" "--help first line is 'ctlhq-skills: ...'"
for word in find path show --agents --json --full; do
	expect_grep "$word" "$out" "--help names $word"
done
out2="$("$fs" -h 2>&1)"; expect_eq "$out" "$out2" "-h prints the same help as --help"
"$fs" find --help >/dev/null 2>&1; expect_rc 0 $? "--help after a command still exits 0"

# 2. Default listing on the real tree: one row per skill, principles last, exit 0.
out="$("$fs" 2>/dev/null)"; expect_rc 0 $? "listing exits 0"
expect_eq "$nskills" "$(lines "$out")" "listing has one row per skills/*/SKILL.md ($nskills)"
expect_grep '^unslop +Cut AI tells' "$out" "unslop row shows its description"
first_p=$(printf '%s\n' "$out" | grep -n '^principle-' | head -1 | cut -d: -f1)
last_np=$(printf '%s\n' "$out" | grep -vn '^principle-' | tail -1 | cut -d: -f1)
if [ -n "$first_p" ] && [ "$first_p" -gt "$last_np" ]; then ok; else bad "principle-* rows come after every other row"; fi
expect_no '\[agent\]' "$out" "no agent rows without --agents"

# 3. --json listing.
json="$("$fs" --json 2>/dev/null)"; expect_rc 0 $? "--json exits 0"
expect_eq "$nskills True True" "$(printf '%s' "$json" | py '
import json, sys
d = json.load(sys.stdin)
print(len(d), all(set(r) == {"name", "description", "path", "invocable", "kind"} for r in d),
      all(isinstance(r["invocable"], bool) and r["kind"] == "skill" for r in d))')" "--json: $nskills rows, five keys, boolean invocable, kind skill"

# 4. --agents.
out="$("$fs" --agents 2>/dev/null)"; expect_rc 0 $? "--agents exits 0"
expect_eq "$((nskills + nagents))" "$(lines "$out")" "--agents adds one row per agents/*.md"
expect_eq "$nagents" "$(printf '%s\n' "$out" | tail -"$nagents" | grep -c '  \[agent\]$')" "agent rows are last and tagged [agent]"
expect_eq "$nagents" "$("$fs" --agents --json | py 'import json,sys; print(sum(1 for r in json.load(sys.stdin) if r["kind"] == "agent"))')" "--agents --json marks agents with kind agent"

# 5. find.
out="$("$fs" find unslop 2>&1)"; expect_rc 0 $? "find unslop exits 0"
expect_grep '^unslop ' "$out" "find unslop lists unslop"
out="$("$fs" find UNSLOP 2>&1)"; expect_grep '^unslop ' "$out" "find is case-insensitive"
out="$("$fs" find tells writing 2>&1)"; expect_grep '^unslop ' "$out" "find with two words matches when both appear"
"$fs" find unslop zzqqxx-nomatch >/dev/null 2>&1; expect_rc 1 $? "find needs every word (one missing word exits 1)"
out="$("$fs" find zzqqxx-nomatch 2>&1)"; rc=$?
expect_rc 1 "$rc" "find with no match exits 1 (known-bad input)"
expect_eq "" "$out" "find with no match prints nothing"
"$fs" find >/dev/null 2>&1; expect_rc 2 $? "find without a word exits 2"
"$fs" find ctlhq-agent >/dev/null 2>&1; expect_rc 1 $? "find does not see agents without --agents"
out="$("$fs" --agents find ctlhq-agent 2>&1)"; expect_grep '\[agent\]$' "$out" "--agents find sees agents"
expect_eq "$(lines "$("$fs" find unslop)")" "$("$fs" --json find unslop | py 'import json,sys; print(len(json.load(sys.stdin)))')" "--json find prints the same rows as a JSON array"

# 6. path.
out="$("$fs" path unslop 2>&1)"; expect_rc 0 $? "path unslop exits 0"
expect_eq "$root/skills/unslop/SKILL.md" "$out" "path prints the absolute SKILL.md path"
out="$("$fs" path UnSlop 2>&1)"; expect_eq "$root/skills/unslop/SKILL.md" "$out" "path is case-insensitive"
err="$("$fs" path nosuch-skill 2>&1 >/dev/null)"; rc=$?
expect_rc 2 "$rc" "path of an unknown name exits 2"
expect_grep "unknown skill 'nosuch-skill'" "$err" "path names the unknown skill on stderr"
"$fs" path >/dev/null 2>&1; expect_rc 2 $? "path without a name exits 2"
"$fs" path a b >/dev/null 2>&1; expect_rc 2 $? "path with two names exits 2"
"$fs" path ctlhq-agent >/dev/null 2>&1; expect_rc 2 $? "path does not accept an agent without --agents"
out="$("$fs" --agents path ctlhq-agent 2>&1)"; expect_eq "$root/agents/ctlhq-agent.md" "$out" "--agents path accepts an agent"

# 7. show, help, info, --json, --full, leading slash, agents.
out="$("$fs" show unslop 2>&1)"; expect_rc 0 $? "show unslop exits 0"
for k in 'name:        unslop' 'description: ' 'tools:       ctlhq-unslop$' 'invocation:  ' 'path:        /'; do
	expect_grep "^$k" "$out" "show prints '$k'"
done
expect_eq "$out" "$("$fs" help unslop 2>&1)" "help is an alias of show"
expect_eq "$out" "$("$fs" info unslop 2>&1)" "info is an alias of show"
expect_eq "$out" "$("$fs" show /unslop 2>&1)" "show accepts a leading slash"
full="$("$fs" --full show unslop 2>&1)"
expect_grep '^## ' "$full" "--full appends the SKILL.md body"
expect_no '^description: "' "$full" "--full drops the front matter"
expect_eq "unslop True True False" "$("$fs" --json show unslop | py '
import json, sys
d = json.load(sys.stdin)
print(d["name"], d["tools"] == ["ctlhq-unslop"], bool(d["description"]), "body" in d)')" "--json show: name, tools, description, no body"
expect_eq "True" "$("$fs" --json --full show unslop | py 'import json,sys; print(len(json.load(sys.stdin)["body"]) > 100)')" "--json --full show adds body"
out="$("$fs" show ctlhq-agent 2>&1)"; expect_rc 0 $? "show finds an agent without --agents"
expect_grep '^kind:        agent$' "$out" "show marks an agent"
expect_grep '^tools:       none$' "$out" "an agent has no tools"
"$fs" show nosuch-skill >/dev/null 2>&1; expect_rc 2 $? "show of an unknown name exits 2"
"$fs" show >/dev/null 2>&1; expect_rc 2 $? "show without a name exits 2"
"$fs" info a b >/dev/null 2>&1; expect_rc 2 $? "info with two names exits 2"

# 8. Usage errors.
"$fs" --bogus >/dev/null 2>&1; expect_rc 2 $? "unknown option exits 2"
err="$("$fs" bogus 2>&1 >/dev/null)"; rc=$?
expect_rc 2 "$rc" "unknown command exits 2"
expect_grep "unknown command 'bogus'" "$err" "unknown command is named on stderr"

# 9. Synthetic root: the tool resolves its root from its own path.
r="$tmp/root"
mkdir -p "$r/bin" "$r/skills" "$r/agents"
cp "$fs" "$r/bin/ctlhq-skills"
t="$r/bin/ctlhq-skills"
mk() { mkdir -p "$r/skills/$1"; printf '%s\n' "$2" > "$r/skills/$1/SKILL.md"; }
mk alpha $'---\nname: alpha\ndescription: "Alpha does the \\"first\\" thing."\n---\n# Alpha\n\nBody line.'
mk beta-folder $'---\nname: beta\ndescription: >\n  Beta folds\n  over two lines.\ndisable-model-invocation: true\n---\nbody'
mk nameless $'---\ndescription: \'No name here.\'\n---\nbody'
mk principle-zed $'---\nname: principle-zed\ndescription: A principle.\n---\nbody'
mk nofront $'# No front matter at all'
mk zulu $'---\nname: zulu\ndescription: Last by name.\n---\nbody'
mkdir -p "$r/skills/empty-folder" "$r/skills/.hidden"
printf -- '---\nname: hidden\n---\n' > "$r/skills/.hidden/SKILL.md"
mkdir -p "$r/skills/alpha/bin"; printf '#!/bin/sh\n' > "$r/skills/alpha/bin/alpha-tool"; chmod +x "$r/skills/alpha/bin/alpha-tool"
printf -- '---\nname: helper\ndescription: An agent.\n---\n' > "$r/agents/helper.md"

out="$("$t" 2>"$tmp/err")"; rc=$?; err="$(cat "$tmp/err")"
expect_rc 0 "$rc" "synthetic listing exits 0"
expect_eq "alpha beta nameless nofront zulu principle-zed" "$(printf '%s\n' "$out" | awk '{print $1}' | tr '\n' ' ' | sed 's/ $//')" "synthetic rows: sorted, nameless and nofront by folder, principle last, hidden skipped"
expect_grep '^skipped empty-folder: no SKILL.md yet$' "$err" "a folder without SKILL.md is noted on stderr"
expect_grep '^alpha +Alpha does the "first" thing\.$' "$out" "double-quoted description is unquoted with escapes"
expect_grep '^beta +Beta folds over two lines\.$' "$out" "folded description is joined"
expect_grep '^nameless +No name here\.$' "$out" "single-quoted description is unquoted"
expect_eq "False True" "$("$t" --json 2>/dev/null | py '
import json, sys
d = {r["name"]: r for r in json.load(sys.stdin)}
print(d["beta"]["invocable"], d["alpha"]["invocable"])')" "disable-model-invocation: true gives invocable false"
expect_eq "$r/skills/beta-folder/SKILL.md" "$("$t" path beta 2>/dev/null)" "path by front-matter name"
expect_eq "$r/skills/beta-folder/SKILL.md" "$("$t" path beta-folder 2>/dev/null)" "path by folder name"
out="$("$t" show alpha 2>/dev/null)"
expect_grep '^description: Alpha does the "first" thing\.$' "$out" "show prints the front-matter description"
expect_grep '^tools:       alpha-tool$' "$out" "show lists skills/<folder>/bin executables"
expect_grep '^invocation:  by the model or the user$' "$out" "invocable skill invocation line"
expect_eq "Body line." "$("$t" --full show alpha 2>/dev/null | tail -1)" "--full prints the body after the front matter"
out="$("$t" show beta 2>/dev/null)"
expect_grep '^invocation:  by the user only \(disable-model-invocation: true\)$' "$out" "user-only invocation line"
expect_grep '^tools:       none$' "$out" "no bin folder gives tools none"
chmod 000 "$r/skills/alpha/SKILL.md"
out="$("$t" 2>"$tmp/err")"; rc=$?; err="$(cat "$tmp/err")"
chmod 644 "$r/skills/alpha/SKILL.md"
expect_rc 0 "$rc" "an unreadable SKILL.md does not stop the listing"
expect_grep '^skipped .*alpha/SKILL.md' "$err" "an unreadable SKILL.md is noted on stderr"
expect_no '^alpha ' "$out" "an unreadable SKILL.md is left out"
e="$tmp/emptyroot"; mkdir -p "$e/bin"; cp "$fs" "$e/bin/ctlhq-skills"
out="$("$e/bin/ctlhq-skills" 2>"$tmp/err")"; rc=$?
expect_rc 0 "$rc" "a root without skills/ exits 0"
expect_eq "" "$out" "a root without skills/ lists nothing"
expect_grep '^no skills folder at ' "$(cat "$tmp/err")" "a root without skills/ is noted on stderr"
expect_eq "[]" "$("$e/bin/ctlhq-skills" --json 2>/dev/null)" "--json on an empty root prints []"

# 10. Positive controls: planted defects in a copy of the tool must break the checks above.
m="$tmp/mutant"; mkdir -p "$m/bin"; cp -R "$r/skills" "$r/agents" "$m/" 2>/dev/null
mutate() { # sed-expression: write a defective copy to $m/bin/ctlhq-skills and check the defect landed
	sed "$1" "$fs" > "$m/bin/ctlhq-skills"; chmod +x "$m/bin/ctlhq-skills"
	if cmp -s "$fs" "$m/bin/ctlhq-skills"; then bad "control: planted defect '$1' did not change the tool"; else ok; fi
}
mutate 's/return 0 if hits else 1/return 0/'
"$m/bin/ctlhq-skills" find zzqqxx-nomatch >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 0 ]; then ok; else bad "control: a find that always exits 0 is caught by the exit-1 check"; fi
mutate 's/r\["name"\].startswith("principle-"), //'
out="$("$m/bin/ctlhq-skills" 2>/dev/null | awk '{print $1}' | tr '\n' ' ' | sed 's/ $//')"
if [ "$out" = "alpha beta nameless nofront principle-zed zulu" ]; then ok; else bad "control: dropping the principle sort key is caught by the order check"; fi

echo "$pass checks passed"
[ "$fail" -eq 0 ] || { echo "$fail checks failed"; exit 1; }
