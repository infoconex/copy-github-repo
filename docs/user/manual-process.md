---
title: "How to Create a Clean GitHub Repository Snapshot Manually"
description: "Follow a manual Git and GitHub CLI procedure to publish a clean GitHub repository Snapshot with one unrelated root commit, verified content, settings, protection, LFS, and provenance."
---

# Manually Creating a Clean GitHub Repository Snapshot

## Purpose

`CopyGitHubRepo` defaults to `Snapshot` because its primary use case is **clean current-state publication**, not a conventional history-preserving migration. The goal is to publish the current state of a developed repository into a new GitHub repository whose visible Git history begins with one new unrelated root commit.

A successful Snapshot publication keeps the selected source default-branch Git tree while intentionally leaving the development trail behind.

This guide shows a representative manual procedure using Git, GitHub CLI, and GitHub APIs. It is intended to be usable on its own rather than to make the automated path look artificially complicated.

## Desired end state

For `OWNER/source` to `OWNER/destination`, Snapshot should produce:

- the same default-branch Git tree as the selected source commit;
- exactly one unrelated root commit in the destination;
- no prior Git commits;
- no historical non-default branches or tags;
- no pull requests, issues, milestones, discussions, Actions run history, traffic history, stars, watchers, forks, packages, deployments, or similar GitHub historical records;
- source visibility by default;
- required Git LFS objects when the selected Snapshot uses LFS;
- supported ordinary repository settings and topics;
- transferable repository-level rulesets and default-branch protection, restored only after content verification;
- independent read-back verification and publication evidence.

This is intentionally different from `git clone --mirror` / `git push --mirror`, which preserve refs and reachable history.

## Prerequisites

You need Git, GitHub CLI, an authenticated GitHub session/token, and Git LFS when the selected Snapshot contains LFS-tracked files.

```powershell
git --version
gh --version
gh auth status --hostname github.com
```

Authenticate if needed:

```powershell
gh auth login --hostname github.com
```

Use explicit names throughout:

```powershell
$Source = 'OWNER/source'
$Destination = 'OWNER/destination'
```

## 1. Discover and capture the source state

Read repository metadata before mutation:

```powershell
$SourceRepo = gh repo view $Source --json `
    id,nodeId,nameWithOwner,visibility,defaultBranchRef,description,homepageUrl,` 
    hasIssuesEnabled,hasProjectsEnabled,hasWikiEnabled,hasDiscussionsEnabled,` 
    mergeCommitAllowed,squashMergeAllowed,rebaseMergeAllowed,autoMergeAllowed,` 
    deleteBranchOnMerge,webCommitSignoffRequired,repositoryTopics |
    ConvertFrom-Json

$Branch = $SourceRepo.defaultBranchRef.name
```

Capture the exact source commit and tree selected for publication:

```powershell
$SourceCommit = gh api "repos/$Source/commits/$Branch" --jq '.sha'
$SourceTree = gh api "repos/$Source/git/commits/$SourceCommit" --jq '.tree.sha'
```

Keep the source immutable repository ID/node ID, branch, commit SHA, and tree SHA. These values are publication evidence later.

### Capture protection before mutation

Repository protection must be discovered before any replacement operation and restored only after the content is complete.

Repository-level rulesets can be inspected without inherited organization rules:

```powershell
$SourceRulesets = gh api "repos/$Source/rulesets?includes_parents=false" | ConvertFrom-Json
```

For legacy protection on the source default branch:

```powershell
$SourceProtection = gh api "repos/$Source/branches/$Branch/protection" | ConvertFrom-Json
```

Do not assume every returned protection object is safely transferable. Identity-bound bypass actors, team/user/app restrictions, required deployments, and integration-bound status checks require deliberate handling and should not be silently stripped to create a weaker policy. See [Repository protection restoration](protection-restoration.md).

## 2. Confirm the destination name is unused

```powershell
gh repo view $Destination
```

A not-found result is expected. If the command succeeds, stop and choose another destination or use a deliberately designed archive-and-replace flow. Do not delete an existing destination merely to make the preflight pass.

## 3. Clone and verify the selected source state

Create an isolated working directory and clone the default branch:

```powershell
$Work = Join-Path ([System.IO.Path]::GetTempPath()) "clean-snapshot-$([guid]::NewGuid().ToString('N'))"
git clone --depth 1 --branch $Branch "https://github.com/$Source.git" $Work
Set-Location $Work
```

Make sure the source did not move between discovery and clone:

```powershell
$ClonedCommit = git rev-parse HEAD
$ClonedTree = git rev-parse 'HEAD^{tree}'

if ($ClonedCommit -ne $SourceCommit) {
    throw "Source moved. Expected $SourceCommit but cloned $ClonedCommit."
}
if ($ClonedTree -ne $SourceTree) {
    throw "Source tree mismatch. Expected $SourceTree but cloned $ClonedTree."
}
```

## 4. Handle Git LFS when present

```powershell
git lfs version
git lfs ls-files
```

If LFS-tracked files are present:

```powershell
git lfs fetch origin $Branch
git lfs checkout
```

Pointer files alone are not sufficient; the underlying LFS objects must also be transferred and later fetched successfully from the destination.

## 5. Create the destination repository

Preserve source visibility unless an intentional visibility change has been reviewed.

```powershell
# choose the option matching the source
gh repo create $Destination --public
# or
gh repo create $Destination --private
```

Record destination identity:

```powershell
$DestinationRepo = gh repo view $Destination --json id,nodeId,nameWithOwner,url | ConvertFrom-Json
```

A new destination should have a different immutable repository ID from the source.

## 6. Create the clean root commit

The key Git operation is to reuse the selected source tree **without a parent commit**:

```powershell
$DestinationCommit = git commit-tree $SourceTree -m 'Initial repository commit'
```

No `-p` parent is supplied, so this is a root commit. The destination commit SHA is expected to differ from `$SourceCommit` even though both commits reference the same tree; commit identity includes more than the tree and the destination intentionally has different ancestry.

## 7. Push the root commit and LFS content

```powershell
git push "https://github.com/$Destination.git" "$DestinationCommit`:refs/heads/$Branch"
```

When LFS is present:

```powershell
git remote add clean-destination "https://github.com/$Destination.git"
git lfs push clean-destination $Branch
```

A successful push proves transport success, not the complete Snapshot contract.

## 8. Verify Git content before restoring configuration

Reload the destination commit/tree:

```powershell
$DestinationHead = gh api "repos/$Destination/commits/$Branch" --jq '.sha'
$DestinationTree = gh api "repos/$Destination/git/commits/$DestinationHead" --jq '.tree.sha'

if ($DestinationTree -ne $SourceTree) {
    throw 'Destination tree does not match the selected source tree.'
}
```

Clone the destination and verify its history shape:

```powershell
$VerifyPath = "$Work-verify"
git clone --branch $Branch "https://github.com/$Destination.git" $VerifyPath

$CommitCount = [int](git -C $VerifyPath rev-list --count $Branch)
if ($CommitCount -ne 1) {
    throw "Expected exactly one destination commit but found $CommitCount."
}

$RootCommits = @(git -C $VerifyPath rev-list --max-parents=0 $Branch)
if ($RootCommits.Count -ne 1 -or $RootCommits[0] -ne $DestinationHead) {
    throw 'Destination history is not the expected single root commit.'
}
```

When LFS is involved, prove the objects are available from the destination:

```powershell
git -C $VerifyPath lfs fetch --all
git -C $VerifyPath lfs checkout
git -C $VerifyPath lfs ls-files
```

## 9. Restore ordinary supported repository settings

`CopyGitHubRepo` currently restores these ordinary repository-level settings:

- description;
- homepage;
- Issues enabled state;
- Projects enabled state;
- Wiki enabled state;
- Discussions enabled state;
- squash merge enabled state;
- merge-commit enabled state;
- rebase merge enabled state;
- auto-merge enabled state;
- delete-branch-on-merge;
- update-branch allowance;
- web commit signoff requirement;
- repository topics.

A manual process should read source values first and only change values that differ. Do not coerce an unavailable source field to `false`.

Representative repository patch:

```powershell
$Patch = @{
    description                 = $SourceRepo.description
    homepage                    = $SourceRepo.homepageUrl
    has_issues                  = [bool] $SourceRepo.hasIssuesEnabled
    has_projects                = [bool] $SourceRepo.hasProjectsEnabled
    has_wiki                    = [bool] $SourceRepo.hasWikiEnabled
    has_discussions             = [bool] $SourceRepo.hasDiscussionsEnabled
    allow_squash_merge          = [bool] $SourceRepo.squashMergeAllowed
    allow_merge_commit          = [bool] $SourceRepo.mergeCommitAllowed
    allow_rebase_merge          = [bool] $SourceRepo.rebaseMergeAllowed
    allow_auto_merge            = [bool] $SourceRepo.autoMergeAllowed
    delete_branch_on_merge      = [bool] $SourceRepo.deleteBranchOnMerge
    web_commit_signoff_required = [bool] $SourceRepo.webCommitSignoffRequired
} | ConvertTo-Json -Compress

$Patch | gh api --method PATCH "repos/$Destination" --input -
```

`allow_update_branch` is also supported when available in the source API response.

Restore topics separately:

```powershell
$TopicPayload = @{ names = @($SourceRepo.repositoryTopics.name) } | ConvertTo-Json -Compress
$TopicPayload | gh api --method PUT "repos/$Destination/topics" --input -
```

Read the destination back and compare every source-available value:

```powershell
$DestinationSettings = gh api "repos/$Destination" | ConvertFrom-Json
$DestinationTopics = gh api "repos/$Destination/topics" | ConvertFrom-Json
```

A mismatch is a failed publication, not a warning to ignore.

## 10. Restore transferable repository protection last

Only after content and ordinary settings are verified should protection be enabled on the destination.

For repository-level rulesets, recreate only rulesets whose semantics are transferable without source-bound actors/integrations. For example, a normalized identity-free ruleset can be created through:

```powershell
$RulesetPayload = @{
    name        = $Ruleset.name
    target      = $Ruleset.target
    enforcement = $Ruleset.enforcement
    conditions  = $Ruleset.conditions
    rules       = $Ruleset.rules
} | ConvertTo-Json -Depth 100

$RulesetPayload | gh api --method POST "repos/$Destination/rulesets" --input -
```

Legacy default-branch protection can be restored through the branch-protection API only when its restrictions are transferable. Required signatures use their dedicated endpoint.

Do **not** silently remove:

- ruleset bypass actors;
- required deployments that depend on environments you did not create;
- status checks bound to a specific integration/app;
- user/team/app push restrictions;
- identity-bound review-dismissal restrictions.

Those cases should be explicitly recorded as skipped/unsupported rather than converted into weaker protection. Inherited organization rulesets are external organization policy and should not be copied or claimed as copied repository settings.

After writing protection, reload the destination rulesets/default-branch protection and compare the normalized configuration. Treat a mismatch as failure.

## 11. Record publication provenance

Because Snapshot intentionally severs Git ancestry, retain external publication evidence:

- source repository name and immutable ID/node ID;
- source default branch;
- source commit SHA;
- source tree SHA;
- destination repository name and immutable ID/node ID;
- destination root commit SHA;
- destination tree SHA;
- UTC publication timestamp;
- verification outcome;
- configuration/protection restoration and skip evidence.

Do not add a provenance marker file, parent commit, tag, or note to the destination merely to reconnect it to the old history. That would change the clean-publication result.

## 12. Historical GitHub records are intentionally absent

No command in this Snapshot procedure migrates prior commits, non-default branches, tags, pull requests, issues, milestones, discussions, Actions run history, traffic history, stars/watchers/forks, packages, deployments, or similar historical records.

That absence is deliberate.

## Failure and recovery considerations

A manual procedure can fail after destination creation. Avoid destructive cleanup by default. Record source/destination identity, selected commit/tree, destination commit/tree if created, the last completed stage, settings/protection already changed, LFS status, and the exact failure.

Before retrying, reload the destination and determine which operations really completed. Blind repetition can destroy troubleshooting evidence or create a result different from the original plan.

`CopyGitHubRepo` writes durable structured recovery evidence for post-mutation failures; the manual equivalent is disciplined record keeping.

## Advanced: same-name clean replacement

Reusing the source repository's name adds a significant identity boundary. A safe manual process should:

1. choose an unused archive name;
2. capture source immutable ID/node ID, branch, commit, tree, settings, and protection evidence;
3. rename the source to the archive name;
4. reload the archive and verify it retained the original immutable repository ID;
5. verify captured source content survived the rename;
6. create a new repository under the original name;
7. verify the replacement has a **different** immutable repository ID;
8. publish the clean Snapshot from the archive's canonical repository identity;
9. verify tree equality and the one-root-commit contract;
10. restore/verify ordinary settings;
11. restore/verify transferable protection last;
12. record source/archive/replacement provenance;
13. preserve the archive unless a human deliberately decides otherwise.

After replacement, the archive is the durable historical record for the original development history, issues, pull requests, and other records. It is not merely a temporary rollback convenience.

## Alternatives and tradeoffs

### Mirror clone / mirror push

Appropriate when the goal is to preserve refs and reachable Git history. It solves the opposite history requirement from Snapshot.

### Orphan branch or manual file copy

Can create unrelated history, but the operator remains responsible for exact tree fidelity, file modes, LFS, GitHub configuration, collision safety, provenance, and verification.

### GitHub template repositories

Useful for reusable starter repositories. They are not a direct substitute for a controlled one-time publication of an arbitrary developed repository; LFS and configuration behavior must be evaluated separately.

### GitHub Importer

Designed for import/migration scenarios rather than deliberately collapsing a developed repository to one unrelated root commit.

### Blank repository plus file copy

Can produce a clean first commit but shifts exact-content, LFS, metadata, settings, and verification responsibilities to the operator.

## When not to use Snapshot

Do not use Snapshot when you must preserve original commit ancestry, signed historical commits, commit-level provenance, historical `git blame`, multiple branches/tags, long-lived pull-request relationships tied to existing history, or audit requirements that depend on the original Git graph.

Use `FullHistory` or another history-preserving migration mechanism instead.

## Provenance implications

Snapshot intentionally severs Git ancestry. The clean destination cannot reconstruct original commit history, signatures, authorship chronology, or blame data from its own Git graph. Publication evidence can prove which source state was published, but it is not equivalent to preserved history.

Retaining the original/archive can therefore matter for historical auditability even when the clean repository is the public-facing result.

## Security and unsupported configuration

Snapshot does **not** restore every GitHub feature. Current exclusions include Pages, Actions activation/configuration, secret values, webhooks, deploy keys, environments, collaborator/team access, packages, deployments, and other items outside the product contract.

Transferable repository-level rulesets and legacy default-branch protection are supported as a late restoration stage; identity-bound or environment/integration-dependent protection semantics are explicitly skipped rather than weakened. Organization-inherited rulesets are external policy, not copied repository configuration.

Secret values are never requested, displayed, persisted, or copied.

## What the module automates

A thorough manual Snapshot publication commonly represents roughly **30–45 individual commands, API calls, validations, and comparisons**, depending on repository settings, protection, and LFS use. The meaningful complexity is the sequence of safeguards:

- prerequisite/authentication checks;
- source discovery and validation;
- destination collision checks;
- exact source commit/tree capture;
- protection discovery;
- Snapshot Git operations;
- LFS detection, transfer, and verification;
- destination creation and identity capture;
- tree/history-shape verification;
- differential ordinary settings restoration and read-back verification;
- staged transferable protection restoration and read-back verification;
- provenance/reporting/recovery evidence.

`CopyGitHubRepo` also provides behavior that is not just shell-command substitution: `-PlanOnly`, `-WhatIf`/`ShouldProcess`, the guided wizard, repository search, visibility safeguards, exact replacement confirmations, structured results, Markdown/JSON reports, differential restoration, durable recovery reports, immutable-ID checks, publication provenance, and automated post-copy verification.

The underlying operations remain ordinary Git and GitHub operations. The module's value is making the complete clean-publication procedure repeatable, verifiable, and difficult to perform incorrectly.
