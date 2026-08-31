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
        $script:layout | Should -Match 'class="brand__image"[^>]+width="64"[^>]+height="64"[^>]+alt=""'
        $script:layout | Should -Match 'aria-current="page"'
    }

    It 'protects a valid combobox and listbox search accessibility pattern' {
        $script:layout | Should -Match 'id="site-search-input"[^>]+role="combobox"'
        $script:layout | Should -Match 'aria-autocomplete="list"'
        $script:layout | Should -Match 'aria-haspopup="listbox"'
        $script:layout | Should -Match 'aria-controls="site-search-results"'
        $script:layout | Should -Match 'id="site-search-results"[^>]+role="listbox"'
        $script:layout | Should -Match 'id="site-search-status"[^>]+role="status"'
        $script:siteJs | Should -Match "setAttribute\('aria-activedescendant'"
        $script:siteJs | Should -Match "setAttribute\('aria-selected'"
        $script:siteJs | Should -Match "setAttribute\('role', 'option'\)"
        $script:siteJs | Should -Match "removeAttribute\('aria-activedescendant'\)"
        $script:layoutCss | Should -Match '\.site-search__empty\{[^}]*padding:'
    }

    It 'protects visible focus, responsive overflow, and reduced-motion behavior' {
        $script:siteCss | Should -Match ':focus-visible\s*\{[^}]*outline:'
        $script:siteCss | Should -Match '\.skip-link:focus\s*\{[^}]*transform:'
        $script:siteCss | Should -Match 'overflow-x:auto'
        $script:siteCss | Should -Match '@media\s*\(prefers-reduced-motion:reduce\)'
        $script:layoutCss | Should -Match '@media\(prefers-reduced-motion:reduce\)'
        $script:layoutCss | Should -Match '@media\(max-width:900px\)\{\.brand__text span\{display:none\}\}'
        $script:layoutCss | Should -Match '@media\(max-width:760px\)\{\.brand__text\{display:none\}\}'
        $script:siteJs | Should -Match 'prefers-reduced-motion: reduce'
        $script:siteJs | Should -Match "behavior: reduceMotion \? 'auto' : 'smooth'"
    }

    It 'protects keyboard handling and transient-control state' {
        $script:siteJs | Should -Match "event\.key === 'Escape'"
        $script:siteJs | Should -Match "event\.key === 'Tab'"
        $script:siteJs | Should -Match "event\.key === 'ArrowDown'"
        $script:siteJs | Should -Match "event\.key === 'ArrowUp'"
        $script:siteJs | Should -Match "event\.key === 'Enter'"
        $script:siteJs | Should -Match 'getNavigationFocusables'
        $script:siteJs | Should -Match "sidebar\?\.querySelector\('\.docs-nav a\.is-active'\)"
        $script:siteJs | Should -Match 'last\.focus\(\)'
        $script:siteJs | Should -Match 'first\.focus\(\)'
        $script:siteJs | Should -Match "aria-label', isOpen \? 'Close navigation' : 'Open navigation'"
        $script:siteJs | Should -Match 'backToTop\.hidden = !visible'
        $script:layout | Should -Match 'class="back-to-top"[^>]+hidden'
    }

    It 'keeps supplemental diagram rendering out of the accessibility tree' {
        $script:layout | Should -Match "mermaidBlock\.setAttribute\('aria-hidden', 'true'\)"
        $script:layout | Should -Match 'aria-label.*View diagram full screen'
        $script:siteJs | Should -Match 'aria-label.*Reset diagram view'
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
