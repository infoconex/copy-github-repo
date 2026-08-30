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

        PSAvoidSemicolonsAsLineTerminators = @{
            Enable = $true
        }

        PSPlaceOpenBrace = @{
            Enable = $true
            OnSameLine = $true
            NewLineAfter = $true
            IgnoreOneLineBlock = $true
        }

        PSPlaceCloseBrace = @{
            Enable = $true
            NoEmptyLineBefore = $true
            IgnoreOneLineBlock = $true
            NewLineAfter = $true
        }

        PSUseConsistentIndentation = @{
            Enable = $true
            Kind = 'space'
            IndentationSize = 4
            PipelineIndentation = 'IncreaseIndentationForFirstPipeline'
        }

        PSUseConsistentWhitespace = @{
            Enable = $true
            CheckInnerBrace = $true
            CheckOpenBrace = $true
            CheckOpenParen = $true
            CheckOperator = $true
            CheckPipe = $true
            CheckPipeForRedundantWhitespace = $true
            CheckSeparator = $true
            CheckParameter = $true
            IgnoreAssignmentOperatorInsideHashTable = $false
        }

        PSUseConsistentParameterSetName = @{
            Enable = $true
        }

        PSUseConsistentParametersKind = @{
            Enable = $true
            ParametersKind = 'ParamBlock'
        }

        PSUseSingleValueFromPipelineParameter = @{
            Enable = $true
        }

        PSUseCorrectCasing = @{
            Enable = $true
            CheckCommands = $false
            CheckKeyword = $true
            CheckOperator = $true
        }

        PSAvoidUsingDoubleQuotesForConstantString = @{
            Enable = $true
        }
    }
}
