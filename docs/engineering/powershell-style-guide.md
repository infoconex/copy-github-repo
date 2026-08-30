---
title: "CopyGitHubRepo PowerShell Style Guide – Naming, Safety, and Testing"
description: "Follow CopyGitHubRepo's PowerShell conventions for terminology, naming, formatting, public/private command design, structured output, ShouldProcess, native-command safety, tests, and analyzer policy."
---

# PowerShell style guide

This guide defines the PowerShell engineering conventions for Copy GitHub Repository. It records conventions already established by the codebase, identifies deliberate project decisions, distinguishes mandatory engineering contracts from readability preferences, and defines how external PowerShell guidance applies when the project has not already made a deliberate choice.

The repository targets PowerShell 7.4 or newer. `PSScriptAnalyzerSettings.psd1` is the authoritative machine-readable analyzer configuration; this guide is the human-readable engineering contract.

## Product terminology

**Required**

- Human-facing text uses **repository copy**, **copy**, or **publication** for the product operation. Do not introduce generic `migration` wording in new wizard headings, status text, reports, or help when a copy/publication term is accurate.
- The public content-mode values are exactly `Snapshot` and `FullHistory`.
- `Snapshot` means clean current-state publication: the approved current default-branch content is published as one new unrelated root commit without prior history, other branches, or tags.
- `FullHistory` means history-preserving copy: approved history, branches, tags, and reachable Git LFS objects are preserved.
- Use **Repository copy plan** for the human-readable reviewed plan heading.
- Compatibility-sensitive command names, parameter names, `PSTypeName` values, internal helper names, and schema fields that already contain `Migration` may remain until a deliberately versioned breaking change. Do not expose those internal names as normal wizard prose merely for implementation convenience.
- User-facing protection descriptions must explain what will be restored or why protection cannot be transferred. Do not surface raw nested-object formatting or diagnostic phrases such as `captured=False` as normal plan text.

## Rule categories

- **Required** means a mandatory engineering contract. Violations must be corrected or covered by an explicitly permitted and documented exception. PSScriptAnalyzer, Pester, or another deterministic quality check should enforce an objective Required rule when practical and low-noise.
- **Preferred** means the normal/default choice when PowerShell permits more than one technically valid approach. A deviation is not, by itself, a quality-gate failure, and reviewers should not demand churn without a concrete readability or maintenance benefit.
- **Allowed** means an explicitly acceptable alternative. Code using an Allowed form should not be rewritten merely to make it match a Preferred form elsewhere.
- **Discouraged** means avoid in new or modified code unless there is a concrete technical, compatibility, or architectural reason to use it.
- **Prohibited** means the form must not be introduced. Any retained existing use requires an explicit compatibility, exception, or remediation disposition.

## Standards and decision hierarchy

A documented CopyGitHubRepo rule, compatibility contract, ADR, or deliberate architectural boundary takes precedence for this repository unless the project explicitly revisits that decision. External guidance informs unresolved decisions; it does not silently override established project policy.

When no documented project rule resolves a PowerShell engineering decision, use the following order of guidance:

1. Microsoft PowerShell documentation and design guidance.
2. Applicable PSScriptAnalyzer rules and their documented intent.
3. PowerShell Practice and Style guidance.
4. Established PowerShell community practice.
5. Local consistency when multiple valid approaches remain.

This hierarchy is a decision aid, not a command to apply every external recommendation mechanically. A PSScriptAnalyzer rule is an enforcement mechanism for a documented engineering concern; the existence of a rule does not automatically make every optional configuration or Information-level recommendation appropriate for this repository.

Before classifying an inconsistency as a defect, determine whether it is explained by an existing project rule, ADR, compatibility requirement, architectural boundary, or documented exception. Only unexplained divergence should be treated as accidental inconsistency. Avoid cosmetic churn where multiple forms are already valid under this guide.

## Naming

### Commands and functions

**Required**

- Use approved PowerShell verbs.
- Use singular nouns for public commands.
- Public commands use the normal `Verb-Noun` form and expose only the supported module command surface.
- Private helpers retain the repository-specific `Cgr` prefix after the verb, for example `Get-CgrRepository` and `Invoke-CgrRepositorySnapshotVerification`.
- Do not introduce generic private helper names that could collide with commands from other modules.

The `Cgr` prefix is an intentional project convention and must not be expanded or renamed merely to satisfy a generic naming preference.

### Parameters and variables

**Required**

- Parameter names use PascalCase and descriptive words, for example `DestinationRepository` and `ContentMode`.
- Avoid single-character parameter and variable names except for conventional, tightly scoped cases where the meaning is unmistakable.
- Do not reuse PowerShell automatic-variable names.

**Preferred**

- Local variables use descriptive camelCase names, for example `$destinationVisibilityWasProvided`.
- Names should describe domain meaning rather than implementation mechanics.

## Formatting

### Indentation and braces

**Required**

- Indent with four spaces. Do not use tabs for indentation.
- Opening braces remain on the same line as the statement or declaration they belong to.
- Closing braces align with the beginning of the construct they close.
- Put spaces around operators and after separators, and use normal spacing around braces and pipelines.
- Existing compact PowerShell forms such as `param()` are acceptable; the project does not require inserting a space before every opening parenthesis.

The four-space/no-tabs indentation convention is machine-enforced with `PSUseConsistentIndentation`. The project uses spaces, four-space indentation, and `IncreaseIndentationForFirstPipeline` so multiline pipelines follow the standard first-pipeline indentation behavior. Existing source has been normalized to this policy rather than weakening the rule.

### Multiline parameter declarations

**Preferred**

- Put one parameter declaration per line when a parameter block spans multiple lines.
- Put type and validation attributes immediately above the parameter they describe.
- Keep related validation and type information visually attached to the declaration.

Example:

```powershell
[ValidateSet('Snapshot', 'FullHistory')]
[string] $ContentMode = 'Snapshot'
```

### Multiline command invocation and splatting

**Preferred**

- Use named parameters for nontrivial command calls.
- A short fixed invocation may use normal PowerShell line continuation when it remains easy to scan.
- Prefer splatting when an invocation has many arguments, arguments are conditional, or the same argument set is reused. Splatting should make ownership of values clearer rather than simply move a long call into a long hashtable.
- Do not convert stable readable calls to splatting solely for stylistic uniformity.

## Language forms

### Quoting

**Required**

- Use single-quoted strings for literals.
- Use double-quoted strings when interpolation or PowerShell escape processing is required.
- Do not add interpolation where a literal string is sufficient.

### Boolean negation

**Required**

- Use `-not` rather than the `!` alias. `PSAvoidExclaimOperator` enforces this convention.

### `$null` comparisons

**Required**

- Put `$null` on the left side of equality comparisons, for example `$null -eq $value` and `$null -ne $value`.
- Prefer explicit null handling over relying on collection or scalar coercion.

### Early returns and guard clauses

**Preferred**

- Use early returns or terminating errors for invalid/precondition cases when doing so keeps the successful path shallow and readable.
- Avoid deeply nesting the main operation under conditions that can be handled up front.

## Public and private command design

### Public/Private separation

**Required**

- Public commands live under `src/CopyGitHubRepo/Public` and define the supported command surface.
- Internal helpers live under `src/CopyGitHubRepo/Private` and use the `Cgr` prefix.
- Public commands own public parameter semantics, safety decisions, user-facing output selection, and dispatch. Internal helpers own cohesive implementation behavior.
- Do not export private helpers.

### Types and validation attributes

**Required**

- Use parameter types and validation attributes when they make the accepted contract objective and machine-checkable.
- Prefer `ValidateSet`, `ValidatePattern`, `ValidateNotNullOrEmpty`, and similarly focused attributes over manual validation when the attribute expresses the rule accurately.
- Do not use a validation attribute that changes an intentional product contract merely to conform to generic guidance.

### Structured output and errors

**Required**

- Return structured objects on the success pipeline for programmatic behavior.
- Keep presentation/serialization separate from repository-copy behavior.
- Use stable `PSTypeName` values where the public contract depends on an object shape.
- Use structured terminating errors with meaningful error IDs and categories at safety, authentication, Git/GitHub, verification, and integrity boundaries.
- Deliberate application failures must be distinguishable from unexpected implementation/runtime failures at user-facing boundaries. Use a stable project error ID and a project-owned marker on the exception/error record rather than relying on message-text matching.
- User-facing boundary handlers may present deliberate application failures concisely without exception type or stack trace. Unexpected failures must preserve diagnostic information such as exception type, error ID, location, inner exceptions, and script stack trace, and must remain terminating after diagnostics are emitted.
- Do not use `Write-Host` as a substitute for structured output.

For standalone bootstrap scripts that can be invoked repeatedly with `irm ... | iex`, prefer a marked .NET exception/ErrorRecord over declaring a PowerShell `class` solely to identify application-generated failures. PowerShell type definitions persist for the session and can make repeated bootstrap execution brittle. CopyGitHubRepo bootstrap errors use the `CopyGitHubRepo.ApplicationError` marker together with stable `CopyGitHubRepo.*` error IDs.

### Console presentation

**Required**

- Treat console styling as presentation only. Never add ANSI escape sequences, status decoration, or host-only text to structured success-pipeline objects.
- Use PowerShell-native `$PSStyle` for terminal color rather than embedding raw ANSI escape sequences.
- Respect `NO_COLOR` and plain-text output rendering. Output must remain understandable when color is unavailable, disabled, redirected, or captured by CI.
- Never use color as the only carrier of meaning. Pair status color with explicit text and a stable symbol.
- Use the project status vocabulary consistently: `✓ PASS` / `✓ SUCCESS` for successful states, `✗ FAIL` / `✗ ERROR` for failures, `! WARN` for warnings, and `• INFO` for informational status where a marker improves scanning.
- Use green for success, red for failure/error, yellow for warnings, and restrained cyan or neutral text for informational status.
- Prefer simple Unicode symbols with predictable terminal width. Do not depend on emoji-style glyphs for status. Where Unicode is not practical, the status word alone must preserve the meaning.
- Keep formatting views and interactive host presentation separate from repository-copy and verification logic. Public result types must remain suitable for assignment, filtering, serialization, and automation.
- Use custom PowerShell formatting data for richer default display of structured objects when appropriate rather than replacing returned objects with strings.

**Preferred**

- Color only the status marker/label rather than entire lines or paragraphs.
- Use short headings, whitespace, and concise aligned labels to create hierarchy. Prefer this over decorative boxes, heavy separator art, cursor-position tricks, spinners, or full-screen TUI behavior.
- Keep normal output task-focused. Put raw SHAs, IDs, expected/actual evidence, and other diagnostics beneath the failed check or in a detailed view rather than making every successful run verbose.
- Use standard `-Verbose` semantics for diagnostic execution detail. Add a product-specific detailed view only when the normal result would otherwise be too noisy.
- Interactive helpers may write directly to the host when they are genuinely part of the wizard/user-interface boundary, but they must remain mockable and must not replace structured command output.

Example status presentation:

```text
✓ PASS  Destination repository exists
✗ FAIL  Repository content matches
! WARN  Snapshot mode creates one unrelated root commit.
• INFO  Executing the reviewed repository copy plan...
```

The status word is intentionally redundant with both symbol and color. This keeps output scannable while remaining accessible in monochrome terminals and plain CI logs.

### Comment-based help

**Required**

- Every public command must provide useful comment-based help for synopsis, description, every explicitly declared public parameter, examples, inputs, outputs, and related links.
- Help must document product-specific defaults and safety semantics rather than restating syntax alone.
- Private helpers need comments when intent, safety boundaries, or non-obvious behavior cannot be understood readily from the code and tests; full public-style help is not required for every private helper.

### `ShouldProcess`

**Required**

- Public state-changing operations use `SupportsShouldProcess` and call `$PSCmdlet.ShouldProcess()` before mutation.
- `-WhatIf` must remain non-mutating.
- `-Confirm:$false` must not bypass independent product safety requirements such as exact same-name replacement confirmation.
- `-Force` may satisfy explicitly documented guards, but must not become a generic bypass for product safety invariants.

## Native commands and security-sensitive code

**Required**

- Do not use `Invoke-Expression`.
- Do not use aliases in production source where they obscure the invoked command.
- Never place tokens or secrets in diagnostics, returned objects, committed fixtures, or command arguments when a safer mechanism exists.
- Preserve GitHub CLI and Git authentication isolation semantics when modifying native-command execution.
- Fail closed at unsupported-host, identity, checksum, verification, and destructive-action boundaries.

## Tests

**Required**

- Use Pester for repository tests.
- Add or update tests with behavior, safety-contract, analyzer-policy, or documentation-contract changes.
- Keep unit tests deterministic and avoid real external mutation unless the test is explicitly an end-to-end harness.
- Cover failure paths at destructive or security-sensitive boundaries, not only successful paths.
- Assert stable public behavior such as output shape, error ID, verification result, or mutation ordering instead of incidental implementation details.
- Do not weaken an assertion merely to make a failing implementation pass.

**Preferred**

- Organize tests around behavior (`Describe`) and scenario (`It`) names that explain the contract being protected.
- Mock at external or orchestration boundaries when that produces clearer failure isolation than mocking every internal call.

## PSScriptAnalyzer policy

The configured PSScriptAnalyzer Error and Warning policy is mandatory. Code must produce no unsuppressed Error or Warning diagnostics under the repository's analyzer configuration. Any suppression must satisfy the documented suppression requirements below.

`PSScriptAnalyzerSettings.psd1` is the authoritative machine-readable analyzer configuration. This guide documents the project-specific baseline, additions, exclusions, configuration choices, suppression policy, and rationale; it does not duplicate the complete PSScriptAnalyzer rule catalog.

The normal analyzer pass retains the default Error/Warning rule set and explicitly configures the objective rules adopted by this project:

| Rule | Project policy |
| --- | --- |
| `PSAvoidExclaimOperator` | Requires explicit `-not` rather than the `!` alias. |
| `PSAvoidSemicolonsAsLineTerminators` | Prohibits semicolons used only as line terminators. |
| `PSPlaceOpenBrace` / `PSPlaceCloseBrace` | Enforces same-line opening braces, normal newline behavior, and no empty line immediately before a closing brace while leaving one-line blocks intact. |
| `PSUseConsistentIndentation` | Enforces spaces, four-space indentation, and `IncreaseIndentationForFirstPipeline`. |
| `PSUseConsistentWhitespace` | Enforces the adopted brace, parenthesis, operator, pipeline, separator, parameter, and redundant-pipeline-whitespace checks. |
| `PSUseConsistentParameterSetName` | Requires consistent parameter-set naming. |
| `PSUseConsistentParametersKind` | Requires parameter declarations to use the `ParamBlock` form. |
| `PSUseSingleValueFromPipelineParameter` | Prevents ambiguous multiple value-from-pipeline parameters. |
| `PSUseCorrectCasing` | Enforces command, keyword, and operator casing through the focused Information-rule contract. |
| `PSAvoidUsingDoubleQuotesForConstantString` | Requires single quotes for constant strings through the focused Information-rule contract. |

The main recursive analyzer gate intentionally remains limited to Error and Warning diagnostics. The Required Information-severity conventions `PSUseCorrectCasing`, `PSAvoidUsingDoubleQuotesForConstantString`, and `PSAvoidUsingPositionalParameters` are promoted by a focused contract test instead of enabling every Information diagnostic globally.

`PSAvoidLongLines`, `PSAlignAssignmentStatement`, and `PSUseConstrainedLanguageMode` remain outside the mandatory policy because they are subjective or specialized for this repository. Compatibility is established by the PowerShell 7.4+ contract and the actual Windows, Linux, and macOS CI matrix rather than by obsolete analyzer compatibility profiles.

Additional rules should be evaluated against this repository and adopted when they express an objective engineering contract with acceptable signal-to-noise characteristics.

### Pester and AST enforcement

PSScriptAnalyzer remains the preferred mechanism for objective language and formatting rules that it can express accurately. Repository-structure and project-specific conventions that are narrower than built-in analyzer rules are enforced by deterministic Pester contracts using the PowerShell AST and source discovery.

`tests/contract/PowerShellSourceConventions.Tests.ps1` enforces the Required conventions that explicitly declared parameters use PascalCase, private functions use approved PowerShell verbs with the `Cgr` noun prefix, manifest-exported commands have exactly one matching public source file and do not use the private `Cgr` prefix, and governed Public/Private PowerShell source does not use tab indentation. Public command coverage is derived from `FunctionsToExport`; the contract does not maintain a second hard-coded command inventory.

These AST/Pester checks complement the analyzer configuration rather than replacing it. They are intentionally narrow so project-specific structure can be enforced without enabling broader analyzer behavior that would create unrelated formatting churn or false positives.

## Suppressions

The repository uses narrow function-level `PSUseShouldProcessForStateChangingFunctions` suppressions on the internal GitHub mutation boundaries `New-CgrGitHubRepository`, `Rename-CgrGitHubRepository`, and `Set-CgrGitHubRepositorySetting`. These helpers intentionally do not perform independent `ShouldProcess` checks because the public `Copy-GitHubRepository` command owns `ShouldProcess` and, for same-name replacement, the stronger exact-confirmation safety contract before dispatching to those private mutation helpers. Each suppression is attached directly to the affected function and includes a justification describing that boundary.

Any suppression must continue to follow these rules:

1. Scope it to the narrowest function, parameter, or statement practical.
2. Name the exact rule being suppressed.
3. Include a nearby comment explaining why the project contract intentionally differs from the rule.
4. Do not disable a useful rule globally to silence one exceptional case.
5. Add a test when the exception protects an important product behavior or compatibility contract.

A suppression is an explicit engineering decision, not a shortcut for making the quality gate green.

## External references

Use durable upstream documentation as the primary external reference for unresolved PowerShell engineering questions:

- [PowerShell documentation](https://learn.microsoft.com/powershell/)
- [PowerShell cmdlet development guidelines](https://learn.microsoft.com/powershell/scripting/developer/cmdlet/cmdlet-development-guidelines)
- [Approved verbs for PowerShell commands](https://learn.microsoft.com/powershell/scripting/developer/cmdlet/approved-verbs-for-windows-powershell-commands)
- [PSScriptAnalyzer documentation](https://learn.microsoft.com/powershell/utility-modules/psscriptanalyzer/overview)
- [PowerShell Practice and Style](https://github.com/PoshCode/PowerShellPracticeAndStyle)

These references guide decisions where CopyGitHubRepo has not already established an intentional project contract. They do not replace this guide, compatibility requirements, ADRs, or deliberate architectural boundaries.