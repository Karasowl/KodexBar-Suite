#!/usr/bin/env python3
"""Run repository safety checks without invoking provider CLIs."""

from __future__ import annotations

import json
from pathlib import Path
import re
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[1]
AI = ROOT / "ai"
RECOVER = ROOT / "recover.py"
QUOTAS = ROOT / "kodexbar-quotas"
PANEL = ROOT / "kodexbar-panel"
TRAY = ROOT / "kodexbar-tray"
LOCAL_AI = ROOT / "local-ai"
SKILLS = ROOT / "kodexbar-skills"
AUR_PKGBUILD = ROOT.parents[1] / "packaging" / "aur" / "PKGBUILD"
AUR_INSTALL = ROOT.parents[1] / "packaging" / "aur" / "kodexbar-suite.install"
PLASMOID_METADATA = ROOT.parent / "kodexbar" / "metadata.json"
PLASMA_RELOAD = ROOT.parents[1] / "packaging" / "aur" / "reload-plasma-after-upgrade"
RELEASE_VERSION = "0.12.6"
AUR_RELEASE_VERSION = "0.12.5"
FORBIDDEN = ("eval(", "shell=True", "shell = True", "os.system(")
SECRET_PATTERNS = {
    "private key": re.compile(r"-----BEGIN (?:[A-Z0-9 ]+ )?PRIVATE KEY-----"),
    "GitHub token": re.compile(r"\bgh[opsur]_[A-Za-z0-9]{36,255}\b|\bgithub_pat_[A-Za-z0-9_]{20,255}\b"),
    "personal home path": re.compile(r"/(?:home|Users)/[A-Za-z0-9._-]+(?:/|$)"),
    "email address": re.compile(r"\b[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+\b"),
}
TEXT_SUFFIXES = {"", ".md", ".py", ".sh", ".yml", ".yaml", ".json", ".txt"}


def tracked_text_files() -> list[Path]:
    """Return tracked text files, with a deterministic fallback for source archives."""
    try:
        result = subprocess.run(
            ["git", "-C", str(ROOT), "ls-files", "-z"],
            text=True,
            capture_output=True,
            check=True,
        )
        candidates = [ROOT / item for item in result.stdout.split("\0") if item]
    except (OSError, subprocess.CalledProcessError):
        candidates = [
            path for path in ROOT.rglob("*")
            if path.is_file() and "__pycache__" not in path.parts
        ]
    return sorted(path for path in candidates if path.suffix in TEXT_SUFFIXES)


def find_secrets() -> list[str]:
    findings: list[str] = []
    for path in tracked_text_files():
        try:
            source = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        for name, pattern in SECRET_PATTERNS.items():
            if pattern.search(source):
                findings.append(f"{path.relative_to(ROOT)}: possible {name}")
    return findings


def main() -> int:
    source = AI.read_text(encoding="utf-8")
    if not RECOVER.is_file():
        print("Missing standalone recover.py engine", file=sys.stderr)
        return 1
    if not QUOTAS.is_file():
        print("Missing kodexbar-quotas engine", file=sys.stderr)
        return 1
    if not PANEL.is_file():
        print("Missing kodexbar-panel adapter", file=sys.stderr)
        return 1
    if not TRAY.is_file():
        print("Missing kodexbar-tray indicator", file=sys.stderr)
        return 1
    if not LOCAL_AI.is_file():
        print("Missing local-ai engine", file=sys.stderr)
        return 1
    if not SKILLS.is_file():
        print("Missing kodexbar-skills engine", file=sys.stderr)
        return 1
    aur_source = AUR_PKGBUILD.read_text(encoding="utf-8")
    aur_install_source = AUR_INSTALL.read_text(encoding="utf-8")
    plasma_reload_source = PLASMA_RELOAD.read_text(encoding="utf-8")
    package_statements = "\n".join(line for line in aur_source.splitlines() if not line.lstrip().startswith("#"))
    release_sources = {
        "ai": AI,
        "kodexbar-quotas": QUOTAS,
        "local-ai": LOCAL_AI,
        "kodexbar-skills": SKILLS,
    }
    for name, path in release_sources.items():
        if f'VERSION = "{RELEASE_VERSION}"' not in path.read_text(encoding="utf-8"):
            print(f"{name} does not declare release version {RELEASE_VERSION}", file=sys.stderr)
            return 1
    try:
        metadata_version = json.loads(PLASMOID_METADATA.read_text(encoding="utf-8"))["KPlugin"]
    except (OSError, json.JSONDecodeError, KeyError, TypeError):
        print("Plasmoid metadata is invalid", file=sys.stderr)
        return 1
    if metadata_version.get("Version") != RELEASE_VERSION:
        print("Plasmoid metadata version does not match the release", file=sys.stderr)
        return 1
    if metadata_version.get("Website") != "https://github.com/Karasowl/KodexBar-Suite":
        print("Plasmoid metadata does not point to the maintained suite repository", file=sys.stderr)
        return 1
    if f"pkgver={AUR_RELEASE_VERSION}" not in package_statements:
        print("AUR package version does not match its pinned release", file=sys.stderr)
        return 1
    required_payload_statements = (
        r"(?m)^\s*packages/ai-cli-control/local-ai\s+\\$",
        r"(?m)^\s*packages/ai-cli-control/kodexbar-skills\s+\\$",
        r'(?m)^\s*install -d "\$\{payload\}/local_ai_drivers"$',
        r"(?m)^\s*packages/ai-cli-control/local_ai_drivers/__init__\.py\s+\\$",
        r"(?m)^\s*packages/ai-cli-control/local_ai_drivers/builtin\.py\s+\\$",
        r"(?m)^\s*packages/ai-cli-control/local_ai_drivers/descriptors\.py\s+\\$",
        r'(?m)^\s*ln -s /usr/lib/kodexbar-suite/ai-cli-control/local-ai "\$\{pkgdir\}/usr/bin/local-ai"$',
        r'(?m)^\s*ln -s /usr/lib/kodexbar-suite/ai-cli-control/kodexbar-skills "\$\{pkgdir\}/usr/bin/kodexbar-skills"$',
        r"(?m)^\s*install -m644 packages/ai-cli-control/local_ai_drivers/CONTRACT\.md\s+\\$",
    )
    if not all(re.search(pattern, package_statements) for pattern in required_payload_statements):
        print("AUR package does not install the local-ai executable, drivers, documentation, and symlink", file=sys.stderr)
        return 1
    reload_contract = (
        "post_install()",
        "post_upgrade()",
        "/usr/lib/kodexbar-suite/reload-plasma-after-upgrade",
    )
    if not all(token in aur_install_source for token in reload_contract):
        print("AUR lifecycle hooks do not reload an installed KodexBar widget", file=sys.stderr)
        return 1
    if (
        "org.kde.PlasmaShell.dumpCurrentLayoutJS" not in plasma_reload_source
        or 'systemctl_bin" --user restart plasma-plasmashell.service' not in plasma_reload_source
        or "plugin_marker=" not in plasma_reload_source
    ):
        print("Plasma reload helper does not detect KodexBar before restarting the user shell", file=sys.stderr)
        return 1
    recover_source = RECOVER.read_text(encoding="utf-8")
    quotas_source = QUOTAS.read_text(encoding="utf-8")
    panel_source = PANEL.read_text(encoding="utf-8")
    tray_source = TRAY.read_text(encoding="utf-8")
    local_ai_source = LOCAL_AI.read_text(encoding="utf-8")
    skills_source = SKILLS.read_text(encoding="utf-8")
    failures = [token for token in FORBIDDEN if token in source]
    if failures:
        print(f"Forbidden execution tokens found: {', '.join(failures)}", file=sys.stderr)
        return 1
    if 'return [command_name(provider), "update"]' not in source:
        print("Updates are not built as an argument array", file=sys.stderr)
        return 1
    if 'default = "agy" if provider == "antigravity" else provider' not in source:
        print("Missing Antigravity executable mapping", file=sys.stderr)
        return 1
    if 'Path(__file__).resolve().with_name("recover.py")' not in source:
        print("Recovery engine is not resolved beside the installed ai script", file=sys.stderr)
        return 1
    if any(token in recover_source for token in FORBIDDEN):
        print("Forbidden execution tokens found in recover.py", file=sys.stderr)
        return 1
    if any(token in quotas_source for token in FORBIDDEN):
        print("Forbidden execution tokens found in kodexbar-quotas", file=sys.stderr)
        return 1
    if any(token in panel_source for token in FORBIDDEN):
        print("Forbidden execution tokens found in kodexbar-panel", file=sys.stderr)
        return 1
    if any(token in tray_source for token in FORBIDDEN):
        print("Forbidden execution tokens found in kodexbar-tray", file=sys.stderr)
        return 1
    if any(token in local_ai_source for token in FORBIDDEN):
        print("Forbidden execution tokens found in local-ai", file=sys.stderr)
        return 1
    if any(token in skills_source for token in FORBIDDEN):
        print("Forbidden execution tokens found in kodexbar-skills", file=sys.stderr)
        return 1
    if 'sub.add_parser("status"' not in local_ai_source or '"unmount"' not in local_ai_source:
        print("local-ai is missing its JSON inspection/control contract", file=sys.stderr)
        return 1
    if (
        'sub.add_parser("status"' not in skills_source
        or '"sync"' not in skills_source
        or '"batch"' not in skills_source
        or '"--changes-json"' not in skills_source
    ):
        print("kodexbar-skills is missing its JSON inspection/control contract", file=sys.stderr)
        return 1
    findings = find_secrets()
    if findings:
        print("Potential secrets or personal data found:", file=sys.stderr)
        print("\n".join(findings), file=sys.stderr)
        return 1
    print("Static safety checks passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
