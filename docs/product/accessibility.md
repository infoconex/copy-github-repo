---
title: "CopyGitHubRepo Accessibility Baseline – Console and Documentation"
description: "Review CopyGitHubRepo accessibility expectations for PowerShell console output, keyboard interaction, GitHub Pages semantics, focus, reduced motion, images, diagrams, and manual review."
---

# Accessibility baseline

This document defines the repository-owned accessibility expectations for Copy GitHub Repository across the PowerShell console experience and the published documentation site. It is a product and contribution baseline, not a certification or claim of conformance to a regulatory or accessibility standard.

Accessibility is treated as an observable quality property: important meaning must remain available without color, pointer-only interaction, animation, wide displays, or decorative symbols. Automated checks protect the parts the repository can evaluate deterministically; browser, assistive-technology, contrast, and usability review still require human judgment.

## Status vocabulary

Use these terms when describing accessibility evidence:

- **Implemented** — the repository contains the behavior or semantic structure.
- **Automatically verified** — a deterministic repository test protects the behavior or markup contract.
- **Manual review required** — meaningful validation depends on a browser, assistive technology, visual inspection, keyboard traversal, or human judgment.
- **Not claimed** — the project has not performed the evidence needed to make the stronger statement.

Automated checks are not a substitute for manual accessibility testing and do not establish legal or standards compliance.

## PowerShell console baseline

### Meaning must not depend on color

Console status output must remain understandable when styling is disabled. `Format-CgrConsoleStatus` emits a text label for every status (`PASS`, `SUCCESS`, `FAIL`, `ERROR`, `WARN`, or `INFO`) in addition to any symbol or color. Color and symbols are presentation enhancements; the label and message carry the meaning.

Styling is suppressed when:

- the `NO_COLOR` environment variable is set;
- PowerShell output rendering is configured as plain text; or
- console output is redirected or styling capability cannot be determined safely.

Tests in `tests/ConsolePresentation.Tests.ps1` protect the plain-text and `NO_COLOR` behavior.

### Symbols and Unicode

Check marks, cross marks, and bullets may improve scanning in capable terminals, but they must never be the only indication of status. Every status symbol is paired with an ASCII text label and explanatory message.

The current implementation uses a small set of Unicode status symbols in interactive presentation. The project does not claim that every legacy terminal renders those glyphs identically. A missing or substituted glyph must not remove the accompanying text meaning.

### Keyboard-only operation

The wizard is a console workflow based on text input and numbered/text choices. It does not require mouse or pointer input. Enter accepts documented defaults where available, and explicit text commands provide Help, Back, Cancel, filtering, and repository-list navigation where those actions are supported.

The authoritative interaction and navigation behavior is documented in [`wizard-contract.md`](wizard-contract.md) and [`wizard-navigation.md`](wizard-navigation.md). Pester suites covering wizard interaction, navigation, defaults, help, and cancellation provide automated evidence for those repository-owned behaviors.

### Plain-language prompts and errors

Prompts must expose their effective default in text. Choice lists identify the default option in text rather than by color or cursor position alone. Help returns the operator to the relevant prompt. Known application, validation, prerequisite, and safety conditions are presented as concise messages rather than raw PowerShell exception formatting.

Destructive replacement confirmation remains explicit and case-sensitive; accessibility changes must not weaken safety confirmation requirements.

### Interactive and non-interactive hosts

Interactive terminals may receive styling and in-place activity presentation. Redirected or non-interactive output must remain line-oriented and must not depend on cursor movement or ANSI styling for meaning. Structured public commands remain the preferred interface for automation; the wizard is the human-facing interface.

See [`wizard-activity.md`](wizard-activity.md) and [`wizard-presentation.md`](wizard-presentation.md) for the presentation contract.

### Width and wrapping

Console messages should be concise enough to remain usable in typical terminal widths. Correctness, safety meaning, defaults, and recovery instructions must not depend on fixed column alignment. Tables or decorative spacing must not be used where wrapping would separate a status from its meaning.

Narrow-terminal readability remains a human review item because host width, font metrics, line wrapping, and terminal behavior differ across environments.

## Documentation and GitHub Pages baseline

### Semantic structure and landmarks

The site layout provides:

- a declared page language;
- a keyboard-focusable skip link to the main content;
- semantic `header`, `nav`, `aside`, `main`, `article`, and `footer` regions where applicable;
- labels for navigation, search, theme selection, diagram controls, and back-to-top behavior; and
- a single documentation content region that preserves Markdown heading semantics.

Documentation authors must use headings hierarchically. A page should have one meaningful top-level heading and should not choose heading levels merely for visual size.

### Keyboard navigation and focus

All repository-owned interactive site controls must be reachable and usable from the keyboard. The site provides a visible `:focus-visible` outline, keyboard-operable native buttons/selects/links, Escape handling for transient navigation/search UI, and arrow/Enter navigation for search results.

Pointer interactions may supplement a control but must not be the sole way to reach critical information or perform an essential action. Diagram pan/zoom gestures are convenience interactions; the underlying documentation must provide equivalent explanatory text.

Keyboard traversal, focus order, focus visibility in each theme, mobile navigation behavior, and browser-specific behavior require manual review in addition to repository contract tests.

### Images and diagrams

Informative Markdown images must have meaningful alternative text. Decorative layout images may use an empty `alt` value when nearby visible text already names the product or purpose.

Mermaid diagrams must have nearby prose that communicates the material concept represented by the diagram. A diagram is supplemental visualization, not the sole source of a requirement, safety rule, architecture boundary, process step, or decision.

Automated validation can detect missing image alternative text and enforce repository-owned layout semantics, but it cannot determine whether a particular alternative or diagram explanation is sufficiently meaningful. That remains a review responsibility.

### Links

Link text should identify its destination or purpose when read out of context. Avoid generic link labels such as `click here`, `here`, or `read more` when a descriptive phrase is practical. Generated-site validation continues to verify that repository-local links and assets resolve.

### Color, contrast, and status meaning

Documentation meaning must not depend on color alone. Text, headings, labels, icons with accessible names, or other non-color cues must carry the important information.

The site defines light, dark, and sepia themes using centralized design tokens and provides visible keyboard focus. Contrast in all themes is a manual review requirement; repository tests may protect token/semantic contracts but do not claim to replace visual contrast evaluation in rendered browsers.

### Motion

The site honors `prefers-reduced-motion: reduce` by suppressing smooth scrolling and minimizing transitions/animations. Reading progress is decorative and is hidden from assistive technology.

### Responsive content

Images scale within their container. Tables and code blocks allow horizontal overflow rather than forcing the full page beyond the viewport, and the site has responsive layout rules for narrower screens.

Authors should keep tables purposeful, use concise column headings, and prefer prose or lists when a table becomes difficult to understand on a small viewport.

## Automated validation boundary

Repository validation should protect objectively testable accessibility contracts, including:

- console status labels remaining present without color;
- `NO_COLOR` and plain-text rendering paths;
- semantic site landmarks and control labels owned by the layout;
- skip-link and visible-focus CSS contracts;
- reduced-motion handling;
- keyboard search/navigation behavior that is implemented in repository JavaScript;
- non-empty alternative text for informative Markdown images;
- explicit decorative handling for repository-owned layout images; and
- contributor guidance that makes accessibility part of change impact.

The following are intentionally **manual review** items unless a future tool is adopted with a defensible deterministic signal:

- rendered color contrast across supported themes and browsers;
- screen-reader announcement quality and reading order;
- browser/OS high-contrast and zoom behavior;
- whether alternative text and diagram explanations are semantically sufficient;
- keyboard focus order and usability across complete pages;
- narrow-terminal wrapping under different host/font combinations; and
- cognitive clarity of prompts, recovery guidance, and dense documentation.

The project currently does not claim independent accessibility assessment, formal accessibility certification, or regulatory compliance.

## Contributor change-impact guidance

Accessibility review is required when a change modifies any of the following:

| Change area | Required accessibility review |
| --- | --- |
| Wizard prompt, choice, status, progress, warning, or error presentation | Verify meaning remains available in plain text, without color, and by keyboard-only interaction. |
| New status icon/symbol/color | Pair it with explicit text; test the no-style path. |
| Site layout, navigation, search, theme, dialog-like/transient UI, or JavaScript control | Verify semantic labeling, keyboard operation, focus behavior, Escape/close behavior where applicable, and reduced-motion implications. |
| Markdown image | Supply meaningful alt text unless the image is deliberately decorative and equivalent text is already present. |
| Mermaid/other diagram | Provide nearby prose containing the material information conveyed visually. |
| Table or large code block | Review narrow/mobile readability and preserve horizontal scrolling where needed. |
| Theme/color token | Review contrast and ensure no status/instruction meaning becomes color-only. |

Run `./build/Test-Project.ps1` for code/test/site implementation changes. Documentation-only changes may use `./build/Test-Documentation.ps1`, while published-site changes are additionally built and checked by the GitHub Pages workflow.

## Manual review checklist

Before a material console or site presentation release, a reviewer should sample the affected experience with:

1. color/styling disabled for console output;
2. keyboard-only wizard or site navigation;
3. a narrow terminal or browser viewport;
4. browser zoom and text enlargement;
5. reduced-motion preference enabled when motion-related behavior changed;
6. each affected site theme for visible focus and readable contrast; and
7. images/diagrams reviewed for equivalent text.

Record material limitations rather than describing an unperformed manual review as passed.

## Related authority

- Product behavior: [`product-contract.md`](product-contract.md)
- Wizard behavior: [`wizard-contract.md`](wizard-contract.md)
- Wizard navigation: [`wizard-navigation.md`](wizard-navigation.md)
- Wizard presentation: [`wizard-presentation.md`](wizard-presentation.md)
- Activity presentation: [`wizard-activity.md`](wizard-activity.md)
- Documentation ownership and validation: [`documentation-strategy.md`](../engineering/documentation-strategy.md)
- Maintainer change-impact process: [`maintainer-guide.md`](../engineering/maintainer-guide.md)
- Quality/evidence vocabulary: [`quality-strategy.md`](../engineering/quality-strategy.md)
- Non-functional boundaries: [`non-functional-requirements.md`](non-functional-requirements.md)
