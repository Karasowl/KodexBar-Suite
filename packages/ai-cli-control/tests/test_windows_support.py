from __future__ import annotations

import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path, PureWindowsPath
import stat
import tempfile
import threading
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

# Avoid /Users/ and /home/ so static_checks does not treat fixtures as personal paths.
WINDOWS_HOME = PureWindowsPath("C:/WinDev")
POSIX_HOME = Path("/opt/devhome")


class CostLockTests(unittest.TestCase):
    def setUp(self) -> None:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        # Windows resolves profiles through APPDATA even when a home is supplied.
        appdata = mock.patch.dict(os.environ, {"APPDATA": temporary.name})
        appdata.start()
        self.addCleanup(appdata.stop)

    def test_credential_lock_serializes_concurrent_writers(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "credentials.lock"
            waiting = threading.Event()
            entered = threading.Event()

            def competing_writer():
                waiting.set()
                with engine._exclusive_file_lock(path):
                    entered.set()

            with engine._exclusive_file_lock(path):
                thread = threading.Thread(target=competing_writer, daemon=True)
                thread.start()
                self.assertTrue(waiting.wait(1))
                self.assertFalse(entered.wait(0.1))
            thread.join(timeout=2)
            self.assertTrue(entered.is_set())

    def test_concurrent_account_additions_do_not_overwrite_each_other(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            with engine.ThreadPoolExecutor(max_workers=4) as executor:
                profiles = list(executor.map(lambda _: engine.add_managed_profile("codex", "Work", home), range(8)))
            self.assertEqual(len({profile.profile_id for profile in profiles}), 8)
            document = engine.load_profiles_document(home)
            self.assertEqual(len(document["codex"]), 9)

    def test_duplicate_long_account_labels_keep_valid_profile_ids(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            for _ in range(3):
                profile = engine.add_managed_profile("codex", "w" * 64, home)
                self.assertLessEqual(len(profile.profile_id), 64)
            self.assertEqual(len(engine.load_profiles_document(home)["codex"]), 4)

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
    def test_windows_tray_loads_shared_subscription_status_contract(self) -> None:
        loader = importlib.machinery.SourceFileLoader("panel_windows_contract", str(ROOT / "kodexbar-panel"))
        spec = importlib.util.spec_from_loader(loader.name, loader)
        panel = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(panel)
        shared = tray_win.load_shared_tray()
        self.assertIsNotNone(shared)
        model = panel.compact_model([{"provider": "cursor", "usage": {
            "isUnified": True, "planName": "The X Subscription",
            "identity": {"accountLabel": "xAI test-account"},
            "secondary": {"usedPercent": 28, "periodType": "weekly"}}}], [])
        status = shared.parse_panel_output(json.dumps(panel.status_payload(model, 12)))
        self.assertEqual(status["text"], "Cr W 28%")
        self.assertIn("The X Subscription [xAI test-account]", shared.provider_menu_label(status["providers"][0]))
        self.assertIn("Semanal 28%", shared.menu_model(status)[0]["label"])

    def test_managed_grok_profile_keeps_platform_paths_and_isolates_login(self) -> None:
        for windows in (False, True):
            with self.subTest(windows=windows), tempfile.TemporaryDirectory() as directory:
                home = Path(directory)
                roaming = home / "Roaming with spaces"
                with mock.patch.object(engine, "IS_WINDOWS", windows), \
                     mock.patch.dict(os.environ, {"APPDATA": str(roaming), "GROK_HOME": ""}), \
                     mock.patch.object(engine, "command_on_path", return_value=True), \
                     mock.patch.object(engine.subprocess, "Popen") as launch:
                    profile = engine.add_managed_profile("grok", "The X Subscription", home)
                    config = roaming if windows else home / ".config"
                    auth_file = config / "kodexbar-suite" / "accounts" / "grok" / "the-x-subscription" / "auth.json"
                    self.assertEqual(profile.credential_source.auth_file, auth_file)
                    argv, env, _ = engine.login_argv_for_profile("grok", profile.profile_id, home)
                    self.assertEqual(argv, ["grok", "login"])
                    self.assertEqual(env, {"GROK_HOME": str(auth_file.parent)})
                    self.assertEqual(engine.grok_auth_path(home), home / ".grok" / "auth.json")
                    self.assertEqual([p.profile_id for p in engine.resolve_provider_profiles(["grok"], home)],
                                     ["default", "the-x-subscription"])
                    launch.assert_not_called()

    def test_home_directory_prefers_userprofile_on_windows(self) -> None:
        with mock.patch.object(engine, "IS_WINDOWS", True), mock.patch.dict(
            os.environ, {"USERPROFILE": "C:\\WinDev"}, clear=False
        ):
            self.assertEqual(str(engine.home_directory()), str(WINDOWS_HOME))

    def test_home_directory_keeps_home_on_posix(self) -> None:
        with mock.patch.object(engine, "IS_WINDOWS", False), mock.patch.dict(
            os.environ, {"HOME": str(POSIX_HOME)}
        ):
            self.assertEqual(engine.home_directory(), Path(str(POSIX_HOME)))

    def test_cost_cache_directory_on_windows(self) -> None:
        with mock.patch.object(engine, "IS_WINDOWS", True), mock.patch.dict(
            os.environ, {"LOCALAPPDATA": "C:\\WinDev\\AppData\\Local", "XDG_CACHE_HOME": ""}
        ):
            directory = engine.cost_cache_directory()
            self.assertEqual(
                str(directory).replace("\\", "/"),
                "C:/WinDev/AppData/Local/kodexbar-suite/cache",
            )

    def test_user_config_paths_on_windows(self) -> None:
        with mock.patch.object(engine, "IS_WINDOWS", True), mock.patch.dict(
            os.environ, {"APPDATA": "C:\\WinDev\\AppData\\Roaming"}
        ):
            home = WINDOWS_HOME
            self.assertEqual(
                str(engine.profiles_config_path(home)).replace("\\", "/"),
                "C:/WinDev/AppData/Roaming/kodexbar-suite/profiles.json",
            )
            self.assertEqual(
                str(engine.accounts_root_path(home)).replace("\\", "/"),
                "C:/WinDev/AppData/Roaming/kodexbar-suite/accounts",
            )
            self.assertEqual(
                str(engine.codexbar_config_path(home)).replace("\\", "/"),
                "C:/WinDev/AppData/Roaming/codexbar/config.json",
            )

    def test_cursor_state_db_on_windows(self) -> None:
        with mock.patch.object(engine, "IS_WINDOWS", True):
            self.assertEqual(
                str(engine.cursor_state_db_path(WINDOWS_HOME)).replace("\\", "/"),
                "C:/WinDev/AppData/Roaming/Cursor/User/globalStorage/state.vscdb",
            )
        with mock.patch.object(engine, "IS_WINDOWS", False):
            self.assertEqual(
                engine.cursor_state_db_path(POSIX_HOME),
                POSIX_HOME / ".config" / "Cursor" / "User" / "globalStorage" / "state.vscdb",
            )

    def test_devin_credentials_path_on_windows(self) -> None:
        with mock.patch.object(engine, "IS_WINDOWS", True), mock.patch.dict(
            os.environ, {"APPDATA": "C:/WinDev/AppData/Roaming"}
        ):
            self.assertEqual(
                str(engine.devin_credentials_path(WINDOWS_HOME)).replace("\\", "/"),
                "C:/WinDev/AppData/Roaming/devin/credentials.toml",
            )
        with mock.patch.object(engine, "IS_WINDOWS", False), mock.patch.dict(
            os.environ, {}, clear=False
        ):
            self.assertEqual(
                engine.devin_credentials_path(POSIX_HOME),
                POSIX_HOME / ".local" / "share" / "devin" / "credentials.toml",
            )

    def test_hermes_auth_path_follows_home_on_windows(self) -> None:
        with mock.patch.object(engine, "IS_WINDOWS", True):
            self.assertEqual(
                str(engine.hermes_auth_path(WINDOWS_HOME)).replace("\\", "/"),
                "C:/WinDev/.hermes/auth.json",
            )
        with mock.patch.object(engine, "IS_WINDOWS", False):
            self.assertEqual(
                engine.hermes_auth_path(POSIX_HOME),
                POSIX_HOME / ".hermes" / "auth.json",
            )

    def test_opencodego_candidates_on_windows(self) -> None:
        with mock.patch.object(engine, "IS_WINDOWS", True), mock.patch.dict(
            os.environ, {"USERPROFILE": "C:\\WinDev"}
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
            self.assertEqual(os.path.normcase(resolved[0]), os.path.normcase(str(shim)))
            self.assertEqual(resolved[1:], argv[1:])


class TrayWinSharedTests(unittest.TestCase):
    def test_status_class_falls_back_to_critical(self) -> None:
        self.assertEqual(tray_win.status_class({"class": "ok"}), "ok")
        self.assertEqual(tray_win.status_class({"class": "unexpected"}), "critical")
        self.assertEqual(tray_win.status_class({}), "critical")

    def test_panel_palette_follows_explicit_theme(self) -> None:
        dark = tray_win.panel_palette(False)
        light = tray_win.panel_palette(True)
        self.assertEqual(dark["bg"], "#1b1b22")
        self.assertEqual(light["bg"], "#edeff6")
        self.assertNotEqual(dark["fg"], light["fg"])
        self.assertEqual(light["error"], "#d33f3f")

    def test_missing_windows_theme_key_stays_dark(self) -> None:
        with mock.patch.object(tray_win, "windows_apps_use_light_theme", return_value=False):
            self.assertEqual(tray_win.panel_palette()["bg"], "#1b1b22")

    def test_missing_dependencies_message_mentions_install_command(self) -> None:
        self.assertIn("pystray", tray_win.MISSING_DEPENDENCIES_MESSAGE)
        self.assertIn("pillow", tray_win.MISSING_DEPENDENCIES_MESSAGE)


if __name__ == "__main__":
    unittest.main()
