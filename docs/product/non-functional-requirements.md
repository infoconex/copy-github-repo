---
title: "CopyGitHubRepo Non-Functional Requirements and Resilience Boundaries"
description: "Review CopyGitHubRepo operational requirements for scale, disk and memory, API retries, native-command timeout and cancellation, interruption, concurrency, recovery, and cross-platform behavior."
---

# Non-functional requirements and operational boundaries

This document defines the current non-functional and resilience contract for Copy GitHub Repository. It complements [`product-contract.md`](product-contract.md), which remains authoritative for normative product behavior, and [`troubleshooting-recovery.md`](../user/troubleshooting-recovery.md), which remains authoritative for operator recovery.

The project deliberately avoids unsupported performance SLAs. Where a hard threshold has not been characterized and adopted, this document says so explicitly.

## Status vocabulary

Use these terms consistently:

- **Implemented** — behavior exists in source and is part of the current product contract.
- **Automatically tested** — deterministic automated tests protect the behavior.
- **Characterized** — behavior has been measured under a documented environment/fixture, but is not necessarily an enforceable product limit.
- **Accepted limitation** — behavior or evidence has a deliberate bounded limitation that is documented for release/readiness review.
- **Unsupported** — deliberately outside current product scope.

A repository being functionally supported does not imply that every possible repository size, history depth, LFS volume, network condition, or terminal-interruption behavior has a hard supported bound.

## Current operational contract

| Area | Current expectation | Evidence / status |
| --- | --- | --- |
| Host | GitHub.com only for v0.1.0 | Implemented and tested; other hosts fail closed. |
| PowerShell | PowerShell 7.4+ | Implemented baseline. |
| OS | Windows, macOS, Linux | Cross-platform Quality Gate coverage. |
| Git / `gh` | Required native prerequisites | Implemented prerequisite checks/usage. |
| Git LFS | Required for FullHistory and for Snapshot when approved content needs LFS objects | Implemented mode-specific behavior. |
| Planning | Planning and `-PlanOnly` do not mutate GitHub | Implemented/tested safety boundary. |
| Source drift | Approved source state is revalidated before first mutation and again in the copy workspace | Implemented/tested fail-closed behavior. |
| Pagination | Contract-required paginated GitHub results are collected completely | Automatically tested, including result sets larger than one page. |
| Large repository size | No hard repository-size or history-size maximum is claimed | Characterized; no universal hard limit or performance SLA adopted. |
| Branch/tag count | No hard supported maximum is claimed | Characterized; correctness remains the contract rather than a fixed count ceiling. |
| LFS dataset size | No hard supported maximum is claimed | Characterized; local disk amplification can be material. |
| Disk/temp capacity | A defensible known lower-bound shortage fails before GitHub mutation; additional headroom is advisory | Implemented/tested preflight with normal recovery semantics for later exhaustion. |
| Memory | No fixed memory ceiling is claimed | Peak child-process-tree memory remains an observational/characterization concern rather than a release limit. |
| Native process timeout/cancellation | The centralized native-process boundary supports explicit finite timeout and explicit cancellation, with process-tree termination and captured evidence | Implemented/tested. Default timeout remains `InfiniteTimeSpan`; no universal finite duration is promised. |
| API throttling/retry | Side-effect-free GitHub API reads use bounded transient retry/backoff; mutating GitHub API calls are deliberately not automatically replayed | Implemented and deterministically tested. |
| Retry/idempotency | Pre-mutation retries may proceed after a fresh plan; post-mutation retry requires inspection of preserved state/evidence | Implemented and deterministically tested. |
| Process interruption | Controlled cancellation is supported; raw Ctrl+C/session/hard-termination behavior remains host/OS dependent | Deterministic interruption contract implemented; no guarantee that abrupt termination can always create recovery evidence. |
| Concurrency | One intentional operation controls a source/destination/archive naming set at a time | No distributed lock or multi-writer coordination guarantee. |
| Automatic rollback | Not performed | Preservation-first recovery contract. |

## Performance philosophy

Performance is dominated by repository content, history shape, LFS volume, local disk/network performance, GitHub service behavior, authentication, and API latency. The project therefore does **not** promise a fixed completion time for repository copy operations.

Performance claims should be introduced only when they are:

1. measured with a documented fixture and environment;
2. repeatable enough to be meaningful;
3. tied to a user-visible decision or safety need; and
4. distinguishable from uncontrolled GitHub/network variability.

Variable timing measurements belong in characterization evidence rather than flaky blocking CI benchmarks. See [`scale-characterization.md`](../engineering/scale-characterization.md) for the current evidence and limitations.

## Resource exhaustion

Local workspace, clone, archive, and LFS operations can consume substantial disk space. Exact future disk consumption cannot always be predicted reliably from GitHub metadata alone.

Current contract:

- a defensible known lower-bound disk shortage is rejected before GitHub mutation;
- additional headroom may be reported as advisory rather than false precision;
- if capacity cannot be determined reliably, execution is not blocked merely because the value is unknown;
- a later local resource failure must not be described as successful execution;
- if a failure occurs after GitHub mutation begins, repositories are preserved and normal recovery semantics apply;
- users must not infer rollback merely because the local process failed.

## GitHub API pagination, throttling, and retries

Pagination is required wherever a complete result set is part of the contract. Rate limiting and transient service failures are handled separately from pagination.

Side-effect-free GitHub API reads route through a centralized bounded retry adapter:

- recognized transient read failures include HTTP `429`, `502`, `503`, `504`, GitHub primary/secondary rate-limit and abuse responses, and a narrow set of transient network/TLS/EOF conditions;
- ordinary authentication, authorization, validation, permission, and not-found failures fail fast unless they also contain a recognized transient condition;
- read requests use at most three attempts by default with bounded exponential backoff and jitter;
- numeric `Retry-After` guidance takes precedence when it is 60 seconds or less;
- a server-requested delay greater than 60 seconds is surfaced instead of retrying earlier than GitHub instructed;
- retry exhaustion reports the attempt count through protected diagnostics;
- optional reads retain normal `404 Not Found` as an absent-resource result;
- GitHub API mutations are never automatically replayed because a failed response does not prove the mutation did not occur.

The detailed authority is [`github-api-retry-policy.md`](../engineering/github-api-retry-policy.md). After any ambiguous post-mutation failure, inspect GitHub state and recovery evidence before retrying.

## Native commands, hangs, and cancellation

Git, GitHub CLI, and Git LFS are native external processes routed through `Invoke-CgrNativeCommand`. The centralized boundary supports:

- an explicit finite `TimeSpan` timeout when a caller has a defensible bound;
- an explicit `CancellationToken` for controlled cancellation;
- distinct `NativeCommandTimedOut` and `NativeCommandCancelled` terminating errors;
- best-effort termination of the full child process tree on timeout/cancellation;
- capture of stdout/stderr before the timeout/cancellation error is surfaced;
- unchanged ordinary exit-code behavior when the native process exits normally.

The default timeout remains `InfiniteTimeSpan`. Characterization has not established one finite duration that is defensible for clone, push, LFS, and GitHub CLI operations across supported repository sizes and network conditions. This is an accepted limitation, not a promise of universal hang prevention.

An explicit cancellation token is not the same as terminal Ctrl+C or hard process/session termination. Raw signal propagation and whether catch/finally/recovery reporting can complete are host/OS dependent. Absence of a recovery file after abrupt termination does not prove that no GitHub mutation occurred.

Timeout, cancellation, or interruption after GitHub mutation does **not** imply rollback. Inspect destination/archive state and recovery evidence before retrying.

## Retry and idempotency boundaries

### Before mutation

A corrected prerequisite, authentication, stale-plan, unsupported-host, or other pre-mutation failure can normally be retried by creating and reviewing a fresh plan. Existing safety checks still apply.

### After mutation begins

Do not simply repeat the original command without examining current state. Depending on the stage reached:

- an original destination may already have been archived;
- a replacement repository may already exist;
- Git content may be partially or fully published;
- content verification may have failed;
- settings/protection may be partially restored.

Repeated invocation must not silently reuse or overwrite archive/replacement identities. Recovery evidence and observed GitHub state are authoritative for diagnosis before retry.

## Concurrency

The orchestration model assumes one intentional operation controls a given source/destination/archive naming set at a time. Concurrent processes attempting to mutate the same logical repositories can invalidate plans and create naming/identity conflicts.

The product's stale-state and destination/archive checks fail closed where they observe conflicts, but the project does not claim distributed locking or multi-writer coordination. Avoid parallel copy/replacement attempts against the same repository names.

## Cross-platform considerations

The functional contract is intended to be equivalent on supported Windows, macOS, and Linux hosts, and the Quality Gate runs across all three.

Material OS differences may still exist in filesystem free-space reporting, child-process termination and signal propagation, credential-helper behavior, shell/console cancellation behavior, and filesystem performance. Any difference that changes mutation or recovery semantics is a product concern rather than merely an implementation detail.

## Resilience scenario inventory

| Scenario family | Expected observable safety behavior | Current treatment |
| --- | --- | --- |
| Paginated result set > one page | Complete contract-required results without silently truncating aggregate state | Automatically tested. |
| Large repository/history | Complete correctly or fail explicitly without corrupting source/preserved repositories | Characterized; no hard maximum/SLA adopted. |
| Large branch/tag count | Preserve/verify FullHistory refs or fail explicitly | Characterized; no fixed count ceiling adopted. |
| Large LFS volume | Transfer/verify required LFS or fail explicitly | Characterized; local disk amplification is disclosed. |
| Insufficient disk/temp | Reject a defensible known shortage before mutation; otherwise fail safely and preserve partial state | Implemented/tested. |
| API rate limiting | Retry bounded side-effect-free reads while never hiding ambiguous mutation behind unsafe replay | Implemented/tested. |
| Transient network/API failure | Retry only recognized bounded read failures; fail clearly otherwise and preserve mutation evidence | Implemented/tested for GitHub API reads. |
| Authentication expires mid-operation | Fail explicitly; mutation status determined by stage/evidence | Fail-fast auth behavior plus normal recovery model. |
| Native command hangs | Explicit finite timeout/cancellation is available and fails distinctly | Implemented/tested; no finite universal default claimed. |
| User/process interruption | Never imply automatic rollback; preserve evidence when the host/process remains capable | Deterministic contract implemented; raw signal behavior remains host/OS dependent. |
| Retry after pre-mutation failure | New plan/retry may proceed after the cause is corrected | Supported safety model. |
| Retry after partial mutation | Inspect state/evidence first; no blind replay | Implemented/tested. |
| Concurrent same-target operations | No distributed lock guarantee; conflicts fail closed when detected | Unsupported as a coordination pattern. |

Canonical scenario identifiers and their automated/live evidence mappings belong in [`product-model.md`](product-model.md) and the repository test traceability data.

## Release-readiness treatment

A non-functional limitation must be described directly and explicitly dispositioned for the exact release candidate. The current accepted boundaries include no universal finite native-command timeout, no hard repository-size maximum or completion-time SLA, host-dependent raw interruption behavior, and no automatic replay/rollback after ambiguous mutation.

A release candidate is not ready merely because these mechanisms exist in source. Exact-candidate automated evidence, any required live evidence, documentation, and release-specific accepted limitations must all be evaluated under [`release-readiness.md`](../release/release-readiness.md).

## Related authoritative material

- Product behavior and invariants: [`product-contract.md`](product-contract.md)
- User workflows/support matrix: [`user-guide.md`](../user/user-guide.md)
- Mutation/recovery state model: [`troubleshooting-recovery.md`](../user/troubleshooting-recovery.md)
- GitHub API retry policy: [`github-api-retry-policy.md`](../engineering/github-api-retry-policy.md)
- Scale characterization: [`scale-characterization.md`](../engineering/scale-characterization.md)
- Canonical capability/use-case/scenario IDs: [`product-model.md`](product-model.md)
- Architecture boundaries: [`architecture.md`](architecture.md)
- Release readiness: [`release-readiness.md`](../release/release-readiness.md)
