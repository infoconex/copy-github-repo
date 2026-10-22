BeforeAll {
    $root = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $root 'src/CopyGitHubRepo/CopyGitHubRepo.psd1') -Force
}

InModuleScope CopyGitHubRepo {
    Describe 'Existing-destination Snapshot recovery provenance' {
        BeforeEach {
            $script:recoverySourceState = [pscustomobject] @{
                ContentMode = 'Snapshot'
                Repository = 'infoconex/source'
                RepositoryId = 10L
                RepositoryNodeId = 'R_source'
                DefaultBranch = 'main'
                CommitSha = 'approved-source-commit'
                TreeSha = 'approved-source-tree'
            }
            $script:recoveryPlan = [pscustomobject] @{
                SourceRepository = 'infoconex/source'
                DestinationRepository = 'infoconex/destination'
                ArchiveRepository = 'infoconex/archive'
                DestinationVisibility = 'private'
                ContentMode = 'Snapshot'
                SourceDefaultBranch = 'main'
                SkipSettings = $true
                SourceState = $script:recoverySourceState
            }
            $script:recoverySource = [pscustomobject] @{ FullName = 'infoconex/source'; Id = 10L; NodeId = 'R_source' }
            $script:recoveryOriginal = [pscustomobject] @{ FullName = 'infoconex/destination'; Id = 20L; NodeId = 'R_original' }
            $script:recoveryArchive = [pscustomobject] @{ FullName = 'infoconex/archive'; Id = 20L; NodeId = 'R_original' }
            $script:recoveryReplacement = [pscustomobject] @{ FullName = 'infoconex/destination'; Id = 30L; NodeId = 'R_replacement' }

            Mock Assert-CgrApprovedSourceState { $true }
            Mock Rename-CgrGitHubRepository { $script:recoveryArchive }
            Mock New-CgrGitHubRepository { $script:recoveryReplacement }
            Mock Get-CgrSnapshotReleasePreservationEvidence { $null }
        }

        It 'writes the approved and actually verified Snapshot provenance after completion-report I/O failure' {
            Mock Invoke-CgrNewDestinationSnapshot {
                [pscustomobject] @{
                    Status = 'SnapshotVerifiedSettingsSkipped'
                    IsVerified = $true
                    Provenance = [pscustomobject] @{
                        CopiedSourceCommitSha = 'copied-source-commit'
                        CopiedSourceTreeSha = 'copied-source-tree'
                        DestinationRootCommitSha = 'destination-root'
                        DestinationTreeSha = 'do-not-trust-without-readback'
                        VerificationSuccessful = $true
                    }
                    Verification = [pscustomobject] @{
                        IsSuccessful = $true
                        DestinationTree = 'verified-destination-tree'
                    }
                    CompletedSteps = @(
                        [pscustomobject] @{ Order = 1; Name = 'CreateDestinationRepository'; MutatedGitHub = $true; Verified = $true }
                        [pscustomobject] @{ Order = 2; Name = 'CopySnapshot'; MutatedGitHub = $true; Verified = $true }
                        [pscustomobject] @{ Order = 3; Name = 'VerifySnapshot'; MutatedGitHub = $false; Verified = $true }
                        [pscustomobject] @{ Order = 4; Name = 'RestoreSupportedSettings'; MutatedGitHub = $false; Verified = $true }
                        [pscustomobject] @{ Order = 5; Name = 'RestoreRepositoryProtection'; MutatedGitHub = $false; Verified = $true }
                    )
                }
            }
            Mock Write-CgrMigrationExecutionReport { throw 'Synthetic local report I/O failure.' }
            $path = Join-Path $TestDrive 'after-copy.json'

            {
                Invoke-CgrExistingDestinationReplacement -Plan $script:recoveryPlan -SourceRepository $script:recoverySource -ExistingDestinationRepository $script:recoveryOriginal -ReportPath $path
            } | Should -Throw -ExpectedMessage '*Synthetic local report I/O failure*'

            $recoveryPath = "$path.recovery.json"
            Test-Path -LiteralPath $recoveryPath | Should -BeTrue
            $r = Get-Content -LiteralPath $recoveryPath -Raw | ConvertFrom-Json
            $r.SchemaVersion | Should -Be 1
            $r.Status | Should -Be 'ExistingDestinationReplacementFailed'
            $r.FailureStage | Should -Be 'WriteCompletionReport'
            $r.OriginalDestinationRepositoryId | Should -Be 20
            $r.ArchiveRepositoryId | Should -Be 20
            $r.ArchiveRepositoryNodeId | Should -Be 'R_original'
            $r.ReplacementRepositoryId | Should -Be 30
            $r.ReplacementRepositoryNodeId | Should -Be 'R_replacement'
            $r.ArchivedOriginalIdentityPreserved | Should -BeTrue
            $r.ReplacementHasDistinctIdentity | Should -BeTrue
            @($r.CompletedSteps).Name | Should -Be @(
                'PreserveDestinationAsArchive', 'VerifyArchivedDestinationIdentity',
                'CreateReplacementRepository', 'VerifyReplacementRepositoryIdentity',
                'CopySnapshot', 'VerifySnapshot', 'RestoreSupportedSettings', 'RestoreRepositoryProtection'
            )
            $r.Provenance.PlannedSourceState.RepositoryId | Should -Be 10
            $r.Provenance.PlannedSourceState.CommitSha | Should -Be 'approved-source-commit'
            $r.Provenance.SourceRepositoryNodeId | Should -Be 'R_source'
            $r.Provenance.SourceDefaultBranch | Should -Be 'main'
            $r.Provenance.SourceTreeSha | Should -Be 'approved-source-tree'
            $r.Provenance.CopiedSourceCommitSha | Should -Be 'copied-source-commit'
            $r.Provenance.CopiedSourceTreeSha | Should -Be 'copied-source-tree'
            $r.Provenance.DestinationRootCommitSha | Should -Be 'destination-root'
            $r.Provenance.DestinationTreeSha | Should -Be 'verified-destination-tree'
            $r.Provenance.VerificationSuccessful | Should -BeTrue
            $r.Provenance.ActualEvidenceAvailable | Should -BeTrue
            $r.Provenance.EvidenceLimitation | Should -BeNullOrEmpty
            $r.Recovery.AutomaticDeletionAttempted | Should -BeFalse
            $r.Recovery.AutomaticRollbackAttempted | Should -BeFalse
            Should -Invoke Write-CgrMigrationExecutionReport -Times 1 -Exactly
            Should -Invoke Rename-CgrGitHubRepository -Times 1 -Exactly
            Should -Invoke New-CgrGitHubRepository -Times 1 -Exactly
        }

        It 'preserves approved state but no invented destination provenance when the child copy throws' {
            Mock Invoke-CgrNewDestinationSnapshot { throw 'Synthetic failure before child result.' }
            $path = Join-Path $TestDrive 'copy-failed.json'

            {
                Invoke-CgrExistingDestinationReplacement -Plan $script:recoveryPlan -SourceRepository $script:recoverySource -ExistingDestinationRepository $script:recoveryOriginal -ReportPath $path
            } | Should -Throw -ExpectedMessage '*Synthetic failure before child result*'

            $r = Get-Content -LiteralPath "$path.recovery.json" -Raw | ConvertFrom-Json
            $r.FailureStage | Should -Be 'CopySnapshot'
            $r.ErrorMessage | Should -Match 'Synthetic failure before child result'
            $r.Provenance.PlannedSourceState.CommitSha | Should -Be 'approved-source-commit'
            $r.Provenance.PlannedSourceState.TreeSha | Should -Be 'approved-source-tree'
            $r.Provenance.CopiedSourceCommitSha | Should -BeNullOrEmpty
            $r.Provenance.CopiedSourceTreeSha | Should -BeNullOrEmpty
            $r.Provenance.DestinationRootCommitSha | Should -BeNullOrEmpty
            $r.Provenance.DestinationTreeSha | Should -BeNullOrEmpty
            $r.Provenance.VerificationSuccessful | Should -BeNullOrEmpty
            $r.Provenance.ActualEvidenceAvailable | Should -BeFalse
            $r.Provenance.EvidenceLimitation | Should -Match 'did not return a result'
            $r.ArchiveRepositoryId | Should -Be 20
            $r.ReplacementRepositoryId | Should -Be 30
            @($r.CompletedSteps).Count | Should -Be 4
            $r.Recovery.ExistingDestinationWasDeleted | Should -BeFalse
            $r.Recovery.AutomaticRollbackAttempted | Should -BeFalse
        }

        It 'records observed-but-unverified child evidence without assuming a destination tree' {
            $path = Join-Path $TestDrive 'unverified.json'
            $err = [System.Management.Automation.ErrorRecord]::new(
                [System.InvalidOperationException]::new('Snapshot verification mismatch.'),
                'SnapshotMismatch',
                [System.Management.Automation.ErrorCategory]::InvalidResult,
                'infoconex/destination'
            )
            $partial = [pscustomobject] @{
                Provenance = [pscustomobject] @{
                    CopiedSourceCommitSha = 'copied-source'
                    CopiedSourceTreeSha = 'copied-tree'
                    DestinationRootCommitSha = 'created-root'
                    DestinationTreeSha = 'source-fallback-must-not-be-used'
                    VerificationSuccessful = $false
                }
                Verification = [pscustomobject] @{ IsSuccessful = $false }
            }

            $recoveryPath = Write-CgrExistingDestinationRecoveryReport -Plan $script:recoveryPlan -OriginalDestinationRepositoryId 20 -OriginalDestinationRepositoryNodeId 'R_original' -ArchiveRepository $script:recoveryArchive -DestinationRepository $script:recoveryReplacement -FailureStage VerifySnapshot -ErrorRecord $err -SnapshotResult $partial -PreferredReportPath $path
            $r = Get-Content -LiteralPath $recoveryPath -Raw | ConvertFrom-Json
            $r.Provenance.PlannedSourceState.CommitSha | Should -Be 'approved-source-commit'
            $r.Provenance.CopiedSourceTreeSha | Should -Be 'copied-tree'
            $r.Provenance.DestinationRootCommitSha | Should -Be 'created-root'
            $r.Provenance.DestinationTreeSha | Should -BeNullOrEmpty
            $r.Provenance.VerificationSuccessful | Should -BeFalse
            $r.Provenance.ActualEvidenceAvailable | Should -BeTrue
            $r.Provenance.EvidenceLimitation | Should -Match 'not successful'
            $r.Recovery.AutomaticRollbackAttempted | Should -BeFalse
        }

        It 'retains the primary copy failure when the recovery writer also throws' {
            Mock Invoke-CgrNewDestinationSnapshot { throw 'Original Snapshot copy failure.' }
            Mock Write-CgrExistingDestinationRecoveryReport { throw 'Secondary recovery disk failure.' }

            {
                Invoke-CgrExistingDestinationReplacement -Plan $script:recoveryPlan -SourceRepository $script:recoverySource -ExistingDestinationRepository $script:recoveryOriginal
            } | Should -Throw -ExpectedMessage '*Original Snapshot copy failure*'
            Should -Invoke Write-CgrExistingDestinationRecoveryReport -Times 1 -Exactly -ParameterFilter {
                $FailureStage -eq 'CopySnapshot' -and
                $null -eq $SnapshotResult -and
                $ArchiveRepository.Id -eq 20 -and
                $DestinationRepository.Id -eq 30
            }
        }
    }
}
