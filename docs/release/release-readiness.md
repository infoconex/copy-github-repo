# Release capability readiness and go/no-go model

This document is the authoritative program-level release-readiness view for Copy GitHub Repository. It answers whether the capabilities targeted by a release are sufficiently implemented, evidenced, documented, secured, and dispositioned to ship.

It does **not** redefine product behavior, test semantics, security controls, support policy, or publication mechanics. Those remain authoritative in [`product-contract.md`](../product/product-contract.md), [`product-model.md`](../product/product-model.md), [`quality-strategy.md`](../engineering/quality-strategy.md), [`security-architecture.md`](../security/security-architecture.md), [`support-policy.md`](../user/support-policy.md), [`versioning.md`](versioning.md), [`publishing.md`](publishing.md), and [`release-runbook.md`](release-runbook.md).

A mutable `main`-branch matrix is planning evidence only. A real go/no-go decision must be bound to one exact immutable release candidate commit/tag/artifact identity.

## Decision authority

Release-readiness authority follows [`governance.md`](../engineering/governance.md). The current primary maintainer owns the project go/no-go decision unless maintainership changes are explicitly recorded.

That authority does not create independent review evidence. Adopting organizations remain responsible for their own approval and risk-acceptance process.

## Scope classifications

Every capability targeted by a release uses one of these scope states:

- **Required** — must be release-ready or explicitly covered by an accepted limitation before go/no-go can be `GO`.
- **Optional** — may ship when ready but does not block the release when deliberately omitted.
- **Deferred** — intentionally moved to later work and excluded from the release contract.
- **Unsupported** — explicitly outside the release's supported product scope.

A capability must never be called optional merely because its implementation or evidence is incomplete.

## Evidence and readiness states

Keep these states distinct:

- **Not started** — no accepted implementation/evidence exists.
- **Implemented** — product behavior exists in source.
- **Automatically tested** — deterministic automated evidence protects the relevant contract.
- **E2E-capable** — a controlled live GitHub harness exists where external behavior requires it.
- **Live-validated for RC** — the exact release candidate was actually exercised and the evidence record identifies that candidate.
- **Documented** — applicable user/maintainer/reviewer guidance is current.
- **Blocked** — a required prerequisite, control, defect, or evidence item prevents release readiness.
- **Accepted limitation** — an incomplete expected item has an explicit release-specific rationale, residual risk, authority, and follow-up.
- **Release-ready** — all required evidence and dependencies for this exact release candidate are satisfied or explicitly accepted.
- **Deferred / not in scope** — deliberately excluded from this release.

`Implemented`, `Automatically tested`, `E2E-capable`, and `Documented` are evidence dimensions, not substitutes for `Release-ready`.

## v0.1.0 capability scope

The stable capability IDs below come from [`product-model.md`](../product/product-model.md). This table is the current **planning baseline, not a go/no-go record** for a release candidate.

| Capability | v0.1.0 scope | Current repository evidence | RC live evidence | Current readiness treatment |
| --- | --- | --- | --- | --- |
| `CAP-DISC` Repository discovery/authentication | Required | Implemented; automated discovery/auth/host contracts | Pending exact-RC decision/evidence | Pending RC evidence |
| `CAP-PLAN` Immutable source-state planning/preview | Required | Implemented; automated stale-state and no-mutation contracts | Pending exact-RC decision/evidence | Pending RC evidence |
| `CAP-SNAP` Snapshot clean publication | Required | Implemented; automated tests; live Snapshot E2E harness | Not yet recorded for an exact RC | Pending RC live evidence |
| `CAP-HIST` FullHistory copy | Required | Implemented; automated tests; live FullHistory E2E harness | Not yet recorded for an exact RC | Pending RC live evidence |
| `CAP-DEST` Destination/archive-and-replace safety | Required | Implemented; automated safety/recovery coverage | Not yet recorded for an exact RC | Pending RC evidence |
| `CAP-SAME` Same-name archive-and-replace | Required | Implemented; automated tests; live same-name E2E harnesses | Not yet recorded for an exact RC | Pending RC live evidence |
| `CAP-LFS` Git LFS handling | Required when approved content requires LFS | Implemented; automated tests; live LFS E2E harness | Not yet recorded for an exact RC | Pending RC live evidence when applicable |
| `CAP-SET` Supported settings restoration | Required | Implemented; automated tests; live settings E2E harness | Not yet recorded for an exact RC | Pending RC live evidence |
| `CAP-PROT` Protection restoration/skipped semantics | Required | Implemented; automated protection/status coverage | Pending exact-RC decision/evidence | Pending RC evidence |
| `CAP-WIZ` Guided wizard | Required | Implemented; extensive unit/integration/presentation contracts | Pending exact-RC decision/evidence | Pending RC evidence |
| `CAP-AUTO` Scripted/non-interactive operation | Required | Implemented; automated public/safety contracts | Pending exact-RC decision/evidence | Pending RC evidence |
| `CAP-VERIFY` Standalone/integrated verification | Required | Implemented; automated Snapshot/FullHistory verification | Pending exact-RC decision/evidence | Pending RC evidence |
| `CAP-EVID` Provenance/reporting/recovery evidence | Required | Implemented; automated report/recovery/provenance coverage | Pending exact-RC decision/evidence | Pending RC evidence |
| `CAP-DIST` Install/update/uninstall/distribution | Required | Implemented install/release/uninstall/package contracts | Post-publication verification cannot exist before release | Pending release/publication evidence |
| `CAP-REL` Packaging/publication integrity | Required | Packaging/checksum/SPDX SBOM/GitHub attestation contracts implemented; independent publisher signing is optional for the initial stable release | Post-publication evidence pending | Pending release execution |

The matrix does not claim that every `Required` capability needs an independent live E2E script. The release decision applies the live-evidence rules in [`quality-strategy.md`](../engineering/quality-strategy.md) and must explain when automated evidence is sufficient versus when real GitHub evidence is required.

## v0.1.0 non-functional disposition

The current non-functional controls and limitations are stated directly rather than through historical work-tracking references.

| Area | v0.1.0 disposition | Evidence / rationale | Residual limitation | Blocking treatment |
| --- | --- | --- | --- | --- |
| Native child-process timeout/cancellation | **Required for v0.1.0 — implemented. Accepted limitation: no universal finite default timeout.** | Centralized `Invoke-CgrNativeCommand` supports explicit finite timeout and explicit cancellation, distinct errors, captured streams, and best-effort process-tree termination. | The default remains `System.Threading.Timeout::InfiniteTimeSpan`; repository size, LFS volume, network, and GitHub latency do not justify an arbitrary universal duration. | **Not a release blocker** provided the unbounded default is disclosed and no release material claims a universal hang-prevention SLA. |
| GitHub API throttling/transient retry | **Required for v0.1.0 — implemented.** | Side-effect-free reads use bounded retry/backoff for recognized transient/rate-limit failures, while mutation calls remain single-attempt to avoid unsafe duplicate side effects. | External GitHub/network degradation can exceed bounded policy; ambiguous mutation failures require state inspection rather than automatic replay. | **Not a release blocker** once exact-RC automated evidence passes. |
| Large-repository/resource characterization | **Required characterization completed; accepted limitation: no supported hard maximum or performance SLA is adopted.** | Repeatable history/ref/content/LFS fixtures, local measurements, and a live GitHub baseline were recorded. | Peak process-tree memory remains observational unless measured for the relevant workload. Characterized timings and sizes are observations, not guarantees. | **Not a release blocker.** |
| Local disk/temp resource preflight | **Required for v0.1.0 — implemented.** | A defensible known lower-bound shortage fails before GitHub mutation. Additional headroom is advisory and unknown capacity does not become false precision. | Exact future workspace/LFS consumption cannot always be predicted from remote metadata; later exhaustion remains possible and normal recovery semantics apply. | **Not a release blocker** once exact-RC automated evidence passes. |
| Repeated-invocation retry/idempotency | **Required for v0.1.0 — implemented and cross-platform validated.** | The retry contract distinguishes pre-mutation retry from post-mutation recovery and prevents silent reuse/overwrite of archive or replacement identities. | Concurrent multi-writer coordination is not provided; post-mutation retry still requires inspection of recovery evidence/current GitHub state. | **Not a release blocker.** |
| Cross-platform interruption/signal handling | **Required deterministic contract implemented. Accepted limitation: raw Ctrl+C and hard process/session termination are host/OS dependent.** | The contract distinguishes explicit controlled cancellation from terminal interruption and hard termination and preserves the pre-/post-mutation boundary. | Signal propagation, whether catch/finally completes during shutdown, and hard-termination cleanup cannot be normalized across Windows/macOS/Linux. | **Not a release blocker** when exact-RC cross-platform deterministic evidence passes. |

The accepted limitations above do not authorize broader claims. In particular, v0.1.0 does not promise a finite universal native-command timeout, a supported hard repository-size maximum, a fixed completion-time SLA, guaranteed recovery-file creation after hard termination, or automatic rollback/replay after ambiguous mutation.

## Current cross-cutting v0.1.0 readiness items

The following durable concerns must remain visible before a `GO` decision:

| Item | Current state | Required readiness treatment |
| --- | --- | --- |
| Repository security baseline | Live owner-side hardening/verification remains until the required baseline is confirmed | Must be satisfied or explicitly accepted with release-specific residual risk; the release must not claim a fully hardened repository without live evidence. |
| Independent publisher signing | Optional for the initial stable release | Do not describe checksum/SBOM/GitHub attestations as independent code signing. |
| Non-functional resilience controls | Implemented with the accepted limitations above | Exact-RC automated evidence is still required. |
| Product scenario traceability | Required before final qualification | Required scenarios must map to deterministic evidence and applicable live E2E evidence through durable scenario identifiers. |
| Release/deployment runbook | Implemented in [`release-runbook.md`](release-runbook.md) | Must remain aligned with the release workflow and publication contract. |
| Repository-hosted installation rehearsal | Required before the clean Snapshot publication | A real supported workstation must install, use, uninstall, and reinstall through the documented repository/release path. |
| Clean Snapshot qualification | Required before the first stable release | Historical repository must not be tagged/published as `v0.1.0`; the clean replacement must be independently qualified. |
| Exact release-candidate evidence | Not yet applicable on mutable `main` | Required for the actual go/no-go record. |

A planning or tracking artifact is not automatically a release blocker. The release decision is based on the durable requirement/control itself and its evidence. No undispositioned release blocker may remain for a `GO` decision.

## Capability dependency rules

Readiness rolls up conservatively:

1. A capability cannot be `Release-ready` while a required prerequisite is `Blocked` or undispositioned.
2. `CAP-SNAP`, `CAP-HIST`, `CAP-DEST`, and `CAP-SAME` depend on `CAP-PLAN`, relevant verification, and evidence/recovery behavior.
3. `CAP-LFS` is required for a release-candidate scenario only when approved content requires LFS; absence of LFS in a fixture does not validate the LFS path.
4. `CAP-SET` and `CAP-PROT` occur only after required content verification and must not make a failed content copy appear successful.
5. `CAP-DIST` depends on the exact packaged version and distribution channel under review.
6. `CAP-REL` depends on readiness approval for the exact candidate, package/integrity evidence, and the publication controls required by the release runbook.
7. A dependent capability cannot become ready merely because its own row is green while a required dependency remains unresolved.

## Accepted limitations and exceptions

An accepted limitation is a release-specific decision, not a permanent waiver. Record all of the following:

- exact release candidate commit/tag/artifact identity;
- affected capability/use case/scenario;
- incomplete control/evidence item;
- why release is still acceptable;
- user/security/operational consequence;
- residual risk;
- compensating control or evidence, if any;
- current decision authority;
- durable follow-up requirement/reference when applicable;
- effect on support/security/release messaging; and
- point at which the limitation expires or must be reconsidered.

Ordinary incomplete work remains incomplete. Do not convert it into an exception simply to obtain a `GO` result.

## Exact release-candidate go/no-go record

Before tagging/publishing, create or update a release-specific record containing at least:

| Field | Required value |
| --- | --- |
| Version | Exact SemVer release version |
| Candidate commit | Exact 40-character commit SHA |
| Candidate tag | Proposed/final immutable tag |
| Artifact identity | Expected package/release filename and digest once built |
| Decision | `GO`, `NO-GO`, or `PENDING` |
| Decision timestamp | UTC timestamp |
| Decision authority | Current authority from `governance.md` |
| Quality Gate evidence | Exact successful run(s) for the candidate |
| Required live E2E evidence | Exact scenarios/runs/results, or explicit rationale when not required |
| Security/readiness disposition | Live repository/security controls and any accepted residual risk |
| Non-functional disposition | Exact-candidate treatment of the resilience controls/limitations above |
| Known limitations | Release-specific accepted limitations/residual risks |
| Publication prerequisites | Release-runbook and publishing environment/credential readiness |
| Final result | Why the candidate is or is not authorized for tagging/publication |

The decision applies only to the recorded candidate. **A later commit requires a new readiness review**; approval of an earlier SHA must never be inferred to cover mutable `main`.

## Release decision algorithm

A v0.1.0 decision can be `GO` only when:

1. every `Required` capability is implemented and documented;
2. automated evidence required by the quality strategy passes for the exact candidate;
3. required live GitHub evidence for the exact candidate is present;
4. required security, integrity, support, and non-functional items are satisfied or have explicit accepted-limitations records;
5. no undispositioned release blocker remains;
6. package/release metadata is internally consistent;
7. publication prerequisites/runbook state are ready; and
8. the current decision authority records `GO` against the exact candidate identity.

Otherwise the correct result is `PENDING` or `NO-GO`, not an optimistic partial-ready label.

## Clean Snapshot release boundary

For the first stable release, the same-name Snapshot replacement is part of release qualification:

1. finish all required pre-Snapshot repository, documentation, security, workflow, test, and installation-readiness work on the historical repository;
2. run the approved same-name Snapshot replacement;
3. verify the replacement repository has the intended unrelated clean root commit and approved tree;
4. reapply/verify required repository security/settings and validate workflows/documentation deployment;
5. rerun required cross-platform automated and live evidence from the replacement repository;
6. designate one exact clean replacement commit as the release candidate;
7. create `v0.1.0` only on that clean replacement commit; and
8. publish through the controlled release workflow.

The historical repository must not be used as the source of the first stable tag, GitHub Release, or PowerShell Gallery publication.

## Relationship to release execution

This document owns **whether** a candidate is ready to release. [`release-runbook.md`](release-runbook.md) owns **how** an approved candidate is tagged, packaged, published, verified, and recovered across GitHub Release, PowerShell Gallery, and documentation deployment.

`versioning.md` and `publishing.md` remain authoritative for their detailed contracts. This readiness model references their evidence rather than duplicating or weakening them.

## Related authorities

- Product goals/capabilities/use cases/scenarios: [`product-model.md`](../product/product-model.md)
- Product behavior/invariants: [`product-contract.md`](../product/product-contract.md)
- Quality and live-evidence semantics: [`quality-strategy.md`](../engineering/quality-strategy.md)
- Non-functional requirements: [`non-functional-requirements.md`](../product/non-functional-requirements.md)
- Security architecture: [`security-architecture.md`](../security/security-architecture.md)
- Repository security baseline: [`repository-security-baseline.md`](../security/repository-security-baseline.md)
- Support policy: [`support-policy.md`](../user/support-policy.md)
- Release execution: [`release-runbook.md`](release-runbook.md)
- Publishing: [`publishing.md`](publishing.md)
