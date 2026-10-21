# Interview and Research

The goal is sufficient context for a defensible foundation, not exhaustive
questioning.

## Establish current truth

Read the supplied idea or brief first. Then inspect only relevant local context:

- applicable parent and project `AGENTS.md` files;
- existing foundation or architecture documents;
- current files, commands, dependencies, and tests when a repository exists;
- sibling project contracts only when the user identifies them as related.

Do not infer requirements from unrelated repositories, prior projects, or a
tool merely because it is available. Distinguish current behavior from desired
behavior in every draft.

## Start with the lived journey

Before asking about architecture, establish how the product is encountered and
used. For each primary user or calling system, answer in its language:

- What causes the journey to begin, and where do they begin it?
- What do they do or provide?
- What do they see immediately, and how do they know the request was accepted?
- What happens while work is in progress?
- If work outlives the interaction, how are they notified and how do they
  resume?
- What result arrives, where does it arrive, and what can they do next?
- What does failure look like, and how do they retry, recover, or get help?
- How can they inspect history, current status, and enough detail to debug a
  surprising result?

Do not accept component names, protocols, queues, schemas, or “there is a UI”
as answers. Those may implement the journey, but they do not describe it. For
an existing product, walk at least one real case through the current system and
mark every manual bridge, invisible wait, dead end, or claim that is not yet
true.

## Establish what actually runs

For software with runtime behavior, build a compact current-truth map before
selecting or endorsing architecture. Identify:

- user and machine entry surfaces;
- resident services and short-lived processes, including where and when they
  run;
- communication paths and which side initiates each interaction;
- the authoritative state and any derived inbox, view, cache, or notification;
- what keeps working after a terminal, request, browser, or agent turn exits;
- how delayed work wakes or reaches a human or calling system;
- logs, health checks, status views, and the first debugging steps; and
- which parts are current, planned, experimental, or merely possible later.

The runtime map belongs in the engineering plan when it materially helps
implementation. Its user-visible consequences belong in the PRD. Architecture
must explain the accepted journey, not silently invent it.

## Build a decision inventory

Classify missing information:

### Ask before drafting

Ask when the answer changes:

- the primary user or job;
- the first-release boundary or a major use case;
- the entry surface, feedback, delayed-delivery, resume, or recovery behavior
  of a primary journey;
- externally visible behavior or compatibility;
- authority to mutate repositories, systems, accounts, or external services;
- security, privacy, identity, credential, or data-retention posture;
- platform, deployment, offline, or regulatory constraints;
- a foundational architecture choice that is expensive to reverse;
- the evidence required to call the product complete.

Ask concise questions in one or two focused rounds. Explain the consequence of
the choice and give a recommendation when evidence supports one. Do not ask the
user to choose an internal detail the engineering plan can safely decide later.

### Choose a reversible default

Proceed without interruption when the choice is local, low-risk, reversible,
and does not change the user contract. Record the decision in the owning
document only if implementers need to preserve it.

Examples include internal names, initial file organization, or whether a simple
pure helper is a function or small type.

### Leave genuinely open

If the user cannot answer a material question yet, state the decision, impact,
safe interim boundary, and point by which it must be resolved. Do not fill the
gap with a fabricated assumption.

## Research

Research is warranted when a requirement depends on current external facts,
standards, platform behavior, security guidance, licenses, or an existing
integration contract. Prefer primary sources and verify version-sensitive
claims.

Research informs the design. Generated project documents should describe the
project itself. Do not name comparison products, inspirations, abandoned
approaches, or research sources unless the user asks, the dependency is part of
the product, or attribution is required.

## Mode-specific behavior

### Create

Confirm the intended outcome, conduct the material interview, then write the
four documents. Do not create implementation files, empty directories,
dependencies, or Git metadata as part of foundation generation.

### Audit

Read all existing foundation documents and enough repository state to test their
claims. Report findings in priority order with owning file and practical impact.
When correction is requested or implied, make the smallest coherent edits and
rerun the quality gate.

### Revise

Identify the changed decision and its dependency path. Update the owning
document first, then every affected reference, milestone, test, completion
criterion, and agent rule. Preserve unrelated accepted decisions and prose.
