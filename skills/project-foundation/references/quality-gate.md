# Quality Gate

Run this review after drafting or revising the foundation. Resolve substantive
gaps before editing for brevity.

## Product completeness

- The product, primary user, problem, and first-release outcome are explicit.
- Every primary use case explains where the user or caller starts, what they
  do, what they see immediately, what happens while they wait, how delayed work
  reaches them, what completion enables, and what observable result they get.
- Failure, recovery, resume, status, history, and debugging are understandable
  from the user's point of view wherever they affect a primary journey.
- For an existing product, current experience, target experience, and the gap
  between them are explicit. Planned behavior is not written as present fact.
- Goals describe outcomes; non-goals close likely scope ambiguity.
- Requirements are externally observable or objectively verifiable.
- Security, privacy, recovery, compatibility, performance, accessibility, and
  operations are addressed where they affect the product.
- Success criteria state evidence, boundaries, and thresholds where relevant.
- Open decisions are material, have stated impact, and are not disguised
  assumptions.

## Traceability

- Each use case is covered by one or more requirements.
- Every requirement or requirement group maps to an owning milestone.
- Every product success criterion has corresponding validation evidence.
- Milestone completion checklists collectively satisfy the PRD completion
  boundary without adding unapproved product scope.
- Cross-document links and identifiers resolve and use one consistent meaning.

## Architecture and delivery

- For a product with runtime behavior, a reader can answer what actually runs,
  where it runs, which processes are resident or short-lived, how they
  communicate, where authoritative state lives, and how delayed work reaches a
  user or caller.
- The system boundary, component responsibilities, dependency direction,
  authoritative state, trust boundaries, and principal failure paths are clear.
- Security-sensitive decisions identify deterministic enforcement points.
- Milestones are ordered, shippable slices with an observable outcome.
- Internal mechanisms are not counted as product completion while the entry,
  feedback, delivery, resume, recovery, or debugging path for the owning user
  journey is missing.
- Each milestone specifies tests or evidence established before implementation,
  the affected boundaries, validation, and objective completion conditions.
- The plan does not claim commands, dependencies, directories, or capabilities
  already exist when they are only proposed.

## Principles and agent rules

- Each engineering principle resolves a project-relevant tradeoff and can guide
  review decisions.
- `AGENTS.md` routes work to the relevant source without requiring every file
  for every task; every retained rule is unique and broadly relevant.
- Agent instructions distinguish advisory guidance from enforced controls.
- Authority boundaries, security invariants, normal change flow, validation,
  and handoff expectations are concise and operational.
- Mandatory validation commands in `AGENTS.md` resolve and run in the agent's
  environment; unavailable or authority-blocked commands are explicit.

## Truth and compression

- A reader who is new to the topic can understand the documents without
  decoding corporate language, unexplained jargon, or needlessly hard words.
- Sections lead with the result or decision, stay orderly, and contain no
  filler, repeated points, or essay-length treatment of a simple idea.
- Sentences state the point directly. They avoid rhetorical “X, not Y” framing
  and do not use em dashes. Necessary safety rules and exact scope boundaries
  may still use direct negative wording.
- Current facts, planned behavior, reversible defaults, and open decisions are
  clearly distinguished.
- User-language journeys come before architecture explanations; internal nouns
  do not stand in for what a person or caller does and sees.
- Each concept has one owning document. Other files link to it and remove
  repeated explanations.
- No text exists only to sound comprehensive. Remove generic tutorials,
  repeated rationale, empty headings, and decorative adjectives.
- Terms are consistent. Sentences use concrete subjects, verbs, and observable
  outcomes.
- A revision search finds no superseded current behavior; historical evidence
  is clearly labeled.
- Completion checkboxes agree with recorded evidence. A composite check remains
  open while any required evidence is pending.
- There are no placeholders, stale comparisons, unrelated research history, or
  private machine-specific details.

## Mechanical validation

Run:

```text
<skill-directory>/scripts/validate_foundation.py <project-root>
```

Resolve every failure. Review warnings in context; a warning may be acceptable
when a small project does not benefit from requirement identifiers or when a
path is intentionally documented for a local-only workflow.
