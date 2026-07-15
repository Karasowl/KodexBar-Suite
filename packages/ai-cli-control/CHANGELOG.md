# Changelog

All notable changes to this project are documented in this file.

## 0.5.0, 2026-07-14

- Reported when an installed upstream `codexbar` fails to provide usage data, without mislabeling it as missing.
- Added examples and output guidance to `ai recover --help`, with `ai recover` in command usage lines.
- Added positional recovery with numbered session listings and `last`, index, or session-ID selectors.
- Added terminal export destinations for recovery dumps: clipboard, Markdown file, or stdout, while preserving plain non-interactive output.

## 0.4.0, 2026-07-14

- Added `kodexbar-panel`, a stdlib-only compact quota adapter for Waybar and the XFCE Generic Monitor plugin.
- Added safe installation and removal of the owned `kodexbar-panel` user-local executable.

## 0.3.0, 2026-07-14

- Added `kodexbar-quotas`, a stdlib-only quota engine that reads enabled CodexBar providers, fetches Claude OAuth usage directly, and falls back per provider to upstream `codexbar`.
- Installed and safely removed the owned `kodexbar-quotas` user-local executable with the existing `ai` ownership rules.

## 0.2.1, 2026-07-14

- Made the test harness locale-independent by forcing a deterministic English locale for subprocesses.

## 0.2.0, 2026-07-14

- Added `ai recover`, a read-only conversation recovery command for Codex, Claude, Grok, and Antigravity histories.
- Added installable Claude and Grok skill adapters for direct recovery, session selection, and multi-provider recovery.

## 0.1.0, 2026-07-12

- Published the universal local selector for Codex, Claude, Grok, and Antigravity.
- Added dynamic model catalogs, permission selection, graphical and text interfaces, dry-run support, and sequential provider updates.
- Added English and Spanish runtime interfaces and complete bilingual documentation.
- Added durable user-local installation, safe removal, tests, static checks, and continuous integration.
