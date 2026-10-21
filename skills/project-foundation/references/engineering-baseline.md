# Engineering Baseline

Use this as a selection pool, not boilerplate. Keep only rules that resolve a
real decision for the project.

## Scope and design

- Establish the smallest complete user or caller journey before selecting the
  architecture. Treat entry, feedback, delayed delivery, resume, recovery, and
  debugging as part of the outcome when the product requires them.
- Optimize for the smallest complete user outcome. Defer optional machinery
  until a measured need exists.
- Give each behavior, policy, and state transition one clear owner.
- Keep decision logic deterministic where practical. Put filesystem, process,
  network, clock, and external-service effects behind narrow adapters.
- Introduce an abstraction after a second concrete use or when isolation is
  required for security or testing. Do not design speculative extension points.
- Prefer explicit data flow and composition over hidden global state.

## Correctness and tests

- Use red-green-refactor: establish a meaningful failing test or other
  reproducible evidence before implementing behavior.
- Test at the boundary that owns the rule. Use unit tests for deterministic
  logic, contract tests for interfaces, integration tests for real adapters,
  and end-to-end tests only for critical workflows.
- Cover failure and recovery behavior, not only successful paths.
- Keep tests deterministic, isolated, readable, and independent of execution
  order. Control time, randomness, environment, and external I/O.
- Do not weaken an assertion, delete a test, or broaden an exception merely to
  make a change pass. Update tests when the accepted contract changes.

## Security and authority

- Treat file contents, model output, process output, network responses, and
  user-supplied identifiers as untrusted input.
- Validate inputs at trust boundaries. Prefer typed argument arrays and
  structured protocols over constructed shell commands or ad hoc text parsing.
- Deny unknown operations and states by default. Fail closed when authorization
  or state ownership cannot be established.
- Separate advisory model instructions from mechanically enforced policy.
  Enforce authorization, path, command, state-transition, and publication rules
  in deterministic code.
- Grant the smallest capability needed for the current operation. Require exact
  authorization for Git mutations, dependency changes, host changes, secrets,
  destructive actions, publication, deployment, and external side effects.
- Avoid logging secrets, credentials, private source, full prompts, or sensitive
  payloads. Redact at ingestion rather than after persistence.

## State, recovery, and observability

- Define one authoritative source for each state domain. Derive views instead
  of maintaining competing writable copies.
- Make retried operations idempotent or detect duplicates explicitly.
- Use atomic writes or transactional state changes where interruption could
  leave corrupt or misleading state.
- Bound logs and artifacts by size and retention. Record enough structured
  context to explain decisions without storing private content.
- Keep private machine-local data in ignored locations such as `.local/` when
  that convention is established. Treat tracked files as publishable.

## Dependencies and compatibility

- Prefer the standard library and existing dependencies when they satisfy the
  requirement clearly. Add a dependency only with an explicit owner and value.
- Pin or lock executable dependencies as appropriate. Record provenance and
  review license, maintenance, and security implications.
- Avoid mutable remote references and automatic updates in trusted execution
  paths. Upgrade through a reviewed change with verification evidence.
- Define compatibility deliberately. Reject unsupported versions clearly and
  test migrations before changing persisted formats or public contracts.

## Code and communication

- Follow the repository's established formatter, linter, and language style.
  For a greenfield project, choose an official or Google-style convention and
  enforce it automatically; document only project-specific differences.
- Use names that express domain intent. Keep functions focused and side effects
  visible. Comments explain purpose, invariants, or non-obvious constraints.
- Keep public interfaces narrow and typed. Return actionable errors at the
  boundary where recovery is possible.
- Keep documents concise and current. In handoffs, report changed behavior,
  validation run, failures, skips, assumptions, and remaining risks.
