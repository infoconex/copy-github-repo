BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:modulePath = Join-Path $repositoryRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
    Import-Module $script:modulePath -Force
}

Describe 'CopyGitHubRepo module' {
    It 'has a valid module manifest' {
        Test-ModuleManifest -Path $script:modulePath | Should -Not -BeNullOrEmpty
    }

    It 'exports the approved public command surface' {
        $actualCommands = Get-Command -Module CopyGitHubRepo | Select-Object -ExpandProperty Name | Sort-Object
        $expectedCommands = @(
            'Copy-GitHubRepository'
            'Get-GitHubRepository'
            'Start-CopyGitHubRepositoryWizard'
            'Test-GitHubRepositoryMigration'
        ) | Sort-Object
        ($actualCommands -join ',') | Should -Be ($expectedCommands -join ',')
    }

    It 'requires PowerShell 7.4 or newer' {
        $manifest = Import-PowerShellDataFile -Path $script:modulePath
        $manifest.PowerShellVersion | Should -Be '7.4'
        $manifest.CompatiblePSEditions | Should -Contain 'Core'
    }
}

InModuleScope CopyGitHubRepo {
    Describe 'Repository copy planning' {
        BeforeEach {
            $script:prerequisites = [pscustomobject] @{
                Git = [pscustomobject] @{ Found = $true }
                GitHubCli = [pscustomobject] @{ Found = $true }
                Authentication = [pscustomobject] @{ Authenticated = $true; Message = 'Authenticated.' }
            }
            $script:source = [pscustomobject] @{
                PSTypeName = 'CopyGitHubRepo.Repository'
                Id = 101L
                NodeId = 'R_source'
                Name = 'source'
                FullName = 'infoconex/source'
                Owner = 'infoconex'
                Visibility = 'public'
                IsPrivate = $false
                IsArchived = $false
                IsFork = $false
                DefaultBranch = 'main'
                Description = 'Source repository.'
                HtmlUrl = 'https://github.com/infoconex/source'
                CloneUrl = 'https://github.com/infoconex/source.git'
                HostName = 'github.com'
                CanAdmin = $true
                CanPush = $true
            }
            Mock Get-CgrPrerequisiteStatus { $script:prerequisites }
            Mock Get-CgrRepository { $script:source } -ParameterFilter { $Repository -eq 'infoconex/source' }
            Mock Test-CgrGitHubRepositoryExistence { $false }
            Mock Get-CgrRepositoryProtectionConfiguration {
                [pscustomobject] @{ Rulesets = @(); BranchProtection = $null; Unsupported = @() }
            }
            Mock Get-CgrApprovedSourceState {
                if ($ContentMode -eq 'FullHistory') {
                    [pscustomobject] @{
                        PSTypeName = 'CopyGitHubRepo.ApprovedSourceState'
                        ContentMode = 'FullHistory'; Repository = 'infoconex/source'; RepositoryId = 101L; RepositoryNodeId = 'R_source'
                        DefaultBranch = 'main'; Refs = @('refs/heads/main source-commit'); ReachableCommitCount = 1
                        BranchTrees = @('refs/heads/main source-tree'); GitLfsObjectsAvailable = $true
                    }
                }
                else {
                    [pscustomobject] @{
                        PSTypeName = 'CopyGitHubRepo.ApprovedSourceState'
                        ContentMode = 'Snapshot'; Repository = 'infoconex/source'; RepositoryId = 101L; RepositoryNodeId = 'R_source'
                        DefaultBranch = 'main'; CommitSha = 'source-commit'; TreeSha = 'source-tree'; GitLfsObjectsAvailable = $false; GitLfsPointerFiles = @()
                    }
                }
            }
        }

        It 'returns a deterministic read-only Snapshot plan for a new destination' {
            $plan = Copy-GitHubRepository -SourceRepository infoconex/source -DestinationRepository infoconex/destination -PlanOnly
            $plan.PSTypeNames[0] | Should -Be 'CopyGitHubRepo.MigrationPlan'
            $plan.Mode | Should -Be 'NewDestination'
            $plan.ContentMode | Should -Be 'Snapshot'
            $plan.SourceState.CommitSha | Should -Be 'source-commit'
            $plan.SourceState.TreeSha | Should -Be 'source-tree'
            $plan.DestinationVisibility | Should -Be 'public'
            $plan.WillMutateGitHub | Should -BeFalse
            $plan.PlanOnly | Should -BeTrue
            @($plan.Steps).Count | Should -Be 5
            @($plan.Steps)[0].Name | Should -Be 'CreateDestinationRepository'
            @($plan.Steps)[-1].Name | Should -Be 'RestoreRepositoryProtection'
        }

        It 'defaults destination visibility to source visibility' {
            $script:source.Visibility = 'private'
            $script:source.IsPrivate = $true
            $plan = Copy-GitHubRepository -SourceRepository infoconex/source -DestinationRepository infoconex/private-copy -PlanOnly
            $plan.SourceVisibility | Should -Be 'private'
            $plan.DestinationVisibility | Should -Be 'private'
        }

        It 'stops planning when the destination already exists without explicit archive intent' {
            Mock Test-CgrGitHubRepositoryExistence { $true } -ParameterFilter { $Repository -eq 'infoconex/destination' }
            { Copy-GitHubRepository -SourceRepository infoconex/source -DestinationRepository infoconex/destination -PlanOnly } |
                Should -Throw -ErrorId 'DestinationRepositoryAlreadyExists,New-CgrMigrationPlan'
        }

        It 'requires an archive name for same-name replacement planning' {
            { Copy-GitHubRepository -SourceRepository infoconex/source -DestinationRepository infoconex/source -PlanOnly } |
                Should -Throw -ErrorId 'ArchiveRepositoryNameRequired,New-CgrMigrationPlan'
        }

        It 'plans same-name replacement when the archive is unused' {
            $plan = Copy-GitHubRepository `
                -SourceRepository infoconex/source `
                -DestinationRepository infoconex/source `
                -ArchiveRepositoryName source-archive `
                -PlanOnly
            $plan.Mode | Should -Be 'SameNameReplacement'
            $plan.ArchiveRepository | Should -Be 'infoconex/source-archive'
            @($plan.Steps)[0].Name | Should -Be 'PreserveSourceAsArchive'
        }

        It 'captures FullHistory ref evidence in the plan' {
            $plan = Copy-GitHubRepository `
                -SourceRepository infoconex/source `
                -DestinationRepository infoconex/destination `
                -ContentMode FullHistory `
                -PlanOnly
            $plan.ContentMode | Should -Be 'FullHistory'
            @($plan.SourceState.Refs) | Should -Contain 'refs/heads/main source-commit'
            $plan.SourceState.ReachableCommitCount | Should -Be 1
        }

        It 'returns JSON when JSON output is requested' {
            $json = Copy-GitHubRepository -SourceRepository infoconex/source -DestinationRepository infoconex/destination -PlanOnly -OutputMode Json
            $parsed = $json | ConvertFrom-Json
            $parsed.SourceRepository | Should -Be 'infoconex/source'
            $parsed.SourceState.CommitSha | Should -Be 'source-commit'
            $parsed.PlanOnly | Should -BeTrue
        }
    }

    Describe 'Public repository copy execution safety' {
        BeforeEach {
            $script:prerequisites = [pscustomobject] @{
                Git = [pscustomobject] @{ Found = $true }
                GitHubCli = [pscustomobject] @{ Found = $true }
                Authentication = [pscustomobject] @{ Authenticated = $true; Message = 'Authenticated.' }
            }
            $script:source = [pscustomobject] @{
                Id = 101L; NodeId = 'R_source'; FullName = 'infoconex/source'; Owner = 'infoconex'; Visibility = 'public'; IsPrivate = $false
                DefaultBranch = 'main'; Description = 'Source repository.'; CloneUrl = 'https://github.com/infoconex/source.git'; HostName = 'github.com'
            }
            $script:sourceState = [pscustomobject] @{
                ContentMode = 'Snapshot'; Repository = 'infoconex/source'; RepositoryId = 101L; RepositoryNodeId = 'R_source'
                DefaultBranch = 'main'; CommitSha = 'source-commit'; TreeSha = 'source-tree'; GitLfsObjectsAvailable = $false; GitLfsPointerFiles = @()
            }
            Mock Get-CgrPrerequisiteStatus { $script:prerequisites }
            Mock Get-CgrRepository { $script:source } -ParameterFilter { $Repository -eq 'infoconex/source' }
            Mock Test-CgrGitHubRepositoryExistence { $false }
            Mock Get-CgrRepositoryProtectionConfiguration { [pscustomobject] @{ Rulesets = @(); BranchProtection = $null; Unsupported = @() } }
            Mock Get-CgrApprovedSourceState {
                if ($ContentMode -eq 'FullHistory') {
                    [pscustomobject] @{
                        ContentMode = 'FullHistory'; Repository = 'infoconex/source'; RepositoryId = 101L; RepositoryNodeId = 'R_source'
                        DefaultBranch = 'main'; Refs = @('refs/heads/main source-commit'); ReachableCommitCount = 1
                        BranchTrees = @('refs/heads/main source-tree'); GitLfsObjectsAvailable = $true
                    }
                } else { $script:sourceState }
            }
            Mock Assert-CgrApprovedSourceState { $SourceState }
            Mock Invoke-CgrApprovedMigrationPlan {
                [pscustomobject] @{
                    PSTypeName = 'CopyGitHubRepo.MigrationExecutionResult'
                    Status = 'CompletedWithSupportedSettings'
                    Plan = $Plan
                    CompletedSteps = @()
                    IsVerified = $true
                }
            } -ParameterFilter { $Plan.Mode -ne 'SameNameReplacement' }
        }

        It 'executes the exact plan through the approved-plan boundary' {
            $result = Copy-GitHubRepository -SourceRepository infoconex/source -DestinationRepository infoconex/destination -Confirm:$false
            $result.Status | Should -Be 'CompletedWithSupportedSettings'
            $result.Plan.SourceState.CommitSha | Should -Be 'source-commit'
            Should -Invoke Invoke-CgrApprovedMigrationPlan -Times 1 -Exactly -ParameterFilter {
                $Plan.SourceState.CommitSha -eq 'source-commit' -and $SourceRepository.FullName -eq 'infoconex/source'
            }
        }

        It 'does not execute the plan when WhatIf prevents ShouldProcess' {
            $result = Copy-GitHubRepository -SourceRepository infoconex/source -DestinationRepository infoconex/destination -WhatIf
            $result.PSTypeNames[0] | Should -Be 'CopyGitHubRepo.MigrationPlan'
            Should -Invoke Invoke-CgrApprovedMigrationPlan -Times 0 -Exactly
        }

        It 'requires Force before changing destination visibility' {
            { Copy-GitHubRepository -SourceRepository infoconex/source -DestinationRepository infoconex/destination -DestinationVisibility private -Confirm:$false } |
                Should -Throw -ErrorId 'VisibilityChangeRequiresForce,Copy-GitHubRepository'
            Should -Invoke Invoke-CgrApprovedMigrationPlan -Times 0 -Exactly
        }

        It 'requires Force for non-interactive mutation' {
            { Copy-GitHubRepository -SourceRepository infoconex/source -DestinationRepository infoconex/destination -NonInteractive } |
                Should -Throw -ErrorId 'NonInteractiveExecutionRequiresForce,Copy-GitHubRepository'
        }

        It 'executes non-interactively when Force is supplied' {
            Copy-GitHubRepository -SourceRepository infoconex/source -DestinationRepository infoconex/destination -NonInteractive -Force | Out-Null
            Should -Invoke Invoke-CgrApprovedMigrationPlan -Times 1 -Exactly
        }

        It 'allows an explicit non-interactive visibility change only with Force' {
            Copy-GitHubRepository `
                -SourceRepository infoconex/source `
                -DestinationRepository infoconex/destination `
                -DestinationVisibility private `
                -NonInteractive `
                -Force | Out-Null
            Should -Invoke Invoke-CgrApprovedMigrationPlan -Times 1 -Exactly -ParameterFilter { $Plan.DestinationVisibility -eq 'private' }
        }

        It 'rejects unimplemented Pages and Actions mutation switches' {
            { Copy-GitHubRepository -SourceRepository infoconex/source -DestinationRepository infoconex/destination -RestorePages -Confirm:$false } |
                Should -Throw -ErrorId 'RestorePagesExecutionNotImplemented,Copy-GitHubRepository'
            { Copy-GitHubRepository -SourceRepository infoconex/source -DestinationRepository infoconex/destination -EnableActionsAfterMigration -Confirm:$false } |
                Should -Throw -ErrorId 'EnableActionsAfterMigrationExecutionNotImplemented,Copy-GitHubRepository'
        }

        It 'requires exact same-name confirmation even when Confirm is explicitly disabled' {
            Mock Invoke-CgrApprovedMigrationPlan {
                Assert-CgrSameNameReplacementConfirmation -Plan $Plan -Confirmation $SameNameConfirmation
            } -ParameterFilter { $Plan.Mode -eq 'SameNameReplacement' }

            { Copy-GitHubRepository `
                -SourceRepository infoconex/source `
                -DestinationRepository infoconex/source `
                -ArchiveRepositoryName source-archive `
                -Confirm:$false } |
                Should -Throw -ErrorId 'SameNameReplacementConfirmationRequired,Assert-CgrSameNameReplacementConfirmation'
        }

        It 'routes FullHistory through the approved-plan boundary with captured ref state' {
            Copy-GitHubRepository `
                -SourceRepository infoconex/source `
                -DestinationRepository infoconex/destination `
                -ContentMode FullHistory `
                -Confirm:$false | Out-Null
            Should -Invoke Invoke-CgrApprovedMigrationPlan -Times 1 -Exactly -ParameterFilter {
                $Plan.ContentMode -eq 'FullHistory' -and @($Plan.SourceState.Refs).Count -eq 1
            }
        }
    }

    Describe 'Prerequisite failures' {
        It 'fails clearly when GitHub CLI is missing' {
            Mock Get-CgrPrerequisiteStatus {
                [pscustomobject] @{
                    Git = [pscustomobject] @{ Found = $true }
                    GitHubCli = [pscustomobject] @{ Found = $false }
                    Authentication = [pscustomobject] @{ Authenticated = $false; Message = 'Unavailable.' }
                }
            }
            { Copy-GitHubRepository -SourceRepository infoconex/source -DestinationRepository infoconex/destination -PlanOnly } |
                Should -Throw -ErrorId 'GitHubCliNotFound,Copy-GitHubRepository'
        }

        It 'fails clearly when GitHub CLI is not authenticated' {
            Mock Get-CgrPrerequisiteStatus {
                [pscustomobject] @{
                    Git = [pscustomobject] @{ Found = $true }
                    GitHubCli = [pscustomobject] @{ Found = $true }
                    Authentication = [pscustomobject] @{ Authenticated = $false; Message = 'Authenticate first.' }
                }
            }
            { Copy-GitHubRepository -SourceRepository infoconex/source -DestinationRepository infoconex/destination -PlanOnly } |
                Should -Throw -ErrorId 'GitHubCliNotAuthenticated,Copy-GitHubRepository'
        }
    }
}
