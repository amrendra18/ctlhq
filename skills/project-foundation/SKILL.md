---
name: project-foundation
description: Create, audit, or revise a concise, user-journey-first software-project foundation from an idea, brief, or existing repository. Use when defining or materially changing AGENTS.md, PRD.md, ENGINEERING_PLAN.md, and ENGINEERING_PRINCIPLES.md, or a single README.md plus AGENTS.md for a personal project.
---

# Project Foundation

Build four documents that agree with each other and are sufficient to guide
implementation. Ground the foundation in what users do and see before choosing
architecture. Optimize for truth, traceability, and semantic density.

## Select the mode

- **Create:** The project has an idea, brief, or incomplete foundation. Produce
  the best first version of all four documents.
- **Audit:** Inspect existing foundation documents. Identify and, when requested,
  correct gaps, contradictions, vague requirements, duplicate ownership, and
  missing validation.
- **Revise:** A product or architecture decision changed. Update every affected
  owning document without rewriting unrelated content.
- **Single file:** A personal project (one operator, no outside contributors).
  Write `README.md` and `AGENTS.md` only. `README.md` holds the product, the
  principles, and the plan as sections. Use it when the operator asks for it.
  Create, Audit, and Revise apply to these two files the same way.

Infer the mode from the request. If ambiguity changes which files may be
modified, ask one concise question. For a personal project, that question is
whether to use Single file mode.

## Load only the needed guidance

- For **Create**, read
  [interview-and-research.md](references/interview-and-research.md),
  [document-contracts.md](references/document-contracts.md), and
  [engineering-baseline.md](references/engineering-baseline.md). Read
  [quality-gate.md](references/quality-gate.md) after drafting.
- For **Audit**, read [document-contracts.md](references/document-contracts.md)
  and [quality-gate.md](references/quality-gate.md). Read the engineering
  baseline only when evaluating engineering or agent rules.
- For **Revise**, read [document-contracts.md](references/document-contracts.md),
  the references affected by the decision, and then the quality gate.
- For **Single file**, also read the "Document roles" and "Single-file mode"
  sections of [document-contracts.md](references/document-contracts.md).

## Workflow

1. Read the supplied idea or brief, applicable `AGENTS.md` files, the four
   existing foundation documents, and only the repository context needed to
   distinguish current truth from planned behavior.
2. Before proposing architecture or internal contracts, describe each primary
   user or caller journey in plain language: trigger, entry surface, user
   action, visible feedback, waiting or resume behavior, result, and recovery.
   For an existing system, distinguish the current journey from the intended
   one and identify the first point where reality stops matching the product
   promise.
3. For software with runtime behavior, establish "what actually runs": the
   resident and short-lived processes, where they run, how they communicate,
   where durable state lives, how delayed work reaches the user or caller, and
   how a person observes and debugs the system. Label current, planned, and
   speculative behavior explicitly.
4. In Audit mode, classify every agent rule as keep, route to its owner,
   replace with deterministic enforcement, or remove. Resolve each mandatory
   command; run validation commands within authority, and report unavailable or
   authority-blocked commands.
5. Separate known facts, reversible defaults, and material open decisions.
6. Interview only for decisions that change user outcomes, scope, authority,
   security, architecture, compatibility, or acceptance. Do not re-ask facts in
   the source material.
7. In Create mode, draft in this order:
   `PRD.md`, `ENGINEERING_PRINCIPLES.md`, `ENGINEERING_PLAN.md`, then
   `AGENTS.md`. In Single file mode, draft `README.md`, then `AGENTS.md`.
8. Give each fact one owning document. Cross-reference it elsewhere and remove
   repeated explanations.
9. In Revise mode, search current docs and tests for superseded behavior and
   reconcile completion checkboxes with recorded evidence.
10. Run the semantic and compression review in `quality-gate.md`.
11. Run `scripts/validate_foundation.py <project-root>` (add `--single-file`
   in Single file mode). Resolve failures and assess warnings; do not change
   substance merely to silence a warning.
12. Report the files changed, material decisions encoded, validation results,
    and any decision that remains genuinely open.
13. Report the token cost: the word count of each document before and after
    the change. In ctlhq, `bin/ctlhq-doc-diet words <project-root>` prints it in a
    git repository; elsewhere, `wc -w` on each file.

## Writing constraints

- Use simple, everyday English. Assume the reader is new to the topic. Avoid
  corporate language, unexplained jargon, and needlessly difficult words. When
  an exact technical term is needed, explain it in plain words the first time.
- Keep each section short and orderly. Lead with the conclusion, decision, or
  user-visible result. Include only the detail needed to understand or act.
- State points directly. Avoid rhetorical "X, not Y" contrasts when a positive
  statement works. Use two short sentences when both ideas matter. Keep direct
  negative wording when safety, accuracy, or scope requires it.
- Do not use em dashes. Use a period, comma, colon, or parentheses instead.
- Use plain, precise technical English. Put conclusions before rationale.
- Start product discussion in the language of the user or calling system. Do
  not use component, protocol, schema, or infrastructure names as substitutes
  for describing the experience.
- Make requirements observable and success criteria passable or fail-able.
- Use prose for reasoning, lists for parallel items, and tables for mappings.
- Remove filler, generic tutorials, research history, and duplicated policy.
- Avoid vague claims such as "robust," "scalable," or "user-friendly" unless the
  document supplies a measurable meaning.
- Do not invent commands, directories, dependencies, services, tests, or
  capabilities and describe them as current. Label planned behavior clearly.
- Do not include comparison products, inspirations, or research sources in the
  generated documents unless the user requests them or attribution is legally
  required.
- Do not leave placeholder markers. Record a material unresolved decision in a
  short `Open decisions` section with its impact.
- Scale detail to the project. A small utility needs fewer requirements and
  milestones than a distributed system.
- Do not call a foundation implementation-ready when entry, feedback,
  completion, delayed delivery, recovery, or debugging remain unexplained for
  a primary journey.

## Scope and authority

Creating or revising these documents does not authorize Git initialization,
staging, commits, dependencies, implementation scaffolding, host changes,
publication, deployment, or external mutations. Preserve unrelated files and
private `.local/` content.
