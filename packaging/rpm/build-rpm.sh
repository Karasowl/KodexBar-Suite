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
for tool in date gzip rpmbuild sed tar; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        printf '%s is required to build the RPM package.\n' "$tool" >&2
        exit 1
    fi
done

build_dir="$(mktemp -d "${TMPDIR:-/tmp}/kodexbar-rpm.XXXXXX")"
trap 'rm -rf -- "$build_dir"' EXIT
top_dir="${build_dir}/rpmbuild"
source_tree="${build_dir}/kodexbar-suite-${version}"
install -d -- "${top_dir}/BUILD" "${top_dir}/BUILDROOT" "${top_dir}/RPMS" \
    "${top_dir}/SOURCES" "${top_dir}/SPECS" "${top_dir}/SRPMS" "$source_tree"

install -m 0644 -- \
    "${root_dir}/LICENSE" \
    "${root_dir}/NOTICE.md" \
    "${root_dir}/README.md" \
    "${root_dir}/README.es.md" \
    "${root_dir}/INSTALL.md" \
    "${root_dir}/INSTALL.es.md" \
    "$source_tree/"
install -d -- \
    "${source_tree}/packages/ai-cli-control/local_ai_drivers" \
    "${source_tree}/packages/ai-cli-control/icons" \
    "${source_tree}/packages/kodexbar" \
    "${source_tree}/packaging/aur" \
    "${source_tree}/packaging/system"
install -m 0755 -- \
    "${root_dir}/packages/ai-cli-control/ai" \
    "${root_dir}/packages/ai-cli-control/kodexbar-quotas" \
    "${root_dir}/packages/ai-cli-control/kodexbar-panel" \
    "${root_dir}/packages/ai-cli-control/kodexbar-tray" \
    "${root_dir}/packages/ai-cli-control/local-ai" \
    "${root_dir}/packages/ai-cli-control/kodexbar-skills" \
    "${root_dir}/packages/ai-cli-control/recover.py" \
    "${source_tree}/packages/ai-cli-control/"
install -m 0644 -- \
    "${root_dir}/packages/ai-cli-control/LICENSE" \
    "${source_tree}/packages/ai-cli-control/"
install -m 0644 -- \
    "${root_dir}/packages/ai-cli-control/local_ai_drivers/__init__.py" \
    "${root_dir}/packages/ai-cli-control/local_ai_drivers/builtin.py" \
    "${root_dir}/packages/ai-cli-control/local_ai_drivers/descriptors.py" \
    "${root_dir}/packages/ai-cli-control/local_ai_drivers/CONTRACT.md" \
    "${source_tree}/packages/ai-cli-control/local_ai_drivers/"
install -m 0644 -- \
    "${root_dir}/packages/ai-cli-control/icons/kodexbar-tray-ok.svg" \
    "${root_dir}/packages/ai-cli-control/icons/kodexbar-tray-warning.svg" \
    "${root_dir}/packages/ai-cli-control/icons/kodexbar-tray-critical.svg" \
    "${source_tree}/packages/ai-cli-control/icons/"
install -m 0644 -- \
    "${root_dir}/packages/kodexbar/metadata.json" \
    "${root_dir}/packages/kodexbar/LICENSE" \
    "${source_tree}/packages/kodexbar/"
cp -a -- "${root_dir}/packages/kodexbar/contents" "${source_tree}/packages/kodexbar/contents"
install -m 0755 -- \
    "${root_dir}/packaging/aur/reload-plasma-after-upgrade" \
    "${source_tree}/packaging/aur/"
install -m 0755 -- \
    "${root_dir}/packaging/system/stage-package.sh" \
    "${source_tree}/packaging/system/"

source_date_epoch="${SOURCE_DATE_EPOCH:-$(git -C "$root_dir" log -1 --format=%ct 2>/dev/null || printf '0')}"
if [[ ! "$source_date_epoch" =~ ^[0-9]+$ ]]; then
    printf 'Invalid SOURCE_DATE_EPOCH: %s\n' "$source_date_epoch" >&2
    exit 1
fi
export SOURCE_DATE_EPOCH="$source_date_epoch"
changelog_date="$(LC_ALL=C date -u --date="@${source_date_epoch}" '+%a %b %d %Y')"
tar --sort=name --owner=0 --group=0 --numeric-owner --mtime="@${source_date_epoch}" \
    -C "$build_dir" -czf "${top_dir}/SOURCES/kodexbar-suite-${version}.tar.gz" \
    "kodexbar-suite-${version}"
sed \
    -e "s/@VERSION@/${version}/g" \
    -e "s/@RELEASE@/${release}/g" \
    -e "s/@CHANGELOG_DATE@/${changelog_date}/g" \
    "${script_dir}/kodexbar-suite.spec.in" > "${top_dir}/SPECS/kodexbar-suite.spec"

rpmbuild --define "_topdir ${top_dir}" -bb "${top_dir}/SPECS/kodexbar-suite.spec" >&2
rpm_artifact="$(find "${top_dir}/RPMS" -type f -name '*.rpm' -print -quit)"
if [[ -z "$rpm_artifact" ]]; then
    printf 'rpmbuild did not produce an RPM artifact.\n' >&2
    exit 1
fi
install -d -- "$output_dir"
artifact="${output_dir}/${rpm_artifact##*/}"
install -m 0644 -- "$rpm_artifact" "$artifact"
printf '%s\n' "$artifact"
