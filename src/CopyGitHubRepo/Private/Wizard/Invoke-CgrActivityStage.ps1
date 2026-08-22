function Invoke-CgrActivityStage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Name,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Message,

        [Parameter(Mandatory)]
        [scriptblock] $Action
    )

    Send-CgrActivityEvent -Name $Name -State Started -Message $Message
    try {
        $result = & $Action
        $completedMessage = Get-CgrActivityCompletionMessage -Name $Name -DefaultMessage $Message -Result $result
        $terminalState = Get-CgrActivityTerminalState -Name $Name -Result $result
        Send-CgrActivityEvent -Name $Name -State $terminalState -Message $completedMessage
        return $result
    }
    catch {
        Send-CgrActivityEvent -Name $Name -State Failed -Message $Message
        throw
    }
}
