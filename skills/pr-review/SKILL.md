---
name: pr-review
description: Review a pull request with two fresh reviewers, one on the whole diff and one on its fit in the repository. Use before the code-ready push of a pull request, the push after which its code is meant to merge. For a pull request opened with its finished code, that is the push that opens it. Each of its commits has passed commit-review first.
---

# PR review

Both reviewers are set up per the **commit-review** skill. Its section 1 says what a reviewer receives and never receives, and its section 2 picks the model. The diff is the whole pull request, `git diff <base>...<head>`.

## 1. Steps

1. Run commit-review's section 3 steps 1 and 2 on the pull request's head. They run the **no-comments** skill on the whole diff, then the gate.
2. Start both reviewers at once. Neither sees the other's report.
   1. **Reviewer A, the diff.** The commit-review brief over the whole pull request.
   2. **Reviewer B, fit in the repository.** The brief below.
3. Save both reports to `.local/reviews/pr-<branch>-a.md` and `-b.md`. A fix reopens both reviews for the files it changed.
4. The pull request is ready to push only when both verdicts are accept.

## 2. Reviewer B's brief

```
You are reviewing how a pull request you did not write fits the whole repository. Read only
the inputs listed, and read beyond the diff: the code, skills, tests, and docs it touches or
repeats. Change no files.
Question 1: which existing pattern, name, or output format does it break?
Question 2: which doc, help text, or skill now disagrees with the code or with another doc?
Question 3: what in the repository could now be deleted because of this change?
Then answer questions 4 to 9 in <absolute path of ../commit-review/references/questions.md>
for the repository as it would be after the merge.
Report: 1. verdict (accept / fix first / reject); 2. defects, each with file, line, the
question it fails, and how to reproduce; 3. what you read and ran, with exit codes; 4. what
you did not check. "I did not check" is a valid line.
```
