BeforeAll {
    $root = Split-Path -Parent $PSScriptRoot
    $modulePath = Join-Path $root 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
    Import-Module $modulePath -Force
}

Describe 'Wizard scalable repository selection' {
    It 'keeps small repository collections on one simple page' {
        InModuleScope CopyGitHubRepo {
            $repositories = 1..3 | ForEach-Object { [pscustomobject] @{ FullName = "owner/repo$_" } }
            $script:messages = [System.Collections.Generic.List[string]]::new()
            Mock Write-CgrWizardMessage { param($Message) if ($Message) { $script:messages.Add($Message) } }
            Mock Read-CgrWizardInput { '2' }

            $result = Select-CgrWizardRepository -Repositories $repositories -PageSize 20

            $result.Value.FullName | Should -Be 'owner/repo2'
            ($script:messages -join "`n") | Should -Not -Match 'page 1 of 1'
        }
    }

    It 'pages large collections without dumping every repository' {
        InModuleScope CopyGitHubRepo {
            $repositories = 1..45 | ForEach-Object { [pscustomobject] @{ FullName = ('owner/repo{0:d2}' -f $_) } }
            $script:inputs = [System.Collections.Generic.Queue[string]]::new()
            $script:inputs.Enqueue('n')
            $script:inputs.Enqueue('2')
            $script:messages = [System.Collections.Generic.List[string]]::new()
            Mock Write-CgrWizardMessage { param($Message) if ($Message) { $script:messages.Add($Message) } }
            Mock Read-CgrWizardInput { $script:inputs.Dequeue() }

            $result = Select-CgrWizardRepository -Repositories $repositories -PageSize 20

            $result.Value.FullName | Should -Be 'owner/repo22'
            ($script:messages -join "`n") | Should -Match 'Showing 1-20 of 45 repositories'
            ($script:messages -join "`n") | Should -Match 'Showing 21-40 of 45 repositories'
            ($script:messages -join "`n") | Should -Not -Match 'owner/repo45'
        }
    }

    It 'resets paging after filtering and selects from the filtered window' {
        InModuleScope CopyGitHubRepo {
            $repositories = 1..30 | ForEach-Object { [pscustomobject] @{ FullName = ('owner/repo{0:d2}' -f $_) } }
            $script:inputs = [System.Collections.Generic.Queue[string]]::new()
            $script:inputs.Enqueue('n')
            $script:inputs.Enqueue('f')
            $script:inputs.Enqueue('repo03')
            $script:inputs.Enqueue('1')
            Mock Write-CgrWizardMessage
            Mock Read-CgrWizardInput { $script:inputs.Dequeue() }

            $result = Select-CgrWizardRepository -Repositories $repositories -PageSize 10

            $result.Value.FullName | Should -Be 'owner/repo03'
        }
    }
}

Describe 'Wizard destination list resolution' {
    It 'shows the selected repository name as the default and uses it unchanged' {
        InModuleScope CopyGitHubRepo {
            $selected = [pscustomobject] @{ FullName = 'owner/existing' }
            Mock Read-CgrWizardRepositoryName { ConvertTo-CgrWizardNavigationResult -Action List }
            Mock Select-CgrWizardRepository { ConvertTo-CgrWizardNavigationResult -Action Next -Value $selected }
            Mock Read-CgrWizardChoice {
                param($DefaultValue)
                ConvertTo-CgrWizardNavigationResult -Action Next -Value $DefaultValue
            }
            Mock Write-CgrWizardMessage

            $result = Resolve-CgrWizardDestinationRepository -Repositories @($selected)

            $result.Value | Should -Be 'owner/existing'
            Should -Invoke Read-CgrWizardChoice -Times 1 -Exactly -ParameterFilter {
                $Title -eq 'Use selected destination' -and
                $Choices[0] -eq 'owner/existing' -and
                $Choices[1] -eq 'Modify repository name' -and
                $Choices[2] -eq 'Choose another repository' -and
                $DefaultValue -eq 'owner/existing'
            }
        }
    }

    It 'allows editing a selected destination before returning the resolved value' {
        InModuleScope CopyGitHubRepo {
            $selected = [pscustomobject] @{ FullName = 'owner/existing' }
            $script:readCount = 0
            Mock Read-CgrWizardRepositoryName {
                $script:readCount++
                if ($script:readCount -eq 1) { return ConvertTo-CgrWizardNavigationResult -Action List }
                ConvertTo-CgrWizardNavigationResult -Action Next -Value 'owner/new-name'
            }
            Mock Select-CgrWizardRepository { ConvertTo-CgrWizardNavigationResult -Action Next -Value $selected }
            Mock Read-CgrWizardChoice { ConvertTo-CgrWizardNavigationResult -Action Next -Value 'Modify repository name' }
            Mock Write-CgrWizardMessage

            $result = Resolve-CgrWizardDestinationRepository -Repositories @($selected)
            $result.Value | Should -Be 'owner/new-name'
        }
    }

    It 'can choose another repository before resolving the destination' {
        InModuleScope CopyGitHubRepo {
            $one = [pscustomobject] @{ FullName = 'owner/one' }
            $two = [pscustomobject] @{ FullName = 'owner/two' }
            $script:selectCount = 0
            $script:choiceCount = 0
            Mock Read-CgrWizardRepositoryName { ConvertTo-CgrWizardNavigationResult -Action List }
            Mock Select-CgrWizardRepository {
                $script:selectCount++
                ConvertTo-CgrWizardNavigationResult -Action Next -Value $(if ($script:selectCount -eq 1) { $one } else { $two })
            }
            Mock Read-CgrWizardChoice {
                $script:choiceCount++
                ConvertTo-CgrWizardNavigationResult -Action Next -Value $(if ($script:choiceCount -eq 1) { 'Choose another repository' } else { 'owner/two' })
            }
            Mock Write-CgrWizardMessage

            $result = Resolve-CgrWizardDestinationRepository -Repositories @($one, $two)
            $result.Value | Should -Be 'owner/two'
        }
    }
}

Describe 'Wizard execution semantics' {
    It 'renames only the final Execute/Cancel choice heading' {
        InModuleScope CopyGitHubRepo {
            $script:headings = [System.Collections.Generic.List[string]]::new()
            Mock Write-CgrWizardMessage { param($Message, $Style) if ($Style -eq 'Heading') { $script:headings.Add($Message) } }
            Mock Read-CgrWizardInput { '2' }

            Read-CgrWizardChoice -Title 'Repository copy plan' -Choices @('Execute', 'Cancel') -DefaultValue Cancel | Out-Null
            $script:headings | Should -Contain 'Confirm repository copy'
            $script:headings | Should -Not -Contain 'Repository copy plan'
        }
    }

    It 'describes a no-op Git LFS stage without claiming transfer' {
        InModuleScope CopyGitHubRepo {
            $result = [pscustomobject] @{ UsesGitLfs = $false; PointerFiles = @(); ObjectsCopied = $false; IsSuccessful = $true }
            Get-CgrActivityCompletionMessage -Name TransferGitLfs -DefaultMessage 'Transfer Git LFS objects' -Result $result |
                Should -Be 'No Git LFS objects found; no transfer required.'
        }
    }

    It 'reports useful Git LFS evidence after a transfer' {
        InModuleScope CopyGitHubRepo {
            $result = [pscustomobject] @{ UsesGitLfs = $true; PointerFiles = @('one.bin', 'two.bin'); ObjectsCopied = $true; IsSuccessful = $true }
            Get-CgrActivityCompletionMessage -Name TransferGitLfs -DefaultMessage 'Transfer Git LFS objects' -Result $result |
                Should -Be 'Transferred Git LFS objects for 2 tracked path(s).'
        }
    }

    It 'shows verification and restoration outcomes before the completion heading and treats no protection as a no-op' {
        InModuleScope CopyGitHubRepo {
            $script:messages = [System.Collections.Generic.List[string]]::new()
            Mock Write-CgrWizardMessage { param($Message) if ($Message) { $script:messages.Add($Message) } }
            $result = [pscustomobject] @{
                DestinationRepository = 'owner/destination'
                DestinationHtmlUrl = 'https://example.invalid/owner/destination'
                IsVerified = $true
                SettingsRestored = $true
                ProtectionRestored = $false
                Settings = [pscustomobject] @{ IsSuccessful = $true }
                Protection = [pscustomobject] @{ Restored = @(); Skipped = @(); IsSuccessful = $true; IsComplete = $true }
                Plan = [pscustomobject] @{ ContentMode = 'Snapshot'; SkipSettings = $false; ArchiveRepository = $null }
                Provenance = $null
            }

            Write-CgrWizardCompletionSummary -Result $result
            $text = $script:messages -join "`n"
            $text | Should -Match 'No transferable repository protection to restore\.'
            $text | Should -Not -Match 'protection restored and verified'
            $text.IndexOf('Verify destination content') | Should -BeLessThan $text.IndexOf('Repository copy complete')
            $text.IndexOf('No transferable repository protection') | Should -BeLessThan $text.IndexOf('Repository copy complete')
        }
    }
}
