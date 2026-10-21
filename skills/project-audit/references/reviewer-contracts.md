# Reviewer Contracts

The audit has exactly five review lenses. Together they cover product value, user experience, security, reliability, design, scale, repository hygiene, tests, documentation, proof, and code craft. Each reviewer stays independent until the lead combines the results.

Every reviewer must inspect the shared evidence pack, test the claims within their lens, report evidence for each finding, list important clean areas, and name anything they could not verify.

## 1. Product and User Experience

### Mission

Determine whether the repository delivers a complete, understandable, and recoverable experience for its accepted users and use cases.

### Required coverage

- **Product contract:** Product purpose, target users, user problems, promised outcomes, non-goals, and supported use cases
- **Surfaces and access:** Supported devices, operating systems, interfaces, environments, access needs, and discoverability
- **Journey lifecycle:** Setup, onboarding, configuration, first success, repeated use, update, migration, import, export, downgrade, and removal
- **Failure and recovery:** Empty states, invalid input, cancellation, retry, interruption, partial completion, recovery, and destructive actions
- **Clarity and accessibility:** Feedback, progress, errors, confirmations, help, terminology, novice comprehension, keyboard use, screen readers, contrast, and nonvisual command-line needs where relevant
- **Control and truthfulness:** State visibility, user control, reversibility, data ownership, privacy expectations, documentation agreement, missing workflows, surprising limits, and features whose cost exceeds user value

### Adversarial questions

- Can a new user reach the promised result using only the supplied instructions?
- What happens at every boundary before, during, and after the main workflow?
- Can a user tell what changed, what is still running, what failed, and how to recover?
- Does the product expose implementation details as required user knowledge?
- Do supported surfaces behave consistently enough to preserve the same product promise?
- Is a documented capability absent, misleading, or technically present but practically unusable?

### Required output

Provide a journey map, the gaps found in each journey, user-facing impact, and the simplest complete product correction. Put new product ideas that lack accepted evidence under open questions rather than findings.

## 2. Security and Reliability

### Mission

Find realistic ways the system can expose data, grant unintended capability, corrupt state, become unavailable, or fail without safe recovery.

### Required coverage

- **Threat and access model:** Protected data, dangerous capabilities, actors, trust boundaries, threat assumptions, authentication, authorization, sessions, tenants, ownership, privileges, least privilege, and confirmation
- **Untrusted input and execution:** Parsing, validation, encoding, injection, traversal, unsafe deserialization, command execution, hostile input, plugins, and external-service boundaries
- **Data and privacy:** Secrets, personal data, logs, telemetry, diagnostics, errors, caches, temporary files, retained state, and privacy-safe failure output
- **State safety and recovery:** Atomicity, idempotence, concurrency, races, retries, timeouts, cancellation, duplicate requests, partial failure, rollback, backup, restoration, restart behavior, and consistency
- **Availability and abuse:** Resource exhaustion, unbounded input, denial of service, rate limits, quotas, backpressure, availability, health signals, observability, alerting, misuse, and operator mistakes
- **Deployment and supply chain:** Filesystem, process, network, database, and browser boundaries; dependencies; pinned executable inputs; generated artifacts; build provenance; configuration; environment separation; platform assumptions; and development shortcuts

### Adversarial questions

- Which untrusted value reaches a sensitive operation, and what proves it is constrained?
- What remains after interruption at each state-changing step?
- Can retries, parallel calls, or stale state duplicate or lose work?
- Can an error or diagnostic reveal data outside the selected task?
- Which failure is silent, irreversible, or difficult for a user to diagnose?
- What happens when a dependency is unavailable, slow, malicious, or returns malformed data?

### Required output

For each risk, identify the asset or capability, trust boundary, realistic trigger, consequence, current control, control gap, and verification method. Do not claim exploitability without evidence. Clearly label threat-model assumptions.

## 3. Architecture, Scalability, and Repository Hygiene

### Mission

Determine whether the design is the smallest clear system that can meet current product needs and expected scale without avoidable bottlenecks or maintenance burden.

### Required coverage

- **System shape:** Component responsibilities, boundaries, dependency direction, coupling, cohesion, cycles, data flow, control flow, and error flow
- **State and contracts:** Sources of truth, state ownership, consistency rules, public interfaces, internal contracts, versioning, migrations, and backward compatibility
- **Simplicity and duplication:** Layers, wrappers, indirection, abstractions, extension points, configuration, competing implementations, and repeated policy across components (Code Craft owns copied logic and inconsistent helpers inside and between modules)
- **Repository hygiene and removal:** Dead code, unused exports, dependencies, scripts, flags, configuration, fixtures, documentation, assets, generated output, stale experiments, obsolete migrations, ownership, and change locality. Code Craft owns naming and repository layout
- **Scale and performance:** Algorithms, data structures, hot paths, startup, memory, CPU, disk, network, databases, external services, unbounded work, caching, batching, pagination, queues, fan-out, backpressure, contention, concurrency, distribution, partitioning, capacity, and failure domains
- **Build and operations:** Packaging, deployment, portability, supported platforms, dependency weight, operational complexity, maintainability, diagnosability, replacement cost, and connection to accepted use cases

### Adversarial questions

- Can one source, component, or rule replace several overlapping versions?
- Is an abstraction solving a current repeated problem or predicting an unaccepted future?
- Which path becomes slow or unsafe as users, data, files, requests, or workers grow?
- Does state have one owner, and are consistency and recovery rules visible?
- Can a change stay local, or does hidden coupling force edits across unrelated layers?
- Which file or dependency can be removed while preserving every accepted behavior?

### Proof required for removal

Never classify code or a file as dead from text search alone. Check:

- Runtime and command entry points
- Static imports and dynamic discovery
- Build, packaging, deployment, and generated-file rules
- Configuration, environment, plugins, reflection, and registration
- Supported operating systems and optional features
- Public interfaces and downstream compatibility
- Migrations, rollback paths, and retained data
- Tests, examples, automation, and relevant history

A removal recommendation must name the exact item, the evidence that it is redundant or unused, the canonical replacement if one exists, removal risks, tests needed first, and verification after removal.

### Required output

Provide the current architecture map, scale assumptions, bottleneck evidence, duplication or removal candidates, and a smaller target shape. Separate measured limits from inferred ones.

## 4. Tests and Evidence

### Mission

Determine whether the smallest sufficient evidence portfolio protects every accepted behavior and material risk with fast, clear, trustworthy feedback.

### Required coverage

- **Traceability:** Mapping from product requirements, user journeys, trust boundaries, and failure risks to validation evidence
- **Unit evidence:** Isolated rules, decisions, boundary values, state transitions, failure branches, malformed input, and useful property-based or fuzz checks
- **Boundary and journey evidence:** Integration contracts across components and external boundaries, plus a small set of critical end-to-end journeys
- **Risk evidence:** Security, recovery, compatibility, migration, concurrency, limit, and performance tests where the risk justifies them
- **Test quality and efficiency:** Assertions, independence, fixtures, mocks, fakes, snapshots, determinism, flakiness, failure clarity, runtime, repeated setup, parallel safety, duplication, wrong-layer tests, and tests that protect no useful behavior
- **Delivery evidence:** Platform coverage, continuous integration, release checks, coverage reports, documentation checks, examples, schemas, runbooks, manual checks, and claims that lack executable proof

### Smallest sufficient test portfolio

Build a behavior-to-evidence matrix with these fields. For `quick`, include the primary journey, material findings, and important risks inspected. For `standard` and `deep`, include every accepted journey and material risk.

| Behavior or risk | Importance | Current evidence | Best owning level | Decision | Reason |
| --- | --- | --- | --- | --- | --- |

Classify each proposed test action as `keep`, `combine`, `replace`, `remove`, or `add`.

- Give each behavior a clear owning level. Prefer the cheapest level that fully exercises the rule.
- Keep integration coverage for real boundaries. A unit mock does not prove two components work together.
- Keep end-to-end coverage for a few critical journeys. Do not repeat every edge case end to end.
- Keep explicit security and recovery cases for dangerous boundaries, even when ordinary behavior overlaps.
- Combine table-shaped cases when they protect the same rule and produce clear failures.
- Avoid one giant test that hides which behavior failed.
- Do not remove a test unless named remaining evidence protects the same behavior and risk with equal or stronger failure detection.
- Treat similar text, shared setup, or overlapping line coverage as clues. They do not prove duplication.
- For each removal, name the replacement coverage and the command that verifies the resulting suite.

### Adversarial questions

- Which accepted behavior can regress while every current test still passes?
- Which test passes even when the important assertion or integration is removed?
- Are several tests paying runtime cost for the same signal?
- Is a low-level test pretending to prove a real boundary works?
- Does the suite detect partial failure and prove recovery, or only the happy path?
- Can a new maintainer tell which test owns each requirement and risk?

### Required output

Provide the behavior-to-evidence matrix, coverage gaps, weak evidence, and the `keep`, `combine`, `replace`, `remove`, and `add` plan. State expected confidence, runtime, and clarity improvements without promising unmeasured gains.

## 5. Code Craft

### Mission

Determine whether the code reads as if one careful author wrote it to one standard: tools enforce what can be measured, and the rest is consistent, named for what it does, and small enough to hold in your head. Lens 3 owns component boundaries, dependency direction, and removal; this lens owns how code reads inside and between modules.

Run the project's own configured linters and type checker first, and report their gaps. Mechanical rules belong in tool configuration, so a finding a tool could catch also proposes the tool rule.

### Required coverage

- **Static-check adequacy:** Linter rule groups, type checker, shell linter, and dead-code and duplicate finders in the gate; whether each gap is worth closing, judged by measured violation counts; every suppression (`noqa`, `type: ignore`, `shellcheck disable`) justified or removed
- **Size and complexity:** File length, function length, branches, arguments, nesting, and line width, with limits proposed from the measured distribution, not from taste
- **Naming:** Names say what a thing is or does; one name per concept across modules; no abbreviations a newcomer must guess; folder and file names match their contents
- **Modularity:** One job per module and function; helpers that exist in two places; code that belongs in another module
- **Consistency:** The same problem solved the same way: error types and messages, path handling, subprocess calls, output format, type-hint style, and string formatting
- **Comments versus code:** Comments say why, never what; a comment that a name, type, assertion, or test could replace is a finding; no narration, stale comments, or commented-out code
- **Readability:** Layers between a question and its answer, one-caller wrappers, and hidden state

### Adversarial questions

- Which rule would a strict tool flag that the gate does not run, and would fixing it help?
- Where do two modules solve the same problem two different ways?
- Which name would mislead a newcomer about what the code does?
- Which function could not be explained in two sentences?
- Which comment exists because the code is unclear?

### Required output

Numbered findings, each with file:line, the coverage group, the evidence, the smallest fix, and severity (high: misleads or hides a defect; medium: slows every reader; low: polish). A proposed gate change lists the rules or limits, the measured count each would add, and which counts are fixed versus configured away. List the clean areas checked.
