# KodexBar Suite

[Leer en español](README.es.md)

> Ordered AI provider quotas in your KDE Plasma panel.

[![Plasma 6](https://img.shields.io/badge/KDE%20Plasma-6-1d99f3?style=flat-square)](https://kde.org/plasma-desktop/)
[![CodexBar CLI](https://img.shields.io/badge/powered%20by-CodexBar%20CLI-0a0a0c?style=flat-square)](https://github.com/steipete/CodexBar)
[![License: MIT](https://img.shields.io/badge/license-MIT-6e5aff?style=flat-square)](LICENSE)

KodexBar Suite is a KDE Plasma 6 widget for monitoring AI provider quotas through the [CodexBar CLI](https://github.com/steipete/CodexBar). It provides a configurable compact summary in the panel and a complete popup with every enabled provider and quota.

This package is also maintained inside the [KodexBar Suite monorepo](../../README.md). From that repository root, use `./install.sh` to install it together with `ai-cli-control`. The package can still be validated and installed independently.

![KodexBar Suite screenshot](screenshot.png)

## Features

- Uses the selected dark 520 by 560 card with provider tabs, live status, source pills, metric badges, progress bars, and a matching compact preview.
- Shows one provider account at a time, ordered as Codex, Claude, Grok, Antigravity, then every other enabled provider.
- Keeps repeated accounts separate with stable non-sensitive ordinals in tabs and compact output.
- Uses the supplied Codex, Claude, Grok, Antigravity, and Gemini SVG assets while keeping Antigravity and Gemini distinct.
- Adds `compactProviderOrder`, an ordered comma-separated provider selection for the compact panel.
- Adds `compactQuotaSelection`, a comma-separated quota selection for the compact panel.
- Defaults to `codex,claude,grok,antigravity`.
- Matches provider IDs without case and removes duplicate IDs.
- Keeps listed providers with errors visible as `ERR`.
- Omits unselected providers only from the compact panel.
- Preserves every returned provider and detected quota in the popup.
- Always acquires the providers enabled in CodexBar. The compact settings never narrow acquisition.
- Preserves multiple accounts returned with the same provider ID.
- Adds stable account ordinals such as `Cx #1` and `Cx #2` without exposing account emails.
- Shows compact provider labels and both primary and weekly used percentages on one line.
- Shows selected extra windows at every usage percentage, with no automatic threshold.
- Shows standard primary, secondary, and tertiary windows in the popup when usage or reset data is known.
- Uses deterministic minimum unique prefixes for extra quota labels, while preserving `Fb` for Fable.
- Keeps provider tabs horizontally scrollable when the popup contains many enabled providers or accounts.
- Shows each provider-level cost summary only once when multiple accounts share a provider.
- Labels the Antigravity tab as `Antigravity` and presents its full heading as `Gemini (Antigravity)`.
- Colors compact status dots from the worst selected usage, with warning at 50 percent, error at 80 percent, and neutral when usage is unavailable.
- Corrects reversed Gemini window order when the CLI reports a longer primary window than secondary.
- Preserves provider-specific popup details, reset times, credits, status, and cost summaries.

## Requirements

- KDE Plasma 6
- `kpackagetool6`
- `kodexbar-quotas` on `PATH` for the default local engine, with upstream `codexbar` on `PATH` as its per-provider fallback

Install the CLI with Homebrew on Linux:

```sh
brew install steipete/tap/codexbar
codexbar --version
codexbar usage --format json --pretty
```

You can also download a Linux CLI archive from the [CodexBar releases](https://github.com/steipete/CodexBar/releases/latest).

Provider credentials and enabled providers are managed by CodexBar. Configure the provider CLIs, OAuth sessions, or API keys required by the providers you use.

## Compatibility Warning

This fork intentionally uses the same Plasma plugin ID as upstream, `org.kde.plasma.kodexbar`. It replaces an upstream installation in place. Do not install the upstream widget and this fork at the same time.

Your existing Plasma widget configuration remains associated with that plugin ID. A one-time migration converts the hidden legacy provider choice into the compact provider selection. A specific provider becomes that provider ID, `all` becomes an empty compact filter, and `detect` keeps the default order. An already customized compact order is never overwritten.

## Install

Clone the fork and install it:

```sh
git clone https://github.com/Karasowl/KodexBar.git
cd KodexBar
kpackagetool6 -t Plasma/Applet -i .
```

If `kpackagetool6` reports that the package already exists, use the update command because this fork replaces the same plugin ID:

```sh
kpackagetool6 -t Plasma/Applet -u .
```

Then add **KodexBar Suite** to a Plasma panel if it is not already present.

## Update

Update the clone and replace the installed package:

```sh
git pull --ff-only
kpackagetool6 -t Plasma/Applet -u .
```

Restart Plasma only if the shell does not reload the changed package automatically:

```sh
plasmashell --replace
```

## Uninstall

Remove the shared plugin ID:

```sh
kpackagetool6 -t Plasma/Applet -r org.kde.plasma.kodexbar
```

This removes whichever package currently occupies that ID, whether it is KodexBar Suite or the upstream KodexBar widget.

## Usage

- Click the panel item to open the popup.
- Use the refresh button to query the CLI immediately.
- Open widget settings to choose a source, refresh interval, and panel fields.
- Right-click the widget and choose `Open AI CLI Control` to launch the separate `ai` selector window. Choose `Update all AI CLIs` to run its existing multi-provider update flow for Codex, Claude, Grok, and Antigravity.
- The widget always requests the providers enabled in CodexBar.
- Use the visible provider checkboxes to select which providers appear in the system tray, then edit `Compact providers` when you need a custom order or provider ID.
- Edit `Compact quotas` to select the quota values shown in the system tray.
- Leave `Compact providers` empty to show every returned provider in CLI order.
- Leave `Compact quotas` empty to show provider labels without quota values.
- Open the popup to see every returned provider and detected quota regardless of compact selections.

The default compact output follows this shape:

```text
[Codex icon] S24% W61% | [Claude icon] ERR | [Grok icon] S8% W31% | [Antigravity icon] S0% W1%
```

`S` is the used percentage for the Session window, kept internally as the `primary` quota key. `W` is the used percentage for the weekly or secondary window. The values above are illustrative, not real account data.

When CodexBar returns multiple accounts for one provider, the compact panel adds non-sensitive ordinals such as `Cx #1` and `Cx #2`. The ordinals remain visible when provider labels are disabled. Account emails remain confined to the optional popup email field.

The default quota selection is `primary,weekly`. These global keys apply to every provider selected for the compact panel. Add `extras` to include the standard tertiary window and every entry from `extraRateWindows`. To choose individual values, use provider-qualified keys such as `codex.primary`, `antigravity.tertiary`, `claude.weekly`, and `claude.fable-only`. A provider-qualified `extras` key, such as `claude.extras`, selects its tertiary window and every detected extra rate-limit window. Extra quota titles become stable lowercase keys with words separated by hyphens. Their visible labels use the shortest unique prefix of at least two characters within the provider. Identical titles receive ordinals. Each visual provider block is capped and elided safely, while its complete selected values remain available to the compact model.

### Acquisition and compact selection

Every refresh runs the default CodexBar usage query without a `--provider` override. CodexBar therefore honors its enabled-provider toggles, and the popup receives every enabled provider and returned account. Passing `--provider all` is intentionally avoided because CodexBar 0.40.0 also returns disabled providers for that explicit override.

`Compact providers` and `Compact quotas` only control the system tray summary after that CLI request returns. They never remove data from the popup. An invalid provider or quota selection displays `No selection` with a neutral icon instead of implying that Codex was selected.

### Gemini labels

The popup uses `Gemini (Antigravity)` for Antigravity and `Gemini` for the independent Gemini provider. Compact labels stay distinct too. Antigravity uses `Ag` and Gemini uses `Gm`, so their quota values are not visually combined.

## Settings

| Setting | Purpose |
| --- | --- |
| Command | Empty or default uses `kodexbar-quotas`, then retries `codexbar` only if the engine command is missing. A custom command is used alone. |
| AI CLI Control | `ai` binary name or full path used by the widget actions. |
| Source | `Best available`, `auto`, `web`, `cli`, `oauth`, or `api`. |
| Refresh | Poll interval from 10 to 3600 seconds. |
| Compact providers | Display-only ordered comma-separated provider IDs used by the system tray. The visible provider checkboxes cover Codex, Claude, Grok, and Antigravity. Empty shows every returned provider and never filters the popup. |
| Compact quotas | Display-only comma-separated quota keys. Supports global keys and provider-qualified keys. Empty shows provider labels only and never filters the popup. |
| Show provider in panel | Includes each selected provider icon in the compact system tray summary. |
| Show used percent in panel | Includes usage percentages in compact output. |
| Show credits in panel | Includes available credits as `Cr` values in each compact provider block. Disabled by default. |
| Show email in widget | Shows the account email in the popup when available. |
| Fetch provider status | Requests and displays provider status information. |
| Show local cost summary | Displays local CodexBar token and cost estimates when available. |

## Data and Privacy

The widget runs `kodexbar-quotas usage --format json --json-only` locally by default and renders the returned JSON. The engine uses upstream `codexbar` as a per-provider fallback. Optional cost summaries come from upstream `codexbar cost`. This repository does not add a provider backend, credential store, telemetry service, or remote account service.

CodexBar owns provider authentication, provider configuration, API calls, and CLI probing. Review the [CodexBar project](https://github.com/steipete/CodexBar) for its supported providers and data handling.

### AI CLI Control integration

KodexBar Suite can launch the separately installed [ai-cli-control](https://github.com/Karasowl/ai-cli-control) selector from its popup AI button or Plasma context menu. The widget does not embed the selector or copy its provider logic. `Open AI CLI Control` starts `ai` in its own graphical window. `Update all AI CLIs` runs `ai --update all` through Konsole with the terminal held open so the version and result summary remain visible. Set `AI CLI Control` in widget settings when the executable is not named `ai` or is outside `PATH`.

## Validation

Run the deterministic fixture tests and static checks:

```sh
scripts/validate.sh
```

The validation checks JSON, XML, fixture logic, QML linting, preserved asset hashes, common secret patterns, documentation punctuation, and whitespace errors.

To inspect CLI data before debugging the widget:

```sh
codexbar usage --format json --json-only --source auto | python3 -m json.tool
```

## Troubleshooting

| Symptom | Likely fix |
| --- | --- |
| Widget says `No data` | Run the CLI command above and confirm it returns usable JSON. |
| A listed provider shows `ERR` | Configure that provider in CodexBar or inspect its CLI error. |
| A provider is absent from the system tray | Add its exact CodexBar provider ID to `Compact providers`, or leave the setting empty. |
| A quota is absent from the system tray | Add its global or provider-qualified key to `Compact quotas`. The popup shows the detected title needed to derive an extra quota key. |
| The system tray says `No selection` | Correct a provider or quota key in the compact settings. The popup remains complete. |
| Provider works in a terminal but not in Plasma | Configure the full path to `codexbar` because Plasma may not inherit the shell `PATH`. |
| Status is absent | Enable **Fetch provider status**. |
| Cost summary is absent | Run `codexbar cost --format json --pretty` and verify local cost data exists. |

## Attribution and License

Maintained by [Karasowl](https://github.com/Karasowl). Based on the original KodexBar project by [tylxr](https://github.com/tylxr59).

Usage data is supplied by the independent [CodexBar CLI](https://github.com/steipete/CodexBar). See [NOTICE.md](NOTICE.md) for attribution details.

Licensed under the original MIT license. See [LICENSE](LICENSE). The notice file supplements the license and does not replace it.
