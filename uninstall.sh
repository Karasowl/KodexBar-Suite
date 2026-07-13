#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ai_uninstall="${script_dir}/packages/ai-cli-control/uninstall.sh"
plugin_type="Plasma/Applet"
plugin_id="org.kde.plasma.kodexbar"
state_dir="${XDG_STATE_HOME:-${HOME}/.local/state}/kodexbar-suite"
marker="${state_dir}/install-marker"

if [[ ! -f "$marker" ]]; then
    printf 'No root-owned KodexBar Suite installation was recorded. Nothing was removed.\n'
    exit 0
fi
if ! grep -qx 'product=KodexBar Suite' "$marker" || ! grep -qx "plugin_id=${plugin_id}" "$marker"; then
    printf 'The installation marker is not recognized. Nothing was removed.\n' >&2
    exit 1
fi
if ! command -v kpackagetool6 >/dev/null 2>&1; then
    printf 'kpackagetool6 is required to remove KodexBar Suite.\n' >&2
    exit 1
fi

if plugin_info="$(kpackagetool6 -t "$plugin_type" -s "$plugin_id" 2>&1)"; then
    if ! grep -q 'Name[[:space:]]*:[[:space:]]*KodexBar Suite' <<< "$plugin_info"; then
        printf 'The installed Plasma package is not identified as KodexBar Suite. Nothing was removed.\n' >&2
        exit 1
    fi
    kpackagetool6 -t "$plugin_type" -r "$plugin_id"
else
    printf 'The KodexBar Suite Plasma package is already absent.\n'
fi

bash "$ai_uninstall"
rm -f -- "$marker"
rmdir --ignore-fail-on-non-empty "$state_dir" 2>/dev/null || true
printf 'KodexBar Suite uninstalled.\n'
