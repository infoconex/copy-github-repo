function Write-CgrWizardActivityEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject] $ActivityEvent
    )

    $state = $script:CgrWizardActivityPresentationState
    if ($null -eq $state) {
        return
    }

    if ($ActivityEvent.State -eq 'Started') {
        $state.StartedAt[$ActivityEvent.Name] = $ActivityEvent.Timestamp
        if ($state.Interactive) {
            $frame = $state.SpinnerFrames[$state.SpinnerIndex % $state.SpinnerFrames.Count]
            $state.SpinnerIndex++
            Write-Progress -Id $state.ProgressId -Activity 'Repository copy' -Status ('{0} {1}' -f $frame, $ActivityEvent.Message)
        }
        else {
            Write-CgrWizardMessage -Message $ActivityEvent.Message -Status Info
        }
        return
    }

    if ($ActivityEvent.State -eq 'Progress') {
        if ($state.Interactive) {
            $hasMeasure = $null -ne $ActivityEvent.Current -and $null -ne $ActivityEvent.Total -and $ActivityEvent.Total -gt 0
            if ($hasMeasure) {
                $percent = [Math]::Min(100, [Math]::Max(0, [int] [Math]::Floor(($ActivityEvent.Current / $ActivityEvent.Total) * 100)))
                Write-Progress -Id $state.ProgressId -Activity 'Repository copy' -Status $ActivityEvent.Message -PercentComplete $percent
            }
            else {
                $frame = $state.SpinnerFrames[$state.SpinnerIndex % $state.SpinnerFrames.Count]
                $state.SpinnerIndex++
                Write-Progress -Id $state.ProgressId -Activity 'Repository copy' -Status ('{0} {1}' -f $frame, $ActivityEvent.Message)
            }
        }
        return
    }

    if ($state.Interactive) {
        Write-Progress -Id $state.ProgressId -Activity 'Repository copy' -Completed
    }

    $elapsedSuffix = ''
    if ($state.StartedAt.ContainsKey($ActivityEvent.Name)) {
        $elapsed = $ActivityEvent.Timestamp - $state.StartedAt[$ActivityEvent.Name]
        $elapsedSuffix = ' ({0:N1}s)' -f [Math]::Max(0, $elapsed.TotalSeconds)
        $state.StartedAt.Remove($ActivityEvent.Name)
    }

    $message = '{0}{1}' -f $ActivityEvent.Message, $elapsedSuffix
    switch ($ActivityEvent.State) {
        'Completed' {
            Write-CgrWizardMessage -Message $message -Status Success
        }
        'Info' {
            Write-CgrWizardMessage -Message $message -Status Info
        }
        'Warning' {
            Write-CgrWizardMessage -Message $message -Status Warning
        }
        'Failed' {
            Write-CgrWizardMessage -Message $message -Status Error
        }
    }
}
