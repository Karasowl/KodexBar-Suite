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
kodexbar_dir="${script_dir}/packages/kodexbar"
ai_dir="${script_dir}/packages/ai-cli-control"
plugin_type="Plasma/Applet"
plugin_id="org.kde.plasma.kodexbar"
state_dir="${XDG_STATE_HOME:-${HOME}/.local/state}/kodexbar-suite"
marker="${state_dir}/install-marker"
local_bin="${HOME}/.local/bin"

if [[ ! -d "$kodexbar_dir" || ! -d "$ai_dir" ]]; then
    say "Faltan los directorios de los paquetes." "Package directories are missing." >&2
    exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
    say "Se necesita python3 3.10 o posterior." "python3 3.10 or newer is required." >&2
    exit 1
fi
if ! python3 -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 10) else 1)'; then
    say "python3 es demasiado antiguo. KodexBar Suite necesita 3.10 o posterior." \
        "python3 is too old. KodexBar Suite needs 3.10 or newer." >&2
    exit 1
fi

plasma_installed=0
if command -v kpackagetool6 >/dev/null 2>&1; then
    if kpackagetool6 -t "$plugin_type" -s "$plugin_id" >/dev/null 2>&1; then
        kpackagetool6 -t "$plugin_type" -u "$kodexbar_dir"
    else
        kpackagetool6 -t "$plugin_type" -i "$kodexbar_dir"
    fi
    plasma_installed=1
else
    say "No está kpackagetool6. Se instala el motor, la bandeja y el panel, sin el widget de Plasma." \
        "kpackagetool6 was not found. Installing the data engine, tray, and panel tools without the Plasma widget."
    say "En GNOME o COSMIC usa kodexbar-tray. En Hyprland usa kodexbar-panel --waybar-snippet. En XFCE usa kodexbar-panel --format text --pango." \
        "On GNOME or COSMIC use kodexbar-tray. On Hyprland use kodexbar-panel --waybar-snippet. On XFCE use kodexbar-panel --format text --pango."
fi

bash "${ai_dir}/install.sh"

case ":${PATH}:" in
    *:"${local_bin}":*)
        ;;
    *)
        say "Aviso: ${local_bin} no está en PATH. Añádelo para encontrar ai, kodexbar-quotas, kodexbar-panel y kodexbar-tray." \
            "Note: ${local_bin} is not on PATH. Add it so ai, kodexbar-quotas, kodexbar-panel, and kodexbar-tray can be found."
        ;;
esac

mkdir -p -- "$state_dir"
{
    printf 'product=KodexBar Suite\n'
    printf 'plugin_id=%s\n' "$plugin_id"
    printf 'plugin_type=%s\n' "$plugin_type"
    printf 'source=%s\n' "$script_dir"
    printf 'plasma=%s\n' "$plasma_installed"
} > "$marker"

if [[ "$plasma_installed" -eq 1 ]]; then
    bash "${script_dir}/packaging/aur/reload-plasma-after-upgrade" --current-user
    say "KodexBar Suite instalado (widget de Plasma y motor de datos)." \
        "KodexBar Suite installed (Plasma widget and data engine)."
else
    say "KodexBar Suite instalado (solo motor de datos, sin widget de Plasma)." \
        "KodexBar Suite installed (data engine only, no Plasma widget)."
fi
