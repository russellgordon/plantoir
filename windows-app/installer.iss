; Inno Setup Script for Plantoir
; Configured for zero-admin / per-user installation in school environments

#ifndef AppVersion
#define AppVersion "1.4.2"
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
// runs, for one started after the app's last check. Residual risk, UNEXERCISED:
// a file still in use at copy time leaves the update to fail under /NORESTART.
// A hand-run installer keeps the kill and the closing.
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

procedure CurStepChanged(CurStep: TSetupStep);
var
  ResultCode: Integer;
begin
  if CurStep = ssInstall then
  begin
    if not IsUpdate then
    begin
      Exec('taskkill.exe', '/F /IM plantoir-mcp.exe /T', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
      Exec('taskkill.exe', '/F /IM llama-server.exe /T', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    end;
  end;
end;
