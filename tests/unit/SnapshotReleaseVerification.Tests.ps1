BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $modulePath = Join-Path $repositoryRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
    Import-Module $modulePath -Force
}

Describe 'Approved Snapshot release checkpoint verification' {
    BeforeEach {
        InModuleScope CopyGitHubRepo {
            $script:source = [pscustomobject] @{ FullName = 'acme/source'; HostName = 'github.com' }
            $script:destination = [pscustomobject] @{
                FullName = 'acme/destination'
                HostName = 'github.com'
                CloneUrl = 'https://github.com/acme/destination.git'
                DefaultBranch = 'main'
            }
            $script:plan = [pscustomobject] @{
                PlannedSnapshotCommitCount = 3
                FinalHeadCheckpointRequired = $true
                SourceHead = [pscustomobject] @{ DefaultBranch = 'main'; CommitSha = 'source-head'; TreeSha = 'tree-head' }
                Checkpoints = @(
                    [pscustomobject] @{ Order = 1; SourceCommitSha = 'source-v1'; SourceTreeSha = 'tree-v1'; TagNames = @('v1.0.0') },
                    [pscustomobject] @{ Order = 2; SourceCommitSha = 'source-v2'; SourceTreeSha = 'tree-v2'; TagNames = @('v2.0.0') }
                )
                ReleaseEvidence = @(
                    [pscustomobject] @{ TagName = 'v1.0.0'; PeeledCommitSha = 'source-v1' },
                    [pscustomobject] @{ TagName = 'v2.0.0'; PeeledCommitSha = 'source-v2' }
                )
            }
            $script:treeV2 = 'tree-v2'
            $script:v1Target = 'destination-1'

            Mock Invoke-CgrGitCommand {
                [pscustomobject] @{ ExitCode = 0; Output = @(); ErrorText = '' }
            }
            Mock Invoke-CgrNativeCommand {
                $joined = $ArgumentList -join ' '
                if ($joined -match 'rev-list --reverse refs/heads/main$') {
                    return [pscustomobject] @{ ExitCode = 0; Output = @('destination-1', 'destination-2', 'destination-3'); ErrorText = '' }
                }
                if ($joined -match 'rev-list --parents -n 1 destination-1$') { return [pscustomobject] @{ ExitCode = 0; Output = @('destination-1'); ErrorText = '' } }
                if ($joined -match 'rev-list --parents -n 1 destination-2$') { return [pscustomobject] @{ ExitCode = 0; Output = @('destination-2 destination-1'); ErrorText = '' } }
                if ($joined -match 'rev-list --parents -n 1 destination-3$') { return [pscustomobject] @{ ExitCode = 0; Output = @('destination-3 destination-2'); ErrorText = '' } }
                if ($joined -match 'rev-parse destination-1\^\{tree\}$') { return [pscustomobject] @{ ExitCode = 0; Output = @('tree-v1'); ErrorText = '' } }
                if ($joined -match 'rev-parse destination-2\^\{tree\}$') { return [pscustomobject] @{ ExitCode = 0; Output = @($script:treeV2); ErrorText = '' } }
                if ($joined -match 'rev-parse destination-3\^\{tree\}$') { return [pscustomobject] @{ ExitCode = 0; Output = @('tree-head'); ErrorText = '' } }
                if ($joined -match 'rev-parse refs/tags/v1.0.0\^\{commit\}$') { return [pscustomobject] @{ ExitCode = 0; Output = @($script:v1Target); ErrorText = '' } }
                if ($joined -match 'rev-parse refs/tags/v2.0.0\^\{commit\}$') { return [pscustomobject] @{ ExitCode = 0; Output = @('destination-2'); ErrorText = '' } }
                if ($joined -match 'for-each-ref --format=%\(refname:strip=2\) refs/tags$') { return [pscustomobject] @{ ExitCode = 0; Output = @('v1.0.0', 'v2.0.0'); ErrorText = '' } }
                throw "Unexpected git verification command: $joined"
            }
        }
    }

    It 'verifies multiple sequential checkpoints tags and a required final HEAD checkpoint from reviewed evidence' {
        InModuleScope CopyGitHubRepo {
            $result = Invoke-CgrApprovedSnapshotReleaseVerification -SourceRepository $script:source -DestinationRepository $script:destination -ReleaseCheckpointPlan $script:plan

            $result.IsSuccessful | Should -BeTrue
            $result.DestinationCommitCount | Should -Be 3
            $result.FinalHeadCheckpointRequired | Should -BeTrue
            @($result.Checkpoints).Count | Should -Be 2
            $result.Checkpoints[0].DestinationCommitSha | Should -Be 'destination-1'
            $result.Checkpoints[1].DestinationTreeSha | Should -Be 'tree-v2'
            $result.DestinationHeadTreeSha | Should -Be 'tree-head'
            @($result.ReleaseTags | Where-Object { -not $_.IsSuccessful }).Count | Should -Be 0
            Should -Invoke Invoke-CgrGitCommand -Times 1 -Exactly -ParameterFilter { $ArgumentList[0] -eq 'clone' -and $ArgumentList[1] -eq '--bare' }
            Should -Invoke Invoke-CgrNativeCommand -Times 0 -ParameterFilter {
                ($ArgumentList -join ' ') -match '(?i)\b(push|commit-tree|tag -[afd]|update-ref)\b'
            }
        }
    }

    It 'reports a wrong destination release-tag target as a concrete verification mismatch' {
        InModuleScope CopyGitHubRepo {
            $script:v1Target = 'destination-2'
            $result = Invoke-CgrApprovedSnapshotReleaseVerification -SourceRepository $script:source -DestinationRepository $script:destination -ReleaseCheckpointPlan $script:plan

            $result.IsSuccessful | Should -BeFalse
            $check = $result.Checks | Where-Object Name -EQ 'SnapshotReleaseTagTarget:v1.0.0'
            $check.Passed | Should -BeFalse
            $check.Expected | Should -Be 'destination-1'
            $check.Actual | Should -Be 'destination-2'
        }
    }

    It 'reports checkpoint tree/content mismatch without comparing source and destination commit identity' {
        InModuleScope CopyGitHubRepo {
            $script:treeV2 = 'altered-tree'
            $result = Invoke-CgrApprovedSnapshotReleaseVerification -SourceRepository $script:source -DestinationRepository $script:destination -ReleaseCheckpointPlan $script:plan

            $result.IsSuccessful | Should -BeFalse
            $check = $result.Checks | Where-Object Name -EQ 'SnapshotCheckpointTree:2'
            $check.Passed | Should -BeFalse
            $check.Expected | Should -Be 'tree-v2'
            $check.Actual | Should -Be 'altered-tree'
            $result.Checkpoints[1].SourceCommitSha | Should -Be 'source-v2'
            $result.Checkpoints[1].DestinationCommitSha | Should -Be 'destination-2'
        }
    }

    It 'accepts no additional final commit when reviewed HEAD equals the latest release state' {
        InModuleScope CopyGitHubRepo {
            $plan = [pscustomobject] @{
                PlannedSnapshotCommitCount = 1
                FinalHeadCheckpointRequired = $false
                SourceHead = [pscustomobject] @{ DefaultBranch = 'main'; CommitSha = 'source-head'; TreeSha = 'tree-v1' }
                Checkpoints = @([pscustomobject] @{ Order = 1; SourceCommitSha = 'source-v1'; SourceTreeSha = 'tree-v1'; TagNames = @('v1.0.0') })
                ReleaseEvidence = @([pscustomobject] @{ TagName = 'v1.0.0'; PeeledCommitSha = 'source-v1' })
            }
            Mock Invoke-CgrNativeCommand {
                $joined = $ArgumentList -join ' '
                if ($joined -match 'rev-list --reverse refs/heads/main$') { return [pscustomobject] @{ ExitCode = 0; Output = @('destination-1'); ErrorText = '' } }
                if ($joined -match 'rev-list --parents -n 1 destination-1$') { return [pscustomobject] @{ ExitCode = 0; Output = @('destination-1'); ErrorText = '' } }
                if ($joined -match 'rev-parse destination-1\^\{tree\}$') { return [pscustomobject] @{ ExitCode = 0; Output = @('tree-v1'); ErrorText = '' } }
                if ($joined -match 'rev-parse refs/tags/v1.0.0\^\{commit\}$') { return [pscustomobject] @{ ExitCode = 0; Output = @('destination-1'); ErrorText = '' } }
                if ($joined -match 'for-each-ref --format=%\(refname:strip=2\) refs/tags$') { return [pscustomobject] @{ ExitCode = 0; Output = @('v1.0.0'); ErrorText = '' } }
                throw "Unexpected git verification command: $joined"
            }

            $result = Invoke-CgrApprovedSnapshotReleaseVerification -SourceRepository $script:source -DestinationRepository $script:destination -ReleaseCheckpointPlan $plan

            $result.IsSuccessful | Should -BeTrue
            $result.DestinationCommitCount | Should -Be 1
            ($result.Checks | Where-Object Name -EQ 'SnapshotFinalHeadCheckpointShape').Actual | Should -Be 'LatestReleaseCheckpoint'
        }
    }
}

Describe 'Approved Snapshot GitHub Release verification' {
    BeforeEach {
        InModuleScope CopyGitHubRepo {
            $script:source = [pscustomobject] @{ FullName = 'acme/source' }
            $script:destination = [pscustomobject] @{ FullName = 'acme/destination' }
            $script:selection = [pscustomobject] @{
                AvailableReleaseCount = 2
                SelectedReleaseCount = 1
                SelectedAssetCount = 1
                SourceLatestTag = 'v2.0.0'
                SourceLatestSelected = $true
                IncludePatterns = @('v2.*')
                ExcludePatterns = @()
                IncludePrerelease = $false
                IncludeDraftReleases = $false
                ReleaseCount = 1
                Releases = @([pscustomobject] @{
                        ReleaseId = 10
                        TagName = 'v2.0.0'
                        Name = 'Release 2.0'
                        Body = 'reviewed body'
                        Draft = $false
                        Prerelease = $false
                        IsLatest = $true
                        TargetCommitSha = 'source-v2'
                        Assets = @([pscustomobject] @{ Name = 'module.zip'; Label = 'package'; Size = 42; ContentType = 'application/zip'; Digest = 'sha256:abc' })
                    })
            }
            $script:releaseName = 'Release 2.0'
            $script:assetSize = 42
            $script:latestTag = 'v2.0.0'
            Mock Get-CgrGitHubReleaseSelection { throw 'Approved Snapshot verification must not rerun live source release selection.' }
            Mock Invoke-CgrGitHubApiReadRequest {
                $joined = $ArgumentList -join ' '
                if ($joined -match 'releases\?per_page=100') { return [pscustomobject] @{ ExitCode = 0; Output = @('[[{"tag_name":"v2.0.0"}]]'); ErrorText = '' } }
                if ($joined -match 'commits/v2.0.0') { return [pscustomobject] @{ ExitCode = 0; Output = @('destination-2'); ErrorText = '' } }
                if ($joined -match 'releases/tags/v2.0.0') {
                    $json = "{`"id`":20,`"tag_name`":`"v2.0.0`",`"name`":`"$script:releaseName`",`"body`":`"reviewed body`",`"draft`":false,`"prerelease`":false,`"assets`":[{`"name`":`"module.zip`",`"label`":`"package`",`"size`":$script:assetSize,`"content_type`":`"application/zip`",`"digest`":`"sha256:abc`"}]}"
                    return [pscustomobject] @{ ExitCode = 0; Output = @($json); ErrorText = '' }
                }
                if ($joined -match 'releases/latest') { return [pscustomobject] @{ ExitCode = 0; Output = @("{`"tag_name`":`"$script:latestTag`"}"); ErrorText = '' } }
                throw "Unexpected release verification read: $joined"
            }
        }
    }

    It 'uses reviewed selection and Snapshot destination targets without live reselection' {
        InModuleScope CopyGitHubRepo {
            $targets = @([pscustomobject] @{ TagName = 'v2.0.0'; DestinationCommitSha = 'destination-2' })
            $result = Test-CgrGitHubReleaseMigration -SourceRepository $script:source -DestinationRepository $script:destination -ApprovedSelection $script:selection -DestinationTagTargets $targets -RequireExactDestinationReleaseSet

            $result.IsSuccessful | Should -BeTrue
            $result.UsedApprovedSelection | Should -BeTrue
            $result.Releases[0].ExpectedDestinationCommitSha | Should -Be 'destination-2'
            Should -Invoke Get-CgrGitHubReleaseSelection -Times 0
        }
    }

    It 'detects altered release metadata and altered asset evidence' {
        InModuleScope CopyGitHubRepo {
            $script:releaseName = 'Altered name'
            $script:assetSize = 99
            $targets = @([pscustomobject] @{ TagName = 'v2.0.0'; DestinationCommitSha = 'destination-2' })
            $result = Test-CgrGitHubReleaseMigration -SourceRepository $script:source -DestinationRepository $script:destination -ApprovedSelection $script:selection -DestinationTagTargets $targets -RequireExactDestinationReleaseSet

            $result.IsSuccessful | Should -BeFalse
            $result.Releases[0].Mismatches | Should -Contain 'Name'
            $result.Releases[0].Mismatches | Should -Contain 'AssetSize:module.zip'
        }
    }

    It 'detects an incorrect Latest designation' {
        InModuleScope CopyGitHubRepo {
            $script:latestTag = 'v1.0.0'
            $targets = @([pscustomobject] @{ TagName = 'v2.0.0'; DestinationCommitSha = 'destination-2' })
            $result = Test-CgrGitHubReleaseMigration -SourceRepository $script:source -DestinationRepository $script:destination -ApprovedSelection $script:selection -DestinationTagTargets $targets -RequireExactDestinationReleaseSet

            $result.IsSuccessful | Should -BeFalse
            $result.LatestReleaseMatches | Should -BeFalse
            ($result.Checks | Where-Object Name -EQ 'GitHubLatestReleaseMatches').Actual | Should -Be 'v1.0.0'
        }
    }
}

Describe 'Test-GitHubRepositoryMigration Snapshot release contract' {
    It 'requires reviewed planning evidence and does not rerun live selection' {
        InModuleScope CopyGitHubRepo {
            Mock Get-CgrPrerequisiteStatus {
                [pscustomobject] @{
                    Git = [pscustomobject] @{ Found = $true }
                    GitHubCli = [pscustomobject] @{ Found = $true }
                    Authentication = [pscustomobject] @{ Authenticated = $true; Message = 'Authenticated' }
                }
            }
            Mock Get-CgrRepository {
                param($Repository)
                [pscustomobject] @{ FullName = $Repository; HostName = 'github.com'; CloneUrl = "https://github.com/$Repository.git"; DefaultBranch = 'main' }
            }
            Mock Get-CgrGitHubReleaseSelection { throw 'Live source release selection must not run.' }
            Mock Invoke-CgrApprovedSnapshotReleaseVerification {
                [pscustomobject] @{
                    IsSuccessful = $true
                    ReleaseTags = @([pscustomobject] @{ TagName = 'v1.0.0'; DestinationCommitSha = 'destination-1' })
                    Checks = @()
                }
            }
            Mock Test-CgrGitHubReleaseMigration {
                [pscustomobject] @{ IsSuccessful = $true; SelectedReleaseCount = 1; VerifiedReleaseCount = 1 }
            }
            $selection = [pscustomobject] @{ Releases = @([pscustomobject] @{ TagName = 'v1.0.0' }) }
            $plan = [pscustomobject] @{
                ContentMode = 'Snapshot'
                IncludeReleases = $true
                SourceRepository = 'acme/source'
                ReleaseSelection = $selection
                ReleaseCheckpointPlan = [pscustomobject] @{ PlannedSnapshotCommitCount = 1 }
            }

            $result = Test-GitHubRepositoryMigration -SourceRepository acme/source -DestinationRepository acme/destination -ContentMode Snapshot -IncludeReleases -ApprovedPlan $plan

            $result.IsSuccessful | Should -BeTrue
            $result.ReleasesVerified | Should -BeTrue
            Should -Invoke Get-CgrGitHubReleaseSelection -Times 0
            Should -Invoke Get-CgrRepository -Times 1 -Exactly -ParameterFilter { $Repository -eq 'acme/destination' }
            Should -Invoke Test-CgrGitHubReleaseMigration -Times 1 -Exactly -ParameterFilter {
                $ApprovedSelection -eq $selection -and $RequireExactDestinationReleaseSet
            }
        }
    }

    It 'fails closed before prerequisite work when approved Snapshot release evidence is absent' {
        InModuleScope CopyGitHubRepo {
            Mock Get-CgrPrerequisiteStatus { throw 'Prerequisite work must not run without approved evidence.' }
            { Test-GitHubRepositoryMigration -SourceRepository acme/source -DestinationRepository acme/destination -ContentMode Snapshot -IncludeReleases } |
                Should -Throw -ErrorId 'SnapshotReleaseVerificationPlanRequired,Test-GitHubRepositoryMigration'
            Should -Invoke Get-CgrPrerequisiteStatus -Times 0
        }
    }
}

Describe 'Snapshot post-release verification gating' {
    It 'independently verifies recreated releases before settings and protection restoration' {
        InModuleScope CopyGitHubRepo {
            $selection = [pscustomobject] @{ Releases = @([pscustomobject] @{ TagName = 'v1.0.0' }) }
            $plan = [pscustomobject] @{ ContentMode = 'Snapshot'; IncludeReleases = $true; ReleaseSelection = $selection; SkipSettings = $false }
            $verification = [pscustomobject] @{
                IsSuccessful = $true
                ReleaseTags = @([pscustomobject] @{ TagName = 'v1.0.0'; DestinationCommitSha = 'destination-1' })
            }
            $source = [pscustomobject] @{ FullName = 'acme/source' }
            $destination = [pscustomobject] @{ FullName = 'acme/destination' }
            $completed = [System.Collections.Generic.List[object]]::new()
            $failureStage = 'BeforePostVerification'
            Mock Invoke-CgrActivityStage { & $Action }
            Mock Test-CgrGitHubReleaseMigration { [pscustomobject] @{ IsSuccessful = $true } }
            Mock Set-CgrGitHubRepositorySetting { [pscustomobject] @{ IsSuccessful = $true } }
            Mock Set-CgrRepositoryProtectionConfiguration { [pscustomobject] @{ IsSuccessful = $true; IsComplete = $true } }

            $result = Invoke-CgrPostVerificationConfigurationRestore -Plan $plan -SourceRepository $source -DestinationRepository $destination -Verification $verification -VerificationFailureReason SnapshotVerificationFailed -CompletedSteps $completed -FailureStage ([ref] $failureStage)

            $verification.ReleasesVerified | Should -BeTrue
            $verification.IsSuccessful | Should -BeTrue
            @($completed.Name) | Should -Contain 'VerifyGitHubReleases'
            $result.Settings.IsSuccessful | Should -BeTrue
            Should -Invoke Test-CgrGitHubReleaseMigration -Times 1 -Exactly -ParameterFilter { $ApprovedSelection -eq $selection -and $RequireExactDestinationReleaseSet }
            Should -Invoke Set-CgrGitHubRepositorySetting -Times 1
        }
    }

    It 'blocks configuration mutation when independent release verification fails' {
        InModuleScope CopyGitHubRepo {
            $plan = [pscustomobject] @{ ContentMode = 'Snapshot'; IncludeReleases = $true; ReleaseSelection = [pscustomobject] @{ Releases = @() }; SkipSettings = $false }
            $verification = [pscustomobject] @{ IsSuccessful = $true; ReleaseTags = @() }
            $source = [pscustomobject] @{ FullName = 'acme/source' }
            $destination = [pscustomobject] @{ FullName = 'acme/destination' }
            $completed = [System.Collections.Generic.List[object]]::new()
            $failureStage = 'BeforePostVerification'
            Mock Invoke-CgrActivityStage { & $Action }
            Mock Test-CgrGitHubReleaseMigration { [pscustomobject] @{ IsSuccessful = $false; Checks = @([pscustomobject] @{ Name = 'GitHubReleaseSetMatchesReviewedSelection'; Passed = $false }) } }
            Mock Set-CgrGitHubRepositorySetting { throw 'Settings mutation must remain blocked.' }
            Mock Set-CgrRepositoryProtectionConfiguration { throw 'Protection mutation must remain blocked.' }

            $result = Invoke-CgrPostVerificationConfigurationRestore -Plan $plan -SourceRepository $source -DestinationRepository $destination -Verification $verification -VerificationFailureReason SnapshotVerificationFailed -CompletedSteps $completed -FailureStage ([ref] $failureStage)

            $verification.IsSuccessful | Should -BeFalse
            $verification.ReleasesVerified | Should -BeFalse
            $result.Settings.IsSuccessful | Should -BeFalse
            $result.Protection.IsSuccessful | Should -BeFalse
            Should -Invoke Set-CgrGitHubRepositorySetting -Times 0
            Should -Invoke Set-CgrRepositoryProtectionConfiguration -Times 0
        }
    }
}
