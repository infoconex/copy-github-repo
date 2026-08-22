# GitHub repository security baseline

This document records the repository-level GitHub security baseline for `infoconex/copy-github-repo`. It distinguishes settings verified from the live repository from settings that the connected GitHub integration cannot read or administer.

A feature is never described as enabled merely because GitHub may enable it by default for some public repositories. Owner-side verification performed in the GitHub web UI is recorded explicitly as such and is not represented as API evidence.

## Baseline status

| Control | Required state | Evidence | Status |
| --- | --- | --- | --- |
| Private vulnerability reporting | Enabled | GitHub API returned `{"enabled":true}` on 2026-08-16; repository owner also confirmed the live security settings in the GitHub web UI on 2026-08-19 | Verified enabled |
| GitHub Actions CodeQL analysis | Enabled and running | Initial CodeQL workflow execution completed successfully | Verified enabled for GitHub Actions workflow analysis |
| PowerShell code security analysis | Dedicated repository-owned gate | `Analyze Code Security` uses a security-only PSScriptAnalyzer profile plus targeted security behavior tests | Implemented in repository configuration; workflow evidence is release-specific |
| Repository ruleset for `main` | Active | Repository owner created and configured an active branch ruleset named `main` in the GitHub web UI on 2026-08-19, including the required `main` protections | Owner verified |
| Dependabot configuration for GitHub Actions | Weekly update monitoring | `.github/dependabot.yml` schedules weekly GitHub Actions updates | Implemented in repository configuration |
| Dependabot alerts | Enabled | Repository owner confirmed the live Advanced Security settings in the GitHub web UI on 2026-08-19 | Owner verified enabled |
| Dependabot security updates | Enabled | Repository owner confirmed the live Advanced Security settings in the GitHub web UI on 2026-08-19 | Owner verified enabled |
| Secret scanning | Enabled where GitHub exposes the setting | Repository owner confirmed the live Advanced Security settings in the GitHub web UI on 2026-08-19 | Owner verified enabled/available configuration |
| Push protection for secrets | Enabled where available | Repository owner confirmed the live Advanced Security settings in the GitHub web UI on 2026-08-19 | Owner verified enabled/available configuration |
| Code scanning alert state | Reviewable with no unaccepted blocker for release | GitHub Actions CodeQL analysis uploads successfully; connected integration receives HTTP 403 when listing code-scanning alerts | Live alert review required for the exact release candidate |
| Default GitHub Actions workflow permissions | Read-only by default unless a workflow declares narrower/required permissions | Repository owner confirmed the repository Actions workflow-permission setting in the GitHub web UI on 2026-08-19 | Owner verified |
| Classic `main` branch protection | Superseded by or compatible with the required active ruleset | Active `main` ruleset is the repository's intended protection mechanism | Satisfied by ruleset; classic protection is not independently required |

## Required `main` ruleset

Before the repository is treated as release-ready, maintain an **active branch ruleset targeting the default branch (`main`)**. The intended minimum is:

- block branch deletion;
- block force pushes;
- require changes to arrive through a pull request for normal contributor changes;
- require required status checks before merge;
- include **Validate Project Quality** as a required check once GitHub offers the exact observed check context for selection;
- include **Analyze Code Security** as a required check for executable/security-relevant changes when the exact observed check context is available;
- include CodeQL/code-scanning requirements when the repository plan and GitHub UI expose an appropriate rule without creating a circular or unusable workflow;
- do not grant broad bypass access merely to make the rule convenient.

Workflow and job names are part of the observable status-check surface. When workflow/job names change, verify any configured required-check context against the newly observed check names before treating the ruleset as satisfied.

The live repository uses an active ruleset named `main`. The ruleset name itself is not part of the security contract; the target, enforcement state, required checks, and protection behavior are what must be verified.

This project may require a controlled administrative path during the same-name Snapshot replacement. Any temporary bypass must be explicit and removed or narrowed before the final release-readiness decision.

### Configure or reconfigure the ruleset

1. Open the repository on GitHub.
2. Select **Settings**.
3. Under **Code and automation**, select **Rules** → **Rulesets**.
4. Create or edit the branch ruleset used to protect `main`.
5. Set enforcement to **Active**.
6. Target the default branch.
7. Enable the minimum protections listed above.
8. Save the ruleset.
9. Re-run the verification steps in this document and record the result in the release evidence.

## Advanced Security settings to verify

Open **Settings** → **Security** → **Advanced Security** and verify these controls directly:

- **Dependabot alerts:** enabled.
- **Dependabot security updates:** enabled.
- **Secret scanning:** enabled when GitHub exposes the setting for the repository/account.
- **Push protection:** enabled when available.
- **Private vulnerability reporting:** enabled.

The repository owner verified these live settings in the GitHub web UI on 2026-08-19. That verification establishes the current historical-repository baseline but does not replace the required post-Snapshot verification of the clean replacement repository.

Do not infer the state of these toggles from repository visibility or GitHub defaults. Capture the actual setting state during release readiness.

## Code scanning review

The repository-owned `.github/workflows/analyze-github-actions-security.yml` analyzes GitHub Actions workflow code with CodeQL. Successful workflow execution proves the configured analysis ran and uploaded its result; it does not by itself prove there are zero open code-scanning alerts.

Before stable release:

1. Open **Security** → **Code scanning**.
2. Review open alerts for the repository.
3. Resolve any release-blocking finding or explicitly record a risk acceptance through the release-readiness process.
4. Preserve the relevant workflow run and alert disposition as release evidence.

PowerShell source is not represented as CodeQL-covered. `.github/workflows/analyze-code-security.yml` provides the separate PowerShell-aware security gate using `PSScriptAnalyzerSecuritySettings.psd1`, the repository-owned custom security rule, selected built-in PSScriptAnalyzer security rules, and targeted Pester safety/security behavior tests. This separation avoids implying that CodeQL scans PowerShell while still giving PowerShell security findings a dedicated CI surface.

## GitHub Actions permissions

Open **Settings** → **Actions** → **General** → **Workflow permissions** and verify the repository default is **Read repository contents and packages permissions** rather than a broad read/write default. Do not enable Actions to create or approve pull requests unless a documented workflow requirement justifies it.

The repository owner verified the live workflow-permission setting in the GitHub web UI on 2026-08-19.

Individual workflows must continue declaring explicit permissions appropriate to their jobs. Repository defaults are a backstop, not a substitute for workflow-level least privilege.

## Snapshot replacement responsibility and qualification

A same-name Snapshot replacement creates a new GitHub repository object. Repository-hosted files move with the approved Snapshot tree, but GitHub platform settings are not part of Git commit history and must not be assumed to survive repository replacement.

Treat the controls in this document as follows:

| Control | Source-controlled / product-restored behavior | Owner-side post-Snapshot requirement |
| --- | --- | --- |
| `.github/dependabot.yml` update schedule | Included in the Snapshot tree and therefore restored with approved repository content | Verify Dependabot is operating after replacement |
| CodeQL and PowerShell security workflows | Included in the Snapshot tree | Verify workflows are enabled and complete successfully on the replacement repository |
| General repository settings and protection restoration supported by the product | Governed by the product's documented `CAP-SET` / `CAP-PROT` behavior and exact migration result | Verify the resulting live settings rather than assuming restoration succeeded |
| `main` ruleset / branch protection required by this baseline | Do not assume preservation merely because product protection restoration exists; the baseline requires the exact live rule behavior described above | Reapply or correct the rule after replacement and verify deletion, force-push, PR, and required-check behavior |
| Dependabot alerts | Not represented by Git content | Verify enabled in the replacement repository |
| Dependabot security updates | Not represented by Git content | Verify enabled in the replacement repository |
| Secret scanning | Not represented by Git content | Verify enabled where the account/repository exposes it |
| Push protection for secrets | Not represented by Git content | Verify enabled where available |
| Private vulnerability reporting | Not represented by Git content | Verify enabled in the replacement repository |
| Default GitHub Actions workflow permissions | Not represented by Git content | Set/verify the least-privilege repository default |
| Code-scanning alert disposition | Alert state is GitHub platform state, not Snapshot content | Review the replacement repository's code-scanning results and disposition any blocker |

The product's supported settings/protection restoration is useful migration behavior, but it is not evidence that this security baseline is satisfied. Security qualification always verifies the resulting live repository.

### Required post-Snapshot security qualification

Before the clean replacement repository can become the first stable release candidate:

1. Confirm the replacement repository is the intended same-name repository and `main` is the default branch.
2. Confirm the approved Snapshot tree contains `.github/dependabot.yml` and all required security/quality workflows.
3. Reapply or verify the active `main` protection ruleset and its exact required-check contexts.
4. Verify Dependabot alerts and Dependabot security updates.
5. Verify secret scanning and push protection where GitHub exposes those controls.
6. Verify private vulnerability reporting.
7. Verify the default GitHub Actions workflow permission is least privilege and that workflows use explicit job/workflow permissions where required.
8. Run the required quality/security workflows from the replacement repository and confirm successful evidence is bound to the clean replacement commit.
9. Review code-scanning alerts and disposition any release blocker.
10. Record any unavailable platform feature as a release-specific limitation with the platform/account constraint and compensating control; do not silently mark it satisfied.

A pre-Snapshot verification result does not carry forward as evidence for the replacement repository. The clean repository must be qualified independently before `v0.1.0` is tagged or published.

## Evidence classification

Use these terms consistently:

- **Verified enabled** — live setting or behavior was read directly from GitHub through an independently queryable interface.
- **Owner verified** / **Owner verified enabled** — the repository owner inspected the live GitHub web UI and confirmed the setting or behavior; the connected integration could not independently read that setting.
- **Implemented in repository configuration** — repository files enforce or configure the behavior, but a platform-side setting may still be relevant.
- **Live verification required** — the current evidence does not prove the setting or release-specific state.
- **Not satisfied** — live evidence proves the intended baseline is currently missing.

A permissions limitation in the verification integration is not evidence that a control is either enabled or disabled. Owner-side verification must be labeled distinctly from API evidence, and the replacement repository must be verified independently after the Snapshot migration.
