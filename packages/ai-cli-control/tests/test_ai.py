from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import textwrap
import unittest
from contextlib import redirect_stdout
from importlib.util import module_from_spec, spec_from_file_location
from io import StringIO


ROOT = Path(__file__).resolve().parents[1]
AI = ROOT / "ai"
RECOVER = ROOT / "recover.py"
INSTALL = ROOT / "install.sh"
UNINSTALL = ROOT / "uninstall.sh"


class AiSelectorTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.temp = Path(self.temporary.name)
        self.cache = self.temp / "models.json"
        self.cache.write_text(
            json.dumps(
                {
                    "models": [
                        {
                            "slug": "codex-test",
                            "display_name": "Codex Test",
                            "supported_reasoning_levels": [
                                {"effort": "low", "description": "Rapido"},
                                {"effort": "high", "description": "Profundo"},
                            ],
                        }
                    ]
                }
            ),
            encoding="utf-8",
        )
        self.grok = self.temp / "grok-test"
        self.grok.write_text(
            textwrap.dedent(
                """\
                #!/usr/bin/env python3
                import os
                from pathlib import Path
                import sys

                if sys.argv[1:] == ["models"]:
                    print("Available models:")
                    print("  * grok-test (default)")
                    print("  - grok-fast")
                elif sys.argv[1:] == ["--version"]:
                    state = Path(os.environ["AI_TEST_VERSION_STATE"]) / "grok"
                    count = int(state.read_text() if state.exists() else "0")
                    state.write_text(str(count + 1))
                    print("grok antes" if count == 0 else "grok despues")
                elif sys.argv[1:] == ["update"]:
                    Path(os.environ["AI_TEST_UPDATE_LOG"]).open("a").write("grok\\n")
                    print("grok update stdout")
                    print("grok update stderr", file=sys.stderr)
                    raise SystemExit(17 if os.environ.get("AI_TEST_UPDATE_FAIL") == "grok" else 0)
                else:
                    print(os.getcwd())
                    print(*sys.argv[1:], sep="\\n")
                """
            ),
            encoding="utf-8",
        )
        self.grok.chmod(0o755)
        self.antigravity = self.temp / "agy-test"
        self.antigravity.write_text(
            textwrap.dedent(
                """\
                #!/usr/bin/env python3
                import os
                from pathlib import Path
                import sys

                if sys.argv[1:] == ["models"]:
                    print("Gemini 3.5 Flash (Medium)")
                    print("")
                    print("Gemini 3.1 Pro (High)")
                elif sys.argv[1:] == ["--version"]:
                    state = Path(os.environ["AI_TEST_VERSION_STATE"]) / "antigravity"
                    count = int(state.read_text() if state.exists() else "0")
                    state.write_text(str(count + 1))
                    print("antigravity antes" if count == 0 else "antigravity despues")
                elif sys.argv[1:] == ["update"]:
                    Path(os.environ["AI_TEST_UPDATE_LOG"]).open("a").write("antigravity\\n")
                    print("antigravity update stdout")
                    print("antigravity update stderr", file=sys.stderr)
                    raise SystemExit(17 if os.environ.get("AI_TEST_UPDATE_FAIL") == "antigravity" else 0)
                else:
                    print(os.getcwd())
                    print(repr(sys.argv[1:]))
                """
            ),
            encoding="utf-8",
        )
        self.antigravity.chmod(0o755)
        self.fake_bin = self.temp / "bin"
        self.fake_bin.mkdir()
        self.update_log = self.temp / "updates.log"
        self.version_state = self.temp / "versions"
        self.version_state.mkdir()
        self.codex = self.make_update_cli("codex")
        self.claude = self.make_update_cli("claude")
        self.env = os.environ.copy()
        self.env.update(
            {
                "AI_CODEX_MODELS_CACHE": str(self.cache),
                "AI_GROK_EXECUTABLE": str(self.grok),
                "AI_ANTIGRAVITY_EXECUTABLE": str(self.antigravity),
                "AI_TEST_UPDATE_LOG": str(self.update_log),
                "AI_TEST_VERSION_STATE": str(self.version_state),
            }
        )

    def make_update_cli(self, provider: str) -> Path:
        executable = self.temp / f"{provider}-test"
        executable.write_text(
            textwrap.dedent(
                f"""\
                #!/usr/bin/env python3
                import os
                from pathlib import Path
                import sys

                if sys.argv[1:] == ["--version"]:
                    state = Path(os.environ["AI_TEST_VERSION_STATE"]) / "{provider}"
                    count = int(state.read_text() if state.exists() else "0")
                    state.write_text(str(count + 1))
                    print("{provider} antes" if count == 0 else "{provider} despues")
                elif sys.argv[1:] == ["update"]:
                    Path(os.environ["AI_TEST_UPDATE_LOG"]).open("a").write("{provider}\\n")
                    print("{provider} update stdout")
                    print("{provider} update stderr", file=sys.stderr)
                    raise SystemExit(17 if os.environ.get("AI_TEST_UPDATE_FAIL") == "{provider}" else 0)
                else:
                    raise SystemExit(3)
                """
            ),
            encoding="utf-8",
        )
        executable.chmod(0o755)
        return executable

    def enable_update_executables(self) -> None:
        self.env.update(
            {
                "AI_CODEX_EXECUTABLE": str(self.codex),
                "AI_CLAUDE_EXECUTABLE": str(self.claude),
            }
        )

    def run_ai(self, *arguments: str, input_text: str | None = None) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [str(AI), *arguments],
            input=input_text,
            text=True,
            capture_output=True,
            check=False,
            env=self.env,
        )

    def run_script(self, script: Path, home: Path, language: str = "en") -> subprocess.CompletedProcess[str]:
        environment = self.env.copy()
        locale = "es_MX.UTF-8" if language == "es" else "C"
        environment.update({"HOME": str(home), "LANG": locale, "LC_ALL": locale})
        return subprocess.run(
            [str(script)], text=True, capture_output=True, check=False, env=environment
        )

    def test_codex_command(self) -> None:
        result = self.run_ai(
            "--dry-run", "--provider", "codex", "--model", "codex-test",
            "--effort", "high", "--permissions", "ask",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            result.stdout.strip(),
            "codex --model codex-test --config 'model_reasoning_effort=\"high\"' "
            "--sandbox workspace-write --ask-for-approval on-request",
        )

    def test_claude_command(self) -> None:
        result = self.run_ai(
            "--dry-run", "--provider", "claude", "--model", "fable",
            "--effort", "xhigh", "--permissions", "accept-edits",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            result.stdout.strip(),
            "claude --model fable --effort xhigh --permission-mode acceptEdits",
        )

    def test_grok_command_uses_dynamic_catalog(self) -> None:
        result = self.run_ai(
            "--dry-run", "--provider", "grok", "--model", "grok-fast",
            "--effort", "medium", "--permissions", "default",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            result.stdout.strip(),
            f"{self.grok} --model grok-fast --reasoning-effort medium --permission-mode default",
        )

    def test_antigravity_uses_dynamic_model_with_spaces_and_no_effort_flag(self) -> None:
        result = self.run_ai(
            "--dry-run", "--provider", "antigravity",
            "--model", "Gemini 3.5 Flash (Medium)",
            "--effort", "included", "--permissions", "accept-edits",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            result.stdout.strip(),
            f"{self.antigravity} --model 'Gemini 3.5 Flash (Medium)' --mode accept-edits",
        )
        self.assertNotIn("effort", result.stdout)

    def test_antigravity_preserves_model_order_and_skips_effort_dialog(self) -> None:
        result = self.run_ai("--text", "--dry-run", input_text="4\n2\n2\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            result.stdout.strip(),
            f"{self.antigravity} --model 'Gemini 3.1 Pro (High)' --mode plan",
        )
        self.assertNotIn("Selecciona el esfuerzo", result.stderr)

    def test_antigravity_permission_modes(self) -> None:
        expected = {
            "manual": "",
            "plan": " --mode plan",
            "accept-edits": " --mode accept-edits",
            "sandbox": " --sandbox",
            "full": " --dangerously-skip-permissions",
        }
        for permission, suffix in expected.items():
            with self.subTest(permission=permission):
                result = self.run_ai(
                    "--dry-run", "--provider", "antigravity",
                    "--model", "Gemini 3.5 Flash (Medium)",
                    "--permissions", permission,
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(
                    result.stdout.strip(),
                    f"{self.antigravity} --model 'Gemini 3.5 Flash (Medium)'{suffix}",
                )

    def test_cancel_from_text_provider_menu_changes_nothing(self) -> None:
        result = self.run_ai("--text", "--dry-run", input_text="0\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "")

    def test_graphical_kdialog_flow(self) -> None:
        state = self.temp / "dialog-state"
        kdialog = self.fake_bin / "kdialog"
        kdialog.write_text(
            textwrap.dedent(
                """\
                #!/usr/bin/env python3
                import os
                from pathlib import Path
                state = Path(os.environ["AI_TEST_DIALOG_STATE"])
                step = int(state.read_text() if state.exists() else "0")
                values = ["codex", "codex-test", "high", "ask"]
                print(values[step])
                state.write_text(str(step + 1))
                """
            ),
            encoding="utf-8",
        )
        kdialog.chmod(0o755)
        self.env.update(
            {
                "DISPLAY": ":test",
                "PATH": f"{self.fake_bin}:{self.env['PATH']}",
                "AI_TEST_DIALOG_STATE": str(state),
            }
        )
        result = self.run_ai("--dry-run")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            result.stdout.strip(),
            "codex --model codex-test --config 'model_reasoning_effort=\"high\"' "
            "--sandbox workspace-write --ask-for-approval on-request",
        )

    def test_graphical_cancel_changes_nothing(self) -> None:
        kdialog = self.fake_bin / "kdialog"
        kdialog.write_text("#!/usr/bin/env bash\nexit 1\n", encoding="utf-8")
        kdialog.chmod(0o755)
        self.env.update(
            {
                "DISPLAY": ":test",
                "PATH": f"{self.fake_bin}:{self.env['PATH']}",
            }
        )
        result = self.run_ai("--dry-run")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "")

    def test_cancel_from_antigravity_permissions_changes_nothing(self) -> None:
        result = self.run_ai("--text", "--dry-run", input_text="4\n1\n0\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "")

    def test_invalid_provider(self) -> None:
        result = self.run_ai("--dry-run", "--provider", "otro")
        self.assertEqual(result.returncode, 2)
        self.assertIn("invalid provider", result.stderr)

    def test_invalid_model(self) -> None:
        result = self.run_ai("--dry-run", "--provider", "claude", "--model", "inventado")
        self.assertEqual(result.returncode, 2)
        self.assertIn("invalid model", result.stderr)

    def test_invalid_effort(self) -> None:
        result = self.run_ai(
            "--dry-run", "--provider", "grok", "--model", "grok-test",
            "--effort", "max",
        )
        self.assertEqual(result.returncode, 2)
        self.assertIn("invalid effort", result.stderr)

    def test_invalid_permissions(self) -> None:
        result = self.run_ai(
            "--dry-run", "--provider", "antigravity",
            "--model", "Gemini 3.5 Flash (Medium)",
            "--effort", "included", "--permissions", "root",
        )
        self.assertEqual(result.returncode, 2)
        self.assertIn("invalid permission mode", result.stderr)

    def test_spanish_validation_uses_accents(self) -> None:
        result = self.run_ai("--language", "es", "--dry-run", "--provider", "otro")
        self.assertEqual(result.returncode, 2)
        self.assertIn("proveedor inválido", result.stderr)
        self.assertIn("Valores válidos", result.stderr)

    def test_antigravity_exec_preserves_current_directory_and_argument_boundaries(self) -> None:
        mock = self.temp / "antigravity mock"
        mock.write_text(
            textwrap.dedent(
                """\
                #!/usr/bin/env python3
                import os
                import sys
                if sys.argv[1:] == ["models"]:
                    print("Gemini 3.5 Flash (Medium)")
                    raise SystemExit(0)
                print(os.getcwd())
                print(repr(sys.argv[1:]))
                """
            ),
            encoding="utf-8",
        )
        mock.chmod(0o755)
        self.env["AI_ANTIGRAVITY_EXECUTABLE"] = str(mock)
        result = subprocess.run(
            [
                str(AI), "--provider", "antigravity",
                "--model", "Gemini 3.5 Flash (Medium)",
                "--permissions", "plan",
            ],
            cwd=self.temp,
            text=True,
            capture_output=True,
            check=False,
            env=self.env,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        lines = result.stdout.splitlines()
        self.assertEqual(lines[0], str(self.temp))
        self.assertEqual(
            lines[1],
            "['--model', 'Gemini 3.5 Flash (Medium)', '--mode', 'plan']",
        )

    def test_antigravity_model_is_never_evaluated_by_a_shell(self) -> None:
        marker = self.temp / "must-not-exist"
        model = f"Model $(touch {marker}) (High)"
        mock = self.temp / "safe-agy"
        mock.write_text(
            textwrap.dedent(
                """\
                #!/usr/bin/env python3
                import os
                import sys
                if sys.argv[1:] == ["models"]:
                    print(os.environ["AI_TEST_ANTIGRAVITY_MODEL"])
                    raise SystemExit(0)
                print(repr(sys.argv[1:]))
                """
            ),
            encoding="utf-8",
        )
        mock.chmod(0o755)
        self.env.update(
            {
                "AI_ANTIGRAVITY_EXECUTABLE": str(mock),
                "AI_TEST_ANTIGRAVITY_MODEL": model,
            }
        )
        result = self.run_ai(
            "--provider", "antigravity", "--model", model, "--permissions", "manual"
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), repr(["--model", model]))
        self.assertFalse(marker.exists())

    def test_text_update_selection_accepts_multiple_numbers(self) -> None:
        self.enable_update_executables()
        result = self.run_ai("--text", "--dry-run", input_text="5\n1,3\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            result.stdout.splitlines(),
            [f"{self.codex} update", f"{self.grok} update"],
        )

    def test_kdialog_update_uses_a_checklist_with_no_default_selection(self) -> None:
        self.enable_update_executables()
        kdialog = self.fake_bin / "kdialog"
        invocation = self.temp / "kdialog-invocation"
        kdialog.write_text(
            textwrap.dedent(
                """\
                #!/usr/bin/env python3
                import os
                from pathlib import Path
                import sys
                Path(os.environ["AI_TEST_KDIALOG_INVOCATION"]).write_text(repr(sys.argv[1:]))
                if "--checklist" in sys.argv:
                    print("grok")
                    print("codex")
                else:
                    print("update")
                """
            ),
            encoding="utf-8",
        )
        kdialog.chmod(0o755)
        self.env.update(
            {
                "DISPLAY": ":test",
                "PATH": f"{self.fake_bin}:{self.env['PATH']}",
                "AI_TEST_KDIALOG_INVOCATION": str(invocation),
            }
        )
        result = self.run_ai("--dry-run")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            result.stdout.splitlines(),
            [f"{self.codex} update", f"{self.grok} update"],
        )

        args = invocation.read_text(encoding="utf-8")
        self.assertIn("'--checklist'", args)
        self.assertIn("'codex', 'Codex', 'off'", args)
        self.assertIn("'antigravity', 'Antigravity', 'off'", args)

    def test_yad_update_uses_multiple_selection_with_no_defaults(self) -> None:
        self.enable_update_executables()
        invocation = self.temp / "yad-invocation"
        yad = self.fake_bin / "yad"
        yad.write_text(
            "#!/bin/sh\n"
            "printf '%s\\n' \"$@\" > \"$AI_TEST_YAD_INVOCATION\"\n"
            "for argument in \"$@\"; do\n"
            "    if [ \"$argument\" = '--multiple' ]; then\n"
            "        printf '%s' 'grok,codex'\n"
            "        exit 0\n"
            "    fi\n"
            "done\n"
            "printf '%s' 'update'\n",
            encoding="utf-8",
        )
        yad.chmod(0o755)
        env = self.env.copy()
        env.update(
            {
                "DISPLAY": ":test",
                "PATH": str(self.fake_bin),
                "AI_TEST_YAD_INVOCATION": str(invocation),
            }
        )
        result = subprocess.run(
            [sys.executable, str(AI), "--dry-run"],
            text=True,
            capture_output=True,
            check=False,
            env=env,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            result.stdout.splitlines(),
            [f"{self.codex} update", f"{self.grok} update"],
        )
        args = invocation.read_text(encoding="utf-8")
        self.assertIn("--multiple", args)
        self.assertIn("FALSE", args)
        self.assertIn("--print-column=2", args)

    def test_update_all_is_automatable_without_a_menu(self) -> None:
        self.enable_update_executables()
        result = self.run_ai("--update", "all", "--dry-run")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            result.stdout.splitlines(),
            [
                f"{self.codex} update",
                f"{self.claude} update",
                f"{self.grok} update",
                f"{self.antigravity} update",
            ],
        )
        self.assertEqual(result.stderr, "")
        self.assertFalse(self.update_log.exists())
        self.assertEqual(list(self.version_state.iterdir()), [])

    def test_updates_run_in_fixed_order_and_keep_output_visible(self) -> None:
        self.enable_update_executables()
        result = self.run_ai("--update", "grok,codex,antigravity")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            self.update_log.read_text(encoding="utf-8").splitlines(),
            ["codex", "grok", "antigravity"],
        )
        self.assertIn("codex update stdout", result.stdout)
        self.assertIn("grok update stderr", result.stderr)
        self.assertIn("Update summary:", result.stdout)

    def test_update_reports_versions_before_and_after(self) -> None:
        self.enable_update_executables()
        result = self.run_ai("--update", "codex")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Codex: previous version: codex antes", result.stdout)
        self.assertIn("Codex: result: success", result.stdout)
        self.assertIn("Codex: new version: codex despues", result.stdout)

    def test_update_failure_continues_with_remaining_providers(self) -> None:
        self.enable_update_executables()
        self.env["AI_TEST_UPDATE_FAIL"] = "grok"
        result = self.run_ai("--update", "codex,grok,antigravity")
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertEqual(
            self.update_log.read_text(encoding="utf-8").splitlines(),
            ["codex", "grok", "antigravity"],
        )
        self.assertIn("Grok: result: failed (code 17)", result.stdout)
        self.assertIn("Antigravity: success", result.stdout)

    def test_missing_update_executable_is_reported_and_does_not_stop_the_next_one(self) -> None:
        self.enable_update_executables()
        self.env["AI_CLAUDE_EXECUTABLE"] = str(self.temp / "does-not-exist")
        result = self.run_ai("--update", "claude,grok")
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertEqual(self.update_log.read_text(encoding="utf-8").splitlines(), ["grok"])
        self.assertIn("Claude: result: failed to run", result.stdout)
        self.assertIn("Grok: success", result.stdout)

    def test_update_cancel_or_empty_selection_runs_nothing(self) -> None:
        self.enable_update_executables()
        cancelled = self.run_ai("--text", input_text="5\n0\n")
        empty = self.run_ai("--text", input_text="5\n\n")
        self.assertEqual(cancelled.returncode, 0, cancelled.stderr)
        self.assertEqual(empty.returncode, 0, empty.stderr)
        self.assertEqual(cancelled.stdout, "")
        self.assertEqual(empty.stdout, "")
        self.assertFalse(self.update_log.exists())

    def test_update_rejects_invalid_ids(self) -> None:
        self.enable_update_executables()
        result = self.run_ai("--update", "codex,inventado", "--dry-run")
        self.assertEqual(result.returncode, 2)
        self.assertIn("invalid update list", result.stderr)
        self.assertFalse(self.update_log.exists())

    def test_selector_has_no_eval_or_shell_execution(self) -> None:
        source = AI.read_text(encoding="utf-8")
        self.assertNotIn("eval(", source)
        self.assertNotIn("shell=True", source)
        self.assertNotIn("shell = True", source)
        self.assertNotIn("os.system(", source)

    def test_version_and_english_help(self) -> None:
        version = self.run_ai("--version")
        help_result = self.run_ai("--language", "en", "--help")
        self.assertEqual(version.returncode, 0, version.stderr)
        self.assertEqual(version.stdout.strip(), "ai-cli-control 0.2.0")
        self.assertEqual(help_result.returncode, 0, help_result.stderr)
        self.assertIn("Choose and launch Codex", help_result.stdout)
        self.assertIn("--language LANGUAGE", help_result.stdout)

    def test_spanish_locale_and_language_override(self) -> None:
        spanish_environment = self.env.copy()
        spanish_environment.update({"LANG": "es_MX.UTF-8", "LC_ALL": ""})
        localized = subprocess.run(
            [str(AI), "--text", "--dry-run"], input="0\n", text=True,
            capture_output=True, check=False, env=spanish_environment,
        )
        overridden = subprocess.run(
            [str(AI), "--language", "en", "--text", "--dry-run"], input="0\n",
            text=True, capture_output=True, check=False, env=spanish_environment,
        )
        self.assertEqual(localized.returncode, 0, localized.stderr)
        self.assertIn("Selecciona un proveedor", localized.stderr)
        self.assertIn("Selección:", localized.stderr)
        self.assertIn("Cancelar", localized.stderr)
        self.assertEqual(overridden.returncode, 0, overridden.stderr)
        self.assertIn("Choose a provider", overridden.stderr)
        self.assertIn("Cancel", overridden.stderr)

    def test_locale_priority_and_spanish_help(self) -> None:
        environment = self.env.copy()
        environment.update({"LANG": "es_MX.UTF-8", "LC_ALL": "C"})
        result = subprocess.run(
            [str(AI), "--help"], text=True, capture_output=True, check=False, env=environment
        )
        spanish = self.run_ai("--language", "es", "--help")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Choose and launch Codex", result.stdout)
        self.assertEqual(spanish.returncode, 0, spanish.stderr)
        self.assertIn("Selecciona e inicia Codex", spanish.stdout)
        self.assertIn("muestra esta ayuda y termina", spanish.stdout)
        self.assertIn("muestra la versión del programa", spanish.stdout)
        self.assertIn("inglés o español", spanish.stdout)
        self.assertIn("opciones:", spanish.stdout)

    def test_spanish_update_summary(self) -> None:
        self.enable_update_executables()
        result = self.run_ai("--language", "es", "--update", "codex")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Codex: versión anterior: codex antes", result.stdout)
        self.assertIn("Codex: resultado: éxito", result.stdout)
        self.assertIn("Resumen de actualizaciones:", result.stdout)

    def test_install_is_durable_and_uninstall_is_idempotent(self) -> None:
        home = self.temp / "home"
        home.mkdir()
        (home / ".claude").mkdir()
        (home / ".grok").mkdir()
        first = self.run_script(INSTALL, home)
        second = self.run_script(INSTALL, home)
        installed = home / ".local/share/ai-cli-control/ai"
        installed_recover = home / ".local/share/ai-cli-control/recover.py"
        installed_uninstall = home / ".local/share/ai-cli-control/uninstall.sh"
        target = home / ".local/bin/ai"
        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertTrue(installed.is_file())
        self.assertTrue(installed_recover.is_file())
        self.assertTrue(installed_uninstall.is_file())
        self.assertTrue(target.is_symlink())
        self.assertEqual(target.readlink(), installed)
        self.assertEqual(installed.read_text(encoding="utf-8"), AI.read_text(encoding="utf-8"))
        self.assertEqual(installed_recover.read_text(encoding="utf-8"), RECOVER.read_text(encoding="utf-8"))
        for cli in ("claude", "grok"):
            adapter = home / f".{cli}/skills/recover-chat"
            self.assertTrue((adapter / "SKILL.md").is_file())
            self.assertEqual((adapter / ".ai-cli-control-owner").read_text(encoding="utf-8").strip(), "ai-cli-control")
        self.assertNotEqual(target.resolve(), AI.resolve())
        self.assertEqual(self.run_script(installed_uninstall, home).returncode, 0)
        self.assertEqual(self.run_script(UNINSTALL, home).returncode, 0)
        self.assertFalse(target.exists())
        self.assertFalse(installed.exists())
        self.assertFalse(installed_recover.exists())
        self.assertFalse((home / ".claude/skills/recover-chat").exists())
        self.assertFalse((home / ".grok/skills/recover-chat").exists())

    def test_recover_forwards_arguments_and_exit_code(self) -> None:
        help_result = self.run_ai("recover")
        self.assertEqual(help_result.returncode, 0, help_result.stderr)
        self.assertIn("usage: ", help_result.stdout)
        self.assertIn("Recupera conversaciones locales por proyecto", help_result.stdout)
        listed = self.run_ai("recover", "list", "--provider", "grok", "--cwd", str(self.temp))
        self.assertEqual(listed.returncode, 0, listed.stderr)
        self.assertEqual(listed.stdout, "")
        self.assertIn("No se encontraron conversaciones", listed.stderr)
        failed = self.run_ai("recover", "dump", "--provider", "grok", "--id", "missing", "--cwd", str(self.temp))
        self.assertEqual(failed.returncode, 2)
        self.assertIn("no se encontró la sesión missing", failed.stderr)

    def test_install_and_uninstall_refuse_foreign_target(self) -> None:
        home = self.temp / "foreign-home"
        foreign = self.temp / "foreign-ai"
        foreign.write_text("foreign", encoding="utf-8")
        target = home / ".local/bin/ai"
        target.parent.mkdir(parents=True)
        target.symlink_to(foreign)
        install = self.run_script(INSTALL, home)
        self.assertEqual(install.returncode, 1)
        self.assertEqual(target.readlink(), foreign)
        target.unlink()
        self.assertEqual(self.run_script(INSTALL, home).returncode, 0)
        target.unlink()
        target.symlink_to(foreign)
        uninstall = self.run_script(UNINSTALL, home)
        self.assertEqual(uninstall.returncode, 1)
        self.assertTrue((home / ".local/share/ai-cli-control/ai").exists())
        self.assertEqual(target.readlink(), foreign)

    def test_install_preserves_foreign_recover_adapter(self) -> None:
        home = self.temp / "foreign-adapter-home"
        adapter = home / ".claude/skills/recover-chat"
        adapter.mkdir(parents=True)
        skill = adapter / "SKILL.md"
        skill.write_text("skill ajeno", encoding="utf-8")
        result = self.run_script(INSTALL, home)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(skill.read_text(encoding="utf-8"), "skill ajeno")
        self.assertIn("Skipped", result.stderr)

    def test_spanish_install_and_uninstall_output_uses_accents(self) -> None:
        home = self.temp / "spanish-home"
        home.mkdir()
        install = self.run_script(INSTALL, home, "es")
        uninstall = self.run_script(UNINSTALL, home, "es")
        target = home / ".local/bin/ai"
        self.assertEqual(install.returncode, 0, install.stderr)
        self.assertIn(f"ai se instaló en {target}", install.stdout)
        self.assertEqual(uninstall.returncode, 0, uninstall.stderr)
        self.assertIn("ai-cli-control se desinstaló.", uninstall.stdout)


class RecoverEngineTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        spec = spec_from_file_location("recover_engine", RECOVER)
        assert spec is not None and spec.loader is not None
        cls.engine = module_from_spec(spec)
        spec.loader.exec_module(cls.engine)

    def test_truncation_never_emits_the_full_transcript(self) -> None:
        transcript = "INICIO_UNICO " + ("contenido " * 600) + "FINAL_UNICO"
        session = {
            "provider": "agy", "id": "test", "cwd": "", "started": "2026-01-01T00:00:00Z",
            "last": "2026-01-01T00:00:00Z", "kind": "main", "turns": [("user", transcript)],
            "path": Path("/tmp/recover-engine-test"),
        }
        original = self.engine.sessions_for
        self.engine.sessions_for = lambda _provider, _cwd: [session]
        try:
            output = StringIO()
            args = type("Args", (), {"provider": "agy", "cwd": ".", "id": "last", "max_chars": 300})()
            with redirect_stdout(output):
                self.assertEqual(self.engine.command_dump(args), 0)
        finally:
            self.engine.sessions_for = original
        rendered = output.getvalue()
        self.assertIn("[TRUNCADO:", rendered)
        self.assertNotIn(transcript, rendered)
        self.assertNotIn("INICIO_UNICO", rendered)

    def test_codex_synthetic_message_filter(self) -> None:
        self.assertTrue(self.engine.is_synthetic_user_message("<recommended_plugins>configuración</recommended_plugins>"))
        self.assertFalse(self.engine.is_synthetic_user_message("<pedido>texto real del usuario</pedido>"))

    def test_printable_ratio_keeps_short_ok(self) -> None:
        self.assertEqual(self.engine.printable_ratio("OK"), 1.0)
        uuid = "8418cc72-9e8a-434d-a210-7d709527da15"

        def pb(field, value):
            if isinstance(value, str):
                value = value.encode("utf-8")
            return bytes(((field << 3) | 2, len(value))) + value

        payload = (
            pb(1, "OK") + pb(2, uuid) + pb(3, uuid + uuid)
            + pb(4, "file:///workspace/project")
            + pb(5, "8D1UasqREpCIz7IPwZGB-QY")
            + pb(6, "-3750763034362895579")
        )
        self.assertEqual(self.engine.useful_protobuf_text(payload), "OK")

    def test_protobuf_keeps_nested_turns_and_drops_printable_tag_bytes(self) -> None:
        uuid = "8418cc72-9e8a-434d-a210-7d709527da15"

        def pb(field, value):
            if isinstance(value, str):
                value = value.encode("utf-8")
            return bytes(((field << 3) | 2, len(value))) + value

        nested = pb(1, "UNIDAD FINAL autorizada") + pb(2, uuid)
        payload = pb(1, nested) + pb(2, uuid)
        self.assertEqual(self.engine.useful_protobuf_text(payload), "UNIDAD FINAL autorizada")
        tagged = (
            pb(1, b"\nKPOST ONLY de FINAL")
            + pb(2, pb(1, "POST ONLY de FINAL") + pb(2, uuid))
            + pb(3, uuid)
        )
        self.assertEqual(
            self.engine.useful_protobuf_text(tagged),
            "POST ONLY de FINAL",
        )

    def test_dump_last_skips_sessions_without_text_turns(self) -> None:
        empty = {
            "provider": "grok", "id": "empty", "cwd": "", "started": "2026-01-02T00:00:00Z",
            "last": "2026-01-02T00:00:00Z", "kind": "main", "turns": [("tool", 1)],
            "path": Path("/tmp/recover-engine-empty"),
        }
        populated = {
            "provider": "grok", "id": "populated", "cwd": "", "started": "2026-01-01T00:00:00Z",
            "last": "2026-01-01T00:00:00Z", "kind": "main", "turns": [("user", "texto real")],
            "path": Path("/tmp/recover-engine-populated"),
        }
        original = self.engine.sessions_for
        self.engine.sessions_for = lambda _provider, _cwd: [empty, populated]
        try:
            output = StringIO()
            args = type("Args", (), {"provider": "grok", "cwd": ".", "id": "last", "max_chars": 800})()
            with redirect_stdout(output):
                self.assertEqual(self.engine.command_dump(args), 0)
            self.assertIn("Sesión: populated", output.getvalue())
        finally:
            self.engine.sessions_for = original

    def test_dump_last_rejects_only_empty_sessions(self) -> None:
        empty = {
            "provider": "grok", "id": "empty", "cwd": "", "started": "2026-01-02T00:00:00Z",
            "last": "2026-01-02T00:00:00Z", "kind": "main", "turns": [("tool", 1)],
            "path": Path("/tmp/recover-engine-empty"),
        }
        original = self.engine.sessions_for
        self.engine.sessions_for = lambda _provider, _cwd: [empty]
        try:
            args = type("Args", (), {"provider": "grok", "cwd": ".", "id": "last", "max_chars": 800})()
            with self.assertRaisesRegex(ValueError, "no hay una sesión pasada reciente"):
                self.engine.command_dump(args)
        finally:
            self.engine.sessions_for = original


if __name__ == "__main__":
    unittest.main()
