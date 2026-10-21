#!/usr/bin/env bash
# tests/ctlhq-repo-map/run.sh: checks for bin/ctlhq-repo-map in a scratch git repository.
# Prints "N checks passed" and exits 1 when any check fails. Writes only to a temp folder.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
rm_="$root/bin/ctlhq-repo-map"
pass=0
fail=0
ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL: $1"; }
expect_rc() { if [ "$1" -eq "$2" ]; then ok; else bad "$3 (expected exit $1, got $2)"; fi; }
expect_eq() { if [ "$1" = "$2" ]; then ok; else bad "$3 (expected '$1', got '$2')"; fi; }
expect_grep() { if printf '%s\n' "$2" | grep -Eq -- "$1"; then ok; else bad "$3 (no line matches: $1)"; fi; }
expect_nogrep() { if printf '%s\n' "$2" | grep -Eq -- "$1"; then bad "$3 (a line matches: $1)"; else ok; fi; }

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
tmp="$(mktemp -d "${TMPDIR:-/tmp}/repo-map-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
tmp="$(cd "$tmp" && pwd)"  # TMPDIR may end in a slash
repo="$tmp/repo"
mkdir -p "$repo/cmd/server" "$repo/docs" "$repo/bin" "$repo/tests/smoke" "$repo/.github/workflows" "$repo/config" "$repo/src"
cat > "$repo/package.json" <<'J'
{"name": "demo", "main": "src/index.js", "bin": {"demo": "bin/demo"},
 "scripts": {"start": "node src/index.js", "test": "node --test", "test:e2e": "playwright test", "lint": "eslint ."}}
J
printf 'console.log(process.env.API_KEY)\n' > "$repo/src/index.js"
printf 'export const x: number = 1\n' > "$repo/src/util.ts"
cat > "$repo/Makefile" <<'M'
.PHONY: build test
VERSION := 1
build:
	go build ./...
test: build
	go test ./...
%.o: %.c
	cc $<
M
printf 'module example.com/demo\n\ngo 1.21\n' > "$repo/go.mod"
printf 'package main\n\nfunc main() {}\n' > "$repo/cmd/server/main.go"
printf 'package lib\n' > "$repo/lib.go"
printf '#!/usr/bin/env bash\necho demo\n' > "$repo/bin/demo"; chmod +x "$repo/bin/demo"
printf 'not executable\n' > "$repo/bin/notes"
printf '#!/usr/bin/env bash\nexit 0\n' > "$repo/tests/smoke/run.sh"
printf '[project]\nname = "demo"\n\n[project.scripts]\ndemo-py = "demo.cli:main"\n\n[tool.pytest.ini_options]\naddopts = "-q"\n' > "$repo/pyproject.toml"
printf '# Demo\n\none two three four\n' > "$repo/README.md"
printf 'rule one\n' > "$repo/AGENTS.md"
printf 'five words in this doc\n' > "$repo/docs/intro.md"
printf 'deep\n' > "$repo/docs/nested.txt"
printf 'name: ci\non: push\n' > "$repo/.github/workflows/ci.yml"
printf 'DATABASE_URL=postgres://x\nPORT=8080\n# COMMENTED=1\nexport SECRET_TOKEN=\n' > "$repo/.env.example"
printf 'services:\n  web:\n    ports:\n      - "3000:3000"\n    environment:\n      - REDIS_URL=${REDIS_URL:-redis://localhost:6379}\n' > "$repo/docker-compose.yml"
printf 'server:\n  port: 9090\n' > "$repo/config/app.yaml"
printf 'ignored.md\n' > "$repo/.gitignore"
printf 'untracked doc\n' > "$repo/ignored.md"
git -C "$repo" init -q
git -C "$repo" add -A
git -C "$repo" -c user.name=t -c user.email=t@example.com commit -q -m init

# 1. --help and usage errors.
out="$("$rm_" --help 2>&1)"; expect_rc 0 $? "--help exits 0"
expect_grep '^ctlhq-repo-map: ' "$(printf '%s\n' "$out" | head -1)" "--help first line is 'ctlhq-repo-map: ...'"
expect_grep 'Set bars from a measurement' "$out" "--help quotes the AGENTS.md rule"
err="$("$rm_" --bogus 2>&1)"; expect_rc 2 $? "unknown option exits 2"
expect_grep '^ctlhq-repo-map: unknown option: --bogus$' "$err" "unknown option is named"
expect_grep '^fix: use --json, or no option' "$err" "unknown option gets a fix line"
err="$("$rm_" "$repo" "$repo" 2>&1)"; expect_rc 2 $? "two folders exit 2"
expect_grep "^fix: ctlhq-repo-map $repo\$" "$err" "two folders get a fix line with the first folder filled in"
err="$("$rm_" "$tmp/missing" 2>&1)"; expect_rc 2 $? "missing folder exits 2"
expect_grep "^ctlhq-repo-map: not a folder: $tmp/missing\$" "$err" "missing folder is named"
expect_grep "^fix: pass a folder that exists, for example: ctlhq-repo-map $tmp\$" "$err" "missing folder gets a fix line"
mkdir -p "$tmp/plain"
err="$("$rm_" "$tmp/plain" 2>&1)"; expect_rc 1 $? "non-git folder exits 1"
expect_grep "^ctlhq-repo-map: not a git repository: $tmp/plain\$" "$err" "non-git folder is named"
expect_grep '^why: ctlhq-repo-map maps tracked files only' "$err" "non-git folder says why"
expect_grep '^fix: ctlhq-repo-map <path to the repository>, or cd into the repository and run ctlhq-repo-map$' "$err" "non-git folder gets a fix line"
py="$(command -v python3)"
err="$(PATH=/var/empty "$py" "$rm_" "$repo" 2>&1)"; expect_rc 1 $? "no git on PATH exits 1"
expect_grep '^fix: install git' "$err" "no git on PATH gets a fix line"

# 2. Text report: seven numbered sections.
out="$("$rm_" "$repo")"; expect_rc 0 $? "map exits 0"
expect_grep '^ctlhq-repo-map: .*\(commit [0-9a-f]{7,}\)$' "$(printf '%s\n' "$out" | head -1)" "first line names the commit"
expect_eq 7 "$(printf '%s\n' "$out" | grep -cE '^## [1-7]\. ')" "seven numbered section headers"
expect_grep '^## 1\. Languages ' "$out" "section 1 is Languages"
expect_grep '^## 6\. Ports and env vars ' "$out" "section 6 is Ports and env vars"
expect_grep '^## 7\. Verification harness \(3\)$' "$out" "section 7 is Verification harness with three rows"
expect_grep '^\| 1 \| scripts/verify \| missing \|$' "$out" "no scripts/verify reads missing"
expect_grep '^\| 2 \| verify/features \| 0 feature map files \|$' "$out" "no feature map reads 0 files"
expect_grep '^\| 3 \| newest evidence \| none \|$' "$out" "no evidence folder reads none"
expect_grep '^\| # \| language \| files \|$' "$out" "tables lead with a # column"

# 3. Languages from tracked extensions.
expect_grep '^\| [0-9]+ \| Go \| 2 \|$' "$out" "Go counts 2 files"
expect_grep '^\| [0-9]+ \| TypeScript \| 1 \|$' "$out" "TypeScript counts 1 file"
expect_grep '^\| [0-9]+ \| Shell \| 2 \|$' "$out" "shebang scripts count as Shell"
expect_grep '^\| [0-9]+ \| Makefile \| 1 \|$' "$out" "Makefile counted by name"

# 4. Entry points.
expect_grep '\| package bin \| demo -> bin/demo \| package.json \|' "$out" "package.json bin"
expect_grep '\| package main \| src/index.js \| package.json \|' "$out" "package.json main"
expect_grep '\| package script \| start: node src/index.js \|' "$out" "package.json script"
expect_grep '\| python script \| demo-py -> demo.cli:main \| pyproject.toml \|' "$out" "pyproject script"
expect_grep '\| go main \| cmd/server \| cmd/server/main.go \|' "$out" "cmd/*/main.go"
expect_grep '\| make target \| build \| Makefile \|' "$out" "Makefile target build"
expect_nogrep '\| make target \| (VERSION|\.PHONY|%\.o) ' "$out" "variables, .PHONY and patterns are not targets"
expect_grep '\| bin/ executable \| demo \| bin/demo \|' "$out" "executable in bin/"
expect_nogrep 'bin/notes' "$out" "non-executable bin/ file skipped"

# 5. Test commands.
expect_grep '\| npm run test \| package.json \|' "$out" "npm test script"
expect_grep '\| npm run test:e2e \| package.json \|' "$out" "test* script"
expect_nogrep '\| npm run lint \|' "$out" "non-test script not a test command"
expect_grep '\| make test \| Makefile \|' "$out" "make test target"
expect_grep '\| go test \./\.\.\. \| go.mod \|' "$out" "go test from go.mod"
expect_grep '\| pytest \| pyproject.toml \|' "$out" "pytest from pyproject"
expect_grep '\| bash tests/smoke/run.sh \| tests/smoke/run.sh \|' "$out" "tests/*/run.sh"

# 6. Docs with word counts; .gitignore respected.
expect_grep '\| 6 \| README.md \|' "$out" "README word count 6"
expect_grep '\| 2 \| AGENTS.md \|' "$out" "AGENTS.md word count"
expect_grep '\| 5 \| docs/intro.md \|' "$out" "docs/*.md word count"
expect_nogrep 'docs/nested.txt|ignored.md' "$out" "non-md and ignored files skipped"

# 7. CI, ports and env vars.
expect_grep '\| \.github/workflows/ci\.yml \|' "$out" "GitHub workflow listed"
expect_grep '\| env \| DATABASE_URL \| \.env\.example \|' "$out" "env name from .env.example"
expect_grep '\| env \| SECRET_TOKEN \| \.env\.example \|' "$out" "export line in .env.example"
expect_nogrep 'COMMENTED' "$out" "commented env line skipped"
expect_grep '\| port \| 8080 \| \.env\.example \|' "$out" "PORT value from .env.example"
expect_grep '\| port \| 3000 \| docker-compose\.yml \|' "$out" "compose port mapping"
expect_grep '\| env \| REDIS_URL \| docker-compose\.yml \|' "$out" "compose \${VAR} reference"
expect_grep '\| port \| 6379 \| docker-compose\.yml \|' "$out" "localhost port in compose"
expect_grep '\| port \| 9090 \| config/app\.yaml \|' "$out" "port key in config/"

# 8. Subfolder, JSON, read-only, empty sections.
sub="$("$rm_" "$repo/docs")"; expect_rc 0 $? "subfolder exits 0"
expect_eq "$(printf '%s\n' "$out" | tail -n +2)" "$(printf '%s\n' "$sub" | tail -n +2)" "subfolder maps the whole repository"
js="$("$rm_" --json "$repo")"; expect_rc 0 $? "--json exits 0"
expect_eq "languages entry_points test_commands docs ci ports_env verification" \
  "$(printf '%s' "$js" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(" ".join(k for k in d if k not in ("root","commit")))')" "JSON has the seven sections"
expect_eq 2 "$(printf '%s' "$js" | python3 -c 'import json,sys; d=json.load(sys.stdin); print([r["files"] for r in d["languages"] if r["language"]=="Go"][0])')" "JSON Go count matches"
expect_eq "" "$(git -C "$repo" status --porcelain)" "work tree unchanged after runs"
empty="$tmp/empty"; mkdir -p "$empty"; git -C "$empty" init -q
eo="$("$rm_" "$empty")"; expect_rc 0 $? "empty repository exits 0"
expect_eq 6 "$(printf '%s\n' "$eo" | grep -c '^none found$')" "empty repository prints none found six times"
expect_grep '\(commit none\)' "$eo" "no commit prints none"

# 9. Verification harness facts, planted on disk (untracked, so the work tree check above is not affected).
h="$tmp/harness"; mkdir -p "$h/scripts" "$h/verify/features" "$h/.local/verify/20200101T000000Z" "$h/.local/verify/20261001T120000Z" "$h/.local/verify/notes"
git -C "$h" init -q
printf '#!/bin/sh\n' > "$h/scripts/verify"
printf 'a\n' > "$h/verify/features/a.md"; printf 'b\n' > "$h/verify/features/b.md"; printf 'c\n' > "$h/verify/features/c.txt"
ho="$("$rm_" "$h")"
expect_grep '^\| 1 \| scripts/verify \| present but not executable \|$' "$ho" "a scripts/verify without the x bit is named"
chmod +x "$h/scripts/verify"
ho="$("$rm_" "$h")"
expect_grep '^\| 1 \| scripts/verify \| present \|$' "$ho" "an executable scripts/verify reads present"
expect_grep '^\| 2 \| verify/features \| 2 feature map files \|$' "$ho" "only *.md files count as feature map files"
expect_grep '^\| 3 \| newest evidence \| \.local/verify/20261001T120000Z, [0-9]+ days? old \|$' "$ho" "the newest stamped folder is named with its age"
age="$(python3 -c 'import datetime as d; print((d.datetime.now(d.timezone.utc)-d.datetime(2026,10,1,12,tzinfo=d.timezone.utc)).days)')"
expect_grep "20261001T120000Z, $age days? old" "$ho" "the age in days matches the clock"
expect_eq ".local/verify/20261001T120000Z" "$("$rm_" --json "$h" | python3 -c 'import json,sys; print(json.load(sys.stdin)["verification"][2]["state"].split(",")[0])')" "--json verification names the newest folder"

total=$((pass + fail))
if [ "$fail" -gt 0 ]; then echo "$fail of $total checks failed"; exit 1; fi
echo "$pass checks passed"
