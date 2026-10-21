# Depth and Evidence

## One coverage standard

Every depth covers all five review lenses. Depth changes the amount of evidence, the number of journeys and failure cases traced, and the strength of verification. It never removes a lens.

The caller must explicitly choose one depth. Do not infer a default.

## Quick

Use quick for a time-bounded first pass.

- Read repository instructions, product documents, the top-level tree, entry points, dependency manifests, normal check commands, and current Git state.
- Trace the primary user journey and its most important failure or recovery path.
- Inspect the main trust boundaries, state changes, performance-sensitive path, repository structure, and test layout.
- Run existing fast checks when they are safe.
- Complete all five lens summaries and the coverage ledger. Use `sampled` when the evidence covers only part of a named coverage group.
- Build the behavior-to-evidence matrix for the primary journey, material findings, and important risks inspected during the quick pass.
- Report clear high-impact findings and obvious simplifications. Mark topics that received only sampled evidence.

Quick does not claim exhaustive evidence.

## Standard

Use standard for a complete working review of the current product.

- Perform every quick activity.
- Trace every documented user journey, major alternative, and important error or recovery path.
- Run the repository's normal full validation when it is safe.
- Inspect implementation boundaries, dependencies, configuration, build and release paths, state ownership, and the full test portfolio.
- Build the full behavior-to-evidence matrix for accepted journeys and material risks.
- Check relevant recent history when it explains compatibility code, migrations, risk, or apparent dead content.
- Use five independent reviewers when subagents are available, one for each review contract.
- Verify critical and high findings independently before reporting them.

## Deep

Use deep for release readiness, high-risk systems, major simplification, or a suspected systemic problem.

- Perform every standard activity.
- Trace all discoverable entry points, supported platforms, state transitions, trust boundaries, and operational workflows.
- Inspect relevant history deeply enough to understand migrations, compatibility promises, repeated fixes, and abandoned implementations.
- Exercise safe failure, recovery, hostile-input, concurrency, and resource-limit cases when the repository supports them.
- Build an explicit scale model covering likely growth dimensions, bottlenecks, limits, and backpressure.
- Use existing coverage, mutation, static analysis, performance, or security tools when available and relevant. Do not install tools or use external services without authority.
- Use independent reviewers. Run another challenge pass for critical and high findings and for proposed large deletions or architectural removal.
- State the remaining uncertainty even when all checks pass.

## Shared evidence pack

The lead gives every reviewer the same factual starting point:

- Review scope, depth, current commit, comparison base, and working-tree state
- Repository instructions and accepted product or architecture documents
- Supported users, interfaces, platforms, and documented journeys
- Repository tree, entry points, major modules, state stores, and external boundaries
- Dependency, build, deployment, migration, and automation files
- Test inventory and results from checks the lead ran
- Relevant diffs and history for the selected scope
- Known constraints and evidence that could not be obtained

Do not include the lead's suspected problems in the shared pack. Independent reviewers should reach their own conclusions.

## Reviewer execution

For `standard` and `deep`, assign each lens to an independent subagent when the harness supports subagents. Five reviewers may run together or in waves. The lead remains responsible for scope, shared commands, evidence quality, and the final report.

For `quick`, independence means completing each lens analysis before cross-lens synthesis. It does not require five separate subagents.

Reviewers operate read-only unless the caller separately approves a mutation. They return:

1. Confirmed findings in their owned topics
2. Evidence inspected and checks used
3. Important areas with no finding
4. Unknowns, blocked checks, and assumptions
5. Possible cross-lens issues for the lead to reconcile

When subagents are unavailable, the lead performs the five lenses as separate passes. Finish one lens record before synthesizing across lenses so early conclusions do not erase a fresh perspective.

## Evidence rules

Prefer direct evidence in this order:

1. Reproducible behavior and safe command output
2. Current code, tests, configuration, and tracked artifacts
3. Accepted product and architecture documents
4. Relevant version history
5. A clearly labeled inference

Documentation is a claim about intended behavior. Running code is evidence about current behavior. A disagreement between them is itself a finding when it affects users or maintainers.

Do not use access to production, private data, credentials, paid services, or external systems unless the caller explicitly places them in scope and authorizes the access.
