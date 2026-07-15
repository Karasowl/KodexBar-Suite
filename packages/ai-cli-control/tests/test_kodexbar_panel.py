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


ROOT = Path(__file__).resolve().parents[1]
PANEL = ROOT / "kodexbar-panel"
FIXTURES = ROOT / "tests" / "fixtures"
loader = importlib.machinery.SourceFileLoader("kodexbar_panel", str(PANEL))
spec = importlib.util.spec_from_loader(loader.name, loader)
panel = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(panel)


class PanelAdapterTests(unittest.TestCase):
    def setUp(self) -> None:
        self.entries = json.loads((FIXTURES / "panel-engine-output.json").read_text(encoding="utf-8"))

    def test_compact_model_applies_widget_thresholds_and_error_rendering(self) -> None:
        model = panel.compact_model(self.entries, [])
        self.assertEqual(model["text"], "Cx S 12% W 52% | Cl S 50% W 80% | Gk ERR | Ag S 80% W 5%")
        self.assertEqual(model["class"], "critical")
        self.assertEqual([item["severity"] for item in model["providers"]], ["warning", "warning", "critical", "critical"])
        self.assertTrue(model["providers"][2]["error"])
        self.assertEqual(model["providers"][2]["percentages"], {"session": None, "weekly": None})

    def test_provider_filter_is_case_insensitive_ordered_and_deduplicated(self) -> None:
        selected = panel.normalize_providers(" ANTIGRAVITY,claude,antigravity ")
        model = panel.compact_model(self.entries, selected)
        self.assertEqual(selected, ["antigravity", "claude"])
        self.assertEqual(model["text"], "Ag S 80% W 5% | Cl S 50% W 80%")

    def test_waybar_output_is_valid_json_and_limits_tooltip_lines(self) -> None:
        model = panel.compact_model(self.entries, [])
        payload = panel.waybar_payload(model, 3)
        parsed = json.loads(json.dumps(payload))
        self.assertEqual(parsed["class"], "critical")
        self.assertEqual(parsed["text"], model["text"])
        self.assertLessEqual(len(parsed["tooltip"].splitlines()), 3)
        self.assertIn("Session", parsed["tooltip"])

    def test_status_json_keeps_plain_tray_data_and_provider_details(self) -> None:
        model = panel.compact_model(self.entries, [])
        payload = panel.status_payload(model, 2)
        self.assertEqual(payload["text"], model["text"])
        self.assertEqual(payload["class"], "critical")
        self.assertEqual(payload["providers"], model["providers"])
        self.assertLessEqual(len(payload["tooltip"].splitlines()), 2)

    def test_pango_escapes_untrusted_provider_data(self) -> None:
        entries = [{"provider": "<b", "error": {"message": "<span foreground='red'>oops</span>"}}]
        model = panel.compact_model(entries, [])
        rendered = panel.pango_text(model["providers"])
        self.assertIn("&lt;b ERR", rendered)
        self.assertNotIn("<b ERR", rendered)
        self.assertNotIn("oops", rendered)

    def test_waybar_escapes_untrusted_provider_data(self) -> None:
        entries = [{"provider": "hostile<&>", "name": "<&>", "error": {"message": "& <span>oops</span>"}}]
        model = panel.compact_model(entries, [])
        payload = json.loads(json.dumps(panel.waybar_payload(model, 1)))
        self.assertIn("&lt;&amp; ERR", payload["text"])
        self.assertNotIn("<& ERR", payload["text"])
        self.assertIn("&lt;&amp;&gt;", payload["tooltip"])
        self.assertIn("&amp; &lt;span&gt;oops&lt;/span&gt;", payload["tooltip"])
        self.assertNotIn("<span>oops</span>", payload["tooltip"])

    def test_cli_uses_sibling_engine_and_returns_valid_waybar_json(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            executable = root / "kodexbar-panel"
            engine = root / "kodexbar-quotas"
            executable.write_text(PANEL.read_text(encoding="utf-8"), encoding="utf-8")
            engine.write_text(
                "#!" + os.sys.executable + "\n" + textwrap.dedent("""\
                    import json
                    print(json.dumps(""" + repr(self.entries) + """))
                """),
                encoding="utf-8",
            )
            executable.chmod(0o755)
            engine.chmod(0o755)
            result = subprocess.run(
                [str(executable), "--format", "waybar", "--max-tooltip-lines", "2"],
                text=True,
                capture_output=True,
                check=True,
            )
        payload = json.loads(result.stdout)
        self.assertEqual(payload["class"], "critical")
        self.assertIn("Cx S 12%", payload["text"])
        self.assertLessEqual(len(payload["tooltip"].splitlines()), 2)

    def test_status_json_cli_keeps_legacy_formats_separate(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            executable = root / "kodexbar-panel"
            engine = root / "kodexbar-quotas"
            executable.write_text(PANEL.read_text(encoding="utf-8"), encoding="utf-8")
            engine.write_text(
                "#!" + os.sys.executable + "\nimport json\nprint(json.dumps(" + repr(self.entries) + "))\n",
                encoding="utf-8",
            )
            executable.chmod(0o755)
            engine.chmod(0o755)
            result = subprocess.run(
                [str(executable), "--status-json"], text=True, capture_output=True, check=True
            )
        payload = json.loads(result.stdout)
        self.assertEqual(payload["class"], "critical")
        self.assertIn("tooltip", payload)
        self.assertEqual(len(payload["providers"]), len(self.entries))

    def test_engine_failure_is_short_text_in_every_output_format(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            executable = root / "kodexbar-panel"
            engine = root / "kodexbar-quotas"
            executable.write_text(PANEL.read_text(encoding="utf-8"), encoding="utf-8")
            engine.write_text("#!" + os.sys.executable + "\nraise SystemExit(1)\n", encoding="utf-8")
            executable.chmod(0o755)
            engine.chmod(0o755)
            for output_format in ("text", "json", "waybar"):
                with self.subTest(output_format=output_format):
                    result = subprocess.run(
                        [str(executable), "--format", output_format], text=True, capture_output=True, check=True
                    )
                    self.assertNotIn("Traceback", result.stdout)
                    if output_format == "text":
                        self.assertEqual(result.stdout.strip(), "Quota error")
                    else:
                        payload = json.loads(result.stdout)
                        self.assertEqual(payload["class"], "critical")


if __name__ == "__main__":
    unittest.main()
