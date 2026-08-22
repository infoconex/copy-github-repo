function Show-CgrWizardHelp {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet(
            'SourceRepository',
            'DestinationRepository',
            'ExistingDestination',
            'ContentMode',
            'DestinationVisibility',
            'SupportedSettings',
            'SnapshotCommitMessage',
            'ArchiveRepositoryName',
            'MigrationPlan',
            'ExactConfirmation'
        )]
        [string] $Topic
    )

    $help = switch ($Topic) {
        'SourceRepository' {
            @(
                'Source repository help'
                ''
                'Choose the GitHub repository whose content you want to copy.'
                'Use F to filter a long repository list by owner or repository name.'
                'The source is read during planning and copy; a normal different-name copy does not rename or delete it.'
            )
        }
        'DestinationRepository' {
            @(
                'Destination repository help'
                ''
                'Enter the destination as owner/name, for example infoconex/copy-github-repo-test.'
                'If the destination does not exist, the wizard can create it.'
                'If a different destination already exists, the wizard can let you choose another name or preserve the existing repository by archiving and replacing it.'
            )
        }
        'ExistingDestination' {
            @(
                'Existing destination help'
                ''
                'Choose another destination when you do not want to change the existing repository.'
                'Archive and replace renames the existing destination to an archive name, verifies that rename, then creates a fresh repository at the original destination name.'
                'The existing repository is not deleted by this workflow.'
            )
        }
        'ContentMode' {
            @(
                'Content mode help'
                ''
                'Snapshot creates one new root commit containing the selected source default-branch content. Prior commit history, other branches, and tags are not copied.'
                'FullHistory preserves ordinary Git commit history, branches, tags, and reachable Git LFS objects.'
                'Use Snapshot when you want a clean repository without prior history; use FullHistory when history must be retained.'
            )
        }
        'DestinationVisibility' {
            @(
                'Destination visibility help'
                ''
                'public makes the repository visible to everyone.'
                'private restricts access to explicitly authorized users and teams.'
                'internal is available only where the GitHub account and organization support internal repositories.'
                'The safest default is to preserve the source repository visibility.'
            )
        }
        'SupportedSettings' {
            @(
                'Supported repository settings help'
                ''
                'Restore reapplies the repository settings the module currently supports and verifies them after the content copy succeeds.'
                'Skip leaves those destination settings at their newly created defaults.'
                'Unsupported settings are reported rather than silently assumed to have copied.'
            )
        }
        'SnapshotCommitMessage' {
            @(
                'Snapshot commit message help'
                ''
                'This text becomes the message of the single new root commit created by Snapshot mode.'
                'It does not change the source repository.'
                'The default is Initial repository commit, and you can replace it with any non-empty commit message.'
            )
        }
        'ArchiveRepositoryName' {
            @(
                'Archive repository name help'
                ''
                'The archive name is used to preserve an existing repository before its original name is reused.'
                'Enter only the repository-name portion, not owner/name.'
                'The archive name must be unused. The wizard verifies this before any rename occurs.'
            )
        }
        'MigrationPlan' {
            @(
                'Repository copy plan help'
                ''
                'The displayed plan comes from the real Copy-GitHubRepository -PlanOnly path.'
                'No remote mutation has occurred merely because the plan is displayed.'
                'Choose Execute only after the source, destination, archive behavior, visibility, content mode, and planned steps are correct.'
            )
        }
        'ExactConfirmation' {
            @(
                'Exact confirmation help'
                ''
                'This safety confirmation protects repository-name reuse operations.'
                'Copy the displayed confirmation text exactly, including owner names, repository names, separators, and capitalization.'
                'Force and Confirm:$false do not bypass this confirmation requirement.'
            )
        }
    }

    $navigation = if ($Topic -eq 'SourceRepository') {
        @(
            ''
            'Navigation'
            'F   Filter the repository list'
            '?   Show help for this step'
            'C   Cancel without making changes'
        )
    }
    else {
        @(
            ''
            'Navigation'
            '?   Show help for this step'
            'B   Return to the previous step when Back is shown'
            'C   Cancel without making changes'
        )
    }

    $help = @($help) + $navigation
    Write-CgrWizardMessage
    for ($index = 0; $index -lt $help.Count; $index++) {
        $style = if ($index -eq 0 -or $help[$index] -eq 'Navigation') { 'Heading' } elseif ($index -eq $help.Count - 1) { 'Hint' } else { 'Normal' }
        Write-CgrWizardMessage -Message $help[$index] -Style $style
    }
    Write-CgrWizardMessage
    Read-CgrWizardInput -Prompt 'Press Enter to return' | Out-Null
}
