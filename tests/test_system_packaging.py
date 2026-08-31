#!/usr/bin/env python3
"""Verify the shared system payload used by DEB and RPM packages."""

from __future__ import annotations

import json
import os
from pathlib import Path
import re
import stat
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
STAGER = ROOT / "packaging/system/stage-package.sh"
METADATA = ROOT / "packages/kodexbar/metadata.json"
COMMANDS = (
    "ai",
    "kodexbar-quotas",
    "kodexbar-panel",
    "kodexbar-tray",
    "local-ai",
    "kodexbar-skills",
)


class SystemPackagingTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.temp = Path(self.temporary.name)
        self.destination = self.temp / "package-root"

    def stage(self) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["bash", str(STAGER), str(self.destination)],
            cwd=self.temp,
            text=True,
            capture_output=True,
            check=False,
        )

    def test_shared_payload_has_commands_widget_icons_and_docs(self) -> None:
        result = self.stage()
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)

        payload = self.destination / "usr/lib/kodexbar-suite/ai-cli-control"
        for command in COMMANDS:
            installed = payload / command
            link = self.destination / "usr/bin" / command
            self.assertTrue(installed.is_file(), f"missing payload command {command}")
            self.assertTrue(installed.stat().st_mode & stat.S_IXUSR, f"{command} is not executable")
            self.assertTrue(link.is_symlink(), f"missing command link {command}")
            self.assertEqual(
                os.readlink(link),
                f"../lib/kodexbar-suite/ai-cli-control/{command}",
            )

        drivers = payload / "local_ai_drivers"
        self.assertEqual(
            {path.name for path in drivers.iterdir()},
            {"__init__.py", "builtin.py", "descriptors.py"},
        )

        plasmoid = self.destination / "usr/share/plasma/plasmoids/org.kde.plasma.kodexbar"
        installed_metadata = json.loads((plasmoid / "metadata.json").read_text(encoding="utf-8"))
        source_metadata = json.loads(METADATA.read_text(encoding="utf-8"))
        self.assertEqual(installed_metadata, source_metadata)
        self.assertTrue((plasmoid / "contents/ui/main.qml").is_file())
        for forbidden in ("tests", "screenshots", "scripts", ".git"):
            self.assertFalse((plasmoid / forbidden).exists(), f"development content leaked: {forbidden}")

        icons = self.destination / "usr/share/icons/hicolor/scalable/apps"
        self.assertEqual(
            {path.name for path in icons.iterdir()},
            {
                "kodexbar-tray-ok.svg",
                "kodexbar-tray-warning.svg",
                "kodexbar-tray-critical.svg",
            },
        )
        self.assertTrue((self.destination / "usr/share/licenses/kodexbar-suite/LICENSE").is_file())
        self.assertTrue((self.destination / "usr/share/doc/kodexbar-suite/README.es.md").is_file())

    def test_staged_commands_report_the_metadata_version(self) -> None:
        result = self.stage()
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        version = json.loads(METADATA.read_text(encoding="utf-8"))["KPlugin"]["Version"]
        payload = self.destination / "usr/lib/kodexbar-suite/ai-cli-control"
        expected = {
            "ai": f"ai-cli-control {version}",
            "kodexbar-quotas": f"kodexbar-quotas {version}",
            "local-ai": version,
            "kodexbar-skills": version,
        }
        for command, wanted in expected.items():
            completed = subprocess.run(
                [str(payload / command), "--version"],
                cwd=self.temp,
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)
            self.assertIn(wanted, completed.stdout)

    def test_stager_refuses_root_and_nonempty_destinations(self) -> None:
        root_result = subprocess.run(
            ["bash", str(STAGER), "/"],
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(root_result.returncode, 2)
        self.assertIn("never /", root_result.stderr)

        self.destination.mkdir()
        sentinel = self.destination / "keep-me"
        sentinel.write_text("unchanged\n", encoding="utf-8")
        result = self.stage()
        self.assertEqual(result.returncode, 2)
        self.assertIn("must be empty", result.stderr)
        self.assertEqual(sentinel.read_text(encoding="utf-8"), "unchanged\n")

    def test_native_templates_use_the_same_package_identity(self) -> None:
        deb_control = (ROOT / "packaging/deb/control.in").read_text(encoding="utf-8")
        rpm_spec = (ROOT / "packaging/rpm/kodexbar-suite.spec.in").read_text(encoding="utf-8")
        self.assertIn("Package: kodexbar-suite\n", deb_control)
        self.assertIn("Architecture: all\n", deb_control)
        self.assertIn("Depends: bash, python3 (>= 3.10)\n", deb_control)
        self.assertIn("Name:           kodexbar-suite\n", rpm_spec)
        self.assertIn("Release:        @RELEASE@\n", rpm_spec)
        self.assertNotIn("%{?dist}", rpm_spec)
        self.assertIn("BuildArch:      noarch\n", rpm_spec)
        self.assertIn("Requires:       python3 >= 3.10\n", rpm_spec)
        self.assertIn("Requires:       python3.11\n", rpm_spec)
        self.assertIn("%global kodexbar_python /usr/bin/python3.11\n", rpm_spec)
        self.assertEqual(
            set(re.findall(r"@[A-Z_]+@", deb_control)),
            {"@VERSION@", "@RELEASE@", "@INSTALLED_SIZE@"},
        )
        self.assertEqual(
            set(re.findall(r"@[A-Z_]+@", rpm_spec)),
            {"@VERSION@", "@RELEASE@", "@CHANGELOG_DATE@"},
        )


if __name__ == "__main__":
    unittest.main()
