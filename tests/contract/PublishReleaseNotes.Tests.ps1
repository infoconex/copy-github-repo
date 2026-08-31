#requires -Version 7.4

Describe 'Publish Release notes contract' -Tag 'Contract' {
    BeforeAll {
        $repositoryRoot = Split-Path -Parent $PSScriptRoot
        $workflowPath = Join-Path $repositoryRoot '.github/workflows/publish-release.yml'
        $script:workflow = Get-Content -LiteralPath $workflowPath -Raw
    }

    It 'publishes GitHub Release notes from the finalized changelog release section' {
        $script:workflow | Should -Match [regex]::Escape('./build/New-PowerShellGalleryPackage.ps1')
        $script:workflow | Should -Match [regex]::Escape('PrivateData.PSData.ReleaseNotes')
        $script:workflow | Should -Match [regex]::Escape('--notes-file')
        $script:workflow | Should -Not -Match [regex]::Escape('--generate-notes')
    }
}
