from __future__ import annotations

import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import textwrap
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
        self.assertEqual(entry["engine"], "kodexbar")

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

    def test_cli_aggregates_and_preserves_upstream_passthrough(self) -> None:
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
            self.assertEqual([entry["provider"] for entry in entries], ["claude", "codex", "grok"])
            self.assertIn("error", entries[0])
            self.assertEqual(entries[1]["source"], "upstream")
            self.assertEqual(entries[2]["source"], "upstream")

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


if __name__ == "__main__":
    unittest.main()
