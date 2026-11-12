; A HARNESS installer for the running-work check (#700): its own AppId,
; installed per-user into a temp folder, a payload of a few stand-in programs.
; It includes ..\installer-running-work.iss UNCHANGED and calls it exactly as
; installer.iss does, so what run-harness.ps1 proves about it is what ships,
; without ever installing, upgrading or uninstalling the real Plantoir.
; Never ship this; it is compiled by run-harness.ps1 only.

#ifndef HarnessVersion
  #define HarnessVersion "1"
#endif
#ifndef PayloadDir
  #error PayloadDir must be passed: run-harness.ps1 builds it
#endif
#ifndef OutputFolder
  #error OutputFolder must be passed: run-harness.ps1 chooses it
#endif
; A must-fail run compiles against an edited copy of the include.
#ifndef RunningWorkInclude
  #define RunningWorkInclude "..\installer-running-work.iss"
#endif
; The version the include writes into its refusal marker.
#define AppVersion HarnessVersion
#ifndef RunningWorkWaitSeconds
  #define RunningWorkWaitSeconds 20
#endif

[Setup]
; A test's own id, never Plantoir's {A14C3E2D-...}.
AppId={{D7A92D73-E5AF-4D50-978A-D127394C485D}
AppName=Plantoir installer harness (test only)
AppVersion={#HarnessVersion}
AppPublisher=Plantoir tests
DefaultDirName={localappdata}\Temp\plantoir-installer-harness\app
DisableProgramGroupPage=yes
DisableDirPage=yes
PrivilegesRequired=lowest
TimeStampsInUTC=yes
OutputDir={#OutputFolder}
OutputBaseFilename=HarnessSetup-{#HarnessVersion}
Compression=lzma2/fast
SolidCompression=no
WizardStyle=modern
CloseApplications=yes
CloseApplicationsFilter=*Plantoir*,*plantoir-mcp*,*llama-server*

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

; The SAME lines as installer.iss's [InstallDelete] (run-harness.ps1 refuses
; to run when the two differ).
[InstallDelete]
Type: filesandordirs; Name: "{app}\runtime\vendor\tikz-engine\node_modules"
Type: filesandordirs; Name: "{app}\runtime\node"
Type: filesandordirs; Name: "{app}\runtime\vendor\geogebra"
Type: filesandordirs; Name: "{app}\runtime\wrangler"
Type: filesandordirs; Name: "{app}\runtime\python"
Type: filesandordirs; Name: "{app}\Toolchain\scripts\__pycache__"

[Files]
Source: "{#PayloadDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Code]
#include RunningWorkInclude

function IsUpdate: Boolean;
begin
  Result := ExpandConstant('{param:PLANTOIRUPDATE|0}') = '1';
end;

function WantsRelaunch: Boolean;
begin
  Result := ExpandConstant('{param:RELAUNCH|0}') = '1';
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
#ifdef HarnessOnlyAtSsInstall
  // The 'ssinstall' case: only the second look runs, to prove what its Abort does.
  Result := '';
#else
  Result := RunningWorkBeforeChangingFiles(IsUpdate, WantsRelaunch);
#endif
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  ResultCode: Integer;
begin
  if CurStep = ssInstall then
  begin
    if RunningWorkBeforeChangingFiles(IsUpdate, WantsRelaunch) <> '' then
      Abort;
    RunningWorkInstallingBegins;
    // The scheduled-during-copy cases: a scheduled run of the INSTALLED
    // Plantoir.exe (the harness's own {app}\Plantoir.exe, so its image is
    // what setup must replace) starts now, while the installing marker is
    // there. /HARNESSSCHEDULED= names how it behaves: stand down at once (what
    // ScheduledRun does), or wait while the marker is there (what it did before
    // the third review). Then 1.5 s for it to start and decide, before [Files].
    if ExpandConstant('{param:HARNESSSCHEDULED|}') <> '' then
    begin
      Exec(ExpandConstant('{app}\Plantoir.exe'),
           ExpandConstant('{param:HARNESSSCHEDULED|}') + ' "' + RunningWorkStateFolder + '"',
           '', SW_HIDE, ewNoWait, ResultCode);
      Sleep(1500);
    end;
  end;
  if CurStep = ssPostInstall then
  begin
    RunningWorkInstallingEnds;
    RunningWorkInstalledCleanly;
  end;
end;

procedure DeinitializeSetup;
begin
  RunningWorkInstallingEnds;
end;
