"""Small built-in runtime adapters, isolated from inventory and control policy."""

from __future__ import annotations

import math
import re
from urllib.parse import quote


METRIC_LINE = re.compile(r"^(llamacpp:(?:requests_processing|predicted_tokens_seconds))\s+([+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?)\s*$")


def llama_metrics(text):
    """Return the two router gauges only when their samples are plain finite numbers."""
    values = {}
    for line in text.splitlines():
        match = METRIC_LINE.fullmatch(line)
        if not match:
            continue
        name, raw_value = match.groups()
        value = float(raw_value)
        if not math.isfinite(value) or name in values:
            continue
        values[name] = value
    return values


def is_router_placeholder(name, item, status):
    """Hide only llama.cpp's synthetic default preset, never a real default model."""
    if name != "default" or safe_text(item.get("source")) != "preset" or not isinstance(status, dict):
        return False
    preset = safe_text(status.get("preset"))
    args = status.get("args")
    if not re.match(r"^\[default\](?:\r?\n|$)", preset) or not isinstance(args, list):
        return False
    return not any(str(argument) == "--model" or str(argument).startswith("--model=") for argument in args)


def safe_text(value):
    return str(value or "").strip()


def builtin_drivers(api):
    request_json, request_text, make_model = api["request_json"], api.get("request_text"), api["make_model"]
    safe_name = api["safe_name"]

    def llama(runtime):
        raw = request_json(runtime.endpoint + "/models")
        values = raw.get("data", raw.get("models", raw)) if isinstance(raw, dict) else raw
        if not isinstance(values, list):
            raise api["LocalAIError"]("runtime returned an invalid model catalog")
        models = []
        for item in values:
            item = item if isinstance(item, dict) else {"id": item}
            name = safe_text(item.get("id") or item.get("name") or item.get("model"))
            if not name:
                continue
            status_payload = item.get("status") if isinstance(item.get("status"), dict) else item.get("state")
            status_object = status_payload if isinstance(status_payload, dict) else None
            if is_router_placeholder(name, item, status_object):
                continue
            status = safe_text(status_object.get("value") if status_object else (item.get("status") or item.get("state"))).lower()
            requests = item.get("requests_processing", item.get("active_requests", item.get("requests", 0)))
            try:
                active = status == "active" or float(requests) > 0
            except (TypeError, ValueError):
                active = status == "active"
            state = {"loaded": "loaded", "loading": "loading", "unloaded": "installed", "sleeping": "installed",
                     "slept": "installed", "unloading": "unloading", "active": "active"}.get(status, "unknown")
            metric_value = None
            if state in {"loaded", "active"} and request_text is not None:
                try:
                    gauges = llama_metrics(request_text(runtime.endpoint + "/metrics?model=" + quote(name, safe="")))
                    if gauges.get("llamacpp:requests_processing", 0) > 0:
                        active, state = True, "active"
                    if state == "active":
                        predicted = gauges.get("llamacpp:predicted_tokens_seconds")
                        if predicted is not None and predicted >= 0:
                            metric_value = predicted
                except api["LocalAIError"]:
                    pass
            if active and state == "loaded":
                state = "active"
            detail = "sleeping" if status in {"sleeping", "slept"} else status
            models.append(make_model("llama_cpp", name, state=state, declared_kind=safe_text(item.get("type")),
                metric_value=metric_value, metric_unit="tok/s" if metric_value is not None else "", activity=state == "active",
                memory={"vramMiB": item.get("vram_mib", item.get("vramMiB")), "ramMiB": item.get("ram_mib", item.get("ramMiB"))},
                capabilities={"mount": True, "unmount": True, "releaseRuntime": False, "stopRuntime": False}, detail=detail))
        return models, {"id": "llama_cpp", "state": "connected", "activityProbe": True,
            "capabilities": {"releaseRuntime": False, "stopRuntime": False}}

    def ollama(runtime):
        tags, running = request_json(runtime.endpoint + "/api/tags"), request_json(runtime.endpoint + "/api/ps")
        catalog = tags.get("models", []) if isinstance(tags, dict) else []
        active = running.get("models", []) if isinstance(running, dict) else []
        by_name = {safe_name(item.get("name") or item.get("model")): item for item in active if isinstance(item, dict)}
        models = []
        for item in catalog if isinstance(catalog, list) else []:
            item = item if isinstance(item, dict) else {"name": item}
            name = safe_name(item.get("name") or item.get("model"))
            if name:
                resident = by_name.get(name)
                models.append(make_model("ollama", name, state="loaded" if resident else "installed", activity=False,
                    memory={"vramMiB": resident.get("size_vram", 0) / (1024 * 1024) if resident else None},
                    capabilities={"mount": False, "unmount": True, "releaseRuntime": False, "stopRuntime": False}, detail="resident" if resident else "installed"))
        return models, {"id": "ollama", "state": "connected", "capabilities": {"releaseRuntime": False, "stopRuntime": False}}

    def openai_catalog(runtime, name):
        raw = request_json(runtime.endpoint + "/v1/models")
        catalog = raw.get("data", []) if isinstance(raw, dict) else []
        models = [make_model(name, safe_name(item.get("id")), state="loaded", declared_kind=safe_name(item.get("type")),
            capabilities={"mount": False, "unmount": False, "releaseRuntime": False, "stopRuntime": False}, detail="served")
            for item in catalog if isinstance(item, dict) and safe_name(item.get("id"))]
        return models, {"id": name, "state": "connected", "capabilities": {"releaseRuntime": False, "stopRuntime": False}}

    def comfyui(runtime):
        request_json(runtime.endpoint + "/system_stats")
        queue = request_json(runtime.endpoint + "/queue")
        busy = bool(queue.get("queue_running") or queue.get("queue_pending")) if isinstance(queue, dict) else False
        return [], {"id": "comfyui", "state": "connected", "queueActive": busy,
            "activityProbe": True,
            "releaseWarning": "Affects every model resident in ComfyUI. Individual residency is not exposed.",
            "stopImpact": "Stops ComfyUI and every resident model after its queue is empty.",
            "capabilities": {"releaseRuntime": not busy, "stopRuntime": False}}

    return {"llama_cpp": llama, "ollama": ollama, "lm_studio": lambda runtime: openai_catalog(runtime, "lm_studio"),
        "comfyui": comfyui, "vllm": lambda runtime: openai_catalog(runtime, "vllm")}
