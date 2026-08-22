BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:modulePath = Join-Path $repositoryRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
    Import-Module $script:modulePath -Force
}

Describe 'Migration recovery reporting' {
    It 'writes a durable JSON recovery record with bounded guidance' {
        InModuleScope CopyGitHubRepo {
            $plan = [pscustomobject] @{
                SourceRepository = 'infoconex/source'
                DestinationRepository = 'infoconex/destination'
                SourceVisibility = 'private'
                DestinationVisibility = 'private'
                ContentMode = 'Snapshot'
                SourceDefaultBranch = 'main'
                SourceState = [pscustomobject] @{ ContentMode = 'Snapshot'; Repository = 'infoconex/source'; DefaultBranch = 'main'; CommitSha = 'source-commit'; TreeSha = 'source-tree' }
            }
            $destination = [pscustomobject] @{ FullName = 'infoconex/destination'; HtmlUrl = 'https://github.com/infoconex/destination' }
            $exception = [System.InvalidOperationException]::new('Simulated snapshot push failure.')
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                $exception,
                'DestinationRepositorySnapshotPushFailed',
                [System.Management.Automation.ErrorCategory]::InvalidOperation,
                'infoconex/destination'
            )
            $completedSteps = @([pscustomobject] @{ Order = 1; Name = 'CreateDestinationRepository'; MutatedGitHub = $true; Verified = $true })
            $preferredPath = Join-Path $TestDrive 'migration-report.md'

            $recoveryPath = Write-CgrMigrationRecoveryReport `
                -Plan $plan `
                -DestinationRepository $destination `
                -FailureStage 'CopySnapshot' `
                -ErrorRecord $errorRecord `
                -CompletedSteps $completedSteps `
                -PreferredReportPath $preferredPath

            $recoveryPath | Should -Be ([System.IO.Path]::GetFullPath("$preferredPath.recovery.json"))
            Test-Path -LiteralPath $recoveryPath | Should -BeTrue
            $recovery = Get-Content -LiteralPath $recoveryPath -Raw | ConvertFrom-Json
            $recovery.Status | Should -Be 'FailedAfterDestinationCreation'
            $recovery.DestinationRepository | Should -Be 'infoconex/destination'
            $recovery.DestinationVisibility | Should -Be 'private'
            $recovery.FailureStage | Should -Be 'CopySnapshot'
            $recovery.ErrorId | Should -Match 'DestinationRepositorySnapshotPushFailed'
            @($recovery.CompletedSteps).Count | Should -Be 1
            $recovery.Recovery.DestinationWasCreated | Should -BeTrue
            $recovery.Recovery.AutomaticDeletionAttempted | Should -BeFalse
            $recovery.Recovery.SourceRepositoryMutated | Should -BeFalse
            @($recovery.Recovery.RecommendedActions).Count | Should -BeGreaterThan 0
        }
    }

    It 'persists recovery information before rethrowing a failure after destination creation' {
        InModuleScope CopyGitHubRepo {
            $source = [pscustomobject] @{
                Id = 101L; NodeId = 'R_source'; FullName = 'infoconex/source'; Owner = 'infoconex'; Visibility = 'private'; DefaultBranch = 'main'
                Description = 'Source repository.'; CloneUrl = 'https://github.com/infoconex/source.git'; HostName = 'github.com'
            }
            $destination = [pscustomobject] @{
                Id = 202L; NodeId = 'R_destination'; FullName = 'infoconex/destination'; Owner = 'infoconex'; Visibility = 'private'; DefaultBranch = 'main'
                HtmlUrl = 'https://github.com/infoconex/destination'; CloneUrl = 'https://github.com/infoconex/destination.git'; HostName = 'github.com'
            }
            $plan = [pscustomobject] @{
                Mode = 'NewDestination'
                SourceRepository = 'infoconex/source'
                DestinationRepository = 'infoconex/destination'
                SourceVisibility = 'private'
                DestinationVisibility = 'private'
                ContentMode = 'Snapshot'
                SourceDefaultBranch = 'main'
                CommitMessage = 'Initial repository commit'
                SkipSettings = $false
                SourceState = [pscustomobject] @{
                    ContentMode = 'Snapshot'; Repository = 'infoconex/source'; RepositoryId = 101L; RepositoryNodeId = 'R_source'
                    DefaultBranch = 'main'; CommitSha = 'source-commit'; TreeSha = 'source-tree'; GitLfsObjectsAvailable = $false; GitLfsPointerFiles = @()
                }
            }

            Mock Assert-CgrApprovedSourceState { [pscustomobject] @{ DefaultBranch = 'main'; CommitSha = 'source-commit'; TreeSha = 'source-tree' } }
            Mock New-CgrGitHubRepository { $destination }
            Mock Copy-CgrRepositorySnapshot {
                $exception = [System.InvalidOperationException]::new('Simulated snapshot push failure.')
                throw [System.Management.Automation.ErrorRecord]::new(
                    $exception,
                    'DestinationRepositorySnapshotPushFailed',
                    [System.Management.Automation.ErrorCategory]::InvalidOperation,
                    'infoconex/destination'
                )
            }
            Mock Write-CgrMigrationRecoveryReport { 'C:\recovery\migration.json' } -ParameterFilter {
                $Plan.DestinationRepository -eq 'infoconex/destination' -and
                $DestinationRepository.FullName -eq 'infoconex/destination' -and
                $FailureStage -eq 'CopySnapshot' -and
                @($CompletedSteps).Count -eq 1 -and
                @($CompletedSteps)[0].Name -eq 'CreateDestinationRepository'
            }

            { Invoke-CgrApprovedMigrationPlan -Plan $plan -SourceRepository $source -ReportPath './migration-report.md' } | Should -Throw

            Should -Invoke Assert-CgrApprovedSourceState -Times 1 -Exactly
            Should -Invoke New-CgrGitHubRepository -Times 1 -Exactly
            Should -Invoke Write-CgrMigrationRecoveryReport -Times 1 -Exactly
        }
    }
}
