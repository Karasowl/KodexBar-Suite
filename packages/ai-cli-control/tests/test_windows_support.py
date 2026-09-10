from __future__ import annotations

import importlib.machinery
import importlib.util
import os
from pathlib import Path, PureWindowsPath
import stat
import tempfile
import unittest
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
QUOTAS = ROOT / "kodexbar-quotas"
TRAY_WIN = ROOT / "kodexbar-tray-win"


def load_engine():
    loader = importlib.machinery.SourceFileLoader("kodexbar_quotas_windows_test", str(QUOTAS))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


def load_tray_win():
    loader = importlib.machinery.SourceFileLoader("kodexbar_tray_win_test", str(TRAY_WIN))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


engine = load_engine()
tray_win = load_tray_win()

WINDOWS_HOME = PureWindowsPath("C:/Users/dev")


class CostLockTests(unittest.TestCase):
    def test_lock_excludes_second_holder_until_release(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            lock_path = Path(directory) / "cost.lock"
            first = engine.acquire_cost_lock(lock_path, blocking=False)
            self.assertIsNotNone(first)
            try:
                second = engine.acquire_cost_lock(lock_path, blocking=False)
                self.assertIsNone(second)
            finally:
                engine.release_cost_lock(first)
            third = engine.acquire_cost_lock(lock_path, blocking=False)
            self.assertIsNotNone(third)
            engine.release_cost_lock(third)


class WindowsPathTests(unittest.TestCase):
    def test_home_directory_prefers_userprofile_on_windows(self) -> None:
        with mock.patch.object(engine, "IS_WINDOWS", True), mock.patch.dict(
            os.environ, {"USERPROFILE": "C:\\Users\\dev"}, clear=False
        ):
            self.assertEqual(str(engine.home_directory()), str(WINDOWS_HOME))

    def test_home_directory_keeps_home_on_posix(self) -> None:
        with mock.patch.object(engine, "IS_WINDOWS", False), mock.patch.dict(os.environ, {"HOME": "/home/dev"}):
            self.assertEqual(str(engine.home_directory()), "/home/dev")

    def test_cost_cache_directory_on_windows(self) -> None:
        with mock.patch.object(engine, "IS_WINDOWS", True), mock.patch.dict(
            os.environ, {"LOCALAPPDATA": "C:\\Users\\dev\\AppData\\Local", "XDG_CACHE_HOME": ""}
        ):
            directory = engine.cost_cache_directory()
            self.assertEqual(
                str(directory).replace("\\", "/"),
                "C:/Users/dev/AppData/Local/kodexbar-suite/cache",
            )

    def test_user_config_paths_on_windows(self) -> None:
        with mock.patch.object(engine, "IS_WINDOWS", True), mock.patch.dict(
            os.environ, {"APPDATA": "C:\\Users\\dev\\AppData\\Roaming"}
        ):
            home = WINDOWS_HOME
            self.assertEqual(
                str(engine.profiles_config_path(home)).replace("\\", "/"),
                "C:/Users/dev/AppData/Roaming/kodexbar-suite/profiles.json",
            )
            self.assertEqual(
                str(engine.accounts_root_path(home)).replace("\\", "/"),
                "C:/Users/dev/AppData/Roaming/kodexbar-suite/accounts",
            )
            self.assertEqual(
                str(engine.codexbar_config_path(home)).replace("\\", "/"),
                "C:/Users/dev/AppData/Roaming/codexbar/config.json",
            )

    def test_cursor_state_db_on_windows(self) -> None:
        with mock.patch.object(engine, "IS_WINDOWS", True):
            self.assertEqual(
                str(engine.cursor_state_db_path(WINDOWS_HOME)).replace("\\", "/"),
                "C:/Users/dev/AppData/Roaming/Cursor/User/globalStorage/state.vscdb",
            )
        with mock.patch.object(engine, "IS_WINDOWS", False):
            self.assertEqual(
                engine.cursor_state_db_path(Path("/opt/devhome")),
                Path("/opt/devhome/.config/Cursor/User/globalStorage/state.vscdb"),
            )

    def test_hermes_auth_path_follows_home_on_windows(self) -> None:
        with mock.patch.object(engine, "IS_WINDOWS", True):
            self.assertEqual(
                str(engine.hermes_auth_path(WINDOWS_HOME)).replace("\\", "/"),
                "C:/Users/dev/.hermes/auth.json",
            )
        with mock.patch.object(engine, "IS_WINDOWS", False):
            self.assertEqual(
                engine.hermes_auth_path(Path("/opt/devhome")),
                Path("/opt/devhome/.hermes/auth.json"),
            )

    def test_opencodego_candidates_on_windows(self) -> None:
        with mock.patch.object(engine, "IS_WINDOWS", True), mock.patch.dict(
            os.environ, {"USERPROFILE": "C:\\Users\\dev"}
        ):
            # No credentials under the fake profile, so detection stays False
            # but the Windows candidate layout must not raise.
            self.assertFalse(engine.detect_opencodego_installed())


class WindowsSpawnTests(unittest.TestCase):
    def test_detached_kwargs_on_windows_use_creationflags(self) -> None:
        with mock.patch.object(engine, "IS_WINDOWS", True):
            self.assertIn("creationflags", engine.detached_spawn_kwargs())
            self.assertIn("creationflags", engine.new_console_spawn_kwargs())
            self.assertIn("creationflags", engine.low_priority_spawn_kwargs())

    def test_detached_kwargs_on_posix_use_session(self) -> None:
        with mock.patch.object(engine, "IS_WINDOWS", False):
            self.assertEqual(engine.detached_spawn_kwargs(), {"start_new_session": True})
            self.assertEqual(engine.new_console_spawn_kwargs(), {"start_new_session": True})
            self.assertIn("preexec_fn", engine.low_priority_spawn_kwargs())

    def test_resolved_command_only_rewrites_on_windows(self) -> None:
        argv = ["claude", "auth", "login"]
        with mock.patch.object(engine, "IS_WINDOWS", False):
            self.assertEqual(engine.resolved_command(argv), argv)
        with mock.patch.object(engine, "IS_WINDOWS", True), tempfile.TemporaryDirectory() as directory:
            # POSIX resolves a bare executable; Windows resolves PATHEXT shims.
            shim_name = "claude.cmd" if os.name == "nt" else "claude"
            shim = Path(directory) / shim_name
            shim.write_text("#!/bin/sh\n", encoding="utf-8")
            shim.chmod(shim.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
            with mock.patch.dict(os.environ, {"PATH": directory}):
                resolved = engine.resolved_command(argv)
            self.assertEqual(resolved[0], str(shim))
            self.assertEqual(resolved[1:], argv[1:])


class TrayWinSharedTests(unittest.TestCase):
    def test_status_class_falls_back_to_critical(self) -> None:
        self.assertEqual(tray_win.status_class({"class": "ok"}), "ok")
        self.assertEqual(tray_win.status_class({"class": "unexpected"}), "critical")
        self.assertEqual(tray_win.status_class({}), "critical")

    def test_missing_dependencies_message_mentions_install_command(self) -> None:
        self.assertIn("pystray", tray_win.MISSING_DEPENDENCIES_MESSAGE)
        self.assertIn("pillow", tray_win.MISSING_DEPENDENCIES_MESSAGE)


if __name__ == "__main__":
    unittest.main()
