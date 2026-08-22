function Get-CgrGitCommitIdentity {
    [CmdletBinding()]
    param(
        [ValidateNotNullOrEmpty()]
        [string] $HostName = 'github.com'
    )

    $name = $null
    $email = $null

    try {
        $nameResult = Invoke-CgrNativeCommand `
            -FilePath 'git' `
            -ArgumentList @('config', '--get', 'user.name')
        if ($nameResult.ExitCode -eq 0 -and @($nameResult.Output).Count -gt 0) {
            $name = [string] @($nameResult.Output)[0]
        }
    }
    catch {
        $name = $null
    }

    try {
        $emailResult = Invoke-CgrNativeCommand `
            -FilePath 'git' `
            -ArgumentList @('config', '--get', 'user.email')
        if ($emailResult.ExitCode -eq 0 -and @($emailResult.Output).Count -gt 0) {
            $email = [string] @($emailResult.Output)[0]
        }
    }
    catch {
        $email = $null
    }

    if (-not [string]::IsNullOrWhiteSpace($name) -and
        -not [string]::IsNullOrWhiteSpace($email)) {
        return [pscustomobject] @{
            PSTypeName = 'CopyGitHubRepo.GitCommitIdentity'
            Name = $name.Trim()
            Email = $email.Trim()
            Source = 'GitConfig'
        }
    }

    try {
        $userResult = Invoke-CgrNativeCommand `
            -FilePath 'gh' `
            -ArgumentList @('api', '--hostname', $HostName, 'user')
    }
    catch {
        $userResult = $null
    }

    if ($null -ne $userResult -and $userResult.ExitCode -eq 0) {
        $userJson = ($userResult.Output | Out-String).Trim()
        if (-not [string]::IsNullOrWhiteSpace($userJson)) {
            $user = $userJson | ConvertFrom-Json -Depth 20
            $login = [string] $user.login

            if (-not [string]::IsNullOrWhiteSpace($login)) {
                if ([string]::IsNullOrWhiteSpace($name)) {
                    $name = if (-not [string]::IsNullOrWhiteSpace([string] $user.name)) {
                        [string] $user.name
                    }
                    else {
                        $login
                    }
                }

                if ([string]::IsNullOrWhiteSpace($email)) {
                    if (-not [string]::IsNullOrWhiteSpace([string] $user.email)) {
                        $email = [string] $user.email
                    }
                    elseif ($null -ne $user.id -and [string] $user.id -ne '') {
                        $email = '{0}+{1}@users.noreply.github.com' -f $user.id, $login
                    }
                    else {
                        $email = '{0}@users.noreply.github.com' -f $login
                    }
                }

                return [pscustomobject] @{
                    PSTypeName = 'CopyGitHubRepo.GitCommitIdentity'
                    Name = $name.Trim()
                    Email = $email.Trim()
                    Source = 'GitHubCLI'
                }
            }
        }
    }

    $localUser = [Environment]::UserName
    if (-not [string]::IsNullOrWhiteSpace($localUser)) {
        return [pscustomobject] @{
            PSTypeName = 'CopyGitHubRepo.GitCommitIdentity'
            Name = $localUser
            Email = '{0}@localhost' -f $localUser
            Source = 'LocalUser'
        }
    }

    $message = "Unable to determine a Git commit identity. Configure git user.name and user.email, or authenticate GitHub CLI for '$HostName'."
    $exception = [System.InvalidOperationException]::new($message)
    $errorRecord = [System.Management.Automation.ErrorRecord]::new(
        $exception,
        'GitCommitIdentityUnavailable',
        [System.Management.Automation.ErrorCategory]::InvalidData,
        $HostName
    )
    $PSCmdlet.ThrowTerminatingError($errorRecord)
}
