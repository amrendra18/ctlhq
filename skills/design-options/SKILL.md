---
name: design-options
description: Show the operator design options to pick by number. Screens mode builds a clickable mock-up with one hash URL per state. Icon mode draws 4 to 6 icon concepts, then shows the picked one in about 6 palettes and typefaces with the ctlhq-icon-sheet tool, and exports the pick as PNG, favicon.ico and AppIcon.icns. Use from start-project's mock-up step, or when the operator asks for a mock-up or icon options for a product.
---

# Design options

The operator picks from numbered options that the agent has already looked at. Paths such as `skills/start-project/SKILL.md` are relative to this repository (the folder that holds this `skills/` directory). `<project>` is the project folder. Review files live under `<project>/.local/design/`.

Use screens mode for a product with a screen. Use icon mode when the product ships an app or site icon, or when the operator asks for icon options on their own ("icon options for X").

## Tool

`bin/ctlhq-icon-sheet` (a symlink to `skills/design-options/bin/ctlhq-icon-sheet`) does the mechanical part of icon mode. `ctlhq-icon-sheet review` turns a folder of SVG marks into a numbered page (`index.html`), PNG samples at 16 to 64 px on a light and a dark tile, and a full-page screenshot (`review.png`). `ctlhq-icon-sheet export` writes the picked mark in the picked palette as icon files. `ctlhq-icon-sheet --help` lists the options, the mark rules it checks, and the exit codes. Drawing the concepts, choosing palettes, and the recommendation stay with the agent.

Both modes use Chrome through `bin/ctlhq-browser`. When Chrome or Node 22 is missing, write the grant to `BLOCKED.md`, read the HTML and SVG files instead, and say in the reply that no screenshot was read.

## 1. Screens mode

1. Build a clickable mock-up of the main screens in `<project>/mock/index.html`, from the goals as the operator answered them. Make it one self-contained file with realistic data, covering every use case. Make each screen and state reachable by a hash URL (`index.html#empty`, `#loading`, `#error`).
2. Check it yourself first. For each screen and state, run `ctlhq-browser screenshot "file://<project>/mock/index.html#<state>" --out <project>/.local/design/screens/<state>.png`, then read the screenshot.
3. Reply as section 3 says, with the mock-up as the page and each screen and state as a numbered item.
4. Revise until the operator accepts the mock-up in their own words. Record the acceptance in `PLAN.md` section 8, quoting the operator.

## 2. Icon mode

### Round 1, concepts

1. Draw 4 to 6 concepts. Each is a different idea, not the same idea in another style. Save each as `<project>/.local/design/icon/marks/<n>-<word>.svg`, for example `3-orbit.svg`. The leading number is the card number, and it stays the same in round 2.
2. Draw each mark so it survives 16 px:
   1. `viewBox="0 0 64 64"` and a few simple filled shapes. A line or gap under 4 units wide is under 1 px at 16 px.
   2. No text in the mark. The name belongs to the typeface cards.
   3. Colours as `currentColor` (the accent), `var(--ink)` or `var(--paper)`, so a palette recolours the mark.
   4. A `<title>` with the one-line idea. The card shows it.
3. Run `ctlhq-icon-sheet review --marks <project>/.local/design/icon/marks --out <project>/.local/design/icon/round-1`.
4. Read `round-1/review.png`. Redraw a concept that blurs at 16 px or disappears on the dark tile, then run the review again.
5. Reply as section 3 says. The operator picks a concept by number.

### Round 2, variants

1. Copy the picked mark into `<project>/.local/design/icon/picked/`, keeping its file name.
2. Write `<project>/.local/design/icon/palettes.json` with about 6 palettes. Each entry has `id`, `name`, `accent`, `ink` and `paper`. Make at least one dark (dark paper, light ink).
3. Run `ctlhq-icon-sheet review --marks <project>/.local/design/icon/picked --palettes <project>/.local/design/icon/palettes.json --fonts "<up to 6 system families>" --name "<product name>" --out <project>/.local/design/icon/round-2`. Without `--fonts`, the tool uses its 6 default families.
4. Read `round-2/review.png`. Replace or drop a typeface the page marks "not installed on this machine", and a palette whose mark disappears on its own paper.
5. Reply as section 3 says. The operator answers with three numbers, for example "concept 3, palette 2, typeface 5".
6. When the project has a `PLAN.md`, record the pick in section 8, quoting the operator. Note that a system font is for preview, and its licence needs a check before the product ships it.

### Export

1. Run `ctlhq-icon-sheet export --mark <project>/.local/design/icon/picked/<file> --palette <id> --palettes <project>/.local/design/icon/palettes.json --out <folder>`.
2. `<folder>` is the place the project's plan names, for example `<project>/assets/icon/`. With no plan, use `<project>/.local/design/icon/export/` and say so in the reply.
3. The export holds `icon-16.png` to `icon-1024.png` on a transparent background, `favicon.ico` (16, 32 and 48 px), `icon.svg` with the palette written in, and `AppIcon.icns` on macOS. The export draws the mark as it is. A macOS app icon usually sits on a rounded square, so draw that square into the mark when the product is a Mac app.

## 3. Reply contract

Each options reply holds these, in this order:

1. The review page as a `file://` link to the absolute path, for example `file:///path/to/demo/.local/design/icon/round-1/index.html`, and the command that opens it (`open <path>`).
2. What the screenshot showed, one line per option, read from the screenshot. For example "Concept 4 turns into a grey dot at 16 px."
3. The numbered options, using the card numbers.
4. One recommendation with its reason.
5. The question. It asks which concept, which palette and typeface, or whether the operator accepts the mock-up.
