#requires -Version 7.4

[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()]
    [string] $Owner = 'infoconex',

    [ValidateNotNullOrEmpty()]
    [string] $OutputPath = 'artifacts/scale/live-e2e-characterization.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$snapshotScript = Join-Path $repositoryRoot 'tests/e2e/Invoke-SnapshotEndToEndTests.ps1'
$fullHistoryScript = Join-Path $repositoryRoot 'tests/e2e/Invoke-FullHistoryEndToEndTests.ps1'
$resolvedOutput = if ([System.IO.Path]::IsPathRooted($OutputPath)) {
    [System.IO.Path]::GetFullPath($OutputPath)
}
else {
    [System.IO.Path]::GetFullPath((Join-Path $repositoryRoot $OutputPath))
}
$outputDirectory = Split-Path -Parent $resolvedOutput
if (-not (Test-Path -LiteralPath $outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
}

function Get-NativeVersionText {
    param(
        [Parameter(Mandatory)]
        [string] $FilePath,

        [Parameter(Mandatory)]
        [string[]] $ArgumentList
    )

    $output = & $FilePath @ArgumentList 2>&1
    if ($LASTEXITCODE -ne 0) {
        return $null
    }
    return (@($output) -join ' ').Trim()
}

function Invoke-LiveScenario {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Snapshot', 'FullHistory')]
        [string] $Mode,

        [Parameter(Mandatory)]
        [string] $ScriptPath
    )

    $startedAt = [DateTimeOffset]::UtcNow
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $success = $false
    $errorText = $null
    $outputLines = @()

    try {
        $outputLines = @(& $ScriptPath -Owner $Owner 2>&1 | ForEach-Object { $_.ToString() })
        $success = $true
    }
    catch {
        $errorText = $_.Exception.Message
    }
    finally {
        $stopwatch.Stop()
    }

    [ordered] @{
        Mode = $Mode
        StartedAtUtc = $startedAt.ToString('o')
        ElapsedMilliseconds = [long] $stopwatch.ElapsedMilliseconds
        Success = $success
        Error = $errorText
        Harness = [System.IO.Path]::GetRelativePath($repositoryRoot, $ScriptPath).Replace('\\', '/')
        CleanupPolicy = 'Harness requires delete_repo capability and removes repositories created under its protected run-specific prefix unless KeepRepositories is explicitly used.'
        Output = $outputLines
    }
}

if ($Owner -notmatch '^[A-Za-z0-9_.-]+$') {
    throw "Owner '$Owner' is not valid."
}

foreach ($required in @($snapshotScript, $fullHistoryScript)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Required live E2E harness '$required' was not found."
    }
}

$ghAuth = & gh auth status --hostname github.com 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "GitHub CLI authentication is required for live characterization. $(@($ghAuth) -join [Environment]::NewLine)"
}

$gitVersion = Get-NativeVersionText -FilePath 'git' -ArgumentList @('--version')
$gitLfsVersion = Get-NativeVersionText -FilePath 'git' -ArgumentList @('lfs', 'version')
$ghVersion = Get-NativeVersionText -FilePath 'gh' -ArgumentList @('--version')

$headSha = $null
$headOutput = & git -C $repositoryRoot rev-parse HEAD 2>&1
if ($LASTEXITCODE -eq 0) {
    $headSha = (@($headOutput) | Select-Object -First 1).ToString().Trim()
}

$startedAt = [DateTimeOffset]::UtcNow
$snapshot = Invoke-LiveScenario -Mode Snapshot -ScriptPath $snapshotScript
$fullHistory = Invoke-LiveScenario -Mode FullHistory -ScriptPath $fullHistoryScript

$result = [ordered] @{
    SchemaVersion = 1
    CharacterizationKind = 'LiveGitHubE2EBaseline'
    StartedAtUtc = $startedAt.ToString('o')
    RepositoryCommitSha = $headSha
    Owner = $Owner
    EvidencePath = $resolvedOutput
    Environment = [ordered] @{
        OperatingSystem = [System.Runtime.InteropServices.RuntimeInformation]::OSDescription
        OSArchitecture = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
        ProcessArchitecture = [System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString()
        PowerShellVersion = $PSVersionTable.PSVersion.ToString()
        GitVersion = $gitVersion
        GitLfsVersion = $gitLfsVersion
        GitHubCliVersion = $ghVersion
    }
    Scenarios = @($snapshot, $fullHistory)
    Interpretation = [ordered] @{
        IsReleaseSla = $false
        IsBlockingCiEvidence = $false
        IncludesGitHubNetworkOrApiLatency = $true
        MemoryBehavior = 'Unknown'
        Notes = @(
            'This run characterizes the existing authenticated Snapshot and FullHistory live E2E baselines against GitHub.com.',
            'The local scale profiles remain the authority for controlled history/ref/content/LFS dimensional characterization.',
            'Elapsed time includes GitHub service, network, repository creation, publication, verification, and cleanup variability.',
            'Memory remains Unknown because this wrapper does not claim whole-operation child-process peak-memory measurement.'
        )
    }
}

$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resolvedOutput -Encoding utf8
if (-not (Test-Path -LiteralPath $resolvedOutput -PathType Leaf)) {
    throw "Live characterization completed but the evidence file was not retained at '$resolvedOutput'."
}

[pscustomobject] $result
Write-Information "Live characterization evidence: $resolvedOutput" -InformationAction Continue

if (-not $snapshot.Success -or -not $fullHistory.Success) {
    throw "One or more live characterization scenarios failed. Evidence was retained at '$resolvedOutput'."
}
