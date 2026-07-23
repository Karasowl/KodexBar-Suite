"""Contract tests for the portable local-ai JSON surface."""

from __future__ import annotations

import importlib.machinery
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
FIXTURES = Path(__file__).resolve().parent / "fixtures"
OPENCODE_TEMPLATE = ROOT / "examples" / "opencode.local.jsonc"
loader = importlib.machinery.SourceFileLoader("local_ai", str(ROOT / "local-ai"))
spec = importlib.util.spec_from_loader(loader.name, loader)
local_ai = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = local_ai
loader.exec_module(local_ai)


class LocalAIContractTests(unittest.TestCase):
    def fixture(self, name: str) -> object:
        return json.loads((FIXTURES / name).read_text(encoding="utf-8"))

    def text_fixture(self, name: str) -> str:
        return (FIXTURES / name).read_text(encoding="utf-8")

    def test_classification_uses_declaration_before_heuristics(self) -> None:
        self.assertEqual(local_ai.classify("qwen-video", "embedding"), ("embedding", "declared"))
        self.assertEqual(local_ai.classify("qwen-video"), ("video", "heuristic"))
        self.assertEqual(local_ai.classify("opaque-weight"), ("unknown", "unknown"))

    def test_classification_uses_structured_metadata_and_specific_model_rules(self) -> None:
        self.assertEqual(local_ai.classify("opaque", metadata={"general.architecture": "ltxv"}), ("video", "metadata"))
        self.assertEqual(local_ai.classify("opaque", metadata={"license": "video only"}), ("unknown", "unknown"))
        cases = {
            "/models/diffusion_models/ltx_transformer.safetensors": "video",
            "/models/foo_video_vae.safetensors": "video",
            "/models/foo_audio_vae.safetensors": "audio",
            "/models/embeddings_connectors/clip.safetensors": "embedding",
            "/models/mmproj-Qwen.gguf": "vision",
            "/models/Devstral-Small.gguf": "llm",
            "/models/GLM-4.gguf": "llm",
            "/models/RealESRGAN_x4plus.pth": "image",
            "/models/4x-UltraSharp.pth": "image",
            "/models/lightx2v.safetensors": "video",
            "/models/Chatterbox/s3gen.safetensors": "audio",
            "/models/Chatterbox/t3_cfg.safetensors": "audio",
        }
        for location, expected in cases.items():
            with self.subTest(location=location):
                self.assertEqual(local_ai.classify(Path(location).stem, location=location)[0], expected)

    def test_opencode_template_denies_sensitive_reads_and_destructive_git(self) -> None:
        template = json.loads(OPENCODE_TEMPLATE.read_text(encoding="utf-8"))
        sensitive = {".env", ".env.*", "*.env", ".git-credentials", ".npmrc", ".pypirc", ".netrc", ".aws/**", ".ssh/**", "*credentials*", "*.pem", "*.key", "*.p12"}
        destructive = {"git push", "git push *", "git merge", "git merge *", "git reset --hard *", "git clean *", "git rebase *", "git branch -D *", "git tag -d *", "npm publish *", "rm -rf *"}
        for agent in template["agent"].values():
            read, bash = agent["permission"]["read"], agent["permission"]["bash"]
            self.assertEqual(read["*"], "allow")
            self.assertTrue(all(read[item] == "deny" for item in sensitive))
            self.assertTrue(all(bash[item] == "deny" for item in destructive))

    def test_inventory_normalizes_common_runtime_fixtures(self) -> None:
        responses = {
            "/models": self.fixture("local-ai-llama-models.json"),
            "/api/tags": self.fixture("local-ai-ollama-tags.json"),
            "/api/ps": self.fixture("local-ai-ollama-ps.json"),
            "/v1/models": self.fixture("local-ai-lmstudio-models.json"),
            "/system_stats": self.fixture("local-ai-comfyui-system-stats.json"),
            "/queue": self.fixture("local-ai-comfyui-queue-empty.json"),
        }
        original, original_text = local_ai.request_json, local_ai.request_text
        local_ai.request_json = lambda url, **kwargs: next(value for suffix, value in responses.items() if url.endswith(suffix))
        local_ai.request_text = lambda url, **kwargs: self.text_fixture("local-ai-llama-metrics-active.json")
        try:
            config = local_ai.default_config()
            config["knownRoots"] = []
            for runtime in config["runtimes"].values():
                runtime["service"] = "local-ai.service"
            data = local_ai.inventory(config)
        finally:
            local_ai.request_json, local_ai.request_text = original, original_text
        by_runtime = {item["runtime"] for item in data["models"]}
        self.assertTrue({"llama_cpp", "ollama", "lm_studio", "vllm"}.issubset(by_runtime))
        llama = next(item for item in data["models"] if item["runtime"] == "llama_cpp" and item["state"] == "active")
        self.assertEqual(llama["metric"], {"value": 31.25, "unit": "tok/s", "source": "runtime"})
        self.assertEqual(next(item for item in data["models"] if item["runtime"] == "ollama" and item["state"] == "installed")["metric"], None)
        comfy = next(item for item in data["runtimes"] if item["id"] == "comfyui")
        self.assertTrue(comfy["capabilities"]["releaseRuntime"])
        stoppable = {item["id"] for item in data["runtimes"] if item["capabilities"].get("stopRuntime")}
        self.assertEqual(stoppable, {"llama_cpp", "comfyui"})

    def test_inventory_builds_driver_registry_once(self) -> None:
        original = local_ai.driver_registry
        calls = []
        local_ai.driver_registry = lambda config: (calls.append(config) or original(config))
        try:
            config = local_ai.default_config()
            config["knownRoots"] = []
            config["observeGpuProcesses"] = False
            for runtime in config["runtimes"].values(): runtime["enabled"] = False
            local_ai.inventory(config)
        finally:
            local_ai.driver_registry = original
        self.assertEqual(len(calls), 1)

    def test_configured_scan_never_needs_a_home_wide_walk(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "weights"
            root.mkdir()
            (root / "Qwen3-Coder.gguf").write_bytes(b"GGUF")
            config = local_ai.default_config()
            config["roots"] = [str(root)]
            config["knownRoots"] = []
            config["observeGpuProcesses"] = False
            for runtime in config["runtimes"].values():
                runtime["enabled"] = False
            data = local_ai.inventory(config)
        self.assertEqual(len(data["models"]), 1)
        self.assertEqual(data["models"][0]["kind"], "llm")
        self.assertEqual(data["models"][0]["state"], "installed")

    def test_discovery_keeps_same_basename_at_distinct_strong_locations(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            configured = Path(temporary) / "configured" / "shared.gguf"
            independent = Path(temporary) / "independent" / "shared.gguf"
            configured.parent.mkdir(parents=True)
            independent.parent.mkdir(parents=True)
            configured.write_bytes(b"GGUF")
            independent.write_bytes(b"GGUF")
            original_registry = local_ai.driver_registry
            local_ai.driver_registry = lambda config: {"llama_cpp": lambda runtime: (
                [local_ai.make_model("llama_cpp", "shared", location=str(configured), state="loaded")],
                {"id": "llama_cpp", "state": "connected", "capabilities": {}})}
            try:
                config = local_ai.default_config()
                config["roots"] = [str(configured.parent), str(independent.parent)]
                config["knownRoots"] = []
                config["observeGpuProcesses"] = False
                for key, runtime in config["runtimes"].items(): runtime["enabled"] = key == "llama_cpp"
                data = local_ai.inventory(config)
            finally:
                local_ai.driver_registry = original_registry
        self.assertEqual({item["location"] for item in data["models"]}, {str(configured), str(independent)})

    def test_discovery_omits_only_the_exact_runtime_location(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            configured = Path(temporary) / "configured" / "shared.gguf"
            configured.parent.mkdir(parents=True)
            configured.write_bytes(b"GGUF")
            original_registry = local_ai.driver_registry
            local_ai.driver_registry = lambda config: {"llama_cpp": lambda runtime: (
                [local_ai.make_model("llama_cpp", "shared", location=str(configured), state="loaded")],
                {"id": "llama_cpp", "state": "connected", "capabilities": {}})}
            try:
                config = local_ai.default_config()
                config["roots"] = [str(configured.parent)]
                config["knownRoots"] = []
                config["observeGpuProcesses"] = False
                for key, runtime in config["runtimes"].items(): runtime["enabled"] = key == "llama_cpp"
                data = local_ai.inventory(config)
            finally:
                local_ai.driver_registry = original_registry
        self.assertEqual([(item["runtime"], item["location"]) for item in data["models"]], [("llama_cpp", str(configured))])

    def test_metadata_and_path_classification_prevent_known_false_llms(self) -> None:
        self.assertEqual(local_ai.classify("qwen-image-Q4", location="/weights/qwen-image.gguf"), ("image", "heuristic"))
        self.assertEqual(local_ai.classify("umt5-xxl-encoder", location="/models/text_encoders/umt5.gguf"), ("embedding", "heuristic"))
        self.assertEqual(local_ai.classify("ltx_audio_vae", location="/models/vae/ltx_audio_vae.safetensors"), ("audio", "heuristic"))
        self.assertEqual(local_ai.classify("opaque", metadata={"general.architecture": "text-to-speech"}), ("audio", "metadata"))

    def test_endpoint_rejects_file_scheme_and_oversized_responses(self) -> None:
        with self.assertRaisesRegex(local_ai.LocalAIError, "http or https"):
            local_ai.request_json("file:///tmp/models")
        with self.assertRaisesRegex(local_ai.LocalAIError, "http or https"):
            local_ai.request_text("file:///tmp/metrics")
        class Response:
            def __enter__(self): return self
            def __exit__(self, *args): return False
            def read(self, size): return b"x" * size
        original = local_ai.urlopen
        local_ai.urlopen = lambda *args, **kwargs: Response()
        try:
            with self.assertRaisesRegex(local_ai.LocalAIError, "size limit"):
                local_ai.request_json("http://127.0.0.1:9/models")
            with self.assertRaisesRegex(local_ai.LocalAIError, "size limit"):
                local_ai.request_text("http://127.0.0.1:9/metrics")
        finally:
            local_ai.urlopen = original

    def test_llama_router_object_status_filters_only_the_placeholder(self) -> None:
        original_json, original_text = local_ai.request_json, local_ai.request_text
        calls: list[str] = []
        local_ai.request_json = lambda *args, **kwargs: self.fixture("local-ai-llama-router-models.json")
        local_ai.request_text = lambda url, **kwargs: (calls.append(url) or self.text_fixture("local-ai-llama-metrics-active.json"))
        try:
            models, _ = local_ai.models_from_llama(local_ai.Runtime("llama_cpp", "llama_cpp", "http://127.0.0.1:18100"))
        finally:
            local_ai.request_json, local_ai.request_text = original_json, original_text
        self.assertEqual([item["name"] for item in models], ["qwen-worker", "gpt-oss"])
        active = next(item for item in models if item["name"] == "qwen-worker")
        self.assertEqual(active["state"], "active")
        self.assertTrue(active["activity"])
        self.assertEqual(active["metric"], {"value": 31.25, "unit": "tok/s", "source": "runtime"})
        self.assertEqual(next(item for item in models if item["name"] == "gpt-oss")["state"], "installed")
        self.assertEqual(calls, ["http://127.0.0.1:18100/metrics?model=qwen-worker"])

    def test_llama_loaded_model_is_inactive_without_runtime_requests(self) -> None:
        original_json, original_text = local_ai.request_json, local_ai.request_text
        local_ai.request_json = lambda *args, **kwargs: {"data": [{"id": "worker", "status": {"value": "loaded", "args": ["--model", "worker.gguf"]}}]}
        local_ai.request_text = lambda *args, **kwargs: self.text_fixture("local-ai-llama-metrics-idle.json")
        try:
            models, _ = local_ai.models_from_llama(local_ai.Runtime("llama_cpp", "llama_cpp", "http://127.0.0.1:18100"))
        finally:
            local_ai.request_json, local_ai.request_text = original_json, original_text
        self.assertEqual(models[0]["state"], "loaded")
        self.assertFalse(models[0]["activity"])
        self.assertIsNone(models[0]["metric"])

    def test_llama_real_model_named_default_is_not_filtered(self) -> None:
        original_json = local_ai.request_json
        local_ai.request_json = lambda *args, **kwargs: {"data": [{"id": "default", "source": "preset", "status": {
            "value": "unloaded", "args": ["--model", "/models/default.gguf"], "preset": "[default]\\nmodel = /models/default.gguf\\n"}}]}
        try:
            models, _ = local_ai.models_from_llama(local_ai.Runtime("llama_cpp", "llama_cpp", "http://127.0.0.1:18100"))
        finally:
            local_ai.request_json = original_json
        self.assertEqual(models[0]["name"], "default")
        self.assertEqual(models[0]["state"], "installed")

    def test_llama_metrics_failures_and_oversized_body_leave_inventory_usable(self) -> None:
        original_json, original_text = local_ai.request_json, local_ai.request_text
        local_ai.request_json = lambda *args, **kwargs: {"data": [{"id": "worker", "status": {"value": "loaded", "args": ["--model", "worker.gguf"]}}]}
        try:
            for detail in ("HTTP 400: metrics disabled", "HTTP 501: not implemented", "runtime response exceeds the safe size limit"):
                with self.subTest(detail=detail):
                    local_ai.request_text = lambda *args, _detail=detail, **kwargs: (_ for _ in ()).throw(local_ai.LocalAIError(_detail))
                    models, state = local_ai.models_from_llama(local_ai.Runtime("llama_cpp", "llama_cpp", "http://127.0.0.1:18100"))
                    self.assertEqual(models[0]["state"], "loaded")
                    self.assertFalse(models[0]["activity"])
                    self.assertIsNone(models[0]["metric"])
                    self.assertFalse(models[0]["evidence"]["activityKnown"])
                    self.assertFalse(state["activityProbe"])
        finally:
            local_ai.request_json, local_ai.request_text = original_json, original_text

    def test_opencode_catalog_reads_current_llama_catalog_without_writing(self) -> None:
        original = local_ai.request_json
        local_ai.request_json = lambda *args, **kwargs: {"data": [{"id": "qwen-worker", "status": "unloaded"}]}
        try:
            payload = local_ai.opencode_catalog(local_ai.default_config())
        finally:
            local_ai.request_json = original
        provider = payload["provider"]["local-router"]
        self.assertEqual(provider["npm"], "@ai-sdk/openai-compatible")
        self.assertIn("qwen-worker", provider["models"])

    def test_ollama_resident_model_is_loaded_not_active(self) -> None:
        original = local_ai.request_json
        local_ai.request_json = lambda url, **kwargs: self.fixture("local-ai-ollama-ps.json") if url.endswith("/api/ps") else self.fixture("local-ai-ollama-tags.json")
        try:
            models, _ = local_ai.models_from_ollama(local_ai.Runtime("ollama", "ollama", "http://127.0.0.1:11434"))
        finally:
            local_ai.request_json = original
        resident = next(item for item in models if item["name"] == "llama3.2")
        self.assertEqual(resident["state"], "loaded")
        self.assertFalse(resident["activity"])

    def test_vllm_fixture_uses_its_runtime_identity(self) -> None:
        original = local_ai.request_json
        local_ai.request_json = lambda *args, **kwargs: self.fixture("local-ai-vllm-models.json")
        try:
            models, _ = local_ai.models_from_vllm(local_ai.Runtime("vllm", "vllm", "http://127.0.0.1:8000"))
        finally:
            local_ai.request_json = original
        self.assertEqual(models[0]["runtime"], "vllm")
        self.assertEqual(models[0]["name"], "Qwen3-Worker")

    def test_comfy_queue_blocks_global_release(self) -> None:
        original = local_ai.request_json
        local_ai.request_json = lambda url, **kwargs: self.fixture("local-ai-comfyui-queue-active.json") if url.endswith("/queue") else self.fixture("local-ai-comfyui-system-stats.json")
        try:
            config = local_ai.default_config()
            for key, runtime in config["runtimes"].items(): runtime["enabled"] = key == "comfyui"
            with self.assertRaisesRegex(local_ai.LocalAIError, "running or pending"):
                local_ai.action(config, "release", "comfyui", confirmed=True)
        finally:
            local_ai.request_json = original

    def test_active_requests_block_unmount_and_global_release(self) -> None:
        original, original_text = local_ai.request_json, local_ai.request_text
        local_ai.request_json = lambda url, **kwargs: self.fixture("local-ai-llama-models.json")
        local_ai.request_text = lambda *args, **kwargs: self.text_fixture("local-ai-llama-metrics-active.json")
        try:
            config = local_ai.default_config()
            for key, runtime in config["runtimes"].items():
                runtime["enabled"] = key == "llama_cpp"
            with self.assertRaisesRegex(local_ai.LocalAIError, "requests are active"):
                local_ai.action(config, "unmount", "llama_cpp", "qwen3-coder")
        finally:
            local_ai.request_json, local_ai.request_text = original, original_text

    def test_llama_unmount_rejects_when_metrics_cannot_verify_activity(self) -> None:
        calls: list[tuple[str, str, object]] = []
        original_json, original_text = local_ai.request_json, local_ai.request_text

        def fake(url: str, method: str = "GET", payload: object = None, **kwargs: object) -> object:
            calls.append((url, method, payload))
            if url.endswith("/models"):
                return {"data": [{"id": "worker", "status": "loaded"}]}
            return {}

        local_ai.request_json = fake
        local_ai.request_text = lambda *args, **kwargs: (_ for _ in ()).throw(local_ai.LocalAIError("metrics disabled"))
        try:
            config = local_ai.default_config()
            config["observeGpuProcesses"] = False
            for key, runtime in config["runtimes"].items(): runtime["enabled"] = key == "llama_cpp"
            with self.assertRaisesRegex(local_ai.LocalAIError, "could not verify llama.cpp activity"):
                local_ai.action(config, "unmount", "llama_cpp", "worker")
        finally:
            local_ai.request_json, local_ai.request_text = original_json, original_text
        self.assertFalse(any(method == "POST" and url.endswith("/models/unload") for url, method, _ in calls))

    def test_llama_unmount_uses_one_snapshot_when_later_model_metrics_fail(self) -> None:
        calls: list[tuple[str, str, object]] = []
        metrics_calls = 0
        original_json, original_text = local_ai.request_json, local_ai.request_text

        def fake(url: str, method: str = "GET", payload: object = None, **kwargs: object) -> object:
            calls.append((url, method, payload))
            if url.endswith("/models"):
                return {"data": [{"id": "worker", "status": "loaded"}, {"id": "other", "status": "loaded"}]}
            return {}

        def metrics(*args: object, **kwargs: object) -> str:
            nonlocal metrics_calls
            metrics_calls += 1
            if metrics_calls == 1:
                return self.text_fixture("local-ai-llama-metrics-idle.json")
            raise local_ai.LocalAIError("metrics disabled after the first model")

        local_ai.request_json, local_ai.request_text = fake, metrics
        try:
            config = local_ai.default_config()
            for key, runtime in config["runtimes"].items(): runtime["enabled"] = key == "llama_cpp"
            with self.assertRaisesRegex(local_ai.LocalAIError, "could not verify llama.cpp activity"):
                local_ai.action(config, "unmount", "llama_cpp", "worker")
        finally:
            local_ai.request_json, local_ai.request_text = original_json, original_text
        self.assertEqual(sum(url.endswith("/models") and method == "GET" for url, method, _ in calls), 1)
        self.assertEqual(metrics_calls, 2)
        self.assertFalse(any(method == "POST" and url.endswith("/models/unload") for url, method, _ in calls))

    def test_stop_uses_one_snapshot_before_systemd(self) -> None:
        original_driver, original_run = local_ai.DRIVERS["llama_cpp"], local_ai.subprocess.run
        snapshot_reads = 0
        service_calls: list[list[str]] = []

        def driver(runtime: local_ai.Runtime) -> tuple[list[dict[str, object]], dict[str, object]]:
            nonlocal snapshot_reads
            snapshot_reads += 1
            return ([local_ai.make_model("llama_cpp", "worker", state="installed")],
                    {"id": "llama_cpp", "state": "connected", "activityProbe": True, "capabilities": {}})

        class Result:
            returncode = 0
            stdout = "loaded\n"

        def run(command: list[str], **kwargs: object) -> Result:
            service_calls.append(command)
            self.assertEqual(snapshot_reads, 1, "stop must not refresh the activity snapshot before systemd")
            return Result()

        local_ai.DRIVERS["llama_cpp"], local_ai.subprocess.run = driver, run
        try:
            config = local_ai.default_config()
            for key, runtime in config["runtimes"].items(): runtime["enabled"] = key == "llama_cpp"
            config["runtimes"]["llama_cpp"]["service"] = "llama-router.service"
            result = local_ai.action(config, "stop", "llama_cpp", confirmed=True)
        finally:
            local_ai.DRIVERS["llama_cpp"], local_ai.subprocess.run = original_driver, original_run
        self.assertTrue(result["ok"])
        self.assertEqual(service_calls[-1], ["systemctl", "--user", "stop", "llama-router.service"])

    def test_unmount_resolves_the_normalized_id_to_the_runtime_name(self) -> None:
        calls: list[tuple[str, str, object]] = []
        original, original_text = local_ai.request_json, local_ai.request_text

        def fake(url: str, method: str = "GET", payload: object = None, **kwargs: object) -> object:
            calls.append((url, method, payload))
            if url.endswith("/models"):
                return {"data": [{"id": "gpt-oss", "status": "loaded"}]}
            return {}

        local_ai.request_json = fake
        local_ai.request_text = lambda *args, **kwargs: self.text_fixture("local-ai-llama-metrics-idle.json")
        try:
            config = local_ai.default_config()
            for key, runtime in config["runtimes"].items():
                runtime["enabled"] = key == "llama_cpp"
            runtime_id = local_ai.model_id("llama_cpp", "gpt-oss")
            result = local_ai.action(config, "unmount", "llama_cpp", runtime_id)
        finally:
            local_ai.request_json, local_ai.request_text = original, original_text
        self.assertTrue(result["ok"])
        self.assertIn(("http://127.0.0.1:18100/models/unload", "POST", {"model": "gpt-oss"}), calls)

    def test_comfy_release_uses_only_its_documented_runtime_api(self) -> None:
        calls: list[tuple[str, str, object]] = []
        original = local_ai.request_json

        def fake(url: str, method: str = "GET", payload: object = None, **kwargs: object) -> object:
            calls.append((url, method, payload))
            if url.endswith("/system_stats"):
                return self.fixture("local-ai-comfyui-system-stats.json")
            return {}

        local_ai.request_json = fake
        try:
            config = local_ai.default_config()
            for key, runtime in config["runtimes"].items():
                runtime["enabled"] = key == "comfyui"
            result = local_ai.action(config, "release", "comfyui", confirmed=True)
        finally:
            local_ai.request_json = original
        self.assertTrue(result["ok"])
        self.assertIn(("http://127.0.0.1:8188/free", "POST", {"unload_models": True, "free_memory": True}), calls)

    def test_comfy_release_rejects_unknown_queue_shape(self) -> None:
        original = local_ai.request_json
        local_ai.request_json = lambda *args, **kwargs: []
        try:
            config = local_ai.default_config()
            for key, runtime in config["runtimes"].items(): runtime["enabled"] = key == "comfyui"
            with self.assertRaisesRegex(local_ai.LocalAIError, "could not verify"):
                local_ai.action(config, "release", "comfyui", confirmed=True)
        finally:
            local_ai.request_json = original

    def test_stop_rechecks_comfy_queue_before_systemd(self) -> None:
        original_request, original_run = local_ai.request_json, local_ai.subprocess.run
        local_ai.request_json = lambda url, **kwargs: self.fixture("local-ai-comfyui-queue-active.json") if url.endswith("/queue") else self.fixture("local-ai-comfyui-system-stats.json")
        local_ai.subprocess.run = lambda *args, **kwargs: self.fail("systemd must not run while ComfyUI is busy")
        try:
            config = local_ai.default_config()
            for key, runtime in config["runtimes"].items():
                runtime["enabled"] = key == "comfyui"
            config["runtimes"]["comfyui"]["service"] = "comfyui.service"
            with self.assertRaisesRegex(local_ai.LocalAIError, "running or pending"):
                local_ai.action(config, "stop", "comfyui", confirmed=True)
        finally:
            local_ai.request_json, local_ai.subprocess.run = original_request, original_run

    def test_stop_rejects_runtime_without_reliable_probe_even_with_service(self) -> None:
        original_request, original_run = local_ai.request_json, local_ai.subprocess.run
        local_ai.request_json = lambda url, **kwargs: self.fixture("local-ai-ollama-ps.json") if url.endswith("/api/ps") else self.fixture("local-ai-ollama-tags.json")
        local_ai.subprocess.run = lambda *args, **kwargs: self.fail("unprobed runtime must not reach systemd")
        try:
            config = local_ai.default_config()
            for key, runtime in config["runtimes"].items(): runtime["enabled"] = key == "ollama"
            config["runtimes"]["ollama"]["service"] = "ollama.service"
            with self.assertRaisesRegex(local_ai.LocalAIError, "reliable activity probe"):
                local_ai.action(config, "stop", "ollama", confirmed=True)
        finally:
            local_ai.request_json, local_ai.subprocess.run = original_request, original_run

    def test_disconnected_runtime_has_honest_state(self) -> None:
        original = local_ai.request_json
        local_ai.request_json = lambda *args, **kwargs: (_ for _ in ()).throw(local_ai.LocalAIError("connection refused"))
        try:
            config = local_ai.default_config()
            config["knownRoots"] = []
            for key, runtime in config["runtimes"].items():
                runtime["enabled"] = key == "ollama"
            data = local_ai.inventory(config)
        finally:
            local_ai.request_json = original
        ollama = next(item for item in data["runtimes"] if item["id"] == "ollama")
        self.assertEqual(ollama["state"], "disconnected")

    def test_gpu_observer_ignores_generic_apps_and_never_exposes_controls(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            chrome = Path(temporary) / "4311"
            (chrome / "fd").mkdir(parents=True)
            (chrome / "cmdline").write_bytes(b"/usr/bin/chrome\0--gpu-process")
            proc = Path(temporary) / "4312"
            (proc / "fd").mkdir(parents=True)
            (proc / "cmdline").write_bytes(b"custom-server\0--model\0weights.gguf")
            (proc / "fd" / "4").symlink_to(Path(temporary) / "weights.gguf")

            class Result:
                returncode = 0
                stdout = "4311\n4312\n"

            models = local_ai.observed_gpu_processes({}, run=lambda *args, **kwargs: Result(), proc_root=Path(temporary))
        self.assertEqual(len(models), 1)
        self.assertEqual(models[0]["runtime"], "unknown_process")
        self.assertEqual(models[0]["state"], "loaded")
        self.assertEqual(models[0]["metric"], None)
        self.assertFalse(any(models[0]["capabilities"].values()))
        self.assertEqual(models[0]["name"], "weights.gguf")
        self.assertEqual(models[0]["evidence"], {"pid": 4312, "runtimeExecutable": "custom-server", "modelEvidence": "weights.gguf", "activityKnown": False})

    def test_gpu_observer_tolerates_missing_nvidia_tools(self) -> None:
        self.assertEqual(local_ai.observed_gpu_processes({}, run=lambda *args, **kwargs: (_ for _ in ()).throw(OSError("missing"))), [])

    def test_inventory_coalesces_sleeping_llama_gpu_child_without_hiding_unknown_gpu_work(self) -> None:
        original_json, original_text, original_observed = local_ai.request_json, local_ai.request_text, local_ai.observed_gpu_processes
        local_ai.request_json = lambda url, **kwargs: self.fixture("local-ai-llama-sleeping-models.json")
        local_ai.request_text = lambda *args, **kwargs: ""
        local_ai.observed_gpu_processes = lambda config: [
            local_ai.make_model("unknown_process", "Qwen-Worker.gguf", location="/models/Qwen-Worker.gguf", state="loaded",
                detail="GPU process observed, activity unknown",
                evidence={"pid": 321, "runtimeExecutable": "llama-server", "modelEvidence": "/models/Qwen-Worker.gguf"}),
            local_ai.make_model("unknown_process", "other.gguf", location="/models/other.gguf", state="loaded",
                detail="GPU process observed, activity unknown",
                evidence={"pid": 322, "runtimeExecutable": "custom-server", "modelEvidence": "/models/other.gguf"}),
        ]
        try:
            config = local_ai.default_config()
            config["knownRoots"] = []
            for key, runtime in config["runtimes"].items():
                runtime["enabled"] = key == "llama_cpp"
            data = local_ai.inventory(config)
        finally:
            local_ai.request_json, local_ai.request_text, local_ai.observed_gpu_processes = original_json, original_text, original_observed
        self.assertEqual([item["runtime"] for item in data["models"]], ["unknown_process", "llama_cpp"])
        llama = next(item for item in data["models"] if item["runtime"] == "llama_cpp")
        unknown = next(item for item in data["models"] if item["runtime"] == "unknown_process")
        self.assertEqual(llama["state"], "installed")
        self.assertEqual(llama["evidence"]["runtimeModelEvidence"], "/models/Qwen-Worker.gguf")
        self.assertEqual(unknown["evidence"]["runtimeExecutable"], "custom-server")

    def test_inventory_keeps_independent_llama_server_and_relative_aliases(self) -> None:
        original_json, original_text, original_observed = local_ai.request_json, local_ai.request_text, local_ai.observed_gpu_processes
        local_ai.request_json = lambda url, **kwargs: {"data": [{"id": "shared", "status": {"value": "sleeping", "args": ["--model", "/configured/models/shared.gguf"]}}]}
        local_ai.request_text = lambda *args, **kwargs: ""
        local_ai.observed_gpu_processes = lambda config: [
            local_ai.make_model("unknown_process", "shared.gguf", location="/configured/models/shared.gguf", state="loaded",
                detail="GPU process observed, activity unknown", evidence={"pid": 321, "runtimeExecutable": "llama-server", "modelEvidence": "/configured/models/shared.gguf", "activityKnown": False}),
            local_ai.make_model("unknown_process", "shared.gguf", location="/independent/models/shared.gguf", state="loaded",
                detail="GPU process observed, activity unknown", evidence={"pid": 322, "runtimeExecutable": "llama-server", "modelEvidence": "/independent/models/shared.gguf", "activityKnown": False}),
            local_ai.make_model("unknown_process", "shared", location="shared", state="loaded",
                detail="GPU process observed, activity unknown", evidence={"pid": 323, "runtimeExecutable": "llama-server", "modelEvidence": "shared", "activityKnown": False}),
        ]
        try:
            config = local_ai.default_config()
            config["knownRoots"] = []
            for key, runtime in config["runtimes"].items(): runtime["enabled"] = key == "llama_cpp"
            data = local_ai.inventory(config)
        finally:
            local_ai.request_json, local_ai.request_text, local_ai.observed_gpu_processes = original_json, original_text, original_observed
        unknown_locations = {item["location"] for item in data["models"] if item["runtime"] == "unknown_process"}
        self.assertEqual(unknown_locations, {"/independent/models/shared.gguf", "shared"})

    def test_inventory_orders_residents_before_unmounted_models(self) -> None:
        original_json, original_text = local_ai.request_json, local_ai.request_text
        local_ai.request_json = lambda url, **kwargs: {
            "data": [
                {"id": "unmounted", "status": "unloaded", "type": "llm"},
                {"id": "resident", "status": "loaded", "type": "llm"},
                {"id": "busy", "status": "active", "type": "llm"},
            ]
        }
        local_ai.request_text = lambda *args, **kwargs: ""
        try:
            config = local_ai.default_config()
            config["knownRoots"] = []
            config["observeGpuProcesses"] = False
            for key, runtime in config["runtimes"].items():
                runtime["enabled"] = key == "llama_cpp"
            data = local_ai.inventory(config)
        finally:
            local_ai.request_json, local_ai.request_text = original_json, original_text
        self.assertEqual([(item["name"], item["state"]) for item in data["models"]],
                         [("busy", "active"), ("resident", "loaded"), ("unmounted", "installed")])

    def test_declarative_adapter_adds_catalog_without_loading_user_python(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            descriptor = Path(temporary) / "catalog.json"
            descriptor.write_text(json.dumps({"id": "custom", "kind": "openai-model-catalog", "modelsPath": "/models"}), encoding="utf-8")
            original = local_ai.request_json
            local_ai.request_json = lambda *args, **kwargs: {"data": [{"id": "custom-model", "type": "embedding"}]}
            try:
                config = local_ai.default_config()
                config["knownRoots"] = []
                config["observeGpuProcesses"] = False
                for runtime in config["runtimes"].values(): runtime["enabled"] = False
                config["runtimes"]["custom"] = {"enabled": True, "endpoint": "http://127.0.0.1:9999"}
                config["runtimes"]["not-safe"] = {"enabled": True, "endpoint": "http://127.0.0.1:9998"}
                config["adapterDescriptors"] = [str(descriptor)]
                data = local_ai.inventory(config)
            finally:
                local_ai.request_json = original
        self.assertEqual(data["models"][0]["runtime"], "custom")
        self.assertEqual(data["models"][0]["kind"], "embedding")

    def test_user_owned_system_descriptor_directory_is_not_loaded(self) -> None:
        from local_ai_drivers import descriptors
        with tempfile.TemporaryDirectory() as temporary:
            descriptor = Path(temporary) / "unsafe.json"
            descriptor.write_text(json.dumps({"id": "unsafe", "kind": "openai-model-catalog"}), encoding="utf-8")
            original = descriptors.SYSTEM_DESCRIPTOR_DIR
            descriptors.SYSTEM_DESCRIPTOR_DIR = Path(temporary)
            try:
                self.assertEqual(descriptors.descriptor_paths({}), [])
            finally:
                descriptors.SYSTEM_DESCRIPTOR_DIR = original

    def test_safetensors_and_gguf_headers_supply_classification_evidence(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            header = json.dumps({"__metadata__": {"model_type": "text-to-speech"}}).encode("utf-8")
            safe = root / "opaque.safetensors"
            safe.write_bytes(len(header).to_bytes(8, "little") + header)
            metadata, issue = local_ai.metadata_strings(safe)
            self.assertEqual(issue, "")
            self.assertEqual(local_ai.classify(safe.stem, metadata=metadata), ("audio", "metadata"))

            key, value = b"general.architecture", b"video"
            gguf = root / "opaque.gguf"
            gguf.write_bytes(b"GGUF" + (3).to_bytes(4, "little") + (0).to_bytes(8, "little") + (1).to_bytes(8, "little")
                + len(key).to_bytes(8, "little") + key + (8).to_bytes(4, "little") + len(value).to_bytes(8, "little") + value)
            metadata, issue = local_ai.metadata_strings(gguf)
            self.assertEqual(issue, "")
            self.assertEqual(local_ai.classify(gguf.stem, metadata=metadata), ("video", "metadata"))


if __name__ == "__main__":
    unittest.main()
