BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:uninstallContent = Get-Content -LiteralPath (Join-Path $repositoryRoot 'uninstall.ps1') -Raw
}

Describe 'Remote uninstall bootstrap compatibility' {
    It 'keeps caller-scope wrapper parameters free of value validation' {
        $script:uninstallContent | Should -Match "\[Alias\('Version'\)\]"
        $script:uninstallContent | Should -Match '\[string\]\s+\$CgrUninstallVersion'
        $script:uninstallContent | Should -Match "\[Alias\('AllVersions'\)\]"
        $script:uninstallContent | Should -Match "\[Alias\('DestinationRoot'\)\]"
    }

    It 'keeps Version validation inside the isolated advanced function' {
        $script:uninstallContent | Should -Match 'function Invoke-CgrUninstall'
        $script:uninstallContent | Should -Match "\[ValidatePattern\('\^\\d\+\\\.\\d\+\\\.\\d\+\(\?:\\\.\\d\+\)\?\$'\)\]"
        $script:uninstallContent | Should -Match '\$_\.Version\s+-eq\s+\$Version'
    }

    It 'can be evaluated in caller scope when version variables already exist' {
        $probeContent = $script:uninstallContent -replace '(?m)^Invoke-CgrUninstall @cgrInvocationParameters\s*$', '$null = Get-Command Invoke-CgrUninstall'

        {
            & {
                foreach ($variableName in @('Version', 'RequestedVersion', 'CgrUninstallVersion')) {
                    New-Variable -Name $variableName -Value '' -Scope Local -Force
                }
                $null = Get-Variable -Name Version, RequestedVersion, CgrUninstallVersion -Scope Local
                $invokeExpressionCommand = Get-Command 'Invoke-Expression'
                & $invokeExpressionCommand $probeContent
            }
        } | Should -Not -Throw
    }
}
