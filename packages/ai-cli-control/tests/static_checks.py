#!/usr/bin/env python3
"""Run repository safety checks without invoking provider CLIs."""

from __future__ import annotations

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
    recover_source = RECOVER.read_text(encoding="utf-8")
    quotas_source = QUOTAS.read_text(encoding="utf-8")
    panel_source = PANEL.read_text(encoding="utf-8")
    tray_source = TRAY.read_text(encoding="utf-8")
    local_ai_source = LOCAL_AI.read_text(encoding="utf-8")
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
    if 'sub.add_parser("status"' not in local_ai_source or '"unmount"' not in local_ai_source:
        print("local-ai is missing its JSON inspection/control contract", file=sys.stderr)
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
