# Changelog

All notable changes to this project are documented in this file.

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
