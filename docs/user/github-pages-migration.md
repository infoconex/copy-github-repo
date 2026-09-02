---
title: "Migrate GitHub Pages Safely"
description: "Use CopyGitHubRepo to opt into GitHub Pages configuration restoration, understand workflow and branch publishing modes, handle custom domains during replacement, verify results, and recover from partial restoration."
---

# GitHub Pages migration and recovery

GitHub Pages has two different kinds of state that must not be confused:

- **Repository content** — site files, `CNAME`, Jekyll configuration, and `.github/workflows/**` are ordinary Git content. Snapshot or FullHistory may copy them when they are part of the approved Git state.
- **GitHub-side Pages configuration** — whether Pages is configured, its publishing mode, branch/path source where applicable, custom-domain binding, and supported HTTPS intent are separate service state. Copying files does not prove this state was preserved.

Use `-RestorePages` only when you want CopyGitHubRepo to restore the supported GitHub-side Pages configuration from the immutable Pages evidence captured in the reviewed migration plan.

## Opt in deliberately

`-RestorePages` is off by default. Without it, Snapshot and FullHistory keep their normal Git-content behavior. Site files and Pages workflow files may still be copied, but CopyGitHubRepo does not claim that GitHub-side Pages configuration was preserved or restored.

When `-RestorePages` is selected, planning captures the source Pages configuration as reviewed evidence. Execution consumes that evidence rather than rediscovering a mutable source configuration as authority. Immediately before Pages mutation, the relevant source Pages state is read again and compared with the reviewed evidence. A material change fails closed before Pages restoration.

Example:

```powershell
Copy-GitHubRepository `
    -SourceRepository owner/source `
    -DestinationRepository owner/destination `
    -ContentMode Snapshot `
    -RestorePages
```

The guided wizard exposes the same opt-in and uses the real `Copy-GitHubRepository -PlanOnly` plan. Before execution it shows the reviewed Pages state, including whether Pages is configured, the publishing mode/source, custom domain, and HTTPS intent where available.

## Supported publishing modes

### Actions-based Pages

For Actions-based Pages, the GitHub-side build type is `workflow`. CopyGitHubRepo restores and verifies that reviewed mode; it does not treat the presence or execution of a copied workflow as proof of Pages migration.

A Pages deployment workflow is still ordinary Git content. General GitHub Actions configuration, policies, secrets, environments, workflow-run history, and unrelated workflow state are not copied by `-RestorePages`.

The migration controls copied Pages workflow activation until the approved Pages restoration/verification boundary. This prevents copied workflow content from being treated as an unreviewed Pages end state before the reviewed configuration is applied.

### Branch/path-based Pages

For branch/path publishing, CopyGitHubRepo restores the exact reviewed publishing branch and supported path (`/` or `/docs`) only when that source is representable at the destination.

FullHistory can preserve ordinary branch topology. Snapshot normally publishes only its constructed destination history/default branch. Snapshot does not invent a missing publishing branch or silently redirect Pages to another branch/path. If the exact reviewed branch/path cannot be represented safely, planning or execution fails closed instead of substituting another source.

## What is and is not migrated

| State | Behavior with `-RestorePages` |
| --- | --- |
| Pages configured/not configured | Captured, restored/validated, and independently verified as applicable |
| Actions/workflow build type | Restored and verified |
| Branch/path source | Restored and verified only when exactly representable |
| Custom-domain binding | Restored through ownership-safe rules; replacement uses explicit handoff |
| HTTPS enforcement intent | Restored where GitHub permits deterministic mutation/read-back |
| Pages URL/build/status | May be observed and reported as operational evidence; not reproduced as identity |
| External DNS records | **Not copied or modified** |
| Account/organization domain verification | **Not transferred** |
| Certificate issuance/propagation | **Not migrated**; readiness can remain pending |
| Secrets/tokens/environment secrets | **Never requested or copied** |

A successful GitHub-side restoration does not mean external DNS, domain verification, certificate issuance, or HTTPS readiness has completed. For a custom domain, GitHub can legitimately report certificate provisioning as pending after the reviewed configuration has been restored. CopyGitHubRepo reports that external readiness separately rather than misclassifying it as deterministic configuration drift.

## Ordering and activation safety

Requested Pages restoration occurs only after destination Git/LFS content has been independently verified. Requested GitHub Releases and ordinary supported repository settings are handled before Pages; transferable repository/branch protection remains last.

For a Pages-enabled migration the important sequence is:

1. review immutable Pages evidence in the migration plan;
2. publish Git content while the Pages activation guard prevents copied Pages workflows from establishing an unreviewed end state;
3. verify destination content and requested releases;
4. restore ordinary supported repository settings;
5. revalidate source Pages evidence for drift;
6. perform any required custom-domain ownership handoff;
7. restore supported Pages configuration;
8. independently read back and verify GitHub-side Pages state;
9. release the activation guard; and
10. restore transferable repository/branch protection last.

If the reviewed source explicitly had no Pages configuration, the destination is verified to have no unexpected Pages configuration before the activation guard is released.

## Same-name and existing-destination replacement

A production custom domain is ownership-sensitive state. During same-name replacement, and during archive-and-replace when a reviewed domain is being transferred, CopyGitHubRepo does not merely copy the domain string.

Before releasing an archived repository's domain binding, execution verifies the archive/replacement repository identities and the reviewed handoff evidence. It refuses ambiguous ownership. When handoff is safe, it releases the exact reviewed domain from the archive, verifies that release, creates/restores Pages on the replacement, claims the exact reviewed domain, and verifies the replacement read-back. A successful handoff must not leave both archive and replacement claiming the production domain.

External DNS is never changed as part of this process.

The handoff intentionally minimizes the unbound interval, but safety and evidence take precedence over downtime minimization.

## Failure and recovery

Pages mutation is fail closed. Examples include stale reviewed Pages evidence, an unsupported publishing mode, an unrepresentable branch/path source, ambiguous custom-domain ownership, a GitHub mutation refusal, or a read-back mismatch.

After mutation begins, CopyGitHubRepo does not perform destructive automatic rollback when ownership state may be uncertain. Recovery evidence records the reviewed configuration, the last successful Pages stage, destination mutation/creation state, activation-guard state, external readiness, and custom-domain handoff details when applicable. For a handoff this includes whether archive release was attempted/succeeded and whether replacement claim/read-back succeeded.

If a Pages operation fails:

1. preserve the archive and replacement repositories;
2. use the execution/recovery report to identify the exact Pages failure stage;
3. compare the reviewed Pages evidence with current source, archive, and replacement GitHub-side state;
4. for a custom domain, determine which repository currently owns the domain before making another mutation;
5. treat DNS, domain-verification, and certificate readiness as external state and verify them separately; and
6. create a new reviewed plan before retrying if source Pages configuration changed.

Expected external readiness such as pending certificate provisioning should be distinguished from a Pages configuration failure. Do not delete a replacement or move a custom domain based only on certificate propagation still being pending.

## Independent verification

Pages restoration uses independent read-back verification rather than restoration success as proof. Where applicable it compares:

- configured versus not configured;
- build type;
- exact branch/path source;
- exact custom-domain binding;
- HTTPS enforcement where deterministic comparison is supported; and
- for replacement handoff, that the archive no longer owns the production domain and the replacement does.

External DNS records, domain-verification ownership, and certificate issuance/propagation remain separately observed external readiness, not migrated state.

## Related documentation

- [`Copy-GitHubRepository`](../reference/commands/Copy-GitHubRepository.md)
- [`Start-CopyGitHubRepositoryWizard`](../reference/commands/Start-CopyGitHubRepositoryWizard.md)
- [Troubleshooting and recovery](troubleshooting-recovery.md)
- [GitHub Pages migration contract](../product/github-pages-migration-contract.md)
- [Product contract](../product/product-contract.md)
- [Architecture](../product/architecture.md)
