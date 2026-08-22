@{
    RootModule = 'CopyGitHubRepo.psm1'
    ModuleVersion = '0.1.0'
    GUID = 'c428210d-c7a4-49db-81d1-830606e16fa6'
    Author = 'infoconex'
    CompanyName = 'infoconex'
    Copyright = '(c) 2026 infoconex. Licensed under the MIT License.'
    Description = 'Safely copy, publish, and verify GitHub repositories using clean Snapshot or history-preserving FullHistory modes.'
    PowerShellVersion = '7.4'
    CompatiblePSEditions = @('Core')
    FormatsToProcess = @('CopyGitHubRepo.format.ps1xml')
    FunctionsToExport = @(
        'Copy-GitHubRepository'
        'Get-GitHubRepository'
        'Start-CopyGitHubRepositoryWizard'
        'Test-GitHubRepositoryMigration'
    )
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
    PrivateData = @{
        PSData = @{
            Tags = @('GitHub', 'Git', 'Repository', 'Copy', 'Migration', 'PowerShell')
            LicenseUri = 'https://github.com/infoconex/copy-github-repo/blob/main/LICENSE'
            ProjectUri = 'https://github.com/infoconex/copy-github-repo'
            ReleaseNotes = 'https://github.com/infoconex/copy-github-repo/releases'
        }
    }
}
