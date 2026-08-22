# Contributing

Thank you for helping improve Copy GitHub Repository.

## Development requirements

- PowerShell 7.4 or newer
- Git
- Development/test PowerShell modules installed by the repository setup script

Install the repository-pinned development modules for the current user:

```powershell
./build/Install-DevelopmentDependencies.ps1
```

The pinned development/test module versions are maintained in `build/DevelopmentDependencies.psd1`. Runtime prerequisites remain separate from these development-only dependencies. The setup script is idempotent: it reuses an exact required module version when already installed and installs only missing pinned versions.

## Maintainer workflow

For the repository map, logical ownership, change-impact matrix, focused-test choices, live-E2E triggers, maintainer failure triage, release responsibilities, and the project Definition of Done, use [docs/engineering/maintainer-guide.md](docs/engineering/maintainer-guide.md). This file remains the contributor entry point and development-prerequisite guide; the maintainer guide owns the detailed change-completion workflow so those rules are not duplicated across multiple pages.

Project decision ownership, compatibility/design proposal paths, ADR expectations, release authority, current maintainership, and ownership-transfer guidance are defined in [docs/engineering/governance.md](docs/engineering/governance.md). The repository currently uses a single-primary-maintainer model; `.github/CODEOWNERS` routes review to the current owner but does not by itself represent independent review or separation of duties.

## Project conventions

The repository-specific engineering standard is documented in [docs/engineering/powershell-style-guide.md](docs/engineering/powershell-style-guide.md). It distinguishes required conventions from readability preferences and documents the analyzer rules that enforce objective policy.

Key conventions include:

- Use approved PowerShell verbs and singular nouns for public commands.
- Retain the `Cgr` prefix for private helpers.
- Use `[CmdletBinding()]`, named parameters, and validation attributes.
- Use `$PSCmdlet.ShouldProcess()` for state-changing operations.
- Do not use aliases or `Invoke-Expression` in source code.
- Keep presentation separate from migration behavior.
- Return structured objects on the success pipeline.
- Never add repository deletion or destination-overwrite behavior.
- Add or update Pester tests with every behavior change.

### Accessibility change impact

The accessibility baseline is defined in [docs/product/accessibility.md](docs/product/accessibility.md). Treat accessibility as part of change impact whenever a change affects console prompts/status/progress, wizard interaction, site layout/navigation/search/themes, images, diagrams, tables, or other presentation behavior.

In particular, keep status and safety meaning understandable without color, preserve keyboard-only operation, keep styled/interactive presentation optional for redirected or non-interactive hosts, provide meaningful image alternatives or equivalent nearby text, and verify site focus/reduced-motion/responsive behavior when those areas change. Automated accessibility contracts protect deterministic repository behavior, but browser, assistive-technology, contrast, focus-order, narrow-terminal, and semantic-quality checks may still require manual review. Do not describe an unperformed manual accessibility review as passed.

### Source documentation

The maintainership documentation standard is defined in [docs/engineering/source-code-documentation.md](docs/engineering/source-code-documentation.md). Public commands require complete native comment-based help. Every private function must be accounted for in the private-function inventory, while critical planning and Git/GitHub mutation boundaries also require attached inline comment-based help. Significant build, install/uninstall, release, and live E2E scripts must be present in the operational-script inventory.

When adding or renaming a private function or operational script, update the documentation inventory in the same change. When a private function becomes a critical planning or mutation boundary, classify it in `tests/SourceDocumentationPolicy.psd1` so inline help is enforced by the Quality Gate.

Comments should explain safety constraints, invariants, failure/recovery semantics, non-obvious Git/GitHub behavior, or output contracts. Do not add author/date/change-history headers or comments that merely translate the implementation into prose; Git remains the source of truth for authorship and history.

### Security static analysis

The normal `PSScriptAnalyzerSettings.psd1` path loads the repository custom analyzer module. In addition to documentation policy, `Measure-CgrSecurity` rejects high-confidence security regressions such as dynamic `Invoke-Expression` evaluation, explicit shell `-c`/`/c` interpretation, direct Git/GitHub native invocation from module source that bypasses `Invoke-CgrNativeCommand`, and direct diagnostic/output emission of variables whose names indicate secret-bearing material.

These checks are intentionally narrow and actionable. They supplement review and testing; a clean analyzer result is not a claim of comprehensive SAST or vulnerability absence. The authoritative threat/control description is [docs/security/security-architecture.md](docs/security/security-architecture.md).

Run the security analyzer through the same canonical local gate used by CI:

```powershell
./build/Test-Project.ps1
```

The positive-detection and safe-case contracts are in `tests/PSScriptAnalyzerSecurityRules.Tests.ps1` and are included in the Contract category.

## Validate a change

For any code, test, module metadata, build-tooling, or Quality Gate change, run the same local preflight command used by CI before committing or pushing:

```powershell
./build/Test-Project.ps1
```

Treat this as the canonical local quality gate. It imports the module, recursively runs PSScriptAnalyzer across the repository, runs every classified Pester suite, and enforces aggregate code coverage. Running it locally catches preventable analyzer and test failures before GitHub Actions spends Windows, Ubuntu, and macOS runner time validating the same change.

Local success does **not** replace CI. GitHub Actions remains the authoritative cross-platform validation and must pass on Windows, Ubuntu, and macOS before a change is considered complete.

### Test taxonomy

Pester suites are classified in `tests/TestTaxonomy.psd1` and must belong to exactly one category:

- **Unit** — isolated logic, formatting, presentation, parsing, validation, and adapter behavior where dependencies are mocked or otherwise controlled.
- **Integration** — scenarios that exercise multiple module components together, including migration orchestration, replacement, recovery, protection, repository settings, and wizard-to-migration behavior.
- **Contract** — public API, documentation, packaging, release, workflow, security, dependency, and other repository quality contracts.
- **End-to-end** — live GitHub scenarios under `tests/e2e/` that create temporary repositories and exercise real Git/GitHub behavior. These are intentionally separate from the normal Pester Quality Gate because they require authenticated GitHub access and repository-creation/deletion capability.

Run a focused Pester category with:

```powershell
./build/Test-Project.ps1 -Category Unit
./build/Test-Project.ps1 -Category Integration
./build/Test-Project.ps1 -Category Contract
```

Focused category runs still run PSScriptAnalyzer, but they do not enforce aggregate code coverage. The authoritative coverage gate remains:

```powershell
./build/Test-Project.ps1 -Category All
```

Run an end-to-end scenario directly when live GitHub validation is appropriate, for example:

```powershell
./tests/e2e/Invoke-SnapshotEndToEndTests.ps1 -Owner <github-owner>
```

E2E scripts create temporary repositories and validate cleanup capability before repository creation. Use them deliberately; they are not part of routine local preflight or the cross-platform Quality Gate.

`tests/TestTaxonomy.Tests.ps1` enforces that every Pester suite and every `Invoke-*EndToEndTests.ps1` script is classified exactly once, so new test files cannot silently bypass the taxonomy.

For documentation-only changes, the repository uses a narrower path-filtered documentation workflow. You can run its validation directly with:

```powershell
./build/Test-Documentation.ps1
```

Documentation-only changes that affect the published website are also built and validated by the GitHub Pages workflow. Do not use the narrower documentation command for source, tests, module metadata, or build changes that require `./build/Test-Project.ps1`.

### Coverage policy

The quality gate requires at least **65% Pester instruction coverage** across `src/CopyGitHubRepo`. The strengthened test suite measured **65.34%** on Windows, Ubuntu, and macOS when this threshold was established, so 65% is a regression guard just below the demonstrated cross-platform baseline rather than an aspirational percentage selected without evidence.

Aggregate coverage is only one part of the policy. Critical behavior must also retain focused contract and safety suites for GitHub API adapters, Snapshot pagination, repository/path boundaries, stale-state protection, public output contracts, and wizard-to-migration integration. These targeted suites prevent broad presentation coverage from masking weak coverage of destructive or verification paths.

Do not add low-value assertions solely to increase the percentage. Prefer tests that protect observable behavior, failure boundaries, destructive-operation guards, or supported public contracts. A future move toward 75-80% should follow meaningful new coverage that raises the stable cross-platform baseline first; the threshold should not drive artificial tests.

## Pull requests

Keep changes focused and explain the behavior, risks, and validation performed.
Do not include tokens, repository secrets, or private migration reports.
