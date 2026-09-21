# Installs KodexBar Suite on Windows from the latest GitHub release.
#
# One-line install in PowerShell (no administrator rights needed):
#   irm https://raw.githubusercontent.com/Karasowl/KodexBar-Suite/main/packaging/windows/Install.ps1 | iex
#
# The script resolves the latest release through the GitHub API, downloads the
# per-user setup exe plus SHA256SUMS-windows, verifies the checksum, and runs
# the installer silently with autostart and user PATH enabled.

[CmdletBinding()]
param(
    [string]$Version = "latest",
    [string]$Tasks = "autostart,addpath"
)

$ErrorActionPreference = "Stop"

$repo = "Karasowl/KodexBar-Suite"
if ($Version -eq "latest") {
    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/latest"
}
else {
    if ($Version.StartsWith("v")) { $tag = $Version } else { $tag = "v$Version" }
    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/tags/$tag"
}

$setupAsset = $release.assets | Where-Object { $_.name -like "*-windows-setup.exe" } | Select-Object -First 1
if ($null -eq $setupAsset) { throw "No Windows setup found in release $($release.tag_name)." }
$sumsAsset = $release.assets | Where-Object { $_.name -eq "SHA256SUMS-windows" } | Select-Object -First 1
if ($null -eq $sumsAsset) { throw "No SHA256SUMS-windows found in release $($release.tag_name)." }

$dir = Join-Path $env:TEMP "kodexbar-suite-install"
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$setupPath = Join-Path $dir $setupAsset.name
$sumsPath = Join-Path $dir "SHA256SUMS-windows"
Invoke-WebRequest -Uri $setupAsset.browser_download_url -OutFile $setupPath
Invoke-WebRequest -Uri $sumsAsset.browser_download_url -OutFile $sumsPath

$expected = $null
foreach ($line in (Get-Content $sumsPath)) {
    $parts = $line.Split(" ", [System.StringSplitOptions]::RemoveEmptyEntries)
    if ($parts.Count -ge 2 -and $parts[1].TrimStart("*") -eq $setupAsset.name) { $expected = $parts[0] }
}
if ([string]::IsNullOrEmpty($expected)) { throw "Checksum entry missing for $($setupAsset.name)." }
$actual = (Get-FileHash $setupPath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actual -ne $expected.ToLowerInvariant()) { throw "Checksum mismatch for $($setupAsset.name)." }

Write-Host "Checksum OK. Installing $($release.tag_name)..."
Start-Process -FilePath $setupPath -ArgumentList "/VERYSILENT", "/TASKS=`"$Tasks`"" -Wait
$tray = $null
try {
    $tray = (Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{7E5A2C64-52B1-4B3F-9E0D-4A7B6C1D8F21}_is1" -ErrorAction Stop).InstallLocation
} catch {
    $tray = $null
}
if ([string]::IsNullOrEmpty($tray)) {
    $tray = Join-Path $env:LOCALAPPDATA "Programs\KodexBar-Suite"
}
$trayExe = Join-Path $tray "KodexBarTray.exe"
if (Test-Path $trayExe) {
    Start-Process -FilePath $trayExe
    Write-Host "KodexBar Suite installed and the tray is starting. Look for its icon by the clock."
} else {
    Write-Host "KodexBar Suite installed. Open KodexBar Tray from the Start menu."
}
