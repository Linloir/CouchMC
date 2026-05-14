; MC Controller — Inno Setup script
;
; Build the installer:
;   1. Install Inno Setup 6:  winget install JRSoftware.InnoSetup
;   2. Publish the app in Release config (from repo root):
;        & "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\MSBuild.exe" `
;            pc\McController.App\McController.App.csproj `
;            -p:Configuration=Release -p:Platform=x64 -p:RuntimeIdentifier=win-x64 `
;            -t:Rebuild
;   3. Compile this script:
;        & "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" installer\McController.iss
;   4. Output lands in installer\out\McController-Setup-{version}.exe (~80–90 MB
;      because the WindowsAppSDK runtime is bundled — self-contained install).
;
; The installer:
;   - Lays the app out under {userpf}\McController (per-user install, no admin)
;   - Creates Start Menu + optional Desktop shortcuts
;   - Registers a clean Add/Remove Programs entry
;   - On uninstall, optionally clears the user config in %APPDATA%\McController
;     after asking the user. The %LOCALAPPDATA%\McController error log is
;     wiped unconditionally because it has no value beyond a session.

#define AppName       "CouchMC"
#define AppVersion    "1.0.1"
#define AppPublisher  "Linloir"
#define AppExe        "CouchMC.exe"
#define BuildOutputDir "..\pc\McController.App\bin\x64\Release\net8.0-windows10.0.19041.0\win-x64"

[Setup]
; AppId is the reverse-DNS rebrand identifier — distinct from the older
; v0.x GUID, so v0.x installs are seen as a SEPARATE app by Inno Setup
; and won't auto-upgrade. That's intentional: the rebrand from
; "MC Controller" to "CouchMC" also moves to this new id. Users who
; want a clean install can uninstall the old "MC Controller" entry
; first; otherwise both will coexist.
AppId=cn.linloir.couchmc.win
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL=https://github.com/Linloir
DefaultDirName={userpf}\CouchMC
DefaultGroupName=CouchMC
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName={#AppName}
PrivilegesRequired=lowest
ArchitecturesInstallIn64BitMode=x64compatible
ArchitecturesAllowed=x64compatible
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
DisableProgramGroupPage=yes
OutputDir=out
OutputBaseFilename=CouchMC-Setup-{#AppVersion}
SetupIconFile=..\pc\McController.App\Assets\app.ico
; Per-user install: no UAC prompt, registers in HKCU.
UsedUserAreasWarning=no

[Languages]
Name: "english";    MessagesFile: "compiler:Default.isl"
Name: "chinese";    MessagesFile: "compiler:Languages\ChineseSimplified.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked
Name: "runatlogon"; Description: "Start CouchMC when I sign in to Windows"; GroupDescription: "Startup:"; Flags: unchecked

[Files]
; The whole self-contained publish output. WindowsAppSDKSelfContained=true in
; csproj means the WindowsAppRuntime DLLs are already in this folder, so the
; end-user install needs no separate runtime download.
Source: "{#BuildOutputDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\CouchMC"; Filename: "{app}\{#AppExe}"; IconFilename: "{app}\Assets\app.ico"
Name: "{group}\Uninstall CouchMC"; Filename: "{uninstallexe}"
Name: "{userdesktop}\CouchMC"; Filename: "{app}\{#AppExe}"; IconFilename: "{app}\Assets\app.ico"; Tasks: desktopicon

[Registry]
; "Run at logon" task — registers HKCU\Software\Microsoft\Windows\CurrentVersion\Run.
; The app's own GlobalSettings toggle reads/writes this same key, so the
; in-app switch and the installer checkbox stay in sync.
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; \
    ValueType: string; ValueName: "McController"; ValueData: """{app}\{#AppExe}"""; \
    Tasks: runatlogon; Flags: uninsdeletevalue

[Run]
Filename: "{app}\{#AppExe}"; Description: "Launch CouchMC"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; Wipe transient state unconditionally.
Type: filesandordirs; Name: "{localappdata}\McController"

[Code]
// On uninstall, ask whether to clear the user's config + profiles in
// %APPDATA%\McController. Default no — most users want to keep their
// tuning across reinstalls.
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  Path: string;
  KeepConfig: Integer;
begin
  if CurUninstallStep = usPostUninstall then
  begin
    Path := ExpandConstant('{userappdata}\McController');
    if DirExists(Path) then
    begin
      KeepConfig := MsgBox(
        '是否同时删除你的方案与配置 (%APPDATA%\McController)？'#13#10 +
        'Also remove your profiles and config (%APPDATA%\McController)?',
        mbConfirmation, MB_YESNO or MB_DEFBUTTON2);
      if KeepConfig = IDYES then
        DelTree(Path, True, True, True);
    end;
  end;
end;
