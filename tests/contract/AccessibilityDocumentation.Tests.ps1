BeforeAll {
    $script:repositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:accessibilityPath = Join-Path $script:repositoryRoot 'docs/product/accessibility.md'
    $script:layoutPath = Join-Path $script:repositoryRoot '_layouts/default.html'
    $script:siteCssPath = Join-Path $script:repositoryRoot 'assets/css/site.css'
    $script:layoutCssPath = Join-Path $script:repositoryRoot 'assets/css/site-layout.css'
    $script:siteJsPath = Join-Path $script:repositoryRoot 'assets/js/site.js'
    $script:contributingPath = Join-Path $script:repositoryRoot 'CONTRIBUTING.md'

    $script:accessibility = Get-Content -LiteralPath $script:accessibilityPath -Raw
    $script:layout = Get-Content -LiteralPath $script:layoutPath -Raw
    $script:siteCss = Get-Content -LiteralPath $script:siteCssPath -Raw
    $script:layoutCss = Get-Content -LiteralPath $script:layoutCssPath -Raw
    $script:siteJs = Get-Content -LiteralPath $script:siteJsPath -Raw
    $script:contributing = Get-Content -LiteralPath $script:contributingPath -Raw
}

Describe 'Accessibility documentation and site contract' {
    It 'defines a precise accessibility evidence boundary without claiming certification' {
        $script:accessibility | Should -Match 'not a certification'
        $script:accessibility | Should -Match 'Automatically verified'
        $script:accessibility | Should -Match 'Manual review required'
        $script:accessibility | Should -Match 'does not claim independent accessibility assessment, formal accessibility certification, or regulatory compliance'
    }

    It 'requires console meaning to remain available without styling or color' {
        foreach ($label in @('PASS', 'SUCCESS', 'FAIL', 'ERROR', 'WARN', 'INFO')) {
            $script:accessibility | Should -Match ([regex]::Escape($label))
        }

        $script:accessibility | Should -Match 'NO_COLOR'
        $script:accessibility | Should -Match 'plain text'
        $script:accessibility | Should -Match 'Keyboard-only operation'
        $script:accessibility | Should -Match 'non-interactive'
        $script:accessibility | Should -Match 'Width and wrapping'
    }

    It 'keeps the core site landmarks and controls semantically labeled' {
        $script:layout | Should -Match '<html lang="en">'
        $script:layout | Should -Match 'class="skip-link" href="#main-content"'
        $script:layout | Should -Match '<main class="content-wrap" id="main-content">'
        $script:layout | Should -Match 'aria-label="Documentation navigation"'
        $script:layout | Should -Match 'aria-label="Repository links"'
        $script:layout | Should -Match 'aria-label="Back to top"'
        $script:layout | Should -Match 'aria-label="Choose site theme"'
        $script:layout | Should -Match 'class="brand__image"[^>]+alt=""'
    }

    It 'protects visible focus, responsive overflow, and reduced-motion behavior' {
        $script:siteCss | Should -Match ':focus-visible\s*\{[^}]*outline:'
        $script:siteCss | Should -Match '\.skip-link:focus\s*\{[^}]*transform:'
        $script:siteCss | Should -Match 'overflow-x:auto'
        $script:siteCss | Should -Match '@media\s*\(prefers-reduced-motion:reduce\)'
        $script:layoutCss | Should -Match '@media\(prefers-reduced-motion:reduce\)'
    }

    It 'protects keyboard handling for transient navigation and documentation search' {
        $script:siteJs | Should -Match "event\.key === 'Escape'"
        $script:siteJs | Should -Match "event\.key === 'ArrowDown'"
        $script:siteJs | Should -Match "event\.key === 'ArrowUp'"
        $script:siteJs | Should -Match "event\.key === 'Enter'"
        $script:layout | Should -Match 'role="listbox"'
        $script:siteJs | Should -Match "setAttribute\('role', 'option'\)"
    }

    It 'defines image, diagram, link, contrast, and responsive authoring expectations' {
        $script:accessibility | Should -Match 'Informative Markdown images must have meaningful alternative text'
        $script:accessibility | Should -Match 'Mermaid diagrams must have nearby prose'
        $script:accessibility | Should -Match 'Link text should identify its destination or purpose'
        $script:accessibility | Should -Match 'Contrast in all themes is a manual review requirement'
        $script:accessibility | Should -Match 'Tables and code blocks allow horizontal overflow'
    }

    It 'makes accessibility part of contributor change impact' {
        $script:accessibility | Should -Match 'Contributor change-impact guidance'
        $script:accessibility | Should -Match 'Theme/color token'
        $script:contributing | Should -Match 'accessibility'
    }
}
