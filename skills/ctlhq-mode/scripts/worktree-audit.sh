#!/usr/bin/env bash
# Worktree prune audit. Classifies every git worktree by size, merge state,
# uncommitted work, remote/PR state, and the most recent chat that operated in
# it. Emits a table sorted by size with a suggested bucket. Never deletes
# anything; deletion stays a human-gated step in the playbook.
#
# Usage: worktree-audit.sh [-b|--base <ref>] [--no-fetch] [--recent-days <n>] [repo-path]
#   repo-path defaults to the current repo.
#   -b sets the ref the MERGED column checks against (e.g. origin/integration).
#   Without it the base is origin/HEAD, then origin/main, then origin/master.
#   origin/HEAD is the remote's default branch, not necessarily the branch PRs
#   merge into; pass -b when they differ.
#   --no-fetch skips the `git fetch origin` of an origin/* base. The default
#   fetch uses the network and writes remote-tracking refs, so a default run is
#   not read-only in that sense; the worktrees themselves are never written.
#   --recent-days <n>: a chat within the last n days puts the worktree in
#   verify-recent-chat (default 4).
# REMOTE: pushed, ahead<n>, behind<n>, ahead<n>-behind<m> (diverged), no-remote, detached.
# Buckets: hold-wip, hold-open-pr, verify-recent-chat, safe (commit in the base
# or PR merged), review (everything else, including a PR closed without merge).
# Timestamps use BSD stat -f and date -r (macOS); GNU stat -c and date -d are
# the fallback.
# Exit 0 after the table, 1 when not in a git repo or no base ref, 2 on a usage error.
# Every error prints "ctlhq-worktree-audit: <what>", "why: <why>", and "fix: <command>" on stderr.
set -u

# die <exit code> <what> <why> <fix>
die() { printf 'ctlhq-worktree-audit: %s\nwhy: %s\nfix: %s\n' "$2" "$3" "$4" >&2; exit "$1"; }
q() { printf '%q' "$1"; }
why_base="MERGED checks each worktree's commit against that ref"
why_days="--recent-days sets how many days back a chat puts a worktree in verify-recent-chat"
why_repo="ctlhq-worktree-audit lists the worktrees of one git repository"

base=""
fetch=yes
recent_days=4
while [ $# -gt 0 ]; do
	case "$1" in
	-b|--base) [ $# -ge 2 ] || die 2 "$1 needs a ref" "$why_base" "ctlhq-worktree-audit $1 <ref> [repo-path], for example $1 origin/main"
		base="$2"; shift 2 ;;
	--no-fetch) fetch=no; shift ;;
	--recent-days) [ $# -ge 2 ] || die 2 "$1 needs a number of days" "$why_days" "ctlhq-worktree-audit --recent-days 4 [repo-path]"
		case "$2" in ''|*[!0-9]*) die 2 "--recent-days needs a whole number, got: $2" "$why_days" "ctlhq-worktree-audit --recent-days 4 [repo-path]" ;; esac
		recent_days="$2"; shift 2 ;;
	-h|--help) sed -n '2,/^set -u/p' "$0" | sed '$d; s/^# \{0,1\}//'; exit 0 ;;
	-*) die 2 "unknown option: $1" "ctlhq-worktree-audit takes only -b/--base, --no-fetch, --recent-days, and a repo path" "ctlhq-worktree-audit --help" ;;
	*) break ;;
	esac
done

repo="${1:-$(git rev-parse --show-toplevel 2>/dev/null)}"
[ -z "$repo" ] && die 1 "not in a git repo: $PWD" "$why_repo, and with no repo-path it uses the current folder" "ctlhq-worktree-audit <path to the repository>"
[ -d "$repo" ] || die 1 "repo path not found: $repo" "$why_repo, and that folder does not exist" "ctlhq-worktree-audit <path to the repository>"
cd "$repo" || die 1 "cannot enter the repo path: $repo" "$why_repo, and its folder must be readable" "ls -ld $(q "$repo")"
git rev-parse --git-dir >/dev/null 2>&1 || die 1 "not a git repo: $repo" "$why_repo, and that folder is not inside one" "ctlhq-worktree-audit <path to the repository>"

# Main worktree is the first entry; everything else is a candidate.
# sed keeps the whole path; a path may hold spaces.
main_wt=$(git worktree list --porcelain | sed -n 's/^worktree //p' | head -1)

if [ -z "$base" ]; then
	for cand in "$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)" origin/main origin/master; do
		[ -n "$cand" ] && git rev-parse --verify --quiet "$cand^{commit}" >/dev/null && { base="$cand"; break; }
	done
	if [ -z "$base" ]; then
		cur="$(git symbolic-ref --quiet --short HEAD 2>/dev/null)"
		die 1 "no base ref in $repo: origin/HEAD, origin/main, and origin/master are all missing" \
			"MERGED needs a base ref to check each worktree's commit against" \
			"ctlhq-worktree-audit -b ${cur:-<ref>} $(q "$repo") (or another ref that \`git -C $(q "$repo") branch -a\` lists)"
	fi
	echo "warn: no -b given; MERGED checks against $base" >&2
fi

# The base drives the merge check. The fetch is best-effort (stale is fine for
# a first pass) and runs before the check, since -b may name a branch not
# fetched yet. The explicit refspec creates it even in a single-branch clone.
# --no-fetch skips it, for an offline or strictly read-only run.
if [ "$fetch" = yes ]; then
	case "$base" in
	origin/*) git fetch origin "+refs/heads/${base#origin/}:refs/remotes/$base" --quiet 2>/dev/null \
		|| printf 'warn: could not fetch %s; merged column may be stale\nfix: git -C %s fetch origin (to see the error), or pass --no-fetch\n' "$base" "$(q "$repo")" >&2 ;;
	esac
fi
if ! git rev-parse --verify --quiet "$base^{commit}" >/dev/null 2>&1; then
	hint=""
	case "$base" in origin/*) [ "$fetch" = no ] && hint=", or drop --no-fetch so the audit fetches it" ;; esac
	die 1 "base ref not found: $base" "$why_base, and $repo has no such ref" \
		"ctlhq-worktree-audit -b <ref> $(q "$repo") with a ref that \`git -C $(q "$repo") branch -a\` lists$hint"
fi

# PR state by branch, fetched once from gh as [{number, state, head}] with a
# lowercase state. Empty when gh cannot read this repo's PRs.
prs=$(mktemp)
if raw=$(gh pr list --author "@me" --state all --limit 1000 \
	--json number,state,headRefName 2>/dev/null); then
	printf '%s' "$raw" | jq '[.[] | {number, state: (.state | ascii_downcase), head: .headRefName}]' > "$prs" 2>/dev/null
fi
[ -s "$prs" ] || echo "[]" > "$prs"

# Claude Code keeps a workspace's chats in ~/.claude/projects/<workspace path with
# "/" as "-">, or with "/", ".", and "_" as "-"; both forms are tried, as
# ctlhq-transcripts does. Codex files every chat by date under ~/.codex/sessions.
claude_dirs() { # path: the Claude Code transcript folders of that workspace that exist
	for s in "$(printf '%s' "$1" | sed 's#/#-#g')" "$(printf '%s' "$1" | sed 's#[/._]#-#g')"; do
		[ -d "$HOME/.claude/projects/$s" ] && printf '%s\n' "$HOME/.claude/projects/$s"
	done | sort -u
}
now=$(date +%s)

# GNU stat and date first (BSD stat has no -c); BSD forms (macOS) otherwise.
if stat -c '%Y' . >/dev/null 2>&1; then
	mtimes() { xargs stat -c '%Y %n' 2>/dev/null; }
	ymd() { date -d "@$1" '+%Y-%m-%d' 2>/dev/null; }
else
	mtimes() { xargs stat -f '%m %N' 2>/dev/null; }
	ymd() { date -r "$1" '+%Y-%m-%d' 2>/dev/null; }
fi

echo "# base: $base"
printf "SIZE\tAGE\tMERGED\tDIRTY\tREMOTE\tPR\tLAST_CHAT\tBUCKET\tWORKTREE\n"

git worktree list --porcelain | sed -n 's/^worktree //p' | while IFS= read -r wt; do
	[ "$wt" = "$main_wt" ] && continue

	size=$(du -sh "$wt" 2>/dev/null | awk '{print $1}')
	head=$(git -C "$wt" rev-parse HEAD 2>/dev/null)
	head_ts=$(git -C "$wt" log -1 --format='%ct' HEAD 2>/dev/null || echo 0)
	age=$([ "$head_ts" -gt 0 ] 2>/dev/null && echo "$(( (now - head_ts) / 86400 ))d" || echo "?")

	# Squash-merged branches are not ancestors of the base, so PR state is the
	# real signal; merge-base only catches fast-forward/rebase merges.
	git merge-base --is-ancestor "$head" "$base" 2>/dev/null && merged=YES || merged=no

	# Distinguish real WIP (tracked edits) from disposable untracked scratch.
	porcelain=$(git -C "$wt" status --porcelain 2>/dev/null)
	if [ -z "$porcelain" ]; then dirty=clean
	elif printf '%s\n' "$porcelain" | grep -qv '^??'; then
		dirty="wip:$(printf '%s\n' "$porcelain" | grep -cv '^??')"
	else dirty="scratch:$(printf '%s\n' "$porcelain" | grep -c '^??')"; fi

	branch=$(git -C "$wt" symbolic-ref --quiet --short HEAD 2>/dev/null || echo "")
	if [ -z "$branch" ]; then remote=detached
	elif git -C "$wt" show-ref --verify --quiet "refs/remotes/origin/$branch"; then
		# --left-right prints "<behind> <ahead>": commits only on origin, then only local.
		read -r behind ahead <<< "$(git -C "$wt" rev-list --left-right --count "origin/$branch...HEAD" 2>/dev/null)"
		behind="${behind:-0}"; ahead="${ahead:-0}"
		if [ "$behind" -eq 0 ] && [ "$ahead" -eq 0 ]; then remote=pushed
		elif [ "$behind" -eq 0 ]; then remote="ahead$ahead"
		elif [ "$ahead" -eq 0 ]; then remote="behind$behind"
		else remote="ahead$ahead-behind$behind"; fi
	else remote=no-remote; fi

	pr=$([ -n "$branch" ] && jq -r --arg b "$branch" \
		'.[] | select(.head==$b) | "#\(.number)/\(.state)"' "$prs" 2>/dev/null | head -1)
	[ -z "$pr" ] && pr="-"

	# Most recent chat whose transcript operated in this worktree: the main
	# worktree's and this worktree's Claude Code folders, and every Codex session on the machine.
	# Match path followed by "/" or a quote so glint-482 does not match glint-482-r37.
	last="-"; last_ts=0
	dirs=()
	while IFS= read -r d; do [ -n "$d" ] && dirs+=("$d"); done <<< "$(claude_dirs "$main_wt"; claude_dirs "$wt")"
	[ -d "$HOME/.codex/sessions" ] && dirs+=("$HOME/.codex/sessions")
	if [ ${#dirs[@]} -gt 0 ]; then
		f=$(rg -l -F -e "${wt}/" -e "${wt}\"" "${dirs[@]}" 2>/dev/null \
			| mtimes | sort -rn | head -1)
		if [ -n "$f" ]; then last_ts=$(echo "$f" | awk '{print $1}')
			last=$(ymd "$last_ts"); fi
	fi
	recent=$([ "$last_ts" -gt 0 ] 2>/dev/null && [ $(( (now - last_ts) / 86400 )) -le "$recent_days" ] && echo yes || echo no)

	case "$dirty" in wip:*) bucket=hold-wip ;; *)
		case "$pr" in */open|*/draft) bucket=hold-open-pr ;; *)
			# A PR closed without merge is unmerged work, so only */merged counts as safe.
			if [ "$recent" = yes ]; then bucket=verify-recent-chat
			elif [ "$merged" = YES ]; then bucket=safe
			else case "$pr" in */merged) bucket=safe ;; *) bucket=review ;; esac; fi ;;
		esac ;;
	esac

	printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
		"$size" "$age" "$merged" "$dirty" "$remote" "$pr" "$last" "$bucket" "$wt"
done | sort -t$'\t' -k1,1 -rh

rm -f "$prs"
