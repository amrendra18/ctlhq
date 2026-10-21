# Document Contracts

The four documents form one system. Each fact has one owner.

| Document | Owns | Must not become |
| --- | --- | --- |
| `PRD.md` | Product intent, users, use cases, scope, requirements, success evidence, release boundary | An implementation design or backlog |
| `ENGINEERING_PRINCIPLES.md` | Stable rules for resolving engineering tradeoffs | A generic style-guide copy or architecture description |
| `ENGINEERING_PLAN.md` | Architecture, requirement mapping, delivery sequence, milestone evidence | A second PRD or chronological diary |
| `AGENTS.md` | Concise instructions for agents working in this repository | A duplicate of the other three documents |

Use links and stable requirement identifiers when cross-document traceability
would otherwise be ambiguous. Small projects may use descriptive headings and
tables instead of identifier-heavy prose.

## Document roles

Every document a project keeps has one role and a cut rule. A cut removes words
every later session pays to read; the operator asks for that token cost, so
report word counts before and after.

| # | Document | Role | Lifetime | Cut rule |
| --- | --- | --- | --- | --- |
| 1 | `README.md` | Shipped behavior: what it is, how to install and use it. Its "Open decisions" section holds open items with owners, updated in the same commit as the change that opens or closes one. In Single file mode, also the product, principles, and plan | Permanent | Never cut. Finished plan content folds in here. A closed item leaves "Open decisions" |
| 2 | `AGENTS.md` | Instructions for agents working in the repository | Permanent | Exempt from token cuts; keep it short by routing detail to its owner |
| 3 | `CLAUDE.md` | One line, `@AGENTS.md`, so Claude Code reads the same rules | Permanent | Never repeats `AGENTS.md` |
| 4 | `PRD.md`, `ENGINEERING_PRINCIPLES.md`, `ENGINEERING_PLAN.md` | As in the table above | Four-document mode only | One owner per fact; link instead of repeating |
| 5 | `PLAN.md` | Pending work for a build run (the run-method skill) | Until the run is accepted | Pending items only. Fold finished content into `README.md`, then delete it |
| 6 | `BLOCKED.md` | Each blocker with its exact command and owner | While a blocker exists | Delete the entry when it clears |
| 7 | `LICENSE` | The license text | Permanent | Never cut |

Any other Markdown file needs a reader named in this table or in `AGENTS.md`.
Fold its live facts into the owning document, or propose it for deletion (the
garden skill runs that review).

## Single-file mode

For a personal project, write two files:

1. `README.md` with one level-one heading and these sections, each kept only
   when it carries real information: what it is and who uses it; journeys
   (trigger, action, feedback, result, recovery); scope and non-goals;
   requirements and success checks; principles; plan (what actually runs,
   milestones with completion checks); open decisions.
2. `AGENTS.md` under the same contract as in four-document mode. It points to
   the `README.md` sections in place of the three other documents.

The PRD, principles, and plan contracts below still apply to their sections.
Switch to four documents when the project gains a second contributor or the
operator asks.

## PRD.md

The PRD explains what must exist and why. Include only sections that carry real
information, while covering these contracts:

### Product definition

- One paragraph defining the product, primary user, and outcome.
- The concrete problem and why current practice is inadequate.
- Current assumptions that materially constrain the product.

### Users and use cases

- Identify each actual user or operator class.
- Describe every primary use case from the user's or caller's point of view:
  trigger, entry surface, action, immediate feedback, progress or waiting,
  completion and next action, and observable result.
- State how delayed work reaches the user or caller and how an interrupted or
  later interaction resumes.
- Include the visible failure, recovery, status, history, and debugging path
  when they materially affect trust or usability.
- For an existing product, distinguish the current journey, its concrete gaps,
  and the target first-release journey. Do not present planned bridges as
  current behavior.
- Include failure, recovery, administration, or security use cases when they
  affect product behavior.
- Avoid fictional personas and demographic detail that changes no decision.

### Goals and scope

- Goals are outcomes, not features or implementation choices.
- Non-goals prevent likely scope expansion.
- Separate the first release from later possibilities.

### Requirements

- State functional requirements in verifiable language.
- Include security, privacy, reliability, accessibility, compatibility,
  performance, and operability only where the product needs them.
- Assign stable IDs when the plan needs precise many-to-many traceability.
- Do not encode an architecture choice as a product requirement unless it is an
  externally imposed constraint.

### Success criteria and validation

- Provide a checklist of measurable completion criteria.
- Each criterion identifies observable evidence, an accepted threshold where
  relevant, and the environment or boundary in which it is measured.
- Define the product-level validation mix: automated, integration, security,
  performance, recovery, usability, and manual evidence as applicable.
- A passing test suite alone is insufficient when the product also requires a
  user workflow or operational outcome.

### Release boundary and open decisions

- State what satisfying the PRD proves and what it does not prove.
- Record only unresolved decisions that can still change scope or acceptance.
- Do not hide missing information inside assumptions.

## ENGINEERING_PRINCIPLES.md

Principles are durable decision rules. Each principle should contain the rule
and enough reason to resolve a real tradeoff.

Select the principles relevant to the project, such as:

- minimal scope and deletion of unused machinery;
- deterministic core and narrow side-effect adapters;
- enforced policy versus advisory instructions;
- secure defaults, least privilege, and explicit authority;
- red-green-refactor and tests at the owning boundary;
- typed interfaces, input validation, and fail-closed unknown state;
- privacy, secret handling, and public-by-default tracked content;
- dependency restraint, immutable versions, and upgrade evidence;
- recovery, idempotency, and observability without sensitive data;
- language style, formatter, linter, naming, and comment policy;
- compatibility and migration policy;
- documentation ownership and concise communication.

Do not paste a public style guide. Name the selected language convention and
automatic enforcement, then document only project-specific deviations. When the
language is undecided, record selection criteria rather than inventing rules.

## ENGINEERING_PLAN.md

The plan explains how the PRD will become a verified product.

### Architecture

- Begin with a compact “what actually runs” view when the product has services,
  background work, agents, browsers, scheduled jobs, or external adapters.
  Name process lifetimes, runtime locations, communication direction, durable
  state, notification or wake-up behavior, and observability. Separate the
  current system from the planned target.
- Define system boundary, components, responsibility ownership, and dependency
  direction.
- Show the primary request/data/state flow when it clarifies behavior.
- Define authoritative state, trust boundaries, and external adapters.
- State important failure and recovery behavior.
- Add a source layout only when it helps implementation and does not create
  empty speculative layers.

### Requirement mapping

- Map every PRD requirement or requirement group to one owning milestone.
- Call out cross-cutting requirements whose evidence spans milestones.
- Do not add product scope that is absent from the PRD.

### Milestones

Each milestone must be independently demonstrable and contain:

- **Outcome:** the new behavior available when it finishes.
- **Scope:** the smallest implementation needed for that outcome.
- **Tests first:** meaningful failing tests or evidence established before
  production behavior.
- **Implementation boundaries:** components or contracts changed.
- **Validation:** commands, scenarios, inspections, or manual evidence.
- **Completion checklist:** objective conditions for closing the milestone.
- **Dependencies or rollback:** include only when material.

Prefer vertical slices that complete or improve an observable user journey. A
milestone named only for infrastructure, a layer, or a refactor must explain
the independently verifiable user or caller capability it enables.

### Overall completion

- Include a final checklist covering product behavior, security, engineering
  quality, operations, and explicit scope limits.
- The checklist must agree with the PRD success criteria.

## AGENTS.md

Keep AGENTS.md short because it applies broadly to repository work. Include:

- contextual pointers telling agents when the PRD, plan, principles, and
  specialized docs matter;
- the normal change process: outcome, acceptance, failing test, smallest change,
  verification;
- authority boundaries for Git, dependencies, external services, host changes,
  publishing, deployment, destructive actions, and unrelated work;
- project-specific security and privacy invariants;
- test commands only when they actually exist;
- file, code, and communication conventions that are stable across tasks;
- handoff expectations, including failures, skips, and unverified behavior.

Avoid instructions to read every document before every edit. Route agents to
the relevant source based on the kind of change. Do not claim a prompt rule is a
security boundary. Do not repeat detailed requirements or architecture.
