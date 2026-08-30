---
title: "CopyGitHubRepo Support and Compatibility Policy"
description: "Review supported CopyGitHubRepo versions, PowerShell and operating-system compatibility, Git and GitHub prerequisites, deprecation rules, breaking changes, and end-of-support policy."
---

# Support, compatibility, and deprecation policy

This policy defines which Copy GitHub Repository versions and environments the project supports, how compatibility-sensitive changes are handled, and how deprecations or end-of-support decisions are communicated.

The policy is intentionally conservative. It does not create long-term-support commitments, historical prerequisite matrices, or platform guarantees that the project does not continuously test.

## Current support status

Version `0.1.0` is the initial stable release. The latest published stable module version is the supported stable version. Before `1.0.0`, older stable versions are not maintained as parallel supported branches unless a release note explicitly says otherwise.

| Item | Support position |
| --- | --- |
| Module version | Latest published stable version |
| Long-term-support branches | None currently defined |
| Security fixes | Applied to the currently supported stable version; older versions may require upgrading to receive a fix |
| Prerelease/unreleased builds | Development and release-candidate evaluation only; not a separately supported production line |
| GitHub host | GitHub.com only for the current `0.2.x` release line |
| PowerShell | PowerShell 7.4+ / Core edition |
| Operating systems | Windows, Ubuntu/Linux, and macOS families represented by the cross-platform release Quality Gate; exact historical OS versions are not separately guaranteed |

The exact released version is identified by the module manifest, Git tag, changelog entry, and immutable release/package artifacts. See [Versioning and releases](../release/versioning.md).

## Security-fix support

`SECURITY.md` is authoritative for vulnerability reporting and the currently security-supported version/branch.

Security fixes target the latest supported stable version. The project does not promise backports to older pre-1.0 releases. Unreleased `main` content may contain future fixes or changes, but it is not a separately supported production line.

A vulnerability may therefore require users of an older release to upgrade to the fixed supported release. If an exceptional backport or extended-support decision is made, it must be announced explicitly in release notes and reflected in `SECURITY.md`.

## Semantic Versioning and pre-1.0 compatibility

The project follows Semantic Versioning 2.0.0.

Before `1.0.0`, incompatible changes may occur in a **minor** release. That flexibility is not permission for silent breakage. Any incompatible public change must:

1. be intentional and reviewed;
2. be recorded in `CHANGELOG.md` and release notes;
3. identify the affected public command, parameter, output/report contract, behavior, or documented feature;
4. include migration guidance when users must change scripts, automation, or operating procedures;
5. update automated contracts and documentation in the same release.

Patch releases should remain backward-compatible bug/security/documentation fixes. After `1.0.0`, incompatible public contract changes require a major version unless an established deprecation/removal rule explicitly permits otherwise.

## PowerShell compatibility

The current normative minimum is **PowerShell 7.4** with the Core edition. The module manifest and release Quality Gate enforce that baseline.

Raising the minimum PowerShell version is a compatibility-sensitive change. Before `1.0.0`, it requires at least a minor release plus changelog/release-note notice and updated installation/support documentation. After `1.0.0`, the versioning impact must be evaluated against the public compatibility contract rather than being treated as a routine patch.

The project does not imply Windows PowerShell 5.1 support.

## Git, GitHub CLI, and Git LFS prerequisites

Git, GitHub CLI (`gh`), and—when applicable—Git LFS are external prerequisites, not software redistributed with the module.

The project does not maintain a historical compatibility matrix for every prerequisite release. Support is **capability-based and release-tested**:

- the prerequisite must still be supported by its upstream/vendor for normal organizational use;
- it must provide the commands/behaviors required by the product contract;
- the release Quality Gate and release-candidate validation provide evidence for the prerequisite versions present in those test environments;
- older or unusual prerequisite versions that have not been exercised are best-effort, not guaranteed compatibility.

If an operation fails because an installed prerequisite lacks a required capability, upgrading that prerequisite is the supported first remediation. If the project later adopts an exact minimum version for Git, `gh`, or Git LFS, that minimum must be documented, validated, and announced as a compatibility change.

Git LFS remains conditional: it is required only when the selected operation/content requires LFS behavior.

## Operating-system support

The release Quality Gate runs on Windows, Ubuntu, and macOS. Those platform families are the supported cross-platform target for the PowerShell module.

The policy does not claim that every historical release or distribution version within those families has been tested. Support evidence is strongest for the runner/platform versions used by the exact release validation. Organizations with stricter OS-version requirements should validate the intended module release in their managed environment before approval.

A platform family may be removed from support only through an announced compatibility change with changelog/release-note notice and migration guidance where practical.

## GitHub host compatibility

The current `0.2.x` release line supports **GitHub.com only**. GitHub Enterprise Server and other hosts are unsupported/deferred and fail closed through the public host guard.

The detailed host contract is in [GitHub host support](host-support.md). Adding another host is a product capability change that requires explicit design, verification, and documentation; it is not inferred from the presence of the `-HostName` parameter.

## Deprecation policy

Compatibility-sensitive public surface includes:

- exported commands;
- public parameters and accepted values;
- structured output/report fields that automation is expected to consume;
- error identifiers or failure contracts documented as stable;
- default behaviors and safety semantics;
- supported installation/release workflows;
- documented features that users may reasonably automate against.

When practical, a public capability should be deprecated before removal. A deprecation must:

- identify what is deprecated and why;
- identify the intended replacement or migration path when one exists;
- be documented in the changelog/release notes and relevant command/user documentation;
- avoid changing safety-critical behavior silently;
- remain in place for at least one subsequent stable release before removal when doing so is technically and operationally reasonable.

The one-release notice is a project goal, not an unconditional promise. A severe security, data-loss, platform, or correctness risk may require faster removal or behavioral change. Any accelerated removal must be documented with the reason and migration guidance.

## Breaking changes and migration guidance

A breaking change is any change that requires a supported user or automation consumer to modify how it invokes, interprets, or safely operates the product.

For each breaking change, maintainers must record:

- the affected version boundary;
- what changed;
- why the change is necessary;
- who is affected;
- the required migration action;
- whether the change was previously deprecated;
- any release-readiness evidence needed for the new behavior.

The changelog is the concise change record; detailed migration instructions belong in the relevant user/command/installation documentation and should be linked from release notes rather than duplicated everywhere.

## End of support

A module release becomes unsupported when a newer stable release supersedes it under the current single-supported-version policy, unless an explicit exception is announced.

A platform, prerequisite baseline, or product capability may reach end of support when continuing it would be unsafe, technically infeasible, upstream-unsupported, disproportionately costly to validate, or inconsistent with the product direction. End-of-support decisions must be intentional and communicated through the changelog/release notes and the relevant support/security documentation.

The project does not currently promise a fixed calendar support duration. If a time-based support window or LTS model is introduced later, it requires an explicit policy change rather than being inferred from past release cadence.

## Communication and authority

Use these sources together:

| Question | Authority |
| --- | --- |
| Which version/branch receives security fixes? | [`SECURITY.md`](../../SECURITY.md) |
| What versions/compatibility rules apply? | This policy and [`versioning.md`](../release/versioning.md) |
| What changed in a release? | [`CHANGELOG.md`](../../CHANGELOG.md) and GitHub release notes |
| What hosts are supported? | [`host-support.md`](host-support.md) |
| What platforms/prerequisites are required to run the product? | [`user-guide.md`](user-guide.md), [`installation-security.md`](../security/installation-security.md), module manifest |
| What is the organizational approval state? | [`software-assurance.md`](../security/software-assurance.md) |
| What exact release evidence is required? | [`quality-strategy.md`](../engineering/quality-strategy.md), release-readiness/runbook authorities |

If these sources disagree, the narrower authoritative source should be corrected rather than allowing multiple competing support statements to persist.
