# Design QA

## Current acceptance target

The current provider and shell contract comes from Ismael's five annotated screenshots:

- `/tmp/codex-clipboard-6emLDM.png`: remove the redundant provider hero.
- `/tmp/codex-clipboard-j1yYAq.png`: make each compact provider block actionable.
- `/tmp/codex-clipboard-C2G2r3.png`: remove the duplicate provider switcher.
- `/tmp/codex-clipboard-BXTroo.png`: remove the incorrect text wordmark.
- `/tmp/codex-clipboard-W9z4Kr.png`: restore the packaged purple K mark.

The full popup must remain exactly 520 by 560 regardless of provider, account, quota row count, or selected destination.

## Implementation evidence

- Full provider surface: `qa-artifacts/provider-compact-switch-pass3-full.png`.
- Compact provider strip: `qa-artifacts/provider-compact-switch-pass3.png`.
- Feedback and implementation in one comparison: `qa-artifacts/provider-feedback-pass3-comparison.png`.
- Runtime logs: `qa-artifacts/provider-compact-switch-pass3-full-runtime.log` and `qa-artifacts/provider-compact-switch-pass3-runtime.log`.

The implementation was loaded from a source-shadow package under a temporary `XDG_DATA_HOME` and rendered with `plasmawindowed` on an isolated Xvfb display. It did not replace the installed package and did not use the active desktop, keyboard, pointer, or monitor.

## Mandatory comparison passes

### Layout and viewport

- The captured full window is exactly 520 by 560 pixels.
- The representation also declares explicit `width` and `height`, plus matching implicit, minimum, maximum, and preferred dimensions for Plasma.
- Removing the 112 pixel provider hero and 60 pixel switcher leaves one quota-focused surface without duplicated controls.
- Quota rows, cost or credits, operational state, and timestamp retain the existing 18 pixel content margins.
- The compact strip retains outer padding and separators while making the complete provider block the target.

### Brand, typography, color, and icons

- The global bar uses the existing `contents/icons/kodexbar.svg` asset, not a text approximation or a newly drawn mark.
- Existing Manrope typography, dark surface tokens, violet quota accent, and semantic state colors remain unchanged.
- Provider marks in the compact strip remain the real packaged provider assets.

### States and interactions

- Every compact block receives the exact popup `selectionKey`, including duplicate accounts such as `codex:1` and `codex:2`.
- Activating a block selects the provider destination, selects that exact account, and opens the full representation.
- Error blocks remain actionable, so an error for one provider opens its own diagnostic surface.
- The empty compact background still toggles the popup.
- Provider switching no longer appears in the popup because the compact strip is the single provider selector.

### Accessibility and resilience

- Compact blocks are native `AbstractButton` controls with accessible names, descriptions, hover state, pressed state, and full-text tooltips.
- Long quota text remains elided within the available panel width.
- The fixed viewport uses vertical scrolling when content exceeds 560 pixels instead of resizing between providers.

## Findings and corrections

- P1 corrected. The previous QA said the popup was fixed after adding only layout preferences. Ismael's live observation showed that claim was incomplete. The representation now owns explicit 520 by 560 geometry and the isolated capture measures exactly 520 by 560.
- P1 corrected. The provider hero duplicated information already selected in the panel. It is removed.
- P1 corrected. The bottom provider switcher duplicated the new panel interaction. It is removed.
- P1 corrected. The text `KodexBar Suite` replaced the actual product mark. The original packaged purple K mark is restored.
- P1 corrected. Compact provider blocks previously shared one outer click handler and could not select a specific account. They now carry and activate exact account keys.
- P2 corrected. Provider blocks now include internal horizontal padding while preserving the compact panel density.

## Verification

- `make check` passed.
- 236 Python tests passed.
- Provider logic fixtures passed.
- Local model, Skills, Signal Console, and Preferences static checks passed.
- QML lint passed.
- The full source-shadow Plasma capture measured 520 by 560.
- Runtime logs contain no QML error, warning, binding-loop, assignment, reference, or type failures.
- Human approval on the visible desktop remains the product acceptance boundary.

final result: passed
