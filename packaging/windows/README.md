# Windows packaging

Builds the Windows side of KodexBar Suite: a system-tray app (KodexBar Tray)
plus console tools (`ai`, `kodexbar-quotas`, `kodexbar-panel`, `kodexbar-skills`,
`ai-recover`), a portable zip, and an optional per-user installer.

The KDE Plasma 6 widget stays Linux-only. On Windows the tray icon and its
"Panel de cuotas" window take that role, backed by the same quota engine.

## Install (one line, no admin)

In PowerShell:

```powershell
irm https://raw.githubusercontent.com/Karasowl/KodexBar-Suite/main/packaging/windows/Install.ps1 | iex
```

`Install.ps1` resolves the latest GitHub release, downloads the per-user setup
exe plus `SHA256SUMS-windows`, verifies the checksum, and runs the installer
silently with autostart and user PATH enabled:

```powershell
setup.exe /VERYSILENT /TASKS="autostart,addpath"
```

Pass `-Version 0.12.10` to pin a release or `-Tasks ""` to skip both tasks.
The local-ai monitor is parked under `packages/ai-cli-control/attic/local/`
and is not part of the Windows bundle.

## Layout

| File | Purpose |
| --- | --- |
| `build.ps1` | One-shot build: entrypoints, PyInstaller runs, staging, zip, optional installer |
| `KodexBarTray.spec` | PyInstaller spec for the windowed tray app (onedir) |
| `kodexbar-suite.iss` | Inno Setup script for the per-user installer (no admin needed) |
| `generate-tray-icons.py` | Regenerates the tray PNGs and the ICO from the shared tray design (stdlib only, runs anywhere) |

`build/` holds every artifact and is git-ignored.

## Requirements

- Windows 10 or newer with Python 3.10+ on PATH.
- `python -m pip install pyinstaller pystray pillow`
- Inno Setup 6 (`iscc` on PATH) only when building the installer with `-Installer`.

## Build

From the repository root on Windows:

```powershell
python packaging/windows/generate-tray-icons.py   # optional: only when icon sources change
pwsh packaging/windows/build.ps1                  # portable zip
pwsh packaging/windows/build.ps1 -Installer       # zip + setup exe
```

The staged folder is flat on purpose: the tray resolves sibling tools
(`kodexbar-panel.exe`, `ai.exe`, ...) next to `KodexBarTray.exe`, so the whole
bundle also works portable from any directory. The tray ships with
`pystray` and `Pillow`; running the scripts from source instead needs
`pip install pystray pillow` once.

## CI

The `windows` job in `.github/workflows/ci.yml` runs the cross-platform Python
tests (`tests/test_windows_support.py`, `tests/static_checks.py`, compile
checks) on `windows-latest`, builds the zip and installer, and uploads both as
artifacts on every push. Provider-specific engine tests stay in the Linux jobs
because their fake upstream scripts rely on POSIX PATH semantics.

Pushing a `v*` tag also runs `.github/workflows/release-windows.yml`. That job
builds the same bundle and attaches the zip, the setup exe, and
`SHA256SUMS-windows` to the GitHub Release for that tag. Linux DEB, RPM, and
plasmoid assets stay on the existing manual release path.

## Windows scope notes

- Quota providers read the same files as on Linux: `~\.claude`,
  `~\.codex`, `~\.grok`, `~\.hermes`; Devin credentials come from
  `%APPDATA%\devin\credentials.toml`; the Cursor token comes from
  `%APPDATA%\Cursor\User\globalStorage\state.vscdb`.
- Profiles and account sidecars live under `%APPDATA%\kodexbar-suite`; the
  cost cache under `%LOCALAPPDATA%\kodexbar-suite\cache`.
- Systemd-based service controls stay unavailable; `kodexbar-tray`
  (GTK/AppIndicator) and the Waybar/XFCE panel output remain Linux features.
