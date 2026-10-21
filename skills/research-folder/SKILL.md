---
name: research-folder
description: "Study outside work (prior art, a competing tool, an admired engineer's repositories), compare our project with it, and keep the result as a research folder: numbered files, an index, attributed reference copies, a sources-and-gaps file, and a confidence label on every claim. Use when the operator asks to research, compare, or learn from external work."
disable-model-invocation: true
---

# Research folder

The result of a study is a folder another reader can trust and extend. Every claim says how sure it is, every copied document says where it came from, and every gap is written down.

## Tool

`bin/ctlhq-research-folder` (a symlink to `skills/research-folder/bin/ctlhq-research-folder`) makes and checks the folder. `ctlhq-research-folder --help` lists the rules and exit codes.

```
bin/ctlhq-research-folder init <dir> <topic>   # README.md index, 01 to 04 files, reference/
bin/ctlhq-research-folder check <dir>          # index names every file, claims carry labels, copies carry Source: lines
```

## Steps

1. Restate the question, the sources the operator named, and what is out of scope. Then run `bin/ctlhq-research-folder init <dir> <topic>`. Default `<dir>` is `docs/research/<topic>/` in the project, or a new folder when there is no project.
2. Collect sources. Prefer primary ones: the code, the official docs, the author's own writing. Copy a document you rely on into `reference/` only when its license allows copying. Give the copy a first line `Source: <url> (retrieved <YYYY-MM-DD>)` with the license, and add a row for it in `README.md`. When the license is unknown or does not allow copying, link the document instead of copying it. List every source in `04-sources-and-gaps.md` with the date read.
3. When a repository or page is gone, use the public page that remains (a package registry page, an archived copy, a mirror the author named). Mark it "public page fallback" in the sources file and lower the label of claims that rest on it.
4. Write each finding as a numbered line with one label and the reference file it rests on. Keep prose for the summary at the top only. Labels: `[high]` seen in a primary source or tested, `[medium]` one secondary source or inferred, `[low]` a guess or one unconfirmed report.
5. Fill `03-prior-art.md`: for each area, what we do, what they do, and the verdict. List where our project is better, where it is worse, and what it is missing. Every row carries a label.
6. Write every gap in `04-sources-and-gaps.md`: what is unknown, why, and what would close it. A gap is a result. Do not hide it.
7. Run `bin/ctlhq-research-folder check <dir>` and act on every row's fix cell until it prints 0 problems.
8. Product documents state each idea in our own words. A README, a PRD, release notes, or user-facing text credits outside work once, in a credits section that names the project or person and its license. Outside that section, product documents do not name the source. The full names and links stay in the research folder.
9. Reply contract: the folder path, the `check` summary line, the three strongest findings with labels, the better, worse, and missing counts, and the open gaps.
