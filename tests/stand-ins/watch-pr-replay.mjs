// watch-pr-replay.mjs: run ctlhq-watch-pr's own TypeScript (github.ts, policy.ts, render.ts) under
// node, because bun is not installed here. It mirrors main() in cli.ts without commander:
// resolve the PR, discover the stack (--stack), run runSimple once, print the JSON verdict,
// and exit with its exit code. The gh it calls is the first gh on PATH (the fake gh in tests).
// Usage: node watch-pr-replay.mjs <scripts/watch-pr dir> [--owner O] [--repo R] [--pr N]
//        [--stack] [--status-only] [--max-query-errors N]
const [src, ...argv] = process.argv.slice(2);
const github = await import(`${src}/github.ts`);
const policy = await import(`${src}/policy.ts`);
const render = await import(`${src}/render.ts`);
const types = await import(`${src}/types.ts`);
const opt = { owner: null, repo: null, pr: null, stack: false, statusOnly: false, maxQueryErrors: 1 };
for (let i = 0; i < argv.length; i++) {
  const a = argv[i];
  if (a === "--owner") opt.owner = argv[++i];
  else if (a === "--repo") opt.repo = argv[++i];
  else if (a === "--pr") opt.pr = types.parsePrNumber(Number(argv[++i]));
  else if (a === "--stack") opt.stack = true;
  else if (a === "--status-only") opt.statusOnly = true;
  else if (a === "--max-query-errors") opt.maxQueryErrors = Number(argv[++i]);
  else { console.error(`watch-pr-replay: unknown argument ${a}`); process.exit(64); }
}
const mode = opt.stack ? "stack" : "single";
const clock = { now: () => 0, observedAt: () => "2026-10-17T00:00:00.000Z", sleep: async () => {} };
const reader = new github.GhGitHubReader();
const out = (v) => process.stdout.write(render.renderJson(v));
let contexts;
try {
  const seed = await github.resolveContext({ reader, owner: opt.owner, repo: opt.repo, pr: opt.pr });
  contexts = mode === "single" ? [seed] : await github.discoverStack(reader, seed);
} catch (error) {
  if (!(error instanceof github.WatcherQueryError)) throw error;
  const verdict = policy.statusQueryVerdict(policy.verdictFactory(clock, mode), 1, error.failure);
  out(verdict);
  process.exit(verdict.exitCode);
}
const options = { interval: 1, sweepInterval: 1, timeout: 0, maxQueryErrors: opt.maxQueryErrors, allowDraft: false };
const verdict = await policy.runSimple({ dependencies: { reader, clock, emit: out }, contexts, mode, statusOnly: opt.statusOnly, options });
out(verdict);
process.exit(verdict.exitCode);
