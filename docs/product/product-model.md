# Product journeys and behavioral model

This document provides the product/program structure that connects people and goals to the authoritative behavior defined in [`product-contract.md`](product-contract.md).

It does **not** redefine product behavior. `docs/product/product-contract.md` remains authoritative for supported scope, invariants, exclusions, safety semantics, verification, and recovery. Command syntax remains authoritative in [`docs/reference/commands/`](../reference/commands/README.md) and native PowerShell help.

The traceability model is:

`Persona -> Journey -> Capability -> Use Case -> Product Requirement -> Acceptance Criteria -> Behavioral Scenario -> Automated Test -> Live Validation -> Release Evidence`

Later quality and release work can attach test and release evidence to the stable IDs defined here without duplicating the product contract.

## Product intent for v0.1.0

### Problem

A repository owner may need to publish a developed GitHub repository as a clean repository whose visible Git history begins with the approved current state, or make a history-preserving copy, without manually reconstructing repository content, settings, safety checks, and verification steps.

### Intended outcome

The operator can deliberately choose clean `Snapshot` publication or `FullHistory` copy, review the exact planned source state before mutation, preserve an existing repository when replacement is required, verify the resulting content/configuration, and retain usable provenance or recovery evidence.

### Goals

- Make clean current-state publication the safe, understandable default.
- Provide an explicit history-preserving alternative.
- Bind mutation to reviewed immutable source-state evidence and fail closed on drift.
- Preserve existing repositories rather than silently overwrite or delete them.
- Make planning, mutation, verification, and recovery behavior observable.
- Support both guided human use and deterministic automation.
- Provide sufficient product, quality, security, and release evidence for a defensible v0.1.0 release decision.

### Non-goals for v0.1.0

- Repository deletion or silent destructive overwrite.
- Copying GitHub historical/operational records such as pull requests, issues, workflow-run history, stars, watchers, forks, or traffic history.
- Migrating secret values, webhooks, deploy keys, environments, collaborator/team access, packages, or deployments.
- Restoring GitHub Pages or enabling GitHub Actions after migration.
- Supporting GitHub Enterprise Server or non-GitHub.com hosts.
- Providing adoption telemetry or usage analytics.
- Promising arbitrary performance or scale SLAs before the non-functional characterization work is complete.

### Evidence-based release success criteria

For v0.1.0, product success means that the required release capabilities are implemented, documented, automatically tested where practical, have controlled live-validation capability for behaviors that require GitHub, and have actual release-candidate live evidence where the release-readiness process requires it. Safety-critical failure paths must be specified as deliberately as success paths.

[`release-readiness.md`](../release/release-readiness.md) determines whether those conditions are satisfied for one exact release candidate. An E2E harness existing is not the same as that release candidate having been live-validated.

## Personas and primary journeys

The seven primary documentation personas are defined in [`documentation-strategy.md`](../engineering/documentation-strategy.md). Their product-facing journeys are summarized here so capabilities can be traced across audiences.

| Persona | Primary journey | Product question |
| --- | --- | --- |
| User / Operator | Evaluate -> choose mode/scenario -> plan -> execute -> verify -> recover/support | Can I accomplish my repository-copy goal safely and understand what happened? |
| Contributor / Maintainer | Understand behavior -> change -> validate -> document -> release/support | What product behavior must remain true when I change the implementation? |
| Quality Engineer | Requirement -> scenario -> automated evidence -> live evidence -> release evidence | How do we know the advertised behavior and failure semantics are protected? |
| Architect / Engineering Reviewer | Capability -> boundaries/state -> invariants -> design decisions | Does the design preserve the product's safety and verification model? |
| Security Reviewer | Threat/trust boundary -> control -> failure behavior -> evidence/residual risk | Can privileged mutation and supply-chain behavior be assessed independently? |
| Governance / Compliance Reviewer | Scope/dependencies/data/permissions -> assurance evidence -> support | Is the product's actual operating and distribution posture understandable? |
| Product / Program Manager | Intent -> capability -> use case -> scenario -> dependency -> readiness/go-no-go | Is the release complete, coherent, evidenced, and deliberately scoped? |

Industry Expert remains a cross-cutting quality lens rather than another persona.

## Capability catalog

Capability IDs are stable traceability handles. They organize the product; they are not separate implementation components.

| ID | Capability | Primary product-contract authority |
| --- | --- | --- |
| `CAP-DISC` | Repository discovery and GitHub authentication boundary | Public command contract; host/release contract |
| `CAP-PLAN` | Immutable source-state planning and preview | Immutable approved source state |
| `CAP-SNAP` | Snapshot clean publication | Canonical content terminology; verification |
| `CAP-HIST` | FullHistory copy | Canonical content terminology; verification |
| `CAP-DEST` | New-destination and existing-destination safety | Destination and replacement safety |
| `CAP-SAME` | Same-name archive-and-replace | Destination and replacement safety |
| `CAP-LFS` | Git LFS planning, transfer, and verification | Immutable approved source state; verification |
| `CAP-SET` | Supported ordinary repository-settings restoration | Supported repository configuration |
| `CAP-PROT` | Transferable repository-protection restoration/skipped semantics | Supported repository configuration |
| `CAP-WIZ` | Guided wizard planning/review/execution/cancellation/help | Guided wizard |
| `CAP-AUTO` | Deterministic scripted/non-interactive operation | Public command contract; destination safety |
| `CAP-VERIFY` | Standalone and execution-integrated verification | Verification |
| `CAP-EVID` | Provenance, structured reporting, and recovery evidence | Provenance and recovery |
| `CAP-DIST` | Installation/update/uninstall and stable distribution contract | Host/release contract plus installation/versioning authorities |
| `CAP-REL` | Release packaging/publication integrity and immutable release boundary | Host and release contract plus versioning/publishing authorities |

## Use-case catalog

Use-case IDs represent user/program outcomes. A use case may rely on several capabilities and several product-contract requirements.

| ID | Actor / goal | Preconditions | Capabilities | Mutation / evidence expectation |
| --- | --- | --- | --- | --- |
| `UC-DISC-01` | Operator discovers/selects an accessible GitHub.com source repository | PowerShell/Git/`gh`; authenticated GitHub CLI | `CAP-DISC` | Read-only; repository identity/metadata returned |
| `UC-PLAN-01` | Operator previews a Snapshot or FullHistory operation before mutation | Valid source/destination/options | `CAP-PLAN`, `CAP-AUTO` | No mutation; immutable approved source evidence and plan returned |
| `UC-SNAP-NEW` | Operator publishes current approved source state to a new destination with one unrelated root commit | Fresh destination name; unchanged approved source | `CAP-PLAN`, `CAP-SNAP`, `CAP-DEST`, `CAP-LFS`, `CAP-VERIFY`, `CAP-EVID` | Destination created/published; verification/provenance returned |
| `UC-HIST-NEW` | Operator copies approved ordinary Git history to a new destination | Fresh destination; unchanged approved source | `CAP-PLAN`, `CAP-HIST`, `CAP-DEST`, `CAP-LFS`, `CAP-VERIFY`, `CAP-EVID` | Destination created; branch/tag/history/LFS verification returned |
| `UC-DEST-REPLACE` | Operator archives an existing different destination and creates a replacement | Explicit archive-and-replace path and exact confirmation | `CAP-PLAN`, `CAP-DEST`, content-mode capability, `CAP-VERIFY`, `CAP-EVID` | Existing destination preserved under archive identity before replacement |
| `UC-SAME-REPLACE` | Operator republishes under the source's current name while preserving the original as an archive | Same-name flow; unused archive; exact confirmation | `CAP-PLAN`, `CAP-SAME`, content-mode capability, `CAP-VERIFY`, `CAP-EVID` | Original source renamed/preserved; replacement receives distinct identity |
| `UC-VIS-01` | Operator changes destination visibility deliberately | Valid visibility target; explicit force acknowledgement for mutation | `CAP-DEST`, `CAP-AUTO` | Visibility change is explicit, never implicit |
| `UC-SET-01` | Operator restores supported ordinary settings after content verification | Content verification succeeded; settings not skipped | `CAP-SET`, `CAP-VERIFY` | Supported settings restored differentially and read back |
| `UC-PROT-01` | Operator restores transferable protection without weakening semantics | Content/settings phase complete; protection transferable | `CAP-PROT`, `CAP-VERIFY` | Transferable protection restored/read back; unsupported policy reported as skipped |
| `UC-WIZ-01` | Human operator completes the guided flow | Interactive PowerShell host; authenticated prerequisites | `CAP-WIZ`, `CAP-DISC`, `CAP-PLAN`, relevant execution capabilities | Real plan reviewed; explicit execute decision before mutation |
| `UC-AUTO-01` | Automation performs a deterministic non-interactive copy | Complete explicit inputs; required force/confirmation semantics | `CAP-AUTO`, `CAP-PLAN`, relevant execution capabilities | Structured result/evidence; no hidden interactive dependency |
| `UC-VERIFY-01` | Caller independently compares current source and destination state | Both repositories accessible | `CAP-VERIFY` | Read-only structured comparison result |
| `UC-RECOVER-01` | Operator understands what survived after a post-mutation failure | Mutation started and operation terminated | `CAP-EVID`, relevant mutation capability | Durable recovery evidence when possible; no automatic delete/rename-back |
| `UC-DIST-01` | User installs, updates, or removes the module through a supported distribution path | Appropriate package/release exists for requested path | `CAP-DIST` | Local module state changes only; trust boundary documented |
| `UC-REL-01` | Maintainer publishes an immutable stable release | Exact release candidate has required readiness evidence | `CAP-REL`, `CAP-DIST` | Tag/package/release publication follows version/integrity contract |

## Behavioral scenario taxonomy

Scenario IDs are intentionally concise. [`user-guide.md`](../user/user-guide.md) and [`troubleshooting-recovery.md`](../user/troubleshooting-recovery.md) translate them into user-facing scenario and recovery guidance, while [`quality-strategy.md`](../engineering/quality-strategy.md) attaches Unit/Integration/Contract/E2E/live-release evidence.

Scenario categories:

- `HAPPY` — expected successful outcome.
- `VALIDATION` — invalid input, unsupported scope, or unmet precondition before mutation.
- `AUTH` — authentication/authorization/prerequisite failure.
- `SAFETY` — exact confirmation, identity, stale-state, or destructive-operation guard.
- `EDGE` — meaningful boundary behavior such as empty repositories or LFS/no-LFS cases.
- `PARTIAL` — failure after mutation has begun.
- `VERIFY` — content/settings/protection verification failure.
- `RECOVERY` — preservation/evidence behavior after failure.
- `NOOP` — `-PlanOnly`, `-WhatIf`, cancellation, or rejected execution with no mutation.
- `AUTOMATION` — non-interactive behavior.
- `RESILIENCE` — scale, network, rate-limit, timeout, cancellation, retry, interruption, and local-resource behavior.

## High-value behavioral scenarios

### Planning and stale-state safety

#### `SCN-PLAN-HAPPY-01` — approved plan captures executable source state

**Given** a supported GitHub.com source and valid options, **when** planning completes, **then** the plan records the content-mode-specific immutable approved source evidence required by the product contract, **and** no GitHub mutation occurs.

Use cases: `UC-PLAN-01`, `UC-SNAP-NEW`, `UC-HIST-NEW`, `UC-DEST-REPLACE`, `UC-SAME-REPLACE`.

#### `SCN-PLAN-SAFETY-01` — stale plan fails closed

**Given** an approved plan whose source state changes before the first GitHub mutation, **when** execution revalidates the source, **then** execution terminates with the stale-state outcome defined by the product contract, **and** destination creation/rename does not proceed from that plan.

Mutation expectation: none from the stale plan.

#### `SCN-PLAN-NOOP-01` — plan-only and WhatIf do not mutate

**Given** otherwise valid mutating inputs, **when** `-PlanOnly` or `-WhatIf` is used, **then** the operation produces preview/ShouldProcess behavior without creating, renaming, publishing, deleting, or restoring destination resources.

### Snapshot publication

#### `SCN-SNAP-HAPPY-01` — new-destination Snapshot publication

**Given** an approved unchanged Snapshot plan and unused destination, **when** execution succeeds, **then** the approved default-branch tree is published as exactly one unrelated root commit, required Snapshot LFS transfer succeeds, and destination content verification/provenance is returned.

Use case: `UC-SNAP-NEW`.

#### `SCN-SNAP-VERIFY-01` — Snapshot mismatch is not reported as success

**Given** Snapshot publication has occurred but the destination tree/root-commit contract or required LFS verification does not match approved evidence, **when** verification runs, **then** the operation does not report successful migration, **and** recovery/evidence semantics reflect the stage reached.

Mutation expectation: destination may already exist and contain published content.

### FullHistory copy

#### `SCN-HIST-HAPPY-01` — new-destination FullHistory copy

**Given** an approved unchanged FullHistory plan and unused destination, **when** execution succeeds, **then** approved ordinary branches/tags/reachable history/default branch and reachable required LFS objects are preserved and verified according to the product contract.

Use case: `UC-HIST-NEW`.

#### `SCN-HIST-VERIFY-01` — missing/mismatched history is a verification failure

**Given** FullHistory publication has occurred, **when** branch/tag targets, reachable commit count, branch-tip trees, default branch, or required LFS evidence does not match the approved state, **then** the copy is not reported as verified success.

### Destination preservation and replacement

#### `SCN-DEST-VALIDATION-01` — existing destination is not silently overwritten

**Given** a different destination already exists, **when** the operator has not selected the explicit archive-and-replace flow, **then** execution rejects the destination before destructive replacement behavior.

Mutation expectation: existing destination remains unchanged by replacement behavior.

#### `SCN-DEST-SAFETY-01` — exact replacement confirmation cannot be bypassed

**Given** an archive-and-replace operation, **when** exact case-sensitive confirmation is absent or incorrect, **then** replacement does not proceed; neither `-Force` nor `-Confirm:$false` bypasses the exact confirmation contract.

#### `SCN-DEST-HAPPY-01` — existing destination is archived before replacement

**Given** an approved unchanged source plan, existing destination, unused archive name, and valid exact confirmation, **when** replacement executes, **then** the existing destination is renamed to the archive, archive identity continuity is verified, and only then is the replacement created.

Use case: `UC-DEST-REPLACE`.

#### `SCN-DEST-PARTIAL-01` — archive succeeds but later replacement fails

**Given** the existing destination was successfully archived and a later replacement stage fails, **when** the operation terminates, **then** the archived destination is preserved, recovery evidence identifies completed/failed stages and known identities, and the tool does not automatically rename back or delete repositories.

### Same-name replacement

#### `SCN-SAME-HAPPY-01` — original identity is preserved under archive name

**Given** a same-name operation with valid exact confirmation and unchanged approved source state, **when** execution proceeds, **then** the original repository is archived, archive identity continuity is verified against the approved source identity where available, and the replacement created under the original name receives a distinct immutable repository identity.

Use case: `UC-SAME-REPLACE`.

#### `SCN-SAME-SAFETY-01` — source/archive identity mismatch fails closed

**Given** the source/archive identity cannot be shown to be the preserved approved repository where immutable identity evidence is available, **when** the same-name flow reaches that safety boundary, **then** replacement publication does not continue as successful.

### Git LFS

#### `SCN-LFS-HAPPY-01` — required LFS content is available and transferred

**Given** approved source evidence identifies required LFS content for the selected mode, **when** publication and verification succeed, **then** required reachable LFS objects are available at the destination according to that mode's contract.

#### `SCN-LFS-VALIDATION-01` — unavailable required LFS content blocks false success

**Given** required source LFS objects cannot be shown available/transferred as required, **when** planning/execution/verification reaches the applicable boundary, **then** the operation does not claim successful verified publication.

### Settings and protection

#### `SCN-SET-HAPPY-01` — ordinary settings follow content verification

**Given** destination content has verified successfully and settings restoration is enabled, **when** ordinary settings restoration runs, **then** supported settings are restored differentially and read back for verification.

Use case: `UC-SET-01`.

#### `SCN-SET-PARTIAL-01` — settings failure preserves verified content

**Given** content verification succeeded and a later settings restoration/readback step fails, **when** the operation terminates, **then** the verified destination content is not automatically deleted or rolled back, and recovery evidence identifies the failure stage.

#### `SCN-PROT-HAPPY-01` — transferable protection is restored last

**Given** prior applicable stages succeeded, **when** protection restoration runs, **then** transferable repository-level rulesets/default-branch protection are restored/read back after ordinary settings, without weakening security semantics for portability.

#### `SCN-PROT-EDGE-01` — non-transferable protection is explicitly skipped/unsupported

**Given** a protection rule is identity-, deployment-, integration-, or organization-policy-bound and cannot be reproduced safely, **when** restoration evaluates it, **then** it is reported as skipped/unsupported rather than silently weakened or represented as restored.

### Wizard and cancellation

#### `SCN-WIZ-HAPPY-01` — wizard executes the reviewed plan

**Given** the operator completes guided selections and reviews the real plan produced by `Copy-GitHubRepository -PlanOnly`, **when** the operator chooses Execute and source state remains valid, **then** the wizard applies that reviewed plan through the shared execution boundary rather than reconstructing an equivalent command from presentation state.

Use case: `UC-WIZ-01`.

#### `SCN-WIZ-NOOP-01` — cancellation before mutation changes nothing

**Given** the wizard is still before the mutation boundary, **when** the operator cancels, **then** cancellation is a structured no-change outcome.

#### `SCN-WIZ-SAFETY-01` — stale reviewed plan returns to review

**Given** the source changes after wizard plan review but before mutation, **when** execution detects the stale plan, **then** the wizard explains the stale state, regenerates/requires review of new planned state, and does not execute the stale plan.

### Automation and prerequisite failures

#### `SCN-AUTO-AUTOMATION-01` — non-interactive mutation is explicit

**Given** automation requests mutation without the required non-interactive acknowledgement/force semantics, **when** execution validates authority, **then** it fails rather than prompting unpredictably or mutating implicitly.

Use case: `UC-AUTO-01`.

#### `SCN-DISC-AUTH-01` — authentication/prerequisite failure occurs before mutation

**Given** GitHub CLI authentication or a required native prerequisite is unavailable for the requested operation, **when** the product performs discovery/preflight, **then** it returns an actionable failure before repository mutation begins.

#### `SCN-HOST-VALIDATION-01` — unsupported host fails closed

**Given** a repository host other than `github.com`, **when** a v0.1.0 operation is requested, **then** the operation fails closed before mutation.

### Verification, provenance, and recovery

#### `SCN-VERIFY-HAPPY-01` — standalone verification is read-only

**Given** accessible source and destination repositories, **when** `Test-GitHubRepositoryMigration` is invoked, **then** it compares the requested current repository states and returns structured verification results without mutation.

Use case: `UC-VERIFY-01`.

#### `SCN-EVID-HAPPY-01` — successful Snapshot provides external provenance

**Given** Snapshot intentionally severs Git ancestry, **when** execution succeeds, **then** the result exposes approved source state, actual copied evidence, destination root/tree identities, relevant repository identities, time, and verification outcome outside the clean destination Git graph.

#### `SCN-RECOVER-RECOVERY-01` — post-mutation failure retains recovery information

**Given** a terminating failure occurs after mutation begins, **when** recovery handling runs, **then** it records the failure stage, completed steps, known original/archive/replacement identities, and available planned-versus-copied evidence when possible, without automatically deleting or renaming repositories back.

Use case: `UC-RECOVER-01`.

### Resilience scenarios

The following scenarios are canonical `SCN-*` product scenarios. They replace the earlier separate resilience inventory as the traceability authority. Detailed limits and operational wording remain in [`non-functional-requirements.md`](non-functional-requirements.md), [`github-api-retry-policy.md`](../engineering/github-api-retry-policy.md), [`retry-idempotency.md`](../user/retry-idempotency.md), [`scale-characterization.md`](../engineering/scale-characterization.md), and [`interruption-signal-handling.md`](../user/interruption-signal-handling.md).

| Scenario | Observable behavior | Mutation boundary | Retained evidence | Safe retry / recovery | Automated / live evidence |
| --- | --- | --- | --- | --- | --- |
| `SCN-API-RESILIENCE-01` — transient GitHub API read failure | Recognized side-effect-free read failures use bounded retry/backoff; non-transient failures fail clearly; mutation calls are not automatically replayed | Read-only adapter activity; no new mutation from the retry mechanism | Final error plus bounded-attempt diagnostics; normal response on eventual success | Safe automatic retry is limited to recognized reads; ambiguous mutation failures require state inspection | `GitHubApiAdapters.Tests.ps1`; cross-platform Quality Gate; live service degradation is not a deterministic release assertion |
| `SCN-NATIVE-RESILIENCE-01` — native timeout or controlled cancellation | Explicit timeout/cancellation produces distinct terminating errors, preserves captured streams, and makes a best-effort child-process-tree termination | May occur before or after a Git/Git LFS/`gh` operation has produced side effects | Captured stdout/stderr and timeout/cancellation diagnostics; normal orchestration recovery evidence when post-mutation catch paths execute | Never infer rollback from process termination; inspect GitHub state before retry after ambiguous mutation | `NativeCommandStreams.Tests.ps1`; cross-platform Quality Gate |
| `SCN-RESOURCE-RESILIENCE-01` — insufficient local disk/temp capacity | Defensible insufficiency fails before mutation; uncertain estimates are reported conservatively rather than inventing an exact universal size multiplier | Intended blocking point is pre-mutation local preflight; later filesystem exhaustion remains possible | Resource-preflight evidence and normal post-mutation recovery evidence if a later resource failure occurs | Free/select adequate local capacity and create/review a fresh plan after pre-mutation failure; inspect state first after mutation | `LocalResourcePreflight.Tests.ps1`; scale characterization workflow/live evidence informs the estimate, not an SLA |
| `SCN-RETRY-RESILIENCE-01` — retry after pre-mutation failure | Corrected prerequisite/authentication/preflight/stale-state failure can be retried from a fresh reviewed plan without inheriting mutation state | Before first GitHub mutation | Original failure plus newly captured plan/source evidence | Re-plan after the cause is corrected; normal validation/confirmation still applies | `RetryIdempotency.Tests.ps1` and prerequisite/stale-state suites; cross-platform Quality Gate |
| `SCN-RETRY-RESILIENCE-02` — retry after partial mutation | Repeated invocation never silently reuses/overwrites archive or replacement identities and must classify existing state before proceeding | After create/archive/publish/settings/protection mutation | Recovery report where available, completed stages, repository identities, current GitHub state | No blind replay; inspect evidence/state and follow stage-specific recovery guidance | `RetryIdempotency.Tests.ps1` plus existing recovery/replacement suites; live recovery harness where remote identity behavior matters |
| `SCN-SCALE-RESILIENCE-01` — pagination and larger repository/resource dimensions | Contract-required pagination remains complete; characterized larger history/ref/content/LFS fixtures complete or fail explicitly without becoming unsupported hard limits or SLAs | Read/planning/copy stages depending on dimension; characterization itself does not weaken mutation guards | Automated pagination assertions, characterization measurements, environment/tool versions | Correct cause and retry only under normal mutation/recovery rules; scale measurements do not grant blind replay | `SnapshotPagination.Tests.ps1`, scale-characterization workflow, documented local/live characterization evidence |
| `SCN-INTERRUPT-RESILIENCE-01` — Ctrl+C or process/session interruption | Explicit cancellation is normalized; raw Ctrl+C and hard termination are host/OS dependent and never imply rollback | Before mutation: no copy mutation expected; after mutation: state is ambiguous until inspected | Recovery report is attempted only when PowerShell remains capable; absence of a file is not evidence of no mutation | Fresh plan/retry is acceptable before mutation; after mutation inspect repository names/identities/content/settings/protection before retry | `InterruptionContract.Tests.ps1`, `NativeCommandStreams.Tests.ps1`; cross-platform Quality Gate; raw signal delivery is not synthesized as a portable blocking assertion |

These scenarios deliberately distinguish deterministic product guarantees from characterization or external-platform behavior. A measured result is not automatically a supported maximum, SLA, or rollback guarantee.

### Distribution and release

#### `SCN-DIST-VALIDATION-01` — stable installation is not implied before publication

**Given** the requested stable version/channel has not actually been published, **when** documentation or installation guidance is evaluated, **then** it must not claim that stable installation is currently available.

#### `SCN-REL-SAFETY-01` — stable publication is tied to exact release state

**Given** a stable release is being published, **when** release validation executes, **then** the tag/version/exact tagged commit and required release evidence must satisfy the release contract before immutable publication proceeds.

Detailed release readiness and execution are owned by [`release-readiness.md`](../release/release-readiness.md) and [`release-runbook.md`](../release/release-runbook.md) rather than duplicated here.

## Scenario coverage expectations

The scenario catalog is intentionally risk-based rather than combinatorial. A high-risk use case is not complete merely because its happy path exists. Applicable failure categories must be represented, especially when they answer one of these questions:

- Can mutation have started?
- What existing resource must be preserved?
- What identity/state invariant prevents the wrong repository from being changed?
- What verification proves success?
- What evidence remains after failure?
- Is retry safe, or does the operator need recovery guidance first?

Resilience scenarios use the same canonical `SCN-*` traceability model as functional scenarios. They must identify observable behavior, mutation boundary, retained evidence, safe retry/recovery semantics, and automated/live evidence where appropriate rather than living in a disconnected taxonomy.

## Relationship to automated and live evidence

This document does not claim a particular test currently proves every scenario. [`quality-strategy.md`](../engineering/quality-strategy.md) owns the formal requirement/scenario-to-test/evidence mapping.

For each `SCN-*`, the quality strategy should record as applicable:

- Unit test evidence;
- Integration test evidence;
- Contract test evidence;
- controlled E2E harness capability;
- actual live-validation evidence for the exact release candidate;
- known coverage gaps or accepted limitations.

This distinction prevents `implemented`, `automatically tested`, `E2E-capable`, and `live-validated` from becoming interchangeable claims.

## ID maintenance rules

- `CAP-*` identifies a durable product capability.
- `UC-*` identifies a durable user/program outcome.
- `SCN-*` identifies one externally meaningful behavioral scenario.
- Prefer adding a new ID when materially different behavior is introduced rather than silently changing the meaning of an existing published ID.
- Do not assign IDs to every implementation detail or individual test case.
- Tests and evidence may map many-to-many to scenarios.
- User documentation may summarize scenarios in natural language while linking back here when traceability matters.

## Downstream use

- [`user-guide.md`](../user/user-guide.md) reuses the capability/use-case catalog for user-facing getting-started and scenario guidance.
- [`troubleshooting-recovery.md`](../user/troubleshooting-recovery.md) reuses failure, partial-mutation, verification, recovery, retry, resource, and interruption scenarios for troubleshooting/recovery documentation.
- [`quality-strategy.md`](../engineering/quality-strategy.md) maps scenario IDs to automated and live evidence.
- [`release-readiness.md`](../release/release-readiness.md) uses capability/scenario IDs for release scope/readiness rather than inventing a competing taxonomy.
- [`non-functional-requirements.md`](non-functional-requirements.md) and its focused authorities define detailed resilience limits while reusing the canonical scenario IDs here.
