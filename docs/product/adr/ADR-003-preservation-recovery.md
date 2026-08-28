---
title: "ADR-003 – Preserve Repositories and Recovery Evidence | CopyGitHubRepo"
description: "Architecture decision defining preservation-first recovery: CopyGitHubRepo keeps archives, replacements, and recovery evidence instead of deleting repositories or automatically rolling back."
---

# ADR-003: Preserve repositories and recovery evidence instead of deleting or auto-rolling back

Status: Accepted

## Context

Replacement flows can fail after a repository has been archived/renamed or after a replacement has been created. Automatic deletion or rename-back can destroy evidence, collide with partially created resources, or obscure which stages completed.

## Decision

Existing repositories are archived/preserved rather than silently overwritten or deleted. After post-mutation failure, the tool preserves known repositories and records recovery evidence. It does not automatically delete repositories or rename archives back.

## Alternatives and tradeoffs

- Delete/overwrite the existing destination: simpler flow, but destructive and unsuitable for a safety-focused migration tool.
- Automatic rollback: attractive in simple cases, but unreliable once external mutations partially succeed and can make recovery more dangerous.

## Consequences

Partial mutation is an explicit product state. Results and recovery reports must retain known identities, completed stages, and failure stage. Operators make deliberate recovery decisions using preserved evidence.