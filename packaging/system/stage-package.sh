#!/usr/bin/env bash
set -euo pipefail

destination="${1:-}"
if [[ -z "$destination" || "$destination" == "/" ]]; then
    printf 'Usage: %s DESTDIR\n' "${0##*/}" >&2
    printf 'DESTDIR must be a package staging directory, never /.\n' >&2
    exit 2
fi
if [[ -e "$destination" && ! -d "$destination" ]]; then
    printf 'DESTDIR is not a directory: %s\n' "$destination" >&2
    exit 2
fi
if [[ -d "$destination" && -n "$(find "$destination" -mindepth 1 -print -quit)" ]]; then
    printf 'DESTDIR must be empty: %s\n' "$destination" >&2
    exit 2
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
root_dir="$(cd -- "${script_dir}/../.." && pwd)"
ai_dir="${root_dir}/packages/ai-cli-control"
kodexbar_dir="${root_dir}/packages/kodexbar"

required_files=(
    "${ai_dir}/ai"
    "${ai_dir}/kodexbar-quotas"
    "${ai_dir}/kodexbar-panel"
    "${ai_dir}/kodexbar-tray"
    "${ai_dir}/local-ai"
    "${ai_dir}/kodexbar-skills"
    "${ai_dir}/recover.py"
    "${kodexbar_dir}/metadata.json"
    "${root_dir}/packaging/aur/reload-plasma-after-upgrade"
)
for required_file in "${required_files[@]}"; do
    if [[ ! -f "$required_file" ]]; then
        printf 'Required package source is missing: %s\n' "$required_file" >&2
        exit 1
    fi
done

payload="${destination}/usr/lib/kodexbar-suite/ai-cli-control"
install -d -- "$payload"
install -m 0755 -- \
    "${ai_dir}/ai" \
    "${ai_dir}/kodexbar-quotas" \
    "${ai_dir}/kodexbar-panel" \
    "${ai_dir}/kodexbar-tray" \
    "${ai_dir}/local-ai" \
    "${ai_dir}/kodexbar-skills" \
    "${ai_dir}/recover.py" \
    "$payload/"

install -d -- "${payload}/local_ai_drivers"
install -m 0644 -- \
    "${ai_dir}/local_ai_drivers/__init__.py" \
    "${ai_dir}/local_ai_drivers/builtin.py" \
    "${ai_dir}/local_ai_drivers/descriptors.py" \
    "${payload}/local_ai_drivers/"

install -d -- "${destination}/usr/bin"
for executable in ai kodexbar-quotas kodexbar-panel kodexbar-tray local-ai kodexbar-skills; do
    ln -sfn -- "../lib/kodexbar-suite/ai-cli-control/${executable}" \
        "${destination}/usr/bin/${executable}"
done

plasmoid="${destination}/usr/share/plasma/plasmoids/org.kde.plasma.kodexbar"
install -d -- "$plasmoid"
install -m 0644 -- "${kodexbar_dir}/metadata.json" "$plasmoid/"
cp -a -- "${kodexbar_dir}/contents" "${plasmoid}/contents"

install -Dm0755 -- \
    "${root_dir}/packaging/aur/reload-plasma-after-upgrade" \
    "${destination}/usr/lib/kodexbar-suite/reload-plasma-after-upgrade"

icon_dir="${destination}/usr/share/icons/hicolor/scalable/apps"
install -d -- "$icon_dir"
install -m 0644 -- \
    "${ai_dir}/icons/kodexbar-tray-ok.svg" \
    "${ai_dir}/icons/kodexbar-tray-warning.svg" \
    "${ai_dir}/icons/kodexbar-tray-critical.svg" \
    "$icon_dir/"

license_dir="${destination}/usr/share/licenses/kodexbar-suite"
install -d -- "$license_dir"
install -m 0644 -- "${root_dir}/LICENSE" "${root_dir}/NOTICE.md" "$license_dir/"
install -m 0644 -- "${ai_dir}/LICENSE" "${license_dir}/LICENSE.ai-cli-control"
install -m 0644 -- "${kodexbar_dir}/LICENSE" "${license_dir}/LICENSE.kodexbar"

doc_dir="${destination}/usr/share/doc/kodexbar-suite"
install -d -- "${doc_dir}/local_ai_drivers"
install -m 0644 -- \
    "${root_dir}/README.md" \
    "${root_dir}/README.es.md" \
    "${root_dir}/INSTALL.md" \
    "${root_dir}/INSTALL.es.md" \
    "$doc_dir/"
install -m 0644 -- \
    "${ai_dir}/local_ai_drivers/CONTRACT.md" \
    "${doc_dir}/local_ai_drivers/"
