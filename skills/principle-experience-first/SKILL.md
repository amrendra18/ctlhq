---
name: principle-experience-first
description: "Apply when product, UX, or feature-scope tradeoffs come up. Put security and privacy first. Improve user, developer, and agent experience within those limits."
disable-model-invocation: true
---

# Experience First

Security and privacy take priority over experience. Within those constraints, prefer choices that improve user, developer, and agent experience together. When they conflict, prioritize the product's user outcomes and explain the tradeoff.

- Every feature, control, and option must be justified
- Ship less, ship better (polished experience with three features beats rough one with ten)
- Prototype before committing (design decisions are cheaper in throwaway HTML than production code)
- Get the details right (transitions, alignment, spacing, feedback, error states)
- Tighten the core loop (every feature should serve the central workflow or get out of the way)
- Remove taglines, helper text, and secondary labels that add no useful meaning. If basic use needs explanation, improve layout, grouping, or control names first. Keep text needed for accessibility, decisions, error recovery, or consequences.

The user is whoever consumes the work. For a UI that is the end user. For a library or an internal API it is the colleague who imports it. The engineer who maintains the code next is a user too. Consider their needs and explain impact from their perspective.

Foundations should serve the experience. Foundational thinking governs the *sequence* of work. This principle governs the *target*.
