function New-CgrWizardActivitySink {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'This presentation factory initializes in-memory renderer state and returns a scriptblock; it does not mutate GitHub or external state.'
    )]
    [CmdletBinding()]
    param()

    $script:CgrWizardActivityPresentationState = [pscustomobject] @{
        Interactive = Test-CgrInteractiveTerminal
        StartedAt = @{}
        SpinnerFrames = @('|', '/', '-', '\')
        SpinnerIndex = 0
        ProgressId = 417
    }

    return {
        param([psobject] $ActivityEvent)
        Write-CgrWizardActivityEvent -ActivityEvent $ActivityEvent
    }
}
