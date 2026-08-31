@{
    SchemaVersion = 1

    # Stable SCN-* IDs are owned by docs/product/product-model.md. Every canonical
    # scenario must be explicitly classified here and point to repository evidence.
    Scenarios = @{
        'SCN-PLAN-HAPPY-01' = @{
            Classification = 'Required'
            AutomatedEvidence = @('tests/integration/ApprovedSourceState.Tests.ps1')
            LiveValidation = 'NotRequired'
            LiveEvidence = @()
        }
        'SCN-PLAN-SAFETY-01' = @{
            Classification = 'Required'
            AutomatedEvidence = @('tests/integration/StaleStateSafety.Tests.ps1', 'tests/integration/RiskFailurePaths.Tests.ps1')
            LiveValidation = 'NotRequired'
            LiveEvidence = @()
        }
        'SCN-PLAN-NOOP-01' = @{
            Classification = 'Required'
            AutomatedEvidence = @('tests/integration/SameNamePublic.Tests.ps1')
            LiveValidation = 'NotRequired'
            LiveEvidence = @()
        }
        'SCN-SNAP-HAPPY-01' = @{
            Classification = 'Required'
            AutomatedEvidence = @('tests/integration/NewDestinationSnapshot.Tests.ps1')
            LiveValidation = 'Required'
            LiveEvidence = @('tests/e2e/Invoke-SnapshotEndToEndTests.ps1')
        }
        'SCN-SNAP-VERIFY-01' = @{
            Classification = 'Required'
            AutomatedEvidence = @('tests/integration/NewDestinationSnapshot.Tests.ps1', 'tests/integration/RiskFailurePaths.Tests.ps1')
            LiveValidation = 'Required'
            LiveEvidence = @('tests/e2e/Invoke-SnapshotEndToEndTests.ps1')
        }
        'SCN-HIST-HAPPY-01' = @{
            Classification = 'Required'
            AutomatedEvidence = @('tests/integration/FullHistory.Tests.ps1')
            LiveValidation = 'Required'
            LiveEvidence = @('tests/e2e/Invoke-FullHistoryEndToEndTests.ps1')
        }
        'SCN-HIST-VERIFY-01' = @{
            Classification = 'Required'
            AutomatedEvidence = @('tests/integration/FullHistory.Tests.ps1', 'tests/integration/FullHistoryNegativeVerification.Tests.ps1')
            LiveValidation = 'Required'
            LiveEvidence = @('tests/e2e/Invoke-FullHistoryEndToEndTests.ps1')
        }
        'SCN-GHREL-HAPPY-01' = @{
            Classification = 'Required'
            AutomatedEvidence = @('tests/integration/GitHubReleaseMigration.Tests.ps1', 'tests/unit/FullHistoryReleaseOrchestration.Tests.ps1')
            LiveValidation = 'Required'
            LiveEvidence = @('tests/e2e/Invoke-GitHubReleaseEndToEndTests.ps1')
        }
        'SCN-GHREL-SAFETY-01' = @{
            Classification = 'Required'
            AutomatedEvidence = @('tests/unit/GitHubReleaseExecution.Tests.ps1', 'tests/integration/GitHubReleaseMigration.Tests.ps1')
            LiveValidation = 'NotRequired'
            LiveEvidence = @()
        }
        'SCN-GHREL-VERIFY-01' = @{
            Classification = 'Required'
            AutomatedEvidence = @('tests/integration/GitHubReleaseVerification.Tests.ps1', 'tests/unit/GitHubReleaseExecution.Tests.ps1')
            LiveValidation = 'Required'
            LiveEvidence = @('tests/e2e/Invoke-GitHubReleaseEndToEndTests.ps1')
        }
        'SCN-GHREL-PARTIAL-01' = @{
            Classification = 'Required'
            AutomatedEvidence = @('tests/unit/FullHistoryReleaseOrchestration.Tests.ps1')
            LiveValidation = 'NotRequired'
            LiveEvidence = @()
        }
        'SCN-DEST-VALIDATION-01' = @{
            Classification = 'Required'
            AutomatedEvidence = @('tests/integration/ExistingDestinationReplacement.Tests.ps1')
            LiveValidation = 'NotRequired'
            LiveEvidence = @()
        }
        'SCN-DEST-SAFETY-01' = @{
            Classification = 'Required'
            AutomatedEvidence = @('tests/integration/ExistingDestinationPublicSafety.Tests.ps1', 'tests/integration/ExistingDestinationReplacement.Tests.ps1')
            LiveValidation = 'NotRequired'
            LiveEvidence = @()
        }
        'SCN-DEST-HAPPY-01' = @{
            Classification = 'Required'
            AutomatedEvidence = @('tests/integration/ExistingDestinationReplacement.Tests.ps1', 'tests/integration/ReplacementExecutionEvidence.Tests.ps1')
            LiveValidation = 'Required'
            LiveEvidence = @('tests/e2e/Invoke-RecoveryEndToEndTests.ps1')
        }
        'SCN-DEST-PARTIAL-01' = @{
            Classification = 'Required'
            AutomatedEvidence = @('tests/integration/ExistingDestinationReplacement.Tests.ps1', 'tests/integration/Recovery.Tests.ps1')
            LiveValidation = 'Required'
            LiveEvidence = @('tests/e2e/Invoke-RecoveryEndToEndTests.ps1')
        }
        'SCN-SAME-HAPPY-01' = @{
            Classification = 'Required'
            AutomatedEvidence = @('tests/integration/SameNameExecution.Tests.ps1', 'tests/integration/SameNameFullHistory.Tests.ps1')
            LiveValidation = 'Required'
            LiveEvidence = @('tests/e2e/Invoke-SameNameEndToEndTests.ps1', 'tests/e2e/Invoke-SameNameFullHistoryEndToEndTests.ps1')
        }
        'SCN-SAME-SAFETY-01' = @{
            Classification = 'Required'
            AutomatedEvidence = @('tests/integration/SameNameSafety.Tests.ps1', 'tests/integration/SameNamePublic.Tests.ps1')
            LiveValidation = 'Required'
            LiveEvidence = @('tests/e2e/Invoke-SameNameEndToEndTests.ps1')
        }
        'SCN-LFS-HAPPY-01' = @{
            Classification = 'Required'
            AutomatedEvidence = @('tests/integration/GitLfs.Tests.ps1', 'tests/integration/FullHistory.Tests.ps1')
            LiveValidation = 'Required'
            LiveEvidence = @('tests/e2e/Invoke-GitLfsEndToEndTests.ps1')
        }
        'SCN-LFS-VALIDATION-01' = @{
            Classification = 'Required'
            AutomatedEvidence = @('tests/integration/GitLfs.Tests.ps1', 'tests/integration/FullHistoryNegativeVerification.Tests.ps1')
            LiveValidation = 'Required'
            LiveEvidence = @('tests/e2e/Invoke-GitLfsEndToEndTests.ps1')
        }
        'SCN-SET-HAPPY-01' = @{
            Classification = 'Required'
            AutomatedEvidence = @('tests/integration/RepositorySettings.Tests.ps1')
            LiveValidation = 'Required'
            LiveEvidence = @('tests/e2e/Invoke-RepositorySettingsEndToEndTests.ps1')
        }
        'SCN-SET-PARTIAL-01' = @{
            Classification = 'Required'
            AutomatedEvidence = @('tests/integration/RepositorySettings.Tests.ps1', 'tests/integration/Recovery.Tests.ps1')
            LiveValidation = 'Required'
            LiveEvidence = @('tests/e2e/Invoke-RecoveryEndToEndTests.ps1')
        }
        'SCN-PROT-HAPPY-01' = @{
            Classification = 'Required'
            AutomatedEvidence = @('tests/integration/Protection.Tests.ps1', 'tests/integration/ProtectionRestoreStatus.Tests.ps1')
            LiveValidation = 'Constrained'
            LiveEvidence = @('tests/e2e/Invoke-RepositorySettingsEndToEndTests.ps1')
            LiveReason = 'Live protection validation depends on repository and account plan capabilities.'
        }
        'SCN-PROT-EDGE-01' = @{
            Classification = 'Required'
            AutomatedEvidence = @('tests/integration/Protection.Tests.ps1', 'tests/integration/ProtectionRestoreStatus.Tests.ps1')
            LiveValidation = 'Constrained'
            LiveEvidence = @('tests/e2e/Invoke-RepositorySettingsEndToEndTests.ps1')
            LiveReason = 'Non-transferable policy behavior depends on GitHub plan and organization policy capabilities.'
        }
        'SCN-WIZ-HAPPY-01' = @{
            Classification = 'Required'
            AutomatedEvidence = @('tests/integration/WizardMigrationIntegration.Tests.ps1', 'tests/integration/WizardOrchestration.Tests.ps1')
            LiveValidation = 'NotRequired'
            LiveEvidence = @()
        }
        'SCN-WIZ-NOOP-01' = @{
            Classification = 'Required'
            AutomatedEvidence = @('tests/integration/WizardOrchestration.Tests.ps1')
            LiveValidation = 'NotRequired'
            LiveEvidence = @()
        }
        'SCN-WIZ-SAFETY-01' = @{
            Classification = 'Required'
            AutomatedEvidence = @('tests/integration/WizardMigrationIntegration.Tests.ps1', 'tests/integration/StaleStateSafety.Tests.ps1')
            LiveValidation = 'NotRequired'
            LiveEvidence = @()
        }
        'SCN-AUTO-AUTOMATION-01' = @{
            Classification = 'Required'
            AutomatedEvidence = @('tests/integration/ExistingDestinationPublicSafety.Tests.ps1', 'tests/integration/SameNamePublic.Tests.ps1')
            LiveValidation = 'NotRequired'
            LiveEvidence = @()
        }
        'SCN-DISC-AUTH-01' = @{
            Classification = 'Required'
            AutomatedEvidence = @('tests/unit/GitAuthentication.Tests.ps1')
            LiveValidation = 'NotRequired'
            LiveEvidence = @()
        }
        'SCN-HOST-VALIDATION-01' = @{
            Classification = 'Required'
            AutomatedEvidence = @('tests/unit/HostName.Tests.ps1')
            LiveValidation = 'NotRequired'
            LiveEvidence = @()
        }
        'SCN-VERIFY-HAPPY-01' = @{
            Classification = 'Required'
            AutomatedEvidence = @('tests/integration/FullHistory.Tests.ps1', 'tests/integration/NewDestinationSnapshot.Tests.ps1', 'tests/integration/GitHubReleaseVerification.Tests.ps1')
            LiveValidation = 'Required'
            LiveEvidence = @('tests/e2e/Invoke-SnapshotEndToEndTests.ps1', 'tests/e2e/Invoke-FullHistoryEndToEndTests.ps1', 'tests/e2e/Invoke-GitHubReleaseEndToEndTests.ps1')
        }
        'SCN-EVID-HAPPY-01' = @{
            Classification = 'Required'
            AutomatedEvidence = @('tests/integration/NewDestinationSnapshot.Tests.ps1', 'tests/integration/ReplacementExecutionEvidence.Tests.ps1')
            LiveValidation = 'Required'
            LiveEvidence = @('tests/e2e/Invoke-SnapshotEndToEndTests.ps1')
        }
        'SCN-RECOVER-RECOVERY-01' = @{
            Classification = 'Required'
            AutomatedEvidence = @('tests/integration/Recovery.Tests.ps1', 'tests/integration/ReplacementExecutionEvidence.Tests.ps1', 'tests/unit/FullHistoryReleaseOrchestration.Tests.ps1')
            LiveValidation = 'Required'
            LiveEvidence = @('tests/e2e/Invoke-RecoveryEndToEndTests.ps1')
        }
        'SCN-API-RESILIENCE-01' = @{
            Classification = 'Required'
            AutomatedEvidence = @('tests/unit/GitHubApiAdapters.Tests.ps1')
            LiveValidation = 'NotRequired'
            LiveEvidence = @()
        }
        'SCN-NATIVE-RESILIENCE-01' = @{
            Classification = 'Required'
            AutomatedEvidence = @('tests/unit/NativeCommandStreams.Tests.ps1')
            LiveValidation = 'NotRequired'
            LiveEvidence = @()
        }
        'SCN-RESOURCE-RESILIENCE-01' = @{
            Classification = 'Required'
            AutomatedEvidence = @('tests/integration/LocalResourcePreflight.Tests.ps1')
            LiveValidation = 'NotRequired'
            LiveEvidence = @()
        }
        'SCN-RETRY-RESILIENCE-01' = @{
            Classification = 'Required'
            AutomatedEvidence = @('tests/integration/RetryIdempotency.Tests.ps1', 'tests/integration/StaleStateSafety.Tests.ps1')
            LiveValidation = 'NotRequired'
            LiveEvidence = @()
        }
        'SCN-RETRY-RESILIENCE-02' = @{
            Classification = 'Required'
            AutomatedEvidence = @('tests/integration/RetryIdempotency.Tests.ps1', 'tests/integration/Recovery.Tests.ps1')
            LiveValidation = 'Required'
            LiveEvidence = @('tests/e2e/Invoke-RecoveryEndToEndTests.ps1')
        }
        'SCN-SCALE-RESILIENCE-01' = @{
            Classification = 'Required'
            AutomatedEvidence = @('tests/integration/ScaleCharacterizationHarness.Tests.ps1')
            LiveValidation = 'NotRequired'
            LiveEvidence = @()
        }
        'SCN-INTERRUPT-RESILIENCE-01' = @{
            Classification = 'Required'
            AutomatedEvidence = @('tests/integration/InterruptionContract.Tests.ps1', 'tests/unit/NativeCommandStreams.Tests.ps1')
            LiveValidation = 'Constrained'
            LiveEvidence = @()
            LiveReason = 'Raw Ctrl+C and hard process termination are host and operating-system dependent and are not portable blocking E2E assertions.'
        }
        'SCN-DIST-VALIDATION-01' = @{
            Classification = 'Required'
            AutomatedEvidence = @('tests/contract/GalleryPackageContract.Tests.ps1', 'tests/contract/PowerShellGalleryRelease.Tests.ps1')
            LiveValidation = 'NotRequired'
            LiveEvidence = @()
        }
        'SCN-REL-SAFETY-01' = @{
            Classification = 'Required'
            AutomatedEvidence = @('tests/contract/PowerShellGalleryRelease.Tests.ps1', 'tests/contract/ReleasePackaging.Tests.ps1')
            LiveValidation = 'NotRequired'
            LiveEvidence = @()
        }
    }
}