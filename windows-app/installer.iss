; Inno Setup Script for Plantoir
; Configured for zero-admin / per-user installation in school environments

#ifndef AppVersion
#define AppVersion "1.1.0"
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
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
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
// NOT on Plantoir's own update (/PLANTOIRUPDATE=1, #337 bundle-8 ruling 2): the
// app refuses to start that install while ANY plantoir-mcp runs, because one
// may be publishing in a folder the app has never opened, and a forced kill
// would cut a teacher's publish short. A hand-run installer keeps the kill.
function IsUpdate: Boolean;
begin
  Result := ExpandConstant('{param:PLANTOIRUPDATE|0}') = '1';
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
