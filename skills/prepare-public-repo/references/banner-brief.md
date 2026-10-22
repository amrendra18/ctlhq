# Banner brief template

A banner is the image on the README's first line. Round 1 gives 5 distinct ideas. Round 2 takes the operator's picks and feedback and gives 2 tagline variants for each kept idea.
The picked file goes to `.github/banner.svg`. README line 1 becomes a Markdown image of that file. Its alt text is the project name and the tagline, joined by a colon and a space.

```markdown
# Brief: README banner options for <project>, round <n>

Make <5, or 2 per kept idea> distinct banner options for the top of <project>'s README, for the operator to pick by number.

<project>: <one or two plain sentences on what it does>. Read <README path> lines 1-40 for its own words. Read only; do not edit tracked files.

<Round 2 only: the operator's feedback, quoted with its date, and which ideas stay.>

## Each option

1. One SVG file, 1280 x 320, self-contained: no external fonts or images. Use a system font stack such as `-apple-system, Segoe UI, Helvetica, Arial, sans-serif`. Under 30 KB.
2. Shows the name "<project>" and a tagline of 8 words or fewer, in plain English and technically true per the README.
3. Full bleed: the first shape is `<rect width="1280" height="320">` with no `rx`, so the background fills the image edge to edge with square corners.
4. Reads well on GitHub's light (#ffffff) and dark (#0d1117) backgrounds, and stays legible at about 830 px wide.
5. Distinct ideas, each tied to what the project does. No brand logos and no other projects' marks.

## Output

Write to <project>/.local/banners/ (ignored by Git):
1. The SVG files, numbered.
2. A build script that checks the limits above: size, canvas, the full-bleed background, no external references.
3. `index.html`: every option at 830 px wide, on a light and a dark background, numbered, with its tagline and one line on the idea.
4. A PNG screenshot of `index.html`, for example with `ctlhq-browser screenshot file://<path>/index.html --out <path>/index.png --size 1000x2400`. Look at it before you report. Say so if you could not render it.

## Report

A numbered list: file, idea, tagline, size. Your recommendation with one reason. The paths to `index.html` and the PNG. Plain English, no long dashes.
```
