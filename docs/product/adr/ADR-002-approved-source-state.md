# ADR-002: Bind execution to immutable approved source state

Status: Accepted

## Context

A plan can be reviewed and approved while the source repository remains mutable. Re-discovering source state after approval creates a time-of-check/time-of-use gap and can cause execution to act on state the operator never reviewed.

## Decision

Planning captures mode-specific immutable source evidence. The exact approved plan is passed to execution. Before the first GitHub mutation and again inside the copy workspace, execution verifies that the source still matches the approved evidence. Drift fails closed with `SourceStateChangedSincePlanning`.

## Alternatives and tradeoffs

- Re-read source state at execution and continue: simpler, but silently changes the approved operation.
- Allow a force override: operationally convenient, but defeats review-to-execution binding.

## Consequences

Stale plans must be regenerated and reviewed. New-destination creation, archive/rename, or same-name replacement must not begin from stale evidence. Tests must protect both pre-mutation and workspace validation boundaries.