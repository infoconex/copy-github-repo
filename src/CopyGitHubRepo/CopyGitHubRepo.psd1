@{
    RootModule = 'CopyGitHubRepo.psm1'
    ModuleVersion = '0.4.0'
    GUID = 'c428210d-c7a4-49db-81d1-830606e16fa6'
    Author = 'infoconex'
    CompanyName = 'infoconex'
    Copyright = '(c) 2026 infoconex. Licensed under the MIT License.'
    Description = 'PowerShell module for safely copying and migrating GitHub repositories with clean Snapshot or history-preserving FullHistory modes.'
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
            Tags = @(
                'GitHub'
                'Git'
                'Repository'
                'Copy'
                'Migration'
                'Automation'
                'DevOps'
                'PowerShell'
                'PSEdition_Core'
                'Windows'
                'Linux'
                'MacOS'
            )
            LicenseUri = 'https://github.com/infoconex/copy-github-repo/blob/main/LICENSE'
            ProjectUri = 'https://infoconex.github.io/copy-github-repo/'
            IconUri = 'https://infoconex.github.io/copy-github-repo/assets/images/gallery-icon.png'
            ReleaseNotes = 'https://github.com/infoconex/copy-github-repo/releases'
        }
    }
}
