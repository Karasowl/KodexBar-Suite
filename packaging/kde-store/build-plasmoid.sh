#!/usr/bin/env bash
# Build a KDE Store-ready .plasmoid zip from packages/kodexbar.
# Version is read from metadata.json so it is not encoded twice.
# Uses Python's zipfile (stdlib) so the host does not need the zip CLI.
# Archive contents are an explicit distributable list: metadata.json and contents/.
# ZIP bytes are normalized (fixed timestamps from git HEAD, modes, entry order).
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

# Prefer SOURCE_DATE_EPOCH, else git HEAD commit time of the tree (not mtime).
if [[ -n "${SOURCE_DATE_EPOCH:-}" ]]; then
  stamp="${SOURCE_DATE_EPOCH}"
else
  stamp="$(git -C "$repo_root" log -1 --format=%ct HEAD)"
fi

plugin_id="org.kde.plasma.kodexbar"
output="${dist_dir}/${plugin_id}-${version}.plasmoid"

mkdir -p -- "$dist_dir"
rm -f -- "$output"

python3 - "$source_dir" "$output" "$stamp" <<'PY'
from __future__ import annotations

import sys
import time
import zipfile
from pathlib import Path

source = Path(sys.argv[1]).resolve()
output = Path(sys.argv[2]).resolve()
stamp = int(sys.argv[3])
date_time = time.gmtime(stamp)[:6]

# Explicit distributable set only (H6): metadata.json and contents/.
allowed_roots = ("metadata.json", "contents")
files: list[Path] = []
metadata_path = source / "metadata.json"
if not metadata_path.is_file():
    raise SystemExit(f"missing required file: {metadata_path}")
files.append(metadata_path)
contents_dir = source / "contents"
if not contents_dir.is_dir():
    raise SystemExit(f"missing required directory: {contents_dir}")
for path in sorted(contents_dir.rglob("*")):
    if not path.is_file():
        continue
    if "__pycache__" in path.parts or path.suffix == ".pyc":
        continue
    files.append(path)

# Deterministic order by archive name.
files.sort(key=lambda p: str(p.relative_to(source)).replace("\\", "/"))

# Normalize modes: dirs would be 0o755, regular files 0o644 (no execute bits).
file_mode = 0o644

with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
    for path in files:
        arcname = str(path.relative_to(source)).replace("\\", "/")
        info = zipfile.ZipInfo(filename=arcname, date_time=date_time)
        info.compress_type = zipfile.ZIP_DEFLATED
        info.external_attr = (file_mode & 0xFFFF) << 16
        info.create_system = 3  # Unix
        archive.writestr(info, path.read_bytes(), compress_type=zipfile.ZIP_DEFLATED, compresslevel=9)

print(f"Wrote {output}")
print(f"source_date_epoch={stamp}")
print(f"entries={len(files)}")
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
forbidden_prefixes = (
    "tests/",
    "scripts/",
    ".github/",
    ".gitignore",
    "design-qa.md",
    "screenshot.png",
    "README",
    "CHANGELOG",
    "CONTRIBUTING",
    "LICENSE",
    "NOTICE",
)
leaks = [
    name
    for name in names
    if name.startswith(("tests/", "scripts/", ".github/"))
    or name in {".gitignore", "design-qa.md", "screenshot.png"}
    or name.startswith(("README", "CHANGELOG", "CONTRIBUTING", "LICENSE", "NOTICE"))
]
print(f"leaked_dev_files={leaks}")
for name in names[:40]:
    print(name)
if "metadata.json" not in names:
    raise SystemExit("metadata.json missing from archive root")
if leaks:
    raise SystemExit(f"excluded paths leaked into archive: {leaks}")
allowed = all(name == "metadata.json" or name.startswith("contents/") for name in names)
if not allowed:
    bad = [n for n in names if n != "metadata.json" and not n.startswith("contents/")]
    raise SystemExit(f"archive contains non-distributable paths: {bad}")
PY
