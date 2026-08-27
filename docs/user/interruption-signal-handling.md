---
title: "PowerShell Ctrl+C and Interruption Handling | CopyGitHubRepo"
description: "Understand how CopyGitHubRepo handles cancellation, Ctrl+C, process termination, partial GitHub mutation, recovery evidence, and cross-platform signal behavior."
---

# Interruption and signal-handling contract

This document defines how Copy GitHub Repository treats controlled cancellation, terminal interruption, and process/session termination across Windows, macOS, and Linux.

The contract is intentionally preservation-first. Interruption never implies rollback, and the product does not claim that all host/process termination mechanisms can be normalized across operating systems or shells.

## Interruption classes

### Controlled native-command cancellation

`Invoke-CgrNativeCommand` accepts an explicit `CancellationToken`. When that token is cancelled while a native command is running, the helper:

- distinguishes cancellation from timeout;
- makes a best-effort attempt to terminate the native child process tree;
- captures stdout/stderr that was available before termination; and
- throws a terminating `NativeCommandCancelled` error.

This is the only interruption class for which the product currently provides an explicit programmatic cancellation mechanism.

A cancelled native command may already have produced local or remote side effects before cancellation was observed. Killing the process tree therefore does not prove that GitHub state is unchanged.

### Terminal Ctrl+C / pipeline stop

Ctrl+C is mediated by the active PowerShell host, terminal, and operating system. Depending on that combination, PowerShell may stop the pipeline, a native child process may receive a signal, the host may terminate the child, or control may not return to the repository-copy catch path in time to write recovery evidence.

The product therefore does **not** guarantee that Ctrl+C is equivalent to the explicit `CancellationToken` path, and it does not promise identical signal propagation on Windows, macOS, and Linux.

When PowerShell remains alive and the terminating interruption reaches an orchestration `catch` block after mutation has begun, the normal recovery-report path is attempted before the interruption is rethrown. When the host stops the pipeline without allowing that code to run, no recovery-report write can be guaranteed.

### Session or process termination

Hard termination of the PowerShell process, terminal session, machine, runner, or container can prevent all cleanup and recovery-report code from running. Examples include force-kill, terminal/session loss, host shutdown, and abrupt runner termination.

No durable recovery record is guaranteed for this class of interruption. Existing GitHub state is authoritative and must be inspected before any retry.

## Mutation boundary

The interruption response depends on whether GitHub mutation has begun.

### Before mutation

Source-state validation, local resource preflight, confirmation, and other pre-mutation checks occur before repository creation/rename/publish operations.

If interruption occurs before the first GitHub mutation:

- no repository-copy rollback is needed because the copy operation has not mutated GitHub;
- no mutation recovery report is expected; and
- the operator may create/review a fresh plan and retry after resolving the interruption cause.

### After mutation begins

After the first repository create, rename/archive, publish, settings, or protection mutation, interruption is an ambiguous partial-operation state until verified.

The product contract is:

- never claim automatic rollback;
- never assume that an interrupted native command made no remote change;
- preserve any source/archive/replacement repository state that exists;
- attempt to write the normal recovery report when PowerShell regains control and the orchestration catch path can execute;
- if no recovery report exists, inspect GitHub repository names, identities, content, settings, and protection before retrying; and
- follow the retry/idempotency contract rather than blindly replaying the original command.

## Stage-specific operator expectations

| Interruption point | What may already exist | Required response |
| --- | --- | --- |
| Before first mutation | No copy-created GitHub mutation | Re-plan/retry after the cause is resolved. |
| Destination creation | New destination repository | Inspect destination identity/state; use recovery evidence if present. |
| Archive/rename | Original repository may already have its archive name | Do not recreate/reuse archive identity blindly; inspect archive and replacement names first. |
| Content publish | Destination may contain partial or complete Git/LFS state | Verify destination content before any retry. |
| Settings restoration | Content may already be verified; settings may be partial | Inspect settings and recovery evidence; do not republish content solely because settings were interrupted. |
| Protection restoration | Content/settings may already be complete; protection may be partial | Inspect protection separately before retrying configuration work. |
| Completion report write | Migration may already be complete even though local reporting was interrupted | Verify GitHub state before treating the migration as failed. |

## Cross-platform limits

The supported operating systems share the same preservation and recovery semantics, but these low-level behaviors are explicitly **not** normalized:

- which signal a terminal sends to PowerShell or its native descendants;
- whether a native process receives the terminal signal directly;
- the timing with which PowerShell surfaces a pipeline stop;
- whether a host permits `catch`/`finally` blocks to finish during shutdown; and
- behavior of credential helpers or other descendant processes during abrupt termination.

These differences are not used as evidence of rollback or successful cleanup.

## Testing strategy

Deterministic CI tests cover the contract where it can be controlled reliably:

- explicit `CancellationToken` cancellation is distinct from timeout and terminates the controlled native-command path;
- cancellation/failure before mutation does not create a destination or emit post-mutation recovery evidence;
- a terminating cancellation after destination creation flows through the normal recovery-report path when PowerShell remains capable of executing it; and
- a terminating cancellation after same-name archive mutation likewise attempts same-name recovery reporting.

The Quality Gate runs these tests on Windows, macOS, and Linux. CI does not synthesize raw terminal Ctrl+C or hard process termination as a blocking test because host signal delivery is not deterministic enough to serve as a portable product assertion.

## Recovery and retry

After any post-mutation interruption, use [`troubleshooting-recovery.md`](troubleshooting-recovery.md) to identify current state and [`retry-idempotency.md`](retry-idempotency.md) to decide whether and how to make another attempt.

Absence of a recovery file after Ctrl+C or hard termination is not evidence that no mutation occurred.
