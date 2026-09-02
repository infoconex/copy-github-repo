@{
    InlinePrivateHelpRequired = @(
        'Copy-CgrRepositoryFullHistory'
        'Copy-CgrRepositorySnapshot'
        'Invoke-CgrExistingDestinationReplacement'
        'Invoke-CgrNewDestinationFullHistory'
        'Invoke-CgrNewDestinationSnapshot'
        'Invoke-CgrSameNameFullHistoryReplacement'
        'Invoke-CgrSameNameSnapshotReplacement'
        'New-CgrMigrationPlan'
        'New-CgrSnapshotReleaseCheckpointPlan'
    )

    ModuleFiles = @(
        'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
        'src/CopyGitHubRepo/CopyGitHubRepo.psm1'
    )

    OperationalScripts = @(
        'build/Install-DevelopmentDependencies.ps1'
        'build/Invoke-LiveScaleCharacterization.ps1'
        'build/Measure-ScaleCharacterization.ps1'
        'build/New-PowerShellGalleryPackage.ps1'
        'build/New-ReleaseArtifact.ps1'
        'build/New-ReleaseSbom.ps1'
        'build/New-ScaleCharacterizationFixture.ps1'
        'build/Set-PowerShellGalleryReleaseNotes.ps1'
        'build/Test-Documentation.ps1'
        'build/Test-GeneratedSite.ps1'
        'build/Test-Project.ps1'
        'build/Test-ReleaseReadiness.ps1'
        'copy-github-repo.ps1'
        'install.ps1'
        'install-prerelease.ps1'
        'install-release.ps1'
        'uninstall.ps1'
        'tests/e2e/Invoke-CleanSnapshotDemonstration.ps1'
        'tests/e2e/Invoke-FullHistoryEndToEndTests.ps1'
        'tests/e2e/Invoke-GitHubPagesEndToEndTests.ps1'
        'tests/e2e/Invoke-GitHubReleaseEndToEndTests.ps1'
        'tests/e2e/Invoke-GitLfsEndToEndTests.ps1'
        'tests/e2e/Invoke-RecoveryEndToEndTests.ps1'
        'tests/e2e/Invoke-RepositorySettingsEndToEndTests.ps1'
        'tests/e2e/Invoke-SameNameEndToEndTests.ps1'
        'tests/e2e/Invoke-SameNameFullHistoryEndToEndTests.ps1'
        'tests/e2e/Invoke-SnapshotEndToEndTests.ps1'
        'tests/e2e/Invoke-SnapshotReleaseEndToEndTests.ps1'
    )
}
