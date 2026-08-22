# Wizard activity and progress contract

Long-running repository-copy operations expose semantic activity events to the wizard presentation layer. Migration and Git/GitHub boundary code does not perform cursor manipulation and does not write terminal spinners directly.

## Rendering modes

The activity layer has three intentional modes:

1. **Interactive terminal** — the wizard installs an activity sink that uses PowerShell `Write-Progress` for the single active operation. Indeterminate work uses a spinner frame, and completed operations are retained as normal status lines.
2. **Redirected or non-interactive wizard output** — the same events render as line-oriented INFO/SUCCESS/ERROR messages. `Write-Progress` and cursor-oriented presentation are not used.
3. **Structured automation** — deterministic public commands such as `Copy-GitHubRepository` do not install a presentation sink. Activity events therefore produce no host or pipeline output and cannot pollute structured results.

A percentage is permitted only when an operation supplies a real `Current` and `Total`. The renderer never fabricates percentages for Git clone, fetch, push, Git LFS, verification, settings, or GitHub API operations whose actual completion percentage is unknown.

## Semantic stages

Activity names are stable semantic identifiers rather than terminal text. The reviewed execution narrative follows actual operation order and can surface repository archive/rename, destination creation, source clone/fetch, Git LFS handling, Snapshot or FullHistory publication, destination verification, supported-settings restoration, repository-protection restoration/checking, and significant report writing.

No-op stages use outcome-specific language. In particular, a Git LFS check with zero applicable objects is reported as no transfer required rather than as a completed transfer. A successful LFS transfer reports useful evidence such as the number of tracked LFS paths when available. Repository-protection output similarly distinguishes restored, not applicable, skipped/unsupported, partial, and failed outcomes.

Native Git and Git LFS stdout/stderr remain captured by the existing command boundary. The activity layer reports safe semantic stage text; it does not blindly stream native stderr into the wizard while parsing or verification is in progress.

## Presentation rules

- Only the currently active indeterminate operation uses in-place progress.
- Completing a stage clears in-place progress and writes a durable status line through the shared status formatter.
- A failed stage clears progress and writes an error line; the original PowerShell error continues through the normal application/recovery path.
- Every meaningful stage that emits both `Started` and terminal activity events shows elapsed time in seconds to one decimal place. This consistent convention avoids an unexplained duration threshold.
- The concise completion summary is separate from the live execution narrative. Verification/settings/protection outcomes appear before the final `Repository copy complete` declaration, so a warning or failure never follows a misleading success heading.
- Tests inject and invoke sinks directly; they do not require a real terminal.
