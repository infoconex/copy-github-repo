function Select-CgrWizardRepository {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Repositories,

        [AllowNull()]
        [object] $CurrentValue,

        [AllowEmptyString()]
        [string] $FilterText,

        [ValidateNotNullOrEmpty()]
        [string] $Title = 'Select source repository',

        [ValidateSet('SourceRepository', 'DestinationRepository')]
        [string] $HelpTopic = 'SourceRepository',

        [ValidateRange(1, 100)]
        [int] $PageSize = 20,

        [switch] $AllowBack,

        [switch] $AllowCancel
    )

    $filter = if ($null -eq $FilterText) { '' } else { $FilterText.Trim() }
    $pageIndex = 0

    while ($true) {
        $visibleRepositories = @(if ([string]::IsNullOrWhiteSpace($filter)) {
            $Repositories
        }
        else {
            $Repositories | Where-Object {
                $fullName = [string] $_.FullName
                $fullName.IndexOf($filter, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
            }
        })

        $pageCount = [Math]::Max(1, [int] [Math]::Ceiling($visibleRepositories.Count / [double] $PageSize))
        if ($pageIndex -ge $pageCount) { $pageIndex = $pageCount - 1 }
        if ($pageIndex -lt 0) { $pageIndex = 0 }
        $pageStart = $pageIndex * $PageSize
        $pageRepositories = @($visibleRepositories | Select-Object -Skip $pageStart -First $PageSize)

        $currentRepository = $null
        if ($null -ne $CurrentValue) {
            $currentRepository = @($visibleRepositories | Where-Object { $_.FullName -eq $CurrentValue.FullName }) | Select-Object -First 1
        }

        $defaultRepository = $currentRepository
        if ($null -eq $defaultRepository -and $visibleRepositories.Count -eq 1) {
            $defaultRepository = $visibleRepositories[0]
        }

        Write-CgrWizardMessage
        Write-CgrWizardMessage -Message $Title -Style Heading
        if (-not [string]::IsNullOrWhiteSpace($filter)) {
            Write-CgrWizardMessage -Message ("Filter: {0}" -f $filter) -Style Hint
        }
        if ($visibleRepositories.Count -gt $PageSize) {
            Write-CgrWizardMessage -Message ("Showing {0}-{1} of {2} repositories (page {3} of {4})." -f ($pageStart + 1), [Math]::Min($pageStart + $PageSize, $visibleRepositories.Count), $visibleRepositories.Count, ($pageIndex + 1), $pageCount) -Style Hint
        }

        if ($visibleRepositories.Count -eq 0) {
            Write-CgrWizardMessage -Message 'No repositories match the current filter.' -Style Hint
        }
        else {
            for ($index = 0; $index -lt $pageRepositories.Count; $index++) {
                $repository = $pageRepositories[$index]
                $suffix = if ($null -ne $defaultRepository -and $repository.FullName -eq $defaultRepository.FullName) { ' (default)' } else { '' }
                Write-CgrWizardMessage -Message ('  {0}. {1}{2}' -f ($index + 1), $repository.FullName, $suffix)
            }
        }

        $inputText = Read-CgrWizardInput `
            -Prompt 'Choose a number' `
            -DefaultValue $(if ($null -ne $defaultRepository) { $defaultRepository.FullName } else { '' }) `
            -AllowFilter `
            -AllowPreviousPage:($pageIndex -gt 0) `
            -AllowNextPage:($pageIndex -lt ($pageCount - 1)) `
            -AllowHelp `
            -AllowBack:$AllowBack `
            -AllowCancel:$AllowCancel
        $navigation = Resolve-CgrWizardNavigationInput `
            -InputText $inputText `
            -AllowBack:$AllowBack `
            -AllowNext:($null -ne $defaultRepository) `
            -AllowCancel:$AllowCancel `
            -AllowHelp

        if ($null -ne $navigation) {
            if ($navigation.Action -eq 'Help') {
                Show-CgrWizardHelp -Topic $HelpTopic
                continue
            }
            if ($navigation.Action -eq 'Next') { $navigation.Value = $defaultRepository }
            return $navigation
        }

        switch ($inputText.Trim().ToLowerInvariant()) {
            'f' {
                $filterInput = Read-CgrWizardInput -Prompt 'Filter repositories by name' -AllowBack:$AllowBack -AllowCancel:$AllowCancel
                $filterNavigation = Resolve-CgrWizardNavigationInput -InputText $filterInput -AllowBack:$AllowBack -AllowCancel:$AllowCancel
                if ($null -ne $filterNavigation) { return $filterNavigation }
                $filter = $filterInput.Trim()
                $pageIndex = 0
                continue
            }
            'p' {
                if ($pageIndex -gt 0) { $pageIndex-- }
                continue
            }
            'n' {
                if ($pageIndex -lt ($pageCount - 1)) { $pageIndex++ }
                continue
            }
        }

        $choiceNumber = 0
        if ([int]::TryParse($inputText, [ref] $choiceNumber) -and $choiceNumber -ge 1 -and $choiceNumber -le $pageRepositories.Count) {
            return ConvertTo-CgrWizardNavigationResult -Action Next -Value $pageRepositories[$choiceNumber - 1]
        }

        Write-CgrWizardMessage -Message 'Enter a listed repository number or use one of the bracketed commands shown at the prompt.' -Style Hint
    }
}
