---
title: "CopyGitHubRepo Dependency and Supply-Chain Monitoring"
description: "Understand how CopyGitHubRepo monitors PowerShell development dependencies and GitHub Actions for stable updates and published security advisories without automatically adopting changes."
---

# Dependency and supply-chain monitoring

This document defines the ongoing monitoring policy for third-party development and CI dependencies used by Copy GitHub Repository. It complements the exact dependency pins in `build/DevelopmentDependencies.psd1` and the broader threat/control model in [`security-architecture.md`](security-architecture.md).

The installed module currently declares no third-party PowerShell runtime modules. Monitoring therefore focuses on development modules and GitHub Actions without adding a runtime dependency merely to monitor the supply chain.

## Monitoring model

Two mechanisms are intentionally used because GitHub Dependabot supports GitHub Actions but does not support PowerShell Gallery as a package ecosystem.

| Dependency class | Mechanism | Cadence | Result |
| --- | --- | --- | --- |
| GitHub Actions | `.github/dependabot.yml` | Weekly | Dependabot proposes reviewed pull requests for newer action revisions. |
| Pester and PSScriptAnalyzer | `.github/workflows/monitor-dependencies.yml` | Weekly and manual `workflow_dispatch` | The workflow compares PowerShell Gallery's current stable release with the last reviewed stable release and checks the upstream GitHub repository for published security advisories. |

Monitoring is advisory/review automation, not automatic adoption. Repository workflows must remain pinned to immutable action commit SHAs, and PowerShell development modules must remain exact-version pinned.

## Reviewed-version baseline

`build/DevelopmentDependencyMonitoring.psd1` records, for each exact development dependency:

- `ReviewedLatestStableVersion` — the newest stable PowerShell Gallery release that maintainers have already evaluated;
- `UpstreamRepository` — the GitHub repository whose published repository security advisories are checked;
- `ReviewedAdvisoryIds` — published GHSA identifiers already reviewed and explicitly dispositioned.

The reviewed-version baseline is deliberately separate from the installed pin. This lets the project intentionally retain an older compatible version without creating a permanently failing monitor. A later stable release beyond the reviewed baseline still fails the scheduled monitor and requires a new review.

The current reviewed stable baseline and exact installed pins are **Pester 6.1.0** and **PSScriptAnalyzer 1.25.0**. The project completed the Pester 6 migration and now validates the repository test suite on Pester 6.1.0. `build/DevelopmentDependencies.psd1` and `build/DevelopmentDependencyMonitoring.psd1` are the machine-readable sources of truth for the installed and reviewed versions.

## Freshness findings

A freshness finding means **a newer stable version exists beyond the last reviewed stable baseline**. It is not a vulnerability finding.

When the monitor reports `FRESHNESS:`:

1. review the upstream release notes and compatibility requirements;
2. evaluate the newer release against the project's PowerShell 7.4+ and cross-platform support contract;
3. update the exact pin when adoption is appropriate and run **Validate Project Quality**;
4. if the existing pin remains intentional, update `ReviewedLatestStableVersion` only after recording the durable rationale in the relevant change record;
5. never replace exact pins with floating or minimum-version installation behavior merely to silence monitoring.

Major-version adoption is a compatibility decision, not an automatic response to freshness.

## Security-advisory findings

The PowerShell monitor separately queries each dependency's upstream GitHub repository for **published repository security advisories**. A returned GHSA identifier that is not already listed in `ReviewedAdvisoryIds` produces a `SECURITY ADVISORY:` finding and fails the monitor for maintainer review.

An advisory finding does not by itself prove that the repository's pinned version is affected. Maintainers must review the advisory's affected versions, attack preconditions, development/CI exposure, and available remediation. If affected, update or otherwise mitigate the dependency and validate the resulting repository state. If not applicable, record the evidence/rationale before adding the GHSA identifier to `ReviewedAdvisoryIds`.

The upstream repository advisory API is a useful detection source, not a guarantee that every vulnerability is known, published, or represented there. A successful monitor therefore means no **new finding from the configured sources** was detected; it does not mean the dependencies are vulnerability-free.

## GitHub Actions update policy

Dependabot is configured for the `github-actions` ecosystem on a weekly cadence. Dependabot changes are proposals and receive the same review as maintainer-authored workflow changes.

Before accepting an action update:

- confirm the action remains pinned to a full immutable commit SHA;
- review the upstream release/change information and repository ownership;
- inspect permission and behavioral changes;
- require the repository's workflow/contract tests and applicable **Validate Project Quality** evidence;
- do not enable unattended auto-merge merely because the update was opened by Dependabot.

## Workflow security posture

`.github/workflows/monitor-dependencies.yml` uses only `contents: read`, checks out the exact triggering commit with persisted credentials disabled, and uses the ephemeral repository `GITHUB_TOKEN` only to query public upstream repository advisory metadata. It does not install or change project dependencies.

The monitor fails when it detects a new stable release beyond the reviewed baseline or an unreviewed published upstream advisory. This makes scheduled workflow failure an explicit review signal while keeping ordinary freshness and security-advisory messages distinct.

## Validation and maintenance

The monitoring contract is enforced by `tests/contract/DevelopmentDependencies.Tests.ps1`, including:

- one monitoring-policy entry for every pinned PowerShell development dependency;
- weekly GitHub Actions Dependabot coverage;
- scheduled/manual dependency-monitor execution;
- read-only workflow permissions and immutable checkout pinning;
- PowerShell Gallery freshness lookup;
- upstream security-advisory lookup;
- separate `FRESHNESS:` and `SECURITY ADVISORY:` findings;
- no dependency installation in the monitoring workflow.

Run the normal repository preflight after changing dependency pins, monitoring policy, Dependabot configuration, or monitoring workflow behavior:

```powershell
./build/Test-Project.ps1
```

The scheduled dependency monitor can also be run manually from the **Monitor Dependencies** workflow in GitHub Actions when an immediate upstream re-check is needed.
