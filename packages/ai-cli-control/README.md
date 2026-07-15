# ai-cli-control

English documentation. Complete Spanish documentation is available in [README.es.md](README.es.md).

`ai-cli-control` is a local selector for launching Codex, Claude, Grok, or Antigravity from the current terminal directory. It keeps the selected CLI's working directory and environment. It is original work and is not a KodexBar fork.

This package is also maintained inside the [KodexBar Suite monorepo](../../README.md). From that repository root, use `./install.sh` to install it together with the Plasma widget. The package-level `install.sh` remains available for standalone use.

## Features

- Select a provider, model, reasoning effort, and permission mode.
- Use KDialog when available, Yad as a graphical fallback, and an interactive terminal fallback otherwise.
- Read Codex models from the local model cache and query Grok and Antigravity catalogs when selected.
- Run one or more CLI updates in a fixed order, while continuing after a failed update.
- Recover read-only local conversation histories from Codex, Claude, Grok, and Antigravity with `ai recover`.
- Preview launch and update commands with `--dry-run`.
- Use English by default. Spanish locales receive Spanish interface text. `--language en` and `--language es` override locale detection.
- Keep every launched and updated command as an argument array without shell evaluation.
- Provide `kodexbar-quotas`, a local quota engine for the KodexBar Suite widget, and `kodexbar-panel`, a compact adapter for non-KDE bars.

## Requirements

- Python 3.10 or newer.
- At least one supported provider CLI on `PATH` when launching it.
- Optional `kdialog` or `yad` for graphical selection.
- A readable Codex model cache at `~/.codex/models_cache.json` when selecting Codex.

Antigravity must be available as `agy` and authenticated before its catalog can be queried. This project does not install, remove, authenticate, or configure any provider CLI.

## Quick start

Run from a clone or extracted release:

```bash
./ai
./ai --text
./ai --dry-run
./ai --language es --text
./ai --version
```

The graphical selector uses KDialog first, then Yad. Without a graphical session it uses the text selector. Cancelling any selector step exits successfully and does not launch a CLI.

The text selector accepts numbered choices. For the update checklist it accepts comma-separated numbers, `all`, or `0` to cancel.

## Recover conversations

`ai recover` is a standalone, read-only engine for transporting a previous local conversation into the current one. It reads provider history stores without changing them. Run it from a checkout or after installation:

```bash
./ai recover dump --provider grok --id last
ai recover list --provider claude --cwd /path/to/project
ai recover dump --provider agy --id SESSION_ID --max-chars 800
```

Use these three modes:

- Direct recovery: `ai recover dump --provider PROVIDER --id last` recovers the latest eligible conversation for that provider and project.
- List and choose: `ai recover list --provider PROVIDER`, then pass a listed id to `dump`.
- Multiple providers: run `list` once per provider, choose an id for each, then run one `dump` command per chosen session.

Providers are `codex`, `claude`, `grok`, `agy`, and `antigravity` as an alias for `agy`. For Claude, `--id last` skips the session that appears live and chooses the latest past session. Dumps display a `[TRUNCADO: ...]` marker when the output has been shortened.

When the matching CLI home directory exists, installation adds thin `recover-chat` adapters for Claude at `~/.claude/skills/recover-chat/` and Grok at `~/.grok/skills/recover-chat/`. The Claude adapter uses its interactive question tool for selection, and the Grok adapter presents a numbered chat list. Codex and Antigravity users invoke `ai recover` directly because no verified user-level adapter mechanism is installed for them.

## Non-interactive launch

The hidden automation arguments are supported for reproducible scripts and tests:

```bash
./ai --dry-run --provider codex --model gpt-5 --effort high --permissions ask
./ai --dry-run --provider claude --model opus --effort high --permissions accept-edits
./ai --dry-run --provider grok --model grok-4 --effort medium --permissions default
./ai --dry-run --provider antigravity --model 'Gemini 3.1 Pro (High)' --effort included --permissions plan
```

Antigravity model names already include their level. The interactive flow does not request an effort for Antigravity, and `--effort included` adds no effort flag.

## Permissions and launch arguments

The selector builds commands as argument arrays. These mappings are passed exactly to the provider CLI:

| Provider | Permission ID | Arguments |
| --- | --- | --- |
| Codex | `read-only` | `--sandbox read-only --ask-for-approval never` |
| Codex | `ask` | `--sandbox workspace-write --ask-for-approval on-request` |
| Codex | `automatic` | `--sandbox workspace-write --ask-for-approval never` |
| Codex | `full` | `--dangerously-bypass-approvals-and-sandbox` |
| Claude and Grok | `plan`, `manual` or `default`, `accept-edits`, `auto`, `dont-ask`, `bypass` | `--permission-mode` with the provider value |
| Antigravity | `manual` | No permission argument |
| Antigravity | `plan` | `--mode plan` |
| Antigravity | `accept-edits` | `--mode accept-edits` |
| Antigravity | `sandbox` | `--sandbox` |
| Antigravity | `full` | `--dangerously-skip-permissions` |

Provider availability, model entitlement, and provider-side behavior remain controlled by each provider.

## Updating provider CLIs

Choose **Update CLIs** in the main selector, or use a non-interactive list:

```bash
./ai --update codex,grok
./ai --update all --dry-run
```

Valid identifiers are `codex`, `claude`, `grok`, and `antigravity`. Updates always run in that order, even when the input order differs. The exact update arrays are `codex update`, `claude update`, `grok update`, and `agy update`.

Before and after each real update, the selector attempts `<cli> --version`. Standard output and error from each update stay attached to the terminal. A failed or missing CLI is reported and the remaining selected CLIs continue. The final status is `0` only when all selected updates succeed. `--dry-run` prints the update arrays without checking versions or executing updates.

## Installation and removal

Installation copies the executable into a durable user-owned location. It never points `~/.local/bin/ai` at the checkout or release directory.

```bash
./install.sh
ai --version
./uninstall.sh
# If the checkout is gone:
~/.local/share/ai-cli-control/uninstall.sh
```

The installed executable is `~/.local/share/ai-cli-control/ai`, with `~/.local/bin/ai` as its symlink. Its standalone `recover.py` engine, `kodexbar-quotas`, `kodexbar-panel`, and a copy of `uninstall.sh` are stored beside it for removal after a checkout has been deleted. No `sudo` is used. Installation refuses to replace an existing user-local command that is not owned by this project. It installs adapters only when their CLI home directory exists and never replaces an unowned `recover-chat` skill. Uninstallation checks ownership markers and removes only project-owned files. Both scripts are idempotent.

## Quotas engine

`kodexbar-quotas` is the widget's default local command. It reads the enabled providers from `~/.config/codexbar/config.json`. Claude is queried directly from `https://api.anthropic.com/api/oauth/usage` with the Claude OAuth token and a 15-second timeout. Codex, Antigravity, Grok, missing credentials, unexpected responses, and ordinary request failures use upstream `codexbar` per provider. Claude HTTP 429 remains a provider error so the widget can retain its cached reading. `cost --format json --json-only` is an upstream passthrough, or `[]` when upstream is absent.

Codex, Antigravity, and Grok remain upstream passthroughs in this version. During the Swift-source port, their acquisition paths depended on dashboard cookie and session handling plus provider-private response schemas, including protobuf endpoints, which cannot be reproduced faithfully with stdlib Python. Only Claude exposed the direct OAuth JSON request implemented here.

Usage invocations with flags the engine does not implement, such as `--status`, are delegated wholly to upstream `codexbar`.

The installer places it at `~/.local/share/ai-cli-control/kodexbar-quotas` and links `~/.local/bin/kodexbar-quotas` only when that link is owned by this package.

## Panel adapters

`kodexbar-panel` invokes the sibling `kodexbar-quotas` engine first, then the command on `PATH`. It prints the compact `Cx`, `Cl`, `Gk`, and `Ag` quota line used by the suite, with session and weekly usage where available. It has a 20-second engine timeout and returns a short error instead of a traceback when quota data is unavailable.

```bash
kodexbar-panel --format text
kodexbar-panel --format text --pango
kodexbar-panel --format waybar
kodexbar-panel --format json --providers codex,claude
kodexbar-panel --waybar-snippet
```

### Waybar on Hyprland and Omarchy

Print the paste-ready module and CSS example with `kodexbar-panel --waybar-snippet`. Add the `custom/kodexbar` block to your Waybar configuration and add `custom/kodexbar` to `modules-left`, `modules-center`, or `modules-right`. The module runs `kodexbar-panel --format waybar`, uses Waybar's JSON return type, and refreshes every 60 seconds.

On Hyprland, add the commented CSS rules from the snippet to the stylesheet used by your Waybar configuration, commonly `~/.config/waybar/style.css`. On Omarchy, themes override Waybar CSS through `~/.config/omarchy/current/theme/waybar.css`, so add the rules at that theme hook point. The installer never changes either user configuration.

### XFCE Generic Monitor

Add the **Generic Monitor** panel plugin, open its properties, and set **Command** to:

```bash
kodexbar-panel --format text --pango
```

Enable Pango markup in the plugin when that option is available, then use a 60-second period. The command is safe to run without Pango too, but the provider severity colors are only shown with Pango enabled.

## Development

```bash
make test
make check
make install
make uninstall
```

`make test` runs Python unit tests. `make check` runs unit tests, Python compilation, Bash syntax checks, and static safety checks. Tests use temporary executable fixtures and never execute real provider updates.

## Security

This project does not use `eval`, `shell=True`, or `os.system`. It does not include credentials or provider configuration. Read [SECURITY.md](SECURITY.md) for reporting guidance.

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a change. Releases follow [CHANGELOG.md](CHANGELOG.md).

## License and notices

Copyright 2026 Ismael (Karasowl). Licensed under the [MIT License](LICENSE). Third-party product notices are in [NOTICE.md](NOTICE.md).
