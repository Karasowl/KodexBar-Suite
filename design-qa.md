# Design QA

## Comparison target

- Source visual truth: `../Widget-design-reference-2026-07-13/source-codex-520x560.png`, `../Widget-design-reference-2026-07-13/source-claude-520x560.png`, and `../Widget-design-reference-2026-07-13/source-antigravity-520x560.png`.
- Normative template: `../Widget-design-reference-2026-07-13/KodexBar.dc.html`.
- Implementation screenshot: not captured in this worker environment.
- Viewport: 520 by 560.
- States: Codex metrics, Claude error, and Antigravity metrics.

## Full-view comparison evidence

The source screenshots were opened at their original resolution. A matching implementation capture was not produced because this worker was explicitly prohibited from installing the plasmoid or restarting Plasma. A full-view comparison is therefore unavailable.

## Focused region comparison evidence

Focused visual comparison is unavailable for the same reason. Static review covered the header, provider tabs, account heading, metric rows, error card, loading and empty states, and compact preview against the normative HTML values.

## Findings

- P1, no rendered implementation evidence.
  - Location: complete popup and panel representation.
  - Evidence: source captures exist, but there is no screenshot from the real Plasma build.
  - Impact: spacing, clipping, native control metrics, and SVG rendering cannot be judged visually.
  - Fix: install the checkpoint in the isolated QA surface, capture all three states at 520 by 560, and compare them with the source images.

## Required fidelity surfaces

- Fonts and typography: the official Manrope variable font is bundled and loaded from the package with the theme font as a safe fallback. Rendered comparison remains blocked by the missing implementation capture.
- Spacing and layout rhythm: statically mapped to the 520 by 560 template, but visual comparison is blocked.
- Colors and visual tokens: mapped to the normative dark palette in QML, but rendered sampling is blocked.
- Image quality and asset fidelity: supplied provider SVG files are used directly. Rendered sharpness and scale remain unverified.
- Copy and content: reference labels and state copy are implemented with live CodexBar values.

## Implementation checklist

- Capture Codex, Claude error, and Antigravity states from the real plasmoid.
- Exercise provider tabs and refresh in the captured build.
- Compare full views and focused header, metric, error, and compact regions.
- Correct any P0, P1, or P2 differences before visual approval.

## Comparison history

No visual iteration was possible in this worker environment.

final result: blocked
