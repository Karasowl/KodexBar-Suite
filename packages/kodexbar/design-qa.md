# Design QA

## Comparison target

- Approved visual: option 1, the skill-first Operational Matrix selected by Ismael.
- Source asset: approved conversation asset `call_JUzwYN9fxL4ubCMVOBcsdfVo.png`.
- Source pixels: 1365 by 1161.
- Native implementation viewport: 520 by 560 at device scale factor 1.
- Normalized source: `qa-artifacts/skills-reference-520x560.png`.
- Final implementation: `qa-artifacts/skills-implementation-pass2.png`.
- Same-image comparison: `qa-artifacts/skills-comparison-pass2.png`.
- Preview-ready interaction state: `qa-artifacts/skills-preview-ready.png`.
- Supporting system screens: `qa-artifacts/provider-final.png`, `qa-artifacts/local-implementation.png`, `qa-artifacts/preferences-general-pass2.png`, `qa-artifacts/preferences-shortcuts.png`, and `qa-artifacts/preferences-about.png`.

The source aspect ratio is wider than the fixed Plasma popup. It was proportionally resized and letterboxed to 520 by 560 instead of distorted. The implementation adapts the same hierarchy to the approved fixed native viewport and shows all six providers detected on the machine rather than the four examples in the generated visual.

## Capture method

The real installed Plasma applet was opened with `plasmawindowed` on an isolated Xvfb display. No active desktop, keyboard, pointer, or monitor was used. Native X11 test input inside that isolated display exercised the provider checkbox, Preview changes, settings button, and settings navigation. The final package source was restored to the normal provider destination and compact panel representation after capture.

## Mandatory comparison passes

### Layout, spacing, and viewport

- The popup remains exactly 520 by 560 for Providers, Local models, and Skills.
- The approved 18 pixel page margins, strong title area, flat matrix, row dividers, status column, and fixed action area are present.
- Provider switch choices are 56 pixels tall and provider marks sit inside a consistent 30 pixel slot with a 22 pixel icon.
- Skills supports six live provider columns without horizontal overflow. Provider labels move to tooltips while the real marks remain visible.
- Local models keeps a vertical-only inventory inside the same fixed surface.

### Typography and copy

- Manrope remains the product font, with 25 pixel page titles, 13 pixel descriptions, and no 8 to 10 pixel microtype in the redesigned surfaces.
- Long skill names and descriptions elide within their columns. Compact status text avoids the earlier clipped `Missing from providers` sentence.
- Configuration no longer uses all-caps microtype for the panel preview.

### Color, surfaces, and icons

- All main surfaces use the shared dark palette and semantic violet, green, amber, and red states.
- Navigation, utility, local model, and settings icons come from one packaged Tabler outline family. Provider columns retain the existing real provider marks.
- The OpenCode mark receives a light neutral backing because its upstream asset is dark. Other provider marks remain unboxed.
- Preferences now supplies an explicit dark native control palette. Text fields, checkboxes, source chips, and bottom actions no longer inherit light controls with black text.
- Preference groups are flat sections with dividers. Only the live panel preview remains a bordered card because it represents a contained preview surface.

### States and interactions

- A native checkbox exists for every provider cell and a global native checkbox selects every safe provider cell.
- Editing any cell invalidates a stale preview and its exact pending batch.
- Preview changes runs the backend dry run. A successful preview enables Apply changes.
- Apply changes opens the existing confirmation dialog. No batch was applied during visual QA.
- Conflicts remain locked and divergent content is never overwritten.
- Providers, Local models, Skills, refresh, settings, General, Keyboard shortcuts, and About were opened in the isolated runtime.

### Accessibility and resilience

- Top destinations and icon-only actions retain accessible names and descriptions.
- Skill and local model actions use 44 pixel targets.
- Native checkboxes preserve keyboard and focus behavior.
- The fixed viewport, vertical scrolling, elision, and compact status language prevent horizontal clipping at 520 pixels.
- The settings window was captured at 980 by 680. Its declared minimum remains 820 by 560.

## Findings and corrections

- P1 corrected. Local SVG icons resolved as black in Plasma despite `currentColor`. The packaged monochrome assets now use a tested neutral stroke and render consistently.
- P1 corrected. Preferences inherited a light native-control palette, producing white fields and black labels. The window now defines a complete dark control palette.
- P1 corrected. Preview previously opened confirmation immediately. The visible Preview and Apply sequence now matches the approved operational model and prevents applying a stale selection.
- P1 corrected. Popup size could follow destination implicit content. The full representation now has fixed implicit, minimum, maximum, and preferred dimensions.
- P2 corrected. The provider switcher lacked internal icon padding and had smaller targets. It now uses 56 pixel choices and a 30 by 30 icon slot.
- P2 corrected. Skills mixed status with the skill description and truncated provider labels. It now has a dedicated status column, real provider marks, and tooltips.
- P2 corrected. Local models and Preferences used unrelated theme icons and card treatments. They now extend the approved visual system.
- P3 accepted. Live skill names, counts, providers, conflicts, quotas, models, and timestamps differ from the generated example because the implementation renders current machine data.
- P3 accepted. Six providers produce a denser matrix than the four-provider source. The density is necessary to preserve the requested per-provider control without hiding connected providers.

No remaining actionable P0, P1, or P2 design issue was found in the final same-image comparison or supporting screen captures.

## Verification

- `make check` passed.
- 236 Python tests passed.
- Provider logic fixtures passed.
- Local model, Skills, Signal Console, and Preferences static checks passed.
- QML lint passed.
- The installed Skills, Local models, Provider, and all Preferences pages rendered without QML type, binding-loop, assignment, or reference errors.
- The read-only Skills preview interaction reached the visible Preview ready state and enabled Apply changes.
- Final human approval on the visible desktop remains the product acceptance boundary.

final result: passed
