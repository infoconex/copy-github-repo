#requires -Version 7.4

[CmdletBinding()]
param(
    [ValidateSet('All', 'Unit', 'Integration', 'Contract')]
    [string] $Category = 'All',

    [switch] $AnalysisOnly,

    [switch] $SkipAnalysis,

    [switch] $CollectCoverage,

    [switch] $CoverageOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($AnalysisOnly -and $SkipAnalysis) {
    throw '-AnalysisOnly and -SkipAnalysis cannot be used together.'
}

if ($AnalysisOnly -and $CoverageOnly) {
    throw '-AnalysisOnly and -CoverageOnly cannot be used together.'
}

if ($AnalysisOnly -and $CollectCoverage) {
    throw '-AnalysisOnly and -CollectCoverage cannot be used together.'
}

if ($CoverageOnly -and $CollectCoverage) {
    throw '-CoverageOnly and -CollectCoverage cannot be used together.'
}

if ($CoverageOnly -and $Category -ne 'All') {
    throw '-CoverageOnly requires -Category All.'
}

if ($CollectCoverage -and $Category -eq 'All') {
    throw '-CollectCoverage requires a specific Unit, Integration, or Contract category.'
}

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $repositoryRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
$sourcePath = Join-Path $repositoryRoot 'src/CopyGitHubRepo'
$analyzerSettingsPath = Join-Path $repositoryRoot 'PSScriptAnalyzerSettings.psd1'
$testsRoot = Join-Path $repositoryRoot 'tests'
$taxonomyPath = Join-Path $testsRoot 'TestTaxonomy.psd1'
$testResultsPath = Join-Path $repositoryRoot 'TestResults'
$executionRoot = Join-Path $repositoryRoot '.pester-execution'
$minimumCoveragePercent = 65.0
$coverageCategories = @('Unit', 'Integration', 'Contract')

New-Item -Path $testResultsPath -ItemType Directory -Force | Out-Null

function ConvertTo-CgrCoverageCommandKey {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Command
    )

    [ordered] @{
        File = [string] $Command.File
        Line = [int] $Command.Line
        StartColumn = [int] $Command.StartColumn
        Command = [string] $Command.Command
    } | ConvertTo-Json -Compress
}

if ($CoverageOnly) {
    $coverageSnapshots = @(
        foreach ($coverageCategory in $coverageCategories) {
            $snapshotPath = Join-Path $testResultsPath ('coverage-{0}.json' -f $coverageCategory.ToLowerInvariant())
            if (-not (Test-Path -LiteralPath $snapshotPath -PathType Leaf)) {
                throw "Coverage snapshot '$snapshotPath' was not created by the categorized test phase."
            }

            Get-Content -LiteralPath $snapshotPath -Raw | ConvertFrom-Json
        }
    )

    $analyzedCounts = @($coverageSnapshots | ForEach-Object { [int] $_.CommandsAnalyzedCount } | Sort-Object -Unique)
    if ($analyzedCounts.Count -ne 1 -or $analyzedCounts[0] -le 0) {
        throw "Categorized coverage snapshots do not describe the same analyzed command set: $($analyzedCounts -join ', ')."
    }

    $aggregateMissedCommands = $null
    foreach ($snapshot in $coverageSnapshots) {
        $expectedMissedCount = [int] $snapshot.CommandsAnalyzedCount - [int] $snapshot.CommandsExecutedCount
        if (@($snapshot.CommandsMissed).Count -ne $expectedMissedCount) {
            throw "Coverage snapshot '$($snapshot.Category)' has inconsistent analyzed/executed/missed command counts."
        }

        $currentMissedCommands = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        foreach ($missedCommand in @($snapshot.CommandsMissed)) {
            $null = $currentMissedCommands.Add((ConvertTo-CgrCoverageCommandKey -Command $missedCommand))
        }

        if ($null -eq $aggregateMissedCommands) {
            $aggregateMissedCommands = $currentMissedCommands
        }
        else {
            $aggregateMissedCommands.IntersectWith($currentMissedCommands)
        }
    }

    $totalCommands = [int] $analyzedCounts[0]
    $missedCommands = [int] $aggregateMissedCommands.Count
    $coveredCommands = $totalCommands - $missedCommands
    $coveragePercent = ($coveredCommands / $totalCommands) * 100.0
    $coverageSummary = 'Code coverage: {0:N2}% ({1}/{2} commands; minimum {3:N2}%)' -f $coveragePercent, $coveredCommands, $totalCommands, $minimumCoveragePercent

    Write-Output $coverageSummary
    Set-Content `
        -LiteralPath (Join-Path $testResultsPath 'coverage-summary.txt') `
        -Value $coverageSummary `
        -Encoding utf8NoBOM

    [ordered] @{
        CoveragePercent = [math]::Round($coveragePercent, 4)
        CoveredCommands = $coveredCommands
        MissedCommands = $missedCommands
        CommandsAnalyzed = $totalCommands
        MinimumCoveragePercent = $minimumCoveragePercent
        Categories = $coverageCategories
    } | ConvertTo-Json | Set-Content `
        -LiteralPath (Join-Path $testResultsPath 'coverage-summary.json') `
        -Encoding utf8NoBOM

    if ($coveragePercent -lt $minimumCoveragePercent) {
        throw ('Code coverage {0:N2}% is below the required minimum of {1:N2}%.' -f $coveragePercent, $minimumCoveragePercent)
    }

    return
}

# Pester contract tests exercise custom analyzer rules that construct
# DiagnosticRecord instances. Load PSScriptAnalyzer explicitly so those CLR types
# are available even when static analysis is intentionally skipped for this phase.
Import-Module PSScriptAnalyzer -ErrorAction Stop
Import-Module $modulePath -Force -ErrorAction Stop

if (-not $SkipAnalysis) {
    Write-Output 'Running PSScriptAnalyzer.'
    $analysisResults = Invoke-ScriptAnalyzer `
        -Path $repositoryRoot `
        -Settings $analyzerSettingsPath `
        -Recurse

    if (@($analysisResults).Count -gt 0) {
        $formattedAnalysisResults = $analysisResults | Format-Table -AutoSize | Out-String
        Set-Content `
            -LiteralPath (Join-Path $testResultsPath 'script-analyzer.txt') `
            -Value $formattedAnalysisResults `
            -Encoding utf8NoBOM
        throw "PSScriptAnalyzer reported one or more findings.`n$formattedAnalysisResults"
    }

    Write-Output 'PSScriptAnalyzer passed.'
}

if ($AnalysisOnly) {
    return
}

$taxonomy = Import-PowerShellDataFile -LiteralPath $taxonomyPath
$categoryFiles = @{}
foreach ($categoryName in $coverageCategories) {
    $categoryRoot = Join-Path $repositoryRoot $taxonomy.Pester[$categoryName]
    $categoryFiles[$categoryName] = @(
        Get-ChildItem -LiteralPath $categoryRoot -Filter '*.Tests.ps1' -File |
            Sort-Object Name |
            Select-Object -ExpandProperty FullName
    )
}

$categoryCounts = @(
    'Unit={0}' -f $categoryFiles.Unit.Count
    'Integration={0}' -f $categoryFiles.Integration.Count
    'Contract={0}' -f $categoryFiles.Contract.Count
)
Write-Output "Pester suite taxonomy: $($categoryCounts -join ', ')"

$infrastructureTests = @($taxonomy.Infrastructure | ForEach-Object { Join-Path $repositoryRoot $_ })
if ($Category -eq 'All') {
    $sourceTestPaths = @(
        $categoryFiles.Unit
        $categoryFiles.Integration
        $categoryFiles.Contract
    )
    $testResultPath = Join-Path $testResultsPath 'test-results.xml'
}
else {
    $sourceTestPaths = @($categoryFiles[$Category])
    $testResultPath = Join-Path $testResultsPath ('test-results-{0}.xml' -f $Category.ToLowerInvariant())
}

$missingTests = @($sourceTestPaths + $infrastructureTests | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) })
if ($missingTests.Count -gt 0) {
    throw "Expected Pester test file(s) were not found: $($missingTests -join ', ')"
}

$duplicateNames = @(
    $sourceTestPaths |
        ForEach-Object { Split-Path -Leaf $_ } |
        Group-Object |
        Where-Object Count -GT 1
)
if ($duplicateNames.Count -gt 0) {
    throw "Categorized Pester suites must have unique filenames for execution: $($duplicateNames.Name -join ', ')"
}

if (Test-Path -LiteralPath $executionRoot) {
    Remove-Item -LiteralPath $executionRoot -Recurse -Force
}
New-Item -Path $executionRoot -ItemType Directory -Force | Out-Null

try {
    # Existing suites intentionally treat their script directory as one level below the
    # repository root. Execute categorized source files from a flat, temporary workspace
    # at that same depth so physical categorization does not silently change test meaning.
    $stagedTestPaths = @(
        foreach ($sourceTestPath in $sourceTestPaths) {
            $destinationPath = Join-Path $executionRoot (Split-Path -Leaf $sourceTestPath)
            Copy-Item -LiteralPath $sourceTestPath -Destination $destinationPath -Force
            $destinationPath
        }
    )

    foreach ($supportFile in @(Get-ChildItem -LiteralPath $testsRoot -Filter '*.psd1' -File)) {
        Copy-Item -LiteralPath $supportFile.FullName -Destination (Join-Path $executionRoot $supportFile.Name) -Force
    }
    Copy-Item -LiteralPath (Join-Path $testsRoot 'e2e') -Destination (Join-Path $executionRoot 'e2e') -Recurse -Force

    $testPaths = @($stagedTestPaths)
    if ($Category -in @('All', 'Contract')) {
        $testPaths += $infrastructureTests
    }

    Write-Output "Running Pester category: $Category ($(@($testPaths).Count) suite files)"

    $pesterConfiguration = New-PesterConfiguration
    $pesterConfiguration.Run.Path = $testPaths
    $pesterConfiguration.Run.PassThru = $true
    $pesterConfiguration.Output.Verbosity = if ($CollectCoverage) { 'Normal' } else { 'Detailed' }
    $pesterConfiguration.TestResult.Enabled = $true
    $pesterConfiguration.TestResult.OutputPath = $testResultPath

    if ($Category -eq 'All' -or $CollectCoverage) {
        $coverageResultPath = if ($Category -eq 'All') {
            Join-Path $testResultsPath 'coverage.xml'
        }
        else {
            Join-Path $testResultsPath ('coverage-{0}.xml' -f $Category.ToLowerInvariant())
        }

        $pesterConfiguration.CodeCoverage.Enabled = $true
        $pesterConfiguration.CodeCoverage.Path = $sourcePath
        $pesterConfiguration.CodeCoverage.OutputFormat = 'JaCoCo'
        $pesterConfiguration.CodeCoverage.OutputPath = $coverageResultPath
        $pesterConfiguration.CodeCoverage.CoveragePercentTarget = if ($CollectCoverage) { 0 } else { $minimumCoveragePercent }
    }

    $pesterResult = Invoke-Pester -Configuration $pesterConfiguration
}
finally {
    Remove-Item -LiteralPath $executionRoot -Recurse -Force -ErrorAction SilentlyContinue
}

if ($pesterResult.FailedCount -gt 0) {
    throw "$($pesterResult.FailedCount) Pester test(s) failed."
}

if ($CollectCoverage) {
    $coverageSnapshotPath = Join-Path $testResultsPath ('coverage-{0}.json' -f $Category.ToLowerInvariant())
    $coverageSnapshot = [ordered] @{
        Category = $Category
        CommandsAnalyzedCount = [int] $pesterResult.CodeCoverage.CommandsAnalyzedCount
        CommandsExecutedCount = [int] $pesterResult.CodeCoverage.CommandsExecutedCount
        CommandsMissed = @(
            $pesterResult.CodeCoverage.CommandsMissed | ForEach-Object {
                [ordered] @{
                    File = [string] $_.File
                    Line = [int] $_.Line
                    StartColumn = [int] $_.StartColumn
                    Command = [string] $_.Command
                }
            }
        )
    }

    $coverageSnapshot | ConvertTo-Json -Depth 5 | Set-Content `
        -LiteralPath $coverageSnapshotPath `
        -Encoding utf8NoBOM

    Write-Output "Pester category '$Category' passed and coverage evidence was saved to '$coverageSnapshotPath'."
    return
}

if ($Category -ne 'All') {
    Write-Output "Pester category '$Category' passed. Aggregate coverage is enforced by categorized Windows coverage collection in CI or by -Category All locally."
    return
}

if (-not (Test-Path -LiteralPath $coverageResultPath)) {
    throw "Pester did not create the expected coverage report '$coverageResultPath'."
}

[xml] $coverageDocument = Get-Content -LiteralPath $coverageResultPath -Raw
$instructionCounter = $coverageDocument.SelectSingleNode('/report/counter[@type="INSTRUCTION"]')
if ($null -eq $instructionCounter) {
    throw 'The Pester JaCoCo report does not contain an INSTRUCTION coverage counter.'
}

$coveredCommands = [double] $instructionCounter.covered
$missedCommands = [double] $instructionCounter.missed
$totalCommands = $coveredCommands + $missedCommands
if ($totalCommands -le 0) {
    throw 'The Pester coverage report did not analyze any commands.'
}

$coveragePercent = ($coveredCommands / $totalCommands) * 100.0
$coverageSummary = 'Code coverage: {0:N2}% (minimum {1:N2}%)' -f $coveragePercent, $minimumCoveragePercent
Write-Output $coverageSummary
Set-Content `
    -LiteralPath (Join-Path $testResultsPath 'coverage-summary.txt') `
    -Value $coverageSummary `
    -Encoding utf8NoBOM
if ($coveragePercent -lt $minimumCoveragePercent) {
    throw ('Code coverage {0:N2}% is below the required minimum of {1:N2}%.' -f $coveragePercent, $minimumCoveragePercent)
}
