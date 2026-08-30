#!/usr/bin/env python3
"""Prove the root installer works with and without Plasma tools."""

from __future__ import annotations

import os
from pathlib import Path
import shutil
import stat
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
INSTALL = ROOT / "install.sh"
UNINSTALL = ROOT / "uninstall.sh"
ISOLATED_TOOLS = (
    "bash",
    "cat",
    "chmod",
    "cp",
    "dirname",
    "env",
    "grep",
    "install",
    "ln",
    "mkdir",
    "python3",
    "readlink",
    "rm",
    "rmdir",
    "sed",
    "sh",
    "uname",
)


class RootInstallerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.temp = Path(self.temporary.name)
        self.home = self.temp / "home"
        self.home.mkdir()
        self.bindir = self.temp / "bin"
        self.bindir.mkdir()
        for name in ISOLATED_TOOLS:
            located = shutil.which(name)
            self.assertIsNotNone(located, f"test host is missing {name}")
            (self.bindir / name).symlink_to(located)

    def environment(self, language: str = "en") -> dict[str, str]:
        locale = "es_MX.UTF-8" if language == "es" else "C"
        env = os.environ.copy()
        env.pop("LANGUAGE", None)
        env.update(
            {
                "HOME": str(self.home),
                "PATH": str(self.bindir),
                "LANG": locale,
                "LC_ALL": locale,
                "XDG_STATE_HOME": str(self.home / ".local/state"),
            }
        )
        return env

    def add_kpackagetool(self, already_installed: bool = False) -> Path:
        log = self.temp / "kpackagetool.log"
        stub = self.bindir / "kpackagetool6"
        search_body = (
            "    printf '%s\\n' 'Name : KodexBar Suite'\n    exit 0\n"
            if already_installed
            else "    exit 1\n"
        )
        stub.write_text(
            "#!/usr/bin/env bash\n"
            "printf '%s\\n' \"$*\" >> \"$KODEXBAR_TEST_KPACKAGE_LOG\"\n"
            "if [[ \"${3:-}\" == \"-s\" ]]; then\n"
            + search_body
            + "fi\n"
            "exit 0\n",
            encoding="utf-8",
        )
        stub.chmod(stub.stat().st_mode | stat.S_IEXEC)
        return log

    def run_script(self, script: Path, language: str = "en", extra: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
        env = self.environment(language)
        if extra:
            env.update(extra)
        return subprocess.run(
            [str(script)],
            text=True,
            capture_output=True,
            check=False,
            env=env,
            cwd=str(ROOT),
        )

    def installed_engine_files(self) -> dict[str, Path]:
        data = self.home / ".local/share/ai-cli-control"
        bindir = self.home / ".local/bin"
        return {
            "ai": bindir / "ai",
            "quotas": bindir / "kodexbar-quotas",
            "panel": bindir / "kodexbar-panel",
            "tray": bindir / "kodexbar-tray",
            "skills": bindir / "kodexbar-skills",
            "local_ai": bindir / "local-ai",
            "data_ai": data / "ai",
        }

    def assert_engine_installed(self) -> None:
        files = self.installed_engine_files()
        for name, path in files.items():
            self.assertTrue(path.exists(), f"missing {name} at {path}")
        marker = self.home / ".local/state/kodexbar-suite/install-marker"
        self.assertTrue(marker.is_file())
        text = marker.read_text(encoding="utf-8")
        self.assertIn("product=KodexBar Suite\n", text)

    def test_install_without_plasma_installs_engine_only(self) -> None:
        result = self.run_script(INSTALL)
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assertIn("kpackagetool6 was not found", result.stdout)
        self.assertIn("data engine only, no Plasma widget", result.stdout)
        self.assertIn("On GNOME or COSMIC use kodexbar-tray", result.stdout)
        self.assertIn("Note: ", result.stdout)
        self.assertIn(".local/bin is not on PATH", result.stdout)
        self.assert_engine_installed()
        marker = (self.home / ".local/state/kodexbar-suite/install-marker").read_text(encoding="utf-8")
        self.assertIn("plasma=0\n", marker)
        panel = self.installed_engine_files()["panel"]
        snippet = subprocess.run(
            [str(panel), "--waybar-snippet"],
            text=True,
            capture_output=True,
            check=False,
            env=self.environment(),
        )
        self.assertEqual(snippet.returncode, 0, snippet.stderr)
        self.assertIn("custom/kodexbar", snippet.stdout)

    def test_spanish_install_without_plasma(self) -> None:
        result = self.run_script(INSTALL, language="es")
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assertIn("No está kpackagetool6", result.stdout)
        self.assertIn("solo motor de datos", result.stdout)

    def test_install_with_plasma_records_widget(self) -> None:
        log = self.add_kpackagetool()
        result = self.run_script(INSTALL, extra={"KODEXBAR_TEST_KPACKAGE_LOG": str(log)})
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assertIn("Plasma widget and data engine", result.stdout)
        self.assertNotIn("kpackagetool6 was not found", result.stdout)
        self.assert_engine_installed()
        marker = (self.home / ".local/state/kodexbar-suite/install-marker").read_text(encoding="utf-8")
        self.assertIn("plasma=1\n", marker)
        logged = log.read_text(encoding="utf-8")
        self.assertIn("-t Plasma/Applet -s org.kde.plasma.kodexbar", logged)
        self.assertIn("-t Plasma/Applet -i ", logged)

    def test_uninstall_without_plasma_removes_engine(self) -> None:
        installed = self.run_script(INSTALL)
        self.assertEqual(installed.returncode, 0, installed.stderr)
        removed = self.run_script(UNINSTALL)
        self.assertEqual(removed.returncode, 0, removed.stderr + removed.stdout)
        self.assertIn("KodexBar Suite uninstalled", removed.stdout)
        self.assertFalse((self.home / ".local/bin/ai").exists())
        self.assertFalse((self.home / ".local/share/ai-cli-control/ai").exists())
        self.assertFalse((self.home / ".local/state/kodexbar-suite/install-marker").exists())

    def test_uninstall_skips_missing_kpackagetool_when_plasma_was_installed(self) -> None:
        marker_dir = self.home / ".local/state/kodexbar-suite"
        marker_dir.mkdir(parents=True)
        (marker_dir / "install-marker").write_text(
            "\n".join(
                [
                    "product=KodexBar Suite",
                    "plugin_id=org.kde.plasma.kodexbar",
                    "plugin_type=Plasma/Applet",
                    f"source={ROOT}",
                    "plasma=1",
                    "",
                ]
            ),
            encoding="utf-8",
        )
        data = self.home / ".local/share/ai-cli-control"
        data.mkdir(parents=True)
        (data / ".ai-cli-control-owner").write_text("ai-cli-control\n", encoding="utf-8")
        (data / "ai").write_text("#!/bin/sh\n", encoding="utf-8")
        bindir = self.home / ".local/bin"
        bindir.mkdir(parents=True)
        (bindir / "ai").symlink_to(data / "ai")
        result = self.run_script(UNINSTALL)
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assertIn("kpackagetool6 was not found", result.stdout)
        self.assertIn("KodexBar Suite uninstalled", result.stdout)

    def test_old_marker_without_plasma_key_still_tries_widget_removal(self) -> None:
        log = self.add_kpackagetool(already_installed=True)
        marker_dir = self.home / ".local/state/kodexbar-suite"
        marker_dir.mkdir(parents=True)
        (marker_dir / "install-marker").write_text(
            "\n".join(
                [
                    "product=KodexBar Suite",
                    "plugin_id=org.kde.plasma.kodexbar",
                    "plugin_type=Plasma/Applet",
                    f"source={ROOT}",
                    "",
                ]
            ),
            encoding="utf-8",
        )
        data = self.home / ".local/share/ai-cli-control"
        data.mkdir(parents=True)
        (data / ".ai-cli-control-owner").write_text("ai-cli-control\n", encoding="utf-8")
        result = self.run_script(UNINSTALL, extra={"KODEXBAR_TEST_KPACKAGE_LOG": str(log)})
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        logged = log.read_text(encoding="utf-8")
        self.assertIn("-t Plasma/Applet -s org.kde.plasma.kodexbar", logged)
        self.assertIn("-t Plasma/Applet -r org.kde.plasma.kodexbar", logged)

    def test_rejects_python_older_than_3_10(self) -> None:
        stub = self.bindir / "python3"
        stub.unlink()
        stub.write_text(
            "#!/usr/bin/env bash\n"
            "if [[ \"${1:-}\" == \"-c\" ]]; then\n"
            "    exit 1\n"
            "fi\n"
            "exit 0\n",
            encoding="utf-8",
        )
        stub.chmod(stub.stat().st_mode | stat.S_IEXEC)
        result = self.run_script(INSTALL)
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn("python3 is too old", result.stderr)


if __name__ == "__main__":
    unittest.main()
