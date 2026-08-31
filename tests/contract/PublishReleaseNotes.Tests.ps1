#requires -Version 7.4

Describe 'Publish Release notes contract' -Tag 'Contract' {
    BeforeAll {
        $repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $workflowPath = Join-Path $repositoryRoot '.github/workflows/publish-release.yml'
        $workflow = Get-Content -LiteralPath $workflowPath -Raw
    }

    It 'publishes GitHub Release notes from the finalized changelog release section' {
        $workflow | Should -Match [regex]::Escape('./build/Set-PowerShellGalleryReleaseNotes.ps1')
        $workflow | Should -Match [regex]::Escape('--notes-file')
        $workflow | Should -Not -Match [regex]::Escape('--generate-notes')
    }
}
