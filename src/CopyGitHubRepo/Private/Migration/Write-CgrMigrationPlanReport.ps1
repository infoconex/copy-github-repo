function Write-CgrMigrationPlanReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject] $Plan,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Path
    )

    $resolvedParent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($resolvedParent)) {
        New-Item -Path $resolvedParent -ItemType Directory -Force | Out-Null
    }

    $extension = [System.IO.Path]::GetExtension($Path)
    $format = if ($extension -eq '.json') { 'Json' } else { 'Markdown' }
    $content = Format-CgrMigrationPlan -Plan $Plan -Format $format
    Set-Content -Path $Path -Value $content -Encoding utf8NoBOM
}
