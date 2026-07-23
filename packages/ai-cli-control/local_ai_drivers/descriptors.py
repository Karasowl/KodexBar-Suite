"""Data-only adapters for simple OpenAI-compatible model catalogs.

Descriptors cannot name a Python module, command, shell expression, or action.
They only describe a relative JSON endpoint and a runtime id.  This keeps user
configuration extensible without treating it as executable code.
"""

from __future__ import annotations

import json
from pathlib import Path


SYSTEM_DESCRIPTOR_DIR = Path("/usr/lib/kodexbar/local-ai-drivers")


def descriptor_paths(config):
    paths = []
    if SYSTEM_DESCRIPTOR_DIR.is_dir() and not (SYSTEM_DESCRIPTOR_DIR.stat().st_mode & 0o022):
        paths.extend(sorted(SYSTEM_DESCRIPTOR_DIR.glob("*.json")))
    for value in config.get("adapterDescriptors", []):
        if isinstance(value, str) and value.endswith(".json"):
            paths.append(Path(value).expanduser())
    return paths


def descriptor_drivers(config, api):
    drivers = {}
    for path in descriptor_paths(config):
        try:
            raw = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        runtime_id, kind, list_path = raw.get("id"), raw.get("kind"), raw.get("modelsPath", "/v1/models")
        if not (isinstance(runtime_id, str) and isinstance(kind, str) and isinstance(list_path, str)
                and kind == "openai-model-catalog" and list_path.startswith("/") and ":" not in list_path):
            continue

        def catalog(runtime, runtime_id=runtime_id, list_path=list_path):
            raw_models = api["request_json"](runtime.endpoint + list_path)
            values = raw_models.get("data", []) if isinstance(raw_models, dict) else []
            models = [api["make_model"](runtime_id, api["safe_name"](item.get("id")), state="loaded",
                declared_kind=api["safe_name"](item.get("type")),
                capabilities={"mount": False, "unmount": False, "releaseRuntime": False, "stopRuntime": False},
                detail="served by declarative adapter")
                for item in values if isinstance(item, dict) and api["safe_name"](item.get("id"))]
            return models, {"id": runtime_id, "state": "connected", "capabilities": {"releaseRuntime": False, "stopRuntime": False}}

        drivers[runtime_id] = catalog
    return drivers
