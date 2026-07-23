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
            result = local_ai.action(config, "release", "comfyui")
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
