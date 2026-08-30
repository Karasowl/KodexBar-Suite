#!/usr/bin/env bash
set -euo pipefail

language="en"
for variable in LC_ALL LC_MESSAGES LANGUAGE LANG; do
    value="${!variable:-}"
    if [[ -n "$value" ]]; then
        [[ "${value,,}" == es* ]] && language="es"
        break
    fi
done

say() {
    if [[ "$language" == "es" ]]; then
        printf '%s\n' "$1"
    else
        printf '%s\n' "$2"
    fi
}

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ai_uninstall="${script_dir}/packages/ai-cli-control/uninstall.sh"
plugin_type="Plasma/Applet"
plugin_id="org.kde.plasma.kodexbar"
state_dir="${XDG_STATE_HOME:-${HOME}/.local/state}/kodexbar-suite"
marker="${state_dir}/install-marker"

if [[ ! -f "$marker" ]]; then
    say "No hay una instalación de KodexBar Suite registrada por el instalador raíz. No se eliminó nada." \
        "No root-owned KodexBar Suite installation was recorded. Nothing was removed."
    exit 0
fi
if ! grep -qx 'product=KodexBar Suite' "$marker" || ! grep -qx "plugin_id=${plugin_id}" "$marker"; then
    say "El marcador de instalación no se reconoce. No se eliminó nada." \
        "The installation marker is not recognized. Nothing was removed." >&2
    exit 1
fi

plasma_installed=1
if grep -qx 'plasma=0' "$marker"; then
    plasma_installed=0
fi

remove_plasma_widget() {
    if plugin_info="$(kpackagetool6 -t "$plugin_type" -s "$plugin_id" 2>&1)"; then
        if ! grep -q 'Name[[:space:]]*:[[:space:]]*KodexBar Suite' <<< "$plugin_info"; then
            say "El paquete de Plasma instalado no se identifica como KodexBar Suite. No se eliminó el widget." \
                "The installed Plasma package is not identified as KodexBar Suite. The widget was not removed." >&2
            return 1
        fi
        kpackagetool6 -t "$plugin_type" -r "$plugin_id"
    else
        say "El paquete de Plasma de KodexBar Suite ya no está." \
            "The KodexBar Suite Plasma package is already absent."
    fi
    return 0
}

if [[ "$plasma_installed" -eq 1 ]]; then
    if command -v kpackagetool6 >/dev/null 2>&1; then
        remove_plasma_widget
    else
        say "No está kpackagetool6. Se deja el widget de Plasma si existe y se quita el motor de datos." \
            "kpackagetool6 was not found. Leaving any Plasma widget in place and removing the data engine."
    fi
fi

bash "$ai_uninstall"
rm -f -- "$marker"
rmdir --ignore-fail-on-non-empty "$state_dir" 2>/dev/null || true
say "KodexBar Suite desinstalado." "KodexBar Suite uninstalled."
