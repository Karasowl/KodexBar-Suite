# -*- mode: python ; coding: utf-8 -*-
# PyInstaller spec for the Windows tray application.
# Build from packaging/windows with:
#   pyinstaller KodexBarTray.spec --noconfirm --clean
# The build.ps1 script prepares build/entrypoints/KodexBarTray.py and runs this.

a = Analysis(
    ['build/entrypoints/KodexBarTray.py'],
    pathex=[],
    binaries=[],
    datas=[
        ('../../packages/ai-cli-control/kodexbar-tray', '.'),
        ('../../packages/ai-cli-control/icons/windows', 'icons/windows'),
        ('../../LICENSE', '.'),
        ('../../NOTICE.md', '.'),
    ],
    hiddenimports=[
        # kodexbar-tray is exec'd at runtime through importlib, so its own
        # imports stay invisible to the static analysis. Every stdlib module
        # it needs beyond kodexbar-tray-win's imports must be listed here.
        'pystray._win32',
        'json',
    ],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
)
pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name='KodexBarTray',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=False,
    console=False,
    icon='../../packages/ai-cli-control/icons/windows/kodexbar.ico',
)
coll = COLLECT(
    exe,
    a.binaries,
    a.datas,
    strip=False,
    upx=False,
    name='KodexBarTray',
)
