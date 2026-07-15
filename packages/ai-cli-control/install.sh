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
quotas_source="${script_dir}/kodexbar-quotas"
panel_source="${script_dir}/kodexbar-panel"
recover_source="${script_dir}/recover.py"
uninstall_source="${script_dir}/uninstall.sh"
adapters_dir="${script_dir}/skills-adapters"
data_dir="${HOME}/.local/share/ai-cli-control"
installed_ai="${data_dir}/ai"
installed_quotas="${data_dir}/kodexbar-quotas"
installed_panel="${data_dir}/kodexbar-panel"
installed_recover="${data_dir}/recover.py"
installed_uninstall="${data_dir}/uninstall.sh"
marker="${data_dir}/.ai-cli-control-owner"
bin_dir="${HOME}/.local/bin"
target="${bin_dir}/ai"
quotas_target="${bin_dir}/kodexbar-quotas"
panel_target="${bin_dir}/kodexbar-panel"

if [[ ! -f "$source_file" || ! -f "$quotas_source" || ! -f "$panel_source" || ! -f "$recover_source" || ! -f "$uninstall_source" ]]; then
    say "No se encontraron los archivos fuente de instalación." "Installation source files were not found." >&2
    exit 1
fi

check_owned_link() {
    local link="$1"
    local destination="$2"
    if [[ -e "$link" || -L "$link" ]]; then
        if [[ ! -L "$link" || "$(readlink -- "$link")" != "$destination" ]]; then
            say "No se reemplazó ${link} porque pertenece a otra instalación." "Did not replace ${link} because it belongs to another installation." >&2
            exit 1
        fi
    fi
}

install_adapter() {
    local cli_home="$1"
    local cli_name="$2"
    local source="${adapters_dir}/${cli_name}/recover-chat/SKILL.md"
    local target_dir="${cli_home}/skills/recover-chat"
    local target_marker="${target_dir}/.ai-cli-control-owner"
    if [[ ! -d "$cli_home" ]]; then
        return
    fi
    if [[ -e "$target_dir" || -L "$target_dir" ]]; then
        if [[ -L "$target_dir" || ! -d "$target_dir" || ! -f "$target_marker" || "$(<"$target_marker")" != 'ai-cli-control' ]]; then
            say "Se omitió ${target_dir} porque no pertenece a ai-cli-control." "Skipped ${target_dir} because it is not owned by ai-cli-control." >&2
            return
        fi
    fi
    mkdir -p -- "$target_dir"
    install -m 0644 -- "$source" "${target_dir}/SKILL.md"
    printf '%s\n' 'ai-cli-control' > "$target_marker"
    say "Se instaló el adaptador recover-chat para ${cli_name}." "Installed the recover-chat adapter for ${cli_name}."
}
check_owned_link "$target" "$installed_ai"
check_owned_link "$quotas_target" "$installed_quotas"
check_owned_link "$panel_target" "$installed_panel"

mkdir -p -- "$data_dir" "$bin_dir"
printf '%s\n' 'ai-cli-control' > "$marker"
install -m 0755 -- "$source_file" "$installed_ai"
install -m 0755 -- "$quotas_source" "$installed_quotas"
install -m 0755 -- "$panel_source" "$installed_panel"
install -m 0755 -- "$recover_source" "$installed_recover"
install -m 0755 -- "$uninstall_source" "$installed_uninstall"
if [[ ! -L "$target" ]]; then
    ln -s -- "$installed_ai" "$target"
fi
if [[ ! -L "$quotas_target" ]]; then
    ln -s -- "$installed_quotas" "$quotas_target"
fi
if [[ ! -L "$panel_target" ]]; then
    ln -s -- "$installed_panel" "$panel_target"
fi
install_adapter "${HOME}/.claude" "claude"
install_adapter "${HOME}/.grok" "grok"
say "ai se instaló en ${target}" "ai installed at ${target}"
say "kodexbar-quotas se instaló en ${quotas_target}" "kodexbar-quotas installed at ${quotas_target}"
say "kodexbar-panel se instaló en ${panel_target}" "kodexbar-panel installed at ${panel_target}"
