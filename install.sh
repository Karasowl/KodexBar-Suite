#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
kodexbar_dir="${script_dir}/packages/kodexbar"
ai_dir="${script_dir}/packages/ai-cli-control"
plugin_type="Plasma/Applet"
plugin_id="org.kde.plasma.kodexbar"
state_dir="${XDG_STATE_HOME:-${HOME}/.local/state}/kodexbar-suite"
marker="${state_dir}/install-marker"

if [[ ! -d "$kodexbar_dir" || ! -d "$ai_dir" ]]; then
    printf 'Package directories are missing.\n' >&2
    exit 1
fi
if ! command -v kpackagetool6 >/dev/null 2>&1; then
    printf 'kpackagetool6 is required to install KodexBar Suite.\n' >&2
    exit 1
fi

if kpackagetool6 -t "$plugin_type" -s "$plugin_id" >/dev/null 2>&1; then
    kpackagetool6 -t "$plugin_type" -u "$kodexbar_dir"
else
    kpackagetool6 -t "$plugin_type" -i "$kodexbar_dir"
fi

bash "${ai_dir}/install.sh"

mkdir -p -- "$state_dir"
{
    printf 'product=KodexBar Suite\n'
    printf 'plugin_id=%s\n' "$plugin_id"
    printf 'plugin_type=%s\n' "$plugin_type"
    printf 'source=%s\n' "$script_dir"
} > "$marker"

printf 'KodexBar Suite installed.\n'
