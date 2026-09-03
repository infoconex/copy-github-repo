#requires -Version 7.4

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$testsRoot = Join-Path $repositoryRoot 'tests'
$contractTestsPath = Join-Path $testsRoot 'contract'
$executionRoot = Join-Path $repositoryRoot '.documentation-test-execution'
$testResultsPath = Join-Path $repositoryRoot 'TestResults'
$testResultPath = Join-Path $testResultsPath 'documentation-test-results.xml'

$documentationTestNames = @(
    'AccessibilityDocumentation.Tests.ps1'
    'CapabilityReadinessDocumentation.Tests.ps1'
    'CommandReferenceDocumentation.Tests.ps1'
    'DocumentationContract.Tests.ps1'
    'DocumentationStrategy.Tests.ps1'
    'DurableDocumentationIssueReferences.Tests.ps1'
    'GitHubPagesDocumentation.Tests.ps1'
    'GovernanceDocumentation.Tests.ps1'
    'IncidentResponseDocumentation.Tests.ps1'
    'ProductModelDocumentation.Tests.ps1'
    'UserGuideDocumentation.Tests.ps1'
    'TroubleshootingRecoveryDocumentation.Tests.ps1'
    'NonFunctionalRequirementsDocumentation.Tests.ps1'
    'MaintainerGuideDocumentation.Tests.ps1'
    'QualityStrategyDocumentation.Tests.ps1'
    'ArchitectureDocumentation.Tests.ps1'
    'SecurityArchitectureDocumentation.Tests.ps1'
    'RepositorySecurityBaselineDocumentation.Tests.ps1'
    'SoftwareAssuranceDocumentation.Tests.ps1'
    'SupportPolicyDocumentation.Tests.ps1'
    'VulnerabilityApplicabilityDocumentation.Tests.ps1'
    'InstallationSecurity.Tests.ps1'
    'PowerShellGalleryRelease.Tests.ps1'
    'ReleaseReadiness.Tests.ps1'
    'ReleaseRunbookDocumentation.Tests.ps1'
    'UninstallDocumentation.Tests.ps1'
)

$documentationSourceTests = @($documentationTestNames | ForEach-Object { Join-Path $contractTestsPath $_ })
$missingTests = @($documentationSourceTests | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) })
if ($missingTests.Count -gt 0) {
    throw "Expected documentation test file(s) were not found: $($missingTests -join ', ')"
}

New-Item -Path $testResultsPath -ItemType Directory -Force | Out-Null
if (Test-Path -LiteralPath $executionRoot) {
    Remove-Item -LiteralPath $executionRoot -Recurse -Force
}
New-Item -Path $executionRoot -ItemType Directory -Force | Out-Null

try {
    # Stage the full Contract suite at the historical one-level test depth so documentation
    # suites retain their existing repository-root and sibling-file semantics after nesting.
    foreach ($contractTest in @(Get-ChildItem -LiteralPath $contractTestsPath -Filter '*.Tests.ps1' -File)) {
        Copy-Item -LiteralPath $contractTest.FullName -Destination (Join-Path $executionRoot $contractTest.Name) -Force
    }
    foreach ($supportFile in @(Get-ChildItem -LiteralPath $testsRoot -Filter '*.psd1' -File)) {
        Copy-Item -LiteralPath $supportFile.FullName -Destination (Join-Path $executionRoot $supportFile.Name) -Force
    }
    Copy-Item -LiteralPath (Join-Path $testsRoot 'e2e') -Destination (Join-Path $executionRoot 'e2e') -Recurse -Force

    $documentationTests = @($documentationTestNames | ForEach-Object { Join-Path $executionRoot $_ })

    $pesterConfiguration = New-PesterConfiguration
    $pesterConfiguration.Run.Path = $documentationTests
    $pesterConfiguration.Run.PassThru = $true
    $pesterConfiguration.Output.Verbosity = 'Detailed'
    $pesterConfiguration.TestResult.Enabled = $true
    $pesterConfiguration.TestResult.OutputPath = $testResultPath

    $pesterResult = Invoke-Pester -Configuration $pesterConfiguration
}
finally {
    Remove-Item -LiteralPath $executionRoot -Recurse -Force -ErrorAction SilentlyContinue
}

if ($pesterResult.FailedCount -gt 0) {
    throw "$($pesterResult.FailedCount) documentation Pester test(s) failed."
}
