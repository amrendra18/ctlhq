#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

const RULE =
	"Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.";
const LANES = /Ten lanes on `[^`<>]+` at the PR head/;
const SUB_BLOCKS = [
	"Depends on.",
	"Files.",
	"Build.",
	"You see.",
	"Verify, unit.",
	"Verify, live.",
	"Verify, perf.",
	"Review gate.",
	"Merge.",
];
const PROGRAM_H3 = ["Arm the program", "Spawn owners", "PR mechanics", "Verdict and merge", "Boot recipe"];
const PROGRAM_MARKERS = ["git show origin/main:", "/loop 1h", "status message"];
const HOW_TO_READ_MARKERS = [
	"One box is one unit of work",
	"names the evidence",
	"Check a box only when its evidence exists",
	"playbooks/",
	RULE,
];
const PERF_ITEMS = ["Metric.", "Probe.", "Baseline.", "Rule."];
const BOX = /^\s*- \[[ x]\] (.*)$/;

const USAGE = "Usage: node check-plan.mjs [--project] <plan.md>\nThe full help: bin/ctlhq-plan-lint --help";
const args = process.argv.slice(2);
if (args.includes("--help") || args.includes("-h")) {
	console.log(USAGE);
	process.exit(0);
}
const file = args.find((a) => a !== "--project");
if (!file) {
	console.error(USAGE);
	process.exit(2);
}
// A file named PLAN.md, or --project, is a project plan (skills/run-method/references/PLAN-template.md).
const project = args.includes("--project") || path.basename(file) === "PLAN.md";

const raw = fs.readFileSync(file, "utf8").split(/\r?\n/);
const problems = [];
// Each problem is "<file>:<line>: <message>" with a "  fix: <action>" line right under it.
const fail = (line, message, fix) => problems.push(`${file}:${line}: ${message}\n  fix: ${fix}`);

// The skeleton every fix points at, with real line numbers.
const SKELETON_REL = "skills/ctlhq-mode/playbooks/multi-phase-plan.md";
const skeletonPath = path.join(path.dirname(fileURLToPath(import.meta.url)), "..", "playbooks", "multi-phase-plan.md");
let skeleton = [];
try {
	skeleton = fs.readFileSync(skeletonPath, "utf8").split(/\r?\n/);
} catch {
	skeleton = [];
}
const at = (needle) => {
	const i = skeleton.findIndex((l) => l.includes(needle));
	return i === -1 ? SKELETON_REL : `${SKELETON_REL}:${i + 1}`;
};
const copyFrom = (needle) => `copy it from ${at(needle)}`;

let start = 0;
if (raw[0] === "---") {
	start = raw.indexOf("---", 1) + 1;
}

const lines = [];
let fence = null;
const openingFence = (text) => {
	const match = text.match(/^ {0,3}(`{3,}|~{3,})(.*)$/);
	if (!match || (match[1][0] === "`" && match[2].includes("`"))) return null;
	return { char: match[1][0], length: match[1].length };
};
const closingFence = (text, opening) => {
	const match = text.match(/^ {0,3}(`+|~+)[ \t]*$/);
	return Boolean(
		match &&
		match[1][0] === opening.char &&
		match[1].length >= opening.length,
	);
};
for (let i = start; i < raw.length; i++) {
	const text = raw[i];
	const n = i + 1;
	let code = Boolean(fence);
	if (fence && closingFence(text, fence)) {
		code = false;
		fence = null;
	} else if (!fence) {
		fence = openingFence(text);
		code = Boolean(fence);
	}
	lines.push({ n, text, code });
	if (code) continue;
	const prose = text
		.replace(/`[^`]*`/g, "`")
		.replace(/!\[[^\]]*\]\([^)]*\)/g, "")
		.replace(/\]\([^)]*\)/g, "]");
	if (/[\u2013\u2014]/.test(prose)) fail(n, "long dash", "replace the dash with a period, a comma, a colon at the end of a line, or parentheses");
	if (/[\u2018\u2019\u201c\u201d]/.test(prose)) fail(n, "curly quote", "replace it with a straight quote (' or \")");
	if (project) {
		// Inline code counts: a placeholder left inside backticks is still unfilled.
		const hole = text.replace(/\]\([^)]*\)/g, "]").match(/<(?!https?:)[^<>\s][^<>]*>/);
		if (hole) fail(n, `unfilled placeholder "${hole[0]}"`, `replace "${hole[0]}" with the real value, or delete the line`);
		continue;
	}
	const colon = prose.match(/\S*: \S+/);
	if (colon) fail(n, "mid-sentence colon", `"${colon[0]}": end the sentence before the colon, or use a comma; a colon may only end a line`);
}
if (project) checkProject();

const h2 = (l) => (!l.code && l.text.startsWith("## ") ? l.text.slice(3).trim() : null);
const sections = [];
for (const l of lines) {
	const title = h2(l);
	if (title !== null) sections.push({ title, n: l.n, body: [] });
	else if (sections.length) sections.at(-1).body.push(l);
}
const find = (title) => sections.find((s) => s.title === title);
const bodyText = (s) => s.body.map((l) => l.text).join("\n");
const boxes = (ls) => ls.filter((l) => !l.code && BOX.test(l.text)).map((l) => ({ n: l.n, text: l.text.match(BOX)[1] }));

const h1 = lines.findIndex((l) => !l.code && l.text.startsWith("# "));
if (h1 === -1) fail(1, "no H1 title", `add a title line "# <Program> plan" as the first line (${at("# <Program> plan")})`);
const howToRead = find("How to read this");
if (!howToRead) fail(1, 'no "## How to read this" section', `add it under the title; ${copyFrom("## How to read this")}`);
if (h1 !== -1 && howToRead) {
	const intro = lines.slice(h1 + 1).filter((l) => l.n < howToRead.n && l.text.trim() !== "");
	if (intro.length >= 10) fail(lines[h1].n, `intro is ${intro.length} lines, under ten required`, `cut the text between the title and "## How to read this" to at most 9 lines, or move it into an appendix`);
	for (const marker of HOW_TO_READ_MARKERS) {
		if (!bodyText(howToRead).includes(marker)) fail(howToRead.n, `How to read this lacks "${marker}"`, `add the sentence that holds it; ${copyFrom(marker)}`);
	}
}

const program = find("Program checklist");
if (!program) fail(1, 'no "## Program checklist" section', `add it after "## How to read this"; ${copyFrom("## Program checklist")}`);
else {
	const h3s = program.body.filter((l) => !l.code && l.text.startsWith("### ")).map((l) => l.text.slice(4).trim());
	let cursor = 0;
	for (const name of PROGRAM_H3) {
		const found = h3s.findIndex((t, i) => i >= cursor && t.startsWith(name));
		if (found === -1) fail(program.n, `Program checklist lacks "### ${name}" in order`, `the order is ${PROGRAM_H3.map((h) => `"### ${h}"`).join(", ")}; ${copyFrom(`### ${name}`)}`);
		else cursor = found + 1;
	}
	for (const marker of PROGRAM_MARKERS) {
		if (!bodyText(program).includes(marker)) fail(program.n, `Program checklist lacks "${marker}"`, `add the box that holds it; ${copyFrom(marker)}`);
	}
}

const close = find("Close the program");
if (!close) fail(1, 'no "## Close the program" section', `add it after the last PR section; ${copyFrom("## Close the program")}`);
const programIndex = sections.indexOf(program);
const closeIndex = sections.indexOf(close);
const prSections = programIndex === -1 || closeIndex === -1 ? [] : sections.slice(programIndex + 1, closeIndex);
if (prSections.length === 0) fail(1, "no PR sections between Program checklist and Close the program", `add one "## <Task as a verb phrase> (<PR id>)" section per PR between them; ${copyFrom("**Depends on.**")}`);

const report = [];
for (const pr of prSections) {
	const heads = [];
	for (const l of pr.body) {
		if (l.code) continue;
		const m = l.text.match(/^\*\*([^*]+)\*\*(.*)$/);
		if (m && SUB_BLOCKS.includes(m[1])) heads.push({ name: m[1], n: l.n, rest: m[2].trim(), lines: [] });
		else if (heads.length) heads.at(-1).lines.push(l);
	}
	const names = heads.map((h) => h.name);
	if (names.join("|") !== SUB_BLOCKS.join("|")) {
		const missing = SUB_BLOCKS.filter((s) => !names.includes(s));
		const what = missing.length ? `add ${missing.map((s) => `**${s}**`).join(", ")}` : "reorder the blocks";
		fail(pr.n, `${pr.title}: sub-blocks are [${names.join(", ")}], expected [${SUB_BLOCKS.join(", ")}]`, `${what} so they run in the expected order; ${copyFrom("**Depends on.**")}`);
	}
	const block = (name) => heads.find((h) => h.name === name);
	const counts = {};
	for (const h of heads) counts[h.name] = boxes(h.lines).length;

	const depends = block("Depends on.");
	if (depends && depends.rest === "") fail(depends.n, `${pr.title}: Depends on names nothing`, 'write "**Depends on.** None." or name the PR ids it waits for on the same line');
	for (const name of ["Files.", "Build.", "You see.", "Verify, unit.", "Merge."]) {
		const b = block(name);
		if (b && boxes(b.lines).length === 0) fail(b.n, `${pr.title}: ${name} has no box`, `add at least one "- [ ] <step and its evidence>" line under **${name}**`);
	}
	for (const name of ["Verify, unit.", "Verify, live.", "Verify, perf."]) {
		const b = block(name);
		if (b && !b.rest.startsWith(RULE)) fail(b.n, `${pr.title}: ${name} does not open with the rule`, `start line ${b.n} with "**${name}** ${RULE}"`);
	}

	const live = block("Verify, live.");
	if (live) {
		if (!LANES.test(live.rest)) fail(live.n, `${pr.title}: Verify, live lacks "Ten lanes on \`<swarm-workers model>\` at the PR head" with the model filled in`, "add that sentence after the rule, with the model `ctlhq-models get swarm-workers` prints in the backticks");
		const lanes = boxes(live.lines).map((b) => ({ ...b, m: b.text.match(/^Lane (\d+)\. /) }));
		const numbers = lanes.filter((b) => b.m).map((b) => Number(b.m[1])).sort((a, b) => a - b);
		if (numbers.join(",") !== "1,2,3,4,5,6,7,8,9,10") {
			const missing = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10].filter((k) => !numbers.includes(k));
			fail(live.n, `${pr.title}: lanes are [${numbers.join(",")}], expected 1 to 10`, `${missing.length ? `add "- [ ] Lane <n>. <scenario>. Save \`<file>.png\`. Pass when <what you see>." for lane ${missing.join(", ")}` : "keep exactly one box per lane number 1 to 10"}; ${copyFrom("Lane 1.")}`);
		}
		for (const lane of lanes) {
			if (!lane.m) fail(lane.n, `${pr.title}: live box is not a lane`, 'start it with "Lane <n>. " (1 to 10), or move it to another block');
			else if (!/Save `[^`]+`/.test(lane.text)) fail(lane.n, `${pr.title}: lane ${lane.m[1]} names no screenshot`, `add "Save \`<file>.png\`." to lane ${lane.m[1]} on line ${lane.n}`);
			else if (!lane.text.includes("Pass when")) fail(lane.n, `${pr.title}: lane ${lane.m[1]} has no pass predicate`, `add "Pass when <what you see>." to lane ${lane.m[1]} on line ${lane.n}`);
		}
	}

	const perf = block("Verify, perf.");
	if (perf) {
		const items = boxes(perf.lines).map((b) => b.text.split(" ")[0]);
		if (items.join("|") !== PERF_ITEMS.join("|")) fail(perf.n, `${pr.title}: perf boxes are [${items.join(", ")}], expected [${PERF_ITEMS.join(", ")}]`, `write four boxes in this order, each starting with its word: ${PERF_ITEMS.map((p) => `"- [ ] ${p} ..."`).join(", ")}`);
	}

	const gate = block("Review gate.");
	if (gate) {
		const gateBoxes = boxes(gate.lines);
		if (gate.rest.startsWith("None.")) {
			if (gateBoxes.length) fail(gate.n, `${pr.title}: Review gate says None but has boxes`, `remove the boxes under line ${gate.n}, or replace "None." with the review and keep the boxes`);
		} else {
			const text = gate.lines.map((l) => l.text).join("\n");
			if (gateBoxes.length === 0) fail(gate.n, `${pr.title}: Review gate has no box`, `add a "- [ ] ..." box in which the operator reviews the screenshots and a video before merge, or write "**Review gate.** None. <PR id> is not review-gated."`);
			for (const word of ["screenshot", "video", "operator"]) {
				if (!text.includes(word)) fail(gate.n, `${pr.title}: Review gate lacks "${word}"`, `name the ${word} in a Review gate box; ${copyFrom("**Review gate.**")}`);
			}
		}
	}

	const total = boxes(pr.body).length;
	const cells = SUB_BLOCKS.filter((s) => s !== "Depends on.").map((s) => `${s.replace(/[ ,.]+/g, "-").replace(/-$/, "").toLowerCase()}=${counts[s] ?? 0}`);
	report.push(`${pr.title}  boxes=${total}  ${cells.join(" ")}`);
}

if (closeIndex !== -1) {
	const tail = sections.slice(closeIndex + 1);
	for (const s of tail) {
		if (!s.title.startsWith("Appendix")) fail(s.n, `"## ${s.title}" after Close the program is not an appendix`, `rename it "## Appendix <letter>. ${s.title}", or move it above "## Close the program"`);
	}
	if (!tail.some((s) => s.title.includes("Prototype evidence"))) fail(close.n, 'no "## Appendix ... Prototype evidence" section', `add it after "## Close the program"; ${copyFrom("Prototype evidence")}`);
}

for (const line of report) console.log(line);
console.log(`${prSections.length} PR sections, ${problems.length} problems`);
const hint = !howToRead && !program ? "; a project plan is checked with ctlhq-plan-lint --project" : "";
if (problems.length) console.error(`why: ctlhq-mode owners run the plan box by box and the operator audits it, so it must follow the skeleton in ${SKELETON_REL}${hint}`);
for (const p of problems) console.error(p);
process.exit(problems.length ? 1 : 0);

// Project mode. Checks a project PLAN.md against skills/run-method/references/PLAN-template.md.
function checkProject() {
	const TEMPLATE_REL = "skills/run-method/references/PLAN-template.md";
	let template = [];
	try {
		template = fs.readFileSync(path.join(path.dirname(fileURLToPath(import.meta.url)), "..", "..", "run-method", "references", "PLAN-template.md"), "utf8").split(/\r?\n/);
	} catch {
		template = [];
	}
	const from = (needle) => {
		const i = template.findIndex((l) => l.includes(needle));
		return `copy it from ${i === -1 ? TEMPLATE_REL : `${TEMPLATE_REL}:${i + 1}`}`;
	};
	const MILESTONE_HEADER = ["#", "Milestone", "Done when", "State"];
	const STATES = ["planned", "in progress", "done", "blocked"];
	const ROW = /^\s*\|.*\|\s*$/;
	const SEP = /^\s*\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)*\|?\s*$/;
	const CODE = /`([^`]+)`/g;

	const heads = [];
	lines.forEach((l, idx) => {
		const m = !l.code && l.text.match(/^(#{2,6})\s+(.*?)\s*$/);
		if (m) heads.push({ n: l.n, idx, level: m[1].length, title: m[2].replace(/^\d+(\.\d+)*\.?\s+/, "").toLowerCase() });
	});
	const part = (title) => {
		const h = heads.find((x) => x.title === title.toLowerCase());
		if (!h) return null;
		const next = heads.find((x) => x.idx > h.idx && x.level <= h.level);
		return { n: h.n, body: lines.slice(h.idx + 1, next ? next.idx : lines.length) };
	};
	const cellsOf = (text) => text.trim().replace(/^\|/, "").replace(/(?<!\\)\|$/, "").split(/(?<!\\)\|/).map((c) => c.trim());
	const tablesIn = (body) => {
		const out = [];
		for (let k = 0; k + 1 < body.length; k++) {
			if (body[k].code || !ROW.test(body[k].text) || !SEP.test(body[k + 1].text)) continue;
			const rows = [];
			let j = k + 2;
			for (; j < body.length && !body[j].code && ROW.test(body[j].text); j++) rows.push({ n: body[j].n, cells: cellsOf(body[j].text) });
			out.push({ n: body[k].n, header: cellsOf(body[k].text), rows });
			k = j - 1;
		}
		return out;
	};
	const column = (t, re) => t.header.findIndex((c) => re.test(c));
	// The section's own text: lines before its first subheading, outside tables.
	const ownText = (body) => {
		const end = body.findIndex((l) => !l.code && /^#{2,6}\s/.test(l.text));
		return (end === -1 ? body : body.slice(0, end)).some((l) => l.text.trim() && !ROW.test(l.text));
	};
	const required = (title, needle, where, prose = false) => {
		const p = part(title);
		if (!p) fail(1, `no "${title}" section`, `add it ${where}; ${from(needle)}`);
		else if (prose && !ownText(p.body)) fail(p.n, `"${title}" section is empty`, `write its text under line ${p.n}`);
		return p;
	};
	const labels = (p, title, names) => {
		for (const name of names) {
			const l = p.body.find((x) => !x.code && x.text.trim().startsWith(`**${name}**`));
			if (!l) fail(p.n, `${title} lacks **${name}**`, `add a line that starts with "**${name}**"; ${from(`**${name}**`)}`);
			else if (l.text.trim().slice(name.length + 4).trim() === "") fail(l.n, `${title}: **${name}** says nothing`, `write the text after "**${name}**" on line ${l.n}`);
		}
	};

	const what = required("What, why, how", "## 1. What, why, how", "under the title");
	if (what) labels(what, "What, why, how", ["What.", "Why.", "How."]);
	required("Complete, in plain words", "## 3. Complete, in plain words", "before the milestones", true);
	required("Not part of complete", "### Not part of complete", 'under "Complete, in plain words"', true);

	let jobCount = 0;
	const jobs = required("Repeated jobs", "### 5.2. Repeated jobs", "before the milestones");
	if (jobs) {
		const t = tablesIn(jobs.body).find((x) => column(x, /job/i) !== -1 && column(x, /command/i) !== -1 && column(x, /check|prove/i) !== -1);
		if (!t) fail(jobs.n, "Repeated jobs has no table with Job, Command, and Check columns", `add the table "| # | Job | Command | Check that proves it done |"; ${from("| # | Job | Command |")}`);
		else if (t.rows.length === 0) fail(t.n, "Repeated jobs table has no rows", "add one row per job that runs more than once, starting with the harness `scripts/verify fast`");
		else {
			jobCount = t.rows.length;
			const cmd = column(t, /command/i);
			const check = column(t, /check|prove/i);
			for (const r of t.rows) {
				if (!/`[^`]+`/.test(r.cells[cmd] ?? "")) fail(r.n, `repeated job ${r.cells[0]} names no command`, `put the exact command in backticks in the Command cell on line ${r.n}`);
				if (!/\d|exit/i.test(r.cells[check] ?? "")) fail(r.n, `repeated job ${r.cells[0]} has no check that proves it done`, `write the exit code and the observed state that prove it done in the check cell on line ${r.n}`);
			}
		}
	}

	let streamCount = 0;
	const streams = required("Workstreams and waves", "### 5.3. Workstreams and waves", "before the milestones");
	if (streams) {
		const t = tablesIn(streams.body).find((x) => column(x, /wave/i) !== -1 && column(x, /workstream/i) !== -1 && column(x, /owns/i) !== -1);
		if (!t) fail(streams.n, "Workstreams and waves has no table with Wave, Workstream, and Owns columns", `add the table "| # | Wave | Workstream | Owns these files | Depends on |"; ${from("| # | Wave |")}`);
		else if (t.rows.length === 0) fail(t.n, "Workstreams and waves table has no rows", "add one row per workstream; rows with the same wave run in parallel");
		else {
			streamCount = t.rows.length;
			const wave = column(t, /wave/i);
			const owns = column(t, /owns/i);
			const seen = [];
			for (const r of t.rows) {
				const w = (r.cells[wave] ?? "").toLowerCase();
				const paths = [...(r.cells[owns] ?? "").matchAll(CODE)].map((m) => m[1]);
				if (paths.length === 0) fail(r.n, `workstream ${r.cells[0]} owns no file`, `list the files or folders it writes, each in backticks, in the Owns cell on line ${r.n}`);
				for (const p of paths) {
					const clash = seen.find((s) => s.wave === w && (s.path === p || (s.path.endsWith("/") && p.startsWith(s.path)) || (p.endsWith("/") && s.path.startsWith(p))));
					if (clash) fail(r.n, `workstreams ${clash.row} and ${r.cells[0]} in wave "${r.cells[wave]}" both own \`${clash.path === p ? p : `${clash.path}\` and \`${p}`}\``, `give each file one owner: move it to one row, or put the two rows in different waves`);
					seen.push({ wave: w, path: p, row: r.cells[0] });
				}
			}
		}
	}

	const audit = required("Audit rule", "### 5.4. Audit rule", "before the milestones");
	if (audit) labels(audit, "Audit rule", ["When.", "Bar.", "Severity scale.", "Stop."]);

	let milestoneCount = 0;
	const all = tablesIn(lines);
	const mt = all.find((x) => column(x, /^milestone$/i) !== -1 && column(x, /^state$/i) !== -1);
	if (!mt) fail(1, "no milestone table", `add the table "| # | Milestone | Done when | State |" under "## 7. Milestone status"; ${from("| # | Milestone | Done when | State |")}`);
	else if (mt.header.join("|") !== MILESTONE_HEADER.join("|")) fail(mt.n, `milestone table columns are [${mt.header.join(" | ")}], expected [${MILESTONE_HEADER.join(" | ")}]`, `change line ${mt.n} to "| ${MILESTONE_HEADER.join(" | ")} |" and fill each row in that order`);
	else if (mt.rows.length === 0) fail(mt.n, "milestone table has no rows", `add the M0 row first; ${from("| M0 |")}`);
	else {
		milestoneCount = mt.rows.length;
		mt.rows.forEach((r, i) => {
			const [id, , done = "", state = ""] = r.cells;
			if (r.cells.length !== 4) fail(r.n, `milestone row has ${r.cells.length} cells, expected 4`, `write "| M<n> | <name> | <done when> | <state> |" on line ${r.n}`);
			const num = id.match(/^M?(\d+)$/);
			if (!num) fail(r.n, `milestone number "${id}" is not M<n>`, `write M0, M1, and so on in the # cell on line ${r.n}`);
			if (i === 0 && (!num || Number(num[1]) !== 0)) fail(r.n, `the first milestone is "${id}", expected M0`, `add M0 first, the harness plus one real user journey on the real surface; ${from("| M0 |")}`);
			if (!STATES.includes(state)) fail(r.n, `milestone ${id}: State "${state}" is not one of ${STATES.join(", ")}`, `write one of ${STATES.map((s) => `"${s}"`).join(", ")} in the State cell on line ${r.n}`);
			if (!/`[^`]+`/.test(done)) fail(r.n, `milestone ${id}: Done when names no command`, `name the verification command in backticks in the Done when cell on line ${r.n}`);
			if (!/\bexit(?:s|ed)?(?: with)?(?: code)? \d/i.test(done)) fail(r.n, `milestone ${id}: Done when names no exit code`, `say which exit code proves it, for example "exits 0", in the Done when cell on line ${r.n}`);
			if (num && Number(num[1]) === 0 && ![...done.matchAll(CODE)].some((m) => /scripts\/verify (fast|full)\b/.test(m[1]) && m[1].includes("--feature"))) fail(r.n, "milestone M0: Done when does not run the harness `scripts/verify` on one journey", "M0 is the harness plus one real user journey on the real surface; name `scripts/verify fast --feature` with the journey name, and its exit codes (verify-setup writes the harness)");
		});
	}

	const ledger = required("Approvals ledger", "## 10. Approvals ledger", "as section 10");
	if (ledger && !tablesIn(ledger.body).some((x) => column(x, /approved/i) !== -1)) fail(ledger.n, "Approvals ledger has no table with an approved column", `add the ledger table header; ${from("| # | Date and time |")}`);

	console.log(`project plan: ${milestoneCount} milestones, ${jobCount} repeated jobs, ${streamCount} workstreams, ${problems.length} problems`);
	if (problems.length) console.error(`why: run-method builds and resumes from PLAN.md, and ctlhq-status reads it, so it must hold every part of ${TEMPLATE_REL}`);
	for (const p of problems) console.error(p);
	process.exit(problems.length ? 1 : 0);
}
