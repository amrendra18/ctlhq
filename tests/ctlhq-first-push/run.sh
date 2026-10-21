#!/usr/bin/env bash
# tests/ctlhq-first-push/run.sh: checks for bin/ctlhq-first-push on scratch repositories built here.
# Prints "N checks passed" and exits 1 when any check fails. Writes only under a temporary folder.
# Planted values are assembled at run time, so this file itself holds no email, home path, or token.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
fp="$root/bin/ctlhq-first-push"
pass=0
fail=0
ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL: $1"; }
expect_rc() { # expected actual label
	if [ "$1" -eq "$2" ]; then ok; else bad "$3 (expected exit $1, got $2)"; fi
}
expect_grep() { # pattern text label
	if printf '%s\n' "$2" | grep -Eq -- "$1"; then ok; else bad "$3 (no line matches: $1)"; printf '%s\n' "$2" | sed 's/^/    /' | head -20; fi
}
expect_nogrep() { # pattern text label
	if printf '%s\n' "$2" | grep -Eq -- "$1"; then bad "$3 (a line matches: $1)"; else ok; fi
}
expect_fix() { # rule pattern text label: the line right under the rule's first finding is a fix: line matching pattern
	local fixline
	fixline="$(printf '%s\n' "$3" | awk -v r="$1" 'found { print; exit } $0 ~ /^[0-9]+\. / && (index($0, "  " r) > 0) { found = 1 }')"
	if printf '%s\n' "$fixline" | grep -Eq -- "^   fix: .*$2"; then ok; else bad "$4 (fix line under $1 does not match: $2)"; printf '    %s\n' "$fixline"; fi
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home" # never read the operator's real settings or gitleaks
mkdir -p "$HOME/.ctlhq"
settings="$HOME/.ctlhq/first-push.toml"
printf 'github_owner = "acme"\n' > "$settings"
all_out="$tmp/all-output.txt"
: > "$all_out"

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME="Test Author" GIT_COMMITTER_NAME="Test Author"
export GIT_AUTHOR_EMAIL="author@example.com" GIT_COMMITTER_EMAIL="author@example.com"
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
unset FIRST_PUSH_CONFIG

at="@"
private1="Zorblax"
private2="octoname"
email_bad="jane.roe${at}realmail.net"
email_public="press${at}realmail.net"
email_noreply="12345+someone${at}users.noreply.github.com"
home_path="/Use""rs/someone/notes.txt"
key_line="-----BEGIN OPENSSH PRIVATE"" KEY-----"
gh_token="ghp""_abcdefghijklmnopqrstuvwxyz0123456789"
aws_key="AKIA""ABCDEFGHIJKLMNOP"
ssh_fp="SHA""256:abcdefghijklmnopqrstuvwxyz0123456789ABCDEFG"

sha() { python3 -c 'import hashlib,sys; print(hashlib.sha256(sys.argv[1].encode()).hexdigest())' "$1"; }

commit() { # dir message
	git -C "$1" add -A && git -C "$1" -c commit.gpgsign=false commit -q -m "$2"
}

newrepo() { # dir [nolicense] [noreadme]: a clean repository with policy, README, LICENSE
	local d="$1"
	git init -q -b main "$d"
	printf '.local/\n' > "$d/.gitignore"
	mkdir -p "$d/.local/first-commit"
	printf '# private values\n%s\n%s\n' "$private1" "$private2" > "$d/.local/first-commit/private-values.txt"
	printf '{"schema_version": 1}\n' > "$d/.repo-policy.json"
	case " $* " in *" noreadme "*) ;; *) printf '# Demo\n' > "$d/README.md" ;; esac
	case " $* " in *" nolicense "*) ;; *) printf 'MIT License\n' > "$d/LICENSE" ;; esac
	printf 'print("hi")\n' > "$d/main.py"
	commit "$d" "initial"
}

policy() { # dir json
	printf '%s\n' "$2" > "$1/.repo-policy.json"
}

run() { # dir args...: sets out and rc; records all output
	local d="$1"; shift
	out="$("$fp" --root "$d" "$@" 2>"$tmp/stderr")"; rc=$?
	err="$(cat "$tmp/stderr")"
	printf '%s\n%s\n' "$out" "$err" >> "$all_out"
}

n=0
next_dir() { n=$((n + 1)); d="$tmp/r$n"; }

# 1. --help, usage, environment.
out="$("$fp" --help 2>&1)"; expect_rc 0 $? "--help exits 0"
expect_grep '^ctlhq-first-push: ' "$(printf '%s\n' "$out" | head -1)" "--help first line is 'ctlhq-first-push: ...'"
"$fp" --bogus >/dev/null 2>&1; expect_rc 2 $? "unknown argument exits 2"
"$fp" hook >/dev/null 2>&1; expect_rc 2 $? "hook without action exits 2"
mkdir -p "$tmp/plain"
err="$("$fp" --root "$tmp/plain" 2>&1 >/dev/null)"; expect_rc 3 $? "not a git repository exits 3"
expect_grep '^ctlhq-first-push: .*/plain is not inside a git repository with a work tree$' "$err" "not a git repository: what, with the folder"
expect_grep '^why: ctlhq-first-push reads the commits a push would send' "$err" "not a git repository: why"
expect_grep '^fix: cd into the repository and run ctlhq-first-push, or run ctlhq-first-push --root <path to the repository>' "$err" "not a git repository: fix"
err="$("$fp" --root "$tmp/nonexist" 2>&1 >/dev/null)"; expect_rc 3 $? "a --root that is not a folder exits 3"
expect_grep '^ctlhq-first-push: --root .*/nonexist is not a folder$' "$err" "--root not a folder: what"
expect_grep '^fix: Pass the repository folder: ctlhq-first-push --root <path to the repository>\.$' "$err" "--root not a folder: fix"
err="$("$fp" --root "$HOME/first-push-test-no-such-folder" 2>&1 >/dev/null)"
expect_grep '^ctlhq-first-push: --root ~/first-push-test-no-such-folder is not a folder$' "$err" "a path under the home folder is shown with ~"
expect_nogrep "$HOME/" "$err" "the home folder path is not printed"
git init -q -b main "$tmp/empty"
err="$("$fp" --root "$tmp/empty" 2>&1 >/dev/null)"; expect_rc 3 $? "no commits exits 3"
expect_grep '^ctlhq-first-push: the repository at .*/empty has no commits$' "$err" "no commits: what"
expect_grep '^why: A push sends commits' "$err" "no commits: why"
expect_grep '^fix \(operator decides\): Add the files by name \(git add README\.md LICENSE <files>\) and commit them through the project.s commit sequence \(git commit -F <message file>\)' "$err" "no commits: the fix that commits is marked as the operator's decision"
expect_nogrep 'commit -m' "$err" "no commits: the fix does not suggest git commit -m"

# 2. Clean repository: ready, exit 0, notes for gitleaks and the push target.
next_dir; newrepo "$d"
run "$d"
expect_rc 0 "$rc" "clean repository exits 0"
expect_grep '^ready$' "$(printf '%s\n' "$out" | tail -2 | head -1)" "clean repository prints ready before the next line"
expect_grep '^next: ctlhq-first-push hook install$' "$(printf '%s\n' "$out" | tail -1)" "ready output ends with ctlhq-first-push hook install while the hook is missing"
expect_grep 'gitleaks not installed: built-in token shapes only' "$out" "missing gitleaks is said"
expect_grep 'push target not checked \(no remote named origin\)' "$out" "missing origin is said"
run "$d" --json
expect_rc 0 "$rc" "clean --json exits 0"
expect_grep '^True 0 1 full history not installed$' "$(printf '%s' "$out" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["ready"], len(d["findings"]), d["commits_checked"], d["mode"], d["gitleaks"])')" "clean --json fields"

# 3. Planted and allowed case per personal-data rule (one file each).
plant() { # rule content label
	local d; next_dir; newrepo "$d"
	printf 'line one\n%s\n' "$2" > "$d/notes.txt"; commit "$d" "add notes"
	run "$d"
	expect_rc 1 "$rc" "$3 planted exits 1"
	expect_grep "^[0-9]+\. [0-9a-f]{7}  notes\.txt:2  $1\$" "$out" "$3 planted is reported at notes.txt:2"
	expect_grep '^not ready$' "$(printf '%s\n' "$out" | tail -2 | head -1)" "$3 planted prints not ready"
	expect_fix "$1" "$4" "$out" "$3 planted has a fix line naming the action and notes.txt line 2"
}
allow_detector() { # rule content label: a privacy_detector_exceptions entry approves the line
	local d; next_dir; newrepo "$d"
	policy "$d" "{\"schema_version\": 1, \"privacy_detector_exceptions\": [{\"path\": \"notes.txt\", \"line\": 2, \"rule\": \"$1\", \"sha256\": \"$(sha "$2")\", \"reason\": \"test\"}]}"
	printf 'line one\n%s\n' "$2" > "$d/notes.txt"; commit "$d" "add notes"
	run "$d"
	expect_rc 0 "$rc" "$3 allowed by exception exits 0"
}
plant privacy.unapproved-email "contact $email_bad" "email" 'Remove it from notes\.txt line 2, or add the address to public_emails in \.repo-policy\.json'
plant privacy.user-home-path "see $home_path" "home path" 'Remove it from notes\.txt line 2, or approve this exact line with a privacy_detector_exceptions entry'
plant privacy.private-key "$key_line" "private key" 'Revoke and replace the key or token first, then remove it from notes\.txt line 2'
plant privacy.github-token "token = $gh_token" "github token" 'Revoke and replace the key or token first, then remove it from notes\.txt line 2'
plant privacy.aws-access-key "key = $aws_key" "aws key" 'Revoke and replace the key or token first, then remove it from notes\.txt line 2'
plant privacy.ssh-fingerprint "fp $ssh_fp" "ssh fingerprint" 'Remove it from notes\.txt line 2, or approve this exact line'
plant privacy.private-literal "written by zorblax" "private value (case-folded)" 'Remove it from notes\.txt line 2, or add the value to public_terms in ~/\.ctlhq/first-push\.toml if it is public\. Then run `git commit --amend`'
allow_detector privacy.unapproved-email "contact $email_bad" "email"
allow_detector privacy.user-home-path "see $home_path" "home path"
allow_detector privacy.private-key "$key_line" "private key"
allow_detector privacy.github-token "token = $gh_token" "github token"
allow_detector privacy.aws-access-key "key = $aws_key" "aws key"
allow_detector privacy.ssh-fingerprint "fp $ssh_fp" "ssh fingerprint"

# 3b. Emails allowed by policy: public_emails, the contributor record, no-reply, example domain.
next_dir; newrepo "$d"
policy "$d" "{\"schema_version\": 1, \"public_emails\": [\"$email_public\"]}"
printf '{"schema_version": 1, "name": "Me", "email": "%s", "signing_key": "key"}\n' "$email_bad" > "$d/.local/first-commit/contributor.json"
printf 'a %s\nb %s\nc %s\nd demo%sexample.com\n' "$email_public" "$email_bad" "$email_noreply" "$at" > "$d/notes.txt"; commit "$d" "add notes"
run "$d"
expect_rc 0 "$rc" "public, contributor, no-reply, and example emails are allowed"

# 3c. Private literal: content-matched, count-bound exception; survives a moved line, not a changed one.
next_dir; newrepo "$d"
line="owner zorblax here"
policy "$d" "{\"schema_version\": 1, \"private_literal_exceptions\": [{\"path\": \"notes.txt\", \"line\": 1, \"sha256\": \"$(sha "$line")\", \"reason\": \"test\"}]}"
printf '%s\n' "$line" > "$d/notes.txt"; commit "$d" "one copy"
run "$d"; expect_rc 0 "$rc" "private literal approved by exception exits 0"
printf 'new first line\n%s\n' "$line" > "$d/notes.txt"; commit "$d" "moved line"
run "$d"; expect_rc 0 "$rc" "approved private literal still approved after the line moves"
printf '%s\n%s\n' "$line" "$line" > "$d/notes.txt"; commit "$d" "two copies"
run "$d"; expect_rc 1 "$rc" "a second copy exceeds the exception count"
expect_grep '  notes\.txt:2  privacy\.private-literal$' "$out" "the second copy is reported at line 2"
next_dir; newrepo "$d"
policy "$d" "{\"schema_version\": 1, \"private_literal_exceptions\": [{\"path\": \"notes.txt\", \"line\": 1, \"sha256\": \"$(sha "$line")\", \"reason\": \"test\"}]}"
printf '%s!\n' "$line" > "$d/notes.txt"; commit "$d" "changed text"
run "$d"; expect_rc 1 "$rc" "changed line text is not approved"

# 3d. public_github_owner_urls: the owner in a GitHub URL is allowed only with the flag.
next_dir; newrepo "$d"
printf 'see https://github.com/%s/tool\n' "$private2" > "$d/notes.txt"; commit "$d" "owner url"
run "$d"; expect_rc 1 "$rc" "owner URL without the flag exits 1"
expect_grep '  notes\.txt:1  privacy\.private-literal$' "$out" "owner URL without the flag is a private literal"
policy "$d" '{"schema_version": 1, "public_github_owner_urls": true}'
run "$d"; expect_rc 0 "$rc" "owner URL with public_github_owner_urls exits 0"
printf 'see https://github.com/%s/tool and %s alone\n' "$private2" "$private2" > "$d/notes.txt"; commit "$d" "owner outside url"
run "$d"; expect_rc 1 "$rc" "the owner outside a URL is still a finding with the flag"

# 3e. Forbidden paths and immutable vendor files.
next_dir; newrepo "$d"
policy "$d" '{"schema_version": 1, "forbidden_paths": [{"match": "prefix", "value": "secrets/", "reason": "test"}]}'
mkdir -p "$d/secrets" "$d/public"; printf 'x\n' > "$d/secrets/a.txt"; printf 'x\n' > "$d/public/a.txt"; commit "$d" "paths"
run "$d"; expect_rc 1 "$rc" "forbidden path exits 1"
expect_grep '  secrets/a\.txt  privacy\.forbidden-path$' "$out" "forbidden path is reported"
expect_fix privacy.forbidden-path 'Run `git rm --cached` on secrets/a\.txt and add it to \.gitignore' "$out" "forbidden path fix names the file"
expect_nogrep 'public/a\.txt' "$out" "a path outside the forbidden prefix is allowed"
next_dir; newrepo "$d"
mkdir -p "$d/vendor"; printf 'path = "%s"\n' "$home_path" > "$d/vendor/lib.js"
vsha="$(python3 -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$d/vendor/lib.js")"
policy "$d" "{\"schema_version\": 1, \"immutable_vendor_files\": [{\"path\": \"vendor/lib.js\", \"sha256\": \"$vsha\", \"reason\": \"test\"}]}"
commit "$d" "vendor"
run "$d"; expect_rc 0 "$rc" "immutable vendor file with matching hash is allowed"
printf 'path = "%s" changed\n' "$home_path" > "$d/vendor/lib.js"; commit "$d" "vendor edit"
run "$d"; expect_rc 1 "$rc" "vendor file with a changed hash is checked"
expect_grep '  vendor/lib\.js:1  privacy\.user-home-path$' "$out" "changed vendor file reports the home path"

# 3f. Messages and identities.
next_dir; newrepo "$d"
printf 'x\n' > "$d/a.txt"; commit "$d" "$(printf 'subject\n\nmail %s' "$email_bad")"
run "$d"; expect_rc 1 "$rc" "email in a message exits 1"
expect_grep '  message:3  privacy\.unapproved-email$' "$out" "message finding names message:3"
expect_fix privacy.unapproved-email 'Reword line 3 of the message of commit [0-9a-f]{7}' "$out" "message finding fix says to reword line 3"
next_dir; newrepo "$d"
printf 'x\n' > "$d/a.txt"; commit "$d" "$(printf 'subject\n\nthanks %s' "$email_noreply")"
run "$d"; expect_rc 0 "$rc" "no-reply email in a message is allowed"
next_dir; newrepo "$d"
printf 'x\n' > "$d/a.txt"
GIT_AUTHOR_EMAIL="$email_bad" GIT_COMMITTER_NAME="Zorblax Q" commit "$d" "identity"
printf 'y\n' > "$d/b.txt"
GIT_AUTHOR_EMAIL="$email_bad" commit "$d" "identity again"
run "$d"; expect_rc 1 "$rc" "unapproved author email exits 1"
expect_grep '  identity:author  privacy\.unapproved-email \(\+1 more commit\)$' "$out" "author email reported once with a repeat count"
expect_grep '  identity:committer  privacy\.private-literal$' "$out" "private value in the committer name is reported"
expect_fix privacy.unapproved-email 'Set a public author identity .*git config user\.email.* Commit [0-9a-f]{7} already holds it' "$out" "identity fix names git config and the history rewrite"
next_dir; newrepo "$d"
printf 'x\n' > "$d/a.txt"; GIT_AUTHOR_EMAIL="$email_noreply" GIT_COMMITTER_EMAIL="$email_noreply" commit "$d" "noreply identity"
run "$d"; expect_rc 0 "$rc" "no-reply identity is allowed"

# 3f2. Identity name and email are checked separately: an allowed no-reply email allows its account name.
noreply_own="12345+${private2}${at}users.noreply.github.com"
own_noreply_repo() { # dir: newrepo with a .repo-policy.json that allows the own no-reply email
	newrepo "$1"
	local email_line="\"$noreply_own\""
	printf '{"schema_version": 1, "public_emails": [\n%s\n],\n"private_literal_exceptions": [{"path": ".repo-policy.json", "line": 2, "sha256": "%s", "reason": "own no-reply email"}]}\n' "$email_line" "$(sha "$email_line")" > "$1/.repo-policy.json"
	commit "$1" "own no-reply policy"
}
next_dir; own_noreply_repo "$d"
printf 'x\n' > "$d/a.txt"
GIT_AUTHOR_NAME="OctoName" GIT_AUTHOR_EMAIL="$(printf '%s' "$noreply_own" | tr a-z A-Z)" GIT_COMMITTER_NAME="$private2" GIT_COMMITTER_EMAIL="$noreply_own" commit "$d" "own identity"
run "$d"; expect_rc 0 "$rc" "allowed no-reply email plus its account name is not a finding"; [ "$rc" -eq 0 ] || printf "%s\n" "$out" | sed "s/^/    /"
next_dir; own_noreply_repo "$d"
printf 'x\n' > "$d/a.txt"
GIT_AUTHOR_NAME="$private2" GIT_AUTHOR_EMAIL="$email_bad" commit "$d" "own name, other email"
run "$d"; expect_rc 1 "$rc" "account name with an unapproved email exits 1"
expect_grep '  identity:author  privacy\.unapproved-email$' "$out" "the unapproved email is still reported"
expect_nogrep 'identity:author  privacy\.private-literal' "$out" "the allowed account name is not reported"
next_dir; own_noreply_repo "$d"
printf 'x\n' > "$d/a.txt"
GIT_AUTHOR_NAME="Zorblax Q" GIT_AUTHOR_EMAIL="$noreply_own" commit "$d" "other name"
run "$d"; expect_rc 1 "$rc" "a private value in another name exits 1"
expect_grep '  identity:author  privacy\.private-literal$' "$out" "a private value in another name is reported"
next_dir; own_noreply_repo "$d"
printf 'x\n' > "$d/a.txt"
GIT_AUTHOR_NAME="$private2" GIT_AUTHOR_EMAIL="999+${private2}${at}users.noreply.github.com" commit "$d" "unlisted noreply"
run "$d"; expect_rc 1 "$rc" "a no-reply email outside the list allows no name"
expect_grep '  identity:author  privacy\.private-literal$' "$out" "the name beside an unlisted no-reply email is reported"

# 3g. The private-values list: missing is a finding; tracked is a finding.
next_dir; newrepo "$d"
rm "$d/.local/first-commit/private-values.txt"
run "$d"; expect_rc 1 "$rc" "missing private-values list exits 1"
expect_grep '^1\. -  \.local/first-commit/private-values\.txt  policy\.private-values-missing$' "$out" "missing private-values list is a finding"
expect_fix policy.private-values-missing 'Create \.local/first-commit/private-values\.txt .*make sure git ignores it' "$out" "missing list fix gives the path and says git must ignore it"
next_dir; newrepo "$d"
git -C "$d" add -f .local/first-commit/private-values.txt; git -C "$d" -c commit.gpgsign=false commit -q -m "oops"
run "$d"; expect_rc 1 "$rc" "tracked private-values list exits 1"
expect_grep 'policy\.private-values-tracked$' "$out" "tracked private-values list is a finding"
expect_fix policy.private-values-tracked 'git rm --cached \.local/first-commit/private-values\.txt' "$out" "tracked list fix names git rm --cached and the path"
next_dir; newrepo "$d"
: > "$d/.gitignore"
run "$d"; expect_rc 1 "$rc" "private-values list not ignored exits 1"
expect_fix policy.private-values-not-ignored 'Add the line `\.local/first-commit/private-values\.txt` to \.gitignore' "$out" "not-ignored fix names the .gitignore line"
next_dir; newrepo "$d"
printf 'not json' > "$d/.repo-policy.json"
run "$d"; expect_rc 3 "$rc" "unreadable policy file exits 3"
expect_grep '^ctlhq-first-push: policy file \.repo-policy\.json is not valid JSON \(line 1, column 1: Expecting value\)$' "$err" "malformed policy: what, with line and column"
expect_grep '^why: ctlhq-first-push reads the allowed emails' "$err" "malformed policy: why"
expect_grep '^fix: Fix the JSON at line 1 of \.repo-policy\.json \(`python3 -m json\.tool \.repo-policy\.json` shows the error\)' "$err" "malformed policy: fix"
if [ -z "$out" ]; then ok; else bad "an exit-3 run prints nothing on stdout"; fi
policy "$d" '{"forbidden_paths": {}}'
run "$d"; expect_rc 3 "$rc" "a policy field that is not a list exits 3"
expect_grep '^ctlhq-first-push: policy field forbidden_paths in \.repo-policy\.json must be a list$' "$err" "policy field not a list: what"
expect_grep '^fix: Write forbidden_paths in \.repo-policy\.json as a JSON list of objects, each with text fields match, value: \[\{"match": "<match>", "value": "<value>"\}\]\.$' "$err" "policy field not a list: fix shows the shape"
policy "$d" '{"forbidden_paths": [{"match": "exact", "value": "a"}, {"match": 1}]}'
run "$d"; expect_rc 3 "$rc" "an invalid policy entry exits 3"
expect_grep '^ctlhq-first-push: policy field forbidden_paths in \.repo-policy\.json has an invalid entry \(entry 2\)$' "$err" "invalid policy entry names the entry number"
policy "$d" '{"public_emails": "x"}'
run "$d"; expect_rc 3 "$rc" "public_emails that is not a list exits 3"
expect_grep '^fix: Write public_emails in \.repo-policy\.json as a JSON list of quoted addresses: \["<address>", \.\.\.\]\.$' "$err" "public_emails not a list: fix"
policy "$d" '[1]'
run "$d"; expect_rc 3 "$rc" "a policy that is not an object exits 3"
expect_grep '^ctlhq-first-push: policy file \.repo-policy\.json is not a JSON object$' "$err" "policy not an object: what"
printf '\377\376' > "$d/.repo-policy.json"
run "$d"; expect_rc 3 "$rc" "a policy that is not UTF-8 exits 3"
expect_grep '^fix: Save \.repo-policy\.json as UTF-8' "$err" "policy not UTF-8: fix"
policy "$d" '{"schema_version": 1}'
printf '\377\376\n' > "$d/.local/first-commit/private-values.txt"
run "$d"; expect_rc 3 "$rc" "a private-values file that is not UTF-8 exits 3"
expect_grep '^ctlhq-first-push: the private-values file \.local/first-commit/private-values\.txt is unreadable or not UTF-8 text$' "$err" "private-values not UTF-8: what"
expect_grep '^fix: Save the list as UTF-8 text, one value per line' "$err" "private-values not UTF-8: fix"

# 3h. A path that holds a private value is redacted and reported.
next_dir; newrepo "$d"
printf 'x\n' > "$d/notes-zorblax.txt"; commit "$d" "named file"
run "$d"; expect_rc 1 "$rc" "private value in a path exits 1"
expect_grep '  <path redacted>  privacy\.private-literal$' "$out" "private value in a path is redacted"
expect_fix privacy.private-literal 'Rename the file with `git mv`' "$out" "redacted path fix says to rename the file"

# 4. README and LICENSE.
next_dir; newrepo "$d" noreadme
run "$d"; expect_rc 1 "$rc" "missing README exits 1"
expect_grep '  README  readme\.missing$' "$out" "missing README is reported"
expect_fix readme.missing 'Add a README\.md' "$out" "missing README fix says to add README.md"
next_dir; newrepo "$d" nolicense
first="$(git -C "$d" rev-parse --short=7 HEAD)"
printf 'MIT License\n' > "$d/LICENSE"; commit "$d" "add license"
run "$d"; expect_rc 1 "$rc" "LICENSE added in commit 2 exits 1"
expect_grep "^1\. $first  LICENSE  license\.missing\$" "$out" "LICENSE missing from the root commit is reported at commit 1"
expect_fix license.missing "Commit $first is the first commit and has no LICENSE, but a LICENSE must be in it\..*history rewrite.*fresh repository" "$out" "LICENSE fix names the first commit and the rewrite or fresh repository"
next_dir; newrepo "$d"
printf 'more\n' >> "$d/main.py"; commit "$d" "commit 2"
git -C "$d" rm -q LICENSE; commit "$d" "remove license"
third="$(git -C "$d" rev-parse --short=7 HEAD)"
printf 'more\n' >> "$d/main.py"; commit "$d" "commit 4"
run "$d"; expect_rc 1 "$rc" "removed LICENSE exits 1"
expect_grep "^1\. $third  LICENSE  license\.missing \(\+1 more commit\)\$" "$out" "removed LICENSE is reported at commit 3 and counted in commit 4"
expect_fix license.missing "Commit $third and 1 later commit have no LICENSE" "$out" "removed LICENSE fix names the commit and the later count"
next_dir; newrepo "$d" nolicense
printf 'GPL\n' > "$d/COPYING"; git -C "$d" add COPYING
git -C "$d" -c commit.gpgsign=false commit -q --amend -m "initial with copying"
run "$d"; expect_rc 0 "$rc" "COPYING in the root commit counts as a LICENSE"

# Public terms in the operator's ctlhq-first-push settings are not private.
next_dir; newrepo "$d"
printf 'by %s\n' "$private1" > "$d/notes.txt"; commit "$d" "public term"
run "$d"; expect_rc 1 "$rc" "a private value is a finding without a public-terms file"
printf 'public_terms = ["%s"]\n' "$private1" > "$tmp/public.toml"
FIRST_PUSH_CONFIG="$tmp/public.toml" run "$d"; expect_rc 0 "$rc" "a declared public term is not a finding"
printf 'and %s\n' "$private2" >> "$d/notes.txt"; commit "$d" "second value"
FIRST_PUSH_CONFIG="$tmp/public.toml" run "$d"; expect_rc 1 "$rc" "other private values are still findings"
printf '# settings\npublic_terms = [oops]\n' > "$tmp/bad.toml"
FIRST_PUSH_CONFIG="$tmp/bad.toml" run "$d"; expect_rc 3 "$rc" "a malformed public-terms list exits 3"
expect_grep '^ctlhq-first-push: public_terms in .*/bad\.toml line 2 is not a list of quoted strings$' "$err" "malformed public terms: what, with the line"
expect_grep '^why: This file lists the terms you declared public' "$err" "malformed public terms: why"
expect_grep '^fix: Rewrite line 2 of .*/bad\.toml as public_terms = \["term one", "term two"\]' "$err" "malformed public terms: fix"
expect_nogrep 'oops' "$err" "the public-terms content is not printed"
printf 'public_terms = [1, 2]\n' > "$tmp/bad2.toml"
FIRST_PUSH_CONFIG="$tmp/bad2.toml" run "$d"; expect_rc 3 "$rc" "public terms that are not strings exit 3"
expect_grep '^fix: Rewrite line 1 of .*/bad2\.toml' "$err" "public terms that are not strings: fix"
printf '\377\376\n' > "$tmp/bin.toml"
FIRST_PUSH_CONFIG="$tmp/bin.toml" run "$d"; expect_rc 3 "$rc" "a public-terms file that is not UTF-8 exits 3"
expect_grep '^ctlhq-first-push: the public-terms file .*/bin\.toml is unreadable or not UTF-8 text$' "$err" "public terms not UTF-8: what"
expect_grep '^fix: Save .*/bin\.toml as UTF-8 text readable by you' "$err" "public terms not UTF-8: fix"

# 5. Push target owner.
next_dir; newrepo "$d"
git -C "$d" remote add origin "https://github.com/someoneelse/tool.git"
run "$d"; expect_rc 1 "$rc" "foreign owner exits 1"
expect_grep '  push-target  push\.foreign-owner$' "$out" "foreign owner is reported"
expect_nogrep 'someoneelse' "$out" "the push address is not printed"
expect_fix push.foreign-owner 'other than acme\. Point remote origin at your account' "$out" "foreign owner fix names the remote and the expected owner"
for url in "https://github.com/acme/tool.git" "git${at}github.com:acme/tool.git" "ssh://git${at}github.com/acme/tool" "https://github.com/ACME/tool"; do
	git -C "$d" remote set-url origin "$url"
	run "$d"; expect_rc 0 "$rc" "own owner accepted in address form $(printf '%s' "$url" | cut -c1-12)"
done
"$fp" --root "$d" hook install >/dev/null
run "$d"; expect_grep '^next: git push -u origin HEAD$' "$(printf '%s\n' "$out" | tail -1)" "ready with the hook and an own origin ends with git push"
for url in "git${at}gitlab.com:someoneelse/tool.git" "$tmp/local-remote.git" "file://$tmp/local-remote.git"; do
	git -C "$d" remote set-url --push origin "$url"
	run "$d"; expect_rc 0 "$rc" "non-GitHub push address is not a finding ($(printf '%s' "$url" | cut -c1-4))"
	expect_grep 'push target not checked \(not a GitHub address\)' "$out" "non-GitHub push address is said to be not checked"
done
rm "$d/LICENSE"; commit "$d" "drop license"
run "$d"; expect_rc 1 "$rc" "other checks still block with a non-GitHub push address"
run "$d" --remote "https://github.com/someoneelse/tool.git"
expect_grep 'push\.foreign-owner$' "$out" "--remote with a URL checks that URL"
expect_fix push.foreign-owner 'Pass a --remote address under https://github\.com/acme/' "$out" "foreign --remote URL fix names the expected owner"
run "$d" --remote nosuch
expect_grep 'push\.unknown-remote$' "$out" "--remote with an unknown name is a finding"
expect_fix push.unknown-remote 'No remote is named nosuch.*git remote -v' "$out" "unknown remote fix names the remote and git remote -v"

# 5b. The owner comes from github_owner in the settings file; unset means a GitHub target is refused.
owner_fix='Add the line github_owner = "<your GitHub account>" to ~/\.ctlhq/first-push\.toml, then run this command again\.$'
next_dir; newrepo "$d"
git -C "$d" remote add origin "https://github.com/acme/tool.git"
printf 'public_terms = ["%s"]\n' "$private1" > "$settings"
run "$d"; expect_rc 1 "$rc" "a GitHub target with no github_owner exits 1"
expect_grep '  push-target  push\.owner-not-configured$' "$out" "unset owner is reported"
expect_grep 'push target not checked \(github_owner not configured\)' "$out" "the summary says the owner is not configured"
expect_fix push.owner-not-configured "$owner_fix" "$out" "unset owner fix names the file and the key"
rm "$settings"
run "$d"; expect_grep '  push-target  push\.owner-not-configured$' "$out" "a missing settings file is reported the same way"
git -C "$d" remote set-url origin "$tmp/local-remote.git"
run "$d"; expect_rc 0 "$rc" "a non-GitHub target needs no owner"
git -C "$d" remote remove origin
"$fp" --root "$d" hook install >/dev/null
run "$d"; expect_grep "^next: $owner_fix" "$(printf '%s\n' "$out" | tail -1)" "ready with no origin and no owner ends with the owner fix"
printf 'github_owner = acme\n' > "$settings"
run "$d"; expect_rc 3 "$rc" "an unquoted github_owner exits 3"
expect_grep '^ctlhq-first-push: github_owner in ~/\.ctlhq/first-push\.toml is not a GitHub account name in double quotes$' "$err" "malformed owner: what"
expect_grep "^fix: $owner_fix" "$err" "malformed owner: fix"
printf 'public_terms = ["%s"]\ngithub_owner = "other-owner"\n' "$private1" > "$settings"
git -C "$d" remote add origin "git${at}github.com:other-owner/tool.git"
run "$d"; expect_rc 0 "$rc" "the configured owner is allowed, next to public_terms"
git -C "$d" remote set-url origin "https://github.com/acme/tool.git"
run "$d"; expect_grep '  push-target  push\.foreign-owner$' "$out" "the old owner is foreign once another is configured"
printf 'github_owner = "acme"\n' > "$tmp/owner-elsewhere.toml"
FIRST_PUSH_CONFIG="$tmp/owner-elsewhere.toml" run "$d"
expect_grep '  push-target  push\.foreign-owner$' "$out" "FIRST_PUSH_CONFIG cannot name another owner"
printf 'github_owner = "ACME"  # my account\n' > "$settings"
run "$d"; expect_rc 0 "$rc" "an owner with a trailing comment and other letter case is allowed"
printf 'github_owner = "acme"\n' > "$settings"

# 6. --new-only against a local bare repository as the remote.
next_dir; newrepo "$d"
printf 'contact %s\n' "$email_bad" > "$d/old.txt"; commit "$d" "old planted"
git clone -q --bare "$d" "$tmp/bare.git"
git -C "$d" remote add origin "$tmp/bare.git"
git -C "$d" fetch -q origin
git -C "$d" remote set-url --push origin "https://github.com/acme/tool.git"
printf 'contact %s\n' "$email_bad" > "$d/new.txt"; commit "$d" "new planted"
run "$d" --new-only
expect_rc 1 "$rc" "--new-only with a new planted email exits 1"
expect_grep '  new\.txt:1  privacy\.unapproved-email$' "$out" "--new-only reports the new commit"
expect_nogrep 'old\.txt' "$out" "--new-only skips the pushed commit"
expect_grep '^ctlhq-first-push: 1 commits checked \(new-only\)' "$out" "--new-only checks 1 commit"
run "$d"
expect_grep '  old\.txt:1  privacy\.unapproved-email$' "$out" "full mode still reports the pushed commit"
git -C "$d" push -q "$tmp/bare.git" main
git -C "$d" fetch -q origin
run "$d" --new-only
expect_rc 0 "$rc" "--new-only with nothing new exits 0"
next_dir; newrepo "$d"
printf 'contact %s\n' "$email_bad" > "$d/a.txt"; commit "$d" "planted"
run "$d" --new-only
expect_grep '  a\.txt:1  privacy\.unapproved-email$' "$out" "--new-only with no remote checks the whole history"

# 7. hook install chains an existing pre-push hook; hook status.
next_dir; newrepo "$d"
git clone -q --bare "$d" "$tmp/bare2.git"
git -C "$d" remote add origin "$tmp/bare2.git"
"$fp" --root "$d" hook status >/dev/null; expect_rc 1 $? "hook status before install exits 1"
expect_grep '^missing$' "$("$fp" --root "$d" hook status)" "hook status before install prints missing"
hooks="$d/.git/hooks"
printf '#!/usr/bin/env bash\n# File generated by pre-commit: https://pre-commit.com\necho "args $*" > "%s"\ncat >> "%s"\nexit 0\n' "$tmp/previous-ran" "$tmp/previous-ran" > "$hooks/pre-push"
chmod +x "$hooks/pre-push"
cp "$hooks/pre-push" "$tmp/previous-copy"
out="$("$fp" --root "$d" hook install)"; expect_rc 0 $? "hook install exits 0"
expect_grep 'kept as pre-push\.before-first-push' "$out" "hook install says the earlier hook is kept"
if cmp -s "$tmp/previous-copy" "$hooks/pre-push.before-first-push"; then ok; else bad "the earlier hook is kept unchanged"; fi
out="$("$fp" --root "$d" hook status)"; expect_rc 0 $? "hook status after install exits 0"
expect_grep '^installed, runs pre-push\.before-first-push first$' "$out" "hook status reports installed and chained"
out="$("$fp" --root "$d" hook install)"; expect_rc 0 $? "a second hook install exits 0"
expect_grep 'already present' "$out" "a second hook install changes nothing"
if cmp -s "$tmp/previous-copy" "$hooks/pre-push.before-first-push"; then ok; else bad "a second install keeps the earlier hook"; fi
rm -f "$tmp/previous-ran"
printf 'contact %s\n' "$email_bad" > "$d/z.txt"; commit "$d" "planted, to push"
(cd "$d" && git push -q --dry-run origin main) >"$tmp/push-out" 2>&1; prc=$?
cat "$tmp/push-out" >> "$all_out"
expect_rc 1 "$prc" "git push --dry-run is blocked by a planted email"
expect_grep '^args origin ' "$(cat "$tmp/previous-ran" 2>/dev/null)" "git push ran the earlier hook first with its arguments"
expect_grep 'refs/heads/main' "$(cat "$tmp/previous-ran" 2>/dev/null)" "the earlier hook received the push input"
expect_grep '  z\.txt:1  privacy\.unapproved-email$' "$(cat "$tmp/push-out")" "git push ran ctlhq-first-push after the earlier hook"
git -C "$d" reset -q --hard HEAD~1
printf 'z\n' > "$d/z.txt"; commit "$d" "clean, to push"
rm -f "$tmp/previous-ran"
(cd "$d" && git push -q --dry-run origin main) >"$tmp/push-out" 2>&1; prc=$?
cat "$tmp/push-out" >> "$all_out"
expect_rc 0 "$prc" "git push --dry-run to a local remote goes ahead when the repository is ready"
expect_grep 'push target not checked \(not a GitHub address\)' "$(cat "$tmp/push-out")" "the hook says the local remote is not checked"
expect_grep '^args origin ' "$(cat "$tmp/previous-ran" 2>/dev/null)" "the earlier hook ran on the ready push too"
git -C "$d" remote set-url --push origin "https://github.com/acme/tool.git"
rm -f "$tmp/previous-ran"
(cd "$d" && printf 'refs/heads/main 1 refs/heads/main 2\n' | "$hooks/pre-push" origin "https://github.com/acme/tool.git") >"$tmp/hook-out" 2>&1; hrc=$?
cat "$tmp/hook-out" >> "$all_out"
expect_rc 0 "$hrc" "the hook exits 0 on a ready repository with an own target"
expect_grep '^ready$' "$(cat "$tmp/hook-out")" "the hook prints ready"
expect_grep '^next: none; this push goes ahead$' "$(cat "$tmp/hook-out")" "the hook's next line says the push goes ahead"
expect_grep '^refs/heads/main 1 refs/heads/main 2$' "$(cat "$tmp/previous-ran" 2>/dev/null)" "the earlier hook still gets stdin"
printf '#!/usr/bin/env bash\nexit 7\n' > "$hooks/pre-push.before-first-push"
(cd "$d" && "$hooks/pre-push" origin x </dev/null) >/dev/null 2>&1; expect_rc 7 $? "a failing earlier hook stops the push with its exit code"
hooks_both="$d/.git/hooks"
printf '#!/bin/sh\nexit 0\n' > "$hooks_both/pre-push"
err="$("$fp" --root "$d" hook install 2>&1 >/dev/null)"; expect_rc 3 $? "hook install with both hooks present exits 3"
expect_grep '^ctlhq-first-push: both pre-push and pre-push\.before-first-push exist in .*/\.git/hooks; nothing changed$' "$err" "both hooks: what, with the folder"
expect_grep '^fix \(operator decides\): Read both files, merge them into pre-push\.before-first-push or remove one' "$err" "both hooks: the hook fix is marked as the operator's decision"
next_dir; newrepo "$d"
git -C "$d" config core.hooksPath "$tmp/elsewhere-hooks"
err="$("$fp" --root "$d" hook install 2>&1 >/dev/null)"; expect_rc 3 $? "hook install with core.hooksPath outside the repository exits 3"
expect_grep '^ctlhq-first-push: core\.hooksPath points outside this repository$' "$err" "hooksPath outside: what"
expect_grep '^fix \(operator decides\): Install the hook by hand: .*--remote "\$1"; or, when no other tool needs core\.hooksPath, run `git config --unset core\.hooksPath`' "$err" "hooksPath outside: the hook fix is marked as the operator's decision"
marked="$(python3 - "$fp" <<'PY'
import ast, sys
tree = ast.parse(open(sys.argv[1], encoding="utf-8").read())
bad = 0
for n in ast.walk(tree):
    if isinstance(n, ast.Call) and getattr(n.func, "id", "") == "EnvError":
        text = " ".join(s.value for s in ast.walk(n) if isinstance(s, ast.Constant) and isinstance(s.value, str))
        op = any(k.arg == "operator" and getattr(k.value, "value", False) is True for k in n.keywords)
        if ("git commit" in text or "git config" in text or "remove one" in text) and not op:
            bad += 1
print(bad)
PY
)"
expect_grep '^0$' "$marked" "every exit-3 fix that commits or changes a hook passes operator=True"
next_dir; newrepo "$d"
out="$("$fp" --root "$d" hook install)"; expect_rc 0 $? "hook install with no earlier hook exits 0"
expect_grep '^installed$' "$out" "hook install with no earlier hook prints installed"
if [ -x "$d/.git/hooks/pre-push" ] && [ ! -e "$d/.git/hooks/pre-push.before-first-push" ]; then ok; else bad "fresh install writes only pre-push"; fi
run "$d"; expect_grep '^next: git remote add origin https://github\.com/acme/<repository>\.git$' "$(printf '%s\n' "$out" | tail -1)" "ready with the hook and no origin ends with git remote add"

# 7a. Hook ownership and staleness. A hook is ctlhq's only when line 2 is the marker; a marked hook is
#     stale only when its recorded tool cannot run (or the hook itself cannot run). old_hook prints the
#     hook text that bin/first-push wrote before the rename (d4a3584), for the tool path given.
old_hook() { # tool
	cat <<EOF
#!/usr/bin/env bash
# first-push hook v1: runs the pre-push hook that was here before, then first-push.
# Installed by "first-push hook install". The earlier hook, if any, is pre-push.before-first-push.
set -u
here="\$(cd "\$(dirname "\$0")" && pwd)"
previous="\$here/pre-push.before-first-push"
tool=$1
if [ -x "\$previous" ]; then
	input="\$(mktemp)" || exit 1
	trap 'rm -f "\$input"' EXIT
	cat > "\$input"
	"\$previous" "\$@" < "\$input" || exit \$?
fi
if [ ! -x "\$tool" ]; then
	echo "first-push hook: \$tool is missing; reinstall with first-push hook install" >&2
	exit 1
fi
FIRST_PUSH_FROM_HOOK=1 "\$tool" --remote "\${1:-origin}"
EOF
}
next_dir; newrepo "$d"
git clone -q --bare "$d" "$tmp/bare-stale.git"
git -C "$d" remote add origin "$tmp/bare-stale.git"
hooks="$d/.git/hooks"
printf '#!/usr/bin/env bash\necho earlier >> "%s"\nexit 0\n' "$tmp/stale-previous-ran" > "$hooks/pre-push.before-first-push"
chmod +x "$hooks/pre-push.before-first-push"
cp "$hooks/pre-push.before-first-push" "$tmp/stale-previous-copy"
old_hook "$tmp/old-checkout/bin/first-push" > "$hooks/pre-push"
chmod +x "$hooks/pre-push"
cp "$hooks/pre-push" "$tmp/stale-hook-copy"
out="$("$fp" --root "$d" hook status)"; expect_rc 1 $? "hook status on the pre-rename hook whose tool is gone exits 1"
expect_grep '^stale: the hook runs .*/old-checkout/bin/first-push, which is missing or not executable; ctlhq-first-push hook install replaces it$' "$out" "hook status names the stale tool path"
run "$d"; expect_grep '^next: ctlhq-first-push hook install$' "$(printf '%s\n' "$out" | tail -1)" "a stale hook makes the next step hook install"
out="$("$fp" --root "$d" hook install)"; expect_rc 0 $? "hook install over a stale hook exits 0"
expect_grep '^installed; replaced a stale ctlhq hook that runs .*/old-checkout/bin/first-push, which is missing or not executable; the old file is kept as pre-push\.stale\.1; the earlier hook is kept as pre-push\.before-first-push and runs first$' "$out" "hook install names what it replaced and the backup"
if cmp -s "$tmp/stale-hook-copy" "$hooks/pre-push.stale.1"; then ok; else bad "the stale hook is kept byte for byte as pre-push.stale.1"; fi
expect_grep "^tool=.*/bin/ctlhq-first-push'?$" "$(cat "$hooks/pre-push")" "the new hook runs the current tool"
if cmp -s "$tmp/stale-previous-copy" "$hooks/pre-push.before-first-push"; then ok; else bad "the rewrite keeps the chained earlier hook"; fi
out="$("$fp" --root "$d" hook status)"; expect_rc 0 $? "hook status after the rewrite exits 0"
rm -f "$tmp/stale-previous-ran"
(cd "$d" && git push -q --dry-run origin main) >"$tmp/push-out" 2>&1; prc=$?
cat "$tmp/push-out" >> "$all_out"
expect_rc 0 "$prc" "a push after the rewrite goes ahead"
expect_nogrep 'is missing; reinstall' "$(cat "$tmp/push-out")" "a push after the rewrite does not look for the old tool"
expect_grep 'push target not checked' "$(cat "$tmp/push-out")" "a push after the rewrite runs the current tool"
expect_grep '^earlier$' "$(cat "$tmp/stale-previous-ran" 2>/dev/null)" "a push after the rewrite still runs the earlier hook first"
old_hook "$tmp/old-checkout/bin/first-push" > "$hooks/pre-push"
out="$("$fp" --root "$d" hook install)"; expect_rc 0 $? "a second stale hook install exits 0"
expect_grep 'the old file is kept as pre-push\.stale\.2;' "$out" "a second stale hook goes to the first free number"
if cmp -s "$tmp/stale-hook-copy" "$hooks/pre-push.stale.1"; then ok; else bad "the first backup is not overwritten"; fi

# The pre-rename hook whose recorded tool still runs is current, so it is kept as it is.
mkdir -p "$tmp/old-checkout/bin"
printf '#!/bin/sh\nexit 0\n' > "$tmp/old-checkout/bin/first-push"
chmod +x "$tmp/old-checkout/bin/first-push"
next_dir; newrepo "$d"; hooks="$d/.git/hooks"
old_hook "$tmp/old-checkout/bin/first-push" > "$hooks/pre-push"; chmod +x "$hooks/pre-push"
cp "$hooks/pre-push" "$tmp/kept-copy"
out="$("$fp" --root "$d" hook status)"; expect_rc 0 $? "hook status on a marked hook whose tool runs exits 0"
out="$("$fp" --root "$d" hook install)"; expect_rc 0 $? "hook install on a marked hook whose tool runs exits 0"
expect_grep 'already present' "$out" "a marked hook from another checkout is current"
if cmp -s "$tmp/kept-copy" "$hooks/pre-push" && [ ! -e "$hooks/pre-push.stale.1" ]; then ok; else bad "a marked hook from another checkout is left unchanged"; fi
rm -rf "$tmp/old-checkout"

# A hand-edited marked hook whose tool runs is kept.
next_dir; newrepo "$d"; hooks="$d/.git/hooks"
"$fp" --root "$d" hook install >/dev/null
printf 'echo MY-EXTRA-STEP\n' >> "$hooks/pre-push"
cp "$hooks/pre-push" "$tmp/edited-copy"
out="$("$fp" --root "$d" hook status)"; expect_rc 0 $? "hook status on a hand-edited marked hook exits 0"
out="$("$fp" --root "$d" hook install)"; expect_rc 0 $? "hook install on a hand-edited marked hook exits 0"
if cmp -s "$tmp/edited-copy" "$hooks/pre-push" && [ ! -e "$hooks/pre-push.stale.1" ]; then ok; else bad "the hand edit survives hook install"; fi

# A user's hook that quotes the marker, but not as line 2, is the user's hook.
for body in '#!/bin/sh\n# my wrapper, based on # first-push hook v1\nrun-my-lint\n' '#!/bin/sh\n# lint first\n# first-push hook v1\nrun-my-lint\n'; do
	next_dir; newrepo "$d"; hooks="$d/.git/hooks"
	printf "$body" > "$hooks/pre-push"; chmod +x "$hooks/pre-push"
	cp "$hooks/pre-push" "$tmp/quoted-copy"
	expect_grep '^missing$' "$("$fp" --root "$d" hook status)" "a user hook that quotes the marker is not ctlhq's"
	out="$("$fp" --root "$d" hook install)"; expect_rc 0 $? "hook install over a user hook that quotes the marker exits 0"
	expect_grep 'kept as pre-push\.before-first-push' "$out" "a user hook that quotes the marker is kept as the earlier hook"
	if cmp -s "$tmp/quoted-copy" "$hooks/pre-push.before-first-push" && [ ! -e "$hooks/pre-push.stale.1" ]; then ok; else bad "a user hook that quotes the marker is moved unchanged, never overwritten"; fi
done

# A linked pre-push is never written through.
for kind in user stale; do
	next_dir; newrepo "$d"; hooks="$d/.git/hooks"
	if [ "$kind" = user ]; then printf '#!/bin/sh\nexit 0\n' > "$tmp/shared-$kind"; else old_hook "$tmp/gone/bin/first-push" > "$tmp/shared-$kind"; fi
	chmod +x "$tmp/shared-$kind"; cp "$tmp/shared-$kind" "$tmp/shared-copy"
	ln -s "$tmp/shared-$kind" "$hooks/pre-push"
	if [ "$kind" = user ]; then first=missing; else first=stale; fi
	out="$("$fp" --root "$d" hook status)"; expect_rc 1 $? "hook status on a linked $kind hook exits 1"
	expect_grep "^$first: .*; replace the symbolic link .*/\.git/hooks/pre-push with a copy of its target \(or remove it\), then run ctlhq-first-push hook install$" "$out" "hook status on a linked $kind hook gives the link fix"
	run "$d"; expect_grep '^next: replace the symbolic link .*/\.git/hooks/pre-push with a copy of its target' "$(printf '%s\n' "$out" | tail -1)" "a linked $kind hook makes the next step the link fix"
	err="$("$fp" --root "$d" hook install 2>&1 >/dev/null)"; expect_rc 3 $? "hook install on a linked $kind hook exits 3"
	expect_grep '^ctlhq-first-push: pre-push in .*/\.git/hooks is a symbolic link to .*; nothing changed$' "$err" "linked $kind hook: what"
	expect_grep '^fix \(operator decides\): Replace the link with a copy of its target' "$err" "linked $kind hook: fix line"
	if [ -L "$hooks/pre-push" ] && cmp -s "$tmp/shared-copy" "$tmp/shared-$kind" && [ ! -e "$hooks/pre-push.before-first-push" ] && [ ! -e "$hooks/pre-push.stale.1" ]; then ok; else bad "a linked $kind hook and its target are left unchanged"; fi
done

# A marked hook that is not executable is ctlhq's (stale), never chained as the earlier hook.
next_dir; newrepo "$d"; hooks="$d/.git/hooks"
"$fp" --root "$d" hook install >/dev/null
chmod 644 "$hooks/pre-push"
out="$("$fp" --root "$d" hook status)"; expect_rc 1 $? "hook status on a non-executable marked hook exits 1"
expect_grep '^stale: the hook is not executable, so git skips it;' "$out" "hook status says the marked hook is not executable"
out="$("$fp" --root "$d" hook install)"; expect_rc 0 $? "hook install on a non-executable marked hook exits 0"
expect_grep 'the old file is kept as pre-push\.stale\.1' "$out" "the non-executable marked hook is backed up"
if [ -x "$hooks/pre-push" ] && [ ! -e "$hooks/pre-push.before-first-push" ]; then ok; else bad "the non-executable marked hook is never chained as the earlier hook"; fi

# A hooks folder that cannot be changed gives an exit-3 error, never a traceback, and changes nothing.
if [ "$(id -u)" -ne 0 ]; then
	next_dir; newrepo "$d"; hooks="$d/.git/hooks"
	old_hook "$tmp/gone/bin/first-push" > "$hooks/pre-push"; chmod +x "$hooks/pre-push"; cp "$hooks/pre-push" "$tmp/ro-copy"
	chmod 555 "$hooks"
	err="$("$fp" --root "$d" hook install 2>&1 >/dev/null)"; rc=$?
	chmod 755 "$hooks"
	expect_rc 3 "$rc" "hook install in a read-only hooks folder exits 3"
	expect_grep '^ctlhq-first-push: the pre-push hook could not be written \(Permission denied\)$' "$err" "read-only hooks folder: what"
	expect_grep '^fix: Check the folder.s permission with `ls -ld .*/\.git/hooks`' "$err" "read-only hooks folder: fix"
	expect_nogrep 'Traceback' "$err" "read-only hooks folder: no traceback"
	if cmp -s "$tmp/ro-copy" "$hooks/pre-push" && [ ! -e "$hooks/pre-push.stale.1" ]; then ok; else bad "read-only hooks folder: the stale hook is left in place"; fi
fi

# A write that fails part way removes the partial pre-push and puts the old hook back, or names where it is kept.
# The tool is loaded as a module with a file write that writes 20 bytes and then fails. With "lock", that write
# also makes the hooks folder read-only, so the old hook cannot be moved back.
failed_write() { # dir [lock]: prints the exit-3 "what" line
	python3 - "$fp" "$@" <<'PY'
import importlib.machinery, importlib.util, os, sys
from pathlib import Path
loader = importlib.machinery.SourceFileLoader("first_push", sys.argv[1])
spec = importlib.util.spec_from_loader("first_push", loader)
mod = importlib.util.module_from_spec(spec)
loader.exec_module(mod)
def partial_write(self, text, *args, **kwargs):
    with open(self, "w", encoding="utf-8") as handle:
        handle.write(text[:20])
    if len(sys.argv) > 3:
        os.chmod(self.parent, 0o555)
    raise OSError(28, "No space left on device")
Path.write_text = partial_write
try:
    mod.hook_command(Path(sys.argv[2]), "install")
except mod.EnvError as error:
    print(error.what)
PY
}
next_dir; newrepo "$d"; hooks="$d/.git/hooks"
old_hook "$tmp/gone/bin/first-push" > "$hooks/pre-push"; chmod +x "$hooks/pre-push"; cp "$hooks/pre-push" "$tmp/partial-copy"
out="$(failed_write "$d")"
expect_grep '^the pre-push hook could not be written \(No space left on device\); the old hook pre-push\.stale\.1 is back as pre-push$' "$out" "a failed write names the backup it moved back"
if cmp -s "$tmp/partial-copy" "$hooks/pre-push" && [ ! -e "$hooks/pre-push.stale.1" ]; then ok; else bad "a failed write leaves the old hook in place, byte for byte"; fi
if [ "$(id -u)" -ne 0 ]; then
	next_dir; newrepo "$d"; hooks="$d/.git/hooks"
	old_hook "$tmp/gone/bin/first-push" > "$hooks/pre-push"; chmod +x "$hooks/pre-push"
	out="$(failed_write "$d" lock)"
	chmod 755 "$hooks"
	expect_grep '^the pre-push hook could not be written \(No space left on device\); the old hook is kept as pre-push\.stale\.1$' "$out" "a failed write that cannot move the old hook back names the backup"
	if cmp -s "$tmp/partial-copy" "$hooks/pre-push.stale.1"; then ok; else bad "the backup named after a failed write holds the old hook"; fi
fi

# 7b. gitleaks findings get a fix line (a stand-in gitleaks writes a report and exits 10).
fake_gitleaks() { # folder report-json
	mkdir -p "$1"
	printf '#!/bin/sh
for a in "$@"; do case "$a" in --report-path=*) printf %%s %s > "${a#--report-path=}";; esac; done
exit 10
' "'$2'" > "$1/gitleaks"
	chmod +x "$1/gitleaks"
}
next_dir; newrepo "$d"
fake_gitleaks "$HOME/.ctlhq/bin" '[{"File": "config.txt", "StartLine": 4, "Commit": "abcdef1234567"}]'
run "$d"; expect_rc 1 "$rc" "a gitleaks finding exits 1"
expect_fix secrets.gitleaks 'revoke it and remove it from config\.txt line 4.*\.gitleaksignore.*Commit abcdef1 already holds it' "$out" "gitleaks fix names the file, line, and commit"
fake_gitleaks "$HOME/.ctlhq/bin" 'not json'
run "$d"; expect_fix secrets.gitleaks 'gitleaks git --redact -v' "$out" "unreadable gitleaks report fix names the command to see it"
printf '#!/bin/sh\nexit 2\n' > "$HOME/.ctlhq/bin/gitleaks"
run "$d"; expect_rc 3 "$rc" "a gitleaks failure exits 3"
expect_grep '^ctlhq-first-push: gitleaks scan failed \(exit 2\)$' "$err" "gitleaks failure: what"
expect_grep '^why: The secret scan did not complete' "$err" "gitleaks failure: why"
expect_grep '^fix: Run `gitleaks git --redact -v` in the repository' "$err" "gitleaks failure: fix"
rm -rf "$HOME/.ctlhq/bin"

# 7b2. gitleaks runs only from ~/.ctlhq/bin or PATH, never from inside the checked repository.
planted_gitleaks() { # folder: a gitleaks that leaves a marker file when run
	mkdir -p "$1"
	printf '#!/bin/sh\ntouch "%s"\nexit 0\n' "$tmp/gitleaks-ran" > "$1/gitleaks"
	chmod +x "$1/gitleaks"
}
next_dir; newrepo "$d"
planted_gitleaks "$d/.local/bin"
rm -f "$tmp/gitleaks-ran"
run "$d"; expect_rc 0 "$rc" "a repository's own gitleaks does not change the verdict"
if [ -e "$tmp/gitleaks-ran" ]; then bad "a gitleaks inside the repository is never run"; else ok; fi
expect_grep 'gitleaks not installed: built-in token shapes only' "$out" "a repository's own gitleaks counts as not installed"
rm -f "$tmp/gitleaks-ran"
out="$(cd "$d" && PATH=".local/bin:$PATH" "$fp" 2>&1)"
if [ -e "$tmp/gitleaks-ran" ]; then bad "a relative PATH folder is never searched"; else ok; fi
rm -f "$tmp/gitleaks-ran"
out="$(PATH="$d/.local/bin:$PATH" "$fp" --root "$d" 2>&1)"
if [ -e "$tmp/gitleaks-ran" ]; then bad "an absolute PATH folder inside the repository is skipped"; else ok; fi
planted_gitleaks "$tmp/tools"
rm -f "$tmp/gitleaks-ran"
out="$(PATH="$d/.local/bin:$tmp/tools:$PATH" "$fp" --root "$d" 2>&1)"
if [ -e "$tmp/gitleaks-ran" ]; then ok; else bad "a gitleaks on PATH outside the repository runs"; fi
expect_grep 'gitleaks ran' "$out" "the report says the PATH gitleaks ran"
rm -f "$tmp/gitleaks-ran"
planted_gitleaks "$HOME/.ctlhq/bin"
run "$d"; expect_grep 'gitleaks ran' "$out" "~/.ctlhq/bin/gitleaks runs"
if [ -e "$tmp/gitleaks-ran" ]; then ok; else bad "~/.ctlhq/bin/gitleaks is run"; fi
rm -rf "$HOME/.ctlhq/bin" "$tmp/tools"
out="$("$fp" --help)"
expect_grep '~/\.ctlhq/bin/gitleaks' "$out" "--help names the gitleaks folder"
expect_grep 'github_owner = "<your GitHub account>"' "$out" "--help names the owner setting"
expect_grep 'second line is the marker "# first-push hook v1", alone or followed by a colon' "$out" "--help states the marker rule the code uses"
expect_grep 'never from' "$out" "--help says the owner is never read from FIRST_PUSH_CONFIG"

# 7c0. Every exit-3 error in bin/ctlhq-first-push passes its own why and fix text (no default).
bare="$(python3 - "$fp" <<'PY'
import ast, sys
tree = ast.parse(open(sys.argv[1], encoding="utf-8").read())
calls = [n for n in ast.walk(tree) if isinstance(n, ast.Call) and getattr(n.func, "id", "") == "EnvError"]
print(len(calls), sum(1 for c in calls if len(c.args) + len(c.keywords) < 3))
PY
)"
expect_grep '^[1-9][0-9]* 0$' "$bare" "every EnvError call names what, why, and fix"

# 7c. Every rule bin/ctlhq-first-push can emit has why and fix text.
cover="$(python3 - "$fp" <<'PY'
import importlib.machinery, importlib.util, re, sys
loader = importlib.machinery.SourceFileLoader("first_push", sys.argv[1])
spec = importlib.util.spec_from_loader("first_push", loader)
mod = importlib.util.module_from_spec(spec)
loader.exec_module(mod)
source = open(sys.argv[1], encoding="utf-8").read()
rules = sorted(set(re.findall(r'"((?:privacy|policy|push|license|readme|secrets)\.[a-z-]+)"', source)))
missing = []
for rule in rules:
    for where, file, line in (("file", "a.txt", 2), ("file", "a.txt", None), ("message", None, 3),
                              ("identity", None, "author"), ("policy", "p.txt", None), ("push-target", "push-target", None)):
        f = {"commit": "abc1234", "where": where, "file": file, "line": line, "rule": rule, "more_commits": 0}
        why, fix = mod.explain(f, {"tip": "fff0000", "roots": set(), "remote": "origin"})
        if not why.strip() or not fix.strip():
            missing.append(f"{rule} ({where})")
print(len(rules), " ".join(missing) or "none")
PY
)"
expect_grep '^1[0-9] none$' "$cover" "every rule in bin/ctlhq-first-push has why and fix text"

# 8. A real gitleaks in ~/.ctlhq/bin (set FIRST_PUSH_GITLEAKS to a gitleaks binary to test it).
if [ -n "${FIRST_PUSH_GITLEAKS:-}" ] && [ -x "$FIRST_PUSH_GITLEAKS" ]; then
	mkdir -p "$HOME/.ctlhq/bin"; cp "$FIRST_PUSH_GITLEAKS" "$HOME/.ctlhq/bin/gitleaks"
	next_dir; newrepo "$d"
	printf 'token = "%s"\n' "ghp""_skxSJ9z5EMBO3vXNo2Ga7qDBKsBMuOsI2XOq" > "$d/config.txt"; commit "$d" "token"
	run "$d"; expect_rc 1 "$rc" "gitleaks planted token exits 1"
	expect_grep 'gitleaks ran' "$out" "the report says gitleaks ran"
	expect_grep '  config\.txt:1  secrets\.gitleaks$' "$out" "gitleaks finding is reported with file and line"
	next_dir; newrepo "$d"
	run "$d"; expect_rc 0 "$rc" "gitleaks on a clean repository exits 0"
	rm -rf "$HOME/.ctlhq/bin"
else
	echo "note: gitleaks checks skipped (FIRST_PUSH_GITLEAKS not set)"
fi

# 9. No private value or planted email in any stdout, stderr, or JSON output.
for d in "$tmp"/r*; do
	[ -d "$d/.git" ] || continue
	"$fp" --root "$d" --json >> "$all_out" 2>&1
done
json_shape="$(for d in "$tmp"/r*; do [ -d "$d/.git" ] && "$fp" --root "$d" --json 2>/dev/null; done | python3 -c '
import json, sys
text, bad, count, decoder, i = sys.stdin.read(), 0, 0, json.JSONDecoder(), 0
while i < len(text):
    if text[i].isspace():
        i += 1; continue
    data, i = decoder.raw_decode(text, i)
    bad += not str(data.get("next", "")).strip()
    for f in data["findings"]:
        count += 1
        bad += not (f.get("why", "").strip() and f.get("fix", "").strip())
print(count, bad)')"
expect_grep '^[1-9][0-9]* 0$' "$json_shape" "every --json finding has why and fix fields, and every report has next"
unfixed="$(awk 'want { if ($0 !~ /^   fix: [^ ]/) n++; want = 0 } /^[0-9]+\. (-|[0-9a-f]{7})  / { want = 1 } END { print n + 0 }' "$all_out")"
expect_rc 0 "$unfixed" "every finding line in all output has a fix: line right under it"
leaks=0
for value in "$private1" "$private2" "$email_bad" "$email_public" "$email_noreply" "someone/" "$gh_token" "$aws_key" "${ssh_fp#SHA256:}"; do
	if grep -Fiq -- "$value" "$all_out"; then leaks=$((leaks + 1)); echo "leaked a planted value (index $leaks)"; fi
done
expect_rc 0 "$leaks" "no private value, email, or token appears in any output"
if [ -s "$all_out" ]; then ok; else bad "output was recorded for the leak check"; fi

if [ "$fail" -ne 0 ]; then
	echo "$fail checks failed, $pass passed"
	exit 1
fi
echo "$pass checks passed"
