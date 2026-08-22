# Security Policy

## Supported versions

The project has not published its first stable release. Security fixes currently
apply to the latest commit on the default branch until `v0.1.0` is published.

After the first stable release, security fixes target the latest supported stable
module version under [`docs/user/support-policy.md`](docs/user/support-policy.md). Before
`1.0.0`, older stable versions are not promised parallel security-fix branches
unless an exceptional backport or extended-support decision is announced
explicitly.

## Reporting a vulnerability

Do not open a public issue for a suspected vulnerability. Use GitHub's private
vulnerability reporting feature for this repository when available, or contact
the repository owner privately.

Private vulnerability reporting was verified enabled for this repository on
2026-08-16 and was reconfirmed by the repository owner in the GitHub web UI on
2026-08-19.

Include the affected version or commit, reproduction steps, potential impact,
and any suggested mitigation. Do not include live credentials or private
repository content.

For the reviewer-facing threat model, credential/data flow, control/evidence
matrix, dependency trust inventory, and residual-risk status, see
[`docs/security/security-architecture.md`](docs/security/security-architecture.md).

For supported module/platform/prerequisite versions, compatibility expectations,
deprecation, and end-of-support rules, see
[`docs/user/support-policy.md`](docs/user/support-policy.md).

For the live GitHub repository security posture, required baseline, verified
settings, and settings that require re-verification after repository replacement,
see [`docs/security/repository-security-baseline.md`](docs/security/repository-security-baseline.md).

For the stable-release SBOM, dependency classification, provenance/SBOM
attestation contract, retrieval, verification, and evidence limitations, see
[`docs/security/release-sbom.md`](docs/security/release-sbom.md).

## Runtime security boundaries

The utility uses existing GitHub CLI authentication. It does not collect,
display, copy, or persist token values. GitHub secrets, webhook secrets, private
deploy-key material, and GitHub App credentials are outside the migration
contract.

Version 1 supports GitHub.com only. Public commands reject unsupported hosts
before prerequisites, discovery, planning, verification, or mutation. HTTPS Git
operations use GitHub CLI credentials through command-scoped Git configuration;
interactive Git credential prompting is disabled.

The tool does not automatically delete repositories or overwrite an existing
destination. Same-name replacement first preserves the source under an archive
name and validates immutable GitHub repository identity plus mode-specific Git
content evidence before the original name is reused. Replacement content copy
is blocked unless the replacement repository has a distinct immutable identity.

## Repository security posture

Repository-level GitHub security settings are treated as live platform controls,
not inferred defaults. The repository security baseline records which settings
were verified directly and which were verified by the repository owner in the
GitHub web UI when the connected integration could not independently read them.

The historical repository now has an active branch ruleset named `main` targeting
the default branch with the required protection behavior configured by the
repository owner. Dependabot alerts and security updates, secret scanning and push
protection where available, private vulnerability reporting, and least-privilege
default GitHub Actions workflow permissions were also verified in the GitHub web
UI on 2026-08-19. These observations establish the current repository baseline;
they do not carry forward automatically to the clean same-name Snapshot
replacement repository, which must be independently re-verified before release.

## Release and installer trust boundaries

Stable release publication is tag-only. The exact tagged commit must pass the
reusable Windows, Ubuntu, and macOS quality gate before the release job can run.
The normal workflow treats stable release assets as immutable and refuses to
replace or clobber an existing stable release.

The release ZIP is published with a SHA-256 checksum and an SPDX 2.3 JSON SBOM.
The release workflow generates both build-provenance and SBOM attestations for
the exact versioned ZIP before GitHub release publication. The SBOM is generated
from the completed ZIP, records the exact release commit, and deliberately keeps
development/CI dependencies out of the shipped runtime dependency graph.

`install-release.ps1` verifies the selected ZIP against the release checksum
before extraction and before invoking the packaged installer. Without `-Version`
it resolves the latest stable release; with `-Version X.Y.Z` it targets exactly
`vX.Y.Z`.

The convenience one-line stable install command fetches `install-release.ps1`
from mutable `main`, so the bootstrap itself is part of the trust boundary. The
separate `install-prerelease.ps1` bootstrap is also fetched from mutable `main`;
it resolves `main` to a commit SHA before downloading and installing that exact
unreleased source archive. Prerelease source installation has no published
release checksum and is intended for development and release-candidate testing.

For a higher-assurance stable path, use the pinned release procedure in
`docs/security/installation-security.md`, which downloads a specific release artifact and
checksum without executing mutable branch content.

A matching checksum proves that the artifact matches the compared hash. GitHub
artifact attestations provide additional repository/workflow provenance evidence,
but neither the checksum, SBOM, nor attestation is represented as independent
publisher code signing. Independent publisher signing is optional for the initial
stable release and may be added later as a separate publisher-identity control.
