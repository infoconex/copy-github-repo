BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:prereleaseInstallerPath = Join-Path $repositoryRoot 'install-prerelease.ps1'
}

Describe 'Prerelease bootstrap installer' {
    It 'resolves main to an immutable commit before downloading source' {
        Test-Path -LiteralPath $script:prereleaseInstallerPath -PathType Leaf | Should -BeTrue

        $content = Get-Content -LiteralPath $script:prereleaseInstallerPath -Raw
        $commitLookupIndex = $content.IndexOf('Invoke-RestMethod -Uri $commitApiUrl')
        $commitValidationIndex = $content.IndexOf('$commitSha -notmatch ''^[a-fA-F0-9]{40}$''')
        $archiveUrlIndex = $content.IndexOf('$archiveUrl = "https://github.com/$repository/archive/$commitSha.zip"')
        $downloadIndex = $content.IndexOf('Invoke-WebRequest -Uri $archiveUrl')
        $extractIndex = $content.IndexOf('Expand-Archive')
        $installerIndex = $content.IndexOf('& $installerPath')

        $content | Should -Match '\$branch = ''main'''
        $content | Should -Match '/commits/\$branch'
        $content | Should -Not -Match '/releases/latest'
        $content | Should -Not -Match '/archive/main\.zip'
        $commitLookupIndex | Should -BeGreaterThan -1
        $commitValidationIndex | Should -BeGreaterThan $commitLookupIndex
        $archiveUrlIndex | Should -BeGreaterThan $commitValidationIndex
        $downloadIndex | Should -BeGreaterThan $archiveUrlIndex
        $extractIndex | Should -BeGreaterThan $downloadIndex
        $installerIndex | Should -BeGreaterThan $extractIndex
    }

    It 'reuses the packaged installer contract and supports explicit replacement' {
        $content = Get-Content -LiteralPath $script:prereleaseInstallerPath -Raw

        $content | Should -Match '\[switch\] \$Force'
        $content | Should -Match '& \$installerPath -Force'
        $content | Should -Match '& \$installerPath\s*\r?\n'
        $content | Should -Match 'Installing unreleased CopyGitHubRepo source from commit \$commitSha'
        $content | Should -Match 'finally'
        $content | Should -Match 'Remove-Item -LiteralPath \$temporaryRoot -Recurse -Force'
    }

    It 'recognizes deliberate application errors without diagnostic noise' {
        $content = Get-Content -LiteralPath $script:prereleaseInstallerPath -Raw

        $content | Should -Match 'CopyGitHubRepo\.ApplicationError'
        $content | Should -Match 'CopyGitHubRepo\.ErrorId'
        $content | Should -Match 'Test-CgrApplicationErrorRecord -ErrorRecord \$_'
        $content | Should -Match '\$errorId -eq ''CopyGitHubRepo\.VersionAlreadyInstalled'''
        $content | Should -Match 'No changes were made\. Use -Force to replace that version\.'
        $content | Should -Match 'Write-Warning \$friendlyMessage'
        $content | Should -Match 'Write-Error -Message "CopyGitHubRepo: \$message"'
    }

    It 'formats unexpected exceptions with diagnostics before rethrowing' {
        $content = Get-Content -LiteralPath $script:prereleaseInstallerPath -Raw
        $diagnosticIndex = $content.IndexOf('Write-CgrUnhandledError -ErrorRecord $_')
        $rethrowMatch = [regex]::Match($content.Substring($diagnosticIndex), '(?m)^\s{4}throw\r?$')

        $content | Should -Match 'CopyGitHubRepo encountered an unexpected error\.'
        $content | Should -Match 'ExceptionType:'
        $content | Should -Match 'FullyQualifiedErrorId:'
        $content | Should -Match 'ScriptStackTrace:'
        $content | Should -Match 'InnerException\['
        $diagnosticIndex | Should -BeGreaterThan -1
        $rethrowMatch.Success | Should -BeTrue
    }
}
