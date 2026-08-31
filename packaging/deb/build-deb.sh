#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
root_dir="$(cd -- "${script_dir}/../.." && pwd)"
version="$(python3 -c 'import json, pathlib, sys; print(json.loads(pathlib.Path(sys.argv[1]).read_text())["KPlugin"]["Version"])' "${root_dir}/packages/kodexbar/metadata.json" 2>/dev/null)"
release="${KODEXBAR_PACKAGE_RELEASE:-1}"
output_dir="${KODEXBAR_OUTPUT_DIR:-${script_dir}/dist}"

if [[ ! "$version" =~ ^[0-9]+([.][0-9]+)+$ ]]; then
    printf 'Invalid package version: %s\n' "$version" >&2
    exit 1
fi
if [[ ! "$release" =~ ^[0-9]+$ ]]; then
    printf 'Invalid package release: %s\n' "$release" >&2
    exit 1
fi
if ! command -v dpkg-deb >/dev/null 2>&1; then
    printf 'dpkg-deb is required to build the Debian package.\n' >&2
    exit 1
fi

build_dir="$(mktemp -d "${TMPDIR:-/tmp}/kodexbar-deb.XXXXXX")"
trap 'rm -rf -- "$build_dir"' EXIT
package_root="${build_dir}/kodexbar-suite"

bash "${root_dir}/packaging/system/stage-package.sh" "$package_root"
install -d -- "${package_root}/DEBIAN"
installed_size="$(du -sk "${package_root}/usr" | awk '{print $1}')"
sed \
    -e "s/@VERSION@/${version}/g" \
    -e "s/@RELEASE@/${release}/g" \
    -e "s/@INSTALLED_SIZE@/${installed_size}/g" \
    "${script_dir}/control.in" > "${package_root}/DEBIAN/control"
install -m 0755 -- "${script_dir}/postinst" "${package_root}/DEBIAN/postinst"

install -d -- "$output_dir"
artifact="${output_dir}/kodexbar-suite_${version}-${release}_all.deb"
dpkg-deb --root-owner-group --build "$package_root" "$artifact" >&2
printf '%s\n' "$artifact"
