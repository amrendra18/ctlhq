#!/usr/bin/env bash
# tests/ctlhq-dep-age/run.sh: checks for skills/supply-chain/bin/ctlhq-dep-age through bin/ctlhq-dep-age.
# Offline: synthetic lockfiles, a --dates fixture, and a local HTTP server on 127.0.0.1 that
# stands in for the four registries. Prints "N checks passed" and exits 1 when any check fails.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
da="$root/bin/ctlhq-dep-age"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/dep-age-test.XXXXXX")"
srv_pid=""
cleanup() { if [ -n "$srv_pid" ]; then kill "$srv_pid" 2>/dev/null; wait "$srv_pid" 2>/dev/null; fi; rm -rf "$tmp"; }
trap cleanup EXIT
pass=0
fail=0
ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL: $1"; }
expect_rc() { if [ "$1" -eq "$2" ]; then ok; else bad "$3 (expected exit $1, got $2)"; fi; }
expect_eq() { if [ "$1" = "$2" ]; then ok; else bad "$3 (expected '$1', got '$2')"; fi; }
expect_grep() { if printf '%s\n' "$2" | grep -Eq -- "$1"; then ok; else bad "$3 (no line matches: $1)"; fi; }
row() { printf '%s\n' "$2" | awk -F'\t' -v p="$1" '$2==p {print $NF; exit}'; }

# Fixtures.
cat > "$tmp/package-lock.json" <<'EOF'
{"name":"app","lockfileVersion":3,"packages":{
 "":{"name":"app","version":"1.0.0"},
 "node_modules/left-pad":{"version":"1.3.0","resolved":"https://registry.npmjs.org/left-pad/-/left-pad-1.3.0.tgz"},
 "node_modules/fresh":{"version":"2.0.0","resolved":"https://registry.npmjs.org/fresh/-/fresh-2.0.0.tgz"},
 "node_modules/a/node_modules/@scope/b":{"version":"0.1.0","resolved":"https://registry.npmjs.org/@scope/b/-/b-0.1.0.tgz"},
 "node_modules/mirror":{"version":"1.0.0","resolved":"https://npm.example.com/mirror/-/mirror-1.0.0.tgz"},
 "node_modules/local":{"link":true,"resolved":"../local"}}}
EOF
mkdir -p "$tmp/v1"
cat > "$tmp/v1/package-lock.json" <<'EOF'
{"lockfileVersion":1,"dependencies":{"left-pad":{"version":"1.3.0","resolved":"https://registry.npmjs.org/left-pad/-/left-pad-1.3.0.tgz",
 "dependencies":{"inner":{"version":"0.0.1"}}},"gitdep":{"version":"git+https://github.com/x/y.git#abc"}}}
EOF
cat > "$tmp/pnpm-lock.yaml" <<'EOF'
lockfileVersion: '9.0'

importers:
  .:
    dependencies:
      left-pad:
        specifier: 1.3.0
        version: 1.3.0

packages:

  left-pad@1.3.0:
    resolution: {integrity: sha512-abc}

  '@scope/b@0.1.0(react@18.0.0)':
    resolution: {integrity: sha512-def}

  tarred@1.0.0:
    resolution: {tarball: https://evil.example.org/tarred-1.0.0.tgz}
EOF
cat > "$tmp/go.sum" <<'EOF'
github.com/BurntSushi/toml v1.3.2 h1:abc=
github.com/BurntSushi/toml v1.3.2/go.mod h1:def=
golang.org/x/text v0.3.0/go.mod h1:ghi=
EOF
cat > "$tmp/go.mod" <<'EOF'
module example.com/app

go 1.21

require (
	github.com/BurntSushi/toml v1.3.2
	example.com/forked v1.0.0 // indirect
)

replace example.com/forked => ../forked
EOF
cat > "$tmp/uv.lock" <<'EOF'
version = 1

[[package]]
name = "app"
version = "0.1.0"
source = { editable = "." }

[[package]]
name = "requests"
version = "2.31.0"
source = { registry = "https://pypi.org/simple" }

[[package]]
name = "private"
version = "1.0.0"
source = { registry = "https://pypi.internal.example/simple" }
EOF
cat > "$tmp/requirements.txt" <<'EOF'
# comment
requests[socks]==2.31.0 ; python_version >= "3.8" \
    --hash=sha256:abc
flask>=2.0
-e git+https://github.com/x/y.git#egg=ydep
EOF
cat > "$tmp/Cargo.lock" <<'EOF'
version = 3

[[package]]
name = "app"
version = "0.1.0"

[[package]]
name = "serde"
version = "1.0.190"
source = "registry+https://github.com/rust-lang/crates.io-index"

[[package]]
name = "gitcrate"
version = "0.1.0"
source = "git+https://github.com/x/gitcrate#abc"
EOF
printf 'npm\tleft-pad\t1.3.0\t2018-04-09\nnpm\tfresh\t2.0.0\t2026-10-10\nnpm\t@scope/b\t0.1.0\t2020-01-01\nnpm\tmirror\t1.0.0\t2020-01-01\n' > "$tmp/dates.tsv"
printf 'npm\tinner\t0.0.1\t2019-01-01\nnpm\ttarred\t1.0.0\t2020-01-01\n' >> "$tmp/dates.tsv"
printf 'go\tgithub.com/BurntSushi/toml\tv1.3.2\t2023-06-08\ngo\tgolang.org/x/text\tv0.3.0\t2017-12-14\ngo\texample.com/forked\tv1.0.0\t2020-01-01\n' >> "$tmp/dates.tsv"
printf 'pypi\trequests\t2.31.0\t2023-05-22\npypi\tprivate\t1.0.0\t2020-01-01\ncrates\tserde\t1.0.190\t2023-10-26\ncrates\tgitcrate\t0.1.0\t2020-01-01\n' >> "$tmp/dates.tsv"
off=(--offline --dates "$tmp/dates.tsv" --today 2026-10-16)

# 1. --help.
out="$("$da" --help 2>&1)"; expect_rc 0 $? "--help exits 0"
expect_grep '^ctlhq-dep-age: ' "$(printf '%s\n' "$out" | head -1)" "--help first line is 'ctlhq-dep-age: ...'"

# 2. package-lock.json v3: table, verdicts, exit 1 on a young package.
out="$("$da" "${off[@]}" "$tmp/package-lock.json")"; expect_rc 1 $? "package-lock with a young package exits 1"
expect_grep $'^#\tpackage\tversion\treleased\tage_days\tsource\tverdict$' "$out" "header row"
expect_eq 4 "$(printf '%s\n' "$out" | grep -Ec $'^[0-9]+\t')" "4 packages (root and link skipped)"
expect_eq ok "$(row left-pad "$out")" "left-pad ok"
expect_eq young "$(row fresh "$out")" "fresh (6 days) young"
expect_grep $'\tfresh\t2.0.0\t2026-10-10\t6\tregistry.npmjs.org\tyoung$' "$out" "fresh row has date, 6 days, source"
expect_eq ok "$(row @scope/b "$out")" "nested scoped package parsed"
expect_eq unofficial "$(row mirror "$out")" "mirror host flagged unofficial"
expect_grep $'\tnpm.example.com\tunofficial$' "$out" "unofficial host shown"
expect_grep '^4 packages read \(package-lock.json 4\), 2 flagged, 0 excepted, minimum 21 days, counted from 2026-10-16$' "$out" "summary line names the packages read per file"

# 3. --min-days 5 makes fresh ok; exceptions turn the rest into excepted, exit 0.
out="$("$da" "${off[@]}" --min-days 5 "$tmp/package-lock.json")"
expect_eq ok "$(row fresh "$out")" "--min-days 5: fresh ok"
printf '# approved by operator 2026-10-16\nmirror\t*\tinternal mirror, approved 2026-10-16\nfresh 2.0.0 security fix, approved\n' > "$tmp/exc.txt"
out="$("$da" "${off[@]}" --exceptions "$tmp/exc.txt" "$tmp/package-lock.json")"; expect_rc 0 $? "all flags excepted exits 0"
expect_eq excepted "$(row fresh "$out")" "fresh excepted"
expect_eq excepted "$(row mirror "$out")" "mirror excepted by *"
expect_grep '2 excepted' "$out" "summary counts excepted"

# 4. package-lock v1 (nested deps, git version).
out="$("$da" "${off[@]}" "$tmp/v1/package-lock.json")"
expect_eq ok "$(row inner "$out")" "v1 nested dependency read"
expect_eq unofficial "$(row gitdep "$out")" "v1 git dependency unofficial"

# 5. pnpm-lock.yaml v9: keys, peer suffix, tarball host.
out="$("$da" "${off[@]}" "$tmp/pnpm-lock.yaml")"
expect_eq 3 "$(printf '%s\n' "$out" | grep -Ec $'^[0-9]+\t')" "pnpm: 3 packages (importers skipped)"
expect_eq ok "$(row @scope/b "$out")" "pnpm scoped key with peer suffix"
expect_grep $'\ttarred\t1.0.0\t.*\tevil.example.org\tunofficial$' "$out" "pnpm tarball host unofficial"

# 6. go.sum dedupes /go.mod lines; go.mod replace is unofficial.
out="$("$da" "${off[@]}" "$tmp/go.sum")"; expect_rc 0 $? "go.sum clean exits 0"
expect_eq 2 "$(printf '%s\n' "$out" | grep -Ec $'^[0-9]+\t')" "go.sum: 2 modules"
out="$("$da" "${off[@]}" "$tmp/go.mod")"
expect_eq ok "$(row github.com/BurntSushi/toml "$out")" "go.mod require read"
expect_eq unofficial "$(row example.com/forked "$out")" "go.mod local replace unofficial"
expect_grep $'\tfile\tunofficial$' "$out" "replace source shown as file"

# 7. uv.lock: editable skipped, other index unofficial.
out="$("$da" "${off[@]}" "$tmp/uv.lock")"
expect_eq 2 "$(printf '%s\n' "$out" | grep -Ec $'^[0-9]+\t')" "uv.lock: 2 packages (editable skipped)"
expect_eq ok "$(row requests "$out")" "uv requests ok"
expect_grep $'\tpypi.internal.example\tunofficial$' "$out" "uv private index unofficial"

# 8. requirements.txt: pinned with extras and marker, unpinned, editable git.
out="$("$da" "${off[@]}" "$tmp/requirements.txt")"
expect_eq ok "$(row requests "$out")" "requirements pinned line with extras, marker, hash"
expect_eq unpinned "$(row flask "$out")" "requirements >= is unpinned"
expect_eq unofficial "$(row ydep "$out")" "requirements -e git unofficial"

# 9. Cargo.lock: workspace member skipped, git source unofficial.
out="$("$da" "${off[@]}" "$tmp/Cargo.lock")"
expect_eq 2 "$(printf '%s\n' "$out" | grep -Ec $'^[0-9]+\t')" "Cargo: 2 packages"
expect_eq ok "$(row serde "$out")" "Cargo serde ok"
expect_eq unofficial "$(row gitcrate "$out")" "Cargo git unofficial"

# 10. Missing date is not-found; --pkg; --json; default lockfile discovery.
out="$("$da" "${off[@]}" --pkg npm:left-pad@9.9.9 --pkg pypi:requests@2.31.0)"; expect_rc 1 $? "not-found exits 1"
expect_grep $'\tleft-pad\t9.9.9\t-\t-\tregistry.npmjs.org\tnot-found$' "$out" "--pkg not-found row"
json="$("$da" "${off[@]}" --json "$tmp/Cargo.lock")"
expect_eq "2 1 gitcrate" "$(printf '%s' "$json" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["summary"]["packages"], d["summary"]["flagged"], [r["package"] for r in d["rows"] if r["verdict"]!="ok"][0])')" "--json summary and rows"
out="$(cd "$tmp" && "$da" "${off[@]}" 2>&1)"
expect_grep '^[0-9]+ packages read \(' "$out" "no LOCKFILE reads the lockfiles in the current folder"
expect_eq 18 "$(printf '%s\n' "$out" | grep -Ec $'^[0-9]+\t')" "all 7 lockfiles found: 18 rows"

# 11. Usage errors exit 2.
"$da" --offline "$tmp/go.sum" >/dev/null 2>&1; expect_rc 2 $? "--offline without --dates exits 2"
"$da" "${off[@]}" "$tmp/nope.lock" >/dev/null 2>&1; expect_rc 2 $? "missing lockfile exits 2"
"$da" "${off[@]}" --pkg left-pad >/dev/null 2>&1; expect_rc 2 $? "bad --pkg exits 2"
mkdir -p "$tmp/empty"; (cd "$tmp/empty" && "$da" --today 2026-10-16 >/dev/null 2>&1); expect_rc 2 $? "no lockfile anywhere exits 2"
"$da" --bogus >/dev/null 2>&1; expect_rc 2 $? "unknown option exits 2"
echo '{broken' > "$tmp/empty/package-lock.json"; "$da" "${off[@]}" "$tmp/empty/package-lock.json" >/dev/null 2>&1; expect_rc 2 $? "broken JSON exits 2"

# 12. Network path against a local server shaped like the real registries.
mkdir -p "$tmp/www/npm" "$tmp/www/pypi/requests/2.31.0" "$tmp/www/go/github.com/!burnt!sushi/toml/@v" "$tmp/www/crates/serde/1.0.190"
echo '{"time":{"1.3.0":"2018-04-09T01:25:04.391Z"}}' > "$tmp/www/npm/left-pad"
echo '{"urls":[{"upload_time_iso_8601":"2023-05-22T15:12:44.175115Z"},{"upload_time_iso_8601":"2023-05-22T15:12:42.313790Z"}]}' > "$tmp/www/pypi/requests/2.31.0/json"
echo '{"Version":"v1.3.2","Time":"2023-06-08T06:13:35Z"}' > "$tmp/www/go/github.com/!burnt!sushi/toml/@v/v1.3.2.info"
echo '{"version":{"created_at":"2023-10-26T22:28:05.110063+00:00"}}' > "$tmp/www/crates/serde/1.0.190/index"
port="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')"
(cd "$tmp/www" && exec python3 -m http.server "$port" --bind 127.0.0.1 >/dev/null 2>&1) &
srv_pid=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do curl -s "http://127.0.0.1:$port/" >/dev/null 2>&1 && break; sleep 0.3; done
base="http://127.0.0.1:$port"
out="$(DEP_AGE_NPM_URL="$base/npm/{name}" DEP_AGE_PYPI_URL="$base/pypi/{name}/{version}/json" \
	DEP_AGE_GO_URL="$base/go/{name}/@v/{version}.info" DEP_AGE_CRATES_URL="$base/crates/{name}/{version}/index" \
	"$da" --today 2026-10-16 --pkg npm:left-pad@1.3.0 --pkg pypi:requests@2.31.0 \
	--pkg go:github.com/BurntSushi/toml@v1.3.2 --pkg crates:serde@1.0.190 --pkg npm:nosuch@1.0.0)"; rc=$?
expect_rc 1 "$rc" "network run with one missing package exits 1"
expect_grep $'\tleft-pad\t1.3.0\t2018-04-09\t3112\t' "$out" "npm time read from registry document"
expect_grep $'\trequests\t2.31.0\t2023-05-22\t' "$out" "pypi earliest upload read"
expect_grep $'\tgithub.com/BurntSushi/toml\tv1.3.2\t2023-06-08\t' "$out" "go module path escaped (!burnt!sushi)"
expect_grep $'\tserde\t1.0.190\t2023-10-26\t' "$out" "crates created_at read"
expect_eq not-found "$(row nosuch "$out")" "HTTP 404 is not-found"

# 13. Network down exits 3 and says so.
err="$(DEP_AGE_NPM_URL="http://127.0.0.1:9/{name}" "$da" --timeout 2 --pkg npm:left-pad@1.3.0 2>&1 >/dev/null)"; rc=$?
expect_rc 3 "$rc" "unreachable registry exits 3"
expect_grep '^ctlhq-dep-age: network unavailable .*No verdict' "$err" "exit 3 message says network unavailable"

# 14. --file: checksum match, mismatch, signature, nothing.
mkdir -p "$tmp/dl"; printf 'installer\n' > "$tmp/dl/setup.sh"
sum="$(python3 -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$tmp/dl/setup.sh")"
out="$("$da" --file "$tmp/dl/setup.sh")"; expect_rc 1 $? "--file with nothing next to it exits 1"
expect_grep "^sha256	$sum$" "$out" "--file prints the SHA-256"
expect_grep '^verdict	no checksum or signature' "$out" "--file says nothing is next to it"
printf '%s  setup.sh\n' "$sum" > "$tmp/dl/SHA256SUMS"
out="$("$da" --file "$tmp/dl/setup.sh")"; expect_rc 0 $? "--file with matching SHA256SUMS exits 0"
expect_grep $'^checksum\tSHA256SUMS\tmatches$' "$out" "SHA256SUMS matches"
printf '%064d  setup.sh\n' 0 > "$tmp/dl/SHA256SUMS"
out="$("$da" --file "$tmp/dl/setup.sh")"; expect_rc 1 $? "--file mismatch exits 1"
expect_grep 'MISMATCH' "$out" "mismatch is shown"
rm "$tmp/dl/SHA256SUMS"; touch "$tmp/dl/setup.sh.asc"
out="$("$da" --file "$tmp/dl/setup.sh")"; expect_rc 1 $? "--file with only an empty signature exits 1"
expect_grep $'^signature\tsetup.sh.asc\tempty \(0 bytes\)' "$out" "empty signature reported as empty"
echo 'sig' > "$tmp/dl/setup.sh.asc"
out="$("$da" --file "$tmp/dl/setup.sh")"; expect_rc 1 $? "--file with a signature alone exits 1"
expect_grep $'^signature\tsetup.sh.asc\tpresent, not verified' "$out" "signature listed, not verified"
expect_grep '^verdict	no matching SHA-256 .*signature alone is not accepted' "$out" "signature alone is reported, not accepted"
rm "$tmp/dl/setup.sh.asc"

# 15. --file: a signed checksum list that does not name the download (review wave 3, defect 3).
printf '%064d  other.tar.gz\n' 1 > "$tmp/dl/SHA256SUMS"; echo 'sig' > "$tmp/dl/SHA256SUMS.asc"
out="$("$da" --file "$tmp/dl/setup.sh")"; expect_rc 1 $? "--file: signed list without this file exits 1"
expect_grep $'^checksum\tSHA256SUMS\tdoes not name this file$' "$out" "list that does not name the file is shown"
expect_grep $'^signature\tSHA256SUMS.asc\tsigns SHA256SUMS, which does not name this file$' "$out" "signature over that list is not counted"
printf '%s  setup.sh.bak\n' "$sum" > "$tmp/dl/SHA256SUMS"
"$da" --file "$tmp/dl/setup.sh" >/dev/null; expect_rc 1 $? "--file: a longer name containing the file name does not count"
printf '%s *setup.sh\n' "$sum" > "$tmp/dl/SHA256SUMS"
out="$("$da" --file "$tmp/dl/setup.sh")"; expect_rc 0 $? "--file: matching SHA-256 line (binary-mode star) exits 0"
expect_grep $'^signature\tSHA256SUMS.asc\tpresent, not verified .*it signs SHA256SUMS$' "$out" "signature over a list naming the file is listed"
rm "$tmp/dl/SHA256SUMS" "$tmp/dl/SHA256SUMS.asc"
printf '%s\n' "$sum" > "$tmp/dl/setup.sh.sha256"
"$da" --file "$tmp/dl/setup.sh" >/dev/null; expect_rc 0 $? "--file: <file>.sha256 with a bare matching hash exits 0"
rm "$tmp/dl/setup.sh.sha256"
"$da" --file "$tmp/dl/none" >/dev/null 2>&1; expect_rc 2 $? "--file missing exits 2"

# 16. requirements -r and -c includes are followed; 0 packages is not clean (defect 2).
mkdir -p "$tmp/req/sub"
printf -- '-r base.txt\n--constraint sub/pins.txt\n' > "$tmp/req/requirements.txt"
printf 'fresh==2.0.0\n-r requirements.txt\n' > "$tmp/req/base.txt"
printf 'left-pad==1.3.0\n' > "$tmp/req/sub/pins.txt"
printf 'pypi\tfresh\t2.0.0\t2026-10-15\npypi\tleft-pad\t1.3.0\t2018-04-09\n' > "$tmp/req/dates.tsv"
roff=(--offline --dates "$tmp/req/dates.tsv" --today 2026-10-16)
out="$("$da" "${roff[@]}" "$tmp/req/requirements.txt")"; expect_rc 1 $? "-r include with a young package exits 1"
expect_eq young "$(row fresh "$out")" "-r base.txt read relative to the including file"
expect_eq ok "$(row left-pad "$out")" "--constraint sub/pins.txt read"
expect_grep '^2 packages read \(requirements.txt 0, base.txt 1, pins.txt 1\), 1 flagged' "$out" "summary counts each file read"
printf -- '-r missing.txt\n' > "$tmp/req/bad.txt"
"$da" "${roff[@]}" "$tmp/req/bad.txt" >/dev/null 2>&1; expect_rc 2 $? "missing include exits 2"
: > "$tmp/req/requirements.txt"
out="$("$da" "${roff[@]}" "$tmp/req/requirements.txt" 2>"$tmp/err")"; expect_rc 1 $? "empty requirements.txt exits 1"
expect_grep 'requirements.txt: 0 packages read, so nothing was checked there' "$(cat "$tmp/err")" "empty lockfile named on stderr"
expect_grep '^0 packages read \(requirements.txt 0\), 0 flagged' "$out" "summary shows 0 read"
"$da" "${roff[@]}" --allow-empty "$tmp/req/requirements.txt" >/dev/null 2>&1; expect_rc 0 $? "--allow-empty accepts an empty lockfile"
echo '{"name":"app","lockfileVersion":3,"packages":{"":{"name":"app","version":"1.0.0"}}}' > "$tmp/req/package-lock.json"
"$da" "${roff[@]}" "$tmp/req/package-lock.json" >/dev/null 2>&1; expect_rc 1 $? "package-lock with only the root exits 1"
json="$("$da" "${roff[@]}" --json "$tmp/req/package-lock.json" 2>/dev/null)"
expect_eq "0 1" "$(printf '%s' "$json" | python3 -c 'import json,sys; d=json.load(sys.stdin)["summary"]; print(d["packages"], len(d["empty"]))')" "--json names the empty lockfile"

# 17. A registry reply that is not JSON is exit 3 with one line, no traceback (defect 4).
echo '<html>login</html>' > "$tmp/www/npm/portal"
err="$(DEP_AGE_NPM_URL="$base/npm/portal" "$da" --today 2026-10-16 --pkg npm:left-pad@1.3.0 2>&1 >/dev/null)"; rc=$?
expect_rc 3 "$rc" "HTML registry reply exits 3"
expect_grep '^ctlhq-dep-age: unreadable registry reply \(127.0.0.1 answered with something that is not JSON' "$err" "HTML reply names the host"
expect_eq 1 "$(printf '%s\n' "$err" | grep -c .)" "HTML reply is one line"
expect_eq 0 "$(printf '%s\n' "$err" | grep -c Traceback)" "no traceback"

echo "$pass checks passed"
[ "$fail" -eq 0 ] || { echo "$fail checks failed"; exit 1; }
