---
title: "CopyGitHubRepo Post-Release Incident Response and Emergency Maintenance"
description: "Use the CopyGitHubRepo incident-response process for critical defects, vulnerabilities, credential or workflow compromise, artifact problems, distribution mismatches, emergency patches, communication, and follow-up."
---

# Post-release incident response and emergency maintenance

This document defines the lightweight exceptional process for serious problems discovered **after** a CopyGitHubRepo version or release channel has been published. It does not replace normal user migration recovery, normal issue handling, or the normal release process.

Use this process when a released version, artifact, credential, workflow, distribution path, dependency, or safety/security statement may be materially unsafe, defective, compromised, inconsistent, or misleading.

The process is intentionally proportional to a focused open-source PowerShell module. Preserve enough evidence to make defensible decisions, communicate clearly, and prevent recurrence without creating enterprise incident-management bureaucracy the project cannot sustain.

## Authority boundaries

- [`SECURITY.md`](../../SECURITY.md) remains the private vulnerability-reporting front door.
- [`governance.md`](../engineering/governance.md) owns project decision authority.
- [`support-policy.md`](../user/support-policy.md) owns supported-version/deprecation expectations.
- [`release-readiness.md`](release-readiness.md) owns normal exact-candidate go/no-go decisions.
- [`release-runbook.md`](release-runbook.md) owns normal release/deployment execution and partial-publication recovery boundaries.
- [`security-architecture.md`](../security/security-architecture.md) owns threat/control evidence.
- [`vulnerability-applicability.md`](../security/vulnerability-applicability.md) owns VEX applicability semantics if a VEX statement is warranted.
- This document owns exceptional post-release incident triage, containment, remediation, emergency patching, communication, and follow-up.

A successful CI workflow or maintainer self-review is not independent incident review evidence.

## What counts as an incident

Use this process for at least these classes:

- a critical functional defect in a released version that can corrupt, lose, mispublish, or materially misrepresent repository state;
- a security vulnerability affecting a supported release;
- suspected or confirmed compromise of a maintainer, GitHub, PowerShell Gallery, or other publishing credential;
- suspected compromise or unauthorized modification of the release workflow/environment;
- suspected tampering, mismatch, or provenance failure for a published artifact;
- a materially relevant runtime/dependency/supply-chain vulnerability;
- incorrect or incomplete SBOM, checksum, provenance, or attestation evidence;
- an incorrect VEX applicability statement if VEX is published in the future;
- disagreement between the GitHub Release and PowerShell Gallery version/package state;
- a broken or unsafe installer/update/uninstall path;
- an upstream GitHub, Git, GitHub CLI, or Git LFS behavior change that makes a supported release unsafe or nonfunctional;
- documentation or security guidance that could cause unsafe operation.

Ordinary low-impact defects with no urgent safety/security/distribution consequence may remain in normal issue handling.

## Severity and urgency model

Use the smallest category that accurately describes the evidence.

| Severity | Typical meaning | Default response |
| --- | --- | --- |
| **S0 — Routine** | Minor defect/documentation issue with no material safety, security, integrity, or supported-use impact | Normal public issue/maintenance process |
| **S1 — Significant** | Important supported behavior is broken or misleading, but no evidence of compromise or immediate destructive/security risk | Prioritized public issue; patch in normal/accelerated release cadence as appropriate |
| **S2 — Serious** | Material data/repository safety risk, high-impact distribution defect, significant vulnerability, or integrity discrepancy | Incident process; consider stop-use guidance, accelerated patch, channel warning, and private handling if security-sensitive |
| **S3 — Critical** | Confirmed/suspected compromise, actively exploitable critical vulnerability, tampered artifact, exposed publishing credential, or defect likely to cause severe destructive/security harm | Immediate containment; private/security handling; rotate credentials where applicable; stop-use/stop-publish guidance; emergency release or channel action as evidence supports |

Severity may increase or decrease as evidence changes. When compromise is plausible but unconfirmed, begin with containment appropriate to the plausible impact rather than waiting for certainty.

## Initial triage questions

Record the answers before making irreversible changes:

1. Which exact version/tag/commit/artifact/channel is affected?
2. Is the problem reproducible or independently observable without increasing harm?
3. Is there a credible security/credential/supply-chain dimension requiring private handling?
4. Can users avoid harm by avoiding one capability/mode, or should they stop using the release entirely?
5. Does PowerShell Gallery contain the affected immutable version?
6. Does a GitHub Release/tag exist, and do its assets/checksum/SBOM/attestations agree?
7. Are publishing credentials or workflow/environment integrity in question?
8. Does the supported line need an urgent patch or support/deprecation statement?
9. Is public communication safe now, or would disclosure expose an unresolved vulnerability before containment?
10. What evidence must be preserved before logs/credentials/configuration are changed?

## Response lifecycle

Use this lifecycle:

`Detected -> Triaged -> Contained -> Scope Assessed -> Remediation Planned -> Fixed -> Verified -> Communicated -> Follow-up Complete`

### Detected

Capture the initial report, observed symptoms, reporter/contact path, affected version/channel if known, and time discovered. Do not copy secrets into a public issue.

### Triaged

Assign severity, determine whether handling must remain private, identify the current decision authority, and decide whether normal issue handling is still sufficient.

Security-sensitive reports remain on the private path described by `SECURITY.md` until coordinated disclosure is appropriate.

### Contained

Take the least-destructive action that reduces current risk. Depending on evidence this can include:

- stop or pause further stable publication;
- rotate/revoke a suspected credential;
- disable or restrict a compromised workflow/environment if platform controls permit;
- publish clear stop-use or affected-capability guidance;
- mark a release/channel as deprecated/unrecommended where the platform actually supports that state;
- update installation/security guidance to prevent new unsafe use;
- preserve existing immutable artifacts rather than silently replacing them.

Containment does **not** mean deleting evidence or moving a published tag to hide a bad release.

### Scope Assessed

Determine whether the issue affects:

- one version or multiple supported versions;
- one mode/capability or the entire product;
- shipped code versus an external prerequisite/service;
- GitHub Release, PowerShell Gallery, installer/bootstrap paths, Pages documentation, or multiple channels;
- artifact content versus metadata/evidence only;
- release infrastructure/credentials versus the product itself.

Record what is known, unknown, and under investigation.

### Remediation Planned

Choose a response proportional to scope:

- documentation-only correction;
- support/deprecation warning;
- credential/workflow/environment repair;
- new patch release;
- new release evidence/statement when the shipped artifact is correct but metadata/evidence was incomplete;
- VEX update when the issue is vulnerability applicability and VEX is supported/triggered;
- no product release when the actual fix belongs to an external prerequisite and safe guidance is sufficient.

Never choose overwrite/republication of an immutable Gallery version as the repair strategy.

### Fixed

Implement the narrowest safe correction. Emergency fixes should avoid unrelated refactoring or feature work unless needed to restore safety/correctness.

### Verified

Verify both the technical fix and the affected distribution/evidence path. A fix is not complete merely because source tests pass.

### Communicated

Provide the minimum accurate public/private communication required by impact. State affected versions/capabilities, available remediation/workaround, support recommendation, and evidence status without overclaiming certainty.

### Follow-up Complete

Record concise lessons learned and convert systemic improvements into tests, issues, documentation, ADRs, or workflow controls. Avoid a heavyweight postmortem requirement for routine incidents.

## Evidence preservation

Preserve where relevant:

- exact affected version/tag and 40-character commit SHA;
- GitHub Release URL/identifier and release workflow run ID;
- Gallery exact version and observed package identity;
- ZIP/checksum/SBOM/attestation identities;
- installer/bootstrap version/path involved;
- reporter symptoms and safe reproduction evidence;
- relevant logs with secrets/tokens/private repository content removed;
- credential/workflow/environment changes and timestamps without secret values;
- incident timeline and key decisions;
- remediation commit/release identity;
- verification evidence;
- communication/advisory references; and
- follow-up corrective/preventive issues.

Do not preserve secrets merely for completeness. Record that a secret was rotated/revoked without copying the value.

## Credential or workflow compromise

For suspected publishing or maintainer credential compromise:

1. Treat as at least **S2** and usually **S3** when the credential could alter source, workflows, releases, or PowerShell Gallery publication.
2. Preserve relevant access/audit evidence available through the platform.
3. Revoke/rotate the credential as soon as evidence preservation reasonably permits.
4. Review source, tags, release assets, workflow changes, environment configuration, and Gallery versions created during the suspected window.
5. Do not trust artifacts solely because their filenames/versions look expected; verify checksum/provenance/source identity.
6. Restore least-privilege publishing access.
7. Require a fresh exact-candidate readiness and release run for any corrective release.
8. Communicate the affected window/releases when evidence supports a meaningful user action.

If compromise cannot yet be confirmed, communicate `under investigation` rather than asserting either safety or compromise without evidence.

## Security vulnerability handling

For a private vulnerability report:

- use `SECURITY.md` and GitHub private vulnerability reporting/Security Advisory capabilities where available;
- determine affected supported versions/capabilities and whether external prerequisites are involved;
- assess exploitability/applicability using product-specific evidence;
- coordinate fix, verification, release timing, and disclosure;
- use [`vulnerability-applicability.md`](../security/vulnerability-applicability.md) if a VEX statement becomes justified;
- publish a GitHub Security Advisory/CVE only when appropriate to the vulnerability and project role; do not invent a CVE or certification claim;
- update support guidance when users must stop using or upgrade from an affected version.

A vulnerability may require private coordination before public issue creation. Do not disclose exploit-enabling details prematurely merely to make the incident record public.

## Distribution mismatch and partial incidents

### Gallery package is bad; GitHub Release artifact is correct

- Mark the affected Gallery version as unsafe/unrecommended in project communication.
- Do not overwrite the Gallery version.
- Determine whether the defect can occur only through Gallery installation or also after GitHub ZIP installation.
- Publish a corrected new semantic version if shipped code/package correction is required.
- Keep the prior GitHub Release/artifact available as evidence unless platform/security policy requires otherwise; do not move its tag to the fix.

### GitHub Release artifact/evidence is bad; Gallery package is correct

- Stop recommending the affected GitHub Release/install path.
- Preserve the stable tag/release evidence; do not silently replace assets under the same version.
- Determine whether a new version is required for consumer clarity/integrity. For an artifact-content defect, use a new version.
- If only ancillary evidence/metadata is incomplete, document the evidence correction path explicitly and do not pretend the original evidence existed at publication time.

### Installer points to an unsafe/incorrect version

- Treat installer/bootstrap guidance as a distribution incident even when published packages themselves are valid.
- Correct mutable installer/documentation routing promptly.
- Verify the corrected path against a clean environment.
- If users may already have installed an unsafe release, communicate affected versions and upgrade/remediation guidance.

### One capability/mode is affected

- State the exact affected capability and safe unaffected use only when evidence supports the distinction.
- Do not issue a broad `safe` statement if unassessed shared code/control paths could still be affected.
- Decide whether the supported release can remain usable with a temporary limitation or requires an emergency patch.

### External prerequisite is affected

- Determine whether the shipped module is vulnerable/defective versus merely dependent on an unsafe prerequisite version/service behavior.
- Update support/prerequisite guidance and safe minimum/maximum capability requirements where defensible.
- Release module changes only if product code/configuration must change.
- Do not claim to remediate an upstream vulnerability merely by documenting it.

## Immutable release limitations

PowerShell Gallery package versions and stable release identities are treated as immutable project evidence. The project does not claim it can reliably revoke every already-downloaded artifact from user systems.

Therefore:

- never overwrite or republish the same Gallery version;
- never move a published stable tag to a different commit;
- never silently replace stable release assets to make old evidence appear correct;
- use a new semantic version for corrected shipped code/package content;
- use public warnings/deprecation/advisories where supported to steer users away from an unsafe version;
- remember that copies already downloaded by users may persist even after a platform-side visibility/deprecation action.

## Emergency patch / hotfix path

An emergency patch is still a release. Urgency changes prioritization, not identity/integrity requirements.

1. **Identify affected supported release(s).** Use [`support-policy.md`](../user/support-policy.md); do not create unannounced long-lived support branches merely because an old version is affected.
2. **Reproduce/confirm safely.** Preserve evidence and avoid destructive reproduction against user repositories.
3. **Create the smallest safe fix.** Limit unrelated changes.
4. **Increment the version.** Use a new semantic version; never republish the affected version. A backward-compatible emergency fix normally increments PATCH, subject to [`versioning.md`](versioning.md) semantics.
5. **Create an exact release candidate.** Record the commit SHA and change scope.
6. **Run release readiness.** Use [`release-readiness.md`](release-readiness.md) and record a fresh `GO`/`NO-GO`/`PENDING` decision for the exact hotfix candidate.
7. **Run the Quality Gate.** Windows, Ubuntu, and macOS remain required; urgency does not justify silently skipping the repository quality baseline.
8. **Run applicable live E2E evidence.** High-risk behavior affected by the incident should be live-validated when the quality/readiness model requires it.
9. **Generate normal integrity evidence.** ZIP/checksum/SBOM/GitHub attestations and any implemented independent signing remain required according to release policy. If an exceptional control cannot be satisfied, it requires an explicit readiness exception/residual-risk decision rather than silent omission.
10. **Publish through the normal release workflow/runbook.** Prefer `.github/workflows/publish-release.yml`; preserve immutable version/tag rules.
11. **Post-publication verify.** Verify GitHub Release, Gallery, clean install, exported commands, integrity evidence, and relevant incident-specific behavior.
12. **Communicate.** State the affected version(s), fixed version, urgency, workaround/upgrade guidance, and security advisory information when applicable.

Do not bypass the exact-candidate Quality Gate/readiness model by making an emergency edit directly to an already-published asset.

## Communication guidance

Communication depends on impact and disclosure safety, but should answer:

- what exact version(s)/channel/capability are affected;
- whether users should stop using the version, avoid one capability, or upgrade;
- whether a fixed version exists;
- whether a workaround exists and its limits;
- whether the issue is security-sensitive and where the advisory lives;
- whether investigation is still ongoing;
- what evidence supports the current recommendation.

Avoid absolute statements such as `no users are affected`, `the artifact was never downloaded`, or `the vulnerability cannot be exploited` unless those claims can actually be established.

## Support and version implications

The latest published stable release is the normal supported line according to [`support-policy.md`](../user/support-policy.md). An incident may require:

- rapidly publishing a replacement patch version;
- explicitly marking an affected version unsupported/unrecommended;
- documenting a temporary capability limitation;
- raising a prerequisite minimum/compatibility boundary when an upstream dependency becomes unsafe;
- accelerated deprecation/removal when required by security, data-loss prevention, platform change, or correctness.

Record the reason and migration/upgrade guidance when normal compatibility/deprecation expectations must be accelerated.

## Lessons learned and prevention

For an S2/S3 incident, or any event exposing a systemic release/safety gap, capture a concise follow-up containing:

- triggering condition;
- which control/evidence detected or failed to detect it;
- why the impact escaped existing prevention/verification;
- which automated test/workflow/documentation/architecture change prevents recurrence;
- follow-up issue/ADR/test references.

The goal is corrective action, not a ceremonial postmortem document.

## Related authorities

- Vulnerability reporting: [`SECURITY.md`](../../SECURITY.md)
- Governance/decision authority: [`governance.md`](../engineering/governance.md)
- Security architecture: [`security-architecture.md`](../security/security-architecture.md)
- Vulnerability applicability/VEX: [`vulnerability-applicability.md`](../security/vulnerability-applicability.md)
- Support lifecycle: [`support-policy.md`](../user/support-policy.md)
- Release readiness: [`release-readiness.md`](release-readiness.md)
- Normal release/deployment: [`release-runbook.md`](release-runbook.md)
- Release provenance/SBOM: [`release-sbom.md`](../security/release-sbom.md)
- Installation trust: [`installation-security.md`](../security/installation-security.md)
- Publishing: [`publishing.md`](publishing.md)
