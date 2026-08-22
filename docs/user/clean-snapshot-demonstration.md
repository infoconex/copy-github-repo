# Clean Snapshot demonstration

The repository includes a controlled live demonstration harness at:

```text
tests/e2e/Invoke-CleanSnapshotDemonstration.ps1
```

It creates a temporary public source repository with deliberately visible development history and then publishes that source to a clean Snapshot destination using the real module.

## What the source fixture contains

The source is created with:

- multiple commits on `main`;
- a `feature/history-only` branch;
- a `v0.0.1` tag;
- description, homepage, topics, Issues, and Wiki settings;
- an issue assigned to a demonstration milestone;
- an open pull request from the historical feature branch;
- an LFS-tracked fixture when Git LFS is available, unless `-SkipLfs` is supplied.

No secrets or sensitive values are used.

## What the harness proves

After running the real default `Snapshot` flow, the harness verifies observable before/after facts:

- source commit count is greater than one;
- destination commit count is exactly one;
- source default-branch tree SHA equals destination tree SHA;
- the historical feature branch is absent from the destination;
- source tags are absent from the destination;
- destination issue count is zero;
- destination pull-request count is zero;
- destination milestone count is zero;
- supported settings restoration completed;
- repository-protection restoration completed or safely reported;
- Snapshot provenance evidence was recorded;
- the completion report was generated.

The demonstration intentionally tests the product's core proposition: **same current project tree, new clean Git history, no migrated GitHub development records**.

## Run it

From the repository root:

```powershell
./tests/e2e/Invoke-CleanSnapshotDemonstration.ps1
```

Use another owner when needed:

```powershell
./tests/e2e/Invoke-CleanSnapshotDemonstration.ps1 -Owner your-account
```

Skip LFS deliberately:

```powershell
./tests/e2e/Invoke-CleanSnapshotDemonstration.ps1 -SkipLfs
```

Keep the temporary repositories for manual inspection:

```powershell
./tests/e2e/Invoke-CleanSnapshotDemonstration.ps1 -KeepRepositories
```

## Cleanup safety

By default the harness deletes only repositories whose names start with its unique run-specific prefix. Before creating any repository it proves that the authenticated GitHub token advertises the `delete_repo` scope.

If that scope cannot be proven, no repositories are created unless `-KeepRepositories` is explicitly supplied. With `-KeepRepositories`, cleanup is deliberately left to the operator and the created repository names are printed.

The production module itself does not adopt this test-harness cleanup behavior; automatic repository deletion remains outside the normal migration/recovery contract.

## Relationship to the manual guide

[Manually Creating a Clean GitHub Repository Snapshot](manual-process.md) explains the underlying Git and GitHub operations. This harness supplies a repeatable live before/after fixture that can be used to validate those documented invariants against the real module.
