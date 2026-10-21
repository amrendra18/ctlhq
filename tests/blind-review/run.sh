#!/usr/bin/env bash
# tests/blind-review/run.sh: checks that skills/blind-review/SKILL.md section 4 picks the reviewer
# from the role ctlhq-setup gives to reviews, and that the ctlhq-models commands it names work
# on that role with no models file. Prints "N checks passed" and exits 1 when any check fails.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
skill="${BLIND_REVIEW_SKILL:-$root/skills/blind-review/SKILL.md}"
fm="$root/bin/ctlhq-models"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/blind-review-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
pass=0
fail=0
ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL: $1"; }
expect_rc() { if [ "$1" -eq "$2" ]; then ok; else bad "$3 (expected exit $1, got $2)"; fi; }
expect_eq() { if [ "$1" = "$2" ]; then ok; else bad "$3 (expected '$1', got '$2')"; fi; }
expect_grep() { if printf '%s\n' "$2" | grep -Eq -- "$1"; then ok; else bad "$3 (no line matches: $1)"; fi; }

section4="$(awk '/^## 4\. /{on=1; next} /^## /{on=0} on' "$skill")"
setup_role="$(grep -Eo '`[a-z-]+` \(default `[^`]+`\) writes deep-dive plans and reviews' "$root/skills/ctlhq-setup/SKILL.md" | grep -Eo '^`[a-z-]+`' | tr -d '`')"
pick_role="$(printf '%s\n' "$section4" | grep -Eo 'ctlhq-models pick [a-z-]+' | head -1 | awk '{print $3}')"

# 1. One role for reviews in both skills.
expect_eq planners-and-reviewers "$setup_role" "ctlhq-setup step (d) names the review role"
expect_eq "$setup_role" "$pick_role" "blind-review section 4 picks from the review role of ctlhq-setup"
expect_eq 0 "$(printf '%s\n' "$section4" | grep -c 'interrogate-reviewers')" "section 4 no longer reads interrogate-reviewers"

# 2. The section says plainly what a different family takes inside Claude Code.
expect_grep 'Inside Claude Code every model is Claude family' "$section4" "section 4 says Claude Code has one family"
expect_grep 'another host, such as Codex' "$section4" "section 4 names Codex as the other host"

# 3. The commands it names work on that role with no models file.
: > "$tmp/models.toml"
# The top-level (Claude) line only; the [codex] table below it holds the Codex value.
default="$(sed -n "/^\[/q; s/^$pick_role = \"\([^\"]*\)\".*/\1/p" "$root/skills/ctlhq-setup/models.example.toml")"
out="$("$fm" --file "$tmp/models.toml" pick "$pick_role" --not-family claude-opus-5-5 2>/dev/null)"; rc=$?
expect_rc 1 "$rc" "pick inside one family exits 1 (the case step 3 describes)"
expect_eq "$default" "$(printf '%s\n' "$out" | head -1)" "pick prints the role's default model"
fb_role="$(printf '%s\n' "$section4" | grep -Eo 'ctlhq-models get [a-z-]+' | head -1 | awk '{print $3}')"
expect_eq "$pick_role-limit-fallback" "$fb_role" "fallback step reads the role's limit-fallback"
out="$("$fm" --file "$tmp/models.toml" get "$fb_role" 2>/dev/null)"; expect_rc 0 $? "get the fallback role exits 0"
expect_eq opus "$out" "fallback role default is opus"

echo "$pass checks passed"
[ "$fail" -eq 0 ] || { echo "$fail checks failed"; exit 1; }
