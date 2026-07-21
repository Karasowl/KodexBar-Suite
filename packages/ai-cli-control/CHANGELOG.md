# Changelog

All notable changes to this project are documented in this file.

## 0.9.1, 2026-07-21

- Enrich native Codex usage mapping with top-level credits (only when balance > 0) and banked rate-limit reset credits (`codexResetCredits` only when available count > 0).
- Rewrite Claude usage mapping to prefer self-describing `limits[]` (session, weekly_all, and per-model weekly_scoped windows such as Fable as `extraRateWindows`), with legacy five_hour/seven_day fallback, and always emit `extraUsage` status (no top-level Claude credits).
- Map Grok weekly aggregate into the Weekly secondary window, surface Build/API/Imagine breakdown as `extraRateWindows`, and keep the compact tray badge on the weekly percent when primary is empty.
- Gate credit and banked-reset display to positive values only (engine emit + widget).

## 0.9.0, 2026-07-20

- Fetch Codex and Grok quotas natively in `kodexbar-quotas` (stdlib HTTP) without requiring the companion `codexbar` binary for those providers.
- Keep Antigravity on the upstream `codexbar` path. Use that CLI as optional fallback for Codex/Grok on network, timeout, and schema-drift (invalid response) failures when the companion is installed.
- Fall back to installed `codexbar` when the native Codex or Grok parser cannot map a provider response, so schema changes do not leave the widget stuck without the maintained companion path.
- Show plain-language English errors for Codex and Grok (re-login, connection, and optional `codexbar-cli-bin` install guidance) without technical jargon or secrets.
- On Codex or Grok authentication failure (missing credentials, 401/403, expired token), surface a re-login message and do not refresh OAuth tokens automatically.
- Move AUR dependency `codexbar-cli-bin` from hard `depends` to `optdepends` for Antigravity and Codex/Grok fallback.

## 0.8.1

- Default `ai recover` help text to English unless an explicit Spanish locale is set (`LANG`/`LC_*` starting with `es`).
- Make recover help tests assert stable tokens instead of argparse usage line layout that differs across Python 3.12–3.14.

## 0.8.0, 2026-07-19

- Add monorepo-root GitHub Actions CI (`.github/workflows/ci.yml`) for suite tests and packaging checks, and remove package-local workflows under `packages/*/.github/workflows/` that GitHub Actions never discovered.
- On first run without `~/.config/codexbar/config.json`, detect installed AI CLIs (Claude, Codex, Grok, Antigravity) and auto-write a versioned CodexBar provider config so enabled quotas appear without manual editing. Existing configs are never overwritten or repaired.
- Show a friendly missing-engine setup card in the Plasma widget when only the KDE Store applet is installed (command-not-found for `kodexbar-quotas`), with the copyable install command `paru -S kodexbar-suite` and a repository link. The card clears on the next successful engine response.
- Print a short post-install AUR message (`kodexbar-suite.install`) explaining how to add the widget to a Plasma panel and that installed CLI quotas are detected automatically on first use.
- Ship official steipete CodexBar CLI via hard AUR dependency `codexbar-cli-bin` so `paru -S kodexbar-suite` leaves Codex/Grok/Antigravity quota backends ready without a separate companion install.

## 0.7.0, 2026-07-16

- Preserved exact quota acquisition failures with structured retry categories instead of replacing them with a generic upstream error.
- Distinguished transient network, timeout, and invalid-response failures from rate limits, authentication, entitlement, and permanent failures.
- Added AUR packaging (`packaging/aur`) for a system-wide full-suite install under `/usr`, plus a reproducible KDE Store `.plasmoid` builder.
- Resolved tray status icons from the first complete icon directory among the user install and `/usr/share/icons`, so pacman installs work without `~/.local`.
- On first run without `~/.config/codexbar/config.json`, serve Claude quotas natively when Claude Code credentials exist, keep full upstream delegation when steipete's `codexbar` is on `PATH`, and show setup guidance for Claude when neither is available.

## 0.6.0, 2026-07-15

- Made `ai recover --copy` try the next installed clipboard tool when an earlier candidate fails at runtime.
- Added `kodexbar-tray`, a StatusNotifierItem quota indicator for GNOME, COSMIC, and KDE, with manual refresh, user autostart management, and status icons.

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
