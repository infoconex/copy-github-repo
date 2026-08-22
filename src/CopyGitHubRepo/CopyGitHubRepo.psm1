Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$privateFunctionPath = Join-Path $PSScriptRoot 'Private'
if (Test-Path -LiteralPath $privateFunctionPath) {
    Get-ChildItem -LiteralPath $privateFunctionPath -Filter '*.ps1' -File -Recurse |
        Sort-Object -Property FullName |
        ForEach-Object {
            . $_.FullName
        }
}

$publicFunctionPath = Join-Path $PSScriptRoot 'Public'
Get-ChildItem -LiteralPath $publicFunctionPath -Filter '*.ps1' -File |
    Sort-Object -Property Name |
    ForEach-Object {
        . $_.FullName
    }
