---
title: "CopyGitHubRepo Release and Deployment Runbook"
description: "Follow the CopyGitHubRepo maintainer runbook for integrating, qualifying, publishing, and verifying stable releases from the exact approved main commit."
---

# Release and deployment runbook

This runbook is the ordered maintainer procedure for releasing Copy GitHub Repository. It owns **how** an already-approved release candidate is tagged, packaged, distributed, verified, and recovered. It does not decide **whether** a candidate is ready; that decision is authoritative in [`release-readiness.md`](release-readiness.md).

The supported release automation is `.github/workflows/publish-release.yml` (**Publish Release**). Stable publication is manual-dispatch-only from `main`. Use that workflow instead of reconstructing publication manually whenever GitHub Actions is available. [`publishing.md`](publishing.md), [`versioning.md`](versioning.md), [`release-sbom.md`](../security/release-sbom.md), and [`installation-security.md`](../security/installation-security.md) remain authoritative for their detailed contracts.

## Three distinct deployment concerns

Do not treat these as one atomic deployment:

| Concern | Primary mechanism | Mutation/publication boundary | Independent failure/recovery? |
| --- | --- | --- | --- |
| **Product release** | Qualified `main` commit plus stable tag | Creating or reusing the approved stable tag | Yes |
| **Package distribution** | PowerShell Gallery and GitHub Release assets | `Publish-PSResource`, then `gh release create` | Yes; the two channels are not atomic |
| **Documentation deployment** | `.github/workflows/deploy-documentation-site.yml` (**Deploy Documentation Site**) | GitHub Pages deployment | Yes; a Pages failure does not roll back an already-published module release |

A release status must state which concerns completed. Never call a partially published release fully complete merely because one channel succeeded.

## Canonical lifecycle

Use these lifecycle states for a normal stable release:

`Planned -> Integrated to main -> Release Candidate -> Readiness Reviewed -> Approved -> Release Workflow Started -> Validated -> Artifacts Built -> Integrity Evidence Generated -> Attested -> Tag Confirmed/Created -> Published to PowerShell Gallery -> Published to GitHub Release -> Distribution Verified -> Documentation Verified -> Complete`

A failure stops progression at the current state. Record the last irreversible mutation before deciding whether retry is safe.

### State meanings

- **Planned** — version and scope work is still mutable on a release branch.
- **Integrated to main** — the release branch has passed its integration PR and the resulting `main` commit is now the only candidate eligible for final qualification.
- **Release Candidate** — one exact current `main` commit is proposed for release-specific evidence.
- **Readiness Reviewed** — the exact candidate has been evaluated under `release-readiness.md`.
- **Approved** — the current governance authority recorded `GO` for that exact candidate; approval does not carry to a later commit.
- **Release Workflow Started** — **Publish Release** is operating on that exact qualified `main` SHA and requested tag.
- **Validated** — release metadata and the reusable Windows, Ubuntu, and macOS Validate Project Quality jobs passed for the workflow SHA.
- **Artifacts Built** — deterministic ZIP and validated Gallery package were produced from the same SHA.
- **Integrity Evidence Generated** — checksum and SPDX SBOM exist for the exact release artifact.
- **Attested** — required GitHub provenance and SBOM attestations completed. Independent publisher signing remains a separate readiness control until implemented or explicitly dispositioned.
- **Tag Confirmed/Created** — the stable tag resolves to the approved commit. The workflow creates or safely reuses it only after pre-publication validation.
- **Published to PowerShell Gallery** — the immutable Gallery version was successfully published.
- **Published to GitHub Release** — the immutable GitHub Release and expected assets were created for the same stable tag.
- **Distribution Verified** — published identities, assets, and the install path were checked after publication.
- **Documentation Verified** — Pages health was verified when release-related documentation changed.
- **Complete** — every required release-specific evidence item and channel result is resolved.

## Main-first release invariant

Integrate the release branch into `main` before final qualification. Final qualification must then qualify the exact resulting `main` SHA, not the release-branch SHA that existed before integration.

This ordering avoids creating a merge, squash, rebase, or follow-up commit after qualification. If the integration PR changes commit identity, that is expected: the resulting `main` SHA becomes the candidate and receives fresh qualification evidence.

Do not create the stable tag before final qualification. Do not qualify one commit and then publish a different `main` commit. If `main` moves after qualification, return to `Release Candidate` and qualify the new exact SHA.

## Preconditions before starting Publish Release

Do not begin stable publication until all applicable items below are satisfied or explicitly dispositioned by the exact-candidate readiness record:

1. **Release work is integrated** — the intended release content is already on `main` through the repository's protected pull-request process.
2. **Exact candidate selected** — record the 40-character commit SHA for current `main` and intended `vMAJOR.MINOR.PATCH` tag.
3. **Release readiness is `GO`** — use [`release-readiness.md`](release-readiness.md); do not recreate its capability or blocker decision here.
4. **Version metadata is aligned** — `ModuleVersion`, intended stable tag, dated changelog section, and release notes agree; `Unreleased` is empty at the tag boundary.
5. **Release metadata validation passes** — run `./build/Test-ReleaseReadiness.ps1 -Tag <tag> -RequireEmptyUnreleased` on the exact candidate.
6. **Quality evidence exists** — Windows, Ubuntu, and macOS Validate Project Quality evidence is successful for the candidate. **Publish Release** reruns the reusable validation and remains authoritative for release execution.
7. **Applicable live E2E evidence is recorded** — exact-candidate live evidence required by the quality/readiness model is present; an E2E harness existing is not the same as the release candidate having been live-validated.
8. **Security and non-functional blockers are dispositioned** — repository-security hardening, independent publisher-signing status, and any other release-required controls referenced by readiness must have an explicit blocker or accepted-limitation disposition.
9. **Publishing environment is ready** — the `powershell-gallery` GitHub environment exists and provides `PSGALLERY_API_KEY`; any configured environment approval is available.
10. **No immutable-version conflict exists** — the intended version is not already published in PowerShell Gallery or as a stable GitHub Release, and any pre-existing tag resolves to the exact qualified `main` SHA. The workflow checks again before mutation.

If any required precondition changes after approval, return to `Release Candidate` and repeat readiness review. A later commit requires a new readiness review. Do not reuse stale approval.

## Canonical release procedure — manual workflow dispatch

Manual dispatch from `main` is the only supported automated stable-publication entry point. **Publish Release** validates the current branch SHA before it is allowed to create the stable tag.

1. Confirm the release integration PR has completed and refresh `main`.
2. Record the exact current `main` SHA.
3. Complete final release qualification for that exact SHA and record `GO`.
4. Reconfirm `main` still equals the qualified SHA and that no conflicting stable tag, GitHub Release, or Gallery version exists.
5. Open **Actions -> Publish Release -> Run workflow**.
6. Select **main**.
7. Enter the approved stable tag, for example `v0.3.0`.
8. Select `confirm_publish`.
9. Start the workflow.
10. Record the workflow run ID and captured `${{ github.sha }}` in the release evidence record.
11. Verify **Validate Release Context** confirms the dispatch ref is `main`, the captured SHA is still current `main`, and tag/version/changelog readiness passes.
12. Verify **Validate Release Commit** passes the reusable Windows, Ubuntu, and macOS Validate Project Quality jobs on the exact workflow SHA.
13. In **Publish Release**, verify the workflow reruns readiness validation, builds the deterministic ZIP and Gallery package, generates the SPDX SBOM, creates required provenance/SBOM attestations, performs duplicate checks, creates or safely reuses the annotated tag only when it resolves to the approved SHA, publishes the Gallery package, and creates the GitHub Release with ZIP, checksum, and SBOM assets.
14. Do not manually create a second GitHub Release or move or recreate the stable tag around the workflow.
15. Continue to post-publication verification below.

Stable tag pushes do not start publication. Creating a stable tag before the manual workflow does not substitute for qualification or publication and can create an immutable identity conflict. The normal process therefore leaves tag creation to **Publish Release** after validation.

## What Publish Release publishes

For module version `X.Y.Z`, normal GitHub Release evidence includes:

- `CopyGitHubRepo-X.Y.Z.zip`;
- `CopyGitHubRepo-X.Y.Z.zip.sha256`;
- `CopyGitHubRepo-X.Y.Z.spdx.json`;
- GitHub build-provenance attestation bound to the ZIP; and
- GitHub SBOM attestation bound to the same ZIP.

The workflow publishes the validated module package to PowerShell Gallery before creating the GitHub Release. Those operations are separate external mutations and cannot be made atomic.

Independent publisher signing is not implied by checksum, SBOM, or GitHub attestations. Its implementation or explicit release-specific disposition is governed by the security architecture and release-readiness process.

## Post-publication verification

### Tag and GitHub Release

- Confirm the stable tag resolves to the exact approved candidate SHA.
- Confirm the GitHub Release tag, title, and version agree with the module version.
- Confirm the expected ZIP, `.sha256`, and `.spdx.json` assets exist.
- Download and verify the ZIP checksum using the documented stable verification procedure.
- Verify GitHub build-provenance and SBOM attestations against repository `infoconex/copy-github-repo`.
- Confirm release notes, changelog, support, and security links are correct and do not claim evidence that was not produced.

### PowerShell Gallery

- Confirm `Find-PSResource CopyGitHubRepo -Version X.Y.Z -Repository PSGallery` returns the intended immutable version.
- From a clean supported environment, install the exact version through the supported stable distribution path.
- Import the installed module in a fresh `pwsh -NoProfile -NonInteractive` process.
- Confirm the installed manifest version is `X.Y.Z` and only the documented public command surface is exported.
- Exercise a safe smoke path appropriate for the release; do not perform a destructive repository migration merely to prove package import.

### Stable installer/update path

- Verify `install-release.ps1 -Version X.Y.Z` resolves the intended GitHub Release.
- Confirm checksum validation succeeds before extraction and installer execution.
- Confirm an integrity mismatch fails closed; do not bypass checksum validation to complete the release.

### Documentation site

If release-related documentation or site content changed, confirm the corresponding **Deploy Documentation Site** run passed its Jekyll build and generated-site integrity validation, deployment succeeded, and the published-site smoke test succeeded.

Pages is an independent deployment. A Pages failure after module publication does not authorize altering or overwriting immutable package or release artifacts.

## Failure and recovery matrix

Before retrying, determine whether failure occurred **before** or **after** an immutable or public mutation.

| Failure | Public/immutable state | Safe normal response |
| --- | --- | --- |
| Version/tag/manifest/changelog mismatch | None if caught before tag creation | Fix metadata on `main`, create a new candidate/readiness decision, rerun. Do not tag. |
| Validate Project Quality failure | None before tag creation | Diagnose the actual failing evidence; fix on a new commit; repeat readiness for the new SHA. |
| Required live evidence missing/failed | None | Record `NO-GO` or `PENDING`; obtain valid exact-candidate evidence or explicitly disposition it under readiness rules. |
| Package/artifact/SBOM/attestation failure | None before tag creation | Fix the cause on a new candidate and rerun. Never publish without required integrity evidence. |
| Publishing credential/environment approval unavailable | None if failure occurs before Gallery publication | Restore access or approval and rerun only if candidate and tag state remain valid. Never expose the key in diagnostics. |
| Existing Gallery version detected | Gallery version already exists | Stop. Do not overwrite or republish the immutable version. Determine whether it is the intended artifact; use a new version if correction is required. |
| Existing GitHub Release detected | GitHub Release already exists | Stop normal publication. Do not clobber stable assets. Verify the existing release; correction normally requires a new version and tag. |
| Tag exists but resolves to a different commit | Stable identity conflict | Stop. Never move/reuse the tag for a different approved SHA. Use a new version and tag after review unless formal incident recovery explicitly authorizes otherwise before any package/release publication. |
| Gallery publication fails | Tag may exist; Gallery version is not confirmed | Determine whether Gallery accepted the version before retry. If absent, a reviewed rerun may reuse the exact tag only when it resolves to the approved SHA. |
| Gallery succeeds, GitHub Release fails | Gallery version is public and immutable; tag exists; GitHub Release is absent | Do not republish Gallery. Preserve evidence and investigate the GitHub failure. Blind rerun is not a repair mechanism. |
| GitHub Release succeeds but post-publication artifact verification fails | Stable GitHub Release and public assets exist | Treat this as a release incident. Do not clobber stable assets or move the tag; correction normally uses a new version and follows [`incident-response.md`](incident-response.md). |
| Gallery publication succeeds but clean install/import verification fails | Gallery version is public and immutable | Do not overwrite Gallery. Preserve the failing evidence and issue a corrected version if a defect is confirmed. |
| Documentation Pages deployment fails | Product/package release may already be complete | Fix and redeploy documentation independently. Do not mutate stable product artifacts to repair Pages. |

A retry is safe only when it cannot overwrite an immutable version, cannot associate a stable tag with a different commit, and cannot duplicate an uncertain external mutation. When publication status is ambiguous, verify the external service first.

## Partial multi-channel publication record

If one distribution channel succeeds and another fails, record at minimum the exact version/tag/commit, Publish Release workflow run ID and failed step, stable-tag target, Gallery exact-version presence, checksum/SBOM/attestation identities already created, verification status, current user-facing recommendation, recovery decision authority, and any incident reference.

Do not call the release `Complete` until every required channel and verification state is resolved.

## Manual fallback

Manual publication is a contingency, not the normal release procedure. Follow [`publishing.md`](publishing.md) and use the exact approved `main` revision plus the same local quality, release-readiness, package-validation, duplicate-version, integrity, and immutability rules.

A manual fallback must not silently omit evidence that **Publish Release** normally requires. If GitHub attestation generation is unavailable, release readiness must explicitly decide whether publication is blocked or whether a release-specific accepted limitation is defensible. Do not describe missing evidence as generated.

## Documentation deployment lifecycle

GitHub Pages is deployed by `.github/workflows/deploy-documentation-site.yml` (**Deploy Documentation Site**) when site-related paths change, and it can be dispatched manually. The workflow checks out the exact workflow SHA, builds Jekyll content, runs `build/Test-GeneratedSite.ps1`, uploads the Pages artifact, deploys through the `github-pages` environment, and smoke-tests key published routes.

## Release completion record

Before marking a stable release complete, retain or link these release-specific facts:

- version, tag, and exact commit SHA;
- exact release-readiness go/no-go record and decision authority;
- Publish Release workflow run ID;
- Windows, Ubuntu, and macOS Validate Project Quality result;
- applicable exact-candidate live E2E evidence;
- release ZIP filename/SHA-256;
- SPDX SBOM filename and identity;
- provenance and SBOM attestation verification result;
- PowerShell Gallery publication and clean-install verification;
- GitHub Release publication and asset verification;
- stable installer checksum/install verification;
- Pages deployment and smoke evidence when applicable;
- accepted limitations and residual risks; and
- final state: `Complete`, `Partial / recovery required`, or `Failed before publication`.

The mutable `main` branch, a generic previous CI run, or the existence of a release tag alone is not sufficient release-completion evidence.

## Authority and escalation

Release execution follows the current project authority in [`governance.md`](../engineering/governance.md). Self-review and automation do not become independent approval evidence merely because the workflow succeeded.

Normal readiness/go-no-go remains owned by [`release-readiness.md`](release-readiness.md). Serious post-publication security, supply-chain, artifact, credential, or distribution problems transition to [`incident-response.md`](incident-response.md) rather than improvising destructive repair in this runbook.

## Related authorities

- Release readiness/go-no-go: [`release-readiness.md`](release-readiness.md)
- Version semantics: [`versioning.md`](versioning.md)
- PowerShell Gallery/release publication details: [`publishing.md`](publishing.md)
- Release SBOM/provenance: [`release-sbom.md`](../security/release-sbom.md)
- Installation trust/checksum verification: [`installation-security.md`](../security/installation-security.md)
- Quality/live-evidence semantics: [`quality-strategy.md`](../engineering/quality-strategy.md)
- Project governance: [`governance.md`](../engineering/governance.md)
- Support lifecycle: [`support-policy.md`](../user/support-policy.md)
- Software assurance: [`software-assurance.md`](../security/software-assurance.md)
