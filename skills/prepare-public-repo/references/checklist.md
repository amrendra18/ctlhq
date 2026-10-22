# Public-readiness checklist

Every reviewer does every item. Only the current files matter, because one fresh commit will replace the history.
"The listed files" means every tracked file plus every untracked file that `.gitignore` does not ignore. `git ls-files -co --exclude-standard` lists them.

## Default split

The reviewer changes the file in its copy for a "change" item, and writes a proposal for a "propose" item. The operator may move an item in Confirm.

| # | Kind | Items |
| --- | --- | --- |
| 1 | change | 1 personal data and secrets, 2 internal language, 4 docs for strangers, 5 tracked versus ignored, 6 code correctness, 7 checks |
| 2 | propose | 3 license and attribution, the banner, removing a dependency, the project's own name on the word list |

## 1. Personal data and secrets

| # | Check | How |
| --- | --- | --- |
| 1 | Private word list | `ctlhq-privacy-scan --root <worktree>` and then `--joined`. Read the exit code directly. Each hit gives file:line and the word number; it never prints the word. |
| 2 | Joined hits | Read each `joined` line. Pieces of one name or string, joined across quotes, `+`, or a line break, are a real hit. Separate words of ordinary text that happen to spell a private word are a false positive; say so in the report. |
| 3 | Secrets | Copy the listed files to a new, empty scratch folder, then run Gitleaks on that copy (commands below). Search by hand for key shapes, such as private key headers, `AKIA`, `ghp_`, `sk-`, `xox`, and passwords in URLs. A test fixture with a fake value is fine when it is clearly fake; say why. |
| 4 | Machine details | Home-folder paths (`/Users/<name>/`, `/home/<name>/`), machine and host names, local IP addresses, user names, temp-folder paths with session IDs. |
| 5 | Identities | Email addresses and names other than the intended public identity and credited authors. |

Accept the owner's name in the repository's own address, the copyright line, and the commit author. Report it anywhere else.

Gitleaks may not be on PATH. `ctlhq-first-push` first looks for it at `~/.ctlhq/bin/gitleaks`, so look there too.

```bash
cd <worktree>
git ls-files -co --exclude-standard -z | xargs -0 sh -c 'for f; do [ -e "$f" ] || [ -L "$f" ] && printf "%s\0" "$f"; done' sh > <scratch>/listed.z
rsync -a --from0 --files-from=<scratch>/listed.z ./ <scratch>/tree/
echo "rsync exit $?"
test "$(tr -cd '\0' < <scratch>/listed.z | wc -c)" -eq "$(find <scratch>/tree \( -type f -o -type l \) -print0 | tr -cd '\0' | wc -c)"
echo "count check exit $?"
gitleaks dir <scratch>/tree --redact --no-banner
git ls-files -co --exclude-standard -z | xargs -0 grep -nIE '/(Users|home)/[A-Za-z0-9._-]+/' /dev/null | cut -d: -f1,2
```

1. `<scratch>/tree` is a new, empty folder. The first line lists only the files that exist on disk, so a tracked file deleted in the copy is left out.
2. `rsync` must exit 0, and the count check must exit 0, so the copy holds every listed file. Otherwise stop and report it. The rsync that macOS ships (openrsync) exits 23 on a symbolic link whose target is missing.
3. `gitleaks dir` exits 0 with no leak and 1 with a leak. `--redact` hides the secret in its output.
4. The last line prints only file:line for each home-folder path, so no user name reaches the output.

## 2. Internal language

| # | Check |
| --- | --- |
| 1 | Notes written for the operator or for agents, such as approvals, quotes of the operator's words, session dates, and "decided on" lines. |
| 2 | Names of private projects, private repositories, and private tools. |
| 3 | Old names of the project and its parts, outside a Credits section. |
| 4 | Dates and details that reveal private activity. |
| 5 | Links to private places, such as local paths, private repositories, and internal hosts. |

## 3. License and attribution

The operator picks the license in Confirm. The reviewer checks the files against that pick.

| # | Check |
| --- | --- |
| 1 | `LICENSE` holds the exact standard text of the chosen license, with the right year and holder. |
| 2 | Every adapted work keeps its own copyright notice, as its license requires. |
| 3 | Credits are factual and modest. They name the adapted work, its source, and its license. |
| 4 | The README names the license and points to `LICENSE`. It holds no copyright line of its own. |

## 4. Docs for strangers

| # | Check |
| --- | --- |
| 1 | The README's top says what the project is, why to use it, and gives a start command of one or two lines. One line may join commands with `&&`. |
| 2 | A short section index follows. The rest reads as one story from top to end. |
| 3 | The README states requirements and supported platforms, for example "Runs on macOS only, for now." |
| 4 | One short "provided as is, without warranty; see LICENSE" line. |
| 5 | Line 1 is `<!-- banner -->` when the operator wants a banner later. |
| 6 | Every command and fact in every doc matches the code. Read the code to check. |
| 7 | Every other doc earns its own file. Keep, merge, or delete each one, with a one-line reason. A doc that a tool or test reads changes together with that tool or test. Search the code for each doc's file name before you move or delete it. |
| 8 | `SECURITY.md` says how to report a problem privately. `CONTRIBUTING.md` says how to run the checks. |

## 5. Tracked versus ignored

| # | Check | How |
| --- | --- | --- |
| 1 | Every tracked file should be public | `git ls-files`, judged file by file. |
| 2 | `.gitignore` covers every local file | `GIT_OPTIONAL_LOCKS=0 git -C <project> status --ignored --short` in the main folder, which keeps the command read-only. Each untracked local file needs a `.gitignore` pattern. |
| 3 | No tracked file is also ignored | `git ls-files -ci --exclude-standard` prints nothing. |
| 4 | No generated output, caches, logs, `.env` files, keys, editor or OS files, or large binaries | A generated file that a command can rebuild leaves the tree; the command writes it into an ignored folder. |
| 5 | No file ignored only through `.git/info/exclude` | That file goes away with `.git`. Move each pattern into `.gitignore`. |

## 6. Code correctness

| # | Check |
| --- | --- |
| 1 | Correctness bugs. Fix each real bug with a test that fails before the fix. |
| 2 | Dead code, unclear names, comments that only restate the code. |
| 3 | Dependencies the code neither imports nor runs. Propose each removal; do not remove it in your copy. |
| 4 | Anything judged and left as it is, with the reason. |

`/project-audit` at `quick` depth covers this item when the operator prefers a full audit.

## 7. Checks

| # | Check |
| --- | --- |
| 1 | The gate named in Confirm exits 0 in the reviewer's copy. |
| 2 | `ctlhq-privacy-scan --root <worktree>` exits 0, or each hit is an accepted owner's-name hit. |
| 3 | `gitleaks dir` on the copy of the listed files exits 0. |
| 4 | `git diff --quiet -- <protected paths>` exits 0, so no protected file changed. |
| 5 | `git status --short` and `git diff --stat`, including deletions and new files. |
