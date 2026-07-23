"""Small built-in runtime adapters, isolated from inventory and control policy."""

from __future__ import annotations


def builtin_drivers(api):
    request_json, safe_name, make_model = api["request_json"], api["safe_name"], api["make_model"]

    def llama(runtime):
        raw = request_json(runtime.endpoint + "/models")
        values = raw.get("data", raw.get("models", raw)) if isinstance(raw, dict) else raw
        if not isinstance(values, list):
            raise api["LocalAIError"]("runtime returned an invalid model catalog")
        models = []
        for item in values:
            item = item if isinstance(item, dict) else {"id": item}
            name = safe_name(item.get("id") or item.get("name") or item.get("model"))
            if not name:
                continue
            status = safe_name(item.get("status") or item.get("state")).lower()
            state = {"loaded": "loaded", "loading": "loading", "unloaded": "installed", "sleeping": "loaded", "unloading": "unloading"}.get(status, "unknown")
            active = status in {"loading", "unloading"} or bool(item.get("active_requests") or item.get("requests"))
            if active and state == "loaded":
                state = "active"
            models.append(make_model("llama_cpp", name, state=state, declared_kind=safe_name(item.get("type")),
                metric_value=item.get("tokens_per_second", item.get("tokensPerSecond")), metric_unit="tok/s", activity=active,
                memory={"vramMiB": item.get("vram_mib", item.get("vramMiB")), "ramMiB": item.get("ram_mib", item.get("ramMiB"))},
                capabilities={"mount": True, "unmount": True, "releaseRuntime": False, "stopRuntime": False}, detail=status))
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
