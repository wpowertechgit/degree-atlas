; Inno Setup script for Degree Atlas.
; Installs the Flutter Windows build together with the repository files the in-app agent works with
; (AGENTS.md, scripts, schemas, shared data, agent definitions), so the install folder is the repository root.
; Build from the repository root after `flutter build windows --release`:
;   ISCC.exe /DMyAppVersion=1.2.3 installer\degree-atlas.iss

#ifndef MyAppVersion
  #define MyAppVersion "0.0.0"
#endif
#define MyAppName "Degree Atlas"
#define MyAppExe "degree_atlas.exe"
#define BuildDir "..\app\build\windows\x64\runner\Release"

[Setup]
; Stable identifier for this installer. Do not change it between releases.
AppId={{D8F938E4-00CE-4EC1-AD96-D63FF585783C}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher=Degree Atlas
AppPublisherURL=https://github.com/wpowertechgit/degree-atlas
; Per-user and writable: the app and its agent write profiles\, work\ and data\ here.
DefaultDirName={localappdata}\Programs\DegreeAtlas
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=output
OutputBaseFilename=DegreeAtlas-Setup-{#MyAppVersion}
SetupIconFile=..\app\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\bin\{#MyAppExe}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
CloseApplications=yes
RestartApplications=no
VersionInfoVersion={#MyAppVersion}.0
VersionInfoProductName={#MyAppName}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Messages]
FinishedLabel=Setup has installed Degree Atlas. The writing agent also needs Python 3.10 or newer and Claude Code (https://claude.com/claude-code) on this computer.

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; The whole Flutter output (exe, DLLs, data\). The release workflow adds the Visual C++ runtime DLLs app-locally.
Source: "{#BuildDir}\*"; DestDir: "{app}\bin"; Flags: ignoreversion recursesubdirs createallsubdirs
; Repository files used by the agent. Generated data (subjects, degrees, universities) is never shipped.
Source: "..\AGENTS.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\CLAUDE.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\README.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\LICENSE"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\catalogs.json"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\requirements.txt"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\scripts\*"; DestDir: "{app}\scripts"; Excludes: "__pycache__"; Flags: ignoreversion recursesubdirs
Source: "..\schemas\*"; DestDir: "{app}\schemas"; Flags: ignoreversion recursesubdirs
Source: "..\data\*"; DestDir: "{app}\data"; Excludes: "subjects,degrees,universities,domains"; Flags: ignoreversion recursesubdirs
; Domain lists gain the user's own degrees, so an update never overwrites them.
Source: "..\data\domains\*"; DestDir: "{app}\data\domains"; Flags: onlyifdoesntexist uninsneveruninstall
Source: "..\.claude\agents\*"; DestDir: "{app}\.claude\agents"; Flags: ignoreversion recursesubdirs

[Dirs]
Name: "{app}\work"
Name: "{app}\profiles"

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\bin\{#MyAppExe}"; WorkingDir: "{app}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\bin\{#MyAppExe}"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
; Python packages for the scripts. Skipped silently when Python is not installed yet.
Filename: "{cmd}"; Parameters: "/c python -m pip install --user -q -r ""{app}\requirements.txt"""; StatusMsg: "Installing Python packages..."; Flags: runhidden waituntilterminated
Filename: "{app}\bin\{#MyAppExe}"; WorkingDir: "{app}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent
; The in-app updater runs setup with /SILENT /RELAUNCH=1 and expects the app to come back afterwards.
Filename: "{app}\bin\{#MyAppExe}"; WorkingDir: "{app}"; Flags: nowait; Check: WantsRelaunch

; profiles\, work\ and generated data are user content and are deliberately left on uninstall.

[Code]
// True when the in-app updater started setup and wants the app started again afterwards.
function WantsRelaunch: Boolean;
begin
  Result := ExpandConstant('{param:RELAUNCH|0}') = '1';
end;
