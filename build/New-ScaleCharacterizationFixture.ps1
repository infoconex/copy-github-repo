[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string] $Path,

    [ValidateRange(1, 5000)]
    [int] $CommitCount = 100,

    [ValidateRange(1, 1000)]
    [int] $BranchCount = 10,

    [ValidateRange(0, 2000)]
    [int] $TagCount = 25,

    [ValidateRange(1, 500)]
    [int] $TrackedFileCount = 20,

    [ValidateRange(1, 16384)]
    [int] $FileSizeKiB = 16,

    [ValidateRange(0, 200)]
    [int] $LfsFileCount = 0,

    [ValidateRange(1, 65536)]
    [int] $LfsFileSizeKiB = 1024,

    [switch] $Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-FixtureGit {
    param(
        [Parameter(Mandatory)]
        [string[]] $ArgumentList,

        [Parameter(Mandatory)]
        [string] $WorkingDirectory
    )

    Push-Location $WorkingDirectory
    try {
        $output = & git @ArgumentList 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "git $($ArgumentList -join ' ') failed with exit code $LASTEXITCODE. $($output -join [Environment]::NewLine)"
        }
        return @($output)
    }
    finally {
        Pop-Location
    }
}

function Write-DeterministicFile {
    param(
        [Parameter(Mandatory)]
        [string] $FilePath,

        [Parameter(Mandatory)]
        [long] $LengthBytes,

        [byte] $Seed = 65
    )

    $parent = Split-Path -Parent $FilePath
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $buffer = New-Object byte[] 65536
    for ($index = 0; $index -lt $buffer.Length; $index++) {
        $buffer[$index] = [byte] (($Seed + $index) % 251)
    }

    $stream = [System.IO.File]::Open($FilePath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
    try {
        $remaining = $LengthBytes
        while ($remaining -gt 0) {
            $count = [int] [Math]::Min($buffer.Length, $remaining)
            $stream.Write($buffer, 0, $count)
            $remaining -= $count
        }
    }
    finally {
        $stream.Dispose()
    }
}

$resolvedPath = [System.IO.Path]::GetFullPath($Path)
if (Test-Path -LiteralPath $resolvedPath) {
    if (-not $Force) {
        throw "Fixture path '$resolvedPath' already exists. Use -Force only when it is safe to replace it."
    }
    Remove-Item -LiteralPath $resolvedPath -Recurse -Force
}

New-Item -ItemType Directory -Path $resolvedPath -Force | Out-Null

$startedAt = [DateTimeOffset]::UtcNow
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

Invoke-FixtureGit -WorkingDirectory $resolvedPath -ArgumentList @('init', '--initial-branch=main') | Out-Null
Invoke-FixtureGit -WorkingDirectory $resolvedPath -ArgumentList @('config', 'user.name', 'CopyGitHubRepo Characterization') | Out-Null
Invoke-FixtureGit -WorkingDirectory $resolvedPath -ArgumentList @('config', 'user.email', 'characterization@example.invalid') | Out-Null
Invoke-FixtureGit -WorkingDirectory $resolvedPath -ArgumentList @('config', 'commit.gpgsign', 'false') | Out-Null
Invoke-FixtureGit -WorkingDirectory $resolvedPath -ArgumentList @('config', 'gc.auto', '0') | Out-Null
Invoke-FixtureGit -WorkingDirectory $resolvedPath -ArgumentList @('config', 'maintenance.auto', 'false') | Out-Null

if ($LfsFileCount -gt 0) {
    Invoke-FixtureGit -WorkingDirectory $resolvedPath -ArgumentList @('lfs', 'install', '--local') | Out-Null
    Invoke-FixtureGit -WorkingDirectory $resolvedPath -ArgumentList @('lfs', 'track', '*.lfs.bin') | Out-Null
}

$fileSizeBytes = [long] $FileSizeKiB * 1024
for ($fileIndex = 1; $fileIndex -le $TrackedFileCount; $fileIndex++) {
    $fileName = 'content/file-{0:D4}.bin' -f $fileIndex
    Write-DeterministicFile -FilePath (Join-Path $resolvedPath $fileName) -LengthBytes $fileSizeBytes -Seed ([byte] (($fileIndex % 200) + 1))
}

if ($LfsFileCount -gt 0) {
    $lfsSizeBytes = [long] $LfsFileSizeKiB * 1024
    for ($lfsIndex = 1; $lfsIndex -le $LfsFileCount; $lfsIndex++) {
        $fileName = 'lfs/object-{0:D4}.lfs.bin' -f $lfsIndex
        Write-DeterministicFile -FilePath (Join-Path $resolvedPath $fileName) -LengthBytes $lfsSizeBytes -Seed ([byte] (($lfsIndex % 200) + 25))
    }
}

Invoke-FixtureGit -WorkingDirectory $resolvedPath -ArgumentList @('add', '--all') | Out-Null
Invoke-FixtureGit -WorkingDirectory $resolvedPath -ArgumentList @('commit', '-m', 'Fixture seed') | Out-Null

$historyFile = Join-Path $resolvedPath 'history.txt'
for ($commitIndex = 2; $commitIndex -le $CommitCount; $commitIndex++) {
    Add-Content -LiteralPath $historyFile -Value ('commit-{0:D6}' -f $commitIndex) -Encoding utf8
    Invoke-FixtureGit -WorkingDirectory $resolvedPath -ArgumentList @('add', 'history.txt') | Out-Null
    Invoke-FixtureGit -WorkingDirectory $resolvedPath -ArgumentList @('commit', '-m', ('Fixture commit {0:D6}' -f $commitIndex)) | Out-Null
}

for ($branchIndex = 2; $branchIndex -le $BranchCount; $branchIndex++) {
    Invoke-FixtureGit -WorkingDirectory $resolvedPath -ArgumentList @('branch', ('fixture/branch-{0:D4}' -f $branchIndex)) | Out-Null
}

if ($TagCount -gt 0) {
    $commitShas = @(Invoke-FixtureGit -WorkingDirectory $resolvedPath -ArgumentList @('rev-list', '--reverse', 'main'))
    for ($tagIndex = 1; $tagIndex -le $TagCount; $tagIndex++) {
        $position = [int] [Math]::Floor((($tagIndex - 1) * $commitShas.Count) / $TagCount)
        if ($position -ge $commitShas.Count) {
            $position = $commitShas.Count - 1
        }
        Invoke-FixtureGit -WorkingDirectory $resolvedPath -ArgumentList @('tag', ('fixture-v{0:D4}' -f $tagIndex), $commitShas[$position]) | Out-Null
    }
}

$stopwatch.Stop()

$gitDirectory = Join-Path $resolvedPath '.git'
$workingTreeBytes = (Get-ChildItem -LiteralPath $resolvedPath -File -Recurse -Force |
    Where-Object { $_.FullName -notlike "$gitDirectory*" } |
    Measure-Object -Property Length -Sum).Sum
$gitBytes = (Get-ChildItem -LiteralPath $gitDirectory -File -Recurse -Force |
    Measure-Object -Property Length -Sum).Sum

[pscustomobject] @{
    SchemaVersion = 1
    FixturePath = $resolvedPath
    CreatedAtUtc = $startedAt.ToString('o')
    CommitCount = $CommitCount
    BranchCount = $BranchCount
    TagCount = $TagCount
    TrackedFileCount = $TrackedFileCount
    FileSizeKiB = $FileSizeKiB
    LfsFileCount = $LfsFileCount
    LfsFileSizeKiB = if ($LfsFileCount -gt 0) { $LfsFileSizeKiB } else { 0 }
    WorkingTreeBytes = [long] $workingTreeBytes
    GitDirectoryBytes = [long] $gitBytes
    FixtureCreationMilliseconds = [long] $stopwatch.ElapsedMilliseconds
}
