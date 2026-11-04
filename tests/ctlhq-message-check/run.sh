#!/usr/bin/env bash
set -u
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
mc="$root/bin/ctlhq-message-check"
fixtures="$here/fixtures"
pass=0
fail=0
ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL: $1"; }
expect_rc() { if [ "$1" -eq "$2" ]; then ok; else bad "$3 (expected exit $1, got $2)"; fi; }
expect_eq() { if [ "$1" = "$2" ]; then ok; else bad "$3 (expected '$1', got '$2')"; fi; }
expect_grep() { if printf '%s\n' "$2" | grep -Eq -- "$1"; then ok; else bad "$3 (no line matches: $1)"; fi; }
expect_nogrep() { if printf '%s\n' "$2" | grep -Eq -- "$1"; then bad "$3 (a line matches: $1)"; else ok; fi; }

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
tmp="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/ctlhq-message-check-test.XXXXXX")" && pwd -P)"
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home"
mkdir -p "$HOME/.ctlhq"
cd "$tmp" || exit 1

rules_of() { printf '%s\n' "$1" | sed -n 's/^line [0-9]*: \([a-z-]*\).*/\1/p' | sort -u | paste -sd, -; }
newrepo() {
  r="$tmp/$1"; git init -q -b main "$r"
  git -C "$r" config user.name t; git -C "$r" config user.email t@example.invalid; git -C "$r" config commit.gpgsign false
}
commit() { git -C "$1" commit -q --allow-empty -m "$2"; }

out="$("$mc" --help 2>&1)"; expect_rc 0 $? "--help exits 0"
expect_grep '^ctlhq-message-check: ' "$(printf '%s\n' "$out" | head -1)" "--help first line is 'ctlhq-message-check: ...'"
expect_grep 'reword' "$out" "--help names the first way out"
expect_grep 'fix the check in that checkout' "$out" "--help names the second way out"
expect_grep 'git commit -F MESSAGE_FILE' "$out" "--help gives the operator's own block, the third way out"
expect_grep 'git add PATHS' "$out" "the operator's block stages the paths, because a refusal leaves nothing staged"
expect_grep 'write the message to a file' "$out" "the third way out says to write the message to a file first"
expect_grep 'own list line' "$out" "--help says a longer word needs its own list line"
"$mc" --bogus </dev/null >/dev/null 2>&1; expect_rc 2 $? "an unknown option exits 2"
"$mc" "$tmp/nowhere.txt" >/dev/null 2>&1; expect_rc 2 $? "a missing FILE exits 2"
"$mc" --root "$tmp/nowhere" </dev/null >/dev/null 2>&1; expect_rc 2 $? "a missing --root folder exits 2"
"$mc" --history "$fixtures/clean-three-rounds.txt" >/dev/null 2>&1; expect_rc 2 $? "--history with a FILE exits 2"
"$mc" --branch x --history >/dev/null 2>&1; expect_rc 2 $? "--branch with --history exits 2"
"$mc" --history --root "$tmp" >/dev/null 2>&1; expect_rc 2 $? "--history outside a repository exits 2"

flagged=0; clean=0
while IFS=$'\t' read -r name want; do
  out="$("$mc" "$fixtures/$name")"; rc=$?
  if [ "$want" = "-" ]; then
    clean=$((clean + 1)); expect_rc 0 "$rc" "$name exits 0"; expect_eq "" "$out" "$name prints nothing"
  else
    case "$name" in flagged-*) flagged=$((flagged + 1)) ;; esac
    expect_rc 1 "$rc" "$name exits 1"; expect_eq "$want" "$(rules_of "$out")" "$name gives its exact rules"
  fi
done < "$fixtures/rules.tsv"
expect_eq 15 "$flagged" "15 flagged inputs ran"
expect_eq 3 "$clean" "3 clean inputs ran"
expect_eq 15 "$(for f in "$fixtures"/flagged-*.txt; do cksum < "$f"; done | sort -u | wc -l | tr -d ' ')" "the 15 flagged inputs are all different"
expect_eq "approval,label,path,review" "$(rules_of "$("$mc" "$fixtures/bad-example.txt")")" "the bad example gives all four rules"

while IFS=$'\t' read -r want line; do
  expect_eq "$want" "$(rules_of "$(printf '%s\n' "$line" | "$mc")")" "'$line' gives $want"
done <<'TABLE'
path	see .local/reviews/a.md
path	see .local/briefs/a.md
path	see .local/verify/a
path	see .local/plans/a.md
path	see .local/msg-a.txt
path	see .local/commit-a.txt
path	see .local/pr-m4-low.md
approval	the Operator approved it
approval	the operator accepted it
approval	the operator prefers it
approval	the operator reviewed it
approval	the operator reviews it
approval	this waits for their yes
approval	this wait for the operator
approval	this waits for approval
approval	needs the operator's yes
approval	needs the operator's approval
review	Audit round 4
review	round 2 found it
review	Rounds 6 and 7
review	Reviews A and B
review	COMMIT REVIEW accepted
review	two commit reviews
review	Blind review
review	Pull-request reviews read it
review	Pull request review accepted.
review	PR reviews read it next.
review	Blind-review: accept.
review	Commit-review: accept
review	commit-review fix first
review	commit-review: reject
label	Milestone 2 decides
label	Milestone-2 decides
label	this is M12
TABLE
while IFS= read -r line; do
  out="$(printf '%s\n' "$line" | "$mc")"; expect_rc 0 $? "'$line' exits 0"
done <<'TABLE'
the m2 chip in lower case
see .local/gate/a.exit
the operator runs it
Three rounds of two concurrent test runs
a milestone with no number
around 5 seconds
the commit-review skill
the .local/print folder
an April review of the sprint
docs(pr-review): say what it reads
docs(commit-review): name the message file
fix(pr-review): name the title and body
the pr-review skill reads the body
the commit-review skill reads the message file
TABLE
expect_eq review "$(rules_of "$(printf 'Pull-request reviews A and B\n' | "$mc")")" "prose about a review still gives review"

for text in 'Fix the commit\n\nReview the plan before a push.\n' 'Fix how we round\n\n2 tests now run.\n' 'Fix the commit\r\n\r\nReview it.\n' 'Fix the commit\n  \n  review it.\n'; do
  printf "$text" | "$mc" >/dev/null; expect_rc 0 $? "'$text' exits 0"
done

wrapped() { out="$(printf "$2" | "$mc")"; expect_rc 1 $? "'$2' exits 1"; expect_eq "$1" "$(rules_of "$out")" "'$2' gives $1"; }
wrapped approval 'This commit waits for\n  their yes before any push.\n'
wrapped approval 'The operator\napproved it.\n'
wrapped approval 'waits for the\noperator\n'
wrapped approval "the operator's\nyes\n"
wrapped review 'Audit\n  round 4\n'
wrapped review 'Round\n2 found it\n'
wrapped review 'reviews A\nand B\n'
wrapped review 'pull-request\nreviews\n'
wrapped review 'pull request\nreviews\n'
wrapped review 'Commit  review accept\n'
wrapped review 'Commit\treview accept\n'
wrapped review 'Commit\302\240review accept\n'
wrapped review 'Round\302\2402 found it.\n'
wrapped review 'Commit\r\nreview accept\r\n'
wrapped review 'Commit \n  review accept\n'
wrapped label 'milestone\n  2 decides\n'
out="$(printf 'plain\nThis waits for\n  their yes.\nplain\nCommit review: ok\n' | "$mc")"
expect_eq "line 2: approval: This waits for" "$(printf '%s\n' "$out" | sed -n 1p)" "a wrapped note reports its first line"
expect_eq "line 5: review: Commit review: ok" "$(printf '%s\n' "$out" | sed -n 2p)" "a later finding keeps its line number"

printf 'ok line\nCommit review: accept\n' > "$tmp/m.txt"
out="$("$mc" "$tmp/m.txt")"; expect_rc 1 $? "a flagged FILE exits 1"
expect_eq "line 2: review: Commit review: accept" "$(printf '%s\n' "$out" | head -1)" "a finding prints 'line N: rule: text'"
expect_eq 1 "$(printf '%s\n' "$out" | grep -c '^fix: ')" "one fix line"
expect_grep '^fix: .*\.local/reviews/COMMIT\.md' "$out" "the review fix names the review file"
expect_grep '^fix: .*ctlhq-message-check --help' "$out" "the fix line points to the ways out"
out="$(printf 'operator approved\nmilestone 3\n.local/plans/a\n' | "$mc")"; expect_rc 1 $? "standard input is read"
expect_grep '^fix: .*PLAN\.md section 10' "$out" "the approval fix names the approvals table"
expect_grep '^fix: .*PLAN\.md section 7' "$out" "the label fix names the milestone record"
expect_nogrep '^fix: .*\.local/reviews/COMMIT\.md' "$out" "the fix line names only the rules found"
out="$(printf 'round 2 \033[2Jhidden\n' | "$mc")"
if printf '%s' "$out" | LC_ALL=C grep -q "$(printf '\033')"; then bad "a control byte reaches the terminal"; else ok; fi
expect_grep 'round 2 \?\[2Jhidden' "$out" "a control byte prints as ?"

for b in m2-safety m1 M4-adoption milestone-3-x milestone2 m0-round-trip internal-notes-m0 notes-M12 notes-milestone-2 notes-milestone2 fix/m3; do
  out="$("$mc" --branch "$b")"; expect_rc 1 $? "--branch $b exits 1"
  expect_grep "^branch: $b\$" "$out" "--branch $b names the branch"
  expect_grep '^fix: ' "$out" "--branch $b has a fix line"
done
for b in ci-gate main m1x-core audit-fixes-next-train team-m2-safety notes-m1x notes-m notes-am2 notes-milestone; do
  "$mc" --branch "$b" >/dev/null; expect_rc 0 $? "--branch $b exits 0"
done

newrepo h
commit "$tmp/h" "first clean commit"
commit "$tmp/h" "$(printf 'second\n\nCommit review: accept\n.local/reviews/a.md\n')"
git -C "$tmp/h" checkout -q -b side
commit "$tmp/h" "side clean commit"
git -C "$tmp/h" checkout -q main
git -C "$tmp/h" merge -q --no-ff -m "Milestone 2: merge the side branch" side
out="$("$mc" --history --root "$tmp/h")"; expect_rc 1 $? "--history with flagged commits exits 1"
expect_eq "flagged: 2 of 4" "$(printf '%s\n' "$out" | tail -1)" "--history counts the merge commit"
merge="$(git -C "$tmp/h" rev-parse HEAD)"
expect_grep "^${merge:0:12}: line 1: label$" "$out" "--history prints the merge commit's line and rule"
second="$(git -C "$tmp/h" rev-parse HEAD~1)"
expect_grep "^${second:0:12}: line 3: review; line 4: path$" "$out" "--history prints one line per flagged commit"
expect_eq 3 "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" "two commit lines and the count"
git -C "$tmp/h" config log.showSignature true
expect_eq "flagged: 2 of 4" "$("$mc" --history --root "$tmp/h" 2>/dev/null | tail -1)" "log.showSignature does not change the count"
git -C "$tmp/h" checkout -q -b unmerged
commit "$tmp/h" "unmerged: commit review"
unmerged="$(git -C "$tmp/h" rev-parse HEAD)"
git -C "$tmp/h" checkout -q --detach main
commit "$tmp/h" "tagged: commit review"
tagged="$(git -C "$tmp/h" rev-parse HEAD)"
git -C "$tmp/h" tag v1
git -C "$tmp/h" checkout -q main
out="$("$mc" --history --root "$tmp/h")"; expect_rc 1 $? "--history with a tag and an unmerged branch exits 1"
expect_eq "flagged: 4 of 6" "$(printf '%s\n' "$out" | tail -1)" "--history counts a tag and an unmerged branch"
expect_grep "^${unmerged:0:12}: line 1: review$" "$out" "--history reads an unmerged branch"
expect_grep "^${tagged:0:12}: line 1: review$" "$out" "--history reads a commit only a tag reaches"
newrepo clean; commit "$tmp/clean" "one clean commit"
out="$("$mc" --history --root "$tmp/clean")"; expect_rc 0 $? "--history with no flagged commit exits 0"
expect_eq "flagged: 0 of 1" "$out" "--history prints the count alone"

newrepo n
git init -q --bare "$tmp/n.git"
git -C "$tmp/n" remote add origin "$tmp/n.git"
commit "$tmp/n" "already pushed: commit review"
git -C "$tmp/n" push -q origin main
commit "$tmp/n" "new clean commit"
out="$("$mc" --new-only --root "$tmp/n")"; expect_rc 0 $? "--new-only skips a flagged commit the remote holds"
expect_eq "flagged: 0 of 1" "$out" "--new-only counts only the new commit"
commit "$tmp/n" "new flagged: commit review"
out="$("$mc" --history --new-only --root "$tmp/n")"; expect_rc 1 $? "--history --new-only flags a new commit"
expect_eq "flagged: 1 of 2" "$(printf '%s\n' "$out" | tail -1)" "--history --new-only counts two new commits"
expect_eq "flagged: 2 of 3" "$("$mc" --history --root "$tmp/n" | tail -1)" "--history alone counts all three"

printf '\n   \n# a comment line\n' > "$HOME/.ctlhq/message-words.txt"
out="$(printf 'a plain line\n\n' | "$mc")"; expect_rc 0 $? "empty lines and a comment in a list flag nothing"
expect_eq "" "$out" "a list of empty lines prints nothing"
printf 'Zebrafinch\n' > "$HOME/.ctlhq/message-words.txt"
out="$(printf 'plain\nthe zebrafinch project\n' | "$mc")"; expect_rc 1 $? "a listed word exits 1"
expect_eq "line 2: extra-word: the ********** project" "$(printf '%s\n' "$out" | head -1)" "a listed word prints its line with the word starred out"
expect_nogrep 'zebrafinch|Zebrafinch' "$out" "the listed word is absent from the output"
out="$(printf 'zebrafinch: commit review\n' | "$mc")"; expect_rc 1 $? "a line with a listed word and a rule exits 1"
expect_eq "extra-word,review" "$(rules_of "$out")" "that line names both rules"
expect_nogrep 'zebrafinch|Zebrafinch' "$out" "the rule's line text is hidden too"
newrepo w; commit "$tmp/w" "the zebrafinch subject"
out="$("$mc" --history --root "$tmp/w")"; expect_rc 1 $? "--history flags a listed word"
expect_grep ': line 1: extra-word$' "$out" "--history prints line 1: extra-word"
expect_nogrep 'zebrafinch|Zebrafinch' "$out" "--history hides the listed word"
for line in 'zebrafinch_worker' 'zebrafinch2' '2zebrafinch' 'a_zebrafinch_b'; do
  printf '%s\n' "$line" | "$mc" >/dev/null; expect_rc 1 $? "'$line' holds the listed word"
done
expect_eq "line 1: extra-word: **********_worker round 2" "$(printf 'zebrafinch_worker round 2\n' | "$mc" | head -1)" "a word joined to _ never prints in plain text"
"$mc" --branch zebrafinch_x >/dev/null; expect_rc 1 $? "--branch finds a word joined to _"
for line in 'the zebrafinches' 'ZebrafinchApp'; do
  printf '%s\n' "$line" | "$mc" >/dev/null; expect_rc 0 $? "'$line' needs its own list line"
done
out="$("$mc" --branch m2-zebrafinch)"; expect_rc 1 $? "--branch with a rule and a listed word exits 1"
expect_eq 'branch: m2-**********' "$(printf '%s\n' "$out" | head -1)" "--branch stars out the listed word"
out="$("$mc" --branch zebrafinch-x)"; expect_rc 1 $? "--branch with a listed word alone exits 1"
expect_eq 'branch: **********-x' "$(printf '%s\n' "$out" | head -1)" "--branch names the starred branch"
expect_grep '^fix: ' "$out" "--branch with a listed word has a fix line"
"$mc" --branch zebrafinches >/dev/null; expect_rc 0 $? "--branch matches whole words only"

printf 'OS\n' > "$HOME/.ctlhq/message-words.txt"
for line in 'Support macOS 15.' 'Measure the cost of a send.' 'Fix cosine similarity.' 'the COSMOS project'; do
  printf '%s\n' "$line" | "$mc" >/dev/null; expect_rc 0 $? "'$line' holds no whole listed word"
done
for line in 'Run an OS image.' 'os: the first step' '(OS)' 'the OS-steps' 'OS_steps' 'OS2'; do
  printf '%s\n' "$line" | "$mc" >/dev/null; expect_rc 1 $? "'$line' holds the listed word"
done
expect_eq "line 1: extra-word: Run an ** image." "$(printf 'Run an OS image.\n' | "$mc" | head -1)" "the refusal shows where the word is, so the agent can reword"
printf 'zebrafinch # the name\n' > "$HOME/.ctlhq/message-words.txt"
printf 'the zebrafinch line\n' | "$mc" >/dev/null; expect_rc 1 $? "a comment after a listed word does not hide it"
printf 'c#\n' > "$HOME/.ctlhq/message-words.txt"
printf 'use c# here\n' | "$mc" >/dev/null; expect_rc 1 $? "a # joined to a listed word stays part of it"
printf 'zebra finch\nc++\n' > "$HOME/.ctlhq/message-words.txt"
printf 'the zebra\n\nfinch line\n' | "$mc" >/dev/null; expect_rc 0 $? "a listed phrase does not reach across a blank line"
out="$(printf 'plain\nthe zebra\n  finch line\nCommit review\n' | "$mc")"; expect_rc 1 $? "a listed phrase across a line break exits 1"
expect_eq "line 2: extra-word: the *****" "$(printf '%s\n' "$out" | sed -n 1p)" "a wrapped phrase reports its first line, starred"
expect_eq "line 4: review: Commit review" "$(printf '%s\n' "$out" | sed -n 2p)" "starring a wrapped phrase keeps later line numbers"
expect_nogrep 'zebra|finch' "$out" "no part of a wrapped phrase prints"
printf 'use c++ here\n' | "$mc" >/dev/null; expect_rc 1 $? "a listed word with regex characters is read as plain text"
printf 'use c here\n' | "$mc" >/dev/null; expect_rc 0 $? "regex characters in a listed word match only themselves"
printf 'alpha beta\nbeta gamma\n' > "$HOME/.ctlhq/message-words.txt"
out="$(printf 'alpha beta gamma\n' | "$mc")"; expect_nogrep 'alpha|beta|gamma' "$out" "two overlapping listed phrases both stay hidden"
printf '\357\273\277Zebrafinch\n' > "$HOME/.ctlhq/message-words.txt"
printf 'the zebrafinch line\n' | "$mc" >/dev/null; expect_rc 1 $? "a byte order mark does not hide the first listed word"
: > "$HOME/.ctlhq/message-words.txt"

newrepo p; commit "$tmp/p" "base"; mkdir "$tmp/p/.local"
printf 'projectword\n' > "$tmp/p/.local/message-words.txt"
out="$(printf 'the projectword line\n' | "$mc" --root "$tmp/p")"; expect_rc 1 $? "the project list is read through --root"
expect_eq "line 1: extra-word: the *********** line" "$(printf '%s\n' "$out" | head -1)" "the project list flags its word"
(cd "$tmp/p" && printf 'the projectword line\n' | "$mc" >/dev/null); expect_rc 1 $? "the project list is read from the current folder"
git -C "$tmp/p" worktree add -q "$tmp/p-linked"
printf 'the projectword line\n' | "$mc" --root "$tmp/p-linked" >/dev/null; expect_rc 1 $? "a linked worktree reads the main worktree's list"
printf 'the projectword line\n' | "$mc" --root "$tmp/clean" >/dev/null; expect_rc 0 $? "another repository does not read that list"

rm "$HOME/.ctlhq/message-words.txt"; mkdir "$HOME/.ctlhq/message-words.txt"
err="$(printf 'plain\n' | "$mc" 2>&1)"; expect_rc 2 $? "an unreadable list exits 2"
expect_grep "$HOME/\.ctlhq/message-words\.txt" "$err" "the failure names which list"
rmdir "$HOME/.ctlhq/message-words.txt"
ln -s "$tmp/nowhere" "$HOME/.ctlhq/message-words.txt"
printf 'the zebrafinch line\n' | "$mc" >/dev/null 2>&1; expect_rc 2 $? "a dangling list link exits 2"
"$mc" --branch ci-gate >/dev/null 2>&1; expect_rc 2 $? "--branch with a dangling list link exits 2"
"$mc" --history --root "$tmp/clean" >/dev/null 2>&1; expect_rc 2 $? "--history with a dangling list link exits 2"
rm "$HOME/.ctlhq/message-words.txt"
ln -s "$HOME/.ctlhq/message-words.txt" "$HOME/.ctlhq/message-words.txt"
printf 'plain\n' | "$mc" >/dev/null 2>&1; expect_rc 2 $? "a looping list link exits 2"
rm "$HOME/.ctlhq/message-words.txt"
rm "$tmp/p/.local/message-words.txt"; ln -s "$tmp/nowhere" "$tmp/p/.local/message-words.txt"
err="$(printf 'plain\n' | "$mc" --root "$tmp/p" 2>&1)"; expect_rc 2 $? "a dangling project list link exits 2"
expect_grep '\.local/message-words\.txt' "$err" "the failure names the project list"
rm "$tmp/p/.local/message-words.txt"; rmdir "$tmp/p/.local"
ln -s "$tmp/nowhere" "$tmp/p/.local"
printf 'plain\n' | "$mc" --root "$tmp/p" >/dev/null 2>&1; expect_rc 2 $? "a dangling .local link exits 2"
rm "$tmp/p/.local"; : > "$tmp/p/.local"
printf 'plain\n' | "$mc" --root "$tmp/p" >/dev/null 2>&1; expect_rc 2 $? "a .local that is a plain file exits 2"
rm "$tmp/p/.local"
printf 'plain\n' | "$mc" --root "$tmp/p" >/dev/null 2>&1; expect_rc 0 $? "an absent .local means no list"
chmod 000 "$HOME/.ctlhq"
printf 'plain\n' | "$mc" >/dev/null 2>&1; expect_rc 2 $? "a locked list folder exits 2"
chmod 755 "$HOME/.ctlhq"; rmdir "$HOME/.ctlhq"
printf 'plain\n' | "$mc" >/dev/null 2>&1; expect_rc 0 $? "an absent list folder means no list"
ln -s "$tmp/nowhere" "$HOME/.ctlhq"
err="$(printf 'the zebrafinch line\n' | "$mc" 2>&1)"; expect_rc 2 $? "a dangling list folder link exits 2"
expect_grep '\.ctlhq' "$err" "the failure names the list folder"
rm "$HOME/.ctlhq"; ln -s "$HOME/.ctlhq" "$HOME/.ctlhq"
printf 'plain\n' | "$mc" >/dev/null 2>&1; expect_rc 2 $? "a looping list folder link exits 2"
rm "$HOME/.ctlhq"; : > "$HOME/.ctlhq"
printf 'plain\n' | "$mc" >/dev/null 2>&1; expect_rc 2 $? "a list folder that is a plain file exits 2"
"$mc" --branch ci-gate >/dev/null 2>&1; expect_rc 2 $? "--branch with a broken list folder exits 2"
rm "$HOME/.ctlhq"

echo "$pass checks passed"
if [ "$fail" -gt 0 ]; then echo "$fail checks failed"; exit 1; fi
exit 0
