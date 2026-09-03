---
title: "Start-CopyGitHubRepositoryWizard – Guided GitHub Repository Copy"
description: "Use Start-CopyGitHubRepositoryWizard for a guided PowerShell workflow that selects Snapshot or FullHistory, optional releases and GitHub Pages restoration, reviews a real copy plan, and safely executes it."
---

# Start-CopyGitHubRepositoryWizard

Starts the guided, human-facing repository-copy workflow. The wizard handles interaction and delegates repository discovery to `Get-GitHubRepository` and planning/execution to `Copy-GitHubRepository`.

## Synopsis

```powershell
Start-CopyGitHubRepositoryWizard [-HostName <hostname>] [-Version] [-WhatIf] [-Confirm]
```

## When to use it

Use the wizard when a person wants to choose a source and migration options interactively, review a real migration plan, and explicitly decide whether to execute it. For scripts and automation, use [`Copy-GitHubRepository`](Copy-GitHubRepository.md) directly.

Use `-Version` when you only need to report the version of the loaded `CopyGitHubRepo` module. Version reporting exits immediately without repository discovery, planning, or GitHub mutation.

## Parameters

| Parameter | Type | Required | Default | Accepted values / format | Description |
| --- | --- | --- | --- | --- | --- |
| `HostName` | `String` | No | `github.com` | `github.com` in the current release line | GitHub host used by discovery and migration operations. Unsupported hosts fail closed. |
| `Version` | `Switch` | No | Off | `-Version` | Displays the loaded CopyGitHubRepo module version and exits. |

Because the command supports `ShouldProcess`, PowerShell also provides `-WhatIf` and `-Confirm`. Standard common parameters are available as well.

## Guided flow

The wizard guides the user through source selection, destination identity, content mode, destination visibility, supported-settings behavior, replacement safety where applicable, Snapshot-specific release choices, and optional GitHub Pages restoration. Safe defaults are `Snapshot`, source visibility, settings restoration, the default Snapshot commit message, no release preservation, and no Pages restoration.

Repository lists are paged in groups of 20. Use `N` and `P` for next and previous pages and `F` to filter the list. Page-local numbers select a repository from the visible page, while a full repository name remains a valid direct selection.

The destination prompt accepts a repository name directly or `[L list]`. List mode reuses the same paged/filterable selector. After selecting a destination, the wizard can use it unchanged, let the user modify the name, or return to choose another repository. Typed, selected, and modified destinations all converge on the same conflict handling and archive-and-replace safety flow.

Immediately after destination selection, the wizard checks whether a different destination already exists. If it exists, later migration questions are deferred until the conflict is resolved. The user can choose another destination, cancel, or select **Archive and replace existing destination**. Archive-and-replace never deletes the existing destination: the wizard proposes a timestamped archive repository name, allows that name to be changed, verifies that the archive name is unused, and includes the rename plus fresh replacement creation in the reviewed migration plan.

Archive-and-replace requires exact confirmation after the plan is reviewed and before mutation begins. If the migration fails after the existing destination has been renamed, that prior repository remains available under the archive name and the deterministic command writes recovery information describing the archive and failure stage.

For Snapshot migrations, the wizard shows the proposed Snapshot commit message before planning. The default is `Initial repository commit`. Press Enter to accept it or type a replacement. FullHistory migrations preserve existing commits and therefore do not prompt for a new commit message.

After the Snapshot commit-message step, the wizard presents **Snapshot release preservation** with two choices:

- `Skip` — the default; plain Snapshot remains one unrelated current-state root commit.
- `Preserve selected releases` — enables `Snapshot -IncludeReleases` and configures selected release states as newly created checkpoint commits.

Before that choice, the wizard explicitly explains that Snapshot release preservation creates **new checkpoint commits from selected release states**, does **not** preserve original commit identities or ancestry, and recreates selected tags against the new Snapshot checkpoints.

When release preservation is enabled, the wizard then asks for the same release-selection controls supported by `Copy-GitHubRepository`:

1. optional release tag include patterns, entered as comma-separated PowerShell wildcard patterns;
2. optional release tag exclude patterns;
3. whether to exclude or include prereleases, defaulting to exclude;
4. whether to exclude or include draft releases, defaulting to exclude; and
5. an optional positive whole-number release-count limit, applied to the newest releases after the other filters.

Press Enter keeps the current optional filter value. Enter `-` to clear an optional include pattern, exclude pattern, or count value. Back navigation moves through release-filter screens without discarding already accepted values, and Cancel ends the wizard before mutation.

The wizard does not invent its own checkpoint list. These selections are passed into the real `Copy-GitHubRepository -PlanOnly` path. The reviewed plan therefore contains the actual selected release/checkpoint evidence, topology validation, and final-current-state behavior that execution will use. The detailed checkpoint semantics are authoritative in the [Snapshot release-checkpoint product contract](../../product/product-contract.md#snapshot-release-checkpoint-contract).

Snapshot root/checkpoint commits are attributed according to the implementation's Snapshot authoring contract. Plain Snapshot and Snapshot release preservation both create new destination commit identities; neither mode promises preservation of source commit authorship, committer identity, parentage, timestamps, or SHAs.

## GitHub Pages choice and review

GitHub Pages restoration is a separate opt-in choice. The default is to **not** restore GitHub-side Pages configuration.

The wizard distinguishes ordinary Git content from Pages service state. Site files, `CNAME`, Jekyll configuration, and `.github/workflows/**` can be copied by Snapshot or FullHistory as repository content even when Pages restoration is skipped. That does not mean GitHub-side Pages configuration was migrated.

When Pages restoration is selected, the wizard delegates to the same real plan path used by `Copy-GitHubRepository -RestorePages`. The review uses plan-derived evidence rather than reconstructing Pages state independently. Where available it shows:

- whether source Pages is configured;
- Actions/workflow versus branch/path publishing;
- the exact publishing branch/path for branch-based Pages;
- custom domain;
- HTTPS enforcement intent;
- destination representability/safety; and
- external readiness that remains outside migration authority.

Actions-based Pages can restore the reviewed `workflow` build type. Branch/path publishing is supported only when the exact reviewed branch and supported `/` or `/docs` path can exist at the destination. Snapshot does not invent a missing source publishing branch or redirect Pages to a substitute source; unrepresentable state fails closed.

External DNS is not changed. Account/organization domain verification is not transferred. Certificate issuance/propagation can remain pending after deterministic GitHub-side configuration is restored, and the wizard does not present that external readiness as state it will migrate. Secrets, tokens, and environment secret values are never copied.

For same-name and existing-destination replacement with a reviewed custom domain, the review explains the archive-to-replacement domain handoff before execution. The underlying command verifies archive/replacement identity and exact reviewed ownership before release/claim, independently reads back the result, and preserves recovery evidence if handoff is only partially completed. The wizard does not weaken or replace those checks.

See [GitHub Pages migration and recovery](../../user/github-pages-migration.md) for operational and recovery details.

## Review and execution authority

Before mutation, the user can move Back or Cancel and can accept effective defaults with Enter. Changing a plan-affecting choice invalidates an older plan.

The review step calls the real `Copy-GitHubRepository -PlanOnly` path and displays that plan. The final Execute/Cancel decision is headed **Confirm repository copy**. GitHub mutation is not requested until the plan has been shown and the user explicitly chooses Execute. The wizard's `ShouldProcess` check is the final execution gate before delegation.

For same-name replacement, the wizard collects an unused archive name and the exact source/archive/replacement confirmation required by `Copy-GitHubRepository`. It does not weaken that command's safety rules. Snapshot release preservation and Pages restoration use the same archived-source/replacement safeguards and reviewed-plan authority as the deterministic command.

If plan-driving source state changes after review, deterministic execution fails closed at the applicable stale-state boundary. The wizard requires a newly generated plan to be reviewed rather than silently substituting live state.

## Prompt defaults

The wizard presents Enter-to-accept values consistently:

- listed choices mark the applicable option with `(default)`;
- the effective default is restated in parentheses at the end of the prompt;
- prompt affordances and trailing defaults use gray italic styling when ANSI styling is available;
- plain/non-styled hosts retain the same semantic text without ANSI sequences;
- pressing Enter accepts exactly the displayed value; and
- when a step is revisited, the previously accepted value becomes the value Enter will keep.

The wizard does not use separate `default/current` wording that could disagree with the value Enter actually accepts.

## Execution activity

During execution, the wizard presents durable activity in the same order as approved migration operations. This includes repository creation or archival where applicable, source cloning, Git LFS inspection/transfer, content publication, destination verification, requested release/checkpoint restoration and verification, supported-settings restoration, requested Pages restoration/verification, and repository-protection restoration/checking.

Git LFS activity distinguishes a real transfer from a successful no-op. When the source contains no required Git LFS content, the wizard reports that no transfer was required rather than implying that objects were copied.

Terminal activity stages consistently include elapsed duration when a start timestamp is available. Successful work is shown as success, successful no-ops as informational outcomes, partial/unsupported outcomes as warnings, and failures as errors.

For Pages, external readiness such as pending certificate provisioning is distinguished from unexpected migration failure. A partial custom-domain handoff remains a recovery condition with preserved evidence rather than being presented as if automatic rollback succeeded.

The completion summary reports verification, release restoration where requested, settings, Pages where requested, and protection outcomes before the final completion heading. A source with no transferable repository-protection rules is a successful `NotApplicable` outcome, not a skipped or failed restoration.

## Contextual help

Enter `?` at an applicable wizard prompt to display help for that exact decision, then return to the same prompt. Help is available for established wizard decisions such as source selection, destination input, existing-destination handling, content mode, visibility, supported settings, Snapshot commit messages, archive names, plan review, exact safety confirmations, and the Pages restoration decision where applicable.

Snapshot release-preservation and Pages screens present their feature-specific explanatory hints directly in the flow. Viewing available help does not advance or cancel the wizard, change the current/default value, invalidate a plan, or trigger GitHub mutation.

Back, Cancel, paging, filtering, and other navigation behaviors retain state after help is viewed.

## Cancellation and errors

Cancellation before mutation is a normal no-change outcome. Once mutation begins, Back is no longer offered.

Known application, validation, prerequisite, and safety conditions are presented as intentional wizard messages. This includes fail-closed Snapshot release-topology, stale reviewed-evidence, Pages representability, and Pages stale-state/safety failures returned by the shared planning/execution path. Expected recovery warnings are distinct from unexpected defects. The normal wizard UI does not display PowerShell source-file locations, line-number blocks, internal function prefixes, or invocation-position details for known conditions.

This presentation behavior does not change the deterministic command contract. Calling `Copy-GitHubRepository`, `Get-GitHubRepository`, or the other public commands directly still produces structured terminating errors that scripts can inspect and catch.

Unexpected internal defects are not converted into friendly application errors. They are rethrown so diagnostic information remains available. Post-mutation execution failures likewise retain the structured error and recovery information produced by `Copy-GitHubRepository`.

## Output

With `-Version`, the command returns a `System.String` containing the loaded module version and performs no wizard work. Otherwise, pre-mutation cancellation returns `CopyGitHubRepo.WizardResult` with `Status = 'Cancelled'` and `MutatedGitHub = $false`. A known pre-mutation application failure returns `CopyGitHubRepo.WizardResult` with `Status = 'ApplicationError'`, `MutatedGitHub = $false`, and the stable application `ErrorId`. Confirmed execution is rendered as a concise human-facing completion summary; use `Copy-GitHubRepository` directly when automation requires the raw structured migration result.

## Important failure conditions

The wizard can stop before mutation when the selected host is unsupported or when delegated discovery/planning cannot satisfy prerequisites. Snapshot execution also requires usable Snapshot commit-authoring identity. Snapshot release preservation can fail closed during planning when selected release tags cannot be represented as deterministic checkpoint topology or when reviewed release/tag/tree evidence is invalid/stale. Pages restoration can fail closed when the reviewed publishing mode/source is unsupported or unrepresentable, when Pages evidence becomes stale, or when custom-domain ownership/handoff prerequisites are ambiguous. Same-name and existing-destination replacement cannot proceed without valid unused archive names and required exact confirmations.

After mutation begins, Pages recovery evidence can describe a partial custom-domain release/claim or other completed stage. The wizard does not infer that external DNS, domain verification, or certificate readiness was migrated, and it does not claim destructive rollback occurred when ownership state is uncertain.

## Examples

### Report the installed module version

```powershell
Start-CopyGitHubRepositoryWizard -Version
```

### Start with safe defaults

```powershell
Start-CopyGitHubRepositoryWizard
```

Accept or change the guided choices. For Snapshot, you can keep the default plain one-commit publication or opt into selected release preservation. Pages restoration remains off unless explicitly selected. Review the generated real plan before execution.

### State the supported host explicitly

```powershell
Start-CopyGitHubRepositoryWizard -HostName github.com
```

### Exercise the full guided flow without executing mutation

```powershell
Start-CopyGitHubRepositoryWizard -WhatIf
```

The wizard can still gather choices, including Snapshot release selections and Pages restoration, and display the real plan, but `ShouldProcess` prevents delegated execution.

## Related documentation

- [`Copy-GitHubRepository`](Copy-GitHubRepository.md)
- [`Get-GitHubRepository`](Get-GitHubRepository.md)
- [GitHub Pages migration and recovery](../../user/github-pages-migration.md)
- [GitHub Pages migration contract](../../product/github-pages-migration-contract.md)
- [Snapshot release-checkpoint product contract](../../product/product-contract.md#snapshot-release-checkpoint-contract)
- [Wizard contract](../../product/wizard-contract.md)
- [Wizard activity](../../product/wizard-activity.md)
- [Product contract](../../product/product-contract.md)
- [Architecture](../../product/architecture.md)
- [Host support](../../user/host-support.md)
