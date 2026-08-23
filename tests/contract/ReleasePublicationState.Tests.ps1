BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:releaseWorkflowPath = Join-Path $repositoryRoot '.github/workflows/publish-release.yml'
    $script:releaseWorkflow = (Get-Content -LiteralPath $script:releaseWorkflowPath -Raw) -replace "`r`n?", "`n"
}

Describe 'Stable release publication state probes' {
    It 'treats GitHub release absence as an explicit HTTP 404 state instead of a native command failure' {
        $releaseProbeStart = $script:releaseWorkflow.IndexOf('- name: Reject duplicate GitHub release', [StringComparison]::Ordinal)
        $tagProbeStart = $script:releaseWorkflow.IndexOf('- name: Ensure manual release tag', [StringComparison]::Ordinal)
        $releaseProbe = $script:releaseWorkflow.Substring($releaseProbeStart, $tagProbeStart - $releaseProbeStart)

        $releaseProbe | Should -Match 'Invoke-WebRequest'
        $releaseProbe | Should -Match '-SkipHttpErrorCheck'
        $releaseProbe | Should -Match 'switch \(\[int\] \$response\.StatusCode\)'
        $releaseProbe | Should -Match '(?ms)200 \{.*Stable GitHub release.*already exists'
        $releaseProbe | Should -Match '(?ms)404 \{.*publication may proceed'
        $releaseProbe | Should -Match '(?ms)default \{.*Unable to determine whether stable GitHub release.*Publication stopped'
        $releaseProbe | Should -Not -Match 'gh release view'
    }

    It 'treats tag absence as an explicit HTTP 404 state and fails closed on unexpected lookup status' {
        $tagProbeStart = $script:releaseWorkflow.IndexOf('- name: Ensure manual release tag', [StringComparison]::Ordinal)
        $galleryPublishStart = $script:releaseWorkflow.IndexOf('- name: Publish PowerShell Gallery package', [StringComparison]::Ordinal)
        $tagProbe = $script:releaseWorkflow.Substring($tagProbeStart, $galleryPublishStart - $tagProbeStart)

        $tagProbe | Should -Match 'Invoke-WebRequest'
        $tagProbe | Should -Match '-SkipHttpErrorCheck'
        $tagProbe | Should -Match 'switch \(\[int\] \$tagResponse\.StatusCode\)'
        $tagProbe | Should -Match '(?ms)200 \{.*Existing tag.*approved release commit'
        $tagProbe | Should -Match '(?ms)404 \{.*creating it for approved release commit'
        $tagProbe | Should -Match '(?ms)default \{.*Unable to determine whether tag.*Publication stopped'
        $tagProbe | Should -Not -Match '& gh api "repos/\$\{\{ github\.repository \}\}/git/ref/tags/\$tag" 1>\$null 2>\$null'
    }

    It 'verifies both an existing tag and a newly created tag resolve to the exact approved commit' {
        $script:releaseWorkflow | Should -Match 'Existing tag.*does not resolve to approved release commit'
        $script:releaseWorkflow | Should -Match 'Created tag.*did not resolve back to approved release commit'
        $script:releaseWorkflow | Should -Match '(?ms)\$commitResponse\.StatusCode -ne 200.*Publication stopped'
        $script:releaseWorkflow | Should -Match '\$createdCommitResponse\.StatusCode -ne 200'
        $script:releaseWorkflow | Should -Match '\$existingCommit -cne \$expectedCommit'
        $script:releaseWorkflow | Should -Match '\$createdCommit -cne \$expectedCommit'
    }

    It 'uses authenticated versioned GitHub API requests for read-only publication-state decisions' {
        $script:releaseWorkflow | Should -Match 'Authorization = "Bearer \$env:GH_TOKEN"'
        $script:releaseWorkflow | Should -Match "Accept = 'application/vnd\.github\+json'"
        $script:releaseWorkflow | Should -Match "'X-GitHub-Api-Version' = '2022-11-28'"
        $script:releaseWorkflow | Should -Match 'https://api\.github\.com/repos/\$\{\{ github\.repository \}\}/releases/tags/\$tag'
        $script:releaseWorkflow | Should -Match 'https://api\.github\.com/repos/\$\{\{ github\.repository \}\}/git/ref/tags/\$tag'
    }
}
