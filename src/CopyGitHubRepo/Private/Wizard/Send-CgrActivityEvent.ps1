function Send-CgrActivityEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Name,

        [Parameter(Mandatory)]
        [ValidateSet('Started', 'Progress', 'Completed', 'Info', 'Warning', 'Failed')]
        [string] $State,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Message,

        [Nullable[int]] $Current,

        [Nullable[int]] $Total
    )

    $sinkVariable = Get-Variable -Name CgrActivitySink -Scope Script -ErrorAction SilentlyContinue
    if ($null -eq $sinkVariable -or $null -eq $sinkVariable.Value) {
        return
    }

    $activityEvent = [pscustomobject] @{
        PSTypeName = 'CopyGitHubRepo.ActivityEvent'
        Name = $Name
        State = $State
        Message = $Message
        Timestamp = [DateTimeOffset]::UtcNow
        Current = $Current
        Total = $Total
    }

    & $sinkVariable.Value $activityEvent | Out-Null
}
