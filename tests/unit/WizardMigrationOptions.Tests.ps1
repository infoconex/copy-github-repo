BeforeAll {
    $root = Split-Path -Parent $PSScriptRoot
    $modulePath = Join-Path $root 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
    Import-Module $modulePath -Force
}

Describe 'Wizard repository copy options' {
    It 'passes FullHistory and a changed visibility through planning and approved execution' {
        InModuleScope CopyGitHubRepo {
            $source = [pscustomobject] @{ FullName = 'infoconex/source'; Owner = 'infoconex'; Visibility = 'public' }
            $plan = [pscustomobject] @{
                Mode = 'NewDestination'; SourceRepository = 'infoconex/source'; DestinationRepository = 'infoconex/destination'; ArchiveRepository = $null
                ContentMode = 'FullHistory'; DestinationVisibility = 'private'
                SourceState = [pscustomobject] @{ ContentMode = 'FullHistory'; Refs = @('refs/heads/main abc'); ReachableCommitCount = 1; DefaultBranch = 'main' }
                Steps = @([pscustomobject] @{ Description = 'Create destination.' })
            }
            Mock Write-CgrWizardMessage
            Mock Get-GitHubRepository { @($source) }
            Mock Select-CgrWizardRepository { ConvertTo-CgrWizardNavigationResult -Action Next -Value $source }
            Mock Test-CgrGitHubRepositoryExistence { $false }
            Mock Read-CgrWizardRepositoryName { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'infoconex/destination' }
            Mock Read-CgrWizardChoice { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'FullHistory' } -ParameterFilter { $Title -eq 'Content mode' }
            Mock Read-CgrWizardChoice { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'private' } -ParameterFilter { $Title -eq 'Destination visibility' }
            Mock Read-CgrWizardChoice { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'Restore' } -ParameterFilter { $Title -eq 'Supported repository settings' }
            Mock Read-CgrWizardTextValue
            Mock Read-CgrWizardChoice { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'Execute' } -ParameterFilter { $Title -eq 'Repository copy plan' }
            Mock Copy-GitHubRepository { $plan } -ParameterFilter { $PlanOnly }
            Mock Invoke-CgrApprovedMigrationPlan { [pscustomobject] @{ Status = 'Completed'; Plan = $Plan; CompletedSteps = @() } }

            Invoke-CgrRepositoryCopyWizard -HostName github.com -ExecutionGuard { $true } | Out-Null

            Should -Invoke Read-CgrWizardTextValue -Times 0 -Exactly
            Should -Invoke Read-CgrWizardChoice -Times 0 -Exactly -ParameterFilter { $Title -eq 'Snapshot release preservation' }
            Should -Invoke Copy-GitHubRepository -Times 1 -Exactly -ParameterFilter {
                $PlanOnly -and $ContentMode -eq 'FullHistory' -and $DestinationVisibility -eq 'private'
            }
            Should -Invoke Invoke-CgrApprovedMigrationPlan -Times 1 -Exactly -ParameterFilter {
                $Plan.ContentMode -eq 'FullHistory' -and $Plan.DestinationVisibility -eq 'private'
            }
        }
    }

    It 'passes archive and exact confirmation for same-name replacement' {
        InModuleScope CopyGitHubRepo {
            $source = [pscustomobject] @{ FullName = 'infoconex/source'; Owner = 'infoconex'; Visibility = 'public' }
            $expected = 'SOURCE=infoconex/source;ARCHIVE=infoconex/source-archive;REPLACEMENT=infoconex/source'
            $plan = [pscustomobject] @{
                Mode = 'SameNameReplacement'; SourceRepository = 'infoconex/source'; DestinationRepository = 'infoconex/source'; ArchiveRepository = 'infoconex/source-archive'
                ContentMode = 'Snapshot'; IncludeReleases = $false; CommitMessage = 'Initial repository commit'; DestinationVisibility = 'public'
                SourceState = [pscustomobject] @{ ContentMode = 'Snapshot'; CommitSha = 'source-commit'; TreeSha = 'source-tree'; DefaultBranch = 'main' }
                Steps = @([pscustomobject] @{ Description = 'Preserve source as archive.' })
            }
            Mock Write-CgrWizardMessage
            Mock Get-GitHubRepository { @($source) }
            Mock Select-CgrWizardRepository { ConvertTo-CgrWizardNavigationResult -Action Next -Value $source }
            Mock Read-CgrWizardRepositoryName { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'infoconex/source' } -ParameterFilter { $Kind -eq 'Destination' }
            Mock Read-CgrWizardRepositoryName { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'source-archive' } -ParameterFilter { $Kind -eq 'Archive' }
            Mock Read-CgrWizardChoice { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'Snapshot' } -ParameterFilter { $Title -eq 'Content mode' }
            Mock Read-CgrWizardChoice { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'public' } -ParameterFilter { $Title -eq 'Destination visibility' }
            Mock Read-CgrWizardChoice { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'Restore' } -ParameterFilter { $Title -eq 'Supported repository settings' }
            Mock Read-CgrWizardChoice { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'Skip' } -ParameterFilter { $Title -eq 'Snapshot release preservation' }
            Mock Read-CgrWizardTextValue { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'Initial repository commit' } -ParameterFilter { $Title -eq 'Snapshot commit message' }
            Mock Read-CgrWizardChoice { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'Execute' } -ParameterFilter { $Title -eq 'Repository copy plan' }
            Mock Read-CgrWizardInput { $expected }
            Mock Copy-GitHubRepository { $plan } -ParameterFilter { $PlanOnly }
            Mock Invoke-CgrApprovedMigrationPlan { [pscustomobject] @{ Status = 'Completed'; Plan = $Plan; CompletedSteps = @() } }

            Invoke-CgrRepositoryCopyWizard -HostName github.com -ExecutionGuard { $true } | Out-Null

            Should -Invoke Copy-GitHubRepository -Times 1 -Exactly -ParameterFilter {
                $PlanOnly -and $ArchiveRepositoryName -eq 'source-archive' -and $CommitMessage -eq 'Initial repository commit' -and -not $IncludeReleases
            }
            Should -Invoke Invoke-CgrApprovedMigrationPlan -Times 1 -Exactly -ParameterFilter {
                $Plan.ArchiveRepository -eq 'infoconex/source-archive' -and $SameNameConfirmation -ceq $expected
            }
        }
    }

    It 'passes a modified Snapshot commit message through planning and approved execution' {
        InModuleScope CopyGitHubRepo {
            $source = [pscustomobject] @{ FullName = 'infoconex/source'; Owner = 'infoconex'; Visibility = 'public' }
            $plan = [pscustomobject] @{
                Mode = 'NewDestination'; SourceRepository = 'infoconex/source'; DestinationRepository = 'infoconex/destination'; ArchiveRepository = $null
                ContentMode = 'Snapshot'; IncludeReleases = $false; CommitMessage = 'Imported repository baseline'; DestinationVisibility = 'public'
                SourceState = [pscustomobject] @{ ContentMode = 'Snapshot'; CommitSha = 'source-commit'; TreeSha = 'source-tree'; DefaultBranch = 'main' }
                Steps = @([pscustomobject] @{ Description = 'Create destination.' })
            }
            Mock Write-CgrWizardMessage
            Mock Get-GitHubRepository { @($source) }
            Mock Select-CgrWizardRepository { ConvertTo-CgrWizardNavigationResult -Action Next -Value $source }
            Mock Test-CgrGitHubRepositoryExistence { $false }
            Mock Read-CgrWizardRepositoryName { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'infoconex/destination' }
            Mock Read-CgrWizardChoice { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'Snapshot' } -ParameterFilter { $Title -eq 'Content mode' }
            Mock Read-CgrWizardChoice { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'public' } -ParameterFilter { $Title -eq 'Destination visibility' }
            Mock Read-CgrWizardChoice { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'Restore' } -ParameterFilter { $Title -eq 'Supported repository settings' }
            Mock Read-CgrWizardChoice { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'Skip' } -ParameterFilter { $Title -eq 'Snapshot release preservation' }
            Mock Read-CgrWizardTextValue { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'Imported repository baseline' } -ParameterFilter { $Title -eq 'Snapshot commit message' }
            Mock Read-CgrWizardChoice { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'Execute' } -ParameterFilter { $Title -eq 'Repository copy plan' }
            Mock Copy-GitHubRepository { $plan } -ParameterFilter { $PlanOnly }
            Mock Invoke-CgrApprovedMigrationPlan { [pscustomobject] @{ Status = 'Completed'; Plan = $Plan; CompletedSteps = @() } }

            Invoke-CgrRepositoryCopyWizard -HostName github.com -ExecutionGuard { $true } | Out-Null

            Should -Invoke Copy-GitHubRepository -Times 1 -Exactly -ParameterFilter { $PlanOnly -and $CommitMessage -eq 'Imported repository baseline' -and -not $IncludeReleases }
            Should -Invoke Invoke-CgrApprovedMigrationPlan -Times 1 -Exactly -ParameterFilter { $Plan.CommitMessage -eq 'Imported repository baseline' }
        }
    }

    It 'archives and replaces an existing different destination only after exact confirmation' {
        InModuleScope CopyGitHubRepo {
            $source = [pscustomobject] @{ FullName = 'infoconex/source'; Owner = 'infoconex'; Visibility = 'public' }
            $archiveName = 'destination-archive-20260813-213700'
            $expected = "DESTINATION=infoconex/destination;ARCHIVE=infoconex/$archiveName;REPLACEMENT=infoconex/destination"
            $plan = [pscustomobject] @{
                Mode = 'ExistingDestinationReplacement'; SourceRepository = 'infoconex/source'; DestinationRepository = 'infoconex/destination'; ArchiveRepository = "infoconex/$archiveName"
                ContentMode = 'Snapshot'; IncludeReleases = $false; CommitMessage = 'Initial repository commit'; DestinationVisibility = 'public'
                SourceState = [pscustomobject] @{ ContentMode = 'Snapshot'; CommitSha = 'source-commit'; TreeSha = 'source-tree'; DefaultBranch = 'main' }
                Steps = @([pscustomobject] @{ Description = 'Rename existing destination to archive.' }, [pscustomobject] @{ Description = 'Create fresh replacement.' })
            }
            Mock Write-CgrWizardMessage
            Mock Get-GitHubRepository { @($source) }
            Mock Select-CgrWizardRepository { ConvertTo-CgrWizardNavigationResult -Action Next -Value $source }
            Mock Get-CgrDefaultArchiveRepositoryName { $archiveName }
            Mock Test-CgrGitHubRepositoryExistence { param($Repository) $Repository -eq 'infoconex/destination' }
            Mock Read-CgrWizardRepositoryName { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'infoconex/destination' } -ParameterFilter { $Kind -eq 'Destination' }
            Mock Read-CgrWizardRepositoryName { ConvertTo-CgrWizardNavigationResult -Action Next -Value $archiveName } -ParameterFilter { $Kind -eq 'Archive' }
            Mock Read-CgrWizardChoice { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'Archive and replace existing destination' } -ParameterFilter { $Title -eq 'Existing destination' }
            Mock Read-CgrWizardChoice { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'Snapshot' } -ParameterFilter { $Title -eq 'Content mode' }
            Mock Read-CgrWizardChoice { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'public' } -ParameterFilter { $Title -eq 'Destination visibility' }
            Mock Read-CgrWizardChoice { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'Restore' } -ParameterFilter { $Title -eq 'Supported repository settings' }
            Mock Read-CgrWizardChoice { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'Skip' } -ParameterFilter { $Title -eq 'Snapshot release preservation' }
            Mock Read-CgrWizardTextValue { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'Initial repository commit' }
            Mock Read-CgrWizardChoice { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'Execute' } -ParameterFilter { $Title -eq 'Repository copy plan' }
            Mock Read-CgrWizardInput { $expected }
            Mock Copy-GitHubRepository { $plan } -ParameterFilter { $PlanOnly }
            Mock Invoke-CgrApprovedMigrationPlan { [pscustomobject] @{ Status = 'Completed'; Plan = $Plan; CompletedSteps = @() } }

            Invoke-CgrRepositoryCopyWizard -HostName github.com -ExecutionGuard { $true } | Out-Null

            Should -Invoke Copy-GitHubRepository -Times 1 -Exactly -ParameterFilter { $PlanOnly -and $ExistingDestinationArchiveName -eq $archiveName -and -not $IncludeReleases }
            Should -Invoke Invoke-CgrApprovedMigrationPlan -Times 1 -Exactly -ParameterFilter {
                $Plan.ArchiveRepository -eq "infoconex/$archiveName" -and $ExistingDestinationConfirmation -ceq $expected
            }
        }
    }
}
