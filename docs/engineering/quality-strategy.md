---
title: "CopyGitHubRepo Quality Strategy – Test and Release Evidence"
description: "Understand CopyGitHubRepo quality strategy, test taxonomy, traceability, coverage, live E2E evidence, resilience validation, and release-candidate evidence requirements."
---

# Quality strategy and traceability

This document is the authoritative quality strategy for Copy GitHub Repository. It explains how product requirements and behavioral scenarios are evidenced by automated tests, live end-to-end capability, and release-specific validation.

It does **not** redefine product behavior. [`product-contract.md`](../product/product-contract.md) remains authoritative for requirements and invariants, while [`product-model.md`](../product/product-model.md) provides the stable `CAP-*`, `UC-*`, and `SCN-*` traceability IDs used here.

## Quality model

Quality evidence is intentionally layered:

1. **Static and repository policy checks** — PSScriptAnalyzer, source-documentation rules, workflow/package/documentation contracts.
2. **Unit tests** — isolated logic, parsing, validation, formatting, presentation, and controlled adapters.
3. **Integration tests** — orchestration across multiple module components, especially mutation, safety, verification, replacement, recovery, settings, protection, and wizard execution.
4. **Contract tests** — public API, packaging, documentation, release, workflow, security, dependency, and repository-quality contracts.
5. **End-to-end capability** — authenticated disposable-GitHub scripts that exercise real Git/GitHub behavior.
6. **Release-candidate live validation** — an actual E2E execution against the exact commit/tag being considered for release.
7. **Release evidence** — concise records tying the exact release candidate to automated/live results, known exclusions, and accepted risk.

No single layer proves overall correctness. Passing unit tests does not prove GitHub behavior; a live E2E harness existing does not prove a release candidate was actually exercised; and code coverage is a regression signal rather than a completeness claim.

## Test taxonomy

`tests/TestTaxonomy.psd1` is the machine-readable authority for suite classification.

| Category | Purpose | Does not prove |
| --- | --- | --- |
| **Unit** | Fast, isolated behavior with dependencies mocked or controlled | End-to-end orchestration or real GitHub behavior |
| **Integration** | Multiple module components working together, including safety/mutation/recovery paths | Real external GitHub state or account/plan-specific behavior |
| **Contract** | Public API, docs, package, release, workflow, security, and repository contracts | Runtime correctness of every internal implementation path |
| **EndToEnd** | Real authenticated Git/GitHub behavior using disposable repositories | That a particular release candidate was run unless evidence records that exact commit/tag |

Every Pester suite and every `Invoke-*EndToEndTests.ps1` harness must be classified exactly once. `tests/TestTaxonomy.Tests.ps1` enforces this.

## Supporting quality controls

### PSScriptAnalyzer

PSScriptAnalyzer is a static-quality and policy control. It catches selected PowerShell correctness/style/security findings and repository-specific documentation rules. It is **not** a complete static application security testing system and does not replace tests or threat analysis.

### Documentation validation

`./build/Test-Documentation.ps1` runs documentation-focused Contract suites. It protects navigation, authority, user/maintainer guidance, release documentation, and other documentation contracts without running the full source quality gate for documentation-only changes.

### Package and release validation

The Quality Gate builds and validates the PowerShell Gallery package. Contract suites also protect module exports, package contents, version/release assumptions, provenance, uninstall packaging, and release workflow behavior.

### Workflow contracts

Workflow Contract tests verify important CI/release configuration properties such as triggers, permissions, pinned actions, validation steps, and release behavior. Passing those tests proves the repository configuration matches the tested contract; it does not prove every future GitHub-hosted runner/service condition.

### Coverage

The project currently enforces a **65% Pester instruction-coverage floor** across `src/CopyGitHubRepo`. This is a regression guard based on a previously demonstrated cross-platform baseline, not a claim that 65% of product risk is covered or that the software is 65% correct.

High-risk behavior requires focused positive, negative, safety, partial-failure, verification, recovery, and resilience tests regardless of aggregate percentage.

## Evidence-status vocabulary

Use these terms precisely:

- **Implemented** — source contains the capability.
- **Automatically tested** — one or more automated suites protect the relevant behavior/contract.
- **E2E-capable** — an authenticated live harness exists for the scenario/capability.
- **Live-validated** — the behavior was actually exercised against live GitHub for a specific recorded commit/tag.
- **Release-validated** — required automated and live evidence for the exact release candidate has been reviewed and accepted.
- **Constrained** — validation depends on GitHub plan/account/platform capabilities or another external condition.
- **Gap** — material evidence is absent or insufficient and must be explicitly dispositioned before release readiness.

Never use **E2E-capable** and **live-validated** interchangeably.

## High-risk traceability matrix

This matrix is a human-readable index, not a replacement for the machine-readable taxonomy or product contract. The final column intentionally avoids reconstructing immutable `v0.1.0` live-run history inside this mutable strategy page. Exact release-candidate runs, exclusions, and accepted-risk decisions belong in the release-specific qualification/evidence record.

| Product area / scenarios | Primary automated evidence | Live E2E capability | Current release-evidence treatment |
| --- | --- | --- | --- |
| Planning / immutable source state — `CAP-PLAN`, `SCN-PLAN-*` | `ApprovedSourceState.Tests.ps1`, `StaleStateSafety.Tests.ps1`, `RiskFailurePaths.Tests.ps1` | Exercised indirectly by copy E2E harnesses | See immutable `v0.1.0` qualification evidence for exact-candidate live-run status |
| Snapshot — `CAP-SNAP`, `SCN-SNAP-*` | `NewDestinationSnapshot.Tests.ps1`, `SnapshotPagination.Tests.ps1`, `Provenance.Tests.ps1` | `Invoke-SnapshotEndToEndTests.ps1` | See immutable `v0.1.0` qualification evidence for exact-candidate live-run status |
| FullHistory — `CAP-HIST`, `SCN-HIST-*` | `FullHistory.Tests.ps1`, `ApprovedSourceState.Tests.ps1` | `Invoke-FullHistoryEndToEndTests.ps1` | See immutable `v0.1.0` qualification evidence for exact-candidate live-run status |
| Existing-destination replacement — `CAP-DEST`, `SCN-DEST-*` | `ExistingDestinationReplacement.Tests.ps1`, `ReplacementExecutionEvidence.Tests.ps1`, `Recovery.Tests.ps1` | Recovery and scenario-specific live harness coverage | See immutable `v0.1.0` qualification evidence for exact-candidate live-run status |
| Same-name archive/replace — `CAP-SAME`, `SCN-SAME-*` | `SameNameExecution.Tests.ps1`, `SameNameSafety.Tests.ps1`, `SameNameFullHistory.Tests.ps1` | `Invoke-SameNameEndToEndTests.ps1`, `Invoke-SameNameFullHistoryEndToEndTests.ps1` | See immutable `v0.1.0` qualification evidence for exact-candidate live-run status |
| Git LFS — `CAP-LFS`, `SCN-LFS-*` | `GitLfs.Tests.ps1` plus mode-specific integration tests | `Invoke-GitLfsEndToEndTests.ps1` | See immutable `v0.1.0` qualification evidence for exact-candidate live-run status |
| Settings — `CAP-SET`, `SCN-SET-*` | `RepositorySettings.Tests.ps1` | `Invoke-RepositorySettingsEndToEndTests.ps1` | See immutable `v0.1.0` qualification evidence for exact-candidate live-run status |
| Protection — `CAP-PROT`, `SCN-PROT-*` | `Protection.Tests.ps1`, `ProtectionRestoreStatus.Tests.ps1` | Live verification may be constrained by repository/account plan features | See immutable `v0.1.0` qualification evidence for exact-candidate live-run status and constraints |
| Wizard — `CAP-WIZ`, wizard `SCN-*` | Wizard Unit suites plus `WizardMigrationIntegration.Tests.ps1`, `WizardOrchestration.Tests.ps1` | Underlying migration E2E harnesses validate engine behavior; wizard-specific live use is not required for every release | No independent wizard-specific live claim is made here |
| Verification / recovery — `CAP-VERIFY`, `CAP-EVID`, `SCN-*-VERIFY`, `SCN-*-PARTIAL`, `SCN-*-RECOVERY` | `Recovery.Tests.ps1`, `RiskFailurePaths.Tests.ps1`, `ReplacementExecutionEvidence.Tests.ps1`, relevant mode suites | `Invoke-RecoveryEndToEndTests.ps1` plus mode harnesses | See immutable `v0.1.0` qualification evidence for exact-candidate live-run status |
| API throttling/transient reads — `SCN-API-RESILIENCE-01` | `GitHubApiAdapters.Tests.ps1` | Live rate-limit/service degradation is external and not required as a deterministic release fixture | Automatically tested; no live-release degradation claim |
| Native timeout/controlled cancellation — `SCN-NATIVE-RESILIENCE-01` | `NativeCommandStreams.Tests.ps1` | Real native Git/Git LFS behavior is exercised by mode E2E harnesses; timeout injection itself is deterministic CI evidence | Automatically tested; exact-candidate live mutation evidence remains release-specific |
| Local disk/temp exhaustion — `SCN-RESOURCE-RESILIENCE-01` | `LocalResourcePreflight.Tests.ps1` | Scale characterization supplies measured workspace evidence rather than a destructive low-disk live fixture | Characterized/automatically tested; no universal size limit claimed |
| Retry after pre-mutation failure — `SCN-RETRY-RESILIENCE-01` | Retry/idempotency integration tests and prerequisite/stale-state suites | Normal copy E2E harnesses preserve the same pre-mutation guards | Automatically tested; no separate live retry requirement |
| Retry after partial mutation — `SCN-RETRY-RESILIENCE-02` | Retry/idempotency integration tests, `Recovery.Tests.ps1`, replacement evidence suites | `Invoke-RecoveryEndToEndTests.ps1` and replacement harnesses where remote identities matter | E2E-capable; exact-candidate live status belongs to immutable release evidence |
| Pagination and larger scale/resource dimensions — `SCN-SCALE-RESILIENCE-01` | `SnapshotPagination.Tests.ps1`, scale-characterization fixture/tests/workflow | Controlled local characterization plus live GitHub baseline characterization | Characterized; not an SLA or supported hard maximum |
| Cross-platform interruption — `SCN-INTERRUPT-RESILIENCE-01` | `InterruptionContract.Tests.ps1`, `NativeCommandStreams.Tests.ps1` | Raw Ctrl+C/hard termination is intentionally not synthesized as a portable blocking E2E assertion | Deterministic portions automatically tested; host signal delivery constrained |
| Distribution / release — `CAP-DIST`, `CAP-REL` | package, release, installer/uninstaller, provenance, workflow Contract suites | Clean install/update verification is release-process evidence rather than repository-copy E2E | `v0.1.0` publication, package discovery/install/import, release assets, checksum, SBOM, and attestations were completed and verified through the release process |

## Resilience evidence interpretation

The resilience scenarios above use the same evidence vocabulary as functional scenarios and must not be collapsed into a generic "resilience passed" claim.

- `SCN-API-RESILIENCE-01` proves bounded automatic retry only for recognized side-effect-free GitHub API reads; it does not authorize automatic mutation replay.
- `SCN-NATIVE-RESILIENCE-01` proves controlled timeout/cancellation behavior at the centralized native-process boundary; it does not prove rollback of remote side effects.
- `SCN-RESOURCE-RESILIENCE-01` combines deterministic preflight behavior with characterization evidence. Characterized disk usage is not a universal multiplier or supported repository maximum.
- `SCN-RETRY-RESILIENCE-01` and `SCN-RETRY-RESILIENCE-02` deliberately distinguish retry before mutation from retry after ambiguous partial mutation.
- `SCN-SCALE-RESILIENCE-01` combines blocking pagination correctness with non-blocking scale characterization. Variable timing measurements are evidence, not SLAs.
- `SCN-INTERRUPT-RESILIENCE-01` separates explicit controlled cancellation from host/OS-dependent Ctrl+C and hard process termination. Recovery evidence is only guaranteed where the process remains capable of executing the recovery path.

## Behavioral coverage expectations

For high-risk use cases, testing should deliberately consider:

- successful/happy behavior;
- invalid inputs and unsupported preconditions;
- authentication/authorization/prerequisite failures;
- exact-confirmation and destructive-operation safety boundaries;
- stale state / identity mismatch / TOCTOU behavior;
- boundary and empty-repository cases;
- Git and Git LFS failures;
- verification mismatch;
- settings/protection restoration failure;
- post-mutation partial failure;
- preservation and recovery evidence;
- `-PlanOnly`, `-WhatIf`, cancellation, and other no-op paths;
- deterministic non-interactive automation;
- cross-platform behavior where the operating system can affect native-command/process semantics;
- canonical resilience scenarios from [`product-model.md`](../product/product-model.md), with detailed operational limits in [`non-functional-requirements.md`](../product/non-functional-requirements.md).

A scenario can be adequately protected by more than one suite. The goal is observable behavioral coverage, not one-test-file-per-scenario bureaucracy.

## Live E2E policy

Authenticated live E2E is required or strongly expected before release when the risk cannot be adequately proven with mocked/controlled tests alone, especially:

- GitHub repository creation/rename/identity behavior;
- Snapshot and FullHistory publication;
- Git LFS transfer;
- same-name/archive replacement;
- repository settings/protection behavior where supported by the test account;
- recovery behavior after real remote mutation;
- changes to GitHub API/native Git adapter semantics that materially affect mutation or verification.

Live E2E must use disposable repositories and must validate cleanup capability before creating test repositories.

A harness may be **E2E-capable** while a particular release candidate is not **live-validated**. For `v0.1.0`, exact live-run claims are intentionally left to the immutable release-specific qualification record; this mutable strategy page documents capability and evidence semantics rather than reconstructing that historical record.

## External constraints and known gaps

Some evidence can be constrained by external conditions:

- GitHub plan/account features can affect rulesets, branch protection, repository settings, and other administrative APIs.
- GitHub API behavior, rate limiting, transient service degradation, and network failures are external dependencies even when deterministic retry policy is tested.
- Ctrl+C/signal propagation and hard process/session termination remain host/OS dependent; deterministic preservation/recovery boundaries are documented in [`interruption-signal-handling.md`](../user/interruption-signal-handling.md).
- Large-repository/resource measurements are characterization evidence, not a supported maximum or performance SLA; see [`scale-characterization.md`](scale-characterization.md).
- Exact release-candidate live validation remains a release-readiness decision/evidence task rather than something inferred from historical harness runs.

A constrained or missing test must be recorded as a limitation/gap, not silently treated as passing evidence.

## Release-validation evidence model

For an exact release candidate, record concise evidence with these fields:

| Field | Meaning |
| --- | --- |
| **Commit SHA** | Immutable source commit evaluated |
| **Version / tag** | Candidate package/release identity, when assigned |
| **Validation date** | When the evidence was produced |
| **Automated evidence** | Quality Gate run(s), package validation, relevant contract/security checks |
| **Live scenarios** | `SCN-*` IDs or named E2E harnesses actually executed |
| **Environment** | OS/account/plan/tool versions material to interpretation |
| **Result** | Pass/fail/blocked/constrained |
| **Known exclusions** | Required scenarios not executed and why |
| **Accepted risk / blocker** | Explicit readiness disposition, if applicable |
| **Evidence links** | Workflow runs/artifacts/release attestations where useful |

Do not paste raw logs into long-lived prose documents. Store or link durable workflow/release evidence and summarize the decision-relevant facts.

## Release-readiness relationship

This document defines **what quality evidence means**. [`release-readiness.md`](../release/release-readiness.md) decides whether the required evidence for a specific release candidate is sufficient. [`release-runbook.md`](../release/release-runbook.md) consumes that go/no-go decision and must not reinterpret a failed or missing quality requirement as success.

## Maintainer workflow

Use [`maintainer-guide.md`](maintainer-guide.md) to choose focused tests and determine when live E2E is required. The canonical local full preflight remains:

```powershell
./build/Test-Project.ps1
```

GitHub Actions remains the authoritative cross-platform automated validation on Windows, Ubuntu, and macOS.
