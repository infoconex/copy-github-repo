[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })]
    [string] $FixturePath,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string] $OutputPath,

    [switch] $KeepWorkspace
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-CharacterizationGit {
    param(
        [Parameter(Mandatory)]
        [string[]] $ArgumentList,

        [Parameter(Mandatory)]
        [string] $WorkingDirectory
    )

    Push-Location $WorkingDirectory
    try {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $output = & git @ArgumentList 2>&1
        $exitCode = $LASTEXITCODE
        $stopwatch.Stop()
        if ($exitCode -ne 0) {
            throw "git $($ArgumentList -join ' ') failed with exit code $exitCode. $($output -join [Environment]::NewLine)"
        }

        [pscustomobject] @{
            Output = @($output)
            ElapsedMilliseconds = [long] $stopwatch.ElapsedMilliseconds
        }
    }
    finally {
        Pop-Location
    }
}

function Get-DirectoryByteCount {
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return [long] 0
    }

    $measurement = Get-ChildItem -LiteralPath $Path -File -Recurse -Force |
        Measure-Object -Property Length -Sum
    if ($null -eq $measurement.Sum) {
        return [long] 0
    }
    return [long] $measurement.Sum
}

function Get-FileSystemFreeByteCount {
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    $resolved = [System.IO.Path]::GetFullPath($Path)
    $root = [System.IO.Path]::GetPathRoot($resolved)
    try {
        return [long] ([System.IO.DriveInfo]::new($root).AvailableFreeSpace)
    }
    catch {
        return $null
    }
}

$resolvedFixture = [System.IO.Path]::GetFullPath($FixturePath)
$resolvedOutput = [System.IO.Path]::GetFullPath($OutputPath)
$outputDirectory = Split-Path -Parent $resolvedOutput
if (-not (Test-Path -LiteralPath $outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
}

$workspace = Join-Path ([System.IO.Path]::GetTempPath()) ('copy-github-repo-scale-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $workspace -Force | Out-Null

try {
    $startedAt = [DateTimeOffset]::UtcNow
    $initialFreeBytes = Get-FileSystemFreeByteCount -Path $workspace

    $gitVersion = (& git --version 2>&1) -join ' '
    if ($LASTEXITCODE -ne 0) {
        throw 'Git is required for scale characterization.'
    }

    $gitLfsVersion = $null
    $lfsVersionOutput = & git lfs version 2>&1
    if ($LASTEXITCODE -eq 0) {
        $gitLfsVersion = $lfsVersionOutput -join ' '
    }

    $commitResult = Invoke-CharacterizationGit -WorkingDirectory $resolvedFixture -ArgumentList @('rev-list', '--count', '--all')
    $branchResult = Invoke-CharacterizationGit -WorkingDirectory $resolvedFixture -ArgumentList @('for-each-ref', '--format=%(refname)', 'refs/heads')
    $tagResult = Invoke-CharacterizationGit -WorkingDirectory $resolvedFixture -ArgumentList @('for-each-ref', '--format=%(refname)', 'refs/tags')
    $countObjectsResult = Invoke-CharacterizationGit -WorkingDirectory $resolvedFixture -ArgumentList @('count-objects', '-vH')

    $gitDirectory = Join-Path $resolvedFixture '.git'
    $fixtureTotalBytes = Get-DirectoryByteCount -Path $resolvedFixture
    $fixtureGitBytes = Get-DirectoryByteCount -Path $gitDirectory
    $fixtureWorkingTreeBytes = [Math]::Max(0, $fixtureTotalBytes - $fixtureGitBytes)
    $fixtureLfsBytes = Get-DirectoryByteCount -Path (Join-Path $gitDirectory 'lfs/objects')

    $snapshotPath = Join-Path $workspace 'snapshot-clone'
    $snapshotClone = Invoke-CharacterizationGit -WorkingDirectory $workspace -ArgumentList @(
        'clone', '--no-local', '--depth=1', '--branch', 'main', $resolvedFixture, $snapshotPath
    )
    $snapshotBytes = Get-DirectoryByteCount -Path $snapshotPath

    $fullHistoryPath = Join-Path $workspace 'full-history.git'
    $fullHistoryClone = Invoke-CharacterizationGit -WorkingDirectory $workspace -ArgumentList @(
        'clone', '--mirror', $resolvedFixture, $fullHistoryPath
    )
    $fullHistoryBytes = Get-DirectoryByteCount -Path $fullHistoryPath

    $endingFreeBytes = Get-FileSystemFreeByteCount -Path $workspace
    $workspaceBytes = Get-DirectoryByteCount -Path $workspace
    $observedFreeSpaceDelta = if ($null -ne $initialFreeBytes -and $null -ne $endingFreeBytes) {
        [long] ($initialFreeBytes - $endingFreeBytes)
    }
    else {
        $null
    }

    $result = [ordered] @{
        SchemaVersion = 1
        CharacterizationKind = 'LocalGitSubstrate'
        StartedAtUtc = $startedAt.ToString('o')
        FixturePath = $resolvedFixture
        Environment = [ordered] @{
            OperatingSystem = [System.Runtime.InteropServices.RuntimeInformation]::OSDescription
            OSArchitecture = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
            ProcessArchitecture = [System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString()
            PowerShellVersion = $PSVersionTable.PSVersion.ToString()
            GitVersion = $gitVersion
            GitLfsVersion = $gitLfsVersion
            TempPath = [System.IO.Path]::GetTempPath()
        }
        Fixture = [ordered] @{
            CommitCount = [int] ($commitResult.Output | Select-Object -First 1)
            BranchCount = @($branchResult.Output | Where-Object { -not [string]::IsNullOrWhiteSpace([string] $_) }).Count
            TagCount = @($tagResult.Output | Where-Object { -not [string]::IsNullOrWhiteSpace([string] $_) }).Count
            WorkingTreeBytes = [long] $fixtureWorkingTreeBytes
            GitDirectoryBytes = [long] $fixtureGitBytes
            LfsObjectBytes = [long] $fixtureLfsBytes
            CountObjects = @($countObjectsResult.Output)
        }
        Stages = [ordered] @{
            SnapshotLocalClone = [ordered] @{
                ElapsedMilliseconds = [long] $snapshotClone.ElapsedMilliseconds
                WorkspaceBytes = [long] $snapshotBytes
            }
            FullHistoryMirrorClone = [ordered] @{
                ElapsedMilliseconds = [long] $fullHistoryClone.ElapsedMilliseconds
                WorkspaceBytes = [long] $fullHistoryBytes
            }
        }
        LocalResources = [ordered] @{
            CharacterizationWorkspaceBytes = [long] $workspaceBytes
            FreeBytesBefore = $initialFreeBytes
            FreeBytesAfter = $endingFreeBytes
            ObservedFreeSpaceDeltaBytes = $observedFreeSpaceDelta
        }
        Interpretation = [ordered] @{
            IsReleaseSla = $false
            IsBlockingCiEvidence = $false
            IncludesGitHubNetworkOrApiLatency = $false
            Notes = @(
                'Results characterize local Git workspace behavior for this fixture and environment only.',
                'They do not establish a supported maximum repository size, completion-time SLA, or production GitHub service performance.',
                'End-to-end GitHub copy characterization must be recorded separately because network, API, authentication, and service variability are intentionally excluded here.'
            )
        }
    }

    $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resolvedOutput -Encoding utf8
    [pscustomobject] $result
}
finally {
    if (-not $KeepWorkspace -and (Test-Path -LiteralPath $workspace)) {
        Remove-Item -LiteralPath $workspace -Recurse -Force -ErrorAction SilentlyContinue
    }
}
