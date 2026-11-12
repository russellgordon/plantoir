; Inno Setup Script for Plantoir
; Configured for zero-admin / per-user installation in school environments

#ifndef AppVersion
#define AppVersion "1.4.3"
#endif

; publish.ps1 passes a short subst-drive path here: compiled from the repo's
; own depth, 103 toolchain files exceed MAX_PATH and ISCC aborts mid-compress
; with "The system cannot find the path specified".
#ifndef PublishDir
#define PublishDir "Plantoir\bin\Release\net9.0-windows10.0.19041.0\win-x64\publish"
#endif

[Setup]
AppId={{A14C3E2D-5F6B-4820-9D7A-83B92A769CE1}}
AppName=Plantoir
AppVersion={#AppVersion}
AppPublisher=Russell Gordon
AppPublisherURL=https://plantoir.app/
AppSupportURL=https://plantoir.app/support/
AppUpdatesURL=https://plantoir.app/
DefaultDirName={localappdata}\Programs\Plantoir
DisableProgramGroupPage=yes
; Per-user ONLY (Russell, 2026-10-01): no "install for all users" choice, so
; every copy this makes is under %LOCALAPPDATA%\Programs and can update itself
; (AppUpdates.IsPerUserInstall). An all-users copy left by an older installer
; still says it needs an administrator rather than updating beside itself.
PrivilegesRequired=lowest
; File times are stored in UTC (#559). The app trusts the build's manifest of
; the bundled tools (Toolchain\.hashes, exact UTC times) when an installed
; file's time is the manifest's rounded DOWN by under 2 s, which is what Inno's
; default TimeStampRounding=2 does. Stored as LOCAL time instead, every file
; would shift by an hour for a teacher who installs on the other side of a
; clocks change (1 November) from the build, and no tolerance covers that:
; every file would be read in full again on the first launch after the update.
TimeStampsInUTC=yes
OutputDir=dist
OutputBaseFilename=PlantoirSetup
SetupIconFile=Plantoir\Assets\Plantoir.ico
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
CloseApplicationsFilter=*Plantoir*,*plantoir-mcp*,*llama-server*
UninstallDisplayIcon={app}\Plantoir.exe

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

; Inno never removes a file a newer version no longer carries, and the TikZ
; engine's node_modules (#503) is installed from a lockfile: after a lockfile
; change, a package the new tree dropped would stay beside the new ones and
; Node could resolve it. So the folder is emptied before [Files] puts the
; current tree back. (runtime\quartz\node_modules has always had the same
; exposure; its tree has not changed since Quartz v4.5.0 was pinned, and was
; still identical on Node 22, #675.) runtime\node is emptied for the same
; reason since #675: Node 20.18.1 -> 22.23.4 replaces node.exe and the npm it
; carries (10.9.9 now), and the files an older npm had that the new one does not
; would otherwise stay inside it, for Node to resolve. And
; runtime\vendor\geogebra (#687): scripts\geogebra_engine.py makes the folder
; whole, so the next GeoGebra version must not inherit this one's files.
; runtime\wrangler (#719): wrangler 4.80.0 -> 4.156.0 is an npm prefix
; install whose dependencies are hoisted into runtime\wrangler\node_modules,
; and the move changes most of them in place (89 -> 91 packages; sharp
; 0.34.5 -> 0.35.5, ws 8.18.0 -> 8.21.0, undici 7.24.4 -> 7.30.1, miniflare
; 4 -> 5), so every file an old version had and its new one does not would
; stay beside the new tree, for Node to resolve and for the audit to find.
; runtime\python (#764): Python 3.11.9 -> 3.14.10 renames the interpreter's
; own files (python311.dll, python311.zip, python311._pth -> python314.*), and
; 3.11's get-pip installed setuptools, wheel and packaging, which 3.14's does
; not; Pillow's and PyYAML's cp311 .pyd files and the old pip's dist-info
; would stay in Lib\site-packages too. Python 3.14 loads none of them (it
; reads python314._pth only, and a cp311 extension is not a cp314 one), but a
; tree holding two Pythons is what the next reader and the next audit find.
; A process running from one of these folders holds its files, so nothing may
; be deleted here while one runs: PrepareToInstall waits for that work, or ends
; a preview's server, BEFORE this section runs (#700, installer-running-work.iss).
; Toolchain\scripts\__pycache__ (#700): bytecode some run of the bundled
; scripts wrote beside them, which no version ships; measured over 1.9.0, 12
; .pyc files for three Pythons (cpython-311, -312 and -314) were the only
; files an upgrade left that the new version does not carry.
[InstallDelete]
Type: filesandordirs; Name: "{app}\runtime\vendor\tikz-engine\node_modules"
Type: filesandordirs; Name: "{app}\runtime\node"
Type: filesandordirs; Name: "{app}\runtime\vendor\geogebra"
Type: filesandordirs; Name: "{app}\runtime\wrangler"
Type: filesandordirs; Name: "{app}\runtime\python"
Type: filesandordirs; Name: "{app}\Toolchain\scripts\__pycache__"

[Files]
Source: "{#PublishDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Plantoir"; Filename: "{app}\Plantoir.exe"
Name: "{autodesktop}\Plantoir"; Filename: "{app}\Plantoir.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\Plantoir.exe"; Description: "{cm:LaunchProgram,Plantoir}"; Flags: nowait postinstall skipifsilent
; Plantoir's own update (#337, bundle-8 ruling 1): the in-app Install passes
; /RELAUNCH=1, so "Install and Reopen" is true of a /VERYSILENT install that
; skipifsilent above would otherwise never reopen. The at-quit install does not
; pass it, and nothing else does.
Filename: "{app}\Plantoir.exe"; Flags: nowait; Check: WantsRelaunch

[Code]
// Terminate background helper processes before updating files. CloseApplications
// only catches processes the Restart Manager can see holding our files; these
// two are windowless console helpers, so kill them explicitly at ssInstall,
// the step that fires just before file copying begins.
//
// NOT on Plantoir's own update (/PLANTOIRUPDATE=1, #337 bundle-8 rulings 2 and
// 8): the app refuses to start that install while ANY plantoir-mcp runs (one
// may be publishing in a folder the app has never opened), and passes
// /NOCLOSEAPPLICATIONS so Restart Manager does not close plantoir-mcp or a
// scheduled run either -- CloseApplicationsFilter below still names them for a
// hand-run install. InitializeSetup also refuses an update while plantoir-mcp
// runs, for one started after the app's last check. A file still in use at
// copy time made the update fail part way (measured 2026-11-12, #700: a
// preview serving, exit 5, a broken install), so PrepareToInstall now waits
// for work running from {app}, or ends a preview's server, before any file is
// changed (installer-running-work.iss, below). A hand-run installer keeps the
// kill and the closing.
#include "installer-running-work.iss"

function IsUpdate: Boolean;
begin
  Result := ExpandConstant('{param:PLANTOIRUPDATE|0}') = '1';
end;

function InitializeSetup: Boolean;
var
  ResultCode: Integer;
begin
  Result := True;
  if IsUpdate then
  begin
    // find.exe exits 0 when the name is in tasklist's output: a plantoir-mcp is running.
    if Exec(ExpandConstant('{cmd}'), '/C tasklist /FI "IMAGENAME eq plantoir-mcp.exe" | find /I "plantoir-mcp.exe"',
            '', SW_HIDE, ewWaitUntilTerminated, ResultCode) and (ResultCode = 0) then
    begin
      Result := False;
      // Ruling 12: the app has already quit, so reopen it and let it say why.
      if ExpandConstant('{param:RETURNTO|}') <> '' then
        Exec(ExpandConstant('{param:RETURNTO|}'), '--update-not-installed', '', SW_SHOW, ewNoWait, ResultCode);
    end;
  end;
end;

function WantsRelaunch: Boolean;
begin
  Result := ExpandConstant('{param:RELAUNCH|0}') = '1';
end;

// Before ANY file is changed (#700): runs before [InstallDelete] and [Files],
// and before Restart Manager's check on a hand-run install. A non-empty answer
// stops setup on the Preparing to Install page, which a silent install leaves
// with exit code 7, nothing deleted and nothing copied.
function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  Result := RunningWorkBeforeChangingFiles(IsUpdate, WantsRelaunch);
end;

// The `app updated` trail line (#428 item 1): Plantoir writes "by its own
// updater" only when this file names the version now running, and removes it at
// every launch (AppUpdates.ConsumeUpdatedByItselfMarker). EVERY install deletes
// it before copying, and only an update that FINISHES writes it (ssPostInstall),
// so a refused or failed update can never make a later hand install read as
// the updater's. In the state folder, where the app looks, never under {app}.
// ssPostInstall runs before the [Run] entry that reopens Plantoir, so the
// relaunched copy finds it; were that order ever reversed, the line would say
// "by hand" and the next launch would discard the marker with no line at all.
function UpdatedByItselfMarker: String;
begin
  Result := ExpandConstant('{localappdata}\Plantoir\installed-by-its-own-updater.txt');
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  ResultCode: Integer;
begin
  if CurStep = ssInstall then
  begin
    // Looked for again (#700): a hand-run wizard can sit on Restart Manager's
    // page for minutes after PrepareToInstall, and a scheduled deploy can
    // start meanwhile. Still before [InstallDelete]; Abort here ends setup
    // with nothing changed.
    if RunningWorkBeforeChangingFiles(IsUpdate, WantsRelaunch) <> '' then
      Abort;
    DeleteFile(UpdatedByItselfMarker);
    if not IsUpdate then
    begin
      Exec('taskkill.exe', '/F /IM plantoir-mcp.exe /T', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
      Exec('taskkill.exe', '/F /IM llama-server.exe /T', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    end;
  end;
  if (CurStep = ssPostInstall) and IsUpdate then
  begin
    ForceDirectories(ExpandConstant('{localappdata}\Plantoir'));
    SaveStringToFile(UpdatedByItselfMarker, '{#AppVersion}', False);
  end;
end;
