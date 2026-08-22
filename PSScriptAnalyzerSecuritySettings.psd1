@{
    Severity = @('Error', 'Warning')
    IncludeDefaultRules = $false
    CustomRulePath = @(
        './build/PSScriptAnalyzerRules/CopyGitHubRepo.AnalyzerRules.psm1'
    )
    IncludeRules = @(
        'Measure-CgrSecurity'
        'PSAvoidUsingConvertToSecureStringWithPlainText'
        'PSAvoidUsingInvokeExpression'
        'PSAvoidUsingPlainTextForPassword'
        'PSAvoidUsingUsernameAndPasswordParams'
    )
}
