---
title: "CopyGitHubRepo Maintainer Guide – Change Impact and Definition of Done"
description: "Use the CopyGitHubRepo maintainer guide to map repository ownership, choose validation and live E2E, triage failures, assess change impact, and apply the project Definition of Done."
---

# Maintainer guide

This guide is the contributor/maintainer map for making changes safely and knowing when a change is complete. `CONTRIBUTING.md` remains the entry point; this page owns the repository map, change-impact guidance, focused validation choices, maintainer failure triage, and Definition of Done. Project decision ownership, proposal paths, CODEOWNERS policy, and maintainership transfer are authoritative in `docs/engineering/governance.md` rather than being duplicated here.

## Repository map

| Area | Primary responsibility | Typical reasons to change it |
| --- | --- | --- |
| `src/CopyGitHubRepo/Public/` | Public commands and user-visible command contracts | Parameters, help, orchestration, output behavior |
| `src/CopyGitHubRepo/Private/` | Planning, Git/GitHub adapters, migration execution, verification, recovery, wizard helpers, presentation helpers | Product behavior, safety, integration logic, native command interaction |
| `src/CopyGitHubRepo/CopyGitHubRepo.psd1` | Module metadata and exported-command contract | Version, exports, compatibility metadata |
| `src/CopyGitHubRepo/CopyGitHubRepo.psm1` | Module composition/loading | Source layout or module bootstrap changes |
| `src/CopyGitHubRepo/CopyGitHubRepo.format.ps1xml` | Default display formatting | Human-readable object presentation |
| `tests/` | Unit, integration, and contract tests plus taxonomy/policy data | Behavior, safety, packaging, docs, workflows, public contracts |
| `tests/e2e/` | Authenticated disposable-GitHub live scenarios | Real Git/GitHub behavior requiring external evidence |
| `build/` | Local quality gate, dependency setup, packaging, release validation, documentation validation | Engineering automation and release tooling |
| `.github/workflows/` | Cross-platform CI, docs deployment, release automation | CI/CD behavior, permissions, concurrency, release process |
| `docs/` | Product, user, engineering, architecture, security, release, and assurance authorities | Documentation or contract changes |
| `_data/`, `_layouts/`, `assets/`, `_config.yml` | GitHub Pages information architecture and presentation | Documentation-site navigation/layout/assets |
| `README.md` | Product front door | Product overview, quick start, primary navigation |
| `CONTRIBUTING.md` | Contributor entry point | Development prerequisites and contribution workflow |
| `SECURITY.md` | Vulnerability reporting and supported security versions | Security support/reporting changes |
| `CHANGELOG.md` | User-visible release change history | Changes that affect released behavior or distribution |

The current architecture and behavioral boundaries are authoritative in `docs/product/architecture.md`, `docs/product/product-contract.md`, `docs/product/product-model.md`, and `docs/product/non-functional-requirements.md`. Do not infer ownership solely from file location when those contracts say otherwise.

## Normal development workflow

1. Identify the authoritative contract affected by the change before editing implementation.
2. Install the pinned development dependencies with `./build/Install-DevelopmentDependencies.ps1`.
3. Make the smallest coherent implementation and documentation change.
4. Run focused tests while developing.
5. Run the canonical local preflight, `./build/Test-Project.ps1`, for every source/test/build/module/workflow change.
6. For documentation-only changes, use `./build/Test-Documentation.ps1`; source-affecting changes still require the full project gate.
7. Run authenticated live E2E when the change affects behavior that mocks/local integration cannot establish with sufficient confidence.
8. Push only after local self-review. Treat GitHub Actions on Windows, Ubuntu, and macOS as the authoritative cross-platform gate.
9. Resolve all analyzer, test, coverage, packaging, documentation, and workflow failures before considering the change complete.
10. Update changelog/version/release material when the release contract requires it.

## Change-impact matrix

| Change type | Minimum review/validation | Documentation/contract impact | Live E2E expectation |
| --- | --- | --- | --- |
| Public command/API | Public help/output/parameter contract tests, affected unit/integration tests, full preflight | Command reference; product contract/model when behavior changes; changelog if user-visible | Required when behavior depends on real GitHub/Git semantics not proven by deterministic tests |
| Safety or mutation behavior | Failure-path, stale-state, replacement/recovery, verification tests; full preflight | Product contract, product model `SCN-*`, troubleshooting/recovery, architecture as applicable | Normally required before release for changed destructive or partial-mutation paths |
| Wizard UX | Wizard unit/integration/presentation tests plus underlying migration tests | Wizard contract, command help, user guide when the operator journey changes | Required only when the change alters real GitHub execution rather than presentation/selection alone |
| Git/GitHub/native adapter | Adapter unit tests, integration tests, error translation, pagination/resource/resilience tests as applicable | Non-functional, troubleshooting, architecture/security docs when externally material | Strongly expected for changed external command/API behavior |
| Packaging/release/build workflow | Contract tests for package/release/workflow plus full preflight | Publishing/versioning/release docs and changelog where applicable | Required when the release path itself must be demonstrated against an external distribution service |
| Documentation-only | `./build/Test-Documentation.ps1`, Pages validation if published-site content changes | Update the authoritative page first; avoid duplicated normative text | Not required unless documentation is recording a live-validation claim |
| Security-sensitive behavior | Relevant safety/adaptor tests, analyzer/security checks, negative paths, secret handling review | `SECURITY.md`, installation/security architecture or assurance docs as applicable | Required when a security claim depends on external GitHub behavior |
| Formatting/presentation only | Focused presentation/formatting tests plus full preflight when source changes | Command/user docs only if visible semantics change | Usually not required |
| Test-only | Affected taxonomy/coverage/contracts; full preflight | Usually none unless the test defines a documented contract | Not required unless adding/fixing the live harness itself |

The matrix defines a minimum, not an exemption from engineering judgment. Higher-risk changes may require broader validation.

## When live E2E is required

Authenticated live E2E is intentionally separate from routine CI. Use it when the remaining uncertainty is specifically about real GitHub/Git/Git-LFS behavior rather than local logic.

Treat live E2E as release-relevant for changes to:

- Snapshot or FullHistory publication mechanics;
- same-name or archive-and-replace mutation paths;
- repository settings or branch-protection restoration;
- Git LFS publication/verification;
- GitHub identity/stale-state behavior that depends on real repository state;
- recovery behavior after real partial mutation;
- external-service behavior where mocks cannot prove the release claim.

A passing E2E harness means the repository is **E2E-capable**. Do not call a release **live-validated** until the applicable scenario was actually run against the exact release-candidate commit/evidence set.

## Definition of Done

A change is done only when every applicable item below is satisfied:

- The authoritative behavioral/design/documentation contract was identified and updated where required.
- The implementation is cohesive, avoids needless duplication, preserves single-responsibility boundaries, and follows `docs/engineering/engineering-principles.md`.
- PowerShell code follows `docs/engineering/powershell-style-guide.md` and source documentation follows `docs/engineering/source-code-documentation.md`.
- Positive behavior is tested at the lowest useful level.
- Meaningful invalid-input, failure, safety, partial-mutation, and recovery behavior is tested for the risk introduced by the change.
- New Pester/E2E files are classified exactly once in `tests/TestTaxonomy.psd1`.
- Public help, command docs, product/user/recovery/non-functional docs, or architecture/security docs are updated when their contracts changed.
- `./build/Test-Project.ps1` passes locally for source/test/build/module/workflow changes, or `./build/Test-Documentation.ps1` passes for truly documentation-only changes.
- PSScriptAnalyzer has no repository-blocking findings.
- Aggregate coverage remains at or above the enforced threshold without low-value tests added only to manipulate the number.
- Gallery package/release contract validation passes when packaging or module metadata can be affected.
- Cross-platform GitHub Actions passes on Windows, Ubuntu, and macOS for changes that enter the Quality Gate.
- Applicable live E2E is run when real external behavior is necessary to establish confidence; evidence is tied to the tested commit.
- `CHANGELOG.md`, versioning, compatibility, or release-readiness material is updated when required by the nature of the change.
- No credentials, tokens, private migration evidence, or unnecessary private repository content is committed or uploaded as diagnostics.
- The final diff is self-reviewed for accidental unrelated changes and stale/duplicated documentation.

## Maintainer failure triage

### PSScriptAnalyzer failure

Run `./build/Test-Project.ps1` locally and fix the reported rule rather than suppressing it by default. If a rule is genuinely inappropriate, the repository analyzer policy is the authority; change policy only with a documented rationale and protecting test.

### Test-taxonomy failure

Every Pester test file and every `Invoke-*EndToEndTests.ps1` script must be classified exactly once. Update `tests/TestTaxonomy.psd1`; do not rename a file merely to escape classification.

### Coverage failure

Find which meaningful behavior lost coverage. Prefer restoring assertions around observable behavior, safety boundaries, failure handling, or public contracts. Do not add assertions whose only purpose is raising the percentage.

### Documentation-contract failure

Identify which authoritative document or navigation relationship drifted. Fix the source of truth first. Avoid weakening a contract test simply because duplicated documentation became inconvenient to maintain.

### Package/release failure

Review module manifest/export/version consistency, release packaging tests, checksum/provenance requirements, and `docs/release/publishing.md` / `docs/release/versioning.md`. Never overwrite an immutable published version merely to make a retry convenient.

### Cross-platform failure

Assume an OS-specific defect until shown otherwise. Inspect path handling, native command invocation, encoding/newlines, process behavior, filesystem semantics, and platform-specific prerequisite behavior. A pass on one runner does not invalidate a failure on another supported platform.

### Live E2E failure

First determine whether GitHub state may already have changed. Follow `docs/user/troubleshooting-recovery.md`, preserve repository identities and recovery evidence, and do not automatically delete/rename-back partial state merely to make the test rerunnable.

## Release and deployment responsibility

Maintainers implement and validate release mechanics, while `docs/engineering/governance.md` owns who has current project decision authority. The release decision must remain separate from implementation convenience. `docs/release/release-readiness.md` owns go/no-go evidence, and `docs/release/release-runbook.md` owns the ordered publication procedure. `docs/release/versioning.md` and `docs/release/publishing.md` remain authoritative for their detailed scopes.

## Related authorities

- `docs/engineering/governance.md` — current project decision ownership, proposal paths, CODEOWNERS policy, and maintainership transfer
- `docs/engineering/documentation-strategy.md` — documentation ownership and anti-duplication rules
- `docs/engineering/engineering-principles.md` — design and maintainability principles
- `docs/engineering/powershell-style-guide.md` — PowerShell conventions and analyzer policy
- `docs/engineering/source-code-documentation.md` — public/private/source documentation requirements
- `docs/product/product-contract.md` — normative product behavior and safety invariants
- `docs/product/product-model.md` — capabilities, use cases, and `SCN-*` scenarios
- `docs/product/non-functional-requirements.md` — resilience, scale, and operational expectations
- `docs/user/troubleshooting-recovery.md` — mutation/recovery state model and operator-safe recovery
- `docs/release/versioning.md` — version semantics
- `docs/release/publishing.md` — current publication operations
