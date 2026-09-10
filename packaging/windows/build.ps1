# Builds the KodexBar Suite Windows bundle: tray app, console tools, zip, installer.
#
# Usage (from any directory, on Windows with Python 3.10+):
#   pwsh packaging/windows/build.ps1                # zip only
#   pwsh packaging/windows/build.ps1 -Installer     # zip + Inno Setup installer (needs iscc on PATH)
#
# Outputs land in packaging/windows/build/stage/KodexBar-Suite and packaging/windows/build/dist.

[CmdletBinding()]
param(
    [switch]$Installer
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$windowsRoot = $PSScriptRoot
$buildRoot = Join-Path $windowsRoot "build"
$entrypoints = Join-Path $buildRoot "entrypoints"
$stageRoot = Join-Path $buildRoot "stage"
$stage = Join-Path $stageRoot "KodexBar-Suite"
$distRoot = Join-Path $buildRoot "dist"
$workRoot = Join-Path $buildRoot "work"

$metadata = Get-Content (Join-Path $repoRoot "packages\kodexbar\metadata.json") -Raw | ConvertFrom-Json
$version = $metadata.KPlugin.Version
Write-Host "Building KodexBar Suite $version for Windows"

function Copy-Entrypoint([string]$SourceName, [string]$TargetName) {
    $source = Join-Path $repoRoot "packages\ai-cli-control\$SourceName"
    $target = Join-Path $entrypoints $TargetName
    Copy-Item $source $target -Force
}

function Invoke-PyInstaller([string]$Entrypoint, [string]$Name, [switch]$Windowed) {
    $arguments = @(
        "-m", "PyInstaller", "--noconfirm", "--clean",
        "--distpath", $distRoot, "--workpath", (Join-Path $workRoot $Name),
        "--specpath", (Join-Path $workRoot $Name),
        "--name", $Name
    )
    if ($Windowed) { $arguments += "--windowed" } else { $arguments += "--console" }
    $arguments += (Join-Path $entrypoints $Entrypoint)
    & python @arguments
    if ($LASTEXITCODE -ne 0) { throw "PyInstaller failed for $Name" }
}

# 1. Prepare entrypoints: PyInstaller analyzes plain .py files, the installed
#    names have no extension.
New-Item -ItemType Directory -Force -Path $entrypoints, $stageRoot, $stage, $distRoot, $workRoot | Out-Null
Copy-Entrypoint "kodexbar-tray-win" "KodexBarTray.py"
Copy-Entrypoint "kodexbar-quotas" "kodexbar-quotas.py"
Copy-Entrypoint "kodexbar-panel" "kodexbar-panel.py"
Copy-Entrypoint "ai" "ai.py"
Copy-Entrypoint "kodexbar-skills" "kodexbar-skills.py"
Copy-Entrypoint "local-ai" "local-ai.py"
Copy-Entrypoint "recover.py" "ai-recover.py"

# 2. Build the tray app (onedir, no console) and the console tools (onefile).
Push-Location $windowsRoot
try {
    & python -m PyInstaller --noconfirm --clean KodexBarTray.spec --distpath $distRoot --workpath (Join-Path $workRoot "KodexBarTray")
    if ($LASTEXITCODE -ne 0) { throw "PyInstaller failed for KodexBarTray" }
}
finally {
    Pop-Location
}
Invoke-PyInstaller "kodexbar-quotas.py" "kodexbar-quotas"
Invoke-PyInstaller "kodexbar-panel.py" "kodexbar-panel"
Invoke-PyInstaller "ai.py" "ai"
Invoke-PyInstaller "kodexbar-skills.py" "kodexbar-skills"
Invoke-PyInstaller "local-ai.py" "local-ai"
Invoke-PyInstaller "ai-recover.py" "ai-recover"

# 3. Stage one flat folder: tray app plus sibling tools it can find.
Copy-Item (Join-Path $distRoot "KodexBarTray\*") $stage -Recurse -Force
foreach ($tool in @("kodexbar-quotas", "kodexbar-panel", "ai", "kodexbar-skills", "local-ai", "ai-recover")) {
    Copy-Item (Join-Path $distRoot "$tool.exe") $stage -Force
}

# 4. Zip artifact.
$zip = Join-Path $distRoot "KodexBar-Suite-$version-windows-x64.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path $stage -DestinationPath $zip
Write-Host "Portable bundle: $zip"

# 5. Optional installer through Inno Setup.
$installerExe = $null
if ($Installer) {
    $iscc = Get-Command "iscc" -ErrorAction SilentlyContinue
    if ($null -eq $iscc) { throw "iscc not found on PATH. Install Inno Setup and retry." }
    & iscc /DAppVersion=$version (Join-Path $windowsRoot "kodexbar-suite.iss")
    if ($LASTEXITCODE -ne 0) { throw "Inno Setup failed" }
    $installerExe = Get-ChildItem (Join-Path $buildRoot "installer") -Filter "KodexBar-Suite-*-windows-setup.exe" |
        Select-Object -First 1
    Write-Host "Installer: $($installerExe.FullName)"
}

# 6. Checksums for the artifacts that this run actually produced.
$checksums = Join-Path $distRoot "SHA256SUMS-windows"
$lines = @(
    "{0}  {1}" -f (Get-FileHash $zip -Algorithm SHA256).Hash.ToLowerInvariant(), (Split-Path $zip -Leaf)
)
if ($null -ne $installerExe) {
    $lines += "{0}  {1}" -f (Get-FileHash $installerExe.FullName -Algorithm SHA256).Hash.ToLowerInvariant(), $installerExe.Name
}
Set-Content -Path $checksums -Value $lines -Encoding ascii
Write-Host "Checksums: $checksums"
