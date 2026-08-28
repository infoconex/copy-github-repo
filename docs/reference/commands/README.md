---
title: "CopyGitHubRepo PowerShell Command Reference"
description: "Choose and use the four CopyGitHubRepo PowerShell commands for guided repository copying, scripted migration, repository discovery, and migration verification."
---

# Command reference

This directory is the user-facing reference for the four exported `CopyGitHubRepo` commands. For implementation architecture and engineering contracts, see the deeper documents linked from each command page.

| Command | Use it for | Changes GitHub state? |
| --- | --- | --- |
| [`Start-CopyGitHubRepositoryWizard`](Start-CopyGitHubRepositoryWizard.md) | Guided, interactive repository-copy workflow | Yes, only after plan review and confirmation |
| [`Copy-GitHubRepository`](Copy-GitHubRepository.md) | Scriptable planning and repository migration | Yes, except with `-PlanOnly` or `-WhatIf` |
| [`Get-GitHubRepository`](Get-GitHubRepository.md) | Repository discovery and metadata lookup | No |
| [`Test-GitHubRepositoryMigration`](Test-GitHubRepositoryMigration.md) | Read-only verification of a completed migration | No |

## Choosing a command

Use `Start-CopyGitHubRepositoryWizard` when a person wants a guided flow with source selection, safe defaults, plan review, Back/Next/Cancel navigation, and explicit execution confirmation.

Use `Copy-GitHubRepository` for scripts, automation, repeatable planning, explicit migration options, or when you need direct control over parameters such as content mode, visibility, reporting, or same-name replacement.

Use `Get-GitHubRepository` to inspect or search repositories without changing them.

Use `Test-GitHubRepositoryMigration` to independently verify Git content after a Snapshot or FullHistory migration.

## Deeper documentation

- [Product contract](../../product/product-contract.md) — supported product behavior and safety guarantees.
- [Command design](../../product/command-design.md) — engineering-level public command contracts.
- [Architecture](../../product/architecture.md) — layers, verification, recovery, Git/LFS, and settings-restoration design.
- [Wizard contract](../../product/wizard-contract.md) — detailed guided interaction contract.
- [Host support](../../user/host-support.md) — supported GitHub host boundary.
- [Installation security](../../security/installation-security.md) — installation trust model.
- [Versioning and releases](../../release/versioning.md) — release and publication contract.
