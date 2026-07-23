# Design QA

## Comparison target

- Source visual truth for the local-model state: the `KodexBar.dc.html` and `screenshots/local-tab.png` files in the approved Widget retro tecnológico archive. The tab is icon-only, the AI CLI Control terminal action remains separate, model rows are grouped and minimal, and the local list has no horizontal scroll.
- Source visual truth: `../Widget-design-reference-2026-07-13/source-codex-520x560.png`, `../Widget-design-reference-2026-07-13/source-claude-520x560.png`, and `../Widget-design-reference-2026-07-13/source-antigravity-520x560.png`.
- Normative template: `../Widget-design-reference-2026-07-13/KodexBar.dc.html`.
- Implementation screenshots: `qa-artifacts/window-codex-fixed.png`, `qa-artifacts/window-claude-fixed.png`, and `qa-artifacts/window-antigravity-fixed.png`.
- Viewport: 520 by 560.
- States: Codex metrics, Claude error, and Antigravity metrics.

## Full-view comparison evidence

The source screenshots and matching implementation captures were composed side by side at 520 by 560 in `qa-artifacts/comparison-final-codex-claude.png` and `qa-artifacts/comparison-antigravity-fixed-final.png`. The implementation was captured from the installed 0.3.0 package through an isolated Plasma QA window. Codex, Claude, and Antigravity were exercised, including the fixed viewport and the Session quota badge.

## Focused region comparison evidence

Focused comparison covered the header, provider tabs, account heading, metric rows, error card, Session and Weekly badges, scroll area, and compact preview against the normative HTML values.

## Findings

- P2, live provider details include timezone text in some CodexBar reset descriptions, for example `Resets3pm(America/Mexico_City)`. This is preserved provider data and is outside the compact label and viewport changes in this unit.

## Required fidelity surfaces

- Fonts and typography: the official Manrope variable font is bundled and loaded from the package with the theme font as a safe fallback. Rendered comparison remains blocked by the missing implementation capture.
- Spacing and layout rhythm: statically mapped to the 520 by 560 template, but visual comparison is blocked.
- Colors and visual tokens: mapped to the normative dark palette in QML, but rendered sampling is blocked.
- Image quality and asset fidelity: supplied provider SVG files are used directly. Rendered sharpness and scale remain unverified.
- Copy and content: reference labels and state copy are implemented with live CodexBar values.
- Local-model tab: the implementation preserves every provider surface when switching back, shows installed but unmounted rows dimmed, shows real throughput only when present in the JSON contract, and gives ComfyUI a runtime-wide release action instead of pretending it can unload a named checkpoint.

## Implementation checklist

- Capture Codex, Claude error, and Antigravity states from the real plasmoid.
- Exercise provider tabs and refresh in the captured build.
- Compare full views and focused header, metric, error, and compact regions.
- Correct any P0, P1, or P2 differences before visual approval.

## Comparison history

The final local comparison confirmed the fixed 520 by 560 viewport, the visible Session badge, the provider tabs, the fixed footer preview, the real refresh icon, and the preserved scroll area. Codex, Claude, and Antigravity were captured from the installed QA package. The settings implementation was installed and verified by QML lint and static tests. The new provider checkboxes are in the General configuration surface and synchronize with `compactProviderOrder`.

final result: passed
