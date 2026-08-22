Set-StrictMode -Version Latest

$script:RepositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$script:PolicyPath = Join-Path $script:RepositoryRoot 'tests/SourceDocumentationPolicy.psd1'
$script:DocumentationPath = Join-Path $script:RepositoryRoot 'docs/engineering/source-code-documentation.md'
$script:Policy = Import-PowerShellDataFile -LiteralPath $script:PolicyPath
$script:Documentation = Get-Content -LiteralPath $script:DocumentationPath -Raw

function ConvertTo-CgrAnalyzerDiagnostic {
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Language.IScriptExtent] $Extent,

        [Parameter(Mandatory)]
        [string] $RuleName,

        [Parameter(Mandatory)]
        [string] $Message
    )

    [Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord]@{
        Message = $Message
        Extent = $Extent
        RuleName = $RuleName
        Severity = 'Warning'
    }
}

function ConvertTo-CgrDocumentationDiagnostic {
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Language.IScriptExtent] $Extent,

        [Parameter(Mandatory)]
        [string] $Message
    )

    ConvertTo-CgrAnalyzerDiagnostic -Extent $Extent -RuleName 'Measure-CgrDocumentation' -Message $Message
}

function Test-CgrCommentBasedHelp {
    param(
        [Parameter(Mandatory)]
        [string] $Source
    )

    $Source -match '(?ms)<#.*?\.SYNOPSIS\b.+?\.DESCRIPTION\b.+?#>'
}

function Test-CgrSecurityAnalyzedPath {
    param(
        [Parameter(Mandatory)]
        [string] $RelativePath
    )

    $RelativePath -match '^src/CopyGitHubRepo/[^/]+\.ps.*$' -or
    $RelativePath -match '^src/CopyGitHubRepo/Public/[^/]+\.ps1$' -or
    $RelativePath -match '^src/CopyGitHubRepo/Private/[^/]+/[^/]+\.ps1$' -or
    $RelativePath -match '^build/[^/]+\.ps1$' -or
    ($RelativePath -notmatch '/' -and $RelativePath -like '*.ps1')
}

function Measure-CgrDocumentation {
    <#
    .SYNOPSIS
    Enforces CopyGitHubRepo source-documentation requirements during static analysis.

    .DESCRIPTION
    Reports missing public or safety-boundary comment-based help and missing
    maintainer-catalog documentation for private functions and operational scripts.
    The rule intentionally mirrors the repository documentation policy so local
    PSScriptAnalyzer runs surface documentation omissions before the deeper Pester
    contract tests execute.

    .INPUTS
    System.Management.Automation.Language.ScriptBlockAst

    .OUTPUTS
    Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord[]
    #>
    [OutputType([Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord[]])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [System.Management.Automation.Language.ScriptBlockAst] $ScriptBlockAst
    )

    if ($null -ne $ScriptBlockAst.Parent) {
        return
    }

    $filePath = $ScriptBlockAst.Extent.File
    if ([string]::IsNullOrWhiteSpace($filePath)) {
        return
    }

    $relativePath = [System.IO.Path]::GetRelativePath($script:RepositoryRoot, $filePath).Replace('\', '/')
    $functionAsts = @($ScriptBlockAst.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
            }, $true))

    if ($relativePath -like 'src/CopyGitHubRepo/Public/*.ps1') {
        foreach ($functionAst in $functionAsts) {
            if (-not (Test-CgrCommentBasedHelp -Source $functionAst.Extent.Text)) {
                ConvertTo-CgrDocumentationDiagnostic -Extent $functionAst.Extent -Message "Public function '$($functionAst.Name)' requires comment-based help with .SYNOPSIS and .DESCRIPTION."
            }
        }
    }

    if ($relativePath -match '^src/CopyGitHubRepo/Private/[^/]+/[^/]+\.ps1$') {
        foreach ($functionAst in $functionAsts) {
            if ($script:Documentation -notmatch [regex]::Escape("``$($functionAst.Name)``")) {
                ConvertTo-CgrDocumentationDiagnostic -Extent $functionAst.Extent -Message "Private function '$($functionAst.Name)' must be documented in docs/engineering/source-code-documentation.md."
            }

            if ($functionAst.Name -in @($script:Policy.InlinePrivateHelpRequired) -and
                -not (Test-CgrCommentBasedHelp -Source $functionAst.Extent.Text)) {
                ConvertTo-CgrDocumentationDiagnostic -Extent $functionAst.Extent -Message "Safety/planning boundary '$($functionAst.Name)' requires inline comment-based help with .SYNOPSIS and .DESCRIPTION."
            }
        }
    }

    $isRootScript = $relativePath -notmatch '/' -and $relativePath -like '*.ps1'
    $isBuildScript = $relativePath -match '^build/[^/]+\.ps1$'
    $isEndToEndScript = $relativePath -match '^tests/e2e/[^/]+\.ps1$'
    if ($isRootScript -or $isBuildScript -or $isEndToEndScript) {
        if ($relativePath -notin @($script:Policy.OperationalScripts)) {
            ConvertTo-CgrDocumentationDiagnostic -Extent $ScriptBlockAst.Extent -Message "Operational script '$relativePath' must be classified in tests/SourceDocumentationPolicy.psd1."
        }
        elseif ($script:Documentation -notmatch [regex]::Escape("``$relativePath``")) {
            ConvertTo-CgrDocumentationDiagnostic -Extent $ScriptBlockAst.Extent -Message "Operational script '$relativePath' must be documented in docs/engineering/source-code-documentation.md."
        }
    }
}

function Measure-CgrSecurity {
    <#
    .SYNOPSIS
    Detects high-signal PowerShell security regressions in production and operational code.

    .DESCRIPTION
    Enforces architecture-specific security boundaries that are difficult to express with
    default PSScriptAnalyzer rules. The rule rejects dynamic evaluation, explicit shell
    interpretation, direct Git/GitHub native execution outside the centralized wrapper,
    and obvious emission of secret-bearing variables to diagnostic/output commands.

    The rule is intentionally narrow. It supplements code review, Pester security
    contracts, threat modeling, and future scanning; it is not a claim of comprehensive
    static application security testing.

    .INPUTS
    System.Management.Automation.Language.ScriptBlockAst

    .OUTPUTS
    Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord[]
    #>
    [OutputType([Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord[]])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [System.Management.Automation.Language.ScriptBlockAst] $ScriptBlockAst
    )

    if ($null -ne $ScriptBlockAst.Parent) {
        return
    }

    $filePath = $ScriptBlockAst.Extent.File
    if ([string]::IsNullOrWhiteSpace($filePath)) {
        return
    }

    $relativePath = [System.IO.Path]::GetRelativePath($script:RepositoryRoot, $filePath).Replace('\', '/')
    if (-not (Test-CgrSecurityAnalyzedPath -RelativePath $relativePath)) {
        return
    }

    $commandAsts = @($ScriptBlockAst.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.CommandAst]
            }, $true))

    foreach ($commandAst in $commandAsts) {
        $commandName = $commandAst.GetCommandName()
        if ([string]::IsNullOrWhiteSpace($commandName)) {
            continue
        }

        $normalizedCommand = $commandName.ToLowerInvariant()
        if ($normalizedCommand -in @('invoke-expression', 'iex')) {
            ConvertTo-CgrAnalyzerDiagnostic `
                -Extent $commandAst.Extent `
                -RuleName 'Measure-CgrSecurity' `
                -Message 'Dynamic expression evaluation is prohibited. Use parsed/typed data and explicit command invocation instead.'
            continue
        }

        $commandText = $commandAst.Extent.Text
        if (($normalizedCommand -in @('cmd', 'cmd.exe') -and $commandText -match '(?i)(?:^|\s)/c(?:\s|$)') -or
            ($normalizedCommand -in @('sh', 'bash', 'zsh') -and $commandText -match '(?:^|\s)-c(?:\s|$)')) {
            ConvertTo-CgrAnalyzerDiagnostic `
                -Extent $commandAst.Extent `
                -RuleName 'Measure-CgrSecurity' `
                -Message "Shell interpretation through '$commandName' is prohibited. Use Invoke-CgrNativeCommand with discrete arguments."
            continue
        }

        if ($relativePath -match '^src/CopyGitHubRepo/' -and
            $relativePath -ne 'src/CopyGitHubRepo/Private/Git/Invoke-CgrNativeCommand.ps1' -and
            $normalizedCommand -in @('git', 'git.exe', 'gh', 'gh.exe', 'git-lfs', 'git-lfs.exe')) {
            ConvertTo-CgrAnalyzerDiagnostic `
                -Extent $commandAst.Extent `
                -RuleName 'Measure-CgrSecurity' `
                -Message "Direct native invocation of '$commandName' bypasses the centralized process boundary. Route native execution through Invoke-CgrNativeCommand or its approved adapter."
            continue
        }

        if ($normalizedCommand -in @(
                'write-output',
                'write-host',
                'write-verbose',
                'write-debug',
                'write-warning',
                'write-error',
                'write-information'
            )) {
            $sensitiveVariables = @($commandAst.FindAll({
                        param($node)
                        if ($node -isnot [System.Management.Automation.Language.VariableExpressionAst]) {
                            return $false
                        }

                        $node.VariablePath.UserPath -match '(?i)(token|password|secret|credential|privatekey|api[_-]?key|auth(?:entication|orization)?)'
                    }, $true))

            if ($sensitiveVariables.Count -gt 0) {
                $variableNames = @($sensitiveVariables | ForEach-Object { '$' + $_.VariablePath.UserPath } | Sort-Object -Unique)
                ConvertTo-CgrAnalyzerDiagnostic `
                    -Extent $commandAst.Extent `
                    -RuleName 'Measure-CgrSecurity' `
                    -Message "Potential secret-bearing variable(s) $($variableNames -join ', ') must not be written directly to output or diagnostics. Redact or emit non-sensitive status instead."
            }
        }
    }
}

Export-ModuleMember -Function Measure-CgrDocumentation, Measure-CgrSecurity
