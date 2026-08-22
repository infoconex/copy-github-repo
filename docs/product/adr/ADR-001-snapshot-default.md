# ADR-001: Snapshot is the default publication mode

Status: Accepted

## Context

The primary product goal is publishing an approved current repository state as a clean repository without exposing development history. Full history preservation is also valuable, but it is a materially different intent.

## Decision

`Snapshot` is the default content mode. `FullHistory` requires explicit selection.

## Alternatives and tradeoffs

- Default to FullHistory: familiar Git-copy semantics, but conflicts with the product's clean-publication purpose and can expose history unintentionally.
- Require an explicit mode every time: maximally explicit, but adds friction without improving the safety of the documented primary workflow.

## Consequences

User-facing wording must clearly describe Snapshot as a one-root-commit clean publication and FullHistory as history preserving. Tests and documentation must protect that default and prevent ambiguous terminology.