# Snapshot Release Safety

Snapshot publication intentionally creates a clean Git history. Historical Git tags and GitHub Releases are historical records and are not copied into the clean destination.

## New destination

For a normal Snapshot into a new repository:

- the approved default-branch tree is published as one new root commit;
- prior commits, other branches, and source tags are not copied;
- GitHub Releases are not recreated in the destination;
- the source repository remains unchanged and retains its tags and Releases.

The migration plan records the source tag and GitHub Release evidence that was observed during planning so this behavior is visible before publication.

## Same-name replacement

For same-name Snapshot replacement, the original repository is renamed to the selected archive name before a fresh repository is created under the original name. Renaming preserves the original repository identity and its historical records, including existing Git tags and GitHub Releases.

The clean replacement is a distinct GitHub repository. Historical tags and Releases are not recreated there because doing so would reconnect or misrepresent the history that Snapshot is intentionally removing.

## First stable release ordering

Do not create a stable release tag on the historical repository before performing a clean same-name replacement. A tag created before replacement remains associated with the archived history rather than the new clean root commit.

Use this sequence:

```text
clean Snapshot replacement
-> verify destination tree and one-root-commit history
-> create the stable tag on the clean replacement commit
-> create/publish the GitHub Release
-> publish release artifacts and the PowerShell Gallery package
```

For the initial release, `v0.1.0` must point to the final clean replacement commit.

## Planning and wizard behavior

Snapshot planning captures a bounded summary of source tags and GitHub Releases. Human-readable plans state that these records are not copied, and same-name plans state that they remain with the archive. The interactive wizard surfaces the same warning before execution when historical tags or Releases are present.

FullHistory behavior is unchanged: FullHistory continues to preserve Git branches, tags, commits, and reachable history according to its existing contract. GitHub Release records remain outside the Git-history copy contract unless explicitly supported in a future feature.

## Why records are not recreated automatically

Automatically copying historical tags into the clean replacement could make old commits reachable again or imply ancestry that the Snapshot destination does not contain. Automatically recreating GitHub Releases could similarly imply that historical release artifacts belong to the clean repository history. Snapshot therefore leaves historical records with the source/archive and lets maintainers create new release records deliberately after verification.

See also [Publishing to PowerShell Gallery](../release/publishing.md) for the stable release workflow and [Manually Creating a Clean GitHub Repository Snapshot](manual-process.md) for the equivalent manual publication process.
