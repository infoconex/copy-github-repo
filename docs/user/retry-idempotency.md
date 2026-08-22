# Retry and idempotency

This document defines the operator and product contract for repeating repository-copy operations after failure, cancellation, interruption, or partial mutation.

The governing rule is simple: **the product does not blindly resume or replay a previously approved mutation plan after GitHub state may have changed.** A subsequent automated attempt must start from current repository state, produce a new plan, and preserve any repositories created or archived by an earlier attempt unless the operator deliberately chooses a supported replacement flow.

## Classification

| Operation or stage | Classification | Retry contract |
| --- | --- | --- |
| Prerequisite/authentication/host/input validation | Safely repeatable | Correct the condition and rerun. No GitHub mutation should have occurred. |
| Planning and source-state capture | Safely repeatable | Regenerate the plan. A plan is evidence, not a reservation of repository names. |
| Approved-source-state revalidation | Safely repeatable | If stale, create and review a new plan. Never force the old plan through. |
| Local resource preflight | Safely repeatable | Correct the local capacity condition and rerun/replan if source state may have changed. |
| Exact replacement confirmation | Safely repeatable | Re-enter only for the exact reviewed identities. A rejected confirmation performs no replacement mutation. |
| Create a new destination | Conditionally repeatable | A second fresh invocation must treat the existing destination as occupied; it must not silently reuse it. |
| Rename source/destination to an archive | Non-idempotent mutation | Once the rename succeeds, a repeated original plan is stale. Preserve and inspect the archive. |
| Create a replacement repository | Non-idempotent mutation | A repeated attempt must not silently reuse or overwrite the replacement. |
| Publish Snapshot or FullHistory content | Conditionally repeatable mutation | A failed push may have partially changed the destination. Do not replay automatically against the same destination without inspecting state and creating a new plan. |
| Restore ordinary settings | Conditionally repeatable mutation | Some settings may already have been applied. Recovery must start from verified destination state rather than assuming zero progress. |
| Restore protection | Conditionally repeatable mutation | Some controls may already exist while others failed. Inspect and reconcile deliberately. |
| Verification | Safely repeatable as an observation | Re-verification does not authorize replaying mutation stages. |
| Report/recovery evidence writing | Safely repeatable only as local output | A missing report does not imply GitHub mutation did not happen. Inspect GitHub state before retrying. |

## New-destination repeated invocation

A successful or partially successful first attempt may leave the destination repository name occupied. A fresh second invocation must therefore rediscover that state.

- If the destination is absent, a newly reviewed plan may create it.
- If the destination exists, the normal new-destination flow fails with `DestinationRepositoryAlreadyExists` rather than reusing or overwriting it.
- If the operator intentionally wants to preserve and replace that destination, they must choose the supported archive-and-replace flow with a new unused archive name and exact confirmation.

The presence of a destination from an earlier failed attempt is evidence of possible mutation, not permission to continue the old plan.

## Existing-destination archive-and-replace repeated invocation

Archive-and-replace is intentionally non-idempotent at the rename/create boundary.

- The archive name must be unused when the new plan is created.
- If that archive name already exists, planning fails with `ExistingDestinationArchiveAlreadyExists`.
- The existing archive is never assumed to belong to the current attempt and is never overwritten or silently reused.
- If an earlier attempt already archived the destination and created a replacement, preserve both repositories and use recovery evidence plus immutable repository IDs to understand which resource is which.

A subsequent automated replacement must use current repository state and a newly reviewed plan. If another replacement is desired, choose a new unused archive target rather than attempting to replay the original archive step.

## Same-name replacement repeated invocation

Same-name replacement changes the identity/name topology by moving the original repository to an archive and creating a new repository under the original name.

- The archive name must be unused during planning.
- If it already exists, planning fails with `ArchiveRepositoryAlreadyExists`.
- After the source has been renamed, the original approved plan is no longer valid against the original repository identity/name state.
- An existing archive is never silently reused, overwritten, renamed back, or deleted by retry logic.
- If a replacement repository now exists under the original name, treat it as independent current state and inspect immutable identities before further mutation.

## Recovery evidence and the next attempt

Recovery evidence informs the operator; it does not function as an automatic resume token.

Use it to establish:

1. the failure stage and completed stages;
2. source, archive, destination, and replacement names;
3. immutable repository IDs/node IDs when available;
4. whether content publication began or verified successfully;
5. whether ordinary settings or protection restoration completed;
6. whether an earlier attempt may have left partial Git/LFS content.

Then compare that evidence with current GitHub state. If any GitHub mutation occurred, generate a **new** plan for the recovery goal. Never edit or force a stale plan to fit current state.

## Safe retry procedure

### Failure before first GitHub mutation

1. Correct the prerequisite, authentication, source-state, confirmation, or local-resource problem.
2. If source state could have changed, generate a new plan.
3. Review the plan and execute normally.

This is the only class of failure that can generally be treated as a clean retry.

### Failure after archive/rename

1. Preserve the archive exactly as found.
2. Record its immutable identity and compare it with recovery evidence.
3. Inspect whether a replacement repository was created.
4. Do not rename the archive back automatically.
5. Define the desired recovery outcome and generate a new plan against current state.

### Failure after destination/replacement creation or publication

1. Preserve the destination/replacement and any archive.
2. Determine whether content is absent, partial, complete-but-unverified, or verified.
3. Determine settings/protection status if content verified.
4. Do not assume a second invocation can continue where the first stopped.
5. Use a new destination or an explicitly reviewed replacement plan as appropriate.

## Duplicate-attempt invariants

The following are product invariants:

- no existing repository is overwritten merely because its name matches a previous destination;
- no existing archive is silently reused;
- archive/replacement identity must be re-established from current GitHub state;
- a previously approved plan is not an automatic resume token;
- `-Force` and `-Confirm:$false` do not bypass exact replacement confirmation or occupied-name safeguards;
- recovery remains preservation-first; the tool does not automatically delete repositories or roll names back after partial mutation.

## Relationship to API-level retries

This contract is distinct from the bounded retry behavior for individual read-only GitHub API requests. See [`github-api-retry-policy.md`](../engineering/github-api-retry-policy.md).

Automatic API retries do not make repository-copy mutation stages idempotent. Mutation requests are not automatically replayed merely because a service/network failure occurred.

## Related documentation

- [`troubleshooting-recovery.md`](troubleshooting-recovery.md) — failure-stage diagnosis and preservation-first recovery.
- [`product-contract.md`](../product/product-contract.md) — normative safety invariants.
- [`github-api-retry-policy.md`](../engineering/github-api-retry-policy.md) — bounded retries for GitHub API reads and mutation retry boundaries.
- [`local-resource-preflight.md`](local-resource-preflight.md) — pre-mutation local-capacity behavior.
