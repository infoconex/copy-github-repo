---
title: "CopyGitHubRepo Documentation Strategy – Structure, Personas, and Authority"
description: "Understand how CopyGitHubRepo documentation is organized by audience and subject, how progressive disclosure works, which pages own each contract, and how duplication and evidence claims are governed."
---

# Documentation strategy

This document defines how Copy GitHub Repository documentation is organized, who it serves, and which documents own each class of project information.

The goal is progressive disclosure: readers should be able to move from a concise front door to increasingly detailed operational, engineering, quality, architecture, security, assurance, and release material without encountering competing versions of the same contract.

## Physical organization

Documentation beneath `docs/` is organized by durable subject area. `docs/README.md` is the documentation index, and every first-level documentation folder has its own `README.md` that serves as the table of contents and landing page for that topic.

The first-level documentation areas are:

- `docs/user/` — user and operator guidance.
- `docs/reference/` — public command and reference material.
- `docs/product/` — product contracts, architecture, interaction design, and architecture decisions.
- `docs/engineering/` — contributor, maintainer, engineering-standard, quality, and documentation-governance material.
- `docs/security/` — security, supply-chain assurance, vulnerability, and repository-control material.
- `docs/release/` — release readiness, publication, deployment, versioning, and incident operations.

Individual topic documents should not normally be added directly beneath `docs/`. The physical documentation hierarchy and the published website navigation should represent the same conceptual information architecture. When a document moves, repository links, website navigation, validation tests, source help references, workflow smoke-test routes, and other path consumers must be updated in the same change.

## Personas and journeys

A **persona** describes who needs information. A **journey** describes what that person is trying to accomplish. One persona may have several journeys, and one journey may consume information owned by several documents.

The seven primary personas are:

1. **User / Operator** — evaluate the tool, choose the right mode, install it, run it safely, verify the result, and recover from failures.
2. **Contributor / Maintainer** — understand the repository, make a change, validate it, document it correctly, and maintain/release the project.
3. **Quality Engineer** — understand testable requirements, scenario coverage, quality gates, live-validation boundaries, and release evidence.
4. **Architect / Engineering Reviewer** — understand system boundaries, component responsibilities, state transitions, invariants, and durable design decisions.
5. **Security Reviewer** — understand trust boundaries, threats, credentials/data flow, controls, supply-chain posture, vulnerability applicability, and residual risk.
6. **Governance / Compliance Reviewer** — begin with [`software-assurance.md`](../security/software-assurance.md), then follow authoritative evidence for licensing, dependencies, permissions, data handling, support, maintenance, security controls, quality evidence, release trust, and unresolved approval conditions.
7. **Product / Program Manager** — understand product intent, journeys, capabilities, use cases, acceptance behavior, dependencies, release scope, blockers, and go/no-go evidence.

The persona model intentionally includes Product / Program Manager as a primary audience alongside the original user, engineering, quality, architecture, security, and governance audiences. This is one consolidated persona taxonomy rather than a set of historical variants.

**Industry Expert** is a cross-cutting quality lens rather than a separate persona. Claims should be precise, evidence-based, traceable to authoritative contracts/tests/workflows where practical, and clear about current versus planned state.

## Progressive disclosure

Documentation should normally progress through these layers:

1. **Repository/product front door** — `README.md` explains what the product is, when to use it, major safety guarantees, prerequisites, quick start, and where to go next.
2. **User/operations guidance** — user journeys, capabilities, scenarios, troubleshooting, recovery, and detailed command references.
3. **Contributor/engineering guidance** — contribution workflow, governance/decision ownership, change-impact expectations, engineering principles, PowerShell conventions, source-documentation rules, and development/release procedures.
4. **Quality and architecture guidance** — product/test traceability, quality strategy, non-functional requirements, accessibility, architecture, trust/state boundaries, and architecture decisions.
5. **Security and assurance guidance** — vulnerability reporting/applicability, installation trust, threat/control evidence, dependency/software-assurance information, support lifecycle, and release provenance.
6. **Program/release guidance** — capability readiness, go/no-go evidence, release/deployment execution, and post-release incident/emergency maintenance.

A reader should not need to read a lower layer to understand a higher-level user task unless the additional detail is genuinely necessary.

## Documentation authority map

Where practical, each fact or contract has one authoritative home. Other documents should summarize and link rather than reproduce detailed normative text.

| Information / contract | Authoritative home |
| --- | --- |
| Product behavior, supported scope, invariants, exclusions | `docs/product/product-contract.md` |
| Public command syntax, parameters, outputs, examples | `docs/reference/commands/*` and native PowerShell help |
| Product journeys, capabilities, use cases, behavioral scenarios | `docs/product/product-model.md` |
| User getting-started/scenario guidance | `docs/user/user-guide.md` |
| Troubleshooting, partial-mutation recovery, shared mutation/recovery state model | `docs/user/troubleshooting-recovery.md` |
| Non-functional requirements, operational limits, resilience/scale expectations | `docs/product/non-functional-requirements.md` |
| Accessibility baseline for console UX, documentation/site semantics, automated/manual review boundary | `docs/product/accessibility.md` |
| Current architecture, boundaries, flows, state models | `docs/product/architecture.md` |
| Durable architecture rationale | `docs/product/adr/` |
| Project governance, decision ownership, proposal paths, CODEOWNERS policy, maintainership transfer | `docs/engineering/governance.md` |
| Engineering principles | `docs/engineering/engineering-principles.md` |
| PowerShell coding conventions | `docs/engineering/powershell-style-guide.md` |
| Source-code documentation policy/inventory | `docs/engineering/source-code-documentation.md` |
| Contributor entry point and development prerequisites | `CONTRIBUTING.md` |
| Repository map, change-impact guidance, maintainer triage, Definition of Done | `docs/engineering/maintainer-guide.md` |
| Quality strategy, requirement/test/live-evidence traceability | `docs/engineering/quality-strategy.md` |
| Security reporting and currently security-supported version/branch | `SECURITY.md` |
| Vulnerability applicability/VEX publication decision, evidence threshold, release binding, lifecycle | `docs/security/vulnerability-applicability.md` |
| Support lifecycle, compatibility, prerequisite/platform support, deprecation, end of support | `docs/user/support-policy.md` |
| Security architecture, threats, controls, credential/data flow, residual risk | `docs/security/security-architecture.md` |
| Installation/bootstrap/release-channel trust | `docs/security/installation-security.md` |
| Machine-readable release inventory and provenance/SBOM attestation contract | `docs/security/release-sbom.md` |
| Live repository security baseline and owner-side verification | `docs/security/repository-security-baseline.md` |
| Dependency freshness/advisory monitoring | `docs/security/dependency-monitoring.md` |
| Organizational software-assurance review entry point / approval evidence index | `docs/security/software-assurance.md`; it links authoritative facts and must not redefine their detailed contracts |
| Semantic version numbering and release semantics | `docs/release/versioning.md` |
| PowerShell Gallery publication operations | `docs/release/publishing.md` |
| Release capability readiness/go-no-go for an exact release candidate | `docs/release/release-readiness.md` |
| Release/deployment execution | `docs/release/release-runbook.md` |
| Post-release incident/emergency maintenance | `docs/release/incident-response.md` |
| Project license | `LICENSE` |

Until a planned document is implemented, existing authoritative documents remain the source of truth. Planned documentation must not be described as implemented merely because planning work exists.

## Anti-duplication rules

- Keep one detailed normative source per fact/contract where practical.
- Prefer a short summary plus a link over copied paragraphs.
- Do not maintain separate persona-specific copies of the same requirement.
- Command references own command-level syntax/details; higher-level guides should not reproduce full parameter documentation.
- The product contract owns behavioral invariants; architecture and user docs may explain them but should not redefine them.
- Non-functional documentation should distinguish measured/characterized behavior from enforceable support limits rather than turning observations into accidental SLAs.
- Accessibility requirements should be owned by `docs/product/accessibility.md`; contributor, wizard, quality, and site documentation should link to that baseline rather than creating competing accessibility contracts.
- `docs/engineering/governance.md` owns project decision authority, proposal paths, CODEOWNERS policy, and maintainership changes; `docs/engineering/maintainer-guide.md` owns the implementation workflow and Definition of Done. Do not create a second governance model inside release, security, or contributor guidance.
- `docs/security/vulnerability-applicability.md` owns VEX/applicability publication triggers and evidence semantics; the SBOM remains the shipped-content authority and security/assurance documents should link rather than restate the full VEX decision.
- `docs/release/release-readiness.md` owns capability scope, blocker/accepted-limitation treatment, and exact-candidate go/no-go semantics; release execution documents should consume that decision rather than create a competing readiness checklist.
- Security, quality, and assurance documents should reference shared capability/evidence inventories instead of creating competing inventories.
- The software-assurance page is a reviewer entry point/evidence map: it may summarize approval-relevant current state, but product, license, security, quality, release, and support authorities remain authoritative for their detailed facts.
- The support policy owns lifecycle/compatibility/deprecation semantics; versioning, security, host-support, README, and assurance docs should summarize and link rather than define competing support windows.
- Release/readiness documents should reference exact evidence rather than copying test logs, workflow output, or long contract text.
- When duplication is intentionally necessary for usability, keep the duplicate concise and identify the authoritative source.

## Current, planned, and evidenced state

Documentation must distinguish these states when the distinction matters:

- **Implemented** — the capability exists in source.
- **Automatically tested** — automated tests protect the capability/contract.
- **E2E-capable** — a live test harness exists.
- **Live-validated** — the capability was actually exercised against live GitHub for the referenced evidence/release candidate.
- **Documented** — user/maintainer documentation describes the capability.
- **Characterized** — observed/measured under a documented fixture/environment but not necessarily an enforceable limit.
- **Planned** — approved work exists but is not yet implemented.
- **Unsupported / deferred** — deliberately outside the current release scope.

Do not collapse these into a generic "supported" or "ready" claim when the more precise state is material.

## Navigation design

The README and published documentation site should expose a clear path for:

- **Use the product** — getting started, scenarios, commands, troubleshooting/recovery, support/compatibility policy.
- **Understand the product** — product contract, non-functional expectations, accessibility, quality strategy, architecture, and architecture decisions.
- **Engineering and maintenance** — contributing, governance/ownership, maintainer workflow/Definition of Done, engineering standards, source documentation, and quality practices.
- **Security and assurance** — begin organizational review from `docs/security/software-assurance.md`, then follow security architecture, vulnerability reporting/applicability, installation trust, dependency/SBOM evidence, repository security posture, and support lifecycle authorities.
- **Release and operations** — product/program traceability, release readiness/go-no-go, release/deployment, versioning, publishing, and incident response.

Navigation may point to planned areas only after those pages exist. Avoid dead links or placeholder pages that imply unfinished work is current documentation.

## Change guidance

When changing behavior or documentation, identify the authority first:

1. Update the authoritative contract/document.
2. Update derived user/contributor/reviewer guidance only where the change affects that journey.
3. Update tests/validation that protect cross-document consistency where practical.
4. Remove stale duplicated prose rather than trying to keep multiple detailed copies synchronized.
5. When moving a document, update every repository and site path consumer in the same branch before merge.

The final documentation integration work should periodically audit README, site navigation, command references, contributor/security pages, deeper docs, source help, tests, and generated-site routes for stale or competing authority.
