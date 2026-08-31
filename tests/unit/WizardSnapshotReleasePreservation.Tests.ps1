BeforeAll {
    $root = Split-Path -Parent $PSScriptRoot
    $modulePath = Join-Path $root 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
    Import-Module $modulePath -Force
}

Describe 'Wizard Snapshot release preservation' {
    It 'passes Snapshot release filters to public planning, reviews real checkpoints, and executes the exact reviewed plan' {
        InModuleScope CopyGitHubRepo {
            $source = [pscustomobject] @{ FullName = 'acme/source'; Owner = 'acme'; Visibility = 'public' }
            $plan = [pscustomobject] @{
                Mode = 'NewDestination'; SourceRepository = 'acme/source'; DestinationRepository = 'acme/destination'; ArchiveRepository = $null
                ContentMode = 'Snapshot'; IncludeReleases = $true; CommitMessage = 'Initial repository commit'; DestinationVisibility = 'public'
                SourceState = [pscustomobject] @{ ContentMode = 'Snapshot'; CommitSha = 'head'; TreeSha = 'tree-head'; DefaultBranch = 'main' }
                ReleaseSelection = [pscustomobject] @{
                    AvailableReleaseCount = 4; SelectedReleaseCount = 2; SelectedAssetCount = 3
                    IncludePatterns = @('v2.*', 'v3.*'); ExcludePatterns = @('*-beta')
                    IncludePrerelease = $true; IncludeDraftReleases = $false; ReleaseCount = 2
                }
                ReleaseCheckpointPlan = [pscustomobject] @{
                    CheckpointCount = 2; PlannedSnapshotCommitCount = 3; FinalHeadCheckpointRequired = $true
                    Checkpoints = @(
                        [pscustomobject] @{ Order = 1; SourceCommitSha = 'c1'; SourceTreeSha = 'tree-c1'; TagNames = @('v2.0.0') },
                        [pscustomobject] @{ Order = 2; SourceCommitSha = 'c2'; SourceTreeSha = 'tree-c2'; TagNames = @('v3.0.0') }
                    )
                }
                Steps = @([pscustomobject] @{ Description = 'Create destination.' })
            }
            $script:messages = [System.Collections.Generic.List[string]]::new()
            $script:releaseInputs = [System.Collections.Generic.Queue[string]]::new()
            $script:releaseInputs.Enqueue('v2.*, v3.*')
            $script:releaseInputs.Enqueue('*-beta')
            $script:releaseInputs.Enqueue('2')

            Mock Write-CgrWizardMessage { if ($null -ne $Message) { $script:messages.Add([string] $Message) } }
            Mock Get-GitHubRepository { @($source) }
            Mock Select-CgrWizardRepository { ConvertTo-CgrWizardNavigationResult -Action Next -Value $source }
            Mock Test-CgrGitHubRepositoryExistence { $false }
            Mock Read-CgrWizardRepositoryName { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'acme/destination' }
            Mock Read-CgrWizardTextValue { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'Initial repository commit' }
            Mock Read-CgrWizardChoice { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'Snapshot' } -ParameterFilter { $Title -eq 'Content mode' }
            Mock Read-CgrWizardChoice { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'public' } -ParameterFilter { $Title -eq 'Destination visibility' }
            Mock Read-CgrWizardChoice { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'Restore' } -ParameterFilter { $Title -eq 'Supported repository settings' }
            Mock Read-CgrWizardChoice { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'Preserve selected releases' } -ParameterFilter { $Title -eq 'Snapshot release preservation' }
            Mock Read-CgrWizardChoice { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'Include prereleases' } -ParameterFilter { $Title -eq 'Prerelease filtering' }
            Mock Read-CgrWizardChoice { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'Exclude draft releases' } -ParameterFilter { $Title -eq 'Draft release filtering' }
            Mock Read-CgrWizardChoice { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'Execute' } -ParameterFilter { $Title -eq 'Repository copy plan' }
            Mock Read-CgrWizardInput { $script:releaseInputs.Dequeue() } -ParameterFilter { $Prompt -in @('Release tag include patterns', 'Release tag exclude patterns', 'Release count limit') }
            Mock Copy-GitHubRepository { $plan } -ParameterFilter { $PlanOnly }
            Mock Invoke-CgrApprovedMigrationPlan { [pscustomobject] @{ Status = 'Completed'; Plan = $Plan; CompletedSteps = @() } }

            Invoke-CgrRepositoryCopyWizard -HostName github.com -ExecutionGuard { $true } | Out-Null

            Should -Invoke Copy-GitHubRepository -Times 1 -Exactly -ParameterFilter {
                $PlanOnly -and $ContentMode -eq 'Snapshot' -and $IncludeReleases -and
                @($ReleaseTag).Count -eq 2 -and $ReleaseTag[0] -eq 'v2.*' -and $ReleaseTag[1] -eq 'v3.*' -and
                @($ReleaseExcludeTag).Count -eq 1 -and $ReleaseExcludeTag[0] -eq '*-beta' -and
                $IncludePrerelease -and -not $IncludeDraftReleases -and $ReleaseCount -eq 2
            }
            Should -Invoke Invoke-CgrApprovedMigrationPlan -Times 1 -Exactly -ParameterFilter { [object]::ReferenceEquals($Plan, $plan) }
            $rendered = $script:messages -join "`n"
            $rendered | Should -Match 'does not preserve original commit identities or ancestry'
            $rendered | Should -Match 'newly constructed Snapshot checkpoint commits'
            $rendered | Should -Match 'Selected releases: 2 of 4'
            $rendered | Should -Match 'source commit c1; tree tree-c1; recreated tags: v2.0.0'
            $rendered | Should -Match 'source commit c2; tree tree-c2; recreated tags: v3.0.0'
        }
    }

    It 'preserves an accepted include filter when navigating Back and Next through release options' {
        InModuleScope CopyGitHubRepo {
            $source = [pscustomobject] @{ FullName = 'acme/source'; Owner = 'acme'; Visibility = 'public' }
            $plan = [pscustomobject] @{
                Mode = 'NewDestination'; SourceRepository = 'acme/source'; DestinationRepository = 'acme/destination'; ArchiveRepository = $null
                ContentMode = 'Snapshot'; IncludeReleases = $true; CommitMessage = 'Initial repository commit'; DestinationVisibility = 'public'
                SourceState = [pscustomobject] @{ ContentMode = 'Snapshot'; CommitSha = 'head'; TreeSha = 'tree-head'; DefaultBranch = 'main' }
                ReleaseSelection = [pscustomobject] @{ AvailableReleaseCount = 1; SelectedReleaseCount = 1; SelectedAssetCount = 0; IncludePatterns = @('v2.*'); ExcludePatterns = @(); IncludePrerelease = $false; IncludeDraftReleases = $false; ReleaseCount = $null }
                ReleaseCheckpointPlan = [pscustomobject] @{ CheckpointCount = 1; PlannedSnapshotCommitCount = 2; FinalHeadCheckpointRequired = $true; Checkpoints = @([pscustomobject] @{ Order = 1; SourceCommitSha = 'c1'; SourceTreeSha = 'tree-c1'; TagNames = @('v2.0.0') }) }
                Steps = @()
            }
            $script:includeCalls = 0
            $script:excludeCalls = 0

            Mock Write-CgrWizardMessage
            Mock Get-GitHubRepository { @($source) }
            Mock Select-CgrWizardRepository { ConvertTo-CgrWizardNavigationResult -Action Next -Value $source }
            Mock Test-CgrGitHubRepositoryExistence { $false }
            Mock Read-CgrWizardRepositoryName { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'acme/destination' }
            Mock Read-CgrWizardTextValue { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'Initial repository commit' }
            Mock Read-CgrWizardChoice { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'Snapshot' } -ParameterFilter { $Title -eq 'Content mode' }
            Mock Read-CgrWizardChoice { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'public' } -ParameterFilter { $Title -eq 'Destination visibility' }
            Mock Read-CgrWizardChoice { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'Restore' } -ParameterFilter { $Title -eq 'Supported repository settings' }
            Mock Read-CgrWizardChoice { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'Preserve selected releases' } -ParameterFilter { $Title -eq 'Snapshot release preservation' }
            Mock Read-CgrWizardChoice { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'Exclude prereleases' } -ParameterFilter { $Title -eq 'Prerelease filtering' }
            Mock Read-CgrWizardChoice { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'Exclude draft releases' } -ParameterFilter { $Title -eq 'Draft release filtering' }
            Mock Read-CgrWizardChoice { ConvertTo-CgrWizardNavigationResult -Action Cancel } -ParameterFilter { $Title -eq 'Repository copy plan' }
            Mock Read-CgrWizardInput {
                $script:includeCalls++
                if ($script:includeCalls -eq 1) { return 'v2.*' }
                return ''
            } -ParameterFilter { $Prompt -eq 'Release tag include patterns' }
            Mock Read-CgrWizardInput {
                $script:excludeCalls++
                if ($script:excludeCalls -eq 1) { return 'b' }
                return ''
            } -ParameterFilter { $Prompt -eq 'Release tag exclude patterns' }
            Mock Read-CgrWizardInput { '' } -ParameterFilter { $Prompt -eq 'Release count limit' }
            Mock Copy-GitHubRepository { $plan } -ParameterFilter { $PlanOnly }
            Mock Invoke-CgrApprovedMigrationPlan

            Invoke-CgrRepositoryCopyWizard -HostName github.com -ExecutionGuard { $true } | Out-Null

            Should -Invoke Read-CgrWizardInput -Times 2 -Exactly -ParameterFilter { $Prompt -eq 'Release tag include patterns' }
            Should -Invoke Copy-GitHubRepository -Times 1 -Exactly -ParameterFilter { $PlanOnly -and $IncludeReleases -and $ReleaseTag[0] -eq 'v2.*' }
            Should -Invoke Invoke-CgrApprovedMigrationPlan -Times 0 -Exactly
        }
    }

    It 'cancels from each new Snapshot release interaction without planning or mutation' -TestCases @(
        @{ Stage = 'Preservation' },
        @{ Stage = 'IncludeTag' },
        @{ Stage = 'ExcludeTag' },
        @{ Stage = 'Prerelease' },
        @{ Stage = 'Draft' },
        @{ Stage = 'Count' }
    ) {
        param($Stage)
        InModuleScope CopyGitHubRepo -Parameters @{ Stage = $Stage } {
            $source = [pscustomobject] @{ FullName = 'acme/source'; Owner = 'acme'; Visibility = 'public' }
            Mock Write-CgrWizardMessage
            Mock Get-GitHubRepository { @($source) }
            Mock Select-CgrWizardRepository { ConvertTo-CgrWizardNavigationResult -Action Next -Value $source }
            Mock Test-CgrGitHubRepositoryExistence { $false }
            Mock Read-CgrWizardRepositoryName { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'acme/destination' }
            Mock Read-CgrWizardTextValue { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'Initial repository commit' }
            Mock Read-CgrWizardChoice { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'Snapshot' } -ParameterFilter { $Title -eq 'Content mode' }
            Mock Read-CgrWizardChoice { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'public' } -ParameterFilter { $Title -eq 'Destination visibility' }
            Mock Read-CgrWizardChoice { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'Restore' } -ParameterFilter { $Title -eq 'Supported repository settings' }
            Mock Read-CgrWizardChoice {
                if ($Stage -eq 'Preservation') { return ConvertTo-CgrWizardNavigationResult -Action Cancel }
                return ConvertTo-CgrWizardNavigationResult -Action Next -Value 'Preserve selected releases'
            } -ParameterFilter { $Title -eq 'Snapshot release preservation' }
            Mock Read-CgrWizardChoice {
                if ($Stage -eq 'Prerelease') { return ConvertTo-CgrWizardNavigationResult -Action Cancel }
                return ConvertTo-CgrWizardNavigationResult -Action Next -Value 'Exclude prereleases'
            } -ParameterFilter { $Title -eq 'Prerelease filtering' }
            Mock Read-CgrWizardChoice {
                if ($Stage -eq 'Draft') { return ConvertTo-CgrWizardNavigationResult -Action Cancel }
                return ConvertTo-CgrWizardNavigationResult -Action Next -Value 'Exclude draft releases'
            } -ParameterFilter { $Title -eq 'Draft release filtering' }
            Mock Read-CgrWizardInput {
                if ($Stage -eq 'IncludeTag') { return 'c' }
                return ''
            } -ParameterFilter { $Prompt -eq 'Release tag include patterns' }
            Mock Read-CgrWizardInput {
                if ($Stage -eq 'ExcludeTag') { return 'c' }
                return ''
            } -ParameterFilter { $Prompt -eq 'Release tag exclude patterns' }
            Mock Read-CgrWizardInput {
                if ($Stage -eq 'Count') { return 'c' }
                return ''
            } -ParameterFilter { $Prompt -eq 'Release count limit' }
            Mock Copy-GitHubRepository
            Mock Invoke-CgrApprovedMigrationPlan

            $result = Invoke-CgrRepositoryCopyWizard -HostName github.com -ExecutionGuard { $true }

            $result.Status | Should -Be 'Cancelled'
            $result.MutatedGitHub | Should -BeFalse
            Should -Invoke Copy-GitHubRepository -Times 0 -Exactly
            Should -Invoke Invoke-CgrApprovedMigrationPlan -Times 0 -Exactly
        }
    }
}
