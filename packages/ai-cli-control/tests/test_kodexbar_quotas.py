from __future__ import annotations

import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import re
import struct
import subprocess
import tempfile
import textwrap
import threading
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
ENGINE = ROOT / "kodexbar-quotas"
FIXTURES = ROOT / "tests" / "fixtures"
loader = importlib.machinery.SourceFileLoader("kodexbar_quotas", str(ENGINE))
spec = importlib.util.spec_from_loader(loader.name, loader)
quotas = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(quotas)

# Synthetic secrets used only in hermetic tests. Must never appear in engine output.
TEST_CODEX_TOKEN = "test-codex-access-token-SECRET-do-not-leak"
TEST_GROK_KEY = "test-grok-key-SECRET-do-not-leak"


def _encode_varint(value: int) -> bytes:
    parts: list[int] = []
    while True:
        bits = value & 0x7F
        value >>= 7
        parts.append(bits | (0x80 if value else 0))
        if not value:
            break
    return bytes(parts)


def _protobuf_key(field: int, wire_type: int) -> bytes:
    return _encode_varint((field << 3) | wire_type)


def build_minimal_grok_billing_message(used_percent: float, reset_unix: int) -> bytes:
    """Protobuf body with percent at path [1,1] and timestamp at preferred [1,5,1]."""
    # field 1 fixed32 percent (path ends with field 1 — normative candidate)
    percent_field = _protobuf_key(1, 5) + struct.pack("<f", used_percent)
    # field 5 / field 1 varint timestamp → path [1, 5, 1]
    ts_inner = _protobuf_key(1, 0) + _encode_varint(reset_unix)
    field5 = _protobuf_key(5, 2) + _encode_varint(len(ts_inner)) + ts_inner
    nested = percent_field + field5
    return _protobuf_key(1, 2) + _encode_varint(len(nested)) + nested


def build_minimal_grok_billing_frame(used_percent: float, reset_unix: int) -> bytes:
    """Build a gRPC-web data frame with normative percent and timestamp paths."""
    message = build_minimal_grok_billing_message(used_percent, reset_unix)
    return b"\x00" + len(message).to_bytes(4, "big") + message


def build_grpc_web_trailer_frame(status: int, message: str = "") -> bytes:
    """gRPC-web trailer frame (flag 0x80) with grpc-status and optional grpc-message."""
    lines = [f"grpc-status: {status}\r\n"]
    if message:
        lines.append(f"grpc-message: {message}\r\n")
    payload = "".join(lines).encode("utf-8")
    return b"\x80" + len(payload).to_bytes(4, "big") + payload


def sample_codex_usage_payload() -> dict:
    """Shape aligned with CodexUsageResponse / dossier (weekly + spark weekly)."""
    return {
        "plan_type": "pro",
        "rate_limit": {
            "primary_window": None,
            "secondary_window": {
                "used_percent": 33,
                "reset_at": 1782600000,
                "limit_window_seconds": 10080 * 60,
            },
        },
        "additional_rate_limits": [
            {
                "limit_id": "codex-spark-weekly",
                "limit_name": "Spark Weekly",
                "used_percent": 0,
                "reset_at": 1782700000,
                "limit_window_seconds": 10080 * 60,
            }
        ],
        "credits": {"has_credits": True, "balance": 663.3},
    }


class QuotasEngineTests(unittest.TestCase):
    def test_maps_claude_oauth_shape_to_widget_envelope(self) -> None:
        response = json.loads((FIXTURES / "claude-oauth-usage.json").read_text(encoding="utf-8"))
        expected = json.loads((FIXTURES / "claude-widget-entry.json").read_text(encoding="utf-8"))
        entry = quotas.map_claude_usage(response, updated_at="2026-07-14T23:08:40Z")
        self.assertEqual(entry["provider"], "claude")
        self.assertEqual(entry["source"], "claude")
        self.assertEqual(entry["engine"], "kodexbar")
        self.assertEqual(entry["usage"]["primary"], expected["usage"]["primary"])
        self.assertEqual(entry["usage"]["secondary"], expected["usage"]["secondary"])
        self.assertEqual(entry["usage"]["tertiary"]["usedPercent"], 8)

    def test_uses_weekly_window_when_claude_has_no_session(self) -> None:
        entry = quotas.map_claude_usage({"seven_day": {"utilization": 4}})
        self.assertEqual(entry["usage"]["primary"], {"usedPercent": 4, "windowMinutes": 10080})
        self.assertEqual(entry["usage"]["secondary"], {"usedPercent": 4, "windowMinutes": 10080})

    def test_invalid_shape_requests_upstream_fallback(self) -> None:
        with self.assertRaises(quotas.FetchFallback):
            quotas.map_claude_usage({"five_hour": {"resets_at": "2026-07-15T03:29:00Z"}})

    def test_claude_429_is_a_provider_error_not_a_fallback(self) -> None:
        with patch.object(quotas, "claude_access_token", return_value="token"), patch.object(
            quotas, "http_get", return_value=(429, b"{}")
        ):
            entry = quotas.fetch_claude()
        self.assertEqual(entry["error"]["kind"], "provider")
        self.assertIn("rate limited", entry["error"]["message"])
        self.assertEqual(entry["error"]["category"], "rate_limit")
        self.assertFalse(entry["error"]["retryable"])
        self.assertEqual(entry["engine"], "kodexbar")

    def test_claude_auth_and_entitlement_errors_are_not_retryable(self) -> None:
        for status, category in ((401, "authentication"), (403, "entitlement")):
            with self.subTest(status=status), patch.object(
                quotas, "claude_access_token", return_value="token"
            ), patch.object(quotas, "http_get", return_value=(status, b"{}")):
                entry = quotas.fetch_claude()
            self.assertEqual(entry["error"]["category"], category)
            self.assertFalse(entry["error"]["retryable"])
            self.assertIn(f"HTTP {status}", entry["error"]["message"])

    def test_transient_claude_failures_keep_exact_retry_metadata(self) -> None:
        cases = (
            (quotas.FetchFallback("socket offline", "network", True), "network"),
            (quotas.FetchFallback("request timed out", "timeout", True), "timeout"),
            (quotas.FetchFallback("invalid payload", "invalid_response", True), "invalid_response"),
        )
        for failure, category in cases:
            with self.subTest(category=category), patch.object(
                quotas, "fetch_claude", side_effect=failure
            ), patch.object(
                quotas, "upstream_entries", side_effect=quotas.FetchFallback("upstream also failed", "timeout", True)
            ):
                entry = quotas.fetch_provider("claude", None)[0]
            self.assertEqual(entry["error"]["category"], category)
            self.assertTrue(entry["error"]["retryable"])
            self.assertIn(str(failure), entry["error"]["message"])
            self.assertIn("Fallback failed: upstream also failed", entry["error"]["message"])

    def test_claude_request_uses_the_upstream_oauth_headers(self) -> None:
        payload = (FIXTURES / "claude-oauth-usage.json").read_bytes()
        with patch.object(quotas, "claude_access_token", return_value="token") as token, patch.object(
            quotas, "http_get", return_value=(200, payload)
        ) as request:
            quotas.fetch_claude()
        token.assert_called_once()
        url, headers = request.call_args.args
        self.assertEqual(url, "https://api.anthropic.com/api/oauth/usage")
        self.assertEqual(headers["Authorization"], "Bearer token")
        self.assertEqual(headers["anthropic-beta"], "oauth-2025-04-20")
        self.assertEqual(headers["Accept"], "application/json")

    def test_reads_only_explicitly_enabled_providers(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            config = home / ".config/codexbar/config.json"
            config.parent.mkdir(parents=True)
            config.write_text(json.dumps({"providers": [
                {"id": "codex", "enabled": True},
                {"id": "claude", "enabled": False},
                {"id": "grok", "enabled": True},
            ]}), encoding="utf-8")
            self.assertEqual(quotas.enabled_providers(home), ["codex", "grok"])

    def test_cli_aggregates_native_auth_and_antigravity_upstream(self) -> None:
        """Claude uses fixture, Codex/Grok missing auth stay native, Antigravity still upstream."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            home = root / "home"
            bin_dir = root / "bin"
            config = home / ".config/codexbar/config.json"
            config.parent.mkdir(parents=True)
            config.write_text(json.dumps({"providers": [
                {"id": "claude", "enabled": True},
                {"id": "codex", "enabled": True},
                {"id": "grok", "enabled": True},
                {"id": "antigravity", "enabled": True},
            ]}), encoding="utf-8")
            credentials = home / ".claude/.credentials.json"
            credentials.parent.mkdir(parents=True)
            credentials.write_text(json.dumps({"claudeAiOauth": {"accessToken": "test"}}), encoding="utf-8")
            bin_dir.mkdir()
            upstream = bin_dir / "codexbar"
            upstream.write_text("#!" + os.sys.executable + "\n" + textwrap.dedent("""\
                import json, sys
                provider = sys.argv[sys.argv.index("--provider") + 1]
                print(json.dumps([{"provider": provider, "source": "upstream", "usage": {"primary": None}}]))
            """), encoding="utf-8")
            upstream.chmod(0o755)
            env = os.environ.copy()
            env.update({"HOME": str(home), "PATH": str(bin_dir), "KODEXBAR_QUOTAS_FIXTURE_429": "1"})
            result = subprocess.run(
                [os.sys.executable, str(ENGINE), "usage", "--format", "json", "--json-only", "--provider", "all"],
                env=env,
                text=True,
                capture_output=True,
                check=True,
            )
            entries = json.loads(result.stdout)
            self.assertEqual(
                [entry["provider"] for entry in entries],
                ["claude", "codex", "grok", "antigravity"],
            )
            self.assertIn("error", entries[0])
            self.assertEqual(entries[1]["error"]["category"], "authentication")
            self.assertEqual(entries[2]["error"]["category"], "authentication")
            self.assertEqual(entries[3]["source"], "upstream")
            self.assertNotIn(TEST_CODEX_TOKEN, result.stdout)
            self.assertNotIn(TEST_GROK_KEY, result.stdout)

    def test_missing_or_corrupt_claude_credentials_fallback_without_losing_other_providers(self) -> None:
        for credentials_text in (None, "{corrupt json"):
            with self.subTest(credentials_text=credentials_text), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                home = root / "home"
                bin_dir = root / "bin"
                config = home / ".config/codexbar/config.json"
                config.parent.mkdir(parents=True)
                config.write_text(json.dumps({"providers": [
                    {"id": "claude", "enabled": True},
                    {"id": "codex", "enabled": True},
                    {"id": "grok", "enabled": True},
                    {"id": "antigravity", "enabled": True},
                ]}), encoding="utf-8")
                if credentials_text is not None:
                    credentials = home / ".claude/.credentials.json"
                    credentials.parent.mkdir(parents=True)
                    credentials.write_text(credentials_text, encoding="utf-8")
                bin_dir.mkdir()
                upstream = bin_dir / "codexbar"
                upstream.write_text("#!" + os.sys.executable + "\n" + textwrap.dedent("""\
                    import json, sys
                    provider = sys.argv[sys.argv.index("--provider") + 1]
                    print(json.dumps([{"provider": provider, "source": "upstream", "usage": {"primary": None}}]))
                """), encoding="utf-8")
                upstream.chmod(0o755)
                env = os.environ.copy()
                env.update({"HOME": str(home), "PATH": str(bin_dir)})
                result = subprocess.run(
                    [os.sys.executable, str(ENGINE), "usage", "--format", "json", "--json-only", "--provider", "all"],
                    env=env,
                    text=True,
                    capture_output=True,
                    check=True,
                )
                entries = json.loads(result.stdout)
                self.assertEqual(
                    [entry["provider"] for entry in entries],
                    ["claude", "codex", "grok", "antigravity"],
                )
                # Claude falls back to upstream without local OAuth. Codex/Grok stay native auth.
                self.assertEqual(entries[0]["source"], "upstream")
                self.assertEqual(entries[1]["error"]["category"], "authentication")
                self.assertEqual(entries[2]["error"]["category"], "authentication")
                self.assertEqual(entries[3]["source"], "upstream")

    def test_missing_upstream_reports_not_installed(self) -> None:
        """Antigravity still depends on upstream when the companion CLI is absent."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            home = root / "home"
            bin_dir = root / "bin"
            config = home / ".config/codexbar/config.json"
            config.parent.mkdir(parents=True)
            config.write_text(
                json.dumps({"providers": [{"id": "antigravity", "enabled": True}]}),
                encoding="utf-8",
            )
            bin_dir.mkdir()
            env = os.environ.copy()
            env.update({"HOME": str(home), "PATH": str(bin_dir)})
            result = subprocess.run(
                [os.sys.executable, str(ENGINE), "usage", "--format", "json", "--json-only", "--provider", "antigravity"],
                env=env,
                text=True,
                capture_output=True,
                check=True,
            )
        entry = json.loads(result.stdout)[0]
        self.assertEqual(entry["error"]["message"], "upstream codexbar is not installed")

    def test_broken_upstream_reports_failed_without_exposing_output(self) -> None:
        cases = {
            "exit-nonzero": "raise SystemExit(7)",
            "invalid-json": "print('not json')",
        }
        for name, body in cases.items():
            with self.subTest(name=name), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                home = root / "home"
                bin_dir = root / "bin"
                config = home / ".config/codexbar/config.json"
                config.parent.mkdir(parents=True)
                config.write_text(
                    json.dumps({"providers": [{"id": "antigravity", "enabled": True}]}),
                    encoding="utf-8",
                )
                bin_dir.mkdir()
                upstream = bin_dir / "codexbar"
                upstream.write_text(
                    "#!" + os.sys.executable + "\n" + body + "\n",
                    encoding="utf-8",
                )
                upstream.chmod(0o755)
                env = os.environ.copy()
                env.update({"HOME": str(home), "PATH": str(bin_dir)})
                result = subprocess.run(
                    [
                        os.sys.executable,
                        str(ENGINE),
                        "usage",
                        "--format",
                        "json",
                        "--json-only",
                        "--provider",
                        "antigravity",
                    ],
                    env=env,
                    text=True,
                    capture_output=True,
                    check=True,
                )
                entry = json.loads(result.stdout)[0]
                expected = (
                    "upstream codexbar exited with status 7"
                    if name == "exit-nonzero"
                    else "upstream codexbar returned invalid JSON at column 1"
                )
                self.assertEqual(entry["error"]["message"], expected)
                self.assertNotIn("not installed", entry["error"]["message"])
                self.assertNotIn("not json", entry["error"]["message"])
                self.assertEqual(entry["error"]["retryable"], name == "invalid-json")

    def test_nonzero_upstream_exit_preserves_provider_error_json(self) -> None:
        expected = [{
            "provider": "openai",
            "source": "auto",
            "error": {
                "kind": "provider",
                "message": "No available fetch strategy for openai.",
            },
        }]
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            home = root / "home"
            bin_dir = root / "bin"
            config = home / ".config/codexbar/config.json"
            config.parent.mkdir(parents=True)
            config.write_text(
                json.dumps({"providers": [{"id": "openai", "enabled": True}]}),
                encoding="utf-8",
            )
            bin_dir.mkdir()
            upstream = bin_dir / "codexbar"
            upstream.write_text(
                "#!" + os.sys.executable + "\n"
                + "import json\n"
                + "print(json.dumps(" + repr(expected) + "))\n"
                + "raise SystemExit(1)\n",
                encoding="utf-8",
            )
            upstream.chmod(0o755)
            env = os.environ.copy()
            env.update({"HOME": str(home), "PATH": str(bin_dir)})
            result = subprocess.run(
                [os.sys.executable, str(ENGINE), "usage", "--format", "json", "--json-only", "--provider", "openai"],
                env=env,
                text=True,
                capture_output=True,
                check=True,
            )
        entries = json.loads(result.stdout)
        self.assertEqual(entries, expected)
        self.assertNotEqual(entries[0]["error"]["message"], "upstream codexbar failed to provide usage data")

    def test_cost_is_empty_without_upstream(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            env = os.environ.copy()
            env["PATH"] = directory
            result = subprocess.run(
                [os.sys.executable, str(ENGINE), "cost", "--format", "json", "--json-only"],
                env=env,
                text=True,
                capture_output=True,
                check=True,
            )
        self.assertEqual(json.loads(result.stdout), [])

    def test_unknown_usage_combination_delegates_whole_call(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            bin_dir = root / "bin"
            bin_dir.mkdir()
            upstream = bin_dir / "codexbar"
            upstream.write_text("#!" + os.sys.executable + "\nimport json, sys\nprint(json.dumps(sys.argv[1:]))\n", encoding="utf-8")
            upstream.chmod(0o755)
            env = os.environ.copy()
            env["PATH"] = str(bin_dir)
            result = subprocess.run(
                [os.sys.executable, str(ENGINE), "usage", "--status"],
                env=env,
                text=True,
                capture_output=True,
                check=True,
            )
        self.assertEqual(json.loads(result.stdout), ["usage", "--status"])

    def _synthetic_env(self, root: Path, *, with_upstream: bool = False, with_claude_credentials: bool = False) -> dict[str, str]:
        """HOME and PATH that never touch the real home or real provider CLIs/browsers."""
        home = root / "home"
        bin_dir = root / "bin"
        home.mkdir(parents=True, exist_ok=True)
        bin_dir.mkdir(parents=True, exist_ok=True)
        if with_upstream:
            upstream = bin_dir / "codexbar"
            upstream.write_text(
                "#!" + os.sys.executable + "\n"
                "import json, sys\n"
                "print(json.dumps({\"delegated\": sys.argv[1:]}))\n",
                encoding="utf-8",
            )
            upstream.chmod(0o755)
        if with_claude_credentials:
            credentials = home / ".claude" / ".credentials.json"
            credentials.parent.mkdir(parents=True)
            credentials.write_text(
                json.dumps({"claudeAiOauth": {"accessToken": "synthetic-token"}}),
                encoding="utf-8",
            )
        env = os.environ.copy()
        env.update({"HOME": str(home), "PATH": str(bin_dir)})
        # Drop variables that could pull real tooling into subprocesses.
        for key in ("BROWSER", "DISPLAY", "WAYLAND_DISPLAY", "XDG_RUNTIME_DIR"):
            env.pop(key, None)
        return env

    def test_malformed_config_keeps_native_codex_grok(self) -> None:
        """Malformed config must not whole-delegate codex/grok (that was the H3 bug)."""
        cases = {
            "invalid-json": "{not json",
            "no-providers-array": json.dumps({"other": True}),
            "root-array": "[]",
            "root-null": "null",
        }
        for name, body in cases.items():
            with self.subTest(name=name), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                env = self._synthetic_env(root, with_upstream=True)
                home = Path(env["HOME"])
                bin_dir = Path(env["PATH"])
                log_path = bin_dir / "upstream-calls.log"
                # Recording upstream: only antigravity/unknowns should hit it for codex/grok absence.
                upstream = bin_dir / "codexbar"
                upstream.write_text(
                    "#!" + os.sys.executable + "\n"
                    + textwrap.dedent(f"""\
                        import json, sys
                        from pathlib import Path
                        log = Path({str(log_path)!r})
                        provider = "unknown"
                        if "--provider" in sys.argv:
                            provider = sys.argv[sys.argv.index("--provider") + 1]
                        with log.open("a", encoding="utf-8") as handle:
                            handle.write(provider + "\\n")
                        print(json.dumps([{{"provider": provider, "source": "upstream", "usage": {{"primary": None}}}}]))
                    """),
                    encoding="utf-8",
                )
                upstream.chmod(0o755)
                config = home / ".config" / "codexbar" / "config.json"
                config.parent.mkdir(parents=True)
                config.write_text(body, encoding="utf-8")
                result = subprocess.run(
                    [os.sys.executable, str(ENGINE), "usage", "--format", "json", "--json-only", "--provider", "all"],
                    env=env,
                    text=True,
                    capture_output=True,
                    check=True,
                )
                entries = json.loads(result.stdout)
                self.assertIsInstance(entries, list)
                by_provider = {entry["provider"]: entry for entry in entries}
                self.assertIn("codex", by_provider)
                self.assertIn("grok", by_provider)
                self.assertEqual(by_provider["codex"]["error"]["category"], "authentication")
                self.assertEqual(by_provider["grok"]["error"]["category"], "authentication")
                if log_path.is_file():
                    called = log_path.read_text(encoding="utf-8").split()
                    self.assertNotIn("codex", called)
                    self.assertNotIn("grok", called)

    def test_missing_config_with_upstream_keeps_native_codex_grok(self) -> None:
        """No config + upstream: codex/grok re-login natively, zero codex/grok upstream calls."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            env = self._synthetic_env(root, with_upstream=True)
            home = Path(env["HOME"])
            bin_dir = Path(env["PATH"])
            log_path = bin_dir / "upstream-calls.log"
            upstream = bin_dir / "codexbar"
            upstream.write_text(
                "#!" + os.sys.executable + "\n"
                + textwrap.dedent(f"""\
                    import json, sys
                    from pathlib import Path
                    log = Path({str(log_path)!r})
                    provider = "unknown"
                    if "--provider" in sys.argv:
                        provider = sys.argv[sys.argv.index("--provider") + 1]
                    with log.open("a", encoding="utf-8") as handle:
                        handle.write(provider + "\\n")
                    print(json.dumps([{{"provider": provider, "source": "upstream", "usage": {{"primary": None}}}}]))
                """),
                encoding="utf-8",
            )
            upstream.chmod(0o755)

            # Explicit codex without credentials: re-login, stub never called for codex.
            codex_result = subprocess.run(
                [os.sys.executable, str(ENGINE), "usage", "--format", "json", "--json-only", "--provider", "codex"],
                env=env,
                text=True,
                capture_output=True,
                check=True,
            )
            codex_entry = json.loads(codex_result.stdout)[0]
            self.assertEqual(codex_entry["provider"], "codex")
            self.assertEqual(codex_entry["error"]["category"], "authentication")
            self.assertIn("codex", codex_entry["error"]["message"].lower())
            self.assertFalse(log_path.exists() or (log_path.is_file() and "codex" in log_path.read_text(encoding="utf-8")))

            # Explicit grok likewise.
            grok_result = subprocess.run(
                [os.sys.executable, str(ENGINE), "usage", "--format", "json", "--json-only", "--provider", "grok"],
                env=env,
                text=True,
                capture_output=True,
                check=True,
            )
            grok_entry = json.loads(grok_result.stdout)[0]
            self.assertEqual(grok_entry["error"]["category"], "authentication")
            if log_path.is_file():
                self.assertNotIn("grok", log_path.read_text(encoding="utf-8"))

            # --provider all still walks native codex/grok (no whole-call argv dump).
            all_result = subprocess.run(
                [os.sys.executable, str(ENGINE), "usage", "--format", "json", "--json-only", "--provider", "all"],
                env=env,
                text=True,
                capture_output=True,
                check=True,
            )
            all_entries = json.loads(all_result.stdout)
            self.assertIsInstance(all_entries, list)
            by_provider = {entry["provider"]: entry for entry in all_entries}
            self.assertEqual(by_provider["codex"]["error"]["category"], "authentication")
            self.assertEqual(by_provider["grok"]["error"]["category"], "authentication")
            if log_path.is_file():
                called = log_path.read_text(encoding="utf-8").split()
                self.assertNotIn("codex", called)
                self.assertNotIn("grok", called)

    def test_missing_config_without_upstream_uses_claude_when_credentials_exist(self) -> None:
        """Matrix row 4: no config, no upstream, Claude credentials enable auto-config Claude."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            env = self._synthetic_env(root, with_claude_credentials=True)
            env["KODEXBAR_QUOTAS_FIXTURE_429"] = "1"
            # Auto-config detects Claude credentials and enables only Claude.
            result = subprocess.run(
                [os.sys.executable, str(ENGINE), "usage", "--format", "json", "--json-only", "--provider", "all"],
                env=env,
                text=True,
                capture_output=True,
                check=True,
            )
            entries = json.loads(result.stdout)
            self.assertEqual(len(entries), 1)
            self.assertEqual(entries[0]["provider"], "claude")
            self.assertEqual(entries[0]["engine"], "kodexbar")
            self.assertIn("rate limited", entries[0]["error"]["message"])

            claude_only = subprocess.run(
                [os.sys.executable, str(ENGINE), "usage", "--format", "json", "--json-only", "--provider", "claude"],
                env=env,
                text=True,
                capture_output=True,
                check=True,
            )
            claude_entries = json.loads(claude_only.stdout)
            self.assertEqual(claude_entries[0]["provider"], "claude")
            self.assertIn("rate limited", claude_entries[0]["error"]["message"])

            grok = subprocess.run(
                [os.sys.executable, str(ENGINE), "usage", "--format", "json", "--json-only", "--provider", "grok"],
                env=env,
                text=True,
                capture_output=True,
                check=True,
            )
            grok_entry = json.loads(grok.stdout)[0]
            self.assertEqual(grok_entry["error"]["category"], "authentication")
            self.assertIn("grok login", grok_entry["error"]["message"].lower())

    def test_missing_config_without_upstream_or_claude_emits_first_run_guidance(self) -> None:
        """Matrix row 5: no config, no upstream, no usable Claude credentials -> guidance error."""
        credential_cases = {
            "absent": None,
            "root-array": "[]",
            "oauth-not-object": json.dumps({"claudeAiOauth": "bad"}),
        }
        for name, credentials_body in credential_cases.items():
            with self.subTest(credentials=name), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                env = self._synthetic_env(root)
                if credentials_body is not None:
                    credentials = Path(env["HOME"]) / ".claude" / ".credentials.json"
                    credentials.parent.mkdir(parents=True)
                    credentials.write_text(credentials_body, encoding="utf-8")
                result = subprocess.run(
                    [os.sys.executable, str(ENGINE), "usage", "--format", "json", "--json-only", "--provider", "all"],
                    env=env,
                    text=True,
                    capture_output=True,
                    check=True,
                )
                entries = json.loads(result.stdout)
                self.assertEqual(len(entries), 1)
                entry = entries[0]
                self.assertEqual(entry["provider"], "claude")
                self.assertEqual(entry["error"]["kind"], "provider")
                self.assertEqual(entry["error"]["category"], "authentication")
                self.assertEqual(entry["error"]["message"], quotas.FIRST_RUN_CLAUDE_GUIDANCE)
                self.assertIn("Claude Code", entry["error"]["message"])
                self.assertIn("config.json", entry["error"]["message"])

                # Explicit non-Claude provider still reports the honest upstream-missing fallback.
                grok = subprocess.run(
                    [os.sys.executable, str(ENGINE), "usage", "--format", "json", "--json-only", "--provider", "grok"],
                    env=env,
                    text=True,
                    capture_output=True,
                    check=True,
                )
                grok_entry = json.loads(grok.stdout)[0]
                self.assertEqual(grok_entry["error"]["category"], "authentication")
                self.assertIn("grok login", grok_entry["error"]["message"].lower())

    # --- Auto-config first-run matrix (brainless): synthetic HOME/PATH only, never real HOME/CLIs ---

    def _place_fake_cli(self, bin_dir: Path, name: str) -> None:
        path = bin_dir / name
        path.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        path.chmod(0o755)

    def test_auto_config_detection_helpers_are_local_and_pure(self) -> None:
        """Detection uses only HOME layout and PATH names (no network)."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            home = root / "home"
            bin_dir = root / "bin"
            home.mkdir()
            bin_dir.mkdir()
            env_path = str(bin_dir)
            with patch.dict(os.environ, {"HOME": str(home), "PATH": env_path}, clear=False):
                self.assertFalse(quotas.detect_claude_installed(home))
                self.assertFalse(quotas.detect_codex_installed(home))
                self.assertFalse(quotas.detect_grok_installed(home))
                self.assertFalse(quotas.detect_antigravity_installed(home))

                credentials = home / ".claude" / ".credentials.json"
                credentials.parent.mkdir(parents=True)
                credentials.write_text(
                    json.dumps({"claudeAiOauth": {"accessToken": "tok"}}),
                    encoding="utf-8",
                )
                self.assertTrue(quotas.detect_claude_installed(home))

                (home / ".codex").mkdir()
                (home / ".codex" / "auth.json").write_text("{}", encoding="utf-8")
                self.assertTrue(quotas.detect_codex_installed(home))

                (home / ".grok").mkdir()
                self.assertTrue(quotas.detect_grok_installed(home))

                self._place_fake_cli(bin_dir, "agy")
                self.assertTrue(quotas.detect_antigravity_installed(home))

                # PATH-only signals (no home side effects beyond what we set).
                self._place_fake_cli(bin_dir, "claude")
                self._place_fake_cli(bin_dir, "codex")
                self._place_fake_cli(bin_dir, "grok")
                self._place_fake_cli(bin_dir, "antigravity")
                empty_home = root / "empty-home"
                empty_home.mkdir()
                self.assertTrue(quotas.detect_claude_installed(empty_home))
                self.assertTrue(quotas.detect_codex_installed(empty_home))
                self.assertTrue(quotas.detect_grok_installed(empty_home))
                self.assertTrue(quotas.detect_antigravity_installed(empty_home))

    def test_build_auto_config_includes_version_and_four_ids(self) -> None:
        payload = quotas.build_auto_config({
            "claude": True,
            "codex": False,
            "grok": True,
            "antigravity": False,
        })
        self.assertEqual(payload["version"], 1)
        self.assertEqual(
            [item["id"] for item in payload["providers"]],
            ["claude", "codex", "grok", "antigravity"],
        )
        self.assertEqual(
            [item["enabled"] for item in payload["providers"]],
            [True, False, True, False],
        )

    def test_existing_config_is_never_overwritten_byte_for_byte(self) -> None:
        """Config present (valid): remains intact after a full usage invoke."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            env = self._synthetic_env(root)
            home = Path(env["HOME"])
            config = home / ".config" / "codexbar" / "config.json"
            config.parent.mkdir(parents=True)
            original = '{"version":1,"providers":[{"id":"codex","enabled":true}]}\n'
            config.write_text(original, encoding="utf-8")
            # Detection would otherwise try to enable other providers if we rewrote.
            self._place_fake_cli(Path(env["PATH"]), "claude")
            self._place_fake_cli(Path(env["PATH"]), "grok")
            result = subprocess.run(
                [os.sys.executable, str(ENGINE), "usage", "--format", "json", "--json-only", "--provider", "all"],
                env=env,
                text=True,
                capture_output=True,
                check=True,
            )
            self.assertEqual(config.read_text(encoding="utf-8"), original)
            # Output remains parseable JSON and only reflects the existing enabled list.
            entries = json.loads(result.stdout)
            self.assertEqual([entry["provider"] for entry in entries], ["codex"])

    def test_malformed_existing_config_is_not_repaired_or_overwritten(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            env = self._synthetic_env(root, with_upstream=True)
            home = Path(env["HOME"])
            config = home / ".config" / "codexbar" / "config.json"
            config.parent.mkdir(parents=True)
            original = "{not-valid-json"
            config.write_text(original, encoding="utf-8")
            self._place_fake_cli(Path(env["PATH"]), "claude")
            subprocess.run(
                [os.sys.executable, str(ENGINE), "usage", "--format", "json", "--json-only", "--provider", "all"],
                env=env,
                text=True,
                capture_output=True,
                check=True,
            )
            self.assertEqual(config.read_text(encoding="utf-8"), original)

    def test_auto_config_generates_versioned_json_for_detected_clis(self) -> None:
        """Config absent + CLIs detected → atomic write with version 1 and enabled only for detected."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            env = self._synthetic_env(root)
            home = Path(env["HOME"])
            bin_dir = Path(env["PATH"])
            self._place_fake_cli(bin_dir, "claude")
            self._place_fake_cli(bin_dir, "codex")
            # grok via home directory signal
            (home / ".grok").mkdir()
            # antigravity not present

            result = subprocess.run(
                [os.sys.executable, str(ENGINE), "usage", "--format", "json", "--json-only", "--provider", "all"],
                env=env,
                text=True,
                capture_output=True,
                check=True,
            )
            config_path = home / ".config" / "codexbar" / "config.json"
            self.assertTrue(config_path.is_file())
            raw = config_path.read_text(encoding="utf-8")
            # Literal acceptance: generated JSON includes version 1 (stdlib dumps uses ": ").
            self.assertIn('"version": 1', raw)
            payload = json.loads(raw)
            self.assertEqual(payload["version"], 1)
            by_id = {item["id"]: item["enabled"] for item in payload["providers"]}
            self.assertEqual(
                by_id,
                {"claude": True, "codex": True, "grok": True, "antigravity": False},
            )
            # Normal path: only detected/enabled providers are queried.
            entries = json.loads(result.stdout)
            self.assertEqual(
                sorted(entry["provider"] for entry in entries),
                ["claude", "codex", "grok"],
            )
            # Codex/Grok native auth fails honestly without credentials (no upstream install).
            by_provider = {entry["provider"]: entry for entry in entries}
            self.assertEqual(by_provider["codex"]["error"]["category"], "authentication")
            self.assertIn("codex", by_provider["codex"]["error"]["message"].lower())
            self.assertEqual(by_provider["grok"]["error"]["category"], "authentication")
            self.assertIn("grok login", by_provider["grok"]["error"]["message"].lower())
            # stdout must stay pure JSON (auto-config is silent).
            self.assertEqual(result.stderr.strip(), "")

    def test_auto_config_zero_clis_writes_nothing(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            env = self._synthetic_env(root)
            home = Path(env["HOME"])
            config_path = home / ".config" / "codexbar" / "config.json"
            result = subprocess.run(
                [os.sys.executable, str(ENGINE), "usage", "--format", "json", "--json-only", "--provider", "all"],
                env=env,
                text=True,
                capture_output=True,
                check=True,
            )
            self.assertFalse(config_path.exists())
            entries = json.loads(result.stdout)
            self.assertEqual(entries[0]["error"]["message"], quotas.FIRST_RUN_CLAUDE_GUIDANCE)

    def test_auto_config_write_failure_does_not_break_call(self) -> None:
        """If the config directory cannot be created/written, keep absent-config behavior."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            env = self._synthetic_env(root)
            home = Path(env["HOME"])
            bin_dir = Path(env["PATH"])
            self._place_fake_cli(bin_dir, "codex")
            # Block writing config: create a file where the config directory should be.
            blocker = home / ".config"
            blocker.write_text("not-a-directory", encoding="utf-8")
            result = subprocess.run(
                [os.sys.executable, str(ENGINE), "usage", "--format", "json", "--json-only", "--provider", "all"],
                env=env,
                text=True,
                capture_output=True,
                check=True,
            )
            # No config.json created under the blocked tree.
            self.assertFalse((home / ".config" / "codexbar" / "config.json").exists())
            # Call still succeeds with the legacy absent-config guidance (codex on PATH is not
            # credentials for Claude, and write failed so enabled list was never established).
            entries = json.loads(result.stdout)
            self.assertEqual(entries[0]["provider"], "claude")
            self.assertEqual(entries[0]["error"]["message"], quotas.FIRST_RUN_CLAUDE_GUIDANCE)

    def test_auto_config_codex_auth_json_without_cli_enables_codex(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            env = self._synthetic_env(root)
            home = Path(env["HOME"])
            auth = home / ".codex" / "auth.json"
            auth.parent.mkdir(parents=True)
            auth.write_text("{}", encoding="utf-8")
            result = subprocess.run(
                [os.sys.executable, str(ENGINE), "usage", "--format", "json", "--json-only", "--provider", "all"],
                env=env,
                text=True,
                capture_output=True,
                check=True,
            )
            payload = json.loads((home / ".config" / "codexbar" / "config.json").read_text(encoding="utf-8"))
            self.assertEqual(payload["version"], 1)
            self.assertEqual(
                {item["id"]: item["enabled"] for item in payload["providers"]},
                {"claude": False, "codex": True, "grok": False, "antigravity": False},
            )
            entries = json.loads(result.stdout)
            self.assertEqual([entry["provider"] for entry in entries], ["codex"])
            self.assertEqual(entries[0]["error"]["category"], "authentication")
            self.assertEqual(entries[0]["error"]["message"], quotas.CODEX_AUTH_RELOGIN)

    def test_write_auto_config_exclusive_concurrent_publish(self) -> None:
        """Two concurrent publishers: only one wins, the loser never alters winner content."""
        with tempfile.TemporaryDirectory() as directory:
            config_path = Path(directory) / "config.json"
            payload_a = quotas.build_auto_config(
                {"claude": True, "codex": False, "grok": False, "antigravity": False}
            )
            payload_b = quotas.build_auto_config(
                {"claude": False, "codex": True, "grok": False, "antigravity": False}
            )
            barrier = threading.Barrier(2)
            outcomes: list[tuple[str, bool]] = []
            lock = threading.Lock()

            def publish(label: str, payload: dict) -> None:
                barrier.wait(timeout=5)
                won = quotas.write_auto_config_atomic(config_path, payload)
                with lock:
                    outcomes.append((label, won))

            threads = [
                threading.Thread(target=publish, args=("a", payload_a)),
                threading.Thread(target=publish, args=("b", payload_b)),
            ]
            for thread in threads:
                thread.start()
            for thread in threads:
                thread.join(timeout=10)
            self.assertEqual(len(outcomes), 2)
            wins = [label for label, won in outcomes if won]
            losses = [label for label, won in outcomes if not won]
            self.assertEqual(len(wins), 1, f"exactly one publisher must win: {outcomes}")
            self.assertEqual(len(losses), 1, f"exactly one publisher must lose: {outcomes}")
            self.assertTrue(config_path.is_file())
            winner_payload = payload_a if wins[0] == "a" else payload_b
            raw = config_path.read_text(encoding="utf-8")
            self.assertEqual(json.loads(raw), winner_payload)
            # Loser must not have replaced or concatenated content.
            self.assertEqual(raw.count('"version"'), 1)

    # --- Native Codex / Grok (hermetic: synthetic HOME/PATH, monkeypatched http_request) ---

    def _write_codex_auth(self, home: Path, token: str = TEST_CODEX_TOKEN, account_id: str = "acct-test") -> None:
        path = home / ".codex" / "auth.json"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(
            json.dumps({
                "auth_mode": "chatgpt",
                "OPENAI_API_KEY": None,
                "tokens": {
                    "access_token": token,
                    "refresh_token": "refresh-not-used",
                    "account_id": account_id,
                },
            }),
            encoding="utf-8",
        )

    def _write_grok_auth(self, home: Path, key: str = TEST_GROK_KEY) -> None:
        path = home / ".grok" / "auth.json"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(
            json.dumps({
                "https://auth.x.ai::client": {
                    "key": key,
                    "auth_mode": "oidc",
                    "team_id": "team-1",
                    "expires_at": "2099-01-01T00:00:00Z",
                }
            }),
            encoding="utf-8",
        )

    def test_codex_native_oauth_maps_weekly_and_spark(self) -> None:
        payload = sample_codex_usage_payload()
        response_body = json.dumps(payload).encode("utf-8")
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            self._write_codex_auth(home)

            def fake_http(method, url, headers=None, body=None, timeout=None):
                self.assertEqual(method.upper(), "GET")
                self.assertIn("/wham/usage", url)
                self.assertEqual(headers["User-Agent"], "CodexBar")
                self.assertEqual(headers["Authorization"], f"Bearer {TEST_CODEX_TOKEN}")
                self.assertEqual(headers["ChatGPT-Account-Id"], "acct-test")
                return 200, {"Content-Type": "application/json"}, response_body

            with patch.object(quotas, "http_request", side_effect=fake_http):
                entry = quotas.fetch_codex(home)

        self.assertEqual(entry["provider"], "codex")
        self.assertEqual(entry["source"], "oauth")
        self.assertEqual(entry["engine"], "kodexbar")
        self.assertIsNone(entry["usage"]["primary"])
        self.assertEqual(entry["usage"]["secondary"]["usedPercent"], 33)
        self.assertEqual(entry["usage"]["secondary"]["windowMinutes"], 10080)
        self.assertIn("resetsAt", entry["usage"]["secondary"])
        extras = entry["usage"]["extraRateWindows"]
        self.assertEqual(extras[0]["id"], "codex-spark-weekly")
        self.assertEqual(extras[0]["window"]["usedPercent"], 0)
        dumped = json.dumps(entry)
        self.assertNotIn(TEST_CODEX_TOKEN, dumped)

    def test_codex_401_is_auth_relogin_without_upstream_delegation(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            self._write_codex_auth(home)
            upstream_calls: list[str] = []

            def fake_http(method, url, headers=None, body=None, timeout=None):
                return 401, {}, b"{}"

            def fake_upstream(provider, source):
                upstream_calls.append(provider)
                return [{"provider": provider, "source": "upstream"}]

            with patch.object(quotas, "http_request", side_effect=fake_http), patch.object(
                quotas, "upstream_entries", side_effect=fake_upstream
            ), patch.object(quotas, "upstream_path", return_value="/fake/codexbar"):
                entries = quotas.fetch_provider("codex", None, home)

        self.assertEqual(len(entries), 1)
        self.assertEqual(entries[0]["error"]["category"], "authentication")
        self.assertFalse(entries[0]["error"]["retryable"])
        self.assertEqual(entries[0]["error"]["message"], quotas.CODEX_AUTH_RELOGIN)
        self.assertEqual(upstream_calls, [])
        self.assertNotIn(TEST_CODEX_TOKEN, json.dumps(entries))

    def test_codex_500_without_upstream_is_retryable_honest(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            self._write_codex_auth(home)

            def fake_http(method, url, headers=None, body=None, timeout=None):
                return 500, {}, b"error"

            with patch.object(quotas, "http_request", side_effect=fake_http), patch.object(
                quotas, "upstream_path", return_value=None
            ):
                entries = quotas.fetch_provider("codex", None, home)

        self.assertEqual(entries[0]["error"]["category"], "network")
        self.assertTrue(entries[0]["error"]["retryable"])
        self.assertEqual(entries[0]["error"]["message"], quotas.CODEX_NETWORK)
        self.assertNotIn(TEST_CODEX_TOKEN, json.dumps(entries))

    def test_codex_500_with_upstream_delegates(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            self._write_codex_auth(home)

            def fake_http(method, url, headers=None, body=None, timeout=None):
                return 500, {}, b"error"

            with patch.object(quotas, "http_request", side_effect=fake_http), patch.object(
                quotas, "upstream_path", return_value="/fake/codexbar"
            ), patch.object(
                quotas,
                "upstream_entries",
                return_value=[{"provider": "codex", "source": "upstream", "usage": {"primary": None}}],
            ):
                entries = quotas.fetch_provider("codex", None, home)

        self.assertEqual(entries[0]["source"], "upstream")
        self.assertEqual(entries[0]["provider"], "codex")

    def test_codex_alt_usage_path_when_base_url_lacks_backend_api(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            self._write_codex_auth(home)
            config = home / ".codex" / "config.toml"
            config.write_text('chatgpt_base_url = "https://example.test/codex"\n', encoding="utf-8")
            seen: list[str] = []

            def fake_http(method, url, headers=None, body=None, timeout=None):
                seen.append(url)
                return 200, {}, json.dumps(sample_codex_usage_payload()).encode()

            with patch.object(quotas, "http_request", side_effect=fake_http):
                quotas.fetch_codex(home)
        self.assertEqual(seen, ["https://example.test/codex/api/codex/usage"])

    def test_grok_native_grpc_web_maps_primary(self) -> None:
        frame = build_minimal_grok_billing_frame(57.0, 1784733973)
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            self._write_grok_auth(home)

            def fake_http(method, url, headers=None, body=None, timeout=None):
                self.assertEqual(method.upper(), "POST")
                self.assertEqual(url, quotas.GROK_CREDITS_URL)
                self.assertEqual(body, quotas.GROK_EMPTY_FRAME)
                self.assertEqual(headers["Content-Type"], "application/grpc-web+proto")
                self.assertEqual(headers["Authorization"], f"Bearer {TEST_GROK_KEY}")
                self.assertEqual(headers["User-Agent"], "CodexBar")
                return 200, {"content-type": "application/grpc-web+proto"}, frame

            with patch.object(quotas, "http_request", side_effect=fake_http):
                entry = quotas.fetch_grok(home)

        self.assertEqual(entry["provider"], "grok")
        self.assertEqual(entry["source"], "grok-web")
        self.assertEqual(entry["engine"], "kodexbar")
        self.assertAlmostEqual(entry["usage"]["primary"]["usedPercent"], 57.0, places=3)
        self.assertEqual(entry["usage"]["primary"]["resetsAt"], "2026-07-22T15:26:13Z")
        self.assertNotIn("windowMinutes", entry["usage"]["primary"])
        self.assertNotIn(TEST_GROK_KEY, json.dumps(entry))

    def test_grok_missing_key_is_auth_relogin(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            # No auth.json
            with patch.object(quotas, "upstream_path", return_value="/fake/codexbar"), patch.object(
                quotas, "upstream_entries", side_effect=AssertionError("must not delegate on auth")
            ):
                entries = quotas.fetch_provider("grok", None, home)
        self.assertEqual(entries[0]["error"]["category"], "authentication")
        self.assertFalse(entries[0]["error"]["retryable"])
        self.assertEqual(entries[0]["error"]["message"], quotas.GROK_AUTH_RELOGIN)
        self.assertIn("grok login", entries[0]["error"]["message"].lower())

    def test_grok_timeout_is_retryable(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            self._write_grok_auth(home)
            calls = {"n": 0}

            def fake_http(method, url, headers=None, body=None, timeout=None):
                calls["n"] += 1
                raise quotas.FetchFallback("HTTP timeout failure for POST", "timeout", True)

            with patch.object(quotas, "http_request", side_effect=fake_http), patch.object(
                quotas, "upstream_path", return_value=None
            ):
                entries = quotas.fetch_provider("grok", None, home)

        self.assertEqual(calls["n"], 2)  # one retry on timeout
        self.assertEqual(entries[0]["error"]["category"], "timeout")
        self.assertTrue(entries[0]["error"]["retryable"])
        self.assertEqual(entries[0]["error"]["message"], quotas.GROK_TIMEOUT)
        self.assertNotIn(TEST_GROK_KEY, json.dumps(entries))

    def test_antigravity_still_delegates_to_upstream(self) -> None:
        with patch.object(
            quotas,
            "upstream_entries",
            return_value=[{"provider": "antigravity", "source": "cli", "usage": {"primary": None}}],
        ) as upstream, patch.object(quotas, "upstream_path", return_value="/fake/codexbar"):
            entries = quotas.fetch_provider("antigravity", None)
        upstream.assert_called_once_with("antigravity", None)
        self.assertEqual(entries[0]["source"], "cli")
        self.assertEqual(entries[0]["provider"], "antigravity")

    def test_native_errors_never_include_secrets_in_messages(self) -> None:
        """Adversarial non-leak coverage for stdout-equivalent blobs (H1/H2/H4/H5/H8)."""
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            self._write_codex_auth(home, token=TEST_CODEX_TOKEN)
            self._write_grok_auth(home, key=TEST_GROK_KEY)

            def boom_500(method, url, headers=None, body=None, timeout=None):
                return 500, {}, b"fail"

            def boom_trailer_auth(method, url, headers=None, body=None, timeout=None):
                data = build_minimal_grok_billing_frame(12.0, 1784733973)
                trailer = build_grpc_web_trailer_frame(16, f"token={TEST_GROK_KEY}")
                return 200, {"content-type": "application/grpc-web+proto"}, data + trailer

            def boom_protobuf_garbage(method, url, headers=None, body=None, timeout=None):
                # Valid percent then truncated varint (must not succeed or leak).
                percent = _protobuf_key(1, 5) + struct.pack("<f", 57.0)
                nested = percent + b"\x80"  # truncated varint tag
                message = _protobuf_key(1, 2) + _encode_varint(len(nested)) + nested
                frame = b"\x00" + len(message).to_bytes(4, "big") + message
                return 200, {}, frame

            def boom_deep_payload(method, url, headers=None, body=None, timeout=None):
                # Deeply nested empty length-delimited fields to exercise depth limits.
                blob = b""
                for _ in range(quotas.PROTOBUF_MAX_DEPTH + 8):
                    blob = _protobuf_key(1, 2) + _encode_varint(len(blob)) + blob
                frame = b"\x00" + len(blob).to_bytes(4, "big") + blob
                return 200, {}, frame

            def boom_zero_percent(method, url, headers=None, body=None, timeout=None):
                frame = build_minimal_grok_billing_frame(0.0, 1784733973)
                return 200, {}, frame

            def fake_urlopen_invalid_header(request, timeout=None):
                # Real seam path: urllib-style ValueError that embeds the secret.
                raise ValueError(f"Invalid header value b'Bearer {TEST_CODEX_TOKEN}\\n'")

            blobs: list[str] = []

            with patch.object(quotas, "upstream_path", return_value=None):
                with patch.object(quotas, "http_request", side_effect=boom_500):
                    blobs.append(json.dumps(quotas.fetch_provider("codex", None, home)))
                    blobs.append(json.dumps(quotas.fetch_provider("grok", None, home)))

                # H1: exercise real http_request (do not mock the seam away).
                with patch.object(quotas, "urlopen", side_effect=fake_urlopen_invalid_header):
                    blobs.append(json.dumps(quotas.fetch_provider("codex", None, home)))

                with patch.object(quotas, "http_request", side_effect=boom_trailer_auth):
                    blobs.append(json.dumps(quotas.fetch_provider("grok", None, home)))

                with patch.object(quotas, "http_request", side_effect=boom_protobuf_garbage):
                    blobs.append(json.dumps(quotas.fetch_provider("grok", None, home)))

                with patch.object(quotas, "http_request", side_effect=boom_deep_payload):
                    blobs.append(json.dumps(quotas.fetch_provider("grok", None, home)))

                with patch.object(quotas, "http_request", side_effect=boom_zero_percent):
                    zero_entries = quotas.fetch_provider("grok", None, home)
                    blobs.append(json.dumps(zero_entries))
                    self.assertAlmostEqual(zero_entries[0]["usage"]["primary"]["usedPercent"], 0.0)

            combined = "\n".join(blobs)
            self.assertNotIn(TEST_CODEX_TOKEN, combined)
            self.assertNotIn(TEST_GROK_KEY, combined)
            self.assertNotIn("refresh-not-used", combined)

    def test_http_request_swallows_header_value_exceptions(self) -> None:
        """H1: ValueError embedding Bearer token must become a fixed sanitized error."""
        secret = TEST_CODEX_TOKEN + "\n"

        def fake_urlopen(request, timeout=None):
            raise ValueError(f"Invalid header value b'Bearer {secret}'")

        with patch.object(quotas, "urlopen", side_effect=fake_urlopen):
            with self.assertRaises(quotas.FetchFallback) as raised:
                quotas.http_request(
                    "GET",
                    "https://example.test/usage",
                    {"Authorization": f"Bearer {TEST_CODEX_TOKEN}"},
                )
        err = raised.exception
        self.assertEqual(str(err), quotas.HTTP_REQUEST_FAILED)
        self.assertNotIn(TEST_CODEX_TOKEN, str(err))
        self.assertIsNone(err.__cause__)

    def test_malformed_codex_token_is_auth_without_leak(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            bad = TEST_CODEX_TOKEN + "\nextra"
            self._write_codex_auth(home, token=bad)
            entry = quotas.fetch_codex(home)
        self.assertEqual(entry["error"]["category"], "authentication")
        self.assertEqual(entry["error"]["message"], quotas.CODEX_CREDENTIAL_MALFORMED)
        self.assertNotIn(TEST_CODEX_TOKEN, json.dumps(entry))
        self.assertNotIn("extra", entry["error"]["message"])

    def test_codex_corrupt_json_is_permanent_not_auth(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            path = home / ".codex" / "auth.json"
            path.parent.mkdir(parents=True)
            path.write_text("{not-json", encoding="utf-8")
            with self.assertRaises(quotas.FetchFallback) as raised:
                quotas.codex_access_credentials(home)
        self.assertEqual(raised.exception.category, "permanent")
        self.assertEqual(str(raised.exception), quotas.CODEX_AUTH_INVALID_JSON)

    def test_codex_missing_auth_is_authentication(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            with self.assertRaises(quotas.FetchFallback) as raised:
                quotas.codex_access_credentials(home)
        self.assertEqual(raised.exception.category, "authentication")
        self.assertEqual(str(raised.exception), quotas.CODEX_AUTH_NOT_FOUND)

    def test_invalid_toml_fails_closed_without_default_host(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            config = home / ".codex" / "config.toml"
            config.parent.mkdir(parents=True)
            # Inline comment would fool a naive regex into dropping the real URL.
            config.write_text(
                'chatgpt_base_url = "https://custom.example/backend-api" # note\n'
                "this is not valid toml {{{{\n",
                encoding="utf-8",
            )
            with self.assertRaises(quotas.FetchFallback) as raised:
                quotas.read_chatgpt_base_url(home)
        self.assertEqual(raised.exception.category, "permanent")
        self.assertEqual(str(raised.exception), quotas.CODEX_CONFIG_TOML_INVALID)

    def test_valid_toml_reads_chatgpt_base_url(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            config = home / ".codex" / "config.toml"
            config.parent.mkdir(parents=True)
            config.write_text(
                'chatgpt_base_url = "https://custom.example/backend-api"\n',
                encoding="utf-8",
            )
            self.assertEqual(
                quotas.read_chatgpt_base_url(home),
                "https://custom.example/backend-api",
            )

    def test_grok_trailer_status_16_is_auth_even_with_data(self) -> None:
        data = build_minimal_grok_billing_frame(57.0, 1784733973)
        trailer = build_grpc_web_trailer_frame(16, "unauthenticated")
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            self._write_grok_auth(home)

            def fake_http(method, url, headers=None, body=None, timeout=None):
                return 200, {}, data + trailer

            with patch.object(quotas, "http_request", side_effect=fake_http), patch.object(
                quotas, "upstream_path", return_value=None
            ):
                entries = quotas.fetch_provider("grok", None, home)
        self.assertEqual(entries[0]["error"]["category"], "authentication")
        self.assertNotIn(TEST_GROK_KEY, json.dumps(entries))

    def test_grok_trailer_status_7_without_credential_evidence_is_permanent(self) -> None:
        trailer = build_grpc_web_trailer_frame(7, "resource exhausted region")
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            self._write_grok_auth(home)

            def fake_http(method, url, headers=None, body=None, timeout=None):
                return 200, {}, trailer

            with patch.object(quotas, "http_request", side_effect=fake_http), patch.object(
                quotas, "upstream_path", return_value=None
            ):
                entries = quotas.fetch_provider("grok", None, home)
        self.assertEqual(entries[0]["error"]["category"], "permanent")

    def test_grok_transient_grpc_statuses_delegate_to_upstream_stub(self) -> None:
        """H2: DEADLINE_EXCEEDED(4), UNAVAILABLE(14), INTERNAL(13) fall back when companion present."""
        cases = (
            (4, "timeout"),
            (14, "network"),
            (13, "network"),
        )
        for status, expected_category in cases:
            with self.subTest(status=status), tempfile.TemporaryDirectory() as directory:
                home = Path(directory)
                self._write_grok_auth(home)
                trailer = build_grpc_web_trailer_frame(status, f"grpc-status-{status}")
                upstream_calls: list[str] = []

                def fake_http(method, url, headers=None, body=None, timeout=None):
                    return 200, {}, trailer

                def fake_upstream(provider, source):
                    upstream_calls.append(provider)
                    return [{"provider": "grok", "source": "upstream", "usage": {"primary": None}}]

                with patch.object(quotas, "http_request", side_effect=fake_http), patch.object(
                    quotas, "upstream_path", return_value="/fake/codexbar"
                ), patch.object(quotas, "upstream_entries", side_effect=fake_upstream):
                    entries = quotas.fetch_provider("grok", None, home)

                self.assertEqual(upstream_calls, ["grok"])
                self.assertEqual(entries[0]["source"], "upstream")
                self.assertNotIn("error", entries[0])

    def test_grok_transient_grpc_statuses_without_upstream_are_network_or_timeout(self) -> None:
        """H2: without companion, 4/14/13 are human network/timeout, never re-login."""
        cases = (
            (4, "timeout", quotas.GROK_TIMEOUT),
            (14, "network", quotas.GROK_NETWORK),
            (13, "network", quotas.GROK_NETWORK),
        )
        for status, category, message in cases:
            with self.subTest(status=status), tempfile.TemporaryDirectory() as directory:
                home = Path(directory)
                self._write_grok_auth(home)
                trailer = build_grpc_web_trailer_frame(status, f"grpc-status-{status}")

                def fake_http(method, url, headers=None, body=None, timeout=None):
                    return 200, {}, trailer

                with patch.object(quotas, "http_request", side_effect=fake_http), patch.object(
                    quotas, "upstream_path", return_value=None
                ), patch.object(
                    quotas, "upstream_entries", side_effect=AssertionError("must not call without stub")
                ):
                    entries = quotas.fetch_provider("grok", None, home)

                err = entries[0]["error"]
                self.assertEqual(err["category"], category)
                self.assertEqual(err["message"], message)
                self.assertNotEqual(err["category"], "authentication")
                self.assertNotIn("Sign in", err["message"])
                self._assert_human_user_message(err["message"])

    def test_grok_percent_ignores_alien_path_and_rejects_truncated(self) -> None:
        # Alien fixed32 99.0 at path [2] must not beat real 57.0 at [1,1].
        alien = _protobuf_key(2, 5) + struct.pack("<f", 99.0)
        real = build_minimal_grok_billing_message(57.0, 1784733973)
        used, resets = quotas.scan_grok_billing_protobuf(alien + real)
        self.assertAlmostEqual(used, 57.0, places=3)
        self.assertIsNotNone(resets)

        # Truncated varint after a valid percent must fail closed.
        percent_only = _protobuf_key(1, 5) + struct.pack("<f", 57.0)
        nested = percent_only + b"\x80"
        truncated = _protobuf_key(1, 2) + _encode_varint(len(nested)) + nested
        with self.assertRaises(quotas.FetchFallback):
            quotas.scan_grok_billing_protobuf(truncated)

    def test_http_body_limit_rejects_oversized_payload(self) -> None:
        class HugeStream:
            def read(self, n: int = -1) -> bytes:
                return b"x" * n

        with self.assertRaises(quotas.FetchFallback) as raised:
            quotas.read_http_body_limited(HugeStream(), max_bytes=64)
        self.assertEqual(raised.exception.category, "invalid_response")
        self.assertIn("size limit", str(raised.exception).lower())

    # --- Resilience: schema-drift fallback + human error messages ---

    _USER_JARGON = ("protobuf", "gRPC", "invalid_response", "OSError", "traceback")
    # Widget purge regex from packages/kodexbar/contents/code/providerLogic.js
    # (isUnfetchableProviderError). Native human errors must not match it.
    _UNFETCHABLE_PURGE = re.compile(
        r"\bno\s+(?:available\s+)?fetch\s+strategy\b|"
        r"\bunfetchable\s+provider\b|"
        r"\bprovider\s+cannot\s+be\s+fetched\b",
        re.I,
    )

    def _assert_human_user_message(self, message: str) -> None:
        lowered = message.lower()
        for word in self._USER_JARGON:
            self.assertNotIn(word.lower(), lowered, f"user message must not include {word!r}: {message}")
        self.assertIsNone(
            self._UNFETCHABLE_PURGE.search(message),
            f"user message must not match unfetchable purge regex: {message}",
        )

    def test_codex_schema_drift_delegates_to_upstream_stub(self) -> None:
        """HTTP 200 with unmappable JSON falls back to codexbar when installed."""
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            self._write_codex_auth(home)
            upstream_calls: list[tuple[str, str | None]] = []

            def fake_http(method, url, headers=None, body=None, timeout=None):
                return 200, {"Content-Type": "application/json"}, b'{"plan_type":"pro","rate_limit":{}}'

            def fake_upstream(provider, source):
                upstream_calls.append((provider, source))
                return [{"provider": "codex", "source": "upstream", "usage": {"primary": None}}]

            with patch.object(quotas, "http_request", side_effect=fake_http), patch.object(
                quotas, "upstream_path", return_value="/fake/codexbar"
            ), patch.object(quotas, "upstream_entries", side_effect=fake_upstream):
                entries = quotas.fetch_provider("codex", None, home)

        self.assertEqual(upstream_calls, [("codex", None)])
        self.assertEqual(entries[0]["source"], "upstream")
        self.assertNotIn("error", entries[0])

    def test_codex_schema_drift_without_upstream_is_human(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            self._write_codex_auth(home)

            def fake_http(method, url, headers=None, body=None, timeout=None):
                return 200, {"Content-Type": "application/json"}, b'{"unexpected": true}'

            with patch.object(quotas, "http_request", side_effect=fake_http), patch.object(
                quotas, "upstream_path", return_value=None
            ), patch.object(
                quotas, "upstream_entries", side_effect=AssertionError("must not call without stub")
            ):
                entries = quotas.fetch_provider("codex", None, home)

        err = entries[0]["error"]
        self.assertEqual(err["category"], "invalid_response")
        self.assertEqual(err["message"], quotas.CODEX_INVALID_RESPONSE)
        self.assertIn("codexbar-cli-bin", err["message"])
        self._assert_human_user_message(err["message"])

    def _codex_corrupt_numeric_payload(self, **window_overrides: object) -> bytes:
        """Sample Codex JSON with secondary_window numeric fields overridden (allows NaN/Inf)."""
        payload = sample_codex_usage_payload()
        window = payload["rate_limit"]["secondary_window"]
        assert isinstance(window, dict)
        window.update(window_overrides)
        # Python json allows NaN/Infinity (non-standard) which mirrors corrupt upstream values.
        return json.dumps(payload, allow_nan=True).encode("utf-8")

    def test_codex_corrupt_numerics_delegate_to_upstream_stub(self) -> None:
        """H1: NaN/Inf/out-of-range Codex numerics become invalid_response and delegate."""
        cases = (
            ("reset_at_nan", {"reset_at": float("nan")}),
            ("timestamp_huge", {"reset_at": 1e100}),
            ("window_infinity", {"limit_window_seconds": float("inf")}),
            ("used_percent_negative", {"used_percent": -1}),
            ("used_percent_over_100", {"used_percent": 101}),
            ("used_percent_huge", {"used_percent": 1e308}),
        )
        for name, overrides in cases:
            with self.subTest(case=name), tempfile.TemporaryDirectory() as directory:
                home = Path(directory)
                self._write_codex_auth(home)
                response_body = self._codex_corrupt_numeric_payload(**overrides)
                upstream_calls: list[str] = []

                def fake_http(method, url, headers=None, body=None, timeout=None, _payload=response_body):
                    return 200, {"Content-Type": "application/json"}, _payload

                def fake_upstream(provider, source):
                    upstream_calls.append(provider)
                    return [{"provider": "codex", "source": "upstream", "usage": {"primary": None}}]

                with patch.object(quotas, "http_request", side_effect=fake_http), patch.object(
                    quotas, "upstream_path", return_value="/fake/codexbar"
                ), patch.object(quotas, "upstream_entries", side_effect=fake_upstream):
                    entries = quotas.fetch_provider("codex", None, home)

                self.assertEqual(upstream_calls, ["codex"], msg=name)
                self.assertEqual(entries[0]["source"], "upstream", msg=name)
                self.assertNotIn("error", entries[0], msg=name)

    def test_codex_corrupt_numerics_without_upstream_are_human_drift(self) -> None:
        """H1: without companion, corrupt numerics surface human schema-drift text."""
        cases = (
            {"reset_at": float("nan")},
            {"reset_at": 1e100},
            {"limit_window_seconds": float("inf")},
            {"used_percent": -1},
            {"used_percent": 101},
            {"used_percent": 1e308},
        )
        for overrides in cases:
            with self.subTest(overrides=overrides), tempfile.TemporaryDirectory() as directory:
                home = Path(directory)
                self._write_codex_auth(home)
                response_body = self._codex_corrupt_numeric_payload(**overrides)

                def fake_http(method, url, headers=None, body=None, timeout=None, _payload=response_body):
                    return 200, {"Content-Type": "application/json"}, _payload

                with patch.object(quotas, "http_request", side_effect=fake_http), patch.object(
                    quotas, "upstream_path", return_value=None
                ), patch.object(
                    quotas, "upstream_entries", side_effect=AssertionError("must not call without stub")
                ):
                    entries = quotas.fetch_provider("codex", None, home)

                err = entries[0]["error"]
                self.assertEqual(err["category"], "invalid_response")
                self.assertEqual(err["message"], quotas.CODEX_INVALID_RESPONSE)
                self.assertIn("codexbar-cli-bin", err["message"])
                self._assert_human_user_message(err["message"])

    def test_grok_out_of_range_used_percent_is_invalid_response(self) -> None:
        """F1: Grok map_grok_usage rejects usedPercent outside [0, 100]."""
        for percent in (-1.0, 101.0, 1e308):
            with self.subTest(percent=percent):
                with self.assertRaises(quotas.FetchFallback) as raised:
                    quotas.map_grok_usage(percent, None, None)
                self.assertEqual(raised.exception.category, "invalid_response")

    def test_grok_protobuf_garbage_delegates_to_upstream_stub(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            self._write_grok_auth(home)
            upstream_calls: list[str] = []

            def fake_http(method, url, headers=None, body=None, timeout=None):
                return 200, {}, b"\x00\x00\x00\x00\x04notp"

            def fake_upstream(provider, source):
                upstream_calls.append(provider)
                return [{"provider": "grok", "source": "upstream", "usage": {"primary": None}}]

            with patch.object(quotas, "http_request", side_effect=fake_http), patch.object(
                quotas, "upstream_path", return_value="/fake/codexbar"
            ), patch.object(quotas, "upstream_entries", side_effect=fake_upstream):
                entries = quotas.fetch_provider("grok", None, home)

        self.assertEqual(upstream_calls, ["grok"])
        self.assertEqual(entries[0]["source"], "upstream")

    def test_grok_protobuf_garbage_without_upstream_is_human(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            self._write_grok_auth(home)

            def fake_http(method, url, headers=None, body=None, timeout=None):
                # Truncated varint after a valid percent path: invalid_response.
                percent = _protobuf_key(1, 5) + struct.pack("<f", 57.0)
                nested = percent + b"\x80"
                message = _protobuf_key(1, 2) + _encode_varint(len(nested)) + nested
                frame = b"\x00" + len(message).to_bytes(4, "big") + message
                return 200, {}, frame

            with patch.object(quotas, "http_request", side_effect=fake_http), patch.object(
                quotas, "upstream_path", return_value=None
            ):
                entries = quotas.fetch_provider("grok", None, home)

        err = entries[0]["error"]
        self.assertEqual(err["category"], "invalid_response")
        self.assertEqual(err["message"], quotas.GROK_INVALID_RESPONSE)
        self.assertIn("codexbar-cli-bin", err["message"])
        self._assert_human_user_message(err["message"])

    def test_codex_missing_token_never_delegates(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            # No auth.json
            with patch.object(quotas, "upstream_path", return_value="/fake/codexbar"), patch.object(
                quotas, "upstream_entries", side_effect=AssertionError("must not delegate on auth")
            ):
                entries = quotas.fetch_provider("codex", None, home)
        self.assertEqual(entries[0]["error"]["category"], "authentication")
        self.assertEqual(entries[0]["error"]["message"], quotas.CODEX_AUTH_RELOGIN)
        self._assert_human_user_message(entries[0]["error"]["message"])

    def test_network_and_timeout_still_delegate_with_stub(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            self._write_codex_auth(home)
            self._write_grok_auth(home)

            def boom_network(method, url, headers=None, body=None, timeout=None):
                raise quotas.FetchFallback("HTTP request failed", "network", True)

            def boom_timeout(method, url, headers=None, body=None, timeout=None):
                raise quotas.FetchFallback("HTTP timeout failure for POST", "timeout", True)

            with patch.object(quotas, "upstream_path", return_value="/fake/codexbar"), patch.object(
                quotas,
                "upstream_entries",
                return_value=[{"provider": "stub", "source": "upstream", "usage": {"primary": None}}],
            ) as upstream:
                with patch.object(quotas, "http_request", side_effect=boom_network):
                    codex_entries = quotas.fetch_provider("codex", None, home)
                with patch.object(quotas, "http_request", side_effect=boom_timeout):
                    grok_entries = quotas.fetch_provider("grok", None, home)

        self.assertEqual(codex_entries[0]["source"], "upstream")
        self.assertEqual(grok_entries[0]["source"], "upstream")
        self.assertGreaterEqual(upstream.call_count, 2)

    def test_network_without_stub_is_human(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            self._write_codex_auth(home)
            self._write_grok_auth(home)

            def boom(method, url, headers=None, body=None, timeout=None):
                raise quotas.FetchFallback("HTTP request failed", "network", True)

            with patch.object(quotas, "http_request", side_effect=boom), patch.object(
                quotas, "upstream_path", return_value=None
            ):
                codex = quotas.fetch_provider("codex", None, home)
                grok = quotas.fetch_provider("grok", None, home)

        self.assertEqual(codex[0]["error"]["message"], quotas.CODEX_NETWORK)
        self.assertEqual(grok[0]["error"]["message"], quotas.GROK_NETWORK)
        self._assert_human_user_message(codex[0]["error"]["message"])
        self._assert_human_user_message(grok[0]["error"]["message"])

    def test_permanent_no_plan_style_never_delegates(self) -> None:
        """Non-parse permanent failures must not fall back to codexbar."""
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            self._write_codex_auth(home)

            def fake_http(method, url, headers=None, body=None, timeout=None):
                return 404, {}, b"not found"

            with patch.object(quotas, "http_request", side_effect=fake_http), patch.object(
                quotas, "upstream_path", return_value="/fake/codexbar"
            ), patch.object(
                quotas, "upstream_entries", side_effect=AssertionError("must not delegate permanent")
            ):
                entries = quotas.fetch_provider("codex", None, home)

        self.assertEqual(entries[0]["error"]["category"], "permanent")
        self.assertEqual(entries[0]["error"]["message"], quotas.CODEX_PERMANENT)
        self._assert_human_user_message(entries[0]["error"]["message"])

    def test_native_and_companion_both_fail_uses_dual_failure_message(self) -> None:
        """H3: when companion was tried and also failed, do not advise installing it."""
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            self._write_codex_auth(home)
            self._write_grok_auth(home)

            def fake_codex_http(method, url, headers=None, body=None, timeout=None):
                return 200, {"Content-Type": "application/json"}, b'{"unexpected": true}'

            def boom_upstream(provider, source):
                raise quotas.FetchFallback(
                    "upstream codexbar returned secret-should-not-leak TOKEN=abc",
                    "timeout",
                    True,
                )

            with patch.object(quotas, "http_request", side_effect=fake_codex_http), patch.object(
                quotas, "upstream_path", return_value="/fake/codexbar"
            ), patch.object(quotas, "upstream_entries", side_effect=boom_upstream):
                codex_entries = quotas.fetch_provider("codex", None, home)

            trailer = build_grpc_web_trailer_frame(14, "unavailable")
            with patch.object(
                quotas, "http_request", side_effect=lambda *a, **k: (200, {}, trailer)
            ), patch.object(quotas, "upstream_path", return_value="/fake/codexbar"), patch.object(
                quotas, "upstream_entries", side_effect=boom_upstream
            ):
                grok_entries = quotas.fetch_provider("grok", None, home)

        codex_err = codex_entries[0]["error"]
        self.assertEqual(codex_err["message"], quotas.CODEX_BOTH_FAILED)
        self.assertEqual(codex_err["category"], "invalid_response")
        self.assertNotIn("Install the codexbar-cli-bin", codex_err["message"])
        self.assertNotIn("secret-should-not-leak", codex_err["message"])
        self.assertNotIn("TOKEN=abc", codex_err["message"])
        self._assert_human_user_message(codex_err["message"])

        grok_err = grok_entries[0]["error"]
        self.assertEqual(grok_err["message"], quotas.GROK_BOTH_FAILED)
        self.assertEqual(grok_err["category"], "network")
        self.assertNotIn("Install the codexbar-cli-bin", grok_err["message"])
        self.assertNotIn("secret-should-not-leak", grok_err["message"])
        self._assert_human_user_message(grok_err["message"])

    def test_user_visible_native_errors_have_no_technical_jargon(self) -> None:
        """H4: every user-visible message constant is free of jargon and purge phrases."""
        messages = [
            quotas.FIRST_RUN_CLAUDE_GUIDANCE,
            quotas.CODEX_AUTH_RELOGIN,
            quotas.CODEX_AUTH_NOT_FOUND,
            quotas.CODEX_AUTH_MISSING_TOKENS,
            quotas.CODEX_AUTH_EXPIRED,
            quotas.CODEX_AUTH_UNREADABLE,
            quotas.CODEX_AUTH_INVALID_JSON,
            quotas.CODEX_CONFIG_TOML_INVALID,
            quotas.CODEX_CREDENTIAL_MALFORMED,
            quotas.CODEX_NETWORK,
            quotas.CODEX_TIMEOUT,
            quotas.CODEX_INVALID_RESPONSE,
            quotas.CODEX_BOTH_FAILED,
            quotas.CODEX_PERMANENT,
            quotas.GROK_AUTH_RELOGIN,
            quotas.GROK_AUTH_NOT_FOUND,
            quotas.GROK_AUTH_MISSING_KEY,
            quotas.GROK_AUTH_UNREADABLE,
            quotas.GROK_AUTH_INVALID_JSON,
            quotas.GROK_CREDENTIAL_MALFORMED,
            quotas.GROK_NETWORK,
            quotas.GROK_TIMEOUT,
            quotas.GROK_INVALID_RESPONSE,
            quotas.GROK_BOTH_FAILED,
            quotas.GROK_PERMANENT,
            quotas.GROK_PERMISSION_DENIED,
        ]
        # Guard must not silently drop a constant: re-list distinct values for coverage report.
        distinct = sorted(set(messages))
        self.assertGreaterEqual(len(distinct), 20)
        for message in messages:
            self._assert_human_user_message(message)
        # TOML invalid must be actionable (not "were ignored").
        self.assertNotIn("were ignored", quotas.CODEX_CONFIG_TOML_INVALID.lower())
        self.assertIn("fix or remove", quotas.CODEX_CONFIG_TOML_INVALID.lower())


if __name__ == "__main__":
    unittest.main()
