---
title: "CopyGitHubRepo Software Assurance Review Package"
description: "Use the CopyGitHubRepo software assurance review package to assess product scope, licensing, dependencies, permissions, network use, data handling, security controls, release provenance, support, and approval evidence."
---

# Software assurance review package

This page is the organizational review entry point for Copy GitHub Repository. It is designed for Governance / Compliance, security, architecture, quality, and release reviewers who need one place to begin an approval decision without creating a second copy of the project's authoritative engineering contracts.

The package is an **evidence index and current-state summary**, not a certification. It does not claim regulatory compliance, independent assessment, penetration testing, formal certification, or organizational approval. Where a fact is owned elsewhere, this page links to the authoritative source.

## Review status and decision boundary

| Review item | Current state | Authority / evidence |
| --- | --- | --- |
| Product version under review | `0.1.0` is the initial stable release | [Repository module manifest](https://github.com/infoconex/copy-github-repo/blob/main/src/CopyGitHubRepo/CopyGitHubRepo.psd1), [`versioning.md`](../release/versioning.md) |
| Product behavior and supported scope | Implemented/documented contract | [`product-contract.md`](../product/product-contract.md) |
| Support/compatibility lifecycle | Implemented/documented policy; latest published stable version is the supported line | [`support-policy.md`](../user/support-policy.md) |
| Automated quality evidence | Cross-platform Quality Gate, Pester, PSScriptAnalyzer, package validation | [`quality-strategy.md`](../engineering/quality-strategy.md) |
| Exact release-candidate live evidence | Recorded through the release qualification process for the exact v0.1.0 candidate | [`quality-strategy.md`](../engineering/quality-strategy.md) |
| Security architecture/control evidence | Implemented/documented, with explicit residual risk | [`security-architecture.md`](security-architecture.md) |
| Repository security hardening | Main-branch rules, required checks, secret scanning, push protection, and release controls are enabled; residual platform limitations remain documented | [`repository-security-baseline.md`](repository-security-baseline.md) |
| Release SBOM/provenance contract | Implemented in the stable release workflow with deterministic ZIP/checksum, SPDX SBOM, build provenance, and SBOM attestation | [`release-sbom.md`](release-sbom.md) |
| Independent publisher signing | Authenticode signing is not implemented; GitHub artifact attestations are the selected v0.1.0 authenticity control | [`security-architecture.md`](security-architecture.md), [`release-readiness.md`](../release/release-readiness.md) |
| Release approval | Project release approval is governed by the exact-candidate release-readiness process; organizational adoption approval remains the adopter's decision | [`release-readiness.md`](../release/release-readiness.md) |

An organization adopting the tool should make its own approval decision based on its risk tolerance, GitHub governance model, prerequisite software policy, and the exact release evidence available at adoption time.

## Product identity and supported scope

| Item | Current product position |
| --- | --- |
| Product | **Copy GitHub Repository / CopyGitHubRepo** PowerShell module |
| Purpose | Safely copy, publish, and verify GitHub repositories using clean Snapshot or history-preserving FullHistory modes |
| Public interface | `Copy-GitHubRepository`, `Get-GitHubRepository`, `Start-CopyGitHubRepositoryWizard`, `Test-GitHubRepositoryMigration` |
| PowerShell baseline | PowerShell 7.4+, PowerShell Core edition |
| Supported remote host for v0.1.0 | GitHub.com only; unsupported hosts fail closed |
| Primary copy modes | Snapshot (default) and FullHistory |
| Human/automation use | Native PowerShell commands plus a dependency-free console wizard |

The behavioral source of truth is [`product-contract.md`](../product/product-contract.md). User-facing operation and recovery guidance is in [`user-guide.md`](../user/user-guide.md) and [`troubleshooting-recovery.md`](../user/troubleshooting-recovery.md). Support lifecycle and compatibility are authoritative in [`support-policy.md`](../user/support-policy.md); the host-specific boundary is summarized in [`host-support.md`](../user/host-support.md).

## Licensing and redistribution

The repository is licensed under the **MIT License**. The authoritative grant and conditions are in [`LICENSE`](../../LICENSE). The module manifest points to that license and uses the copyright metadata `Licensed under the MIT License.` rather than the potentially ambiguous `All rights reserved` wording.

The release ZIP redistributes project-owned PowerShell/module content and installer/uninstaller scripts. It does **not** bundle PowerShell, Git, GitHub CLI, Git LFS, Pester, PSScriptAnalyzer, or GitHub Actions. Organizations remain responsible for evaluating the licenses and organizational acceptability of externally installed prerequisites and development tooling they choose to use.

The machine-readable release inventory is defined in [`release-sbom.md`](release-sbom.md). The SBOM describes shipped content and deliberately avoids presenting development-only tooling as runtime software.

## Dependency and service inventory

| Class | Current dependency / service | Shipped with release? | Review treatment |
| --- | --- | --- | --- |
| Product payload | CopyGitHubRepo module plus packaged install/uninstall scripts | Yes | MIT-licensed project content; represented in release ZIP/SBOM |
| Runtime PowerShell modules | None declared by the module manifest | No additional module package | No third-party PowerShell runtime module dependency currently shipped |
| Runtime platform | PowerShell 7.4+ | No | External prerequisite |
| Runtime native prerequisite | Git | No | External prerequisite/trust boundary |
| Runtime native prerequisite | GitHub CLI (`gh`) | No | External prerequisite and authentication/API boundary |
| Conditional runtime prerequisite | Git LFS | No | Required when the approved operation includes LFS content |
| Development/test | Pester 6.1.0, PSScriptAnalyzer 1.25.0 | No | Exact-version pinned development dependencies |
| CI/release automation | GitHub Actions dependencies | No | Immutable-SHA pinning policy; monitored/reviewed separately |
| Runtime remote service | GitHub.com | N/A | v0.1.0 supported remote API/Git service |
| Distribution | GitHub Releases, PowerShell Gallery | N/A | Distribution trust boundaries, not installed-module dependencies |

For authoritative dependency/security posture see [`security-architecture.md`](security-architecture.md), [`dependency-monitoring.md`](dependency-monitoring.md), and [`release-sbom.md`](release-sbom.md). Prerequisite compatibility expectations are in [`support-policy.md`](../user/support-policy.md).

## Runtime permissions and authority

CopyGitHubRepo does not define a universal GitHub OAuth/PAT scope requirement because effective authorization depends on repository visibility, ownership/organization policy, and the selected operation. It uses the operator's already-authenticated GitHub CLI context and fails when that identity lacks required access.

| Runtime operation | Required authority in practical terms | Mutation? |
| --- | --- | --- |
| Discover/list/read source | Read repository metadata and source state available to the authenticated operator | No |
| Plan / `-PlanOnly` / `-WhatIf` | Source/destination discovery and validation needed to build the plan | No |
| Create a new destination | Permission to create the destination in the selected owner/organization plus Git push access | Yes |
| Publish Snapshot/FullHistory content | Read source content/refs/LFS as applicable and write destination Git/LFS content | Yes |
| Restore supported repository settings | Permission to update those destination repository settings | Yes |
| Restore supported protections | Sufficient repository administration authority for the selected protection operations | Yes |
| Same-name replacement | Permission to rename/archive the existing repository, create the replacement, publish content, and restore supported configuration | Yes; highest-risk path with exact confirmation |
| Verify migration | Read source/destination evidence required by the selected verification mode | No intended mutation |

The detailed behavioral and authorization safeguards are authoritative in [`product-contract.md`](../product/product-contract.md) and [`security-architecture.md`](security-architecture.md). GitHub secrets, webhook secrets, private deploy-key material, GitHub App credentials, environment secrets, and similar secret-bearing configuration are outside the repository-copy contract and are not requested or copied by the product.

## Maintainer and release permissions

Runtime permissions must not be confused with repository-maintainer/release permissions. A normal operator does not need GitHub Actions release authority, PowerShell Gallery publishing credentials, code-scanning upload permissions, or repository-administration access merely to run the installed module against repositories they are authorized to manage.

Maintainer/release automation uses narrowly scoped platform permissions for its task. The stable release workflow requires repository release publication authority plus `id-token: write` and `attestations: write` so GitHub can create build-provenance and SBOM attestations. Development/quality workflows use their separately declared GitHub Actions permissions. PowerShell Gallery publication credentials are a release/distribution concern and are not part of product runtime authentication.

See [`publishing.md`](../release/publishing.md), [`release-sbom.md`](release-sbom.md), [`repository-security-baseline.md`](repository-security-baseline.md), and the workflow definitions under `.github/workflows/` for the current maintainer/release authority model.

## Network and external-service inventory

| Context | Network/service dependency | Purpose |
| --- | --- | --- |
| Product runtime | GitHub.com API through GitHub CLI | Repository discovery, metadata, creation/rename/settings/protection operations |
| Product runtime | GitHub Git endpoints through Git | Clone/fetch/push repository content |
| Conditional runtime | Git LFS endpoints used by the repository | LFS object transfer when required by selected mode/content |
| Stable installation/update | PowerShell Gallery and/or GitHub Releases | Package/release retrieval |
| Development/CI | GitHub Actions and GitHub-hosted services | Quality, CodeQL, dependency monitoring, documentation validation, release automation |
| Release distribution | GitHub Releases and PowerShell Gallery | Stable artifact/module publication |

The project does **not** define an analytics/telemetry service and does not intentionally transmit product-usage telemetry to the maintainer. Installation/bootstrap trust and network boundaries are documented in [`installation-security.md`](installation-security.md); runtime trust boundaries are documented in [`security-architecture.md`](security-architecture.md).

## Credentials and sensitive-data handling

The product uses the existing GitHub CLI authentication context. It does not intentionally collect, display, copy, or persist token values. HTTPS Git operations use GitHub CLI credentials through command-scoped Git configuration, and interactive Git credential prompting is disabled.

Normal reports/recovery evidence can contain organization/repository names, immutable repository identifiers, commit/tree SHAs, selected mode, completed/failure stages, verification results, and provenance information. Those values may be sensitive in an organization's environment even though they are not authentication secrets.

Tokens, passwords, private keys, GitHub secret values, unrelated private repository content, and similar credential material are not intended to be written to console output, reports, diagnostics, or CI artifacts. The security authority for these rules is [`security-architecture.md`](security-architecture.md); vulnerability reporting instructions are in [`SECURITY.md`](../../SECURITY.md).

## Local data, reports, and recovery artifacts

| Local artifact | Lifetime / ownership expectation |
| --- | --- |
| Temporary Git/workspace content | Implementation-managed transient working data; remnants after interruption should be treated as potentially sensitive repository content |
| User-selected Markdown/JSON result or recovery reports | Persistent operator-controlled evidence; the project does not impose centralized retention or automatic deletion |
| Installed module files | Persist under selected PowerShell module installation scope until updated or uninstalled |
| CI test/diagnostic artifacts | Maintainer/CI evidence governed by GitHub Actions workflow retention/repository settings; not product-runtime data |
| Stable release ZIP/checksum/SBOM/attestations | Publication evidence associated with the release and release immutability/provenance policy |

For partial-mutation state and recovery responsibilities, use [`troubleshooting-recovery.md`](../user/troubleshooting-recovery.md). No statement on this page is an organizational records-retention policy.

## Security controls and verification evidence

The authoritative threat/control/evidence matrix is [`security-architecture.md`](security-architecture.md). Current layered controls include approved immutable source-state binding, archive-before-replace and repository-identity continuity, centralized native-process execution, custom high-signal PowerShell security analyzer rules, Pester coverage, CodeQL for GitHub Actions, exact dependency pins and monitoring, repository security-baseline evidence, and deterministic release integrity/SBOM/attestations.

These controls are evidence of the checks that exist. They are **not** proof that the product is vulnerability-free, are not comprehensive SAST, and do not constitute an independent security assessment. Quality evidence and the distinction between automated, E2E-capable, live-validated, and release-specific evidence are authoritative in [`quality-strategy.md`](../engineering/quality-strategy.md).

## Release, installation, update, and provenance trust

The stable-release contract requires the exact tagged commit to pass the reusable Windows, Ubuntu, and macOS Quality Gate before release publication. Stable release evidence includes the deterministic versioned ZIP, SHA-256 checksum, SPDX 2.3 JSON SBOM, GitHub build-provenance attestation, and GitHub SBOM attestation.

`install-release.ps1` verifies the selected ZIP against the published checksum and GitHub artifact provenance before extraction. The higher-assurance pinned procedure avoids executing mutable branch bootstrap content. Details are in [`installation-security.md`](installation-security.md).

GitHub attestations add repository/workflow provenance evidence, but the checksum, SBOM, and GitHub attestations are **not represented as Authenticode publisher signing**. For v0.1.0, GitHub artifact attestations are the selected independent release-authenticity mechanism; Authenticode may be added later for environments that require it.

Version `v0.1.0` is the initial stable release and uses the documented ZIP/checksum/SBOM/attestation evidence contract. See [`release-sbom.md`](release-sbom.md), [`publishing.md`](../release/publishing.md), and [`versioning.md`](../release/versioning.md).

## Vulnerability reporting, maintenance, and support

- Vulnerabilities must be reported privately according to [`SECURITY.md`](../../SECURITY.md); private vulnerability reporting was verified enabled on 2026-08-16.
- The latest published stable module version is the supported line unless an explicit exception is announced; unreleased `main` content is not a separately supported production line.
- Supported module versions, PowerShell/platform/prerequisite compatibility, deprecation, breaking-change notice, and end-of-support rules are authoritative in [`support-policy.md`](../user/support-policy.md).
- The GitHub.com-only host boundary is described in [`host-support.md`](../user/host-support.md).
- Dependency freshness/advisory monitoring is described in [`dependency-monitoring.md`](dependency-monitoring.md).
- Serious post-release problems use the implemented exceptional process in [`incident-response.md`](../release/incident-response.md).

A governance approval should distinguish the normal support lifecycle and vulnerability-reporting path from the exceptional post-release incident/emergency-maintenance process.

## Known limitations and residual risk

The concise approval-relevant limitations are:

- v0.1.0 is GitHub.com-only; GitHub Enterprise Server and other hosts are outside current scope;
- external prerequisite executables and GitHub.com availability/authorization/API behavior remain trust dependencies outside the module's direct enforcement;
- secret-bearing repository configuration such as GitHub secrets, webhook secrets, private deploy-key material, and GitHub App credentials is unsupported and intentionally excluded;
- no automatic destructive rollback/delete is attempted after partial mutation; preservation and explicit recovery evidence take priority;
- resource exhaustion, timeout/cancellation, retry/throttling, interruption, and scale behavior retain documented limits and accepted boundaries under the non-functional model;
- Authenticode publisher signing is not implemented; v0.1.0 instead relies on GitHub artifact attestations plus checksum verification for release authenticity/integrity;
- quality/static-analysis/security controls do not prove absence of defects or vulnerabilities.

See [`non-functional-requirements.md`](../product/non-functional-requirements.md), [`security-architecture.md`](security-architecture.md), [`repository-security-baseline.md`](repository-security-baseline.md), [`support-policy.md`](../user/support-policy.md), and [`quality-strategy.md`](../engineering/quality-strategy.md) for the detailed authorities.

## Reviewer evidence map

| Reviewer question | Start here / authority |
| --- | --- |
| What does the product do, and what is in/out of scope? | [`product-contract.md`](../product/product-contract.md) |
| Which user journeys/capabilities are expected? | [`product-model.md`](../product/product-model.md) |
| What versions, platforms, prerequisites, and deprecation rules are supported? | [`support-policy.md`](../user/support-policy.md) |
| What GitHub hosts are supported? | [`host-support.md`](../user/host-support.md), [`product-contract.md`](../product/product-contract.md) |
| What license applies? | [`LICENSE`](../../LICENSE) |
| What software is shipped versus prerequisite/development-only? | [`release-sbom.md`](release-sbom.md), [`security-architecture.md`](security-architecture.md) |
| What permissions and credentials does runtime use? | [`security-architecture.md`](security-architecture.md), [`product-contract.md`](../product/product-contract.md) |
| What network/services are involved? | [`security-architecture.md`](security-architecture.md), [`installation-security.md`](installation-security.md) |
| What local/sensitive data can exist? | [`security-architecture.md`](security-architecture.md), [`troubleshooting-recovery.md`](../user/troubleshooting-recovery.md) |
| What security controls and residual risks exist? | [`security-architecture.md`](security-architecture.md), [`repository-security-baseline.md`](repository-security-baseline.md) |
| How are dependencies monitored? | [`dependency-monitoring.md`](dependency-monitoring.md) |
| What is the test/quality/live-evidence model? | [`quality-strategy.md`](../engineering/quality-strategy.md) |
| What are the non-functional limits/resilience gaps? | [`non-functional-requirements.md`](../product/non-functional-requirements.md) |
| How is a release artifact identified and verified? | [`release-sbom.md`](release-sbom.md), [`installation-security.md`](installation-security.md) |
| How are vulnerabilities reported? | [`SECURITY.md`](../../SECURITY.md) |
| How is the module released/published? | [`publishing.md`](../release/publishing.md), [`versioning.md`](../release/versioning.md) |
| What should an organization review before approval? | This page's review-status/limitations sections plus the exact release evidence and applicable organizational policy |

## Approval record guidance

An organizational approval record should identify the **exact version/tag/artifact** reviewed, review date, organizational owner/approver, accepted limitations, and conditions on use. It should link immutable or release-specific evidence where available rather than treating this mutable `main`-branch page as the approval artifact itself.

This page intentionally does not contain an approval checkbox or assertion that the software is approved for a particular organization. The decision belongs to the adopting organization; project release qualification is governed separately by the release-readiness process.