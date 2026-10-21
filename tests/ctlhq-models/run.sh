#!/usr/bin/env bash
# tests/ctlhq-models/run.sh: checks for bin/ctlhq-models (skills/ctlhq-setup/bin/ctlhq-models).
# Prints "N checks passed" and exits 1 when any check fails. Writes only to a temp folder: HOME
# points at a temp folder and CTLHQ_MODELS is unset, so the real ~/.ctlhq is never touched
# (section 13 checks that).
set -u
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
fm="$root/bin/ctlhq-models"
real="$root/skills/ctlhq-setup/bin/ctlhq-models"
example="$root/skills/ctlhq-setup/models.example.toml"
pass=0
fail=0
ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL: $1"; }
expect_rc() { if [ "$1" -eq "$2" ]; then ok; else bad "$3 (expected exit $1, got $2)"; fi; }
expect_eq() { if [ "$1" = "$2" ]; then ok; else bad "$3 (expected '$1', got '$2')"; fi; }
expect_grep() { if printf '%s\n' "$2" | grep -Eq -- "$1"; then ok; else bad "$3 (no line matches: $1)"; fi; }
expect_fgrep() { if printf '%s\n' "$2" | grep -Fq -- "$1"; then ok; else bad "$3 (no line contains: $1)"; fi; }
expect_nogrep() { if printf '%s\n' "$2" | grep -Eq -- "$1"; then bad "$3 (a line matches: $1)"; else ok; fi; }

real_cfg="$HOME/.ctlhq/models.toml"
real_sum_before="$(cksum "$real_cfg" 2>/dev/null || echo absent)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/ctlhq-models-test.XXXXXX")"
tmp="$(cd "$tmp" && pwd)" || exit 1  # TMPDIR may end in a slash
[ -n "$tmp" ] && [ -d "$tmp" ] || { echo "FAIL: no temp folder"; exit 1; }
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home"
mkdir -p "$HOME"
unset CTLHQ_MODELS
ROLES=21  # role lines in models.example.toml, budget not counted
CODEX_ROLES=2  # role lines in the [codex] table of models.example.toml
unset CTLHQ_HOST
# run <args...>: sets out, err, rc.
run() { out="$("$fm" "$@" 2>"$tmp/err")"; rc=$?; err="$(cat "$tmp/err")"; }
line_of() { grep -E "^$2 = " "$1"; }  # file role

# 1. --help, -h, no command, unknown command, --file errors.
run --help; expect_rc 0 "$rc" "--help exits 0"
expect_grep '^ctlhq-models: ' "$(printf '%s\n' "$out" | head -1)" "--help first line is 'ctlhq-models: ...'"
for c in show init get set unset budget validate prune fallback pick known-values; do expect_grep "^  ctlhq-models .*$c" "$out" "--help usage names $c"; done
for f in --budget --force --rewrite-names --allow --valid --not-family --file; do expect_fgrep "$f" "$out" "--help names $f"; done
run -h; expect_rc 0 "$rc" "-h exits 0"
run show --help; expect_rc 0 "$rc" "--help after a command exits 0"
run; expect_rc 2 "$rc" "no command exits 2"; expect_grep '^ctlhq-models: ' "$(printf '%s\n' "$err" | head -1)" "no command prints the help on stderr"
run bogus; expect_rc 2 "$rc" "unknown command exits 2"
run --file; expect_rc 2 "$rc" "--file without a path exits 2"

# 2. known-values.
run known-values; expect_rc 0 "$rc" "known-values exits 0"
expect_eq "Claude Code model names: sonnet, opus, haiku, fable" "$(printf '%s\n' "$out" | head -1)" "known-values lists the Claude Code names"
expect_fgrep 'aliases (the role runs on the parent chat model): inherit-parent, auto' "$out" "known-values lists the aliases"
expect_fgrep 'budgets: unlimited (effort max), large (effort xhigh), medium (effort high), small (effort medium)' "$out" "known-values lists the budgets"
run known-values extra; expect_rc 2 "$rc" "known-values with an argument exits 2"

# 3. show with no file: the defaults, from HOME/.ctlhq/models.toml by default.
run show; expect_rc 0 "$rc" "show with no file exits 0"
expect_eq "file: $HOME/.ctlhq/models.toml  (missing; showing the defaults. fix (operator, changes $HOME/.ctlhq/models.toml): ctlhq-models init --budget large)" "$(printf '%s\n' "$out" | head -1)" "show names the default path, says it is missing, and prints the fix"
expect_eq $((ROLES + 3)) "$(printf '%s\n' "$out" | grep -c '')" "show prints file line, header, budget, and $ROLES roles"
expect_grep '^budget +large \(xhigh\) \(default\) +large \(xhigh\)$' "$out" "budget row shows the default and its effort"
expect_grep '^swarm-workers +sonnet \(default\) +sonnet +inherit-parent \(no Codex value\)$' "$out" "role row shows current, default, codex"
[ ! -e "$HOME/.ctlhq" ] && ok || bad "show writes nothing"
run show extra; expect_rc 2 "$rc" "show with an argument exits 2"

# 4. init: default path, refuse to overwrite, --force, --budget forms.
run init; expect_rc 0 "$rc" "init exits 0"
expect_eq "wrote $HOME/.ctlhq/models.toml  (budget large, effort xhigh)" "$out" "init names the file, budget, effort"
expect_eq "" "$(diff "$example" "$HOME/.ctlhq/models.toml")" "init with the default budget writes the defaults file unchanged"
run init; expect_rc 1 "$rc" "init over an existing file exits 1"; expect_fgrep 'pass --force to overwrite it' "$err" "init refusal names --force"
run init --force --budget small; expect_rc 0 "$rc" "init --force --budget small exits 0"
expect_grep '^budget = "small"  # unlimited' "$(line_of "$HOME/.ctlhq/models.toml" budget)" "--budget small is written, comment kept"
run --file "$tmp/i.toml" init --budget=medium; expect_rc 0 "$rc" "init --budget=medium exits 0"
expect_grep '^budget = "medium"' "$(line_of "$tmp/i.toml" budget)" "--budget=medium is written"
run --file "$tmp/j.toml" init --budget tiny; expect_rc 2 "$rc" "init --budget tiny exits 2"
[ ! -e "$tmp/j.toml" ] && ok || bad "a bad --budget writes no file"
run --file "$tmp/j.toml" init --budget; expect_rc 2 "$rc" "init --budget without a label exits 2"
run --file "$tmp/j.toml" init --bogus; expect_rc 2 "$rc" "init with an unknown option exits 2"

# 5. --file, -f, --file=, CTLHQ_MODELS; --file wins over the environment.
f="$tmp/m.toml"
run -f "$f" init; expect_rc 0 "$rc" "-f PATH init exits 0"; [ -f "$f" ] && ok || bad "-f PATH writes there"
run --file="$tmp/eq.toml" init; [ -f "$tmp/eq.toml" ] && ok || bad "--file=PATH writes there"
out="$(CTLHQ_MODELS="$tmp/env.toml" "$fm" init 2>&1)"; [ -f "$tmp/env.toml" ] && ok || bad "CTLHQ_MODELS sets the file"
out="$(CTLHQ_MODELS="$tmp/env2.toml" "$fm" --file "$tmp/flag.toml" init 2>&1)"
[ -f "$tmp/flag.toml" ] && [ ! -e "$tmp/env2.toml" ] && ok || bad "--file wins over CTLHQ_MODELS"

# 6. get: default with a note, a set value, a list, budget, errors.
run --file "$tmp/none.toml" get swarm-workers; expect_rc 0 "$rc" "get on a missing file exits 0"
expect_eq "sonnet" "$out" "get on a missing file prints the default"
expect_fgrep 'swarm-workers is not in' "$err" "get on a missing file notes it on stderr"
run --file "$f" get best-of-n-runners; expect_eq "opus, sonnet" "$out" "get on a list role prints comma-separated"
run --file "$f" get budget; expect_eq "large" "$out" "get budget prints the label"
run --file "$f" get nosuch; expect_rc 2 "$rc" "get on an unknown role exits 2"; expect_fgrep "unknown role 'nosuch'. Roles: budget, feature-refactoring" "$err" "unknown role lists the roles"
run --file "$f" get; expect_rc 2 "$rc" "get without a role exits 2"
run --file "$f" get a b; expect_rc 2 "$rc" "get with two roles exits 2"
run --file "$tmp" get builders; expect_rc 1 "$rc" "get on a folder exits 1"; expect_fgrep 'cannot read' "$err" "read failure named"

# 7. set: single, list, comment kept, warnings, errors, creation, quoting.
run --file "$f" set swarm-workers haiku; expect_rc 0 "$rc" "set exits 0"
expect_eq "swarm-workers = haiku  ($f)" "$out" "set confirms the value and file"
expect_eq 'swarm-workers = "haiku"' "$(line_of "$f" swarm-workers)" "set writes the value"
run --file "$f" set builders sonnet
expect_eq 'builders = "sonnet"  # role map: builders run on Opus 5.5' "$(line_of "$f" builders)" "set keeps the line's comment"
run --file "$f" get swarm-workers; expect_eq haiku "$out" "get reads the set value"
run --file "$f" set best-of-n-runners " opus , gpt-5 ,, "; expect_rc 0 "$rc" "set on a list role exits 0"
expect_eq 'best-of-n-runners = ["opus", "gpt-5"]' "$(line_of "$f" best-of-n-runners)" "list values are trimmed and empty items dropped"
expect_fgrep "warning: best-of-n-runners = 'gpt-5' is not a Claude Code model name or alias" "$err" "an unknown name warns on stderr"
run --file "$f" set builders auto; expect_eq "" "$err" "an alias does not warn"
run --file "$f" set best-of-n-runners " , "; expect_rc 2 "$rc" "set a list role to nothing exits 2"
run --file "$f" set builders " "; expect_rc 2 "$rc" "set a single role to blank exits 2"
run --file "$f" set builders opus,sonnet; expect_rc 2 "$rc" "set a single role to a list exits 2"
run --file "$f" set nosuch opus; expect_rc 2 "$rc" "set an unknown role exits 2"
run --file "$f" set builders; expect_rc 2 "$rc" "set without a value exits 2"
expect_grep ' set <role> <value>$' "$err" "the fix line gives the usage of set and nothing more"
expect_nogrep 'list roles' "$err" "the fix line holds no words from the help description"
run --file "$f" set budget medium; expect_rc 0 "$rc" "set budget goes through budget"
expect_grep '^budget medium: effort high ' "$out" "set budget prints the effort"
run --file "$f" set budget tiny; expect_rc 2 "$rc" "set budget to an unknown label exits 2"
run --file "$tmp/new/dir/c.toml" set builders opus; expect_rc 0 "$rc" "set on a missing file in a missing folder exits 0"
expect_fgrep 'models file missing; creating it from the defaults' "$err" "set notes the creation on stderr"
expect_eq $((ROLES + 1 + CODEX_ROLES)) "$(grep -Ec '^[a-z-]+ = ' "$tmp/new/dir/c.toml")" "a created file holds every default line"
printf 'budget = "large"\n' > "$tmp/short.toml"
run --file "$tmp/short.toml" set builders opus
expect_eq 'budget = "large"|builders = "opus"  # role map: builders run on Opus 5.5' "$(tr '\n' '|' < "$tmp/short.toml" | sed 's/|$//')" "set adds a missing line after the last entry with the default comment"
: > "$tmp/plainfile"
run --file "$tmp/plainfile/sub/w.toml" set builders opus; expect_rc 1 "$rc" "set where the folder cannot be made exits 1"
expect_fgrep 'cannot write' "$err" "write failure named"
run --file "$tmp/plainfile/sub/w.toml" init; expect_rc 1 "$rc" "init where the folder cannot be made exits 1"
run --file "$tmp/q.toml" set builders 'a"b\c'
run --file "$tmp/q.toml" get builders; expect_eq 'a"b\c' "$out" "quotes and backslashes round-trip through set and get"
printf "builders = 'single'\n" > "$tmp/sq.toml"
run --file "$tmp/sq.toml" get builders; expect_eq single "$out" "single-quoted values are read"
# A newline in a value would be written raw and make the file unreadable, so set refuses it.
run --file "$tmp/nl.toml" set builders "$(printf 'a\nb')"; expect_rc 2 "$rc" "set with a newline in the value exits 2"
expect_fgrep 'cannot hold a newline' "$err" "the newline refusal is named"
expect_eq absent "$([ -e "$tmp/nl.toml" ] && echo present || echo absent)" "a refused newline value writes no file"
run --file "$tmp/nl.toml" set best-of-n-runners "opus,$(printf 'a\rb')"; expect_rc 2 "$rc" "set with a carriage return in a list item exits 2"

# 8. unset.
run --file "$f" unset swarm-workers; expect_rc 0 "$rc" "unset exits 0"
expect_eq "removed swarm-workers from $f; the default applies: sonnet" "$out" "unset names the default"
expect_eq "" "$(line_of "$f" swarm-workers)" "unset removes the line"
run --file "$f" unset swarm-workers; expect_rc 0 "$rc" "unset of an absent line exits 0"; expect_fgrep 'the default applies already (sonnet)' "$err" "absent line noted on stderr"
run --file "$tmp/none.toml" unset builders; expect_rc 0 "$rc" "unset on a missing file exits 0"; [ ! -e "$tmp/none.toml" ] && ok || bad "unset on a missing file creates nothing"
run --file "$f" unset budget; expect_rc 0 "$rc" "unset budget exits 0"; expect_eq "" "$(line_of "$f" budget)" "unset budget removes the budget line"
run --file "$f" get budget; expect_eq large "$out" "after unset budget the default budget applies"
run --file "$f" unset nosuch; expect_rc 2 "$rc" "unset an unknown role exits 2"
run --file "$f" unset; expect_rc 2 "$rc" "unset without a role exits 2"

# 9. budget and --rewrite-names.
b="$tmp/b.toml"
"$fm" --file "$b" init >/dev/null 2>&1
"$fm" --file "$b" set judgment-and-prose claude-big-xhigh >/dev/null 2>&1
"$fm" --file "$b" set swarm-workers acme-7-xhigh-fast >/dev/null 2>&1
"$fm" --file "$b" set builders acme-7-xhigh >/dev/null 2>&1
"$fm" --file "$b" set best-of-n-runners gpt-5-high,opus,auto >/dev/null 2>&1
printf 'retired-role = "x-high"\n' >> "$b"
cp "$b" "$tmp/b-before.toml"
run --file "$b" budget unlimited; expect_rc 0 "$rc" "budget unlimited exits 0"
expect_eq "budget unlimited: effort max  ($b)" "$out" "budget prints the effort"
expect_eq 1 "$(diff "$tmp/b-before.toml" "$b" | grep -c '^>')" "budget without --rewrite-names changes only the budget line"
run --file "$b" budget small --rewrite-names; expect_rc 0 "$rc" "budget --rewrite-names exits 0"
expect_fgrep 'judgment-and-prose: claude-big-xhigh -> claude-big-medium' "$out" "the last token is rewritten"
expect_fgrep 'swarm-workers: acme-7-xhigh-fast -> acme-7-medium-fast' "$out" "the token before a trailing fast is rewritten"
expect_fgrep 'best-of-n-runners: gpt-5-high -> gpt-5-medium, opus (no effort token; left alone), auto (alias; unchanged)' "$out" "list entries: rewritten, left alone, alias unchanged"
expect_eq "rewrote 4 role line(s) to effort medium" "$(printf '%s\n' "$out" | tail -1)" "rewrite count"
expect_eq 'best-of-n-runners = ["gpt-5-medium", "opus", "auto"]' "$(line_of "$b" best-of-n-runners)" "the list line is rewritten in place"
expect_eq 'builders = "acme-7-medium"  # role map: builders run on Opus 5.5' "$(line_of "$b" builders)" "a rewritten line keeps its comment"
expect_eq 'retired-role = "x-high"' "$(line_of "$b" retired-role)" "a retired role line is not rewritten"
expect_nogrep '^retired-role' "$out" "a retired role is not reported"
run --file "$b" budget small --rewrite-names
expect_fgrep 'judgment-and-prose: claude-big-medium (already medium)' "$out" "a name already at the effort is reported as already"
expect_eq "rewrote 0 role line(s) to effort medium" "$(printf '%s\n' "$out" | tail -1)" "second rewrite changes nothing"
run --file "$b" budget huge; expect_rc 2 "$rc" "budget with an unknown label exits 2"; expect_fgrep 'budget must be one of: unlimited, large, medium, small' "$err" "budget labels listed"
run --file "$b" budget; expect_rc 2 "$rc" "budget without a label exits 2"

# 10. validate and prune.
run --file "$tmp/i.toml" validate; expect_rc 0 "$rc" "validate on a fresh init exits 0"
expect_eq "ok: $tmp/i.toml  $ROLES roles set, budget medium (high)" "$out" "validate ok line"
run --file "$tmp/i.toml" validate --allow sonnet,opus,haiku,fable; expect_rc 0 "$rc" "validate --allow with every used name exits 0"
expect_fgrep ", every real value in --allow (4 names)" "$out" "validate --allow counts the names"
run --file "$tmp/i.toml" validate --allow=opus; expect_rc 1 "$rc" "validate --allow=opus exits 1"
expect_fgrep "problem: line 6: feature-refactoring = 'sonnet' is not in --allow" "$out" "a value outside --allow is a problem"
expect_nogrep "builders-limit-fallback = 'inherit-parent' is not in --allow" "$out" "aliases always pass --allow"
run --file "$tmp/i.toml" validate --allow=; expect_rc 2 "$rc" "validate --allow with no names exits 2"
run --file "$tmp/i.toml" validate --allow; expect_rc 2 "$rc" "validate --allow without a value exits 2"
run --file "$tmp/i.toml" validate extra; expect_rc 2 "$rc" "validate with an argument exits 2"
run --file "$tmp/none.toml" validate; expect_rc 1 "$rc" "validate on a missing file exits 1"; expect_fgrep 'models file missing' "$out" "missing file named"
: > "$tmp/empty.toml"
run --file "$tmp/empty.toml" validate; expect_rc 0 "$rc" "validate on an empty file exits 0"
expect_fgrep "budget missing (large applies), $ROLES role line(s) missing (defaults apply)" "$out" "empty file: defaults apply"
v="$tmp/v.toml"
cat > "$v" <<'TOML'
builders = 'opus'
budget = "tiny"
foo = "y"
swarm-workers = ["sonnet"]
best-of-n-runners = "opus"
builders = ""
bad line
hillclimb = "x" trailing
how-explorer = "unterminated
TOML
cp "$v" "$tmp/v-before.toml"
run --file "$v" validate; expect_rc 1 "$rc" "validate on a bad file exits 1"
expect_fgrep 'problem: line 2: budget must be one of unlimited, large, medium, small, got '"'tiny'" "$out" "bad budget"
expect_fgrep 'problem: line 3: retired role foo' "$out" "retired role"
expect_fgrep 'problem: line 4: swarm-workers takes a single value, got a list' "$out" "list in a single role"
expect_fgrep 'problem: line 5: best-of-n-runners takes a list, got a single value' "$out" "single value in a list role"
expect_fgrep 'problem: line 6: builders appears more than once' "$out" "duplicate role"
expect_fgrep 'problem: line 6: builders has an empty value' "$out" "empty value"
expect_fgrep 'problem: line 7: expected key = value' "$out" "unparseable line"
expect_fgrep "problem: line 8: unexpected text after the value: 'trailing'" "$out" "text after the value"
expect_fgrep 'problem: line 9: unterminated string' "$out" "unterminated string"
expect_eq "" "$(diff "$tmp/v-before.toml" "$v")" "validate is read-only"
run --file "$v" get builders; expect_rc 1 "$rc" "get on an unparseable file exits 1"
run --file "$v" show; expect_rc 1 "$rc" "show on an unparseable file exits 1"
p="$tmp/p.toml"
printf 'builders = "opus"\nold-role = "x"  # gone\nswarm-workers = "sonnet"\n' > "$p"
run --file "$p" show; expect_grep '^retired role .*line 2: old-role = x$' "$out" "show lists a retired role line"
run --file "$p" prune; expect_rc 0 "$rc" "prune exits 0"
expect_eq "retired role dropped: line 2: old-role = \"x\"  # gone" "$(printf '%s\n' "$out" | head -1)" "prune prints the dropped line"
expect_eq 'builders = "opus"|swarm-workers = "sonnet"' "$(tr '\n' '|' < "$p" | sed 's/|$//')" "prune keeps the other lines in order"
run --file "$p" prune; expect_rc 0 "$rc" "prune with nothing to prune exits 0"; expect_fgrep 'nothing to prune' "$out" "nothing to prune named"
run --file "$tmp/none.toml" prune; expect_rc 1 "$rc" "prune on a missing file exits 1"
run --file "$p" prune extra; expect_rc 2 "$rc" "prune with an argument exits 2"

# 11. fallback.
d="$tmp/none.toml"
run --file "$d" fallback swarm-workers claude-sonnet-9; expect_rc 0 "$rc" "fallback by family exits 0"
expect_eq "sonnet" "$(printf '%s\n' "$out" | head -1)" "fallback prints the starting value first"
expect_fgrep 'rule: claude-sonnet-9 is family claude by its vendor prefix; starting value 1 of swarm-workers shares the family' "$out" "fallback rule names the family and position"
run --file "$d" fallback builders sonnet; expect_rc 0 "$rc" "fallback builders sonnet exits 0"; expect_eq opus "$(printf '%s\n' "$out" | head -1)" "sonnet counts as claude family"
run --file "$d" fallback builders opus; expect_rc 1 "$rc" "fallback when the only match is the rejected model exits 1"
expect_fgrep 'every starting value of that family is the rejected model itself' "$out" "only-rejected rule named"
run --file "$d" fallback swarm-workers gpt-5; expect_rc 1 "$rc" "fallback with no family match exits 1"
expect_eq "sonnet|rule: no family match: gpt-5 is family gpt by its vendor prefix; printing the first starting value of swarm-workers|next: sonnet matches no family rule; if the host rejects it too, rerun: ctlhq-models --file $d fallback swarm-workers gpt-5 --valid <the host's model names from its error message, comma-separated>" "$(printf '%s\n' "$out" | tr '\n' '|' | sed 's/|$//')" "no family match prints the first value, says so, and gives the --valid rerun"
run --file "$d" fallback judgment-and-prose claude-big-xhigh --valid claude-sonnet-4,claude-big-high,gpt-5; expect_rc 0 "$rc" "fallback --valid exits 0"
expect_eq "claude-big-high" "$(printf '%s\n' "$out" | head -1)" "--valid picks the closest name of the family"
run --file "$d" fallback swarm-workers claude-sonnet-9 --valid=gpt-5; expect_rc 1 "$rc" "--valid without the family exits 1"
expect_fgrep 'or not in --valid' "$out" "--valid exclusion named"
run --file "$d" fallback swarm-workers auto; expect_rc 2 "$rc" "an alias as the rejected model exits 2"
run --file "$d" fallback budget opus; expect_rc 2 "$rc" "fallback on budget exits 2"
run --file "$d" fallback nosuch opus; expect_rc 2 "$rc" "fallback on an unknown role exits 2"
run --file "$d" fallback swarm-workers; expect_rc 2 "$rc" "fallback without a model exits 2"
run --file "$d" fallback swarm-workers opus --valid; expect_rc 2 "$rc" "--valid without a value exits 2"

# 12. pick.
run --file "$d" pick best-of-n-runners --not-family opus; expect_rc 1 "$rc" "pick with only claude entries exits 1"
expect_eq "opus|rule: every entry of best-of-n-runners (opus, sonnet) is family claude or an alias; printing the first entry|next: use opus and say \"same-family review (claude)\" in the reply|next (operator, changes $d): add a model of another family: ctlhq-models --file $d set best-of-n-runners opus,sonnet,<model of another family>" "$(printf '%s\n' "$out" | tr '\n' '|' | sed 's/|$//')" "pick prints the first entry, says so, and gives the next step"
g="$tmp/g.toml"; "$fm" --file "$g" set best-of-n-runners opus,gpt-5-high >/dev/null 2>&1
run --file "$g" pick best-of-n-runners --not-family claude-big; expect_rc 0 "$rc" "pick with another family exits 0"
expect_eq "gpt-5-high|rule: entry 2 of best-of-n-runners is family gpt, which differs from claude-big (claude)" "$(printf '%s\n' "$out" | tr '\n' '|' | sed 's/|$//')" "pick names the entry and both families"
run --file "$g" pick best-of-n-runners --not-family=gpt-5; expect_rc 0 "$rc" "--not-family=MODEL form"; expect_eq opus "$(printf '%s\n' "$out" | head -1)" "pick against gpt returns the claude entry"
run --file "$d" pick best-of-n-runners --not-family auto; expect_rc 1 "$rc" "pick against an alias exits 1"
expect_fgrep 'auto is an alias, so its family is unknown' "$out" "alias rule named"
a="$tmp/a.toml"; "$fm" --file "$a" set best-of-n-runners auto,inherit-parent,opus >/dev/null 2>&1
run --file "$a" pick best-of-n-runners --not-family gpt-5; expect_eq opus "$(printf '%s\n' "$out" | head -1)" "alias entries never qualify"
run --file "$d" pick best-of-n-runners; expect_rc 2 "$rc" "pick without --not-family exits 2"
run --file "$d" pick best-of-n-runners --not-family; expect_rc 2 "$rc" "--not-family without a value exits 2"
run --file "$d" pick budget --not-family opus; expect_rc 2 "$rc" "pick on budget exits 2"
run --file "$d" pick --not-family opus; expect_rc 2 "$rc" "pick without a role exits 2"

# 13. Missing defaults file; the real ~/.ctlhq is untouched; an empty --file value.
mkdir -p "$tmp/nodefaults/bin"; cp "$real" "$tmp/nodefaults/bin/ctlhq-models"
out="$("$tmp/nodefaults/bin/ctlhq-models" --file "$tmp/x.toml" show 2>&1)"; expect_rc 1 $? "a missing models.example.toml exits 1"
expect_fgrep 'cannot read the defaults file' "$out" "missing defaults file named"
out="$("$tmp/nodefaults/bin/ctlhq-models" known-values 2>&1)"; expect_rc 0 $? "known-values does not need the defaults file"
expect_eq "$real_sum_before" "$(cksum "$real_cfg" 2>/dev/null || echo absent)" "the real ~/.ctlhq/models.toml is unchanged"
# An empty --file value is a usage error; it must not fall back to CTLHQ_MODELS or
# ~/.ctlhq/models.toml. HOME is the temp folder here, so a wrong write would stay in it.
rm -rf "$HOME/.ctlhq"
for form in "--file=" "--file ''" "-f ''"; do
	eval "\"\$fm\" $form init" >/dev/null 2>"$tmp/e.err"; e_rc=$?
	expect_rc 2 "$e_rc" "$form (empty) init exits 2"
	expect_fgrep '--file needs a path' "$(cat "$tmp/e.err")" "$form (empty) is named as a usage error"
	expect_eq absent "$([ -e "$HOME/.ctlhq/models.toml" ] && echo present || echo absent)" "$form (empty) writes nothing under HOME/.ctlhq"
done
CTLHQ_MODELS="$tmp/env-empty.toml" "$fm" --file= set builders opus >/dev/null 2>&1; e_rc=$?
expect_rc 2 "$e_rc" "--file= with CTLHQ_MODELS set exits 2"
expect_eq absent "$([ -e "$tmp/env-empty.toml" ] && echo present || echo absent)" "--file= does not fall back to CTLHQ_MODELS"

# 14. Positive control: a copy without the duplicate-role check must miss section 10's duplicate.
mkdir -p "$tmp/mut/bin"; cp "$example" "$tmp/mut/models.example.toml"
sed 's/^        if key in first_line:$/        if False:/' "$real" > "$tmp/mut/bin/ctlhq-models"
chmod +x "$tmp/mut/bin/ctlhq-models"
if cmp -s "$real" "$tmp/mut/bin/ctlhq-models"; then bad "positive control: the planted defect did not change the tool"; else ok; fi
out="$("$tmp/mut/bin/ctlhq-models" --file "$v" validate 2>/dev/null)"
expect_fgrep 'problem: line 3: retired role foo' "$out" "positive control: the mutant runs and still reports the other problems"
expect_nogrep 'appears more than once' "$out" "positive control: the mutant misses the duplicate, so section 10 would catch it"

# 15. Every error and finding says what, why, and how (docs/principles.md 4.1): one planted case per path.
e15="$tmp/e15"; mkdir -p "$e15"; x="$e15/x.toml"; "$fm" --file "$x" init >/dev/null 2>&1
run --file; expect_fgrep 'fix: ctlhq-models --file <path to models.toml> <command>' "$err" "--file without a path: fix line"
run --file= show; expect_fgrep 'never falls back to CTLHQ_MODELS' "$err" "empty --file: why"; expect_fgrep 'fix: pass a real path, or drop --file' "$err" "empty --file: fix line"
run shw; expect_fgrep 'fix: did you mean ctlhq-models show?' "$err" "unknown command: near match"
run --file "$x" get; expect_fgrep "fix: ctlhq-models --file $x get <role>" "$err" "wrong argument count: usage line with the real --file"
run --file "$x" get best-of-n-runner; expect_fgrep 'the roles come from' "$err" "unknown role: why"; expect_fgrep 'fix: did you mean best-of-n-runners?' "$err" "unknown role: near match"
run --file "$x" init; expect_fgrep 'the role choices in it would be lost' "$err" "init over a file: why"; expect_fgrep "fix (operator, changes $x): change one role with ctlhq-models --file $x set <role> <value>, or start over with ctlhq-models --file $x init --force" "$err" "init over a file: fix line"
run --file "$e15/n.toml" init --budget; expect_fgrep "fix (operator, changes $e15/n.toml): ctlhq-models --file $e15/n.toml init --budget large" "$err" "init --budget without a label: fix line"
run --file "$e15/n.toml" init --budget tiny; expect_fgrep "got 'tiny'; each label maps to an effort level: unlimited max" "$err" "init bad budget: why"; expect_fgrep 'init --budget large' "$err" "init bad budget: fix line"
run --file "$e15/n.toml" init --bogus; expect_fgrep 'fix (operator, changes '"$e15"'/n.toml): ctlhq-models --file '"$e15"'/n.toml init [--budget unlimited|large|medium|small] [--force]' "$err" "init unknown option: usage line"
run --file "$x" budget huge; expect_fgrep "fix (operator, changes $x): ctlhq-models --file $x budget large" "$err" "bad budget label: fix line"
run --file "$x" set best-of-n-runners " , "; expect_fgrep 'runs one subagent per entry' "$err" "empty list: why"; expect_fgrep "fix (operator, changes $x): ctlhq-models --file $x set best-of-n-runners opus,sonnet" "$err" "empty list: fix with the default values"
run --file "$x" set builders " "; expect_fgrep "fix (operator, changes $x): ctlhq-models --file $x set builders opus, or ctlhq-models --file $x unset builders" "$err" "blank single value: fix line"
run --file "$x" set builders sonnet,opus; expect_fgrep "fix (operator, changes $x): ctlhq-models --file $x set builders sonnet" "$err" "list in a single role: fix keeps the first item"
run --file "$x" set builders "$(printf 'a\nb')"; expect_fgrep 'the value would break the file' "$err" "control character: why"; expect_fgrep "fix (operator, changes $x): retype the value as one plain line" "$err" "control character: fix line"
run --file "$x" set builders gpt-5; expect_fgrep "Check it against the host's names: ctlhq-models --file $x validate --allow" "$err" "unknown model name warning: how to check it"
"$fm" --file "$x" set builders opus >/dev/null 2>&1
run --file "$e15" get builders; expect_fgrep 'fix: point at a readable models file' "$err" "unreadable file: fix line"
printf 'builders = "opus"\nbad line\n' > "$e15/bad.toml"
run --file "$e15/bad.toml" get builders; expect_fgrep 'no role in the file can be read' "$err" "unparseable file: why"; expect_fgrep "fix (operator, changes $e15/bad.toml): rewrite line 2 of $e15/bad.toml as role = \"model\" or role = [\"a\", \"b\"], or delete it" "$err" "unparseable file: fix names the line"
run --file "$tmp/plainfile/sub/w.toml" set builders opus; expect_fgrep 'nothing was saved' "$err" "unwritable file: why"; expect_fgrep "fix: make $tmp/plainfile/sub writable" "$err" "unwritable file: fix line"
out="$("$tmp/nodefaults/bin/ctlhq-models" --file "$x" show 2>&1)"; expect_fgrep 'fix: restore it from the ctlhq repository: skills/ctlhq-setup/models.example.toml' "$out" "missing defaults file: fix line"
mkdir -p "$e15/bd/bin"; cp "$real" "$e15/bd/bin/ctlhq-models"; printf 'budget = "large"\nbuilders = opus\n' > "$e15/bd/models.example.toml"
out="$("$e15/bd/bin/ctlhq-models" --file "$x" show 2>&1)"; expect_grep 'fix: rewrite line 2 of .*/e15/bd/models\.example\.toml as role = ' "$out" "unparseable defaults file: fix names the line"
printf 'builders = "opus"\n' > "$e15/bd/models.example.toml"
out="$("$e15/bd/bin/ctlhq-models" --file "$x" show 2>&1)"; expect_fgrep 'fix: add the line budget = "large"' "$out" "defaults without a budget line: fix line"
run --file "$e15/none.toml" validate; expect_fgrep 'with none, every role uses its default' "$out" "validate with no file: why"; expect_fgrep "fix (operator, changes $e15/none.toml): ctlhq-models --file $e15/none.toml init --budget large" "$out" "validate with no file: fix line"
run --file "$e15/none.toml" prune; expect_fgrep "fix (operator, changes $e15/none.toml): ctlhq-models --file $e15/none.toml init --budget large" "$out" "prune with no file: fix line"
run --file "$e15" validate; expect_rc 1 "$rc" "validate on a folder exits 1"; expect_fgrep 'fix: point at a readable models file' "$out" "validate on a folder: fix line"
cp "$tmp/v-before.toml" "$e15/v.toml"; vv="$e15/v.toml"
run --file "$vv" validate
expect_fgrep "fix (operator, changes $vv): ctlhq-models --file $vv prune" "$out" "retired role: fix line"
expect_fgrep 'problem: line 6: builders appears more than once (only line 1 is read)' "$out" "duplicate role: why"; expect_fgrep "fix (operator, changes $vv): delete line 6 or line 1 of $vv" "$out" "duplicate role: fix line"
expect_fgrep "fix (operator, changes $vv): ctlhq-models --file $vv budget large" "$out" "bad budget line: fix line"
expect_fgrep "fix (operator, changes $vv): ctlhq-models --file $vv set swarm-workers sonnet" "$out" "list in a single role: fix line"
expect_fgrep "fix (operator, changes $vv): ctlhq-models --file $vv set best-of-n-runners opus  (it writes a list" "$out" "single value in a list role: fix line"
expect_fgrep "fix (operator, changes $vv): ctlhq-models --file $vv unset builders  (the default opus applies)" "$out" "empty value: fix line"
expect_fgrep "fix (operator, changes $vv): rewrite line 7 of $vv as role =" "$out" "unparseable line: fix line"
expect_fgrep "next: once the operator has applied each fix, check again: ctlhq-models --file $vv validate" "$(printf '%s\n' "$out" | tail -1)" "validate ends with a next step"
run --file "$tmp/i.toml" validate --allow=opus
expect_fgrep "is not in --allow (the host's model names), so a spawn on it fails" "$out" "--allow problem: why"
expect_fgrep "fix (operator, changes $tmp/i.toml): ctlhq-models --file $tmp/i.toml set feature-refactoring opus  (sonnet -> opus: closest allowed name of family claude. Allowed: opus; inherit-parent and auto always pass)" "$out" "--allow problem: fix sets the closest allowed name"
expect_fgrep "fix (operator, changes $tmp/i.toml): ctlhq-models --file $tmp/i.toml set best-of-n-runners opus,opus" "$out" "--allow problem in a list role: fix keeps the list"
expect_fgrep "next: once the operator has applied each fix, check again: ctlhq-models --file $tmp/i.toml validate --allow opus" "$(printf '%s\n' "$out" | tail -1)" "validate --allow ends with a next step"
run --file "$tmp/i.toml" validate --allow=gpt-5; expect_fgrep 'no allowed name of family claude; first allowed name' "$out" "--allow with no same-family name says so"
run --file "$x" fallback swarm-workers auto; expect_fgrep 'cannot reject it' "$err" "alias as the rejected model: why"; expect_fgrep "fix: omit the subagent tool's model parameter" "$err" "alias as the rejected model: fix line"
run --file "$x" fallback budget opus; expect_fgrep 'fix: pass a model role, for example: ctlhq-models --file '"$x"' fallback swarm-workers <rejected-model>' "$err" "fallback on budget: fix line"
run --file "$x" pick budget --not-family opus; expect_fgrep 'pick swarm-workers --not-family <model>' "$err" "pick on budget: fix line"
run --file "$e15/none.toml" fallback swarm-workers claude-sonnet-9; expect_fgrep "next: if the host rejects sonnet too, rerun: ctlhq-models --file $e15/none.toml fallback swarm-workers claude-sonnet-9 --valid <the host's model names" "$out" "fallback: next step for a second rejection"
run --file "$e15/none.toml" fallback builders opus; expect_fgrep 'next: opus matches no family rule; if the host rejects it too, rerun: ' "$out" "fallback with only the rejected model: next step"
run --file "$e15/none.toml" fallback swarm-workers claude-sonnet-9 --valid=gpt-5; expect_fgrep 'next: no --valid name fits the rule; say so, and report the model-name issue to the operator' "$out" "fallback with --valid and no fit: plain next step reports to the operator"
run --file "$e15/none.toml" fallback judgment-and-prose claude-big-xhigh --valid claude-big-high; expect_nogrep '^next:' "$out" "fallback with a --valid answer has no next line"
run --file "$e15/none.toml" pick best-of-n-runners --not-family auto; expect_fgrep 'next: rerun with the parent' "$out" "pick against an alias: next step"
run --file "$x" pick best-of-n-runners; expect_fgrep "fix: ctlhq-models --file $x pick <role> --not-family <the model to differ from>" "$err" "pick without --not-family: fix line"
run --file "$x" pick best-of-n-runners --not-family; expect_fgrep 'it was the last argument' "$err" "--not-family without a value: why"; expect_fgrep '--not-family <the model to differ from>' "$err" "--not-family without a value: fix line"
run --file "$x" fallback swarm-workers opus --valid=,; expect_fgrep 'fix: ctlhq-models --file '"$x"' fallback <role> <rejected-model> --valid' "$err" "--valid with no names: fix line"
run --file "$x" validate --allow=,; expect_fgrep 'validate --allow <the host' "$err" "--allow with no names: fix line"
run --file "$e15/none.toml" get swarm-workers; expect_fgrep "note: swarm-workers is not in $e15/none.toml (no such file); printing the default, its starting value in $example" "$err" "get default: note names the file and models.example.toml"
"$fm" --file "$x" set builders auto >/dev/null 2>&1; "$fm" --file "$x" set best-of-n-runners inherit-parent,opus >/dev/null 2>&1
run --file "$x" get builders; expect_eq auto "$out" "get on an alias prints the alias"; expect_fgrep "note: auto runs this entry on the parent chat model; omit the subagent tool's model parameter for it" "$err" "get on an alias: note line"
run --file "$x" get best-of-n-runners; expect_fgrep 'note: inherit-parent runs this entry on the parent chat model' "$err" "get on a list with an alias: note line"
run --file "$x" get swarm-workers; expect_nogrep '^note:' "$err" "get on a set real value prints no note"
run --file "$p" show >/dev/null; printf 'gone-role = "x"\n' >> "$p"; run --file "$p" show; expect_fgrep "so no skill reads it; fix (operator, changes $p): ctlhq-models --file $p prune" "$out" "show: retired role fix line"
# 16. A fix or next line that changes the models file is marked as the operator's action; read-only steps stay plain.
run --file "$e15/none.toml" fallback swarm-workers claude-sonnet-9 --valid=gpt-5
expect_fgrep "next (operator, changes $e15/none.toml): set the role to a --valid name: ctlhq-models --file $e15/none.toml set swarm-workers" "$out" "fallback --valid set suggestion carries the operator marker"
run --file "$e15/none.toml" pick best-of-n-cross-judge-pool --not-family opus
expect_fgrep "next (operator, changes $e15/none.toml): add a model of another family: ctlhq-models --file $e15/none.toml set best-of-n-cross-judge-pool" "$out" "pick set suggestion carries the operator marker"
expect_fgrep 'next: use opus and say "same-family review (claude)" in the reply' "$out" "pick agent step stays plain"
run --file "$e15/none.toml" fallback swarm-workers claude-sonnet-9; expect_grep '^next: if the host rejects' "$out" "fallback --valid rerun (read-only) stays plain"
run --file "$tmp/i.toml" validate --allow=opus; expect_grep '^next: once the operator' "$out" "validate rerun (read-only) stays plain"
run --file "$x" set; expect_fgrep "fix (operator, changes $x): ctlhq-models --file $x set <role> <value>" "$err" "set usage line carries the operator marker"
run --file "$x" get; expect_grep '^fix: ctlhq-models' "$err" "get usage line stays plain"
run sett; expect_fgrep 'fix (operator, changes ' "$err" "near match to a writer command carries the operator marker"
HOME="$HOME" run show; expect_fgrep "fix (operator, changes $HOME/.ctlhq/models.toml)" "$out" "the marker names the default models file"
# Every set, unset, init, budget, or prune suggestion in any output above carries the marker.
all_out="$(for c in "validate" "validate --allow=opus" "pick best-of-n-runners --not-family opus" "fallback swarm-workers claude-sonnet-9 --valid=gpt-5" "set best-of-n-runners ," "budget huge" "init"; do eval "\"\$fm\" --file \"\$tmp/i.toml\" $c" 2>&1; eval "\"\$fm\" --file \"\$vv\" $c" 2>&1; done)"
expect_nogrep '^(fix|next): .*ctlhq-models( --file [^ ]+)? (set|unset|init|budget|prune)( |$)' "$all_out" "no plain fix or next line suggests a command that changes the models file"
run --help; expect_fgrep 'An agent never runs a marked line during a task' "$out" "--help says marked lines are the operator's"
run --help; for w in 'fix:' 'next:' 'note:' '-f PATH' 'init finds an existing file' 'a wrong argument count'; do expect_fgrep "$w" "$out" "--help covers $w"; done

# 17. The Codex host: --host, CTLHQ_HOST, the [codex] table.
c17="$tmp/c17"; mkdir -p "$c17"; cn="$c17/none.toml"; claude_name='^(sonnet|opus|haiku|fable)$'
run --help; for w in '--host claude|codex' '--host=codex' 'CTLHQ_HOST' '[codex]'; do expect_fgrep "$w" "$out" "--help covers $w"; done
expect_fgrep '[codex]' "$(sed -n '/^\[codex\]$/,$p' "$example" | head -1)" "models.example.toml has a [codex] table"
expect_eq 'planners-and-reviewers = "gpt-6-astra"  # role map:' "$(sed -n '/^\[codex\]$/,$p' "$example" | grep -o '^planners-and-reviewers = .*# role map:')" "the [codex] table holds gpt-6-astra with a role-map comment"
expect_eq 'planners-and-reviewers-limit-fallback = "gpt-6.1-sol"  # role map:' "$(sed -n '/^\[codex\]$/,$p' "$example" | grep -o '^planners-and-reviewers-limit-fallback = .*# role map:')" "the [codex] table holds gpt-6.1-sol with a role-map comment"
expect_eq '[codex]' "$(grep -E '^\[' "$example")" "[codex] is the only table header"
# get: host choice and its sources.
run --file "$cn" get planners-and-reviewers; expect_eq fable "$out" "host claude still prints the top-level value"
run --file "$cn" get planners-and-reviewers-limit-fallback; expect_eq opus "$out" "host claude limit fallback still prints opus"
run --file "$cn" --host codex get planners-and-reviewers; expect_rc 0 "$rc" "get --host codex exits 0"; expect_eq gpt-6-astra "$out" "--host codex prints the [codex] default"
expect_fgrep 'is not in the [codex] table of' "$err" "the [codex] default is noted on stderr"
run --file "$cn" --host=codex get planners-and-reviewers-limit-fallback; expect_eq gpt-6.1-sol "$out" "--host=codex prints the [codex] limit fallback"
out="$(CTLHQ_HOST=codex "$fm" --file "$cn" get planners-and-reviewers 2>/dev/null)"; expect_eq gpt-6-astra "$out" "CTLHQ_HOST=codex picks the codex host"
out="$(CTLHQ_HOST=codex "$fm" --file "$cn" --host claude get planners-and-reviewers 2>/dev/null)"; expect_eq fable "$out" "--host claude wins over CTLHQ_HOST=codex"
out="$(CTLHQ_HOST= "$fm" --file "$cn" get planners-and-reviewers 2>/dev/null)"; expect_eq fable "$out" "an empty CTLHQ_HOST means claude"
run --file "$cn" --host codex get builders; expect_rc 0 "$rc" "a role with no Codex value exits 0"; expect_eq inherit-parent "$out" "a role with no Codex value prints inherit-parent"
expect_fgrep "note: no Codex value for builders; runs on the session's model" "$err" "no Codex value is noted on stderr"
run --file "$cn" --host codex get budget; expect_eq large "$out" "the budget line is shared by both hosts"
for r in $(sed -n '/^\[codex\]/q;s/^\([a-z-]*\) = .*/\1/p' "$example"); do
	run --file "$cn" --host codex get "$r"
	expect_nogrep "$claude_name" "$(printf '%s\n' "$out" | tr ',' '\n' | tr -d ' ')" "get --host codex $r prints no Claude name"
done
run --file "$cn" --host gemini get builders; expect_rc 2 "$rc" "--host with an unknown host exits 2"; expect_fgrep 'fix: ctlhq-models --host codex <command>' "$err" "bad --host: fix line"
run --file "$cn" get builders --host; expect_rc 2 "$rc" "--host without a value exits 2"
run --file "$cn" --host= get builders; expect_rc 2 "$rc" "--host= with no value exits 2"
out="$(CTLHQ_HOST=other "$fm" --file "$cn" get builders 2>&1)"; expect_rc 2 $? "a bad CTLHQ_HOST exits 2"; expect_fgrep 'CTLHQ_HOST must be claude or codex' "$out" "a bad CTLHQ_HOST is named"
# get reads the file's [codex] line before the default; the top-level line is not read for Codex.
ck="$c17/k.toml"; printf 'builders = "opus"\nplanners-and-reviewers = "fable"\n\n[codex]\nbuilders = "gpt-x"  # mine\n' > "$ck"
run --file "$ck" --host codex get builders; expect_eq gpt-x "$out" "get --host codex reads the file's [codex] line"; expect_eq "" "$err" "a [codex] value from the file prints no note"
run --file "$ck" get builders; expect_eq opus "$out" "host claude ignores the [codex] line of the same role"
run --file "$ck" --host codex get planners-and-reviewers; expect_eq gpt-6-astra "$out" "a top-level line is never the Codex value"
# set and unset write inside [codex] and create the table at the end.
cs="$c17/s.toml"; printf 'budget = "large"\nbuilders = "opus"\n' > "$cs"
run --file "$cs" --host codex set builders gpt-6-astra; expect_rc 0 "$rc" "set --host codex exits 0"
expect_eq "[codex] builders = gpt-6-astra  ($cs)" "$out" "set --host codex names the table"
expect_eq "" "$err" "a Codex name in [codex] gives no unknown-name warning"
expect_eq 'budget = "large"|builders = "opus"||[codex]|builders = "gpt-6-astra"' "$(tr '\n' '|' < "$cs" | sed 's/|$//')" "set --host codex creates [codex] at the end and leaves the top line"
run --file "$cs" set swarm-workers haiku
expect_eq 'budget = "large"|builders = "opus"|swarm-workers = "haiku"||[codex]|builders = "gpt-6-astra"' "$(tr '\n' '|' < "$cs" | sed 's/|$//')" "a new top-level line goes above the [codex] table"
run --file "$cs" --host codex set best-of-n-runners gpt-6-astra,gpt-6.1-sol
expect_eq 'best-of-n-runners = ["gpt-6-astra", "gpt-6.1-sol"]' "$(sed -n '/^\[codex\]$/,$p' "$cs" | tail -1)" "a second Codex line goes after the last [codex] line, as a list"
run --file "$cs" --host codex set builders gpt-6.1-sol
expect_eq 1 "$(grep -c '^builders = "gpt-6.1-sol"$' "$cs")" "set --host codex replaces the [codex] line in place"
run --file "$cs" get builders; expect_eq opus "$out" "set --host codex never changes the top-level line"
run --file "$cs" --host codex set builders gpt-a,gpt-b; expect_rc 2 "$rc" "set --host codex keeps the single-value rule"
expect_fgrep "fix (operator, changes $cs): ctlhq-models --file $cs --host codex set builders gpt-a" "$err" "set --host codex refusal: fix line names the host"
ci="$c17/i.toml"; "$fm" --file "$ci" init >/dev/null 2>&1
run --file "$ci" --host codex set planners-and-reviewers gpt-6.1-sol
expect_eq 'planners-and-reviewers = "gpt-6.1-sol"  # role map: in Codex, plans and reviews run on gpt-6-astra (model_reasoning_effort xhigh)' "$(sed -n '/^\[codex\]$/,$p' "$ci" | grep '^planners-and-reviewers =')" "set --host codex keeps the line's comment"
run --file "$ci" --host codex unset planners-and-reviewers; expect_rc 0 "$rc" "unset --host codex exits 0"
expect_eq "removed planners-and-reviewers from the [codex] table of $ci; the default applies: gpt-6-astra" "$out" "unset --host codex names the table and the Codex default"
expect_eq 'planners-and-reviewers = "fable"' "$(grep -o '^planners-and-reviewers = "fable"' "$ci")" "unset --host codex leaves the top-level line"
run --file "$ci" --host codex get planners-and-reviewers; expect_eq gpt-6-astra "$out" "after unset --host codex the [codex] default applies"
run --file "$ci" --host codex unset planners-and-reviewers; expect_rc 0 "$rc" "unset --host codex of an absent line exits 0"; expect_fgrep 'has no line in the [codex] table' "$err" "absent [codex] line noted"
run --file "$cs" --host codex unset best-of-n-runners; run --file "$cs" --host codex unset builders
run --file "$cs" --host codex set hillclimb gpt-6-astra
expect_eq 'hillclimb = "gpt-6-astra"' "$(sed -n '/^\[codex\]$/{n;p;}' "$cs")" "set --host codex into an empty [codex] table goes under its header"
expect_eq 1 "$(grep -c '^\[codex\]$' "$cs")" "set --host codex never adds a second [codex] header"
# show: the codex column for every host, so both hosts' values are listed.
run --file "$cn" show; expect_grep 'codex$' "$(printf '%s\n' "$out" | sed -n 2p)" "show for host claude also lists the codex column"
run --file "$cn" --host codex show; expect_rc 0 "$rc" "show --host codex exits 0"
expect_grep '^role +current +default +codex$' "$(printf '%s\n' "$out" | sed -n 2p)" "show --host codex adds a codex column"
expect_grep '^planners-and-reviewers +fable \(default\) +fable +gpt-6-astra \(default\)$' "$out" "show --host codex: the Codex default"
expect_grep '^builders +opus \(default\) +opus +inherit-parent \(no Codex value\)$' "$out" "show --host codex: a role with no Codex value"
expect_grep '^budget +large \(xhigh\) \(default\) +large \(xhigh\)$' "$out" "show --host codex: the budget row has no codex cell"
# Fix lines in Codex never name a Claude model.
run --file "$tmp/fx.toml" --host codex set best-of-n-runners ","; expect_nogrep 'opus|sonnet|fable|haiku' "$err" "set --host codex refusal names no Claude model"
printf '[codex]\nswarm-workers = ["", "gpt-c"]\n' > "$tmp/fv.toml"
run --file "$tmp/fv.toml" --host codex validate; expect_nogrep 'set swarm-workers (opus|sonnet|fable|haiku)' "$out$err" "validate --host codex fix names no Claude model"
run --file "$ck" --host codex show; expect_grep '^builders +opus +opus +gpt-x$' "$out" "show --host codex: the file's [codex] value"
# validate: the [codex] table is accepted, its keys and shapes are checked, --allow checks the chosen host only.
run --file "$ci" validate; expect_rc 0 "$rc" "validate accepts the [codex] table"; expect_eq "" "$err" "Codex names in [codex] give no unknown-name warning"
run --file "$ci" --host codex validate; expect_rc 0 "$rc" "validate --host codex exits 0"
expect_eq "ok: $ci  $ROLES roles set, budget large (xhigh), 1 [codex] role(s) set" "$out" "validate --host codex counts the [codex] lines"
run --file "$ci" --host codex validate --allow gpt-6-astra,gpt-6.1-sol; expect_rc 0 "$rc" "--allow with host codex skips the Claude values"
run --file "$ci" --host codex validate --allow gpt-6-astra; expect_rc 1 "$rc" "--allow with host codex checks the [codex] values"
expect_fgrep "is not in --allow" "$out" "a [codex] value outside --allow is a problem"
expect_fgrep "problem: line" "$(printf '%s\n' "$out" | grep "\[codex\] planners-and-reviewers-limit-fallback = 'gpt-6.1-sol'")" "the --allow problem names the [codex] role"
expect_fgrep "fix (operator, changes $ci): ctlhq-models --file $ci --host codex set planners-and-reviewers-limit-fallback gpt-6-astra  (gpt-6.1-sol -> gpt-6-astra: closest allowed name of family gpt" "$out" "the --allow fix names --host codex and the gpt family"
expect_nogrep "sonnet' is not in --allow" "$out" "--allow with host codex does not check the top-level values"
run --file "$ci" validate --allow gpt-6-astra; expect_nogrep '\[codex\]' "$out" "--allow with host claude does not check the [codex] values"
expect_fgrep "next: once the operator has applied each fix, check again: ctlhq-models --file $ci validate --allow gpt-6-astra" "$(printf '%s\n' "$out" | tail -1)" "host claude next line has no --host"
run --file "$ci" --host codex validate --allow gpt-6-astra
expect_fgrep "next: once the operator has applied each fix, check again: ctlhq-models --file $ci --host codex validate --allow gpt-6-astra" "$(printf '%s\n' "$out" | tail -1)" "host codex next line keeps --host codex"
cv="$c17/v.toml"
cat > "$cv" <<'TOML'
builders = "opus"

[codex]
builders = "gpt-a"
nosuch = "gpt-b"
budget = "large"
swarm-workers = ["gpt-c"]
best-of-n-runners = "gpt-d"
builders = "gpt-e"
how-explorer = ""
TOML
cp "$cv" "$c17/v-before.toml"
run --file "$cv" validate; expect_rc 1 "$rc" "validate on a bad [codex] table exits 1"
expect_fgrep 'problem: line 5: retired role [codex] nosuch (not in the defaults, so no skill reads it)' "$out" "[codex] unknown key"
expect_fgrep 'problem: line 6: budget inside [codex] (both hosts share the top budget line' "$out" "[codex] budget line"
expect_fgrep 'problem: line 7: [codex] swarm-workers takes a single value, got a list' "$out" "[codex] list in a single role"
expect_fgrep "fix (operator, changes $cv): ctlhq-models --file $cv --host codex set swarm-workers gpt-c" "$out" "[codex] shape fix names --host codex"
expect_fgrep 'problem: line 8: [codex] best-of-n-runners takes a list, got a single value' "$out" "[codex] single value in a list role"
expect_fgrep 'problem: line 9: [codex] builders appears more than once (only line 4 is read)' "$out" "[codex] duplicate role"
expect_nogrep 'problem: line 4: ' "$out" "the same role at the top and in [codex] is no duplicate"
expect_fgrep "problem: line 10: [codex] how-explorer has an empty value" "$out" "[codex] empty value"
expect_fgrep "fix (operator, changes $cv): ctlhq-models --file $cv --host codex unset how-explorer  (the default inherit-parent, no Codex value applies)" "$out" "[codex] empty value: fix names --host codex and the Codex default"
expect_eq "" "$(diff "$c17/v-before.toml" "$cv")" "validate with a [codex] table is read-only"
out="$(CTLHQ_HOST=codex "$fm" --file "$vv" validate 2>/dev/null)"
expect_fgrep "fix (operator, changes $vv): ctlhq-models --file $vv --host claude set swarm-workers sonnet" "$out" "with CTLHQ_HOST=codex a top-level fix names --host claude"
printf 'builders = "opus"\n[other]\nbuilders = "x"\n' > "$c17/t.toml"
run --file "$c17/t.toml" validate; expect_rc 1 "$rc" "validate on an unknown table exits 1"; expect_fgrep 'problem: line 2: unknown table [other]; the only table is [codex]' "$out" "unknown table named"
run --file "$c17/t.toml" get builders; expect_rc 1 "$rc" "get on a file with an unknown table exits 1"
# prune drops the [codex] lines no skill reads.
cp "$c17/v-before.toml" "$c17/p.toml"
run --file "$c17/p.toml" prune; expect_rc 0 "$rc" "prune with [codex] lines exits 0"
expect_fgrep 'retired role dropped: line 5: nosuch = "gpt-b"' "$out" "prune drops an unknown [codex] key"
expect_fgrep 'retired role dropped: line 6: budget = "large"' "$out" "prune drops a budget line inside [codex]"
expect_eq "pruned 2 line(s) from $c17/p.toml" "$(printf '%s\n' "$out" | tail -1)" "prune drops only those two lines"
# pick and fallback read the chosen host's values; gpt-* is family gpt.
run --file "$cn" --host codex pick planners-and-reviewers --not-family opus; expect_rc 0 "$rc" "pick --host codex exits 0"
expect_eq "gpt-6-astra|rule: entry 1 of planners-and-reviewers is family gpt, which differs from opus (claude)" "$(printf '%s\n' "$out" | tr '\n' '|' | sed 's/|$//')" "pick --host codex reads the Codex value, family gpt"
run --file "$cn" pick planners-and-reviewers --not-family opus; expect_rc 1 "$rc" "pick on host claude still reads fable"; expect_eq fable "$(printf '%s\n' "$out" | head -1)" "pick on host claude prints fable"
run --file "$cn" --host codex pick planners-and-reviewers --not-family gpt-6.1-sol; expect_rc 1 "$rc" "gpt-6.1-sol and gpt-6-astra share the gpt family"
run --file "$cn" --host codex fallback planners-and-reviewers gpt-6-astra --valid gpt-6.1-sol,o9; expect_rc 0 "$rc" "fallback --host codex with --valid exits 0"
expect_eq "gpt-6.1-sol|rule: gpt-6-astra is family gpt by its vendor prefix; closest --valid model of family gpt" "$(printf '%s\n' "$out" | tr '\n' '|' | sed 's/|$//')" "fallback --host codex picks the gpt family name"
run --file "$cn" --host codex fallback builders gpt-6-astra; expect_eq inherit-parent "$(printf '%s\n' "$out" | head -1)" "fallback --host codex with no Codex value prints inherit-parent"
expect_fgrep "rerun: ctlhq-models --file $cn --host codex fallback builders gpt-6-astra --valid" "$out" "fallback --host codex rerun keeps --host codex"
run --file "$cn" --host codex fallback planners-and-reviewers gpt-6-astra --valid=o9
expect_fgrep "next (operator, changes $cn): set the role to a --valid name: ctlhq-models --file $cn --host codex set planners-and-reviewers" "$out" "fallback --host codex set suggestion names the host and carries the marker"
for r in builders planners-and-reviewers best-of-n-runners swarm-workers; do
	run --file "$cn" --host codex fallback "$r" gpt-6-astra
	expect_nogrep "$claude_name" "$(printf '%s\n' "$out" | head -1)" "fallback --host codex $r prints no Claude name"
done
# budget --rewrite-names leaves the [codex] lines alone.
cb="$c17/b.toml"; printf 'budget = "large"\njudgment-and-prose = "x-xhigh"\n\n[codex]\njudgment-and-prose = "gpt-6-astra-xhigh"\n' > "$cb"
run --file "$cb" budget small --rewrite-names
expect_eq 'judgment-and-prose = "gpt-6-astra-xhigh"' "$(tail -1 "$cb")" "budget --rewrite-names leaves the [codex] line"
expect_eq 'judgment-and-prose = "x-medium"' "$(sed -n 2p "$cb")" "budget --rewrite-names still rewrites the top line"
# Every set, unset, init, budget, or prune suggestion with --host also carries the operator marker.
all_out="$(for c in "validate" "validate --allow=gpt-6-astra" "pick best-of-n-runners --not-family opus" "fallback planners-and-reviewers gpt-6-astra --valid=o9" "set best-of-n-runners ," "unset" "init"; do eval "\"\$fm\" --file \"\$ci\" --host codex $c" 2>&1; eval "\"\$fm\" --file \"\$cv\" --host codex $c" 2>&1; done)"
expect_nogrep '^(fix|next): .*ctlhq-models( --file [^ ]+)?( --host [a-z]+)? (set|unset|init|budget|prune)( |$)' "$all_out" "no plain fix or next line with --host suggests a command that changes the models file"
expect_eq "$real_sum_before" "$(cksum "$real_cfg" 2>/dev/null || echo absent)" "the real ~/.ctlhq/models.toml is unchanged after the Codex checks"

echo "$pass checks passed"
if [ "$fail" -gt 0 ]; then
	echo "$fail checks failed"
	exit 1
fi
exit 0
