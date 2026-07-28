# Design QA

## Current acceptance target

The current provider contract comes from Ismael's latest three screenshots:

- `/tmp/codex-clipboard-T8gOeU.png`: reduce the unused lower region while preserving useful provider data.
- `/tmp/codex-clipboard-7XLWvl.png`: remove compact-provider hover overlays that cover adjacent taskbar navigation.
- `/tmp/codex-clipboard-IfcuY0.png`: keep one stable popup height, restore a small provider logo, and avoid the sparse one-row layout dominating the screen.

The earlier approved constraints remain active. The oversized provider hero and duplicate bottom provider selector must not return. Provider changes must not resize the popup.

## Implementation evidence

- Sparse provider at the final size: `qa-artifacts/provider-feedback-codex-pass2.png`.
- One-row provider at the final size: `qa-artifacts/provider-feedback-grok-pass2.png`.
- Dense provider at its initial scroll position: `qa-artifacts/provider-feedback-dense-pass2.png`.
- Dense provider scrolled through supplemental data: `qa-artifacts/provider-feedback-dense-scrolled-pass2.png`.
- Dense provider scrolled to the operational footer: `qa-artifacts/provider-feedback-dense-footer-pass2.png`.
- Four-second compact hover with no overlay: `qa-artifacts/provider-feedback-hover-no-overlay-pass2.png`.
- Source feedback and final one-row implementation in one comparison image: `qa-artifacts/provider-feedback-pass2-comparison.png`.
- Isolated runtime log: `/tmp/kodexbar-feedback-pass2-runtime.log`.

The implementation was loaded from a source-shadow package under a temporary `XDG_DATA_HOME` and rendered with `plasmawindowed` on Xvfb display `:97`. It did not replace the installed package and did not use the active desktop, keyboard, pointer, or monitor.

## Viewport and normalization

- Source feedback image: 575 by 619 pixels including desktop and taskbar context.
- Implementation content captures: 520 by 400 pixels at density 1.
- CSS-equivalent QML viewport: 520 by 400 logical pixels.
- The combined comparison keeps both screenshots at their native density and top-aligns them. The relevant app content shares the same 520-pixel width.
- The source screenshot is a defect report, not an exact copy target. The comparison therefore judges the four requested corrections while preserving the approved Signal Console visual language.

## Mandatory fidelity surfaces

### Fonts and typography

- The existing bundled Manrope variable font remains unchanged.
- The identity name uses 15-pixel extra-bold type. Plan, source, and optional account context use 11-pixel muted type.
- Quota headings, values, reset labels, details, and operational timestamps retain their prior hierarchy without clipping in the 520-pixel viewport.

### Spacing and layout rhythm

- The popup now declares matching explicit, implicit, minimum, maximum, and preferred dimensions of 520 by 400.
- The fixed height is 160 pixels shorter than the reported 520 by 560 state.
- The provider identity row uses the existing 18-pixel content margins, a 28-pixel logo, and a 44-pixel content height.
- A one-row provider retains a bounded flexible region so the footer stays aligned, but no longer produces the dominant empty column shown in the source screenshot.
- Dense providers remain the same height and scroll vertically. The Claude capture verifies quota rows, spend, extra usage, and the footer remain reachable.

### Colors and visual tokens

- The dark surface, line, text, muted, violet, warning, error, and operational tokens are unchanged.
- The small identity status dot uses the same semantic provider status color as the footer.
- No new decorative card, gradient, or shadow treatment was introduced.

### Image quality and asset fidelity

- Each provider view uses the real packaged provider SVG through `providerIconSource`.
- The 28-pixel identity mark is rendered with preserved aspect ratio and smoothing.
- The packaged purple KodexBar K remains in the global navigation.
- No text glyph, custom inline SVG, or drawn approximation replaces a provider or product logo.

### Copy and content

- Provider name, plan, source, and privacy-controlled account context are restored in the compact identity row.
- Credits or spend remain visible when present.
- Extra usage, banked resets, and dashboard details are restored when the provider returns them.
- A connected provider without quota data now gets an explicit empty state instead of a blank surface.

### States, interactions, and accessibility

- Compact provider blocks remain native `AbstractButton` controls with accessible names and descriptions.
- Hover and pressed visual states remain, but the compact strip contains no `ToolTip`.
- After four seconds of hover, X11 reported only the compact and full KodexBar windows. No tooltip or overlay window was mapped.
- Compact activation switched among Codex, Claude, and Grok in the isolated runtime.
- Dense content was scrolled to supplemental data and to the operational footer.
- The provider logo has an accessible name.

## Findings and comparison history

- P1 corrected. The 520 by 560 popup left a large unused lower region for sparse providers. Pass 1 reduced the popup to 520 by 440, but the visual comparison still showed an avoidable lower gap. Pass 2 reduced it to 520 by 400 and kept the footer, spend line, and two-row Codex state together.
- P1 corrected. The compact hover tooltip covered neighboring taskbar icons. The compact strip no longer creates a tooltip. A timed runtime hover produced no additional mapped window.
- P1 corrected. Removing the old hero also removed useful provider identity and provider-specific data. The final design restores a compact logo, provider name, plan, source, optional account, extra usage, banked resets, and dashboard details without restoring the oversized hero.
- P2 corrected. Dense providers could lose lower data after the height reduction. The final provider surface declares vertical overflow behavior and runtime scrolling reached both supplemental data and the operational footer.

## Residual polish

- P3. A provider that returns only one quota row still has a modest flexible region. This is intentional because the window must remain fixed across providers. Shrinking further would force ordinary two-row providers to scroll before showing spend and state.
- Human approval on the visible desktop remains the product acceptance boundary.

## Verification

- `make check` passed.
- 236 Python tests passed.
- Provider logic, Local models, Skills, Signal Console, and Preferences static checks passed.
- QML lint passed.
- The AUR patch applies cleanly to v0.12.1 and produces QML byte-for-byte identical to the working source.
- A clean `kodexbar-suite 0.12.1-2` package build passed.
- The QML extracted from that package has the same SHA-256 as the working source.
- Runtime logs contain no QML error, warning, binding-loop, assignment, reference, or type failure.

final result: passed
