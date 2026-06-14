# KodexBar

KodexBar is a native KDE Plasma panel widget inspired by [CodexBar](https://github.com/steipete/codexbar). It displays CodexBar CLI usage, quota, and credit data in a Plasma panel popup.

KodexBar intentionally uses the upstream `codexbar` CLI as its data source rather than reimplementing CodexBar's provider backends. The original project is a macOS Swift menu bar app, while the CLI has Linux release artifacts and a JSON interface suitable for Plasma.

## Requirements

- KDE Plasma 6
- CodexBar CLI on `PATH`

Install the upstream CLI with Homebrew on Linux:

```sh
brew install steipete/tap/codexbar
codexbar --version
codexbar usage --format json --pretty
```

Or download a Linux CLI tarball from the upstream GitHub releases.

## Install

From this repository:

```sh
kpackagetool6 -t Plasma/Applet -i .
```

Then add `KodexBar` to a Plasma panel.

For development reloads:

```sh
kpackagetool6 -t Plasma/Applet -u .
plasmashell --replace
```

## Configuration

Open the widget settings to choose:

- `codexbar` command path
- provider (`Best available`, `All enabled`, or any current CodexBar provider ID exposed in the settings list)
- source (`Best available`, `auto`, `web`, `cli`, `oauth`, `api`)
- refresh interval
- whether credits appear in the compact panel label
- whether provider status is fetched with `codexbar usage --status`

Provider credentials and toggles are still owned by CodexBar CLI in `~/.codexbar/config.json`.

On Linux, many CodexBar providers cannot use the upstream macOS WebKit/web source. `Best available` first asks the CLI to use its configured defaults from `~/.codexbar/config.json`, then falls back to Linux-friendly combinations such as Codex CLI/OAuth/API, Claude CLI/OAuth/API, and common API-backed providers. If you already know the provider, choose it directly; leaving Source as `Auto` or `Best available` will still try CLI/OAuth/API before falling back to upstream `auto`.

The popup renders the common CodexBar CLI JSON fields: primary/secondary/tertiary windows, extra named rate windows, provider spend/budget snapshots, credits, basic OpenAI dashboard summaries, provider status, and per-provider errors. Provider-specific charts, account management, cookies/API-key editing, notifications, and cost scans remain available through the upstream app/CLI rather than being reimplemented in the Plasma widget.

## Test The CLI

```sh
codexbar usage --format json --json-only --provider all --source auto | python3 -m json.tool
codexbar usage --format json --json-only --provider codex --source oauth | python3 -m json.tool
```

If the widget shows a CLI error, either install the CLI or set the full command path in the widget settings.
