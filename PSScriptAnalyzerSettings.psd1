@{
    Severity = @('Error', 'Warning')
    IncludeDefaultRules = $true
    CustomRulePath = @(
        './build/PSScriptAnalyzerRules/CopyGitHubRepo.AnalyzerRules.psm1'
    )
    IncludeRules = @(
        '*'
    )
    Rules = @{
        PSAvoidExclaimOperator = @{
            Enable = $true
        }

        PSUseConsistentWhitespace = @{
            Enable = $true
            CheckInnerBrace = $true
            CheckOpenBrace = $true
            CheckOpenParen = $false
            CheckOperator = $true
            CheckPipe = $true
            CheckPipeForRedundantWhitespace = $false
            CheckSeparator = $true
            CheckParameter = $false
            IgnoreAssignmentOperatorInsideHashTable = $false
        }
    }
}
