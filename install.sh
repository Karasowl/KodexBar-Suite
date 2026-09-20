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
        kpackagetool6 -t "$plugin_type" -u "$kodexbar_dir" \
            || kpackagetool6 -t "$plugin_type" -i "$kodexbar_dir"
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

# Backend de cuotas: CLI codexbar oficial (steipete/CodexBar). Sin él el widget
# y la bandeja quedan en estado de error, así que se instala automáticamente.
cli_version=""
cli_sha256=""
cli_pkgbuild="${script_dir}/packaging/aur-codexbar-cli-bin/PKGBUILD"
if [[ -f "$cli_pkgbuild" ]]; then
    while IFS= read -r cli_line; do
        case "$cli_line" in
            pkgver=*)
                cli_version="${cli_line#pkgver=}"
                cli_version="${cli_version//\"/}"
                ;;
            sha256sums_x86_64=*)
                cli_sha256="${cli_line#sha256sums_x86_64=(}"
                cli_sha256="${cli_sha256%%)*}"
                cli_sha256="${cli_sha256//\'}"
                ;;
        esac
    done < "$cli_pkgbuild"
fi
cli_manual="https://github.com/steipete/CodexBar/releases"

install_codexbar_cli() {
    if command -v codexbar >/dev/null 2>&1; then
        say "CLI codexbar ya presente en $(command -v codexbar)." \
            "codexbar CLI already present at $(command -v codexbar)."
        return 0
    fi
    if ! command -v tar >/dev/null 2>&1; then
        say "Falta tar para instalar el CLI codexbar automático. Descárgalo de ${cli_manual}." \
            "tar is missing so the automatic codexbar CLI install cannot run. Download it from ${cli_manual}." >&2
        return 1
    fi
    if [[ -z "$cli_version" || -z "$cli_sha256" ]]; then
        say "No pude determinar la versión del CLI codexbar. Instálalo desde ${cli_manual} o el widget quedará en error." \
            "Could not determine the codexbar CLI version. Install it from ${cli_manual} or the widget will stay in error state." >&2
        return 1
    fi
    case "$(uname -s):$(uname -m)" in
        Linux:x86_64) cli_arch="x86_64";;
        Linux:aarch64|Linux:arm64) cli_arch="aarch64";;
        *)
            say "Instalación automática del CLI codexbar no soportada en $(uname -s) $(uname -m). Descárgalo de ${cli_manual}." \
                "Automatic codexbar CLI install is not supported on $(uname -s) $(uname -m). Download it from ${cli_manual}." >&2
            return 1
            ;;
    esac
    local cli_url="https://github.com/steipete/CodexBar/releases/download/v${cli_version}/CodexBarCLI-v${cli_version}-linux-${cli_arch}.tar.gz"
    local cli_tmp
    cli_tmp="$(mktemp -d)"
    say "Instalando el CLI codexbar ${cli_version} (backend de cuotas)..." \
        "Installing codexbar CLI ${cli_version} (quota backend)..."
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "${cli_tmp}/cli.tar.gz" "$cli_url" || { rm -rf "$cli_tmp"; return 1; }
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "${cli_tmp}/cli.tar.gz" "$cli_url" || { rm -rf "$cli_tmp"; return 1; }
    elif command -v python3 >/dev/null 2>&1; then
        python3 -c 'import sys,urllib.request; urllib.request.urlretrieve(sys.argv[1],sys.argv[2])' "$cli_url" "${cli_tmp}/cli.tar.gz" || { rm -rf "$cli_tmp"; return 1; }
    else
        say "No encontré curl, wget ni python3 para descargar el CLI codexbar. Descárgalo de ${cli_manual}." \
            "Could not find curl, wget, or python3 to download the codexbar CLI. Download it from ${cli_manual}." >&2
        rm -rf "$cli_tmp"
        return 1
    fi
    local cli_sum=""
    if command -v sha256sum >/dev/null 2>&1; then
        cli_sum="$(sha256sum "${cli_tmp}/cli.tar.gz" | awk '{print $1}')"
    elif command -v shasum >/dev/null 2>&1; then
        cli_sum="$(shasum -a 256 "${cli_tmp}/cli.tar.gz" | awk '{print $1}')"
    elif command -v python3 >/dev/null 2>&1; then
        cli_sum="$(python3 -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "${cli_tmp}/cli.tar.gz")"
    fi
    if [[ "$cli_sum" != "$cli_sha256" ]]; then
        say "La suma del CLI descargado no coincide. No se instaló. Descarga manual: ${cli_manual}" \
            "Checksum mismatch for the downloaded CLI. Not installed. Manual download: ${cli_manual}" >&2
        rm -rf "$cli_tmp"
        return 1
    fi
    mkdir -p "${HOME}/.local/lib/codexbar-cli" "${local_bin}"
    tar -xzf "${cli_tmp}/cli.tar.gz" -C "${cli_tmp}" || { rm -rf "$cli_tmp"; return 1; }
    install -m 755 "${cli_tmp}/CodexBarCLI" "${HOME}/.local/lib/codexbar-cli/CodexBarCLI"
    if [[ -f "${cli_tmp}/VERSION" ]]; then
        install -m 644 "${cli_tmp}/VERSION" "${HOME}/.local/lib/codexbar-cli/VERSION"
    fi
    ln -sfn "../lib/codexbar-cli/CodexBarCLI" "${local_bin}/codexbar"
    rm -rf "$cli_tmp"
    say "CLI codexbar instalado en ${local_bin}/codexbar." \
        "codexbar CLI installed at ${local_bin}/codexbar."
}

install_codexbar_cli || say "Sin el CLI codexbar el widget y la bandeja mostrarán error hasta que lo instales." \
    "Without the codexbar CLI the widget and tray will show an error until you install it."

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
