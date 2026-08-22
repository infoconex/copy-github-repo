# Wizard navigation

The guided wizard advertises every available navigation action directly in the prompt. Bracketed hints are presentation-only and use the same subdued styling as other secondary guidance.

The standard ordering is:

1. context actions such as `[F filter]`, `[L list]`, `[P previous]`, and `[N next]`;
2. `[? help]`;
3. `[B back]` when a prior step exists; and
4. `[C cancel]`.

Only the displayed short keys are navigation commands. `?` opens contextual help, `B` returns to the prior pre-execution step, `C` cancels without mutation, `F` filters a repository selector, `L` opens the reusable repository selector from the destination prompt, and `P`/`N` move between bounded repository pages when those pages exist. Enter accepts the trailing displayed current/default value when one is available.

Repository selection is intentionally bounded. Small collections are shown as a simple list. Collections larger than the selector page size are rendered as a page/window with a visible range and total count, so the wizard never dumps hundreds of repository names to the terminal. Filtering resets the selector to the first matching page, and numeric selection always applies to the currently displayed page.

When `[L list]` is used for a destination, selecting an existing repository only resolves an `owner/name` value. The user can use the selected name, edit it, or choose another repository. The final value then follows the same destination-existence and archive/replacement workflow used for a manually typed destination; list selection does not create a second replacement path.

When terminal styling is available, context/navigation hints and trailing default values are gray and italic. Plain-text or redirected output contains the same readable words with no ANSI sequences.

The first repository-selection step does not show Back. Help is a side action: dismissing it returns to the same prompt with the same current/default value. Back preserves valid prior answers; changing an earlier plan-affecting answer invalidates the reviewed plan so it must be regenerated before execution.

After mutation begins, Back is not available.
