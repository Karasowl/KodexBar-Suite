; Inno Setup script for the KodexBar Suite Windows installer.
; Build with:  iscc /DAppVersion=0.12.10 kodexbar-suite.iss
; Prerequisite: run build.ps1 first so build\stage\KodexBar-Suite is populated.

#define AppName "KodexBar Suite"
#ifndef AppVersion
#define AppVersion "0.0.0"
#endif

[Setup]
AppId={{7E5A2C64-52B1-4B3F-9E0D-4A7B6C1D8F21}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=Karasowl
AppPublisherURL=https://github.com/Karasowl/KodexBar-Suite
AppSupportURL=https://github.com/Karasowl/KodexBar-Suite/issues
DefaultDirName={autopf}\KodexBar-Suite
PrivilegesRequired=lowest
ArchitecturesInstallIn64BitMode=x64compatible
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
OutputDir=build\installer
OutputBaseFilename=KodexBar-Suite-{#AppVersion}-windows-setup
UninstallDisplayIcon={app}\KodexBarTray.exe
DisableProgramGroupPage=yes
LicenseFile=..\..\LICENSE

[Tasks]
Name: "autostart"; Description: "Iniciar KodexBar Tray al iniciar Windows"; Flags: unchecked
Name: "addpath"; Description: "Añadir las herramientas (ai, kodexbar-quotas) al PATH del usuario"; Flags: unchecked

[Files]
Source: "build\stage\KodexBar-Suite\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}\KodexBar Tray"; Filename: "{app}\KodexBarTray.exe"; Comment: "Monitor de cuotas de IA en la bandeja"
Name: "{autoprograms}\{#AppName}\AI CLI Control"; Filename: "{app}\ai.exe"; Comment: "Selector de CLIs de IA"

[Registry]
Root: HKCU; Subkey: "Environment"; ValueType: expandsz; ValueName: "Path"; ValueData: "{olddata};{app}"; Tasks: addpath; Check: NeedsAddPath('{app}')
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "KodexBarTray"; ValueData: """{app}\KodexBarTray.exe"""; Tasks: autostart; Flags: uninsdeletevalue

[Run]
Filename: "{app}\KodexBarTray.exe"; Description: "Iniciar KodexBar Tray"; Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "{cmd}"; Parameters: "/C taskkill /IM KodexBarTray.exe /F"; Flags: runhidden; RunOnceId: "StopTray"

[Code]
function NeedsAddPath(Param: string): boolean;
var
  OrigPath: string;
  AppDir: string;
begin
  AppDir := Param;
  if not RegQueryStringValue(HKEY_CURRENT_USER, 'Environment', 'Path', OrigPath) then
  begin
    Result := True;
    exit;
  end;
  Result := Pos(';' + Uppercase(AppDir) + ';', ';' + Uppercase(OrigPath) + ';') = 0;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  OrigPath: string;
  AppDir: string;
  Remove: string;
  Pos1: Integer;
begin
  if CurUninstallStep <> usUninstall then
    exit;
  if not RegQueryStringValue(HKEY_CURRENT_USER, 'Environment', 'Path', OrigPath) then
    exit;
  AppDir := ExpandConstant('{app}');
  Remove := ';' + Uppercase(OrigPath) + ';';
  Pos1 := Pos(';' + Uppercase(AppDir) + ';', Remove);
  if Pos1 = 0 then
    exit;
  Delete(Remove, Pos1, Length(AppDir) + 2);
  OrigPath := Copy(Remove, 2, Length(Remove) - 2);
  RegWriteStringValue(HKEY_CURRENT_USER, 'Environment', 'Path', OrigPath);
end;
