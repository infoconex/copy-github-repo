BeforeAll {
    $script:repositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:modulePath = Join-Path $script:repositoryRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
    Import-Module $script:modulePath -Force
}

Describe 'Console presentation contract' {
    It 'registers the migration verification formatting view' {
        $manifest = Import-PowerShellDataFile -LiteralPath $script:modulePath

        @($manifest.FormatsToProcess) | Should -Contain 'CopyGitHubRepo.format.ps1xml'
    }

    It 'formats validation results as a concise human-readable summary' {
        $previousRendering = $PSStyle.OutputRendering
        try {
            $PSStyle.OutputRendering = [System.Management.Automation.OutputRendering]::PlainText
            $result = [pscustomobject] @{
                PSTypeName = 'CopyGitHubRepo.MigrationVerificationResult'
                SchemaVersion = 1
                ContentMode = 'Snapshot'
                SourceRepository = 'infoconex/source'
                DestinationRepository = 'infoconex/destination'
                BranchName = 'main'
                IsSuccessful = $false
                Checks = @(
                    [pscustomobject] @{
                        Name = 'DestinationExists'
                        Passed = $true
                        Expected = 'infoconex/destination'
                        Actual = 'infoconex/destination'
                    }
                    [pscustomobject] @{
                        Name = 'GitTreeMatches'
                        Passed = $false
                        Expected = 'expected-tree'
                        Actual = 'actual-tree'
                    }
                )
            }

            $checkMark = [char] 0x2713
            $crossMark = [char] 0x2717
            $text = $result | Out-String -Width 200

            $text | Should -Match 'Repository migration validation'
            $text | Should -Match ([regex]::Escape("$checkMark PASS  Destination repository exists"))
            $text | Should -Match ([regex]::Escape("$crossMark FAIL  Repository content matches"))
            $text | Should -Match 'Expected: expected-tree'
            $text | Should -Match 'Actual:\s+actual-tree'
            $text | Should -Match ([regex]::Escape("Result: $crossMark FAILED"))
            $text | Should -Not -Match 'SchemaVersion'
            $text.Contains([char] 27) | Should -BeFalse
        }
        finally {
            $PSStyle.OutputRendering = $previousRendering
        }
    }

    It 'keeps status meaning when color is explicitly disabled' {
        InModuleScope CopyGitHubRepo {
            $text = Format-CgrConsoleStatus -Status Warning -Message 'Review this setting.' -NoColor

            $text | Should -Be '! WARN  Review this setting.'
            $text.Contains([char] 27) | Should -BeFalse
        }
    }

    It 'honors NO_COLOR for interactive status text' {
        InModuleScope CopyGitHubRepo {
            $previousNoColor = $env:NO_COLOR
            try {
                $env:NO_COLOR = '1'
                $text = Format-CgrConsoleStatus -Status Success -Message 'Migration completed.'
                $checkMark = [char] 0x2713

                $text | Should -Be "$checkMark SUCCESS  Migration completed."
                $text.Contains([char] 27) | Should -BeFalse
            }
            finally {
                $env:NO_COLOR = $previousNoColor
            }
        }
    }
}
