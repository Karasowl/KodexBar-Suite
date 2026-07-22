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
TRAY = ROOT / "kodexbar-tray"
loader = importlib.machinery.SourceFileLoader("kodexbar_tray", str(TRAY))
spec = importlib.util.spec_from_loader(loader.name, loader)
tray = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(tray)


class TrayLogicTests(unittest.TestCase):
    def test_parse_panel_output_and_icon_mapping(self) -> None:
        status = tray.parse_panel_output(json.dumps({
            "text": "Cx S 12%", "tooltip": "Cx (codex): Session 12%", "class": "warning", "providers": [],
        }))
        self.assertEqual(status["class"], "warning")
        self.assertEqual(tray.icon_name("ok"), "kodexbar-tray-ok.svg")
        self.assertEqual(tray.icon_name("unexpected"), "kodexbar-tray-critical.svg")
        with self.assertRaisesRegex(ValueError, "clase inválida"):
            tray.parse_panel_output('{"text":"x","tooltip":"x","class":"bad","providers":[]}')

    def test_resolve_icon_directory_prefers_first_complete_candidate(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            user_icons = root / "user" / "icons"
            system_icons = root / "system" / "icons"
            empty = root / "empty"
            empty.mkdir(parents=True)
            system_icons.mkdir(parents=True)
            for name in ("kodexbar-tray-ok.svg", "kodexbar-tray-warning.svg", "kodexbar-tray-critical.svg"):
                (system_icons / name).write_text("<svg/>", encoding="utf-8")
            # Empty user directory loses to the system package layout.
            chosen = tray.resolve_icon_directory([user_icons, system_icons, empty])
            self.assertEqual(chosen, system_icons)
            # Explicit override keeps icon_path stable for callers and tests.
            self.assertEqual(
                tray.icon_path("ok", icon_directory=user_icons),
                str(user_icons / "kodexbar-tray-ok.svg"),
            )
            # Complete user install wins over system when both are present.
            user_icons.mkdir(parents=True)
            for name in ("kodexbar-tray-ok.svg", "kodexbar-tray-warning.svg", "kodexbar-tray-critical.svg"):
                (user_icons / name).write_text("<svg/>", encoding="utf-8")
            self.assertEqual(
                tray.resolve_icon_directory([user_icons, system_icons]),
                user_icons,
            )
            # Fallback when no candidate has icons yet: first search path.
            self.assertEqual(tray.resolve_icon_directory([empty, user_icons.parent]), empty)

    def test_menu_model_includes_provider_quotas_and_error(self) -> None:
        model = tray.menu_model({
            "text": "Cx S 12%", "tooltip": "normal", "class": "ok",
            "providers": [
                {"provider": "codex", "label": "Cx", "percentages": {"session": 12, "weekly": 34}},
                {"provider": "antigravity", "label": "Ag", "percentages": {}, "quotas": [
                    {"key": "gemini-weekly", "group": "gemini", "label": "W", "percentage": 0},
                    {"key": "gemini-5h", "group": "gemini", "label": "S", "percentage": 0},
                    {"key": "claude-gpt-weekly", "group": "claude-gpt", "label": "CW", "percentage": 34},
                    {"key": "claude-gpt-5h", "group": "claude-gpt", "label": "C5h", "percentage": 100},
                ]},
                {"provider": "grok", "label": "Gk", "error": True, "error_message": "sin token"},
            ],
        })
        self.assertEqual(model[0], {"kind": "info", "label": "Cx (codex): Sesión 12%, Semanal 34%"})
        self.assertEqual(model[1], {"kind": "info", "label": "Ag (antigravity): S 0%, W 0%"})
        self.assertEqual(model[2], {"kind": "info", "label": "Gk (grok): ERR, sin token"})
        self.assertEqual([item["kind"] for item in model[-5:]], ["separator", "refresh", "open", "separator", "quit"])
        error = tray.menu_model(tray.error_status("panel falló"))
        self.assertEqual(error[0], {"kind": "info", "label": "panel falló"})

    def test_interval_validation(self) -> None:
        self.assertEqual(tray.validate_interval("60"), 60)
        self.assertEqual(tray.validate_interval("300"), 300)
        with self.assertRaisesRegex(Exception, "al menos 60"):
            tray.validate_interval("59")
        with self.assertRaisesRegex(Exception, "número entero"):
            tray.validate_interval("many")

    def test_fetch_status_uses_stub_panel_and_degrades_on_bad_output(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            panel = root / "kodexbar-panel"
            panel.write_text(
                "#!" + os.sys.executable + "\n"
                "import json\n"
                "print(json.dumps({'text':'Cx S 12%','tooltip':'Cx detail','class':'ok','providers':[]}))\n",
                encoding="utf-8",
            )
            panel.chmod(0o755)
            status = tray.fetch_status(str(panel))
            self.assertEqual(status["text"], "Cx S 12%")
            panel.write_text("#!/bin/sh\nprintf not-json\n", encoding="utf-8")
            panel.chmod(0o755)
            failed = tray.fetch_status(str(panel))
            self.assertEqual(failed["class"], "critical")
            self.assertIn("JSON inválido", failed["error"])

    def test_autostart_content_install_and_remove(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            content = tray.autostart_desktop("/tmp/kodexbar-tray")
            self.assertIn("Exec=/tmp/kodexbar-tray", content)
            self.assertIn("X-GNOME-Autostart-enabled=true", content)
            destination = tray.install_autostart("/tmp/kodexbar-tray", home)
            self.assertEqual(destination.read_text(encoding="utf-8"), content)
            self.assertTrue(tray.remove_autostart(home))
            self.assertFalse(tray.remove_autostart(home))

    def test_help_and_missing_bindings_path_do_not_import_gtk(self) -> None:
        help_result = subprocess.run(
            [str(TRAY), "--help"], text=True, capture_output=True, check=False
        )
        self.assertEqual(help_result.returncode, 0, help_result.stderr)
        self.assertIn("--autostart-install", help_result.stdout)
        with tempfile.TemporaryDirectory() as directory:
            shadow = Path(directory) / "gi.py"
            shadow.write_text("raise ImportError('shadowed gi')\n", encoding="utf-8")
            environment = os.environ.copy()
            environment["PYTHONPATH"] = str(Path(directory))
            missing = subprocess.run(
                [str(TRAY)], text=True, capture_output=True, check=False, env=environment
            )
        self.assertEqual(missing.returncode, 1)
        self.assertIn("libayatana-appindicator", missing.stderr)
        self.assertIn("gir1.2-ayatanaappindicator3-0.1", missing.stderr)
        self.assertIn("libayatana-appindicator-gtk3", missing.stderr)
        self.assertIn("AppIndicator and KStatusNotifierItem Support", missing.stderr)


if __name__ == "__main__":
    unittest.main()
