# Guided repository-copy wizard contract

## Status and scope

`Start-CopyGitHubRepositoryWizard` is the finalized public command name. It is the native PowerShell interactive experience for the four-command module. It remains dependency-free, keyboard-friendly, testable without a human console, and cross-platform on the project's PowerShell 7.4 baseline.

The wizard is a presentation/orchestration layer, not a second copy engine. `Get-GitHubRepository` owns discovery, `Copy-GitHubRepository -PlanOnly` creates the real review artifact, private application helpers execute the exact approved plan, and `Test-GitHubRepositoryMigration` remains the standalone verification command.

## Product terminology

Human-facing copy terminology is canonical:

- **Snapshot** means clean current-state publication. The approved source default-branch content is published as one new unrelated root commit without prior Git history, other branches, or tags.
- **FullHistory** means history-preserving copy. Approved branches, tags, commits, and reachable Git LFS objects are preserved.
- The review heading is **Repository copy plan**, not the generic phrase “Migration plan”.
- Protection/status text is human-readable. Internal property dumps such as `captured=False` or raw nested objects are not wizard UI.

## Guided sequence

The normal journey is:

1. Welcome and prerequisite/authentication status.
2. Select the source repository.
3. Enter the destination repository.
4. Choose `Snapshot` or `FullHistory`.
5. Choose destination visibility and supported-settings behavior.
6. When replacement is required, choose an archive name and satisfy the exact confirmation contract.
7. Generate the real `Copy-GitHubRepository -PlanOnly` plan.
8. Display the repository copy plan, including immutable approved source-state evidence appropriate to the content mode.
9. Require an explicit Execute decision.
10. Execute that exact reviewed plan.
11. Show concise completion/verification or recovery information.

No GitHub mutation occurs during discovery, validation, planning, or review.

## Defaults

Content mode is `Snapshot`.

- Destination visibility: source visibility.
- Supported repository settings: restore.
- Snapshot commit message: `Initial repository commit`.
- Pages restoration and Actions activation are not offered as successful mutating v0.1.0 paths.

Listed choices mark the Enter-to-accept value with `(default)`. Free-text inputs place the Enter-to-accept value in parentheses at the end of the prompt. Revisiting a step preserves a still-valid accepted value and makes it the new default.

## Canonical controls

Prompts advertise only controls that are valid in that context. The canonical compact vocabulary is:

- `[? help]`
- `[B back]`
- `[C cancel]`
- `[F filter]` on repository selection only
- `Enter` accepts the displayed default when a default exists

In short: [F filter] on repository selection only.

Control keys are case-insensitive. Hidden long-form aliases such as `back`, `cancel`, `help`, `filter`, `next`, or `n` are not navigation commands. A prompt must not advertise Back on the first step or Filter where filtering is unavailable.

Invalid input stays on the current step and does not clear unrelated valid state. Contextual help is a side action: dismissing help returns to the same prompt with the same accepted/default value.

## State, Back, and cancellation

Before execution, Back preserves still-valid values and lets the user edit earlier decisions. Changing plan-affecting state invalidates the old plan and any dependent exact-confirmation value. Normal cancellation is a no-change outcome before mutation.

After mutation begins, Back is unavailable. Recovery handling never implies an automatic delete, overwrite, or rename-back unless the application layer explicitly performed one.

## Immutable reviewed-plan boundary

The wizard obtains its review artifact by invoking the real planning path of
`Copy-GitHubRepository` with `-PlanOnly`.

A plan is bound both to the selected configuration and to immutable source-state evidence captured during planning.

For Snapshot, the plan records the approved default branch, source commit SHA, tree SHA, Git LFS evidence, and repository identity when available. For FullHistory, it records the approved default branch, branch/tag ref targets, reachable commit count, branch-tip trees, Git LFS availability, and repository identity when available.

The wizard executes the exact object it displayed; it does not reconstruct an equivalent set of command parameters after review. Immediately before any mutation the application re-checks the current source against the plan. If the source changed, execution terminates with `SourceStateChangedSincePlanning` before repository creation or rename. The wizard explains that the plan is stale, returns to plan generation, and requires the newly captured state to be reviewed again.

Snapshot and FullHistory copy engines also validate their cloned source workspace against the approved evidence before the first destination publish. Destination verification compares against the approved/copied evidence rather than rereading a moving source after publication.

## Replacement safety

Same-name replacement and existing-destination archive-and-replace retain the same fail-closed source-state boundary.

For same-name replacement:

- source state is checked before the source repository is renamed;
- the renamed archive is checked again against the same approved source evidence before the replacement is created;
- immutable repository ID/node ID continuity is verified when available;
- the replacement must receive a distinct immutable repository ID before content copy;
- exact case-sensitive confirmation names source, archive, and replacement; and
- neither `-Force` nor `-Confirm:$false` bypasses exact confirmation.

For an existing different destination, approved source state is checked before the existing destination is archived. The archived destination's immutable identity is verified before its replacement is created.

## ShouldProcess and execution

`Start-CopyGitHubRepositoryWizard` applies `ShouldProcess` to the reviewed plan after the user selects Execute. `-WhatIf` therefore allows discovery and review but prevents mutation. The private approved-plan execution boundary performs the source-state preflight and dispatches the already-reviewed plan into the same copy, verification, settings/protection, provenance, and recovery application logic used by the public API.

## Output and diagnostics

The wizard presents human-readable progress and completion summaries. Interactive terminals may receive in-place progress; redirected/non-interactive hosts receive line-oriented activity without cursor control. `NO_COLOR` preserves semantic text without color dependence.

Known application, validation, prerequisite, source-drift, and safety conditions are presented concisely. Unexpected defects retain their PowerShell error records and are not disguised as normal wizard failures.

Successful interactive execution does not dump the raw execution object. Automation that needs structured execution output should call `Copy-GitHubRepository` directly.

## Acceptance coverage

Pester covers repository filtering, displayed controls, default behavior, Back/state preservation, contextual help, cancellation, real PlanOnly review, exact reviewed-plan execution, ShouldProcess, Snapshot/FullHistory terminology, replacement confirmation, source drift before mutation, replan behavior, presentation fallbacks, and installed-module packaging.

The v0.1.0 wizard work does not create a release tag or GitHub Release; release publication remains a separate explicit boundary.
