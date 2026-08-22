# Architecture Decision Records

Architecture Decision Records (ADRs) capture durable design choices whose rationale should survive implementation refactoring. They complement [`../architecture.md`](../architecture.md); they do not replace the product contract.

| ADR | Decision |
| --- | --- |
| [ADR-001](ADR-001-snapshot-default.md) | Snapshot is the default publication mode |
| [ADR-002](ADR-002-approved-source-state.md) | Execution is bound to immutable approved source state and fails closed on drift |
| [ADR-003](ADR-003-preservation-recovery.md) | Replacement preserves repositories and recovery evidence rather than deleting or auto-rolling back |
| [ADR-004](ADR-004-shared-execution-boundaries.md) | Wizard/public command share the approved-plan application engine; native commands use centralized no-shell execution |
| [ADR-005](ADR-005-publication-and-host-boundaries.md) | Content verifies before protection restoration; v0.1.0 supports github.com only |

Each ADR records context, decision, alternatives/tradeoffs, and consequences. New ADRs should be added only for durable choices that would be costly or confusing to rediscover from source history.