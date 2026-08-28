---
title: "CopyGitHubRepo Product Journeys, Capabilities, Use Cases, and Scenarios"
description: "Explore CopyGitHubRepo personas, product journeys, capability and use-case catalogs, behavioral scenarios, resilience requirements, and traceability from requirements to release evidence."
---

# Product journeys and behavioral model

This document provides the product/program structure that connects people and goals to the authoritative behavior defined in [`product-contract.md`](product-contract.md).

It does **not** redefine product behavior. `docs/product/product-contract.md` remains authoritative for supported scope, invariants, exclusions, safety semantics, verification, and recovery. Command syntax remains authoritative in [`docs/reference/commands/`](../reference/commands/README.md) and native PowerShell help.

The traceability model is:

`Persona -> Journey -> Capability -> Use Case -> Product Requirement -> Acceptance Criteria -> Behavioral Scenario -> Automated Test -> Live Validation -> Release Evidence`

Later quality and release work can attach test and release evidence to the stable IDs defined here without duplicating the product contract.

## Product intent

### Problem

A repository owner may need to publish a developed GitHub repository as a clean repository whose visible Git history begins with the approved current state, or make a history-preserving copy, without manually reconstructing repository content, releases, settings, safety checks, and verification steps.

### Intended outcome

The operator can deliberately choose clean `Snapshot` publication or `FullHistory` copy, optionally preserve an approved subset of GitHub Releases in FullHistory, review the exact planned source state before mutation, preserve an existing repository when replacement is required, verify the resulting content/configuration, and retain usable provenance or recovery evidence.

### Goals

- Make clean current-state publication the safe, understandable default.
- Provide an explicit history-preserving alternative.
- Bind mutation to reviewed immutable source-state evidence and fail closed on drift.
- Preserve selected GitHub Releases and assets in FullHistory without changing Git tag/commit identity.
- Preserve existing repositories rather than silently overwrite or delete them.
- Make planning, mutation, verification, and recovery behavior observable.
- Support both guided human use and deterministic automation.

### Non-goals

- Repository deletion or silent destructive overwrite.
- Snapshot GitHub Release preservation.
- Copying GitHub historical/operational records such as pull requests, issues, workflow-run history, stars, watchers, forks, or traffic history.
- Migrating secret values, webhooks, deploy keys, environments, collaborator/team access, packages, or deployments.
- Restoring GitHub Pages or enabling GitHub Actions after migration.
- Supporting GitHub Enterprise Server or non-GitHub.com hosts.

## Personas and primary journeys

The seven primary documentation personas are defined in [`documentation-strategy.md`](../engineering/documentation-strategy.md). Their product-facing journeys are summarized here so capabilities can be traced across audiences.

| Persona | Primary journey | Product question |
| --- | --- | --- |
| User / Operator | Evaluate -> choose mode/scenario -> plan -> execute -> verify -> recover/support | Can I accomplish my repository-copy goal safely and understand what happened? |
| Contributor / Maintainer | Understand behavior -> change -> validate -> document -> release/support | What product behavior must remain true when I change the implementation? |
| Quality Engineer | Requirement -> scenario -> automated evidence -> live evidence -> release evidence | How do we know the advertised behavior and failure semantics are protected? |
| Architect / Engineering Reviewer | Capability -> boundaries/state -> invariants -> design decisions | Does the design preserve the product's safety and verification model? |
| Security Reviewer | Threat/trust boundary -> control -> failure behavior -> evidence/residual risk | Can privileged mutation and supply-chain behavior be assessed independently? |
| Governance / Compliance Reviewer | Scope/dependencies/data/permissions -> assurance evidence -> support | Is the product's actual operating and distribution posture understandable? |
| Product / Program Manager | Intent -> capability -> use case -> scenario -> dependency -> readiness/go-no-go | Is the release complete, coherent, evidenced, and deliberately scoped? |

Industry Expert remains a cross-cutting quality lens rather than another persona.

## Capability catalog

Capability IDs are stable traceability handles. They organize the product; they are not separate implementation components.

| ID | Capability | Primary product-contract authority |
| --- | --- | --- |
| `CAP-DISC` | Repository discovery and GitHub authentication boundary | Public command contract; host/release contract |
| `CAP-PLAN` | Immutable source-state planning and preview | Immutable approved source state |
| `CAP-SNAP` | Snapshot clean publication | Canonical content terminology; verification |
| `CAP-HIST` | FullHistory copy | Canonical content terminology; verification |
| `CAP-GHREL` | FullHistory GitHub Release selection, restoration, asset transfer, and verification | GitHub Release preservation; immutable approved source state |
| `CAP-DEST` | New-destination and existing-destination safety | Destination and replacement safety |
| `CAP-SAME` | Same-name archive-and-replace | Destination and replacement safety |
| `CAP-LFS` | Git LFS planning, transfer, and verification | Immutable approved source state; verification |
| `CAP-SET` | Supported ordinary repository-settings restoration | Supported repository configuration |
| `CAP-PROT` | Transferable repository-protection restoration/skipped semantics | Supported repository configuration |
| `CAP-WIZ` | Guided wizard planning/review/execution/cancellation/help | Guided wizard |
| `CAP-AUTO` | Deterministic scripted/non-interactive operation | Public command contract; destination safety |
| `CAP-VERIFY` | Standalone and execution-integrated verification | Verification |
| `CAP-EVID` | Provenance, structured reporting, and recovery evidence | Provenance and recovery |
| `CAP-DIST` | Installation/update/uninstall and stable distribution contract | Host/release contract plus installation/versioning authorities |
| `CAP-REL` | Release packaging/publication integrity and immutable release boundary | Host and release contract plus versioning/publishing authorities |

## Use-case catalog

Use-case IDs represent user/program outcomes. A use case may rely on several capabilities and several product-contract requirements.

| ID | Actor / goal | Preconditions | Capabilities | Mutation / evidence expectation |
| --- | --- | --- | --- | --- |
| `UC-DISC-01` | Operator discovers/selects an accessible GitHub.com source repository | PowerShell/Git/`gh`; authenticated GitHub CLI | `CAP-DISC` | Read-only; repository identity/metadata returned |
| `UC-PLAN-01` | Operator previews a Snapshot or FullHistory operation before mutation | Valid source/destination/options | `CAP-PLAN`, `CAP-AUTO` | No mutation; immutable approved source evidence and plan returned |
| `UC-SNAP-NEW` | Operator publishes current approved source state to a new destination with one unrelated root commit | Fresh destination name; unchanged approved source | `CAP-PLAN`, `CAP-SNAP`, `CAP-DEST`, `CAP-LFS`, `CAP-VERIFY`, `CAP-EVID` | Destination created/published; verification/provenance returned |
| `UC-HIST-NEW` | Operator copies approved ordinary Git history to a new destination | Fresh destination; unchanged approved source | `CAP-PLAN`, `CAP-HIST`, `CAP-DEST`, `CAP-LFS`, `CAP-VERIFY`, `CAP-EVID` | Destination created; branch/tag/history/LFS verification returned |
| `UC-HIST-REL` | Operator preserves selected GitHub Releases and assets during FullHistory migration | FullHistory; selected releases resolve to preserved tags; approved release state unchanged | `CAP-PLAN`, `CAP-HIST`, `CAP-GHREL`, `CAP-VERIFY`, `CAP-EVID` | Approved releases/assets recreated only after FullHistory verification and read back |
| `UC-DEST-REPLACE` | Operator archives an existing different destination and creates a replacement | Explicit archive-and-replace path and exact confirmation | `CAP-PLAN`, `CAP-DEST`, content-mode capability, `CAP-VERIFY`, `CAP-EVID` | Existing destination preserved under archive identity before replacement |
| `UC-SAME-REPLACE` | Operator republishes under the source's current name while preserving the original as an archive | Same-name flow; unused archive; exact confirmation | `CAP-PLAN`, `CAP-SAME`, content-mode capability, `CAP-VERIFY`, `CAP-EVID` | Original source renamed/preserved; replacement receives distinct identity |
| `UC-VIS-01` | Operator changes destination visibility deliberately | Valid visibility target; explicit force acknowledgement for mutation | `CAP-DEST`, `CAP-AUTO` | Visibility change is explicit, never implicit |
| `UC-SET-01` | Operator restores supported ordinary settings after content verification | Content verification succeeded; settings not skipped | `CAP-SET`, `CAP-VERIFY` | Supported settings restored differentially and read back |
| `UC-PROT-01` | Operator restores transferable protection without weakening semantics | Content/settings phase complete; protection transferable | `CAP-PROT`, `CAP-VERIFY` | Transferable protection restored/read back; unsupported policy reported as skipped |
| `UC-WIZ-01` | Human operator completes the guided flow | Interactive PowerShell host; authenticated prerequisites | `CAP-WIZ`, `CAP-DISC`, `CAP-PLAN`, relevant execution capabilities | Real plan reviewed; explicit execute decision before mutation |
| `UC-AUTO-01` | Automation performs a deterministic non-interactive copy | Complete explicit inputs; required force/confirmation semantics | `CAP-AUTO`, `CAP-PLAN`, relevant execution capabilities | Structured result/evidence; no hidden interactive dependency |
| `UC-VERIFY-01` | Caller independently compares current source and destination state | Both repositories accessible | `CAP-VERIFY` | Read-only structured comparison result |
| `UC-RECOVER-01` | Operator understands what survived after a post-mutation failure | Mutation started and operation terminated | `CAP-EVID`, relevant mutation capability | Durable recovery evidence when possible; no automatic delete/rename-back |
| `UC-DIST-01` | User installs, updates, or removes the module through a supported distribution path | Appropriate package/release exists for requested path | `CAP-DIST` | Local module state changes only; trust boundary documented |
| `UC-REL-01` | Maintainer publishes an immutable stable release | Exact release candidate has required readiness evidence | `CAP-REL`, `CAP-DIST` | Tag/package/release publication follows version/integrity contract |

## Behavioral scenario taxonomy

Scenario IDs are intentionally concise. [`user-guide.md`](../user/user-guide.md) and [`troubleshooting-recovery.md`](../user/troubleshooting-recovery.md) translate them into user-facing scenario and recovery guidance, while [`quality-strategy.md`](../engineering/quality-strategy.md) attaches Unit/Integration/Contract/E2E/live-release evidence.

Scenario categories:

- `HAPPY` — expected successful outcome.
- `VALIDATION` — invalid input, unsupported scope, or unmet precondition before mutation.
- `AUTH` — authentication/authorization/prerequisite failure.
- `SAFETY` — exact confirmation, identity, stale-state, or destructive-operation guard.
- `EDGE` — meaningful boundary behavior such as empty repositories or LFS/no-LFS cases.
- `PARTIAL` — failure after mutation has begun.
- `VERIFY` — content/settings/protection/release verification failure.
- `RECOVERY` — preservation/evidence behavior after failure.
- `NOOP` — `-PlanOnly`, `-WhatIf`, cancellation, or rejected execution with no mutation.
- `AUTOMATION` — non-interactive behavior.
- `RESILIENCE` — scale, network, rate-limit, timeout, cancellation, retry, interruption, and local-resource behavior.

## High-value behavioral scenarios

### Planning and stale-state safety

#### `SCN-PLAN-HAPPY-01` — approved plan captures executable source state

**Given** a supported GitHub.com source and valid options, **when** planning completes, **then** the plan records the content-mode-specific immutable approved source evidence required by the product contract, **and** no GitHub mutation occurs. When GitHub Releases are requested, the plan also records the exact filtered release inventory and tag/asset evidence.

Use cases: `UC-PLAN-01`, `UC-SNAP-NEW`, `UC-HIST-NEW`, `UC-HIST-REL`, `UC-DEST-REPLACE`, `UC-SAME-REPLACE`.

#### `SCN-PLAN-SAFETY-01` — stale plan fails closed

**Given** an approved plan whose Git source state changes before the first GitHub mutation, **when** execution revalidates the source, **then** execution terminates with the stale-state outcome defined by the product contract, **and** destination creation/rename does not proceed from that plan.

Mutation expectation: none from the stale plan.

#### `SCN-PLAN-NOOP-01` — plan-only and WhatIf do not mutate

**Given** otherwise valid mutating inputs, **when** `-PlanOnly` or `-WhatIf` is used, **then** the operation produces preview/ShouldProcess behavior without creating, renaming, publishing, deleting, restoring releases, or restoring destination resources.

### Snapshot publication

#### `SCN-SNAP-HAPPY-01` — new-destination Snapshot publication

**Given** an approved unchanged Snapshot plan and unused destination, **when** execution succeeds, **then** the approved default-branch tree is published as exactly one unrelated root commit, required Snapshot LFS transfer succeeds, and destination content verification/provenance is returned.

Use case: `UC-SNAP-NEW`.

#### `SCN-SNAP-VERIFY-01` — Snapshot mismatch is not reported as success

**Given** Snapshot publication has occurred but the destination tree/root-commit contract or required LFS verification does not match approved evidence, **when** verification runs, **then** the operation does not report successful migration, **and** recovery/evidence semantics reflect the stage reached.

### FullHistory copy

#### `SCN-HIST-HAPPY-01` — new-destination FullHistory copy

**Given** an approved unchanged FullHistory plan and unused destination, **when** execution succeeds, **then** approved ordinary branches/tags/reachable history/default branch and reachable required LFS objects are preserved and verified according to the product contract.

Use case: `UC-HIST-NEW`.

#### `SCN-HIST-VERIFY-01` — missing/mismatched history is a verification failure

**Given** FullHistory publication has occurred, **when** branch/tag targets, reachable commit count, branch-tip trees, default branch, or required LFS evidence does not match the approved state, **then** the copy is not reported as verified success.

### GitHub Releases in FullHistory

#### `SCN-GHREL-HAPPY-01` — approved releases are restored after FullHistory verification

**Given** an approved FullHistory plan with `-IncludeReleases`, unchanged selected release evidence, and destination tags resolving to the approved commit SHAs, **when** content verification succeeds, **then** the approved GitHub Releases and assets are recreated and read back before settings/protection restoration completes.

Use case: `UC-HIST-REL`.

#### `SCN-GHREL-SAFETY-01` — selected release drift fails closed

**Given** a selected source release changes or disappears after planning, **when** release restoration revalidates the approved selection, **then** execution terminates with `SourceReleaseStateChangedSincePlanning` and does not silently substitute current release metadata.

#### `SCN-GHREL-SAFETY-02` — destination tag identity must match FullHistory

**Given** a selected release tag exists at the destination but resolves to a commit different from the approved FullHistory commit, **when** release restoration begins, **then** destination release creation is blocked.

#### `SCN-GHREL-SAFETY-03` — existing destination release is not overwritten

**Given** the destination already contains a GitHub Release for an approved tag, **when** restoration reaches that release, **then** the operation fails rather than silently replacing the existing release.

#### `SCN-GHREL-VERIFY-01` — release metadata or assets must read back correctly

**Given** release creation or asset transfer completes but supported metadata, asset name/size, or available digest evidence differs from the approved selection, **when** destination release verification runs, **then** the migration is not reported as verified success.

#### `SCN-GHREL-PARTIAL-01` — partial release restoration is preserved for recovery

**Given** earlier approved releases were restored and a later release fails, **when** execution terminates, **then** already-restored releases are not automatically deleted and recovery evidence identifies the release failure stage and available release evidence.

### Destination preservation and replacement

#### `SCN-DEST-VALIDATION-01` — existing destination is not silently overwritten

**Given** a different destination already exists, **when** the operator has not selected the explicit archive-and-replace flow, **then** execution rejects the destination before destructive replacement behavior.

#### `SCN-DEST-SAFETY-01` — exact replacement confirmation cannot be bypassed

**Given** an archive-and-replace operation, **when** exact case-sensitive confirmation is absent or incorrect, **then** replacement does not proceed; neither `-Force` nor `-Confirm:$false` bypasses the exact confirmation contract.

#### `SCN-DEST-HAPPY-01` — existing destination is archived before replacement

**Given** an approved unchanged source plan, existing destination, unused archive name, and valid exact confirmation, **when** replacement executes, **then** the existing destination is renamed to the archive, archive identity continuity is verified, and only then is the replacement created.

Use case: `UC-DEST-REPLACE`.

#### `SCN-DEST-PARTIAL-01` — archive succeeds but later replacement fails

**Given** the existing destination was successfully archived and a later replacement stage fails, **when** the operation terminates, **then** the archived destination is preserved, recovery evidence identifies completed/failed stages and known identities, and the tool does not automatically rename back or delete repositories.

### Same-name replacement

#### `SCN-SAME-HAPPY-01` — original identity is preserved under archive name

**Given** a same-name operation with valid exact confirmation and unchanged approved source state, **when** execution proceeds, **then** the original repository is archived, archive identity continuity is verified against the approved source identity where available, and the replacement created under the original name receives a distinct immutable repository identity.

Use case: `UC-SAME-REPLACE`.

#### `SCN-SAME-SAFETY-01` — source/archive identity mismatch fails closed

**Given** the source/archive identity cannot be shown to be the preserved approved repository where immutable identity evidence is available, **when** the same-name flow reaches that safety boundary, **then** replacement publication does not continue as successful.

### Git LFS

#### `SCN-LFS-HAPPY-01` — required LFS content is available and transferred

**Given** approved source evidence identifies required LFS content for the selected mode, **when** publication and verification succeed, **then** required reachable LFS objects are available at the destination according to that mode's contract.

#### `SCN-LFS-VALIDATION-01` — unavailable required LFS content blocks false success

**Given** required source LFS objects cannot be shown available/transferred as required, **when** planning/execution/verification reaches the applicable boundary, **then** the operation does not claim successful verified publication.
