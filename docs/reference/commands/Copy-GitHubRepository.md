---
title: "Copy-GitHubRepository – Copy or Migrate GitHub Repositories"
description: "Use Copy-GitHubRepository to safely copy or migrate GitHub repositories with Snapshot or FullHistory, optional release preservation and GitHub Pages restoration, planning, verification, and replacement safeguards."
---

# Copy-GitHubRepository

Plans or executes a safe GitHub repository copy/publication. `Snapshot` is the default clean-publication mode; `FullHistory` is the explicit history-preserving alternative. The command is the deterministic API used directly by scripts and indirectly by the guided wizard.

## Synopsis

```powershell
Copy-GitHubRepository `
    -SourceRepository <owner/name> `
    -DestinationRepository <owner/name> `
    [-ContentMode Snapshot|FullHistory] `
    [-IncludeReleases] `
    [-ReleaseTag <pattern[]>] `
    [-ReleaseExcludeTag <pattern[]>] `
    [-IncludePrerelease] `
    [-IncludeDraftReleases] `
    [-ReleaseCount <count>] `
    [-DestinationVisibility public|private|internal] `
    [-ArchiveRepositoryName <name>] `
    [-SameNameConfirmation <text>] `
    [-ExistingDestinationArchiveName <name>] `
    [-ExistingDestinationConfirmation <text>] `
    [-CommitMessage <text>] `
    [-RestorePages] `
    [-EnableActionsAfterMigration] `
    [-SkipSettings] `
    [-PlanOnly] `
    [-NonInteractive] `
    [-OutputMode Interactive|Plain|Json] `
    [-ReportPath <path>] `
    [-HostName <hostname>] `
    [-Force] `
    [-WhatIf] `
    [-Confirm]
```

## When to use it

Use plain Snapshot when the desired result is a new repository containing reviewed current source HEAD as one unrelated root commit, without carrying prior Git history, old branches/tags, issues, pull requests, milestones, discussions, or other historical GitHub activity.

Use `Snapshot -IncludeReleases` when you still want clean, newly created Git history but selected release states, tags, GitHub Release metadata, and assets should be represented as release checkpoints. Snapshot checkpoint commits are intentionally new: original source commit SHAs and detailed ancestry are not preserved.

Use `FullHistory` when ordinary Git history, branches, and tags must be preserved. Add `-IncludeReleases` when selected GitHub Release objects and their assets should also be recreated against the original preserved tags.

Add `-RestorePages` in either content mode when supported GitHub-side Pages configuration should be restored from the reviewed plan. This is distinct from copying site files, `CNAME`, Jekyll configuration, or Pages workflow files as ordinary Git content.

For an interactive guided experience, use [`Start-CopyGitHubRepositoryWizard`](Start-CopyGitHubRepositoryWizard.md). Pages operating guidance is in [GitHub Pages migration and recovery](../../user/github-pages-migration.md). The normative checkpoint topology/state rules are in the [Snapshot release-checkpoint contract](../../product/product-contract.md#snapshot-release-checkpoint-contract).

## Parameters

| Parameter | Type | Required | Default | Accepted values / format | Description |
| --- | --- | --- | --- | --- | --- |
| `SourceRepository` | `String` | Yes | — | `owner/name` | Source repository. It must exist and contain a default branch with content. |
| `DestinationRepository` | `String` | Yes | — | `owner/name` | Destination. A different existing destination requires explicit archive-and-replace parameters; the same name selects same-name replacement. |
| `ContentMode` | `String` | No | `Snapshot` | `Snapshot`, `FullHistory` | Selects clean Snapshot publication or history-preserving Git transfer. |
| `IncludeReleases` | `Switch` | No | `$false` | Snapshot or FullHistory | Requests GitHub Release preservation. Snapshot creates new release-checkpoint commits/tags from selected release states; FullHistory preserves original Git history/tag targets and recreates releases against them. Stable, non-draft releases are selected by default. |
| `ReleaseTag` | `String[]` | No | All tags | PowerShell wildcard patterns | Includes only releases whose tag names match at least one pattern. Exact tag names are valid patterns. Requires `-IncludeReleases`. |
| `ReleaseExcludeTag` | `String[]` | No | None | PowerShell wildcard patterns | Excludes matching release tags after include filtering. Requires `-IncludeReleases`. |
| `IncludePrerelease` | `Switch` | No | `$false` | Switch | Includes GitHub Releases marked as prereleases. Requires `-IncludeReleases`. |
| `IncludeDraftReleases` | `Switch` | No | `$false` | Switch | Includes draft GitHub Releases. Requires `-IncludeReleases`. |
| `ReleaseCount` | `Int32` | No | All selected | `1` or greater | Keeps only the newest N releases after filtering. Filtering uses publication time, then creation time; Snapshot checkpoint construction order is determined separately by source Git ancestry. Requires `-IncludeReleases`. |
| `DestinationVisibility` | `String` | No | Source visibility | `public`, `private`, `internal` | Destination visibility. An intentional change requires `-Force` for mutation. |
| `ArchiveRepositoryName` | `String` | Conditionally | — | Repository name only | Required for same-name replacement; must be unused. |
| `SameNameConfirmation` | `String` | Conditionally | — | Exact `SOURCE=...;ARCHIVE=...;REPLACEMENT=...` text | Exact same-name replacement confirmation. `-Force` cannot bypass it. |
| `ExistingDestinationArchiveName` | `String` | Conditionally | — | Repository name only | Enables archive-and-replace for a different existing destination. |
| `ExistingDestinationConfirmation` | `String` | Conditionally | — | Exact `DESTINATION=...;ARCHIVE=...;REPLACEMENT=...` text | Exact existing-destination replacement confirmation. |
| `CommitMessage` | `String` | No | `Initial repository commit` | Non-empty text | Specifies the Snapshot commit message used by Snapshot publication. FullHistory preserves existing commits and does not rewrite them. |
| `RestorePages` | `Switch` | No | `$false` | Switch | Opts into deterministic GitHub-side Pages restoration from immutable reviewed plan evidence after content verification. Source Pages evidence is revalidated immediately before mutation; unsupported/unrepresentable or stale state fails closed. External DNS, domain verification, certificate provisioning, and secrets are not migrated. |
| `EnableActionsAfterMigration` | `Switch` | No | `$false` | Switch | Reserved in plans; mutating execution rejects general Actions activation because it is not implemented. Pages-specific activation control is part of the `-RestorePages` safety contract and does not make this switch implemented. |
| `SkipSettings` | `Switch` | No | `$false` | Switch | Skips ordinary supported repository settings and repository-protection restoration. Requested release and Pages restoration still run. |
| `PlanOnly` | `Switch` | No | `$false` | Switch | Returns a validated, non-mutating plan including immutable Git state, selected release/checkpoint inventory when requested, and immutable Pages evidence when `-RestorePages` is requested. |
| `NonInteractive` | `Switch` | No | `$false` | Switch | Prevents prompts. Mutating non-interactive execution also requires `-Force`. |
| `OutputMode` | `String` | No | `Interactive` | `Interactive`, `Plain`, `Json` | Controls plan rendering. |
| `ReportPath` | `String` | No | — | File path | Writes plan/execution evidence and is the preferred recovery-report location after mutation begins. |
| `HostName` | `String` | No | `github.com` | `github.com` in the current release line | GitHub host. Other hosts fail closed. |
| `Force` | `Switch` | No | `$false` | Switch | Acknowledges non-interactive mutation and intentional visibility changes; never bypasses exact replacement confirmations. |

The command supports native `ShouldProcess`, so `-WhatIf` and `-Confirm` are available.

## Plain Snapshot behavior

A normal Snapshot publication without `-IncludeReleases`:

1. validates prerequisites/source/destination safety;
2. captures immutable reviewed source evidence;
3. creates or preserves/replaces the destination as required;
4. creates one unrelated root commit from reviewed current source HEAD and transfers required Git LFS content;
5. reloads and verifies tree equality and the one-root-commit history shape;
6. restores and verifies ordinary supported repository settings/topics;
7. restores requested Pages configuration when `-RestorePages` was approved;
8. restores transferable repository protection last and verifies it through API read-back; and
9. returns structured verification and publication-provenance evidence.

The destination root commit SHA is expected to differ from the source commit SHA because Snapshot intentionally creates a new parentless Git commit. The tree/state is the content invariant.

## Snapshot with release checkpoints

```powershell
Copy-GitHubRepository `
    -SourceRepository infoconex/source `
    -DestinationRepository infoconex/destination `
    -ContentMode Snapshot `
    -IncludeReleases
```

`Snapshot -IncludeReleases` creates a new unrelated linear history from the exact release states selected during planning. It does not squash or rewrite the original source graph.

For the selected releases:

- source release tags are resolved to reviewed peeled commit targets and repository trees;
- distinct selected targets must form a deterministic sequence by source Git ancestry; divergent/incompatible topology fails closed;
- the first distinct selected release state becomes a new unrelated root checkpoint;
- later distinct selected release states become later checkpoint commits;
- multiple selected releases at the same source commit share one checkpoint while retaining separate tags/releases;
- recreated release tags point to new Snapshot checkpoint commits whose repository trees correspond to selected source release states;
- original source commit SHAs, parentage, detailed ancestry, authorship, committer identity, and timestamps are not claimed to be preserved;
- if reviewed source HEAD is state-equivalent to the latest selected release state, no extra current-state commit is created; and
- otherwise, when topology permits, exactly one final current-state Snapshot commit represents reviewed source HEAD.

If the approved release selection is empty, Snapshot behaves like normal one-root Snapshot publication.

Planning binds the exact release selection and checkpoint evidence before mutation. Execution consumes that reviewed evidence rather than rerunning live selection, and selected release/tag/tree drift fails closed. The selected GitHub Release metadata/assets and Latest designation where applicable are restored against the recreated Snapshot tags and verified.

## FullHistory

```powershell
Copy-GitHubRepository `
    -SourceRepository infoconex/source `
    -DestinationRepository infoconex/destination `
    -ContentMode FullHistory
```

FullHistory preserves ordinary branches, tags, reachable history, the default branch, and reachable Git LFS objects.

### Preserve GitHub Releases

```powershell
Copy-GitHubRepository `
    -SourceRepository infoconex/source `
    -DestinationRepository infoconex/destination `
    -ContentMode FullHistory `
    -IncludeReleases
```

Release preservation is separate from Git transfer. FullHistory always copies ordinary Git tags; `-IncludeReleases` controls which GitHub Release objects and assets are recreated against those already-preserved original tag targets.

By default, `-IncludeReleases` selects every stable, non-draft source release. Planning enumerates all source releases, applies requested filters, resolves each selected release tag to its commit SHA, and records exact selected inventory and asset metadata. Execution revalidates those approved releases before restoring them. A newly published release that was not part of the approved plan does not silently join the migration, while a selected release that changes after planning causes execution to fail closed.

Release restoration runs only after FullHistory content verification succeeds. For every selected release, the destination tag must resolve to the same approved original commit SHA before the GitHub Release is created. Existing destination releases are not overwritten.

## Release metadata and unsupported properties

For both modes, the following source metadata is recreated where GitHub permits it:

- tag association appropriate to the selected mode;
- release name/title;
- release body/notes;
- draft state when explicitly selected;
- prerelease state when selected;
- release assets, including labels where present; and
- the selected source Latest designation when applicable.

Destination verification compares supported release metadata plus asset name, label, size, content type, and GitHub-provided digests when available.

The following are not preserved exactly: GitHub-assigned release IDs, original release creation/publication timestamps, historical download counts, per-release immutability state/configuration, linked release discussions, annotated-tag object identity/tagger metadata/message, and other unsupported historical/operational GitHub records.

### Filter releases

The same release-selection filters apply to Snapshot and FullHistory:

```powershell
# Only v2 releases
-IncludeReleases -ReleaseTag 'v2.*'

# Specific releases
-IncludeReleases -ReleaseTag 'v1.5.0','v2.0.0'

# Exclude matching tags
-IncludeReleases -ReleaseExcludeTag '*-legacy'

# Include prereleases
-IncludeReleases -IncludePrerelease

# Include drafts as well
-IncludeReleases -IncludePrerelease -IncludeDraftReleases

# Keep only the three newest releases after filtering
-IncludeReleases -ReleaseTag 'v2.*' -ReleaseCount 3
```

`ReleaseCount` is applied after draft/prerelease and tag-pattern filtering. Publication/creation order determines selection only; Snapshot checkpoint history order is determined independently by Git ancestry.

## GitHub Pages restoration

`-RestorePages` is opt-in. Without it, Snapshot and FullHistory keep their normal Git-content semantics: site files, `CNAME`, Jekyll configuration, and Pages workflow files may still be copied if they are part of approved Git content, but CopyGitHubRepo does not claim that GitHub-side Pages configuration was preserved or restored.

When requested, planning captures immutable reviewed Pages evidence. Execution revalidates the relevant source Pages configuration immediately before Pages mutation and consumes the reviewed evidence as authority. Material drift fails closed rather than silently applying the new live state.

Supported GitHub-side state includes:

- explicit configured/not-configured state;
- Actions-based `workflow` build type;
- branch/path publishing when the exact reviewed branch and supported `/` or `/docs` path are representable at the destination;
- custom-domain binding under ownership-safe rules; and
- HTTPS enforcement intent where GitHub permits deterministic mutation/read-back.

Snapshot does not invent a missing source publishing branch or redirect Pages to another branch/path. Unsupported or unrepresentable publishing state fails closed.

External DNS is never copied or modified. Account/organization domain verification is not transferred. Certificate issuance/propagation remains externally dependent, so HTTPS intent can be correctly restored while certificate readiness is still pending. Secrets, tokens, and environment secret values are never requested or copied.

Pages restoration runs only after content verification, requested release restoration, and ordinary supported settings. Copied Pages workflow activation is controlled until the approved restoration/verification boundary. Supported destination Pages state is then independently read back; repository/branch protection remains the final restoration stage.

For same-name and existing-destination replacement, a reviewed custom domain is ownership-sensitive. Archive/replacement identity and exact reviewed ownership evidence are verified before archive release. The implementation records archive release, replacement claim, and replacement read-back evidence. It does not perform destructive automatic rollback when ownership after a partial failure is uncertain.

See [GitHub Pages migration and recovery](../../user/github-pages-migration.md) and the [GitHub Pages migration contract](../../product/github-pages-migration-contract.md).

## Supported ordinary settings

The ordinary settings stage supports description, homepage, Issues/Projects/Wiki/Discussions enabled states, squash/merge-commit/rebase/auto-merge flags, delete-branch-on-merge, update-branch allowance, web commit signoff, and repository topics. Restoration is differential and source-available values are independently read back.

## Repository protection

After content and requested release restoration are verified, the command restores supported ordinary settings, requested Pages configuration, and then the transferable subset of:

- repository-level rulesets;
- legacy protection for the source default branch.

Identity-bound semantics are never silently removed to make a policy portable. Rulesets with bypass actors, required deployments, or integration-bound checks and legacy protection with user/team/app restrictions or app-bound checks are surfaced as skipped/unsupported. Inherited organization rulesets are not copied.

See [Repository protection restoration](../../user/protection-restoration.md) for the detailed support matrix.

## Snapshot provenance

Successful Snapshot results/reports include publication provenance: source/destination repository identities when available, reviewed source state, generated destination Snapshot commits/trees, UTC timestamp, and verification outcome. Snapshot release-preservation evidence also identifies created checkpoint commits, recreated tags, restored releases/assets, and the last completed stage for recovery where applicable.

This evidence does not add provenance marker files, extra provenance tags, notes, or source-history parents to the destination.

## Replacement safety

Same-name replacement and explicit existing-destination replacement preserve the prior repository under an unused archive name before creating the fresh replacement. Exact typed confirmation is required. Neither `-Force` nor `-Confirm:$false` bypasses replacement identity safeguards.

For requested release preservation, same-name replacement reads the approved release/tag state from the archived original after rename and requires it to match the reviewed plan. Snapshot then constructs new checkpoint history in the replacement; FullHistory preserves the archived original history/tag targets.

For requested Pages restoration with a custom domain, the archived repository's immutable identity and exact reviewed domain binding are verified before the binding is released. The replacement claims the same reviewed domain only after that release is verified. External DNS remains untouched, and partial handoff state is retained for recovery.

Failures after mutation begins produce durable recovery information; the command does not automatically delete or roll back repositories, checkpoint commits/tags, restored releases, or uncertain custom-domain ownership.

## Output

Interactive planning returns `CopyGitHubRepo.MigrationPlan`. Plain/JSON planning returns text. Mutating execution returns a structured migration execution result with verification evidence, completed stages, release migration evidence when requested, Pages evidence when requested, ordinary settings evidence, repository-protection evidence, and Snapshot publication/checkpoint provenance where applicable.

When releases are requested, the result includes approved/restored release evidence, asset counts, tag/checkpoint or original-target evidence appropriate to the mode, and verification state. `Result.ReleasesRestored` indicates whether requested release restoration completed successfully.

When Pages is requested, execution evidence includes the reviewed configuration, restoration/verification status, external readiness, activation-guard state, and custom-domain handoff evidence where applicable. External DNS/domain verification/certificate state is not represented as migrated GitHub-side state.

## Important failure conditions

The command fails before mutation when tools/authentication are unavailable, source is invalid/empty, destination/archive safety requirements are not met, an unsupported host is supplied, a release filter is supplied without `-IncludeReleases`, a required `-Force` acknowledgement is missing, exact replacement confirmation is invalid, selected Snapshot release topology cannot be represented safely/deterministically, or reviewed Pages state is unsupported/unrepresentable during planning.

After mutation begins, Git/LFS verification failures, selected source/release/tag/tree drift, Pages evidence drift, wrong Snapshot checkpoint tag targets, checkpoint tree mismatches, pre-existing destination releases, release asset transfer/verification failures, unexpected pre-existing destination Pages, custom-domain ownership/handoff ambiguity, Pages mutation/read-back mismatch, ordinary settings read-back mismatches, protection API failures, and protection read-back mismatches are terminating failures with recovery diagnostics. Pending certificate provisioning is reported as external readiness where the deterministic GitHub-side configuration is otherwise valid.

## Examples

### Preview a clean Snapshot publication

```powershell
Copy-GitHubRepository `
    -SourceRepository infoconex/source `
    -DestinationRepository infoconex/destination `
    -PlanOnly
```

### Publish plain Snapshot

```powershell
Copy-GitHubRepository `
    -SourceRepository infoconex/source `
    -DestinationRepository infoconex/destination `
    -ContentMode Snapshot
```

### Publish Snapshot and preserve selected release checkpoints

```powershell
Copy-GitHubRepository `
    -SourceRepository infoconex/source `
    -DestinationRepository infoconex/destination `
    -ContentMode Snapshot `
    -IncludeReleases `
    -ReleaseTag 'v2.*' `
    -ReleaseCount 3
```

### Preserve full Git history and all stable releases

```powershell
Copy-GitHubRepository `
    -SourceRepository infoconex/source `
    -DestinationRepository infoconex/destination `
    -ContentMode FullHistory `
    -IncludeReleases
```

### Restore supported GitHub Pages configuration

```powershell
Copy-GitHubRepository `
    -SourceRepository infoconex/source `
    -DestinationRepository infoconex/destination `
    -ContentMode FullHistory `
    -RestorePages
```

Review the plan first when branch/path publishing or a custom domain is involved. `-RestorePages` does not modify external DNS or copy secrets.

### Skip ordinary settings and protection restoration

```powershell
Copy-GitHubRepository `
    -SourceRepository infoconex/source `
    -DestinationRepository infoconex/destination `
    -ContentMode Snapshot `
    -IncludeReleases `
    -SkipSettings
```

Requested Pages restoration is independent of `-SkipSettings`.

### Perform same-name Snapshot replacement

```powershell
Copy-GitHubRepository `
    -SourceRepository infoconex/source `
    -DestinationRepository infoconex/source `
    -ArchiveRepositoryName source-archive `
    -SameNameConfirmation 'SOURCE=infoconex/source;ARCHIVE=infoconex/source-archive;REPLACEMENT=infoconex/source' `
    -NonInteractive `
    -Force
```

Add `-RestorePages` only after reviewing the Pages/custom-domain handoff evidence in the plan.

### Archive and replace an existing destination

```powershell
Copy-GitHubRepository `
    -SourceRepository infoconex/source `
    -DestinationRepository infoconex/destination `
    -ExistingDestinationArchiveName destination-archive-20260813-213700 `
    -ExistingDestinationConfirmation 'DESTINATION=infoconex/destination;ARCHIVE=infoconex/destination-archive-20260813-213700;REPLACEMENT=infoconex/destination' `
    -NonInteractive `
    -Force
```

## Related documentation

- [`Start-CopyGitHubRepositoryWizard`](Start-CopyGitHubRepositoryWizard.md)
- [`Get-GitHubRepository`](Get-GitHubRepository.md)
- [`Test-GitHubRepositoryMigration`](Test-GitHubRepositoryMigration.md)
- [GitHub Pages migration and recovery](../../user/github-pages-migration.md)
- [GitHub Pages migration contract](../../product/github-pages-migration-contract.md)
- [Manual clean Snapshot process](../../user/manual-process.md)
- [Repository protection restoration](../../user/protection-restoration.md)
- [Snapshot release-checkpoint product contract](../../product/product-contract.md#snapshot-release-checkpoint-contract)
- [Product contract](../../product/product-contract.md)
- [Command design](../../product/command-design.md)
- [Architecture](../../product/architecture.md)