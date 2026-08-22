@{
    Pester = @{
        Unit = 'tests/unit'
        Integration = 'tests/integration'
        Contract = 'tests/contract'
    }
    Infrastructure = @(
        'tests/TestTaxonomy.Tests.ps1'
    )
    EndToEnd = 'tests/e2e'
}
