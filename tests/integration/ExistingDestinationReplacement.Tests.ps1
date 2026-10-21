BeforeAll {
    $root = Split-Path -Parent $PSScriptRoot
    $modulePath = Join-Path $root 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
    Import-Module $modulePath -Force
}

Describe 'Existing destination archive and replace planning' {
    It 'plans archive before replacement creation when an existing destination is explicitly preserved' {
        InModuleScope CopyGitHubRepo {
            $source = [pscustomobject] @{
                FullName = 'infoconex/source'
                Owner = 'infoconex'
                Visibility = 'public'
                DefaultBranch = 'main'
            }
            Mock Test-CgrGitHubRepositoryExistence { param($Repository) $Repository -eq 'infoconex/destination' }
            Mock Get-CgrApprovedSourceState {
                [pscustomobject] @{ ContentMode = 'Snapshot'; Repository = 'infoconex/source'; DefaultBranch = 'main'; CommitSha = 'source-commit'; TreeSha = 'source-tree' }
            }

            $plan = New-CgrMigrationPlan `
                -SourceRepository $source `
                -DestinationRepository 'infoconex/destination' `
                -ContentMode Snapshot `
                -DestinationVisibility public `
                -ExistingDestinationArchiveName 'destination-archive-20260813-213700' `
                -CommitMessage 'Initial repository commit' `
                -PlanOnly

            $plan.Mode | Should -Be 'ExistingDestinationReplacement'
            $plan.DestinationExistedBeforeMigration | Should -BeTrue
            $plan.ArchiveRepository | Should -Be 'infoconex/destination-archive-20260813-213700'
            $plan.SourceState.CommitSha | Should -Be 'source-commit'
            @($plan.Steps)[0].Name | Should -Be 'PreserveDestinationAsArchive'
            @($plan.Steps)[1].Name | Should -Be 'CreateReplacementRepository'
        }
    }

    It 'rejects an archive-name collision before source-state capture or mutation' {
        InModuleScope CopyGitHubRepo {
            $source = [pscustomobject] @{
                FullName = 'infoconex/source'
                Owner = 'infoconex'
                Visibility = 'public'
                DefaultBranch = 'main'
            }
            Mock Test-CgrGitHubRepositoryExistence { $true }
            Mock Get-CgrApprovedSourceState { throw 'source-state capture must not run after archive collision' }

            {
                New-CgrMigrationPlan `
                    -SourceRepository $source `
                    -DestinationRepository 'infoconex/destination' `
                    -ContentMode Snapshot `
                    -DestinationVisibility public `
                    -ExistingDestinationArchiveName 'destination-archive' `
                    -CommitMessage 'Initial repository commit' `
                    -PlanOnly
            } | Should -Throw -ErrorId 'ExistingDestinationArchiveAlreadyExists,New-CgrMigrationPlan'
        }
    }
}

Describe 'Existing destination archive and replace confirmation' {
    It 'requires the exact destination archive and replacement names' {
        InModuleScope CopyGitHubRepo {
            $plan = [pscustomobject] @{ DestinationRepository = 'infoconex/destination'; ArchiveRepository = 'infoconex/destination-archive' }
            $expected = 'DESTINATION=infoconex/destination;ARCHIVE=infoconex/destination-archive;REPLACEMENT=infoconex/destination'

            Assert-CgrExistingDestinationReplacementConfirmation -Plan $plan -Confirmation $expected | Should -BeTrue
            { Assert-CgrExistingDestinationReplacementConfirmation -Plan $plan -Confirmation 'destination' } |
                Should -Throw -ErrorId 'ExistingDestinationReplacementConfirmationRequired,Assert-CgrExistingDestinationReplacementConfirmation'
        }
    }
}

Describe 'Existing destination archive and replace recovery' {
    It 'preserves the renamed destination and records recovery when replacement copy fails' {
        InModuleScope CopyGitHubRepo {
            $source = [pscustomobject] @{ FullName = 'infoconex/source'; Id = 10 }
            $existingDestination = [pscustomobject] @{ FullName = 'infoconex/destination'; Id = 20 }
            $sourceState = [pscustomobject] @{ ContentMode = 'Snapshot'; Repository = 'infoconex/source'; RepositoryId = 10; DefaultBranch = 'main'; CommitSha = 'source-commit'; TreeSha = 'source-tree' }
            $plan = [pscustomobject] @{
                SourceRepository = 'infoconex/source'
                DestinationRepository = 'infoconex/destination'
                ArchiveRepository = 'infoconex/destination-archive'
                DestinationVisibility = 'public'
                ContentMode = 'Snapshot'
                SourceState = $sourceState
            }

            Mock Assert-CgrApprovedSourceState { [pscustomobject] @{ DefaultBranch = 'main'; CommitSha = 'source-commit'; TreeSha = 'source-tree' } }
            Mock Rename-CgrGitHubRepository { [pscustomobject] @{ FullName = 'infoconex/destination-archive'; Id = 20 } }
            Mock New-CgrGitHubRepository { [pscustomobject] @{ FullName = 'infoconex/destination'; Id = 30 } }
            Mock Invoke-CgrNewDestinationSnapshot { throw 'Synthetic copy failure.' }
            Mock Write-CgrExistingDestinationRecoveryReport { 'recovery.json' }

            {
                Invoke-CgrExistingDestinationReplacement `
                    -Plan $plan `
                    -SourceRepository $source `
                    -ExistingDestinationRepository $existingDestination
            } | Should -Throw '*Synthetic copy failure*'

            Should -Invoke Assert-CgrApprovedSourceState -Times 1 -Exactly
            Should -Invoke Rename-CgrGitHubRepository -Times 1 -Exactly
            Should -Invoke New-CgrGitHubRepository -Times 1 -Exactly
            Should -Invoke Write-CgrExistingDestinationRecoveryReport -Times 1 -Exactly -ParameterFilter {
                $ArchiveRepository.FullName -eq 'infoconex/destination-archive' -and
                $DestinationRepository.FullName -eq 'infoconex/destination' -and
                $FailureStage -eq 'CopySnapshot'
            }
        }
    }
}


Describe 'Existing destination durable recovery report I/O boundary' {
    It 'fails a final execution report at an existing directory while writing a sibling recovery report' {
        InModuleScope CopyGitHubRepo {
            $probeRoot = Join-Path ([System.IO.Path]::GetTempPath()) "cgr-recovery-report-contract-$([guid]::NewGuid().ToString('N'))"
            New-Item -Path $probeRoot -ItemType Directory -ErrorAction Stop | Out-Null
            try {
                $reportTarget = Join-Path $probeRoot 'blocked-execution-report.json'
                New-Item -Path $reportTarget -ItemType Directory -ErrorAction Stop | Out-Null
                Mock Format-CgrMigrationExecutionResult { '{"fixture":true}' }

                $reportError = $null
                try {
                    Write-CgrMigrationExecutionReport -Result ([pscustomobject] @{}) -Path $reportTarget -ErrorAction Stop
                }
                catch { $reportError = $_ }
                $reportError | Should -Not -BeNullOrEmpty
                (Test-Path -LiteralPath $reportTarget -PathType Container) | Should -BeTrue

                $plan = [pscustomobject] @{
                    SourceRepository = 'infoconex/fixture-source'
                    DestinationRepository = 'infoconex/fixture-destination'
                    ArchiveRepository = 'infoconex/fixture-archive'
                    ContentMode = 'Snapshot'
                }
                $archive = [pscustomobject] @{ FullName = $plan.ArchiveRepository; Id = 20 }
                $replacement = [pscustomobject] @{ FullName = $plan.DestinationRepository; Id = 30 }
                $steps = @(
                    [pscustomobject] @{ Order = 1; Name = 'PreserveDestinationAsArchive'; MutatedGitHub = $true; Verified = $true }
                    [pscustomobject] @{ Order = 2; Name = 'VerifyArchivedDestinationIdentity'; MutatedGitHub = $false; Verified = $true }
                    [pscustomobject] @{ Order = 3; Name = 'CreateReplacementRepository'; MutatedGitHub = $true; Verified = $true }
                    [pscustomobject] @{ Order = 4; Name = 'VerifyReplacementRepositoryIdentity'; MutatedGitHub = $false; Verified = $true }
                )

                $savedPath = Write-CgrExistingDestinationRecoveryReport `
                    -Plan $plan `
                    -OriginalDestinationRepositoryId 20 `
                    -ArchiveRepository $archive `
                    -DestinationRepository $replacement `
                    -FailureStage 'WriteCompletionReport' `
                    -ErrorRecord $reportError `
                    -CompletedSteps $steps `
                    -PreferredReportPath $reportTarget

                $savedPath | Should -Be ([System.IO.Path]::GetFullPath("$reportTarget.recovery.json"))
                (Test-Path -LiteralPath $savedPath -PathType Leaf) | Should -BeTrue
                $recovery = Get-Content -LiteralPath $savedPath -Raw | ConvertFrom-Json
                $recovery.Status | Should -Be 'ExistingDestinationReplacementFailed'
                $recovery.FailureStage | Should -Be 'WriteCompletionReport'
                $recovery.ErrorId | Should -Be $reportError.FullyQualifiedErrorId
                $recovery.OriginalDestinationRepositoryId | Should -Be 20
                $recovery.ArchiveRepositoryId | Should -Be 20
                $recovery.ReplacementRepositoryId | Should -Be 30
                $recovery.Recovery.AutomaticRollbackAttempted | Should -BeFalse
                $recovery.Recovery.AutomaticDeletionAttempted | Should -BeFalse
                @($recovery.CompletedSteps).Count | Should -Be 4
            }
            finally {
                Remove-Item -LiteralPath $probeRoot -Recurse -Force -ErrorAction Stop
            }
        }
    }
}
