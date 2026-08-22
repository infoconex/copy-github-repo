# Engineering principles

CopyGitHubRepo is a PowerShell module, but the design applies the same maintainability principles expected of production software. These principles are intentionally pragmatic: they improve clarity, safety, and testability without forcing object-oriented ceremony onto PowerShell.

## Single responsibility and separation of concerns

Public commands define the supported PowerShell API. They should primarily:

1. validate PowerShell-facing input and prerequisites;
2. establish user intent and safety boundaries such as `ShouldProcess`;
3. create or accept the domain plan required for the operation;
4. delegate cohesive implementation work to private helpers; and
5. return stable structured output.

Private helpers should own one cohesive implementation concern whenever that separation makes the behavior easier to understand, test, or reuse. Function length alone is not a design metric. A longer orchestration function can remain appropriate when splitting it would hide the operation's ordering or create trivial pass-through helpers.

Presentation, Git/GitHub mechanics, validation, planning, execution, verification, recovery, and serialization should remain separable concerns. The interactive wizard is an adapter over the same planning and approved execution boundaries used by scripted callers; it is not a second business-logic implementation.

## DRY without over-abstraction

Duplication is a problem when the same rule or safety invariant can drift between implementations. Safety-critical policy should therefore have one authoritative implementation wherever practical.

Do not remove duplication merely because two code blocks look similar. Snapshot and FullHistory, or different replacement modes, may remain explicit when a generalized abstraction would require mode flags, hidden branching, or a less obvious mutation sequence. A small amount of deliberate duplication is preferable to a generic helper that obscures destructive behavior.

Extract a shared helper when at least one of these is true:

- the same domain rule must stay identical in multiple paths;
- the same object contract is constructed repeatedly and can drift;
- the helper creates a clear test seam around an external dependency or safety boundary;
- extraction makes orchestration materially easier to read; or
- the behavior is independently reusable and has a clear domain name.

Avoid extracting helpers solely to reduce line count.

## SOLID in PowerShell

The project applies the intent of SOLID where it is useful rather than treating the principles as a requirement for classes or interfaces.

- **Single Responsibility:** keep functions and modules cohesive and separate policy, presentation, and external operations when that improves comprehension.
- **Open/Closed:** prefer stable seams and explicit dispatch over rewriting unrelated behavior when a mode or capability is added. Do not introduce strategy hierarchies before the number of variants justifies them.
- **Liskov Substitution:** primarily relevant only if substitutable types or implementations are introduced. Do not create inheritance structures merely to satisfy the principle.
- **Interface Segregation:** keep function contracts focused; callers should not need to supply unrelated values or understand private implementation details.
- **Dependency Inversion:** orchestration should depend on project-owned Git/GitHub helpers and domain contracts instead of scattering native-command details throughout public commands. Formal dependency-injection frameworks are not required.

## Cohesion, coupling, and domain contracts

Prefer high-cohesion functions with domain-specific names over generic utility functions. Keep coupling explicit through parameters and returned objects rather than relying on mutable global state.

Stable `PSTypeName` values, plan objects, verification results, recovery evidence, and ErrorIds are part of the project's programmatic contract. When the same structured object shape is built in several independent paths, consider a focused constructor helper to prevent schema drift. Do not introduce classes unless they provide a concrete benefit beyond what a structured PowerShell object and tests provide.

## Error contract

Project-owned ErrorIds should be meaningful, stable, and suitable for automation. Public commands should keep the user-facing error boundary clear even when validation logic is delegated to private helpers.

Refactoring must not casually change `FullyQualifiedErrorId`, error category, target object, or the distinction between deliberate application errors and unexpected runtime failures.

## Safety over abstraction

Destructive repository operations must remain easy to audit. Mutation order, identity checks, immutable approved source state, exact replacement confirmation, recovery evidence, and fail-closed behavior take priority over eliminating repeated lines.

`-Force` is an acknowledgement mechanism for specifically documented guards, not a universal bypass. `-WhatIf` and `ShouldProcess` remain public PowerShell safety boundaries, while product-specific invariants such as exact replacement confirmation remain independently enforced.

## Testing philosophy

Tests should protect behavior and risk rather than implementation trivia or a coverage percentage alone. Additional coverage is most valuable around:

- destructive mutation ordering;
- source-state drift and TOCTOU protection;
- repository identity preservation;
- replacement and recovery paths;
- native Git/GitHub failure translation;
- Snapshot and FullHistory verification;
- Git LFS behavior; and
- the exact module package users install from PowerShell Gallery.

Coverage thresholds are a floor, not a design target. Do not add low-value tests merely to increase the percentage.

## Complexity test

Before adding an abstraction, ask:

1. Does it centralize a real rule or remove a real source of drift?
2. Does it make the mutation or data flow easier to understand?
3. Can it be named in domain language without words such as `Manager`, `Service`, `Factory`, or `Utility` merely to justify a layer?
4. Does it improve a meaningful test boundary?
5. Would an experienced PowerShell maintainer find the result more idiomatic than the explicit version?

If the answer is generally no, keep the simpler PowerShell implementation.
