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

data_dir="${HOME}/.local/share/ai-cli-control"
installed_ai="${data_dir}/ai"
marker="${data_dir}/.ai-cli-control-owner"
target="${HOME}/.local/bin/ai"

remove_owned_adapter() {
    local cli_home="$1"
    local target_dir="${cli_home}/skills/recover-chat"
    local target_marker="${target_dir}/.ai-cli-control-owner"
    if [[ ! -e "$target_dir" && ! -L "$target_dir" ]]; then
        return
    fi
    if [[ -L "$target_dir" || ! -d "$target_dir" || ! -f "$target_marker" || "$(<"$target_marker")" != 'ai-cli-control' ]]; then
        say "No se eliminó ${target_dir} porque no pertenece a ai-cli-control." "Did not remove ${target_dir} because it is not owned by ai-cli-control." >&2
        return
    fi
    rm -rf -- "$target_dir"
    say "Se eliminó el adaptador recover-chat de ${cli_home}." "Removed the recover-chat adapter from ${cli_home}."
}

if [[ ! -e "$marker" || "$(<"$marker")" != 'ai-cli-control' ]]; then
    if [[ -e "$target" || -L "$target" ]]; then
        say "No se eliminó ${target} porque no pertenece a ai-cli-control." "Did not remove ${target} because it does not belong to ai-cli-control." >&2
        exit 1
    fi
    say "ai-cli-control ya estaba desinstalado." "ai-cli-control was already uninstalled."
    exit 0
fi
if [[ -e "$target" || -L "$target" ]]; then
    if [[ ! -L "$target" || "$(readlink -- "$target")" != "$installed_ai" ]]; then
        say "No se eliminó ${target} porque no pertenece a ai-cli-control." "Did not remove ${target} because it does not belong to ai-cli-control." >&2
        exit 1
    fi
    rm -- "$target"
fi
remove_owned_adapter "${HOME}/.claude"
remove_owned_adapter "${HOME}/.grok"
rm -rf -- "$data_dir"
say "ai-cli-control se desinstaló." "ai-cli-control uninstalled."
