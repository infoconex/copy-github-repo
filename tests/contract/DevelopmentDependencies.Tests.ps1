BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:dependencyVersionsPath = Join-Path $repositoryRoot 'build/DevelopmentDependencies.psd1'
    $script:dependencyMonitoringPath = Join-Path $repositoryRoot 'build/DevelopmentDependencyMonitoring.psd1'
    $script:dependencyInstallerPath = Join-Path $repositoryRoot 'build/Install-DevelopmentDependencies.ps1'
    $script:qualityGateWorkflowPath = Join-Path $repositoryRoot '.github/workflows/validate-project-quality.yml'
    $script:dependencyMonitorWorkflowPath = Join-Path $repositoryRoot '.github/workflows/monitor-dependencies.yml'
    $script:dependabotPath = Join-Path $repositoryRoot '.github/dependabot.yml'
    $script:releaseWorkflowPath = Join-Path $repositoryRoot '.github/workflows/publish-release.yml'
    $script:contributingPath = Join-Path $repositoryRoot 'CONTRIBUTING.md'
}

Describe 'Development dependency version ownership' {
    It 'defines the automated development module versions in one repository-owned data file' {
        $versions = Import-PowerShellDataFile -LiteralPath $script:dependencyVersionsPath

        @($versions.Keys | Sort-Object) | Should -Be @('Pester', 'PSScriptAnalyzer')
        foreach ($dependencyName in $versions.Keys) {
            { [version] $versions[$dependencyName] } | Should -Not -Throw
        }
    }

    It 'installs missing pinned development modules from the centralized version data' {
        $content = Get-Content -LiteralPath $script:dependencyInstallerPath -Raw

        $content | Should -Match 'Import-PowerShellDataFile.*DevelopmentDependencies\.psd1'
        $content | Should -Match 'foreach \(\$moduleName in @\(''Pester'', ''PSScriptAnalyzer''\)\)'
        $content | Should -Match '\$requiredVersion = \[version\] \[string\] \$dependencyVersions\[\$moduleName\]'
        $content | Should -Match 'Get-Module -ListAvailable -Name \$moduleName'
        $content | Should -Match '\$_.Version -eq \$requiredVersion'
        $content | Should -Match '(?s)Install-Module.*-Name \$moduleName.*-RequiredVersion \$requiredVersion.*-Repository PSGallery'
        $content | Should -Not -Match '-RequiredVersion\s+[0-9]'
    }

    It 'does not persistently change PSGallery trust while installing dependencies' {
        $content = Get-Content -LiteralPath $script:dependencyInstallerPath -Raw

        $content | Should -Not -Match 'Set-PSRepository'
        $content | Should -Not -Match 'InstallationPolicy'
        $content | Should -Match '-Repository PSGallery'
    }

    It 'has cross-platform CI consume the centralized installer' {
        $content = Get-Content -LiteralPath $script:qualityGateWorkflowPath -Raw

        $content | Should -Match 'run: \./build/Install-DevelopmentDependencies\.ps1'
        $content | Should -Not -Match 'Install-Module'
        $content | Should -Not -Match 'RequiredVersion'
    }

    It 'keeps release validation on the reusable quality workflow without separate dependency pins' {
        $content = Get-Content -LiteralPath $script:releaseWorkflowPath -Raw

        $content | Should -Match 'uses: \./\.github/workflows/validate-project-quality\.yml'
        $content | Should -Not -Match 'Install-Module'
        $content | Should -Not -Match 'RequiredVersion'
    }

    It 'keeps contributor guidance aligned to the centralized setup without restating module versions' {
        $content = Get-Content -LiteralPath $script:contributingPath -Raw

        $content | Should -Match '\./build/Install-DevelopmentDependencies\.ps1'
        $content | Should -Match 'build/DevelopmentDependencies\.psd1'
        $content | Should -Not -Match 'Install-Module'
        $content | Should -Not -Match '(?m)^- Pester\s+[0-9]'
        $content | Should -Not -Match '(?m)^- PSScriptAnalyzer\s+[0-9]'
    }
}

Describe 'Automated dependency and supply-chain monitoring' {
    It 'tracks a reviewed upstream baseline for every pinned PowerShell development dependency' {
        $versions = Import-PowerShellDataFile -LiteralPath $script:dependencyVersionsPath
        $monitoring = Import-PowerShellDataFile -LiteralPath $script:dependencyMonitoringPath

        $versionKeys = @($versions.Keys | Sort-Object)
        $monitoringKeys = @($monitoring.Keys | Sort-Object)
        $monitoringKeys.Count | Should -Be $versionKeys.Count
        @(Compare-Object -ReferenceObject $versionKeys -DifferenceObject $monitoringKeys) | Should -BeNullOrEmpty

        foreach ($dependencyName in $versions.Keys) {
            $policy = $monitoring[$dependencyName]
            { [version] $policy.ReviewedLatestStableVersion } | Should -Not -Throw
            [string] $policy.UpstreamRepository | Should -Match '^[^/]+/[^/]+$'
            [string] $policy.AdvisoryEcosystem | Should -Not -BeNullOrEmpty
            [string] $policy.AdvisoryPackage | Should -Be $dependencyName
            $policy.ContainsKey('ReviewedAdvisoryIds') | Should -BeTrue
            $policy.ReviewedAdvisoryIds.GetType().IsArray | Should -BeTrue
        }
    }

    It 'uses Dependabot to surface GitHub Actions updates weekly' {
        $content = Get-Content -LiteralPath $script:dependabotPath -Raw

        $content | Should -Match '(?m)^version:\s*2\s*$'
        $content | Should -Match 'package-ecosystem:\s*github-actions'
        $content | Should -Match '(?m)^\s*directory:\s*/\s*$'
        $content | Should -Match 'interval:\s*weekly'
    }

    It 'runs a read-only scheduled PowerShell dependency monitor with distinct freshness and advisory findings' {
        $content = Get-Content -LiteralPath $script:dependencyMonitorWorkflowPath -Raw

        $content | Should -Match '(?m)^name: Monitor Dependencies\r?$'
        $content | Should -Match "cron:"
        $content | Should -Match 'workflow_dispatch:'
        $content | Should -Match '(?s)permissions:.*contents:\s*read'
        $content | Should -Match 'actions/checkout@[0-9a-f]{40}'
        $content | Should -Match 'DevelopmentDependencies\.psd1'
        $content | Should -Match 'DevelopmentDependencyMonitoring\.psd1'
        $content | Should -Match 'powershellgallery\.com/api/v2/FindPackagesById'
        $content | Should -Not -Match 'IsLatestVersion'
        $content | Should -Match '\$stableVersions = \[System\.Collections\.Generic\.List\[version\]\]::new\(\)'
        $content | Should -Match 'while \(-not \[string\]::IsNullOrWhiteSpace\(\$galleryUri\)\)'
        $content | Should -Match '\$galleryFeed = \[xml\] \$galleryResponse\.Content'
        $content | Should -Match 'foreach \(\$entry in @\(\$galleryFeed\.feed\.entry\)\)'
        $content | Should -Match '\$isPrereleaseNode = \$entry\.properties\.IsPrerelease'
        $content | Should -Match '\$isPrereleaseNode\.InnerText'
        $content | Should -Match '\[bool\]::TryParse'
        $content | Should -Match 'if \(\$isPrerelease\)'
        $content | Should -Match '\$versionNode = \$entry\.properties\.Version'
        $content | Should -Match '\$versionNode\.InnerText'
        $content | Should -Match '\$stableVersions\.Add\(\[version\] \$versionText\)'
        $content | Should -Match 'Where-Object \{ \[string\] \$_\.rel -eq ''next'' \}'
        $content | Should -Match '\[string\] \$nextLinkNode\[0\]\.href'
        $content | Should -Match '\$stableVersions \| Sort-Object -Descending'
        $content | Should -Not -Match '\[string\] \$entry\.properties\.IsPrerelease'
        $content | Should -Not -Match '\[string\] \$entry\.properties\.Version'
        $content | Should -Not -Match 'Find-PSResource'
        $content | Should -Not -Match 'Find-Module'
        $content | Should -Not -Match 'AdditionalMetadata'
        $content | Should -Match 'api\.github\.com/advisories\?type='
        $content | Should -Match 'ecosystem=\$encodedEcosystem'
        $content | Should -Match 'affects=\$encodedPackage'
        $content | Should -Match '\$advisoryResponse = Invoke-RestMethod'
        $content | Should -Match 'foreach \(\$advisoryItem in @\(\$advisoryResponse\)\)'
        $content | Should -Not -Match '@\(Invoke-RestMethod'
        $content | Should -Not -Match 'security-advisories\?state=published'
        $content | Should -Match 'FRESHNESS:'
        $content | Should -Match 'SECURITY ADVISORY:'
        $content | Should -Not -Match 'Install-Module'
    }
}
