---
title: "CopyGitHubRepo GitHub Pages Migration Contract"
description: "Normative contract and architecture for GitHub Pages migration, implicit workflow activation, custom domains, ordering, verification boundaries, and fail-closed behavior."
---

# GitHub Pages migration contract

## Status and authority

This document is the authoritative 0.4.0 product contract and architecture for GitHub Pages migration. Later Pages planning, execution, verification, recovery, wizard, E2E, and user-documentation work must consume this definition rather than redefine it.

This contract/investigation change does not implement Pages restoration. The existing `-RestorePages` switch remains intentional and opt-in; mutating execution continues to reject it until the later implementation work provides the behavior defined here.

## Core distinction: Git content is not GitHub Pages state

Repository files are ordinary Git content. Snapshot and FullHistory may therefore copy site files, `CNAME`, Jekyll configuration, and `.github/workflows/**`, including a Pages deployment workflow, according to their existing Git-content contracts.

GitHub Pages configuration is separate GitHub-side state. A copied workflow file, a successful Pages workflow run, or a successfully published site is not proof that the reviewed source Pages configuration was preserved. First-class Pages migration must capture, restore, and independently verify the supported GitHub-side state described below.

Plain migrations without `-RestorePages` do not gain an implicit guarantee that Pages will be disabled, preserved, or restored. They preserve only the existing Git-content contract. Any Pages activation caused by copied content or GitHub defaults is an implicit side effect that later implementation must control according to this contract.

## Evidence for current implicit Actions-based behavior

The current repository contains a push-triggered Pages deployment workflow that configures Pages, uploads a Pages artifact, and deploys with the GitHub Pages deployment action. On the exact pre-0.4.0 baseline `e775d92bd3ed34c3633a3bd2972150cb9e063d9e`, GitHub Actions run `33456980366` completed the `Configure GitHub Pages`, `Upload GitHub Pages artifact`, `Deploy to GitHub Pages`, and published-site smoke-test steps successfully.

The migration engine also publishes repository content by pushing the selected Snapshot or FullHistory Git state to the destination. Therefore a migration can make a copied push-triggered Pages workflow available at the same Git boundary that publishes content. Where GitHub permits that workflow to run, Pages can become active or change before any first-class `-RestorePages` stage exists.

This is an implicit-activation risk, not successful Pages migration. Later implementation must prevent or safely contain an unreviewed Pages end state until the reviewed Pages decision is ready to apply.

## Actions-based Pages

For Actions-based Pages, the GitHub-side publishing mode is `workflow`. The reviewed plan must distinguish this mode from branch/path publishing.

Supported first-class migration may restore the reviewed GitHub-side mode and other supported Pages properties, but it must not infer preservation merely because a copied workflow exists or ran successfully. Workflow content remains Git content. General GitHub Actions configuration, enablement policy, secrets, environments, and unrelated workflow state remain outside the Pages restoration contract unless another explicit product contract says otherwise.

A destination whose reviewed source mode is Actions-based must not silently substitute a branch/path build mode.

## Branch/path-based Pages

For branch/path-based Pages, the reviewed GitHub-side configuration includes the publishing branch and supported source path (`/` or `/docs` where GitHub exposes those values).

Restoration is representable only when the exact reviewed publishing branch/path exists at the destination under the selected content mode. FullHistory can preserve ordinary branch topology according to its existing contract. Snapshot normally publishes only its constructed destination history/default branch; it must not invent a missing source publishing branch or silently redirect Pages to another branch/path.

If the reviewed branch/path cannot be represented safely at the destination, planning or execution must fail closed/report the state as unsupported rather than substitute another publishing source.

## Pages property classification

The following classifications control later implementation.

| Property/state | Classification | Contract |
| --- | --- | --- |
| Whether Pages is configured | Supported/readable | Capture when `-RestorePages` is requested; represent an explicit not-configured state rather than ambiguous null. |
| Build type: Actions/workflow vs branch/path | Supported/transferable | Capture, restore when representable, and independently verify. Never substitute another mode. |
| Branch and path for branch-based Pages | Conditionally transferable | Capture exactly; restore only when the reviewed branch/path exists and is representable. |
| Custom domain (`cname`) | Supported GitHub-side configuration with ownership constraints | Capture and restore only through the safe ownership/handoff rules below. |
| HTTPS enforcement intent | Conditionally transferable | Capture and restore where GitHub permits deterministic mutation/read-back; certificate readiness remains external/asynchronous. |
| Pages URL/status/build status | Verification/operational evidence | May be read and reported, but transient operational state is not source identity that must be reproduced exactly. |
| Certificate state/readiness | Externally dependent | Report separately; do not claim migration completes certificate issuance/propagation. |
| DNS records | External and unsupported for mutation | Never query as execution authority, copy, or modify. |
| Account/organization domain verification | External identity/policy state | Never claim it was transferred. A missing prerequisite can make custom-domain restoration unsafe or incomplete. |
| Secrets, tokens, environment secrets | Unsupported/sensitive | Never request, copy, display, or persist secret values. |

Unsupported or incompatible state must remain explicit. CopyGitHubRepo must not invent a substitute publishing mode, branch, path, domain, or external configuration.

## Custom domains and replacement ownership

A production custom domain is an ownership-sensitive resource, not merely text to copy.

For a new destination, later restoration may attempt to attach the exact reviewed custom domain only when GitHub permits it and the operation does not require taking the domain from an unrelated site. External DNS and domain-verification state remain outside the mutation contract.

For same-name replacement and delegated/existing-destination archive-and-replace flows:

1. preserve and verify archive repository identity before any archive-side Pages mutation;
2. prove from the reviewed plan that the intended replacement is the authorized recipient and that its reviewed Pages configuration is otherwise representable;
3. fail closed before releasing a domain when an unrelated repository/site appears to own it or required ownership evidence is ambiguous;
4. release the archived repository's Pages custom-domain binding only at the contract-defined handoff stage;
5. attempt to attach the exact reviewed custom domain to the replacement without silently changing it;
6. never leave archive and replacement independently claiming the same production custom domain after successful handoff;
7. record whether archive release occurred and whether replacement claim succeeded so a mid-handoff failure is recoverable; and
8. do not perform destructive automatic rollback when ownership state after failure is uncertain.

The implementation should minimize the interval in which the domain is unbound, but safety and evidence take precedence over minimizing downtime.

## Stage ordering

The normative ordering for migrations that request first-class Pages restoration is:

1. create/revalidate the immutable reviewed migration plan, including Pages evidence;
2. perform required archive/replacement identity handoffs that do not yet release a production custom domain;
3. publish destination Git content while controlling copied Pages workflows so they cannot establish an unreviewed Pages end state;
4. verify destination Git/LFS content against approved evidence;
5. restore and verify requested GitHub Releases where applicable;
6. restore ordinary supported repository settings according to the existing product contract;
7. revalidate the reviewed Pages evidence immediately before Pages mutation;
8. perform any required custom-domain archive-to-replacement ownership handoff;
9. restore supported destination Pages configuration from reviewed evidence;
10. independently read back and verify supported Pages configuration, while reporting external DNS/domain/certificate readiness separately; and
11. restore transferable repository/branch protection last, consistent with the existing protection contract.

A later implementation may combine adjacent read-only checks operationally, but it must preserve these dependency and authority boundaries. In particular, Pages restoration never precedes successful content verification, and copied workflow execution never counts as Pages verification.

## Behavior when `-RestorePages` is omitted

Without `-RestorePages`:

- Snapshot and FullHistory keep their existing Git-content semantics unchanged;
- site files and Pages workflow files may still be copied because they are Git content;
- CopyGitHubRepo makes no guarantee that GitHub-side Pages configuration is preserved or restored;
- CopyGitHubRepo must not represent incidental workflow execution as successful Pages migration; and
- later implicit-activation controls must avoid creating a new undocumented Pages-restoration guarantee.

## Planning and stale-state authority

When `-RestorePages` is requested, planning must capture immutable reviewed Pages evidence sufficient for later mutation and drift detection. Execution must consume that reviewed evidence rather than rerun mutable source selection/discovery as authority.

Relevant source Pages configuration must be revalidated immediately before Pages mutation. Drift that changes whether Pages is configured, build type, branch/path, custom domain, or another supported mutation-driving property must terminate before Pages mutation rather than silently applying the new live state.

## Independent verification

Pages verification is read-only and independent from restoration logic. It compares destination GitHub-side Pages state with reviewed planning evidence.

Where applicable it verifies:

- configured versus not configured;
- build type;
- exact branch/path source;
- exact reviewed custom-domain binding;
- HTTPS-enforcement state where deterministic comparison is supported; and
- after replacement handoff, that the archive no longer owns the production domain and the replacement does.

DNS records, account/organization domain verification, certificate issuance/propagation, and similar external/asynchronous state are reported separately and never treated as proof that CopyGitHubRepo migrated them.

## Fail-closed rules

Pages work terminates or reports an explicit unsupported state rather than guessing when:

- the reviewed publishing mode is unsupported;
- a branch/path publishing source is absent or unrepresentable;
- source Pages evidence drifted before mutation;
- a custom domain appears owned by an unrelated site;
- ownership/handoff prerequisites are ambiguous;
- GitHub refuses a supported Pages mutation or read-back does not match reviewed intent; or
- required verification cannot distinguish the destination from an unsafe or incompatible state.

No Pages feature may weaken existing destructive confirmation, source-state preservation, stale-plan detection, repository identity checks, content/release verification, recovery evidence, least-privilege Actions permissions, or protection restoration.

## Explicit non-goals for this contract

This contract does not implement Pages restoration, general GitHub Actions restoration, external DNS changes, account/organization domain verification, certificate management, secrets migration, or a new public Pages switch. Those boundaries are intentional.
