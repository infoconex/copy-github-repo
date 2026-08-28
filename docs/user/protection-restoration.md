---
title: "Restore GitHub Rulesets and Branch Protection After Migration"
description: "Learn how CopyGitHubRepo restores transferable GitHub repository rulesets and default-branch protection after migration, including supported and skipped policy semantics."
---

# Repository protection restoration

Repository protection is restored **after Git content has been copied and verified**. This ordering is deliberate: activating rulesets or branch protection before the initial push, LFS transfer, default-branch establishment, or content verification could block the migration itself.

## Ordering

For mutating Snapshot and FullHistory flows, the intended order is:

1. discover source repository state;
2. create or preserve/replace the destination as required;
3. copy Git content;
4. transfer Git LFS content when applicable;
5. reload the destination and establish the expected default branch;
6. verify Git content/history invariants;
7. restore ordinary supported repository settings;
8. restore transferable repository rulesets and legacy default-branch branch protection;
9. read protection configuration back and verify it.

`-PlanOnly` and `-WhatIf` remain non-mutating. `-SkipSettings` also skips protection restoration.

## Supported rulesets

The `v0.1.0` protection-restoration contract copies repository-level rulesets when the rule can be recreated without carrying source-specific identities into the destination.

Supported rulesets preserve:

- name;
- target;
- enforcement mode;
- conditions;
- identity-free rules and rule parameters.

Organization-level inherited rulesets are not copied. They are intentionally queried with `includes_parents=false`; if organization policy independently applies to the destination, that is an external policy outcome rather than a copied repository setting.

## Rulesets that are explicitly skipped

A repository ruleset is reported as skipped rather than weakened when it contains semantics that cannot be proven transferable:

- bypass actors (users, teams, apps, or other identity-bound actors);
- required deployment rules that depend on destination environments that this module does not create;
- required status checks tied to a specific integration ID.

The module does not silently remove those fields and create a weaker ruleset.

## Legacy branch protection

The source default branch's legacy branch-protection configuration is copied when it contains no identity-bound restrictions.

The transferable subset includes:

- required status-check contexts without app/integration identity binding;
- strict status-check behavior;
- administrator enforcement;
- required pull-request review settings without identity-bound dismissal restrictions;
- required approving-review count;
- code-owner review requirement;
- stale-review dismissal;
- last-push approval requirement when available;
- linear-history requirement;
- force-push allowance;
- deletion allowance;
- branch-creation blocking;
- conversation-resolution requirement;
- branch locking;
- fork-sync allowance;
- required commit signatures.

Legacy branch protection is reported as skipped when it contains:

- user/team/app push restrictions;
- user/team/app review-dismissal restrictions;
- required status checks tied to an app ID.

Only the default branch's legacy branch protection is restored in the current implementation. Repository rulesets remain the preferred mechanism for broader branch/tag policy.

## Verification

After mutation, repository-level rulesets are reloaded with inherited parent rules excluded. The module compares each restored ruleset's name, target, enforcement, conditions, and rules with the transferable source configuration.

Legacy default-branch protection is reloaded and compared with the normalized source protection configuration. A mismatch is a terminating verification failure and is included in normal recovery reporting.

## Permissions and GitHub plan behavior

Protection APIs require repository Administration permissions at the appropriate read/write level and may depend on the GitHub plan and repository visibility. If GitHub rejects a read or write because the authenticated identity or plan does not permit the operation, the migration fails with the GitHub API error rather than claiming protection was restored.

## Safety guarantees

- Source protections are never weakened to make migration easier.
- Same-name archives remain preserved and are not modified merely to simplify replacement creation.
- Inherited organization policy is never reported as copied repository policy.
- Identity-bound semantics are surfaced explicitly instead of silently discarded.
- Protection is restored only after content verification.
- Recovery never automatically deletes or renames repositories.
