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
loader = importlib.machinery.SourceFileLoader("local_ai", str(ROOT / "local-ai"))
spec = importlib.util.spec_from_loader(loader.name, loader)
local_ai = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = local_ai
loader.exec_module(local_ai)


class LocalAIContractTests(unittest.TestCase):
    def fixture(self, name: str) -> object:
        return json.loads((FIXTURES / name).read_text(encoding="utf-8"))

    def test_classification_uses_declaration_before_heuristics(self) -> None:
        self.assertEqual(local_ai.classify("qwen-video", "embedding"), ("embedding", "declared"))
        self.assertEqual(local_ai.classify("qwen-video"), ("video", "heuristic"))
        self.assertEqual(local_ai.classify("opaque-weight"), ("unknown", "unknown"))

    def test_inventory_normalizes_common_runtime_fixtures(self) -> None:
        responses = {
            "/models": self.fixture("local-ai-llama-models.json"),
            "/api/tags": self.fixture("local-ai-ollama-tags.json"),
            "/api/ps": self.fixture("local-ai-ollama-ps.json"),
            "/v1/models": self.fixture("local-ai-lmstudio-models.json"),
            "/system_stats": self.fixture("local-ai-comfyui-system-stats.json"),
            "/queue": self.fixture("local-ai-comfyui-queue-empty.json"),
        }
        original = local_ai.request_json
        local_ai.request_json = lambda url, **kwargs: next(value for suffix, value in responses.items() if url.endswith(suffix))
        try:
            config = local_ai.default_config()
            config["knownRoots"] = []
            data = local_ai.inventory(config)
        finally:
            local_ai.request_json = original
        by_runtime = {item["runtime"] for item in data["models"]}
        self.assertTrue({"llama_cpp", "ollama", "lm_studio", "vllm"}.issubset(by_runtime))
        llama = next(item for item in data["models"] if item["runtime"] == "llama_cpp" and item["state"] == "active")
        self.assertEqual(llama["metric"], {"value": 26.5, "unit": "tok/s", "source": "runtime"})
        self.assertEqual(next(item for item in data["models"] if item["runtime"] == "ollama" and item["state"] == "installed")["metric"], None)
        comfy = next(item for item in data["runtimes"] if item["id"] == "comfyui")
        self.assertTrue(comfy["capabilities"]["releaseRuntime"])

    def test_configured_scan_never_needs_a_home_wide_walk(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "weights"
            root.mkdir()
            (root / "Qwen3-Coder.gguf").write_bytes(b"GGUF")
            config = local_ai.default_config()
            config["roots"] = [str(root)]
            config["knownRoots"] = []
            for runtime in config["runtimes"].values():
                runtime["enabled"] = False
            data = local_ai.inventory(config)
        self.assertEqual(len(data["models"]), 1)
        self.assertEqual(data["models"][0]["kind"], "llm")
        self.assertEqual(data["models"][0]["state"], "installed")

    def test_metadata_and_path_classification_prevent_known_false_llms(self) -> None:
        self.assertEqual(local_ai.classify("qwen-image-Q4", location="/weights/qwen-image.gguf"), ("image", "heuristic"))
        self.assertEqual(local_ai.classify("umt5-xxl-encoder", location="/models/text_encoders/umt5.gguf"), ("embedding", "heuristic"))
        self.assertEqual(local_ai.classify("ltx_audio_vae", location="/models/vae/ltx_audio_vae.safetensors"), ("audio", "heuristic"))
        self.assertEqual(local_ai.classify("opaque", metadata={"general.architecture": "text-to-speech"}), ("audio", "metadata"))

    def test_endpoint_rejects_file_scheme_and_oversized_responses(self) -> None:
        with self.assertRaisesRegex(local_ai.LocalAIError, "http or https"):
            local_ai.request_json("file:///tmp/models")
        class Response:
            def __enter__(self): return self
            def __exit__(self, *args): return False
            def read(self, size): return b"x" * size
        original = local_ai.urlopen
        local_ai.urlopen = lambda *args, **kwargs: Response()
        try:
            with self.assertRaisesRegex(local_ai.LocalAIError, "size limit"):
                local_ai.request_json("http://127.0.0.1:9/models")
        finally:
            local_ai.urlopen = original

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
        original = local_ai.request_json
        local_ai.request_json = lambda url, **kwargs: self.fixture("local-ai-llama-models.json")
        try:
            config = local_ai.default_config()
            for key, runtime in config["runtimes"].items():
                runtime["enabled"] = key == "llama_cpp"
            with self.assertRaisesRegex(local_ai.LocalAIError, "requests are active"):
                local_ai.action(config, "unmount", "llama_cpp", "qwen3-coder")
        finally:
            local_ai.request_json = original

    def test_unmount_resolves_the_normalized_id_to_the_runtime_name(self) -> None:
        calls: list[tuple[str, str, object]] = []
        original = local_ai.request_json

        def fake(url: str, method: str = "GET", payload: object = None, **kwargs: object) -> object:
            calls.append((url, method, payload))
            if url.endswith("/models"):
                return {"data": [{"id": "gpt-oss", "status": "loaded"}]}
            return {}

        local_ai.request_json = fake
        try:
            config = local_ai.default_config()
            for key, runtime in config["runtimes"].items():
                runtime["enabled"] = key == "llama_cpp"
            runtime_id = local_ai.model_id("llama_cpp", "gpt-oss")
            result = local_ai.action(config, "unmount", "llama_cpp", runtime_id)
        finally:
            local_ai.request_json = original
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


if __name__ == "__main__":
    unittest.main()
