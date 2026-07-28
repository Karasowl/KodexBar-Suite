from __future__ import annotations

import importlib.machinery
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "kodexbar-skills"
LOADER = importlib.machinery.SourceFileLoader("kodexbar_skills", str(SCRIPT))
SPEC = importlib.util.spec_from_loader(LOADER.name, LOADER)
assert SPEC is not None
skills = importlib.util.module_from_spec(SPEC)
sys.modules[LOADER.name] = skills
LOADER.exec_module(skills)


def write_skill(path: Path, name: str, body: str = "Body") -> None:
    path.mkdir(parents=True, exist_ok=True)
    (path / "SKILL.md").write_text(
        f"---\nname: {name}\ndescription: Test {name}\n---\n\n{body}\n",
        encoding="utf-8",
    )


class KodexBarSkillsTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.home = Path(self.temporary.name)
        for marker in (".codex", ".claude", ".gemini"):
            (self.home / marker).mkdir(parents=True)

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def inventory_skill(self, name: str) -> dict:
        inventory = skills.build_inventory(self.home, "codex,claude,gemini")
        return next(item for item in inventory["skills"] if item["name"] == name)

    def test_inventory_distinguishes_partial_and_synced_links(self) -> None:
        library = self.home / "library/release"
        write_skill(library, "release")
        for provider in (".codex", ".claude"):
            root = self.home / provider / "skills"
            root.mkdir()
            (root / "release").symlink_to(library, target_is_directory=True)

        item = self.inventory_skill("release")
        self.assertEqual(item["status"], "partial")
        self.assertEqual(item["missingProviders"], ["gemini"])
        self.assertTrue(item["syncable"])
        cells = {cell["provider"]: cell for cell in item["cells"]}
        self.assertEqual(cells["codex"]["state"], "linked")
        self.assertTrue(cells["codex"]["canDisable"])
        self.assertEqual(cells["claude"]["state"], "linked")
        self.assertEqual(cells["gemini"]["state"], "missing")
        self.assertTrue(cells["gemini"]["canEnable"])

        result, actions = skills.build_sync_plan(
            self.home,
            "release",
            "codex",
            "codex,claude,gemini",
            None,
        )
        self.assertTrue(result["ok"])
        self.assertEqual([entry["action"] for entry in result["plan"]], [
            "already-linked",
            "create-link",
        ])
        applied = skills.apply_sync_plan(result, actions)
        self.assertTrue(applied["applied"])
        self.assertEqual(
            (self.home / ".gemini/skills/release").resolve(),
            library.resolve(),
        )
        self.assertEqual(self.inventory_skill("release")["status"], "synced")

    def test_identical_copy_is_backed_up_before_linking(self) -> None:
        codex = self.home / ".codex/skills/review"
        claude = self.home / ".claude/skills/review"
        write_skill(codex, "review")
        write_skill(claude, "review")

        inventory = skills.build_inventory(self.home, "codex,claude")
        item = next(entry for entry in inventory["skills"] if entry["name"] == "review")
        self.assertEqual(item["status"], "matching")

        result, actions = skills.build_sync_plan(
            self.home,
            "review",
            "codex",
            "codex,claude",
            "claude",
        )
        applied = skills.apply_sync_plan(result, actions)
        self.assertTrue(applied["applied"])
        self.assertTrue(claude.is_symlink())
        self.assertEqual(claude.resolve(), codex.resolve())
        self.assertEqual(len(applied["backups"]), 1)
        self.assertTrue(Path(applied["backups"][0]).is_dir())

    def test_divergent_target_blocks_every_write(self) -> None:
        codex = self.home / ".codex/skills/review"
        claude = self.home / ".claude/skills/review"
        write_skill(codex, "review", "Codex")
        write_skill(claude, "review", "Claude")

        item = self.inventory_skill("review")
        self.assertEqual(item["status"], "conflict")

        result, actions = skills.build_sync_plan(
            self.home,
            "review",
            "codex",
            "codex,claude,gemini",
            "claude,gemini",
        )
        self.assertFalse(result["ok"])
        self.assertEqual(actions[0][1], self.home / ".gemini/skills/review")
        self.assertFalse((self.home / ".gemini/skills/review").exists())

    def test_target_change_after_preflight_cancels_every_write(self) -> None:
        source = self.home / ".codex/skills/review"
        write_skill(source, "review")
        result, actions = skills.build_sync_plan(
            self.home,
            "review",
            "codex",
            "codex,claude,gemini",
            "claude,gemini",
        )
        write_skill(self.home / ".gemini/skills/review", "review", "Late change")

        applied = skills.apply_sync_plan(result, actions)
        self.assertFalse(applied["ok"])
        self.assertIn("after preflight", applied["error"])
        self.assertFalse((self.home / ".claude/skills/review").exists())
        self.assertFalse((self.home / ".gemini/skills/review").is_symlink())

    def test_provider_owning_link_source_is_not_replaced(self) -> None:
        claude = self.home / ".claude/skills/review"
        write_skill(claude, "review")
        codex_root = self.home / ".codex/skills"
        codex_root.mkdir()
        (codex_root / "review").symlink_to(claude, target_is_directory=True)

        result, actions = skills.build_sync_plan(
            self.home,
            "review",
            "codex",
            "codex,claude,gemini",
            None,
        )
        self.assertTrue(result["ok"])
        self.assertEqual(
            [entry["action"] for entry in result["plan"]],
            ["source-location", "create-link"],
        )
        applied = skills.apply_sync_plan(result, actions)
        self.assertTrue(applied["applied"])
        self.assertTrue(claude.is_dir())
        self.assertFalse(claude.is_symlink())
        self.assertEqual(
            (self.home / ".gemini/skills/review").resolve(),
            claude.resolve(),
        )

    def test_hidden_and_nonportable_skills_are_not_sync_candidates(self) -> None:
        write_skill(self.home / ".codex/skills/.system/internal", "internal")
        write_skill(self.home / ".codex/skills/Not Portable", "Not Portable")

        inventory = skills.build_inventory(self.home, "codex,claude,gemini")
        names = [item["name"] for item in inventory["skills"]]
        self.assertNotIn("internal", names)
        item = next(entry for entry in inventory["skills"] if entry["name"] == "Not Portable")
        self.assertFalse(item["portable"])
        self.assertFalse(item["syncable"])

    def test_oversized_skill_is_bounded_and_reported_as_conflict(self) -> None:
        skill = self.home / ".codex/skills/large"
        write_skill(skill, "large")
        with (skill / "asset.bin").open("wb") as handle:
            handle.truncate(skills.MAX_SKILL_BYTES + 1)

        item = self.inventory_skill("large")
        self.assertEqual(item["status"], "conflict")
        self.assertFalse(item["syncable"])
        self.assertIn("scan limit", item["sources"][0]["error"])

    def test_batch_can_enable_and_disable_provider_links_together(self) -> None:
        library = self.home / "library/release"
        write_skill(library, "release")
        for provider in (".codex", ".claude"):
            root = self.home / provider / "skills"
            root.mkdir()
            (root / "release").symlink_to(library, target_is_directory=True)
        changes = json.dumps(
            [
                {
                    "skill": "release",
                    "provider": "gemini",
                    "enabled": True,
                },
                {
                    "skill": "release",
                    "provider": "claude",
                    "enabled": False,
                },
            ]
        )

        result, actions = skills.build_batch_plan(
            self.home,
            changes,
            "codex,claude,gemini",
        )
        self.assertTrue(result["ok"])
        self.assertEqual(
            [action.action for action in actions],
            ["remove-link", "create-link"],
        )
        applied = skills.apply_batch_plan(result, actions)

        self.assertTrue(applied["applied"])
        self.assertFalse((self.home / ".claude/skills/release").exists())
        gemini = self.home / ".gemini/skills/release"
        self.assertTrue(gemini.is_symlink())
        self.assertEqual(gemini.resolve(), library.resolve())

    def test_batch_links_matching_copy_with_recoverable_backup(self) -> None:
        codex = self.home / ".codex/skills/review"
        gemini = self.home / ".gemini/skills/review"
        write_skill(codex, "review")
        write_skill(gemini, "review")
        changes = json.dumps(
            [
                {
                    "skill": "review",
                    "provider": "gemini",
                    "enabled": True,
                }
            ]
        )

        result, actions = skills.build_batch_plan(
            self.home,
            changes,
            "codex,claude,gemini",
        )
        self.assertTrue(result["ok"])
        self.assertEqual(actions[0].action, "replace-identical")
        applied = skills.apply_batch_plan(result, actions)

        self.assertTrue(applied["applied"])
        self.assertTrue(gemini.is_symlink())
        self.assertEqual(gemini.resolve(), codex.resolve())
        self.assertEqual(len(applied["backups"]), 1)
        self.assertTrue(Path(applied["backups"][0]).is_dir())

    def test_batch_conflict_blocks_every_target(self) -> None:
        write_skill(self.home / ".codex/skills/review", "review", "Codex")
        write_skill(self.home / ".claude/skills/review", "review", "Claude")
        changes = json.dumps(
            [
                {
                    "skill": "review",
                    "provider": "claude",
                    "enabled": True,
                },
                {
                    "skill": "review",
                    "provider": "gemini",
                    "enabled": True,
                },
            ]
        )

        result, actions = skills.build_batch_plan(
            self.home,
            changes,
            "codex,claude,gemini",
        )

        self.assertFalse(result["ok"])
        self.assertEqual(len(result["conflicts"]), 1)
        self.assertEqual(actions[0].provider.identifier, "gemini")
        self.assertFalse((self.home / ".gemini/skills/review").exists())

    def test_batch_source_change_after_preview_cancels_every_write(self) -> None:
        source = self.home / ".codex/skills/review"
        write_skill(source, "review")
        changes = json.dumps(
            [
                {
                    "skill": "review",
                    "provider": "claude",
                    "enabled": True,
                },
                {
                    "skill": "review",
                    "provider": "gemini",
                    "enabled": True,
                },
            ]
        )
        result, actions = skills.build_batch_plan(
            self.home,
            changes,
            "codex,claude,gemini",
        )
        (source / "SKILL.md").write_text("changed", encoding="utf-8")

        applied = skills.apply_batch_plan(result, actions)

        self.assertFalse(applied["ok"])
        self.assertIn("changed after preflight", applied["error"])
        self.assertFalse((self.home / ".claude/skills/review").exists())
        self.assertFalse((self.home / ".gemini/skills/review").exists())


if __name__ == "__main__":
    unittest.main()
