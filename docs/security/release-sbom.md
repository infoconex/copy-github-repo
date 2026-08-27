---
title: "CopyGitHubRepo Release SBOM and GitHub Attestations"
description: "Understand CopyGitHubRepo stable-release SBOM, SHA-256 integrity, dependency classification, GitHub provenance and SBOM attestations, VEX boundaries, retrieval, and verification."
---

# Release SBOM and attestations

Stable CopyGitHubRepo releases publish machine-readable component evidence alongside the installable archive. This document defines that evidence and its security boundary.

## Stable release evidence set

For module version `X.Y.Z`, the stable GitHub release contains:

- `CopyGitHubRepo-X.Y.Z.zip` — deterministic installable release archive;
- `CopyGitHubRepo-X.Y.Z.zip.sha256` — SHA-256 integrity sidecar;
- `CopyGitHubRepo-X.Y.Z.spdx.json` — SPDX 2.3 JSON Software Bill of Materials (SBOM);
- GitHub artifact provenance attestation for the release ZIP;
- GitHub SBOM attestation binding the SPDX document to the same release ZIP.

Independent publisher signing remains a separate optional control. A checksum, SBOM, or GitHub attestation must not be described as equivalent to an independently managed publisher-signing key.

A VEX sidecar is **not** part of the routine v0.1.0 release evidence set. [`vulnerability-applicability.md`](vulnerability-applicability.md) defines the trigger-based VEX decision and the evidence required before a vulnerability applicability statement is published.

## What the SBOM describes

`build/New-ReleaseSbom.ps1` generates the SBOM **after** `build/New-ReleaseArtifact.ps1` has created the release ZIP. The generator opens that completed ZIP and records every shipped file entry with SHA-1 and SHA-256 checksums. The package-level SHA-256 checksum identifies the exact ZIP described by the document.

The SPDX package identity and version come from `src/CopyGitHubRepo/CopyGitHubRepo.psd1`. Generation fails if the supplied artifact name does not match the manifest version. The document also records the exact 40-character Git commit SHA supplied by the release workflow and uses the release commit timestamp for deterministic creation metadata.

The release workflow checks out `${{ github.sha }}`, runs release readiness and the reusable cross-platform Quality Gate for that exact commit, builds the ZIP, and then generates the SBOM from that ZIP. The SBOM therefore does not describe a later mutable `main` working tree.

## Dependency classification

The SBOM package graph intentionally represents **shipped runtime content**, not every tool or service involved in development and delivery.

| Dependency class | SBOM treatment | Rationale |
| --- | --- | --- |
| Shipped PowerShell module files | File inventory inside the `CopyGitHubRepo` SPDX package | These bytes are contained in the release ZIP. |
| Runtime PowerShell module dependencies | None currently declared | The module manifest does not declare third-party runtime PowerShell modules. |
| PowerShell 7.4+, Git, GitHub CLI | Documented as external runtime prerequisites, not `DEPENDS_ON` packages | They are required on the operator host but are not shipped in the archive. |
| Git LFS | Documented as a conditional external prerequisite | It is required only for operations involving approved LFS content and is not shipped. |
| Pester and PSScriptAnalyzer | Explicitly excluded from the shipped runtime package graph | They are development/test dependencies, not installed-module dependencies. |
| GitHub Actions and action dependencies | Explicitly excluded from the shipped runtime package graph | They are CI/release infrastructure. |
| GitHub Releases and PowerShell Gallery | Explicitly excluded from the shipped runtime package graph | They are distribution services, not installed components. |

This classification is deliberate so vulnerability and software-inventory scanners do not infer that development-only tooling is a runtime dependency of an installed CopyGitHubRepo module.

## SPDX format

The project uses **SPDX 2.3 JSON** for v0.1.0 release SBOMs. SPDX 2.3 provides a stable JSON serialization and is accepted by GitHub's SBOM attestation capability. The repository contract validates the fields used by this project, package/version identity, shipped file inventory, artifact checksum binding, deterministic output, and dependency classification.

The SBOM uses one top-level `CopyGitHubRepo` package with `CONTAINS` relationships to the files present in the release archive. A package verification code is calculated from the file SHA-1 values according to the SPDX 2.x package model. The ZIP itself is recorded with a SHA-256 package checksum.

## Vulnerability applicability and VEX

An SBOM records component/content identity; it does not state whether a known vulnerability affects or is exploitable in a particular CopyGitHubRepo release. VEX is the separate evidence class for that applicability/response question.

The project evaluated SPDX VEX and CycloneDX VEX and intentionally **does not generate empty VEX for every release**. The current module has no declared third-party runtime PowerShell module dependencies, and there is no current vulnerability applicability determination that needs machine-readable communication.

When a material vulnerability requires applicability analysis, [`vulnerability-applicability.md`](vulnerability-applicability.md) requires exact release/SBOM/vulnerability binding, defensible evidence for statuses such as not affected, and security decision authority under [`governance.md`](../engineering/governance.md). If the release evidence model has already migrated to SPDX 3 with supported Security-profile tooling, SPDX VEX is preferred; while the authoritative SBOM remains SPDX 2.3, a separate CycloneDX VEX document is the preferred interoperability path when then-current consumers support it reliably.

A future VEX statement must not remove a component from the SBOM, convert a real applicability question into a `false positive`, or suppress scanner evidence without a release-specific technical rationale. GitHub custom artifact attestations may be evaluated to authenticate a VEX statement to the exact release ZIP, but attestation does not prove the vulnerability conclusion is technically correct.

## GitHub attestations

The release workflow uses the consolidated `actions/attest` action with an immutable commit pin.

Two attestations are generated for the versioned ZIP:

1. **Build provenance attestation** — records GitHub Actions provenance for the artifact.
2. **SBOM attestation** — binds the artifact subject to the generated SPDX JSON predicate.

The release job grants only the additional GitHub permissions required for attestation: `id-token: write` and `attestations: write`, alongside the existing release publication permission.

For a public repository, GitHub artifact attestations use GitHub's supported Sigstore-backed verification model. Attestations are associated with the repository and can be verified using GitHub CLI's attestation verification commands.

A successful attestation proves that GitHub's attestation service signed a statement tying the recorded subject digest to the workflow identity and predicate. It does **not** prove the software is vulnerability-free, that every dependency classification is semantically perfect, or that the release was independently code-signed by a separately managed publisher key.

## Retrieval and verification

For a stable release:

1. Download the versioned ZIP, checksum, and `.spdx.json` file from the same stable GitHub release.
2. Verify the ZIP SHA-256 using the release checksum as described in [Installation & Security](installation-security.md).
3. Inspect the SPDX JSON to confirm `CopyGitHubRepo`, the expected module version, artifact filename/checksum, and source commit.
4. Verify GitHub artifact attestations for the ZIP with a current GitHub CLI, using the repository identity `infoconex/copy-github-repo` as the trusted repository when following GitHub's attestation verification procedure.
5. Treat any digest, repository, workflow, version, or subject mismatch as a failed verification rather than falling back to an unverified install.
6. If a release publishes VEX in response to a material vulnerability, verify its exact release/product/vulnerability identity and any associated attestation separately; absence of VEX is not evidence that no vulnerabilities apply.

Version `v0.1.0` is the initial stable release and uses this evidence contract.

## Reproducibility and failure behavior

The ZIP builder fixes entry ordering and timestamps. The SBOM generator sorts ZIP entries and uses the release commit timestamp supplied by the workflow. Given the same release ZIP, source commit, and creation timestamp, the SBOM output is expected to be byte-stable.

Failure to generate the SBOM or either required attestation fails the release job before PowerShell Gallery or GitHub Release publication. The normal release path does not silently publish a stable release without the required SBOM/provenance evidence.

Because VEX is trigger-based rather than routine release evidence, the absence of a VEX file is not a release-job failure unless a specific vulnerability response has made VEX a required artifact for that release under the documented applicability process.

## Relationship to other assurance evidence

- [Security Architecture](security-architecture.md) records the SBOM/provenance control and residual limitations.
- [Dependency Monitoring](dependency-monitoring.md) covers development and CI dependency freshness; that inventory is intentionally broader than the shipped runtime SBOM.
- [Vulnerability Applicability and VEX](vulnerability-applicability.md) defines when vulnerability applicability evidence is warranted and what proof is required.
- [Installation & Security](installation-security.md) defines checksum/bootstrap trust boundaries.
- [Software Assurance Review](software-assurance.md) consumes this SBOM/provenance evidence rather than duplicating its machine-readable component inventory.
