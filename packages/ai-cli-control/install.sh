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
source_file="${script_dir}/ai"
uninstall_source="${script_dir}/uninstall.sh"
data_dir="${HOME}/.local/share/ai-cli-control"
installed_ai="${data_dir}/ai"
installed_uninstall="${data_dir}/uninstall.sh"
marker="${data_dir}/.ai-cli-control-owner"
bin_dir="${HOME}/.local/bin"
target="${bin_dir}/ai"

if [[ ! -f "$source_file" || ! -f "$uninstall_source" ]]; then
    say "No se encontraron los archivos fuente de instalación." "Installation source files were not found." >&2
    exit 1
fi
if [[ -e "$target" || -L "$target" ]]; then
    if [[ ! -L "$target" || "$(readlink -- "$target")" != "$installed_ai" ]]; then
        say "No se reemplazó ${target} porque pertenece a otra instalación." "Did not replace ${target} because it belongs to another installation." >&2
        exit 1
    fi
fi

mkdir -p -- "$data_dir" "$bin_dir"
printf '%s\n' 'ai-cli-control' > "$marker"
install -m 0755 -- "$source_file" "$installed_ai"
install -m 0755 -- "$uninstall_source" "$installed_uninstall"
if [[ ! -L "$target" ]]; then
    ln -s -- "$installed_ai" "$target"
fi
say "ai se instaló en ${target}" "ai installed at ${target}"
