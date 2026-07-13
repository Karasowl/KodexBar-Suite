# Changelog

All notable fork-specific changes are documented here.

## Unreleased

## 0.3.0, 2026-07-13

### Added

- Faithful dark 520 by 560 popup with header, refresh control, provider tabs, status heading, source pill, metric hierarchy, progress bars, error state, empty state, loading state, and compact preview.
- Selectable provider-account tabs ordered as Codex, Claude, Grok, Antigravity, then every other enabled provider.
- Stable account ordinals in popup tabs and compact output.
- Width-safe compact block data shared by the actual panel and popup preview.
- Fixture coverage for popup ordering, active selection, default compact fields, errors, multiple accounts, extras, and elision.
- Supplied provider artwork for Codex, OpenAI, Claude, Grok, Antigravity, and Gemini.
- Bundled Manrope variable font and its SIL Open Font License.

### Changed

- Show only the active provider account in the popup without changing provider acquisition.
- Default compact quota selection to `primary,weekly`.
- Disable compact credits by default so the initial panel shows only primary and weekly usage.
- Use provider icons, status dots, separators, and bounded text in the panel representation.
- Keep Antigravity on its own provider icon instead of reusing the Gemini asset.
- Use short provider tab labels while keeping complete provider headings and stable account ordinals.
- Color compact and popup status dots from reported usage, including neutral unknown usage and shared warning and error thresholds.
- Treat clearly weekly extra-window badges as `W` while preserving deterministic badges for arbitrary extras.
- Rename the bundled Manrope file to a bracket-free package path.
- Set the package version to 0.3.0.

## 0.2.0, 2026-07-12

### Added

- Configurable ordered provider selection for the compact system tray summary.
- Independent compact quota selection with global and provider-qualified keys.
- Provider-grouped compact usage for selected primary, weekly, tertiary, and extra windows.
- One-time migration from the hidden legacy provider selection to compact provider settings.
- Deterministic fixture tests for ordering, filtering, quota selection, error retention, duplicate removal, and Gemini window normalization.
- English and Spanish documentation for installation, update, removal, attribution, and compatibility.
- Static validation and secret scanning workflows.

### Changed

- Keep every returned provider and detected quota in the popup regardless of compact panel selections.
- Acquire providers through the default CodexBar query so enabled-provider toggles are honored, while preserving repeated accounts for the same provider.
- Use the default CodexBar cost query instead of the slow all-provider override.
- Include tertiary and extra rate-limit windows in the `extras` compact key.
- Display reset-only standard windows in the popup with unknown usage marked correctly.
- Show `No selection` with a neutral icon for unmatched compact settings.
- Remove the automatic usage threshold for extra quotas shown in the compact panel.
- Distinguish Antigravity as `Ag` and Gemini as `Gm` in compact output.
- Distinguish repeated provider accounts with stable non-sensitive ordinals.
- Use minimum unique prefixes and duplicate ordinals for extra quota labels.
- Show provider-level cost summaries once and make popup provider chips horizontally scrollable.
- Present Antigravity as `Gemini (Antigravity)` in the popup.
- Normalize reversed primary and secondary windows only for Antigravity and Gemini.
- Use the Karasowl fork website while preserving tylxr as the original author.

### Preserved

- Original upstream Git history, MIT license, and screenshot.
- Provider-specific popup details, reset information, credits, status, and cost summaries.
