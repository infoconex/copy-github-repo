---
title: "GitHub API Retry and Throttling Policy | CopyGitHubRepo"
description: "Understand CopyGitHubRepo's bounded retry policy for transient GitHub API reads, Retry-After handling, fail-fast errors, and why mutation requests are never automatically replayed."
---

# GitHub API throttling and transient retry policy

This document defines the retry contract used by CopyGitHubRepo for GitHub API calls made through the GitHub CLI. It is intentionally conservative: bounded automatic retries are allowed only for read-only API requests where repeating the request cannot duplicate repository mutations.

## Policy summary

| Request class | Automatic retry | Rationale |
| --- | --- | --- |
| Read-only API discovery and state reads | Yes, for recognized transient failures only | Repeating a read does not create duplicate repository state. |
| Optional read-only API probes | Yes, for recognized transient failures only | The same read safety applies; ordinary `404 Not Found` remains an absent-resource result rather than a retry condition. |
| Repository mutations | No | A failed response does not prove the mutation did not occur, so automatic retry could duplicate or obscure a partial change. |
| Git/Git LFS publication operations | Governed by their own execution/recovery behavior | These are not treated as generic GitHub API reads and must preserve partial-mutation evidence. |

## Retryable read failures

The read adapter recognizes a deliberately narrow set of transient conditions surfaced by `gh api`, including:

- HTTP `429`, `502`, `503`, and `504` responses;
- primary or secondary GitHub rate-limit messages;
- abuse-detection responses;
- connection resets or connection timeouts;
- temporary DNS/network failures;
- TLS handshake timeouts;
- server disconnects; and
- unexpected EOF conditions.

Ordinary authorization, authentication, validation, permission, and not-found failures are not automatically retried unless they also contain a recognized transient condition. In particular, a normal `403 Forbidden` fails immediately, and optional reads treat a normal `404 Not Found` as an absent resource.

## Bounded retry behavior

Read requests use at most three attempts by default. Between retryable failures, the adapter applies bounded exponential backoff with jitter. The default base delay is 250 milliseconds and the automatic backoff is capped at 2 seconds.

When GitHub supplies a numeric `Retry-After` delay in the surfaced diagnostic, that server guidance takes precedence over the locally calculated backoff. To avoid unexpectedly blocking an interactive or automation run for a long period, the adapter automatically waits only when the requested server delay is 60 seconds or less. If the server asks for a longer delay, the operation stops and reports the requested delay instead of retrying earlier than GitHub instructed.

A read that still fails after the bounded attempts reports how many attempts were made. Diagnostics are passed through the repository's diagnostic-protection path before being included in the operator-visible error.

## Mutation safety boundary

`Invoke-CgrGitHubApiMutation` deliberately does **not** use the read retry adapter. Even when a mutation receives a transient-looking error such as HTTP `503`, the tool does not automatically repeat it.

This distinction is required because a network or service failure after a mutation request is sent does not establish whether GitHub applied the change. Automatically replaying the request could create duplicate, conflicting, or misleading state. The caller must instead preserve the failure and recovery evidence, inspect the current repository state, and choose a deliberate next action.

This rule applies even when a specific mutation appears likely to be idempotent. Automatic mutation retry must not be added unless the operation's idempotency and response ambiguity are explicitly proven and covered by a separate product contract and tests.

## Operator guidance

When a read-only GitHub API operation fails after retry exhaustion:

1. Read the final error for the number of attempts and any server-provided retry guidance.
2. Check GitHub service availability and local network connectivity if the failure is transient.
3. For rate limiting, allow the GitHub-provided delay or reset window to pass before starting a new operation.
4. Re-authenticate only when the diagnostic indicates an authentication or permission problem; ordinary `401`/`403` failures are not transient retries.
5. If the failure happened before any mutation stage, correct the external condition and create/review a fresh plan when source state may have changed.

When a GitHub API mutation reports a failure:

1. Do **not** assume the mutation failed just because the response failed.
2. Do **not** blindly rerun the same mutation command.
3. Inspect the relevant source, destination, and archive repository identities and current state.
4. Preserve console output, structured recovery evidence, and the recorded failure stage.
5. Follow [`troubleshooting-recovery.md`](../user/troubleshooting-recovery.md) before deciding whether a fresh planned invocation or manual recovery is safest.

## Maintainer guidance

When adding or changing GitHub API calls:

- Route side-effect-free reads through the bounded read adapter unless there is a documented reason not to.
- Keep mutations on the non-retrying mutation adapter by default.
- Do not broaden the transient-error matcher merely to hide flaky failures; add a condition only when it is demonstrably transient and safe to retry.
- Keep retry counts and waits bounded so CI and interactive use cannot hang indefinitely.
- Honor server retry guidance rather than retrying earlier than requested.
- Add deterministic tests for any newly recognized retry condition and for the corresponding fail-fast boundary.
- Preserve protected, actionable diagnostics without exposing credentials or private values.
- Treat retries as resilience behavior, not as a substitute for recovery-state reporting after mutation.

## Verification evidence

The retry contract is exercised by `tests/unit/GitHubApiAdapters.Tests.ps1`. Coverage includes:

- one transient read failure followed by success;
- numeric `Retry-After` handling;
- refusal to retry earlier than excessive server guidance;
- fail-fast behavior for ordinary authorization failures;
- bounded retry exhaustion diagnostics;
- optional `404` absent-resource behavior; and
- the invariant that mutation failures are never automatically retried.

The implementation lives in `src/CopyGitHubRepo/Private/GitHub/Invoke-CgrGitHubApiReadRequest.ps1`, with the standard and optional read adapters routing through it. The mutation adapter remains intentionally separate.

## Related documentation

- Recovery and partial-mutation handling: [`troubleshooting-recovery.md`](../user/troubleshooting-recovery.md)
- Product safety contract: [`product-contract.md`](../product/product-contract.md)
- Architecture and external-tool boundaries: [`architecture.md`](../product/architecture.md)
- Non-functional requirements: [`non-functional-requirements.md`](../product/non-functional-requirements.md)
