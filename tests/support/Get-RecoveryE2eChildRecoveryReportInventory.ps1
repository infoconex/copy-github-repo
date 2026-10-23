function Get-RecoveryE2eChildRecoveryReportInventory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Directory,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $FilePattern,

        [string[]] $PreviouslyObservedPaths = @()
    )

    # Always return one result object, including when zero or one report exists.
    # PowerShell may unwrap a single FileInfo assigned from an if statement;
    # a stable count and array property prevent a strict-mode evidence failure.
    $newFiles = @()
    if (Test-Path -LiteralPath $Directory -PathType Container) {
        $newFiles = @(
            Get-ChildItem -LiteralPath $Directory -File -Filter $FilePattern -ErrorAction Stop |
                Where-Object { $_.FullName -cnotin $PreviouslyObservedPaths }
        )
    }

    [pscustomobject] @{
        Files = @($newFiles)
        Count = $newFiles.Count
    }
}
