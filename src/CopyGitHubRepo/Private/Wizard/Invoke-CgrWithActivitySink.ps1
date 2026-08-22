function Invoke-CgrWithActivitySink {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [scriptblock] $Sink,

        [Parameter(Mandatory)]
        [scriptblock] $Action
    )

    $previous = Get-Variable -Name CgrActivitySink -Scope Script -ErrorAction SilentlyContinue
    try {
        Set-Variable -Name CgrActivitySink -Scope Script -Value $Sink
        & $Action
    }
    finally {
        if ($null -ne $previous) {
            Set-Variable -Name CgrActivitySink -Scope Script -Value $previous.Value
        }
        else {
            Remove-Variable -Name CgrActivitySink -Scope Script -ErrorAction SilentlyContinue
        }
    }
}
