#requires -Version 7.4

[CmdletBinding()]
param(
    [ValidateSet('All', 'Unit', 'Integration', 'Contract')]
    [string] $Category = 'All',

    [switch] $AnalysisOnly,

    [switch] $SkipAnalysis,

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

if ($CoverageOnly -and $Category -ne 'All') {
    throw '-CoverageOnly requires -Category All.'
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

New-Item -Path $testResultsPath -ItemType Directory -Force | Out-Null
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
foreach ($categoryName in @('Unit', 'Integration', 'Contract')) {
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
    $testResultPath = Join-Path $testResultsPath ("test-results-{0}.xml" -f $Category.ToLowerInvariant())
}

$missingTests = @($sourceTestPaths + $infrastructureTests | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) })
if ($missingTests.Count -gt 0) {
    throw "Expected Pester test file(s) were not found: $($missingTests -join ', ')"
}

$duplicateNames = @(
    $sourceTestPaths |
        ForEach-Object { Split-Path -Leaf $_ } |
        Group-Object |
        Where-Object Count -gt 1
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
    $pesterConfiguration.Output.Verbosity = if ($CoverageOnly) { 'Minimal' } else { 'Detailed' }
    $pesterConfiguration.TestResult.Enabled = $true
    $pesterConfiguration.TestResult.OutputPath = $testResultPath

    if ($Category -eq 'All') {
        $coverageResultPath = Join-Path $testResultsPath 'coverage.xml'
        $pesterConfiguration.CodeCoverage.Enabled = $true
        $pesterConfiguration.CodeCoverage.Path = $sourcePath
        $pesterConfiguration.CodeCoverage.OutputFormat = 'JaCoCo'
        $pesterConfiguration.CodeCoverage.OutputPath = $coverageResultPath
        $pesterConfiguration.CodeCoverage.CoveragePercentTarget = $minimumCoveragePercent
    }

    $pesterResult = Invoke-Pester -Configuration $pesterConfiguration
}
finally {
    Remove-Item -LiteralPath $executionRoot -Recurse -Force -ErrorAction SilentlyContinue
}

if ($pesterResult.FailedCount -gt 0) {
    throw "$($pesterResult.FailedCount) Pester test(s) failed."
}

if ($Category -ne 'All') {
    Write-Output "Pester category '$Category' passed. Aggregate coverage is enforced only by -Category All."
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
