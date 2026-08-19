; Inno Setup Script for Plantoir
; Configured for zero-admin / per-user installation in school environments

#ifndef AppVersion
#define AppVersion "1.0.0"
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

[Code]
// Terminate background helper processes before updating files. CloseApplications
// only catches processes the Restart Manager can see holding our files; these
// two are windowless console helpers, so kill them explicitly at ssInstall,
// the step that fires just before file copying begins.
procedure CurStepChanged(CurStep: TSetupStep);
var
  ResultCode: Integer;
begin
  if CurStep = ssInstall then
  begin
    Exec('taskkill.exe', '/F /IM plantoir-mcp.exe /T', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    Exec('taskkill.exe', '/F /IM llama-server.exe /T', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  end;
end;
