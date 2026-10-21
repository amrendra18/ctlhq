#!/usr/bin/env bash
# tests/ctlhq-status/run.sh: checks for bin/ctlhq-status against a scratch git repository
# with a README.md "Open decisions" section, BLOCKED.md, PLAN.md, and .local/gate/ files, plus
# a decoy NEXT.md that the tool must ignore (the positive control for the NEXT.md retirement). Prints "N checks passed" and
# exits 1 when any check fails. Writes only to a temp folder.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
fs="$root/bin/ctlhq-status"
pass=0
fail=0
ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL: $1"; }
expect_rc() { if [ "$1" -eq "$2" ]; then ok; else bad "$3 (expected exit $1, got $2)"; fi; }
expect_eq() { if [ "$1" = "$2" ]; then ok; else bad "$3 (expected '$1', got '$2')"; fi; }
expect_grep() { if printf '%s\n' "$2" | grep -Eq -- "$1"; then ok; else bad "$3 (no line matches: $1)"; fi; }
expect_nogrep() { if printf '%s\n' "$2" | grep -Eq -- "$1"; then bad "$3 (a line matches: $1)"; else ok; fi; }

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
unset ORCH_STORE
tmp="$(mktemp -d "${TMPDIR:-/tmp}/ctlhq-status-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home"  # block 7 reads transcripts under HOME; keep the real ones out
mkdir -p "$HOME"
repo="$tmp/repo"
mkdir -p "$repo/.local/gate" "$repo/sub"
git -C "$repo" init -q -b main 2>/dev/null || { git -C "$repo" init -q; git -C "$repo" symbolic-ref HEAD refs/heads/main; }
git -C "$repo" config user.name "Test User"
git -C "$repo" config user.email "test@example.invalid"
git -C "$repo" config commit.gpgsign false
printf '.local/\n' > "$repo/.gitignore"
cat > "$repo/README.md" <<'MD'
# Demo

Demo imports files.

```md
## Open decisions
- A fenced example. Owner: operator
```

## Open decisions

| # | Item | Owner | Next command |
|---|------|-------|--------------|
| 1 | Approve the schema change | operator | none |
| 2 | Fix the flaky import test | builder | bin/test |
| 3 | Sign the release | Operator and main agent | none |

- Pick the release name. Owner: you, by Friday.
- Write the changelog. Owner: Jun Park, who emails you the list.

## Install

- Outside the section. Owner: operator
MD
cat > "$repo/NEXT.md" <<'MD'
# Next

## State

Old state line from NEXT.md.

## Open items

| # | Item | Owner |
|---|------|-------|
| 1 | Approve the NEXT-only item | operator |

Stopped: the NEXT.md stop line.
MD
cat > "$repo/BLOCKED.md" <<'MD'
# Blocked

1. git commit: the sandbox denies .git writes. Owner: operator.
MD
cat > "$repo/PLAN.md" <<'MD'
# Plan

## 9. Risks

None.

## 10. Approvals

1. 2026-10-14 10:00 scope A
2. 2026-10-15 11:00 scope B
3. 2026-10-16 09:00 scope C
4. 2026-10-16 09:30 scope D

## 11. Notes

Not approvals.
MD
git -C "$repo" add .gitignore README.md NEXT.md PLAN.md
git -C "$repo" commit -q -m "Seed the plan"
printf '0\n' > "$repo/.local/gate/gate.exit"
printf '2026-10-16T10:00:00Z\t2026-10-16T10:00:05Z\t0\tmake test\n' > "$repo/.local/gate/gate.meta"
printf '2\n' > "$repo/.local/gate/lint.exit"
before="$(cd "$repo" && find . -path ./.git -prune -o -type f -print | sort; cat .local/gate/* README.md NEXT.md BLOCKED.md PLAN.md | cksum)"

# 1. --help and usage.
out="$("$fs" --help 2>&1)"; expect_rc 0 $? "--help exits 0"
expect_grep '^ctlhq-status: ' "$(printf '%s\n' "$out" | head -1)" "--help first line is 'ctlhq-status: ...'"
expect_grep 'Before stating the state of a process' "$out" "--help quotes the AGENTS.md rule"
"$fs" --bogus >/dev/null 2>&1; expect_rc 2 $? "unknown option exits 2"
"$fs" --repo >/dev/null 2>&1; expect_rc 2 $? "--repo without a value exits 2"
mkdir -p "$tmp/plain"
"$fs" --repo "$tmp/plain" >/dev/null 2>&1; expect_rc 1 $? "a plain folder exits 1"

# 2. Text output: seven numbered blocks in order.
out="$(cd "$repo/sub" && "$fs" 2>&1)"; rc=$?
expect_rc 0 "$rc" "status from a subfolder exits 0"
expect_eq "1. Repository 2. Gate 3. Open decisions (README.md) 4. BLOCKED.md 5. PLAN.md section 10 6. Agents 7. Now" "$(printf '%s\n' "$out" | grep -E '^[0-9]\. ' | tr '\n' ' ' | sed 's/ $//')" "seven blocks in order"
expect_grep '^   branch: main$' "$out" "branch is main"
expect_grep '^   HEAD: [0-9a-f]{7,} Seed the plan$' "$out" "HEAD hash and subject"
expect_grep '^   committed: [0-9]+ seconds? ago' "$out" "commit age"
expect_grep '^   dirty files: 1$' "$out" "dirty count is 1 (BLOCKED.md untracked)"
expect_grep '^   gate  exit 0  [0-9]+ (days?|hours?|minutes?|seconds?) ago$' "$out" "gate row from .meta"
expect_grep '^   lint  exit 2  .* \(file age, no \.meta\)$' "$out" "lint row falls back to file age"
expect_grep '^   ## Open decisions: 5 rows$' "$out" "the README section heading and row count"
expect_grep '^   1\. Approve the schema change \(owner: operator\) \[needs you\]$' "$out" "operator table row marked"
expect_grep '^   2\. Fix the flaky import test \(owner: builder\)$' "$out" "builder table row listed, not marked"
expect_grep '^   3\. Sign the release \(owner: Operator and main agent\) \[needs you\]$' "$out" "mixed-owner row marked"
expect_grep '^   4\. Pick the release name\. Owner: you, by Friday\. \[needs you\]$' "$out" "list entry with 'Owner: you' marked"
expect_grep '^   5\. Write the changelog\. Owner: Jun Park, who emails you the list\.$' "$out" "a named owner is not marked, even with 'you' later"
expect_grep '^   needs you \(3\): row 1, row 3, row 4$' "$out" "three rows need the operator"
expect_nogrep 'fenced example|Outside the section' "$out" "fenced and later-section entries are not rows"
expect_nogrep 'NEXT-only|Old state line|NEXT\.md' "$out" "positive control: NEXT.md is no longer read"
expect_grep '^   last stop: 1\. git commit: the sandbox denies \.git writes\. Owner: operator\. \(BLOCKED\.md, last entry\)$' "$out" "positive control: last stop from BLOCKED.md, not the NEXT.md stop line"
expect_grep '^   present \(first 3 lines\)$' "$out" "BLOCKED.md present"
expect_grep 'sandbox denies .git writes' "$out" "BLOCKED.md first lines shown"
expect_eq "$(printf '   2. 2026-10-15 11:00 scope B\n   3. 2026-10-16 09:00 scope C\n   4. 2026-10-16 09:30 scope D')" "$(printf '%s\n' "$out" | sed -n '/^5\. /,/^6\. /p' | grep '^   [0-9]')" "PLAN.md section 10 last 3 lines"
expect_grep '^   no agent store$' "$out" "no agent store"

# 3. --json parses and holds the same facts.
json="$("$fs" --repo "$repo" --json)"; expect_rc 0 $? "--json exits 0"
facts="$(printf '%s' "$json" | python3 -c '
import json, sys
d = json.load(sys.stdin)
print(" ".join(sorted(d)))
print(d["repository"]["branch"], d["repository"]["subject"], d["repository"]["dirty_files"])
print(",".join("%s=%s" % (g["name"], g["exit"]) for g in d["gate"]))
print(len(d["decisions"]["rows"]), len(d["decisions"]["needs_you"]), d["decisions"]["heading"])
print(d["blocked"]["present"], len(d["blocked"]["first_lines"]))
print(d["plan"]["last_lines"][-1])
print(d["agents"]["note"])
' 2>&1)"
expect_eq "$(printf 'agents blocked decisions gate now plan repository\nmain Seed the plan 1\ngate=0,lint=2\n5 3 ## Open decisions\nTrue 3\n4. 2026-10-16 09:30 scope D\nno agent store')" "$facts" "--json facts match the text blocks"

# 4. Missing files and a ctlhq-orch store without bun.
rm -f "$repo/BLOCKED.md"
mkdir -p "$repo/.local/orch"
out="$(PATH=/usr/bin:/bin "$fs" --repo "$repo")"
expect_grep '^4\. BLOCKED\.md$' "$out" "block 4 still printed"
expect_eq "absent" "$(printf '%s\n' "$out" | sed -n '/^4\. /{n;p;}' | sed 's/^ *//')" "BLOCKED.md absent"
if PATH=/usr/bin:/bin command -v bun >/dev/null 2>&1; then ok; else expect_grep '^   ctlhq-orch store present, bun missing$' "$out" "ctlhq-orch store without bun"; fi
rmdir "$repo/.local/orch"
printf '1. git commit blocked\n' > "$repo/BLOCKED.md"

# 5. Nothing written.
after="$(cd "$repo" && find . -path ./.git -prune -o -type f -print | sort; cat .local/gate/* README.md NEXT.md BLOCKED.md PLAN.md | cksum)"
before2="$(printf '%s' "$before" | sed '$d')"
after2="$(printf '%s' "$after" | sed '$d')"
expect_eq "$before2" "$after2" "ctlhq-status writes no file"

# 5b. README.md without the section, then no README.md at all.
r3="$tmp/r3"
mkdir -p "$r3"
git -C "$r3" init -q
printf '# Plain\n\n## Open questions\n\n- Not a decisions heading. Owner: operator\n' > "$r3/README.md"
cp "$repo/NEXT.md" "$r3/NEXT.md"
out="$("$fs" --repo "$r3")"; expect_rc 0 $? "a README without the section exits 0"
expect_eq "no open decisions section (no heading names \"open decisions\" or \"open items\")" "$(printf '%s\n' "$out" | sed -n '/^3\. /{n;p;}' | sed 's/^ *//')" "README without the section"
expect_nogrep 'NEXT-only' "$out" "positive control: no fallback to NEXT.md"
printf '# Plain\n\n### OPEN ITEMS\n\n1. Choose a host. Owner: the operator.\n2. Fix the build. Owner: agent.\n' > "$r3/README.md"
out="$("$fs" --repo "$r3")"
expect_grep '^   ### OPEN ITEMS: 2 rows$' "$out" "an 'open items' heading at level 3, any case"
expect_grep '^   needs you \(1\): row 1$' "$out" "numbered list owner text"
json="$("$fs" --repo "$r3" --json)"
expect_eq "Choose a host. Owner: the operator.|the operator|True" "$(printf '%s' "$json" | python3 -c 'import json,sys; r=json.load(sys.stdin)["decisions"]["rows"][0]; print(r["item"], r["owner"], r["needs_you"], sep="|")')" "--json decision row fields"
rm -f "$r3/README.md"
out="$("$fs" --repo "$r3")"
expect_eq "README.md absent" "$(printf '%s\n' "$out" | sed -n '/^3\. /{n;p;}' | sed 's/^ *//')" "README.md absent"
expect_eq "False None" "$("$fs" --repo "$r3" --json | python3 -c 'import json,sys; d=json.load(sys.stdin)["decisions"]; print(d["readme"], d["heading"])')" "--json README absent"

# 6. Block 7 (Now) with no transcript, no milestone table, no stop line.
out="$("$fs" --repo "$repo")"
expect_grep '^   since your last message: unknown \(no Claude Code or Codex session for this workspace; pass --since TIME\)$' "$out" "since is unknown without a transcript"
expect_grep '^   current item: unknown \(no milestone table in PLAN.md section 7\)$' "$out" "no milestone table"
expect_grep '^   lanes: 0 worktrees, 0 processes naming this repository$' "$out" "no lanes"
expect_grep '^   last stop: 1\. git commit blocked \(BLOCKED.md, last entry\)$' "$out" "stop reason from BLOCKED.md"

# 7. Block 7 on a second repository: milestones, a worktree, --since, a stop line.
r2="$tmp/r2"
mkdir -p "$r2/.local/gate"
git -C "$r2" init -q -b main 2>/dev/null || { git -C "$r2" init -q; git -C "$r2" symbolic-ref HEAD refs/heads/main; }
git -C "$r2" config user.name "Test User"; git -C "$r2" config user.email "test@example.invalid"; git -C "$r2" config commit.gpgsign false
printf '.local/\n' > "$r2/.gitignore"
cat > "$r2/PLAN.md" <<'MD'
# Plan

## 6. Milestones

### M0: thin journey

- **Outcome.** The operator runs `imp` and sees one row.

### M1: schema

- **Outcome.** Internal: the schema moves to version 2.

### M2: import page

- **Outcome.** The operator opens the import page and sees every file.

## 7. Milestone status

| Milestone | State | Commit | Date | Tests | Lines | Evidence |
| --- | --- | --- | --- | --- | --- | --- |
| M0 | committed | abc1234 | 2026-10-15 | 4 | 80 | gate |
| M1 | built | | | | | |
| M2 | planned | | | | | |
MD
cat > "$r2/NEXT.md" <<'MD'
# Next

## State

M1 built.

Stopped: waiting for the signing key.
MD
git -C "$r2" add .gitignore PLAN.md NEXT.md
git -C "$r2" commit -q -m "First"
first="$(git -C "$r2" rev-parse --short HEAD)"
printf 'x\n' > "$r2/a.txt"; git -C "$r2" add a.txt; git -C "$r2" commit -q -m "Second"
git -C "$r2" worktree add -q "$tmp/wt" -b lane1 2>/dev/null
printf 'y\n' > "$r2/b.txt"
out="$("$fs" --repo "$r2" --since "$first")"; expect_rc 0 $? "--since REV exits 0"
expect_grep "^   since your last message \($first, from --since\): 1 commits, 1 changed files$" "$out" "--since REV counts commits after it"
expect_grep '^   - commit [0-9a-f]+ Second$' "$out" "the commit after REV is listed"
expect_grep '^   - file \?\? b\.txt$' "$out" "the untracked file is listed"
expect_grep '^   current item: M1 schema \(state built; 1 of 3 milestones committed or accepted\)$' "$out" "current item is M1"
expect_grep '^   next user-visible milestone: M2, 1 open milestones before it; outcome: The operator opens the import page and sees every file\.$' "$out" "internal M1 is skipped"
expect_grep '^   lanes: 1 worktrees, ' "$out" "one worktree lane"
expect_grep "^   - worktree .*/wt \(lane1\), last commit [0-9]+ seconds? ago, dirty files 0$" "$out" "worktree row"
expect_grep '^   last stop: no stop reason recorded$' "$out" "positive control: a NEXT.md stop line is not read"
out="$("$fs" --repo "$r2" --since 2000-01-01T00:00:00Z)"
expect_grep '^   since your last message \(2000-01-01T00:00:00Z, from --since\): 2 commits, 1 changed files$' "$out" "--since ISO counts both commits"
out="$("$fs" --repo "$r2" --since nosuchrev)"; expect_rc 0 $? "a bad --since still prints"
expect_grep "neither an ISO time nor a git revision" "$out" "a bad --since is named"
"$fs" --repo "$r2" --since >/dev/null 2>&1; expect_rc 2 $? "--since without a value exits 2"
sed -i.bak '/^Stopped/d' "$r2/NEXT.md"; rm -f "$r2/NEXT.md.bak"
printf '3\n' > "$r2/.local/gate/gate.exit"
out="$("$fs" --repo "$r2")"
expect_grep '^   last stop: gate gate exited 3 [0-9]+ seconds? ago \(\.local/gate\)$' "$out" "stop reason from a failed gate"
json="$("$fs" --repo "$r2" --json)"
expect_eq "M1 M2 1 1" "$(printf '%s' "$json" | python3 -c 'import json,sys; d=json.load(sys.stdin)["now"]; m=d["milestones"]; print(m["current"]["milestone"], m["visible"]["milestone"], m["open_before"], len(d["lanes"]["worktrees"]))')" "--json now block"

# 8. Since from transcripts: the operator message before the newest one; Claude Code, then Codex.
top="$(git -C "$r2" rev-parse --show-toplevel)"
python3 - "$HOME" "$top" <<'PY2'
import datetime, json, os, sys
home, ws = sys.argv[1], sys.argv[2]
now = datetime.datetime.now(datetime.timezone.utc)
iso = lambda d: d.strftime("%Y-%m-%dT%H:%M:%S.000Z")
t1, t2, t3 = now - datetime.timedelta(days=400), now - datetime.timedelta(days=300), now - datetime.timedelta(seconds=5)
def cl(ts, text):
    return {"type": "user", "timestamp": iso(ts), "sessionId": "s1", "cwd": ws, "isSidechain": False, "uuid": "u" + iso(ts),
            "parentUuid": None, "userType": "external", "message": {"role": "user", "content": text}}
d = os.path.join(home, ".claude", "projects", ws.replace("/", "-"))
os.makedirs(d, exist_ok=True)
with open(os.path.join(d, "s1.jsonl"), "w") as fh:
    for ts, text in ((t1, "Start the build."), (t2, "Go on."), (t3, "Where are we?")):
        fh.write(json.dumps(cl(ts, text)) + "\n")
def cx(kind, ts, payload):
    return {"timestamp": iso(ts), "type": kind, "payload": payload}
def um(ts, text):
    return cx("event_msg", ts, {"type": "item_completed", "turn_id": "t", "item": {"type": "UserMessage", "id": "i" + iso(ts), "content": [{"type": "text", "text": text, "text_elements": []}]}})
c1, c2 = now - datetime.timedelta(days=500), now - datetime.timedelta(days=450)
cd = os.path.join(home, ".codex", "sessions", "2026", "10", "16")
os.makedirs(cd, exist_ok=True)
with open(os.path.join(cd, "rollout-2026-10-16T10-00-00-cccccccc-0000-0000-0000-000000000009.jsonl"), "w") as fh:
    for row in (cx("session_meta", c1, {"id": "cccccccc-0000-0000-0000-000000000009", "timestamp": iso(c1), "cwd": ws, "originator": "codex_cli", "source": "cli"}),
                um(c1, "Codex, start."), um(c2, "Codex, status?")):
        fh.write(json.dumps(row, separators=(",", ":")) + "\n")
PY2
out="$("$fs" --repo "$r2")"
expect_grep '^   since your last message \([0-9T:-]+Z, from claude session s1\.jsonl\): 2 commits, ' "$out" "since comes from the Claude Code session, previous message"
rm -rf "$HOME/.claude"
out="$("$fs" --repo "$r2")"
expect_grep '^   since your last message \([0-9T:-]+Z, from codex session rollout-.*\.jsonl\): 2 commits, ' "$out" "since comes from the Codex session when it is the only one"

# 9. --next: the first "in progress" row of the | # | Milestone | Done when | State | table, else the
# first "planned" row, else "none" with the reason. JSON carries the step and BLOCKED.md's open rows.
nx() { "$fs" --next --repo "$1"; }
r4="$tmp/r4"
mkdir -p "$r4"
git -C "$r4" init -q
expect_eq "next step: none (no PLAN.md)" "$(nx "$r4")" "--next without PLAN.md"
expect_eq "next step: none (no milestone table: PLAN.md has no table with the header | # | Milestone | Done when | State |)" "$(nx "$repo")" "--next without the milestone table"
printf '# Plan\n\n| # | Milestone | Done when | State |\n|---|---|---|---|\n\nNo rows yet.\n' > "$r4/PLAN.md"
expect_eq "next step: none (the milestone table at PLAN.md line 3 has no rows)" "$(nx "$r4")" "--next with an empty table"
cat > "$r4/PLAN.md" <<'MD'
# Plan

```md
| # | Milestone | Done when | State |
|---|---|---|---|
| 9 | Fenced example | never | in progress |
```

## 6. Milestones

| # | Milestone | Done when | State |
|---|---|---|---|
| 0 | Thin journey | `scripts/verify` exits 0 | done |
| 1 | Schema | `tests/schema` exits 0 | **planned** |
| 2 | Import page | `tests/import` exits 0 | In-Progress |
MD
expect_eq 'next step: row 2, Import page (in progress, PLAN.md line 15); done when: `tests/import` exits 0' "$(nx "$r4")" "--next picks the in-progress row before an earlier planned row, outside fences"
sed -i.bak 's/| In-Progress |/| planned |/' "$r4/PLAN.md"; rm -f "$r4/PLAN.md.bak"
expect_eq 'next step: row 1, Schema (planned, PLAN.md line 14); done when: `tests/schema` exits 0' "$(nx "$r4")" "--next picks the first planned row"
cat > "$r4/BLOCKED.md" <<'MD'
# Blocked

| # | Blocked step | Reason | Command that fails | Owner |
|---|---|---|---|---|
| 1 | screen capture | needs Screen Recording for Terminal | scripts/verify shot | operator |
| 2 | push | closed: remote removed | git push | operator |
| 3 | | | | |

- ~~old entry~~ fixed in 4b22be9
- network for the docs check, owner: operator
MD
json="$("$fs" --next --json --repo "$r4")"; expect_rc 0 $? "--next --json exits 0"
expect_eq "1|Schema|planned|14|None|2|done=1,planned=2" "$(printf '%s' "$json" | python3 -c 'import json,sys; d=json.load(sys.stdin); s=d["step"]; print(s["number"], s["milestone"], s["state"], s["line"], d["reason"], len(d["blocked_open"]), ",".join("%s=%s" % kv for kv in sorted(d["counts"].items())), sep="|")')" "--next --json fields; BLOCKED.md has 2 open rows (closed, empty, and struck rows left out)"
sed -i.bak 's/| \*\*planned\*\* |/| done |/; s/| planned |/| done |/' "$r4/PLAN.md"; rm -f "$r4/PLAN.md.bak"
expect_eq "next step: none (all 3 milestones done)" "$(nx "$r4")" "--next when every milestone is done"
sed -i.bak 's/`tests\/import` exits 0 | done |/`tests\/import` exits 0 | blocked |/' "$r4/PLAN.md"; rm -f "$r4/PLAN.md.bak"
expect_eq "next step: none (no row is in progress or planned (done 2, blocked 1))" "$(nx "$r4")" "--next when the rest is blocked"
"$fs" --next --since HEAD --repo "$r4" >/dev/null 2>&1; expect_rc 2 $? "--next with --since exits 2"
cat > "$r4/PLAN.md" <<'MD'
# Plan

## 7. Milestone status

| # | Milestone | Done when | State |
|---|---|---|---|
| M0 | Thin journey | `scripts/verify` exits 0 | committed |
| M1 | Schema | `tests/schema` exits 0 | planned |
MD
expect_eq 'next step: row M1, Schema (planned, PLAN.md line 8); done when: `tests/schema` exits 0; skipped 1 row with an unknown state (M0 committed)' "$(nx "$r4")" "--next skips an old plan's unknown state and names it"
sed -i.bak 's/| planned |/| accepted |/' "$r4/PLAN.md"; rm -f "$r4/PLAN.md.bak"
expect_eq 'next step: none (no row is in progress or planned (unknown state 2)); skipped 2 rows with an unknown state (M0 committed, M1 accepted)' "$(nx "$r4")" "--next with only unknown states says none and names them"
expect_eq "M0 committed 7|M1 accepted 8" "$("$fs" --next --json --repo "$r4" | python3 -c 'import json,sys; print("|".join("%s %s %s" % (u["number"], u["state"], u["line"]) for u in json.load(sys.stdin)["unknown"]))')" "--next --json lists the skipped rows"
cat > "$r4/PLAN.md" <<'MD'
# Plan

```md
| # | Milestone | Done when | State |
|---|---|---|---|
| 9 | Fenced example | never | in progress |
```

## 6. Milestones

| # | Milestone | Done when | State |
|---|---|---|---|
| 0 | Thin journey | `scripts/verify` exits 0 | done |
| 1 | Schema | `tests/schema` exits 0 | done |
| 2 | Import page | `tests/import` exits 0 | blocked |
MD
expect_grep 'Done when \| State' "$("$fs" --help)" "--help names the milestone table header"

# 10. Block 7 carries the next step and the cost line; worktrees come from the main work tree.
sed -i.bak 's/| blocked |/| in progress |/' "$r4/PLAN.md"; rm -f "$r4/PLAN.md.bak"
out="$("$fs" --repo "$r4")"
expect_grep '^   next step: row 2, Import page \(in progress, PLAN.md line 15\)' "$out" "block 7 prints the next step"
expect_grep '^   cost: 0 worktrees in \.local/worktrees \(0 MiB\); [0-9.]+ (GiB|MiB) free on this disk; rounds: none recorded$' "$out" "cost line without worktrees or rounds"
mkdir -p "$r2/.local/worktrees/a" "$r2/.local/worktrees/b"
python3 -c 'import sys; open(sys.argv[1], "wb").write(b"x" * (3 * 2 ** 20))' "$r2/.local/worktrees/a/blob"
cat >> "$r2/PLAN.md" <<'MD'

## 12. Rounds

- Round 1 started: 2026-10-19T01:00:00Z
- Round 1 ended: 2026-10-19T02:30:00Z

| # | Round | Note |
|---|---|---|
| 2 | Round 2 started: 2026-10-19T03:00Z | audit and fix |

```
Round 7 started: 2026-10-19T04:00:00Z
```
MD
out="$("$fs" --repo "$r2")"
expect_grep '^   cost: 2 worktrees in \.local/worktrees \(3 MiB\); [0-9.]+ (GiB|MiB) free on this disk; rounds: 2 so far, round 2 running for [0-9.]+ (minutes?|hours|days) \(PLAN.md line [0-9]+\)$' "$out" "cost line with worktrees, disk, and rounds; a fenced round is ignored"
out="$("$fs" --repo "$tmp/wt")"
expect_grep '^   cost: 2 worktrees in \.local/worktrees ' "$out" "a linked work tree counts the main work tree's .local/worktrees"
json="$("$fs" --repo "$r2" --json)"
expect_eq "2|True|2|3145728" "$(printf '%s' "$json" | python3 -c 'import json,sys; c=json.load(sys.stdin)["now"]["cost"]; print(c["rounds"], c["round_running"], c["worktrees"], c["worktrees_bytes"] // 2 ** 20 * 2 ** 20, sep="|")')" "--json now.cost numbers"
printf 'Round 3 started: 2026-10-19T05:00:00Z\nround 3 ended: 2026-10-19T05:45:00Z\n' > "$r2/REPORT.md"
out="$("$fs" --repo "$r2")"
expect_grep 'rounds: 3 so far, round 3 took 45 minutes \(REPORT.md line 1\)$' "$out" "REPORT.md round lines count, any case"
expect_grep 'Round N started: TIME' "$("$fs" --help)" "--help says where the round numbers come from"
r5="$tmp/r5"; mkdir -p "$r5"; git -C "$r5" init -q
cat > "$r5/PLAN.md" <<'MD'
# Plan

## 7. Milestone status

| # | Milestone | Done when | State |
|---|---|---|---|
| M0 | Thin journey | `scripts/verify` exits 0 | done |
| M1 | Schema | `tests/schema` exits 0 | planned |
| M2 | Import page | `tests/import` exits 0 | in progress |
MD
out="$("$fs" --repo "$r5")"
expect_grep '^   current item: M2 Import page \(state in progress; 1 of 3 milestones done\)$' "$out" "a new-state table: the current item is the in-progress row, counted as done"
sed -i.bak 's/| planned |/| done |/; s/| in progress |/| done |/' "$r5/PLAN.md"; rm -f "$r5/PLAN.md.bak"
expect_grep '^   current item: none \(3 of 3 milestones done\)$' "$("$fs" --repo "$r5")" "a new-state table with every row done"

echo "$pass checks passed"
if [ "$fail" -gt 0 ]; then echo "$fail checks failed"; exit 1; fi
exit 0
