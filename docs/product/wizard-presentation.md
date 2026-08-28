---
title: "PowerShell Wizard Presentation and Accessibility | CopyGitHubRepo"
description: "Understand CopyGitHubRepo wizard styling, semantic status presentation, NO_COLOR and redirected-output fallbacks, completion summaries, and structured-output separation."
---

# Wizard presentation contract

The guided repository-copy wizard is a presentation/orchestration layer over the deterministic public commands. Presentation must never change migration semantics or add terminal decoration to structured command results.

## Semantic hierarchy

Wizard output uses semantic styles rather than raw color calls at individual call sites:

- **Heading**: bright cyan for the wizard title, section headings, the `Repository copy plan`, `Confirm repository copy`, and help headings.
- **Prompt**: cyan for active input prompts.
- **Normal**: the terminal foreground for primary explanatory text and unselected menu items.
- **Hint**: gray and italic when styling is available, for navigation affordances and trailing Enter/default values. Plain text is used when styling is unavailable.
- **Muted**: dim terminal text for secondary explanatory guidance.
- **Value**: a restrained accent for important repository names, archive names, and exact confirmation values.
- **Success**: green for completed or verified states.
- **Warning**: yellow for warnings and destructive confirmations.
- **Error**: red only for actual failures.

Color is deliberately sparse. Unselected repository-menu entries remain neutral, and the first entry must not appear selected merely because it is first.

The shared presentation helpers own `$PSStyle` usage. Wizard orchestration and migration logic request semantic styles instead of selecting terminal colors directly. Prompt helpers also own the ordering and styling of `[? help]`, Back/Cancel/context actions, and the trailing effective value selected by Enter. A constrained option keeps its `(default)` marker beside the option as a separate scanning aid.

## Capability and accessibility rules

Presentation must remain understandable without styling. `NO_COLOR`, PowerShell plain-text output rendering, and redirected output disable ANSI styling. Color is never the sole carrier of meaning; important states retain words and stable status symbols.

Terminal escape sequences and cursor-control sequences belong only in interactive presentation. Structured `Copy-GitHubRepository`, `Get-GitHubRepository`, and `Test-GitHubRepositoryMigration` results remain ordinary PowerShell objects suitable for assignment, filtering, serialization, and automation.

## Completion output

Verification, supported-settings, repository-protection, and replacement-identity outcomes are presented before the final completion declaration. `Repository copy complete` means the reviewed operation has finished without a warning/failure outcome; otherwise the final heading indicates warnings rather than presenting an unconditional success declaration.

Repository-protection presentation distinguishes actual restoration from a no-op. A successful result with no transferable protection is reported as `No transferable repository protection to restore.` It must not be described as restoration. Skipped/unsupported, partial, and failed states also have distinct wording/status treatment.

A successful `Start-CopyGitHubRepositoryWizard` session ends with a concise human-facing summary rather than emitting the full nested migration execution object to the host. The summary should surface, when available:

- destination repository and URL;
- archive repository for replacement workflows;
- content mode;
- content verification outcome;
- settings and repository-protection outcome or explicit skip/no-op reason;
- Snapshot source commit/tree and destination root-commit evidence;
- report path when a report was requested.

The complete structured execution result remains available from `Copy-GitHubRepository`. Tests may exercise the wizard's private orchestration result, but the public interactive wizard must not append the raw object after the completion summary.
