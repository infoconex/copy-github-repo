---
title: "Snapshot Migration Safety – Git Tags and GitHub Releases"
description: "Understand plain Snapshot versus opt-in release-checkpoint preservation, original Git history versus selected release states, same-name replacement archives, and safe stable-release ordering."
---

# Snapshot Release Safety

**Plain `Snapshot` and `Snapshot -IncludeReleases` have different release behavior.** Both intentionally create a new, unrelated Git history. Neither preserves the original commit SHAs or detailed development ancestry. Use `FullHistory` when preserving ordinary commits, branches, tags, and their original targets matters.

The authoritative rules for selected release topology, checkpoint state, and verification are in the [Snapshot release-checkpoint contract](../product/product-contract.md#snapshot-release-checkpoint-contract). The [user guide](user-guide.md#snapshot-release-checkpoints) describes the corresponding command and wizard options.

## Plain Snapshot (without `-IncludeReleases`)

For a plain Snapshot into a new repository:

- the reviewed source default-branch tree is published as **one new unrelated root commit**;
- original commits, other branches, and source Git tags are not copied;
- source GitHub Releases and their assets are **not recreated** in the destination; and
- the source repository is unchanged and retains its historical tags and Releases.

The plan records a bounded summary of observed source tags and GitHub Releases so the intentional omission is visible before publication. Copying ordinary repository files is not equivalent to preserving GitHub-side release objects.

## Snapshot with `-IncludeReleases`

`Snapshot -IncludeReleases` opts into **selected release-state preservation** without copying the original Git commit graph:

- The plan records the exact selected GitHub Releases, tag targets, metadata, assets, and checkpoint evidence. Stable, non-draft releases are selected by default; include/exclude tag filters, draft/prerelease opt-ins, and newest-N limiting are deliberate choices.
- Selected source tag targets are resolved to commits and ordered by **Git ancestry**, not by release dates or tag names. Divergent or ambiguous selected topology fails closed rather than inventing a history.
- The destination receives **new, unrelated linear checkpoint commits** whose repository trees represent the selected release states. Selected release tags point to these **new checkpoint commits**, not to their original source commit SHAs.
- Selected GitHub Release objects and assets are recreated and verified against the approved selection. Unselected historical Git tags, releases, ordinary development branches, and original commit ancestry are not copied.
- A final current-state Snapshot commit is added only if reviewed source HEAD differs in repository state from the last selected release checkpoint. An approved empty release selection yields the ordinary one-root-commit Snapshot.

Execution consumes the immutable reviewed release/checkpoint plan rather than rerunning live release filtering or selecting newer releases. Moved or stale selected source state fails closed. Failure after destination mutation may leave verified checkpoints, tags, or releases in place; recovery preserves evidence and **does not automatically delete or rewrite** them.

## FullHistory with `-IncludeReleases`

`FullHistory` preserves ordinary reachable Git history, branches, and Git tag targets regardless of `-IncludeReleases`. Adding `-IncludeReleases` additionally recreates the approved selected GitHub Release objects and assets **against those original, preserved tag targets**. It does not build Snapshot checkpoint history. GitHub-assigned release identities, timestamps, and historical download counts are not necessarily preserved exactly.

## Same-name Snapshot replacement

For same-name replacement, the original repository is renamed to an approved archive before a **distinct** replacement repository is created. The archive retains its historical Git graph, original tags, releases, issues, and pull requests.

- With plain Snapshot, the replacement contains one new root commit and **does not** recreate the archive's historical releases or tags.
- With `Snapshot -IncludeReleases`, only the immutable **selected** release states, new checkpoint tags, supported release metadata, and assets are recreated in the replacement. Historical source commits and unselected records stay with the archive.
- Selected release metadata and assets are read from the approved archived source after the rename and checked against the reviewed plan; a stale or ambiguous archive/source identity fails closed.
- If later work fails, the archive is preserved. The module does not automatically delete the replacement, rename archives back, remove already-created checkpoints/releases, or claim rollback was complete without evidence.

The wizard surfaces the historical-record warning and the release opt-in, filters, and checkpoint implications before execution.

## Historical Snapshot replacement and stable release ordering

Do **not** create a **new product stable release tag** on the old historical repository before a same-name clean Snapshot replacement. That tag would remain attached to the archived original rather than the qualified replacement. This is distinct from the **selected source release tags** intentionally recreated when `-IncludeReleases` is requested.

The initial `v0.1.0` clean-repository release was tagged only after the replacement had been independently verified. For any **current product release**, use the [release runbook](../release/release-runbook.md) and [publishing procedure](../release/publishing.md), not a separate publication sequence from this Snapshot guide:

1. Complete any intended replacement and independent destination verification; integrate the release branch into `main`.
2. Qualify the **exact resulting current `main` SHA**, record release readiness and an explicit `GO` decision, and check for immutable version/tag conflicts.
3. Deliberately start **Publish Release** by manual workflow dispatch on `main`. That workflow validates, builds, and attests the artifacts and only then safely confirms or creates the release tag for that exact approved commit.
4. The workflow publishes the validated **PowerShell Gallery package first** and creates the **GitHub Release second**. These are separate external mutations; a partial publication failure requires the release incident/recovery process, **not** an overwrite or unreviewed tag move.
5. Independently verify both distribution channels and documentation deployment as required by the release readiness contract.

## Why plain Snapshot omits historical records

Copying arbitrary original tags into a plain Snapshot destination would reintroduce references to commits outside its deliberately clean history or imply ancestry that is not present. Recreating GitHub Releases without opt-in, reviewed tag targets and asset evidence could likewise misrepresent what was published. Plain Snapshot therefore leaves historical records with the source/archive. The opt-in checkpoint path recreates only reviewed **release states** in new history, while FullHistory is the choice for preserving original Git identity.

See also [Manually Creating a Clean GitHub Repository Snapshot](manual-process.md) for an explicit manual procedure and [Troubleshooting and recovery](troubleshooting-recovery.md) for partial-mutation handling.
