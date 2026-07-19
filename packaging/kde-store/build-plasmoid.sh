#!/usr/bin/env bash
# Build a KDE Store-ready .plasmoid zip from packages/kodexbar.
# Version is read from metadata.json so it is not encoded twice.
# Uses Python's zipfile (stdlib) so the host does not need the zip CLI.
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

python3 - "$source_dir" "$output" <<'PY'
from __future__ import annotations

import sys
import zipfile
from pathlib import Path

source = Path(sys.argv[1]).resolve()
output = Path(sys.argv[2]).resolve()
exclude_roots = {"tests", "scripts"}

with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as archive:
    for path in sorted(source.rglob("*")):
        if not path.is_file():
            continue
        relative = path.relative_to(source)
        if relative.parts and relative.parts[0] in exclude_roots:
            continue
        if "__pycache__" in relative.parts or path.suffix == ".pyc":
            continue
        archive.write(path, arcname=str(relative).replace("\\", "/"))

print(f"Wrote {output}")
PY

python3 - "$output" <<'PY'
import sys
import zipfile
from pathlib import Path

path = Path(sys.argv[1])
with zipfile.ZipFile(path) as archive:
    names = archive.namelist()
print(f"entries={len(names)}")
print(f"metadata_at_root={'metadata.json' in names}")
leaks = [name for name in names if name.startswith(("tests/", "scripts/"))]
print(f"leaked_tests_or_scripts={leaks}")
for name in names[:40]:
    print(name)
if "metadata.json" not in names:
    raise SystemExit("metadata.json missing from archive root")
if leaks:
    raise SystemExit(f"excluded paths leaked into archive: {leaks}")
PY
