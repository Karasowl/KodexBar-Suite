# Changelog

All notable fork-specific changes are documented here.

## Unreleased

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
