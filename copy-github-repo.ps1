#requires -Version 7.4

<#
.SYNOPSIS
Loads CopyGitHubRepo and starts the repository-copy wizard.

.DESCRIPTION
This thin launcher resolves the module relative to its own location, imports
it, and starts Start-CopyGitHubRepositoryWizard.
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$modulePath = Join-Path $PSScriptRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
Import-Module $modulePath -Force -ErrorAction Stop

Start-CopyGitHubRepositoryWizard
