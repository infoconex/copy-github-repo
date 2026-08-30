function Resolve-CgrWizardDestinationRepository {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Repositories,

        [AllowEmptyString()]
        [string] $CurrentValue,

        [switch] $AllowBack,

        [switch] $AllowCancel
    )

    $entryResult = Read-CgrWizardRepositoryName `
        -Kind Destination `
        -CurrentValue $CurrentValue `
        -AllowList `
        -AllowBack:$AllowBack `
        -AllowCancel:$AllowCancel

    if ($entryResult.Action -ne 'List') {
        return $entryResult
    }

    while ($true) {
        $selectionResult = Select-CgrWizardRepository `
            -Repositories $Repositories `
            -Title 'Select destination repository' `
            -HelpTopic DestinationRepository `
            -AllowBack:$AllowBack `
            -AllowCancel:$AllowCancel

        if ($selectionResult.Action -ne 'Next') {
            return $selectionResult
        }

        $selectedRepository = $selectionResult.Value
        $selectedRepositoryName = [string] $selectedRepository.FullName
        Write-CgrWizardMessage
        Write-CgrWizardMessage -Message 'Destination repository' -Style Heading
        Write-CgrWizardMessage -Message ('  Selected: {0}' -f $selectedRepositoryName) -Style Value

        $selectionAction = Read-CgrWizardChoice `
            -Title 'Use selected destination' `
            -Choices @($selectedRepositoryName, 'Modify repository name', 'Choose another repository') `
            -DefaultValue $selectedRepositoryName `
            -HelpTopic DestinationRepository `
            -AllowBack:$AllowBack `
            -AllowCancel:$AllowCancel

        if ($selectionAction.Action -ne 'Next') {
            return $selectionAction
        }

        if ($selectionAction.Value -eq $selectedRepositoryName) {
            return ConvertTo-CgrWizardNavigationResult -Action Next -Value $selectedRepositoryName
        }

        switch ($selectionAction.Value) {
            'Modify repository name' {
                return Read-CgrWizardRepositoryName `
                    -Kind Destination `
                    -CurrentValue $selectedRepositoryName `
                    -AllowBack:$AllowBack `
                    -AllowCancel:$AllowCancel
            }
            'Choose another repository' {
                continue
            }
        }
    }
}
