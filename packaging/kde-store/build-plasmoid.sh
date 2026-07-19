#!/usr/bin/env bash
# Build a KDE Store-ready .plasmoid zip from packages/kodexbar.
# Version is read from metadata.json so it is not encoded twice.
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/../.." && pwd)"
source_dir="${repo_root}/packages/kodexbar"
metadata="${source_dir}/metadata.json"
dist_dir="${script_dir}/dist"

if [[ ! -f "$metadata" ]]; then
  printf 'Missing plasmoid metadata: %s\n' "$metadata" >&2
  exit 1
fi

version="$(
  python3 - "$metadata" <<'PY'
import json
import sys
from pathlib import Path

payload = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
version = payload.get("KPlugin", {}).get("Version")
if not isinstance(version, str) or not version.strip():
    raise SystemExit("metadata.json is missing KPlugin.Version")
print(version.strip())
PY
)"

plugin_id="org.kde.plasma.kodexbar"
output="${dist_dir}/${plugin_id}-${version}.plasmoid"

mkdir -p -- "$dist_dir"
rm -f -- "$output"

# Zip contents of packages/kodexbar with metadata.json at the archive root.
# Exclude tests/ and scripts/ (development-only surfaces).
(
  cd -- "$source_dir"
  # shellcheck disable=SC2035
  zip -r -q "$output" . \
    -x 'tests/*' \
    -x 'tests/**' \
    -x 'scripts/*' \
    -x 'scripts/**' \
    -x '*/__pycache__/*' \
    -x '*/*.pyc'
)

printf 'Wrote %s\n' "$output"
unzip -l "$output" | head -n 40
