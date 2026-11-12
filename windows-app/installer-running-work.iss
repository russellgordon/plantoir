// Work still running from the installed copy, looked for BEFORE the installer
// changes any file (#700). Included by installer.iss and, unchanged, by the
// harness in installer-tests\, so the code the harness proves is the code
// that ships. Pascal only: no [Section] in this file.
//
// What the night of 2026-11-11/12 measured (documentation/12-windows-app.md ->
// "The installer waits for work that is still running (#700)"): the update
// from 1.9.0 runs 1.9.0's app code with the NEW installer, with
// /NOCLOSEAPPLICATIONS, so Restart Manager closes nothing, and [InstallDelete]
// then empties runtime\node and runtime\python while a process runs from
// them. A preview's node.exe never exits: the copy of runtime\node\node.exe
// failed "in use", the hidden box defaulted to Abort, setup exited 5 and its
// rollback could not put back what [InstallDelete] had removed (a broken
// install). A build's python.exe that had exited by the time [Files] reached
// it gave exit 0 with python311.dll and a loaded cp311 .pyd left beside 3.14.
//
// So, before [InstallDelete] (PrepareToInstall runs before it, and before
// Restart Manager's own check), and again at ssInstall (the last moment before
// [InstallDelete], which a hand-run wizard can reach minutes later):
//   - a preview's serving node.exe is ENDED, with its children: a preview is
//     not work a teacher loses (appUpdates.mayNotInstallWhile: an open preview
//     does not hold an update), and it never exits by itself;
//   - llama-server.exe on the update path is ended too: the local assistant's
//     engine, which the app that started it has already quit;
//   - any other process whose executable is under {app} (a build's python or
//     node, a deploy's python or wrangler node, a scheduled run's Plantoir.exe,
//     the quitting app itself) is WAITED for, never killed: a deploy cut part
//     way is the one thing a teacher cannot get back;
//   - a silent install waits up to RunningWorkWaitSeconds and then REFUSES
//     (PrepareToInstall returns a message: exit code 7, nothing changed); a
//     hand-run wizard asks Retry or Cancel instead, with no time limit, but
//     not within RunningWorkGraceAfterEndingMs of ending something, so the
//     python a just-ended preview leaves behind is not asked about as work.
//
// How processes are found: K32EnumProcesses, then OpenProcess with
// PROCESS_QUERY_LIMITED_INFORMATION and QueryFullProcessImageNameW for the
// path, and NtQueryInformationProcess(ProcessCommandLineInformation) for the
// command line of the few under {app}. Kernel calls, so nothing here can hang
// the way a WMI query can when the WMI service is slow or broken; no wmic
// (gone from current Windows) and no PowerShell. A process whose path cannot
// be read (another account's, or a protected one) cannot be under this
// per-user {app}. A command line that cannot be read makes a node.exe count as
// WORK, never as a preview: the safe direction is to wait, not to kill.

#ifndef RunningWorkWaitSeconds
  // Ten minutes. The longest work the documentation has measured on this
  // project's PC: getting a Swift course ready plus its build, 263 s; a full
  // rebuild 63-129 s; a deploy's Cloudflare wait up to 120 s on top of its
  // build; and a scheduled deploy waits up to ten minutes for a busy course
  // before it starts. The app's own gate holds an update for the work it knows
  // of, so the installer meets only work the app did not see. Beyond ten
  // minutes the install is refused, the teacher's copy is left exactly as it
  // was, and the update is offered again.
  #define RunningWorkWaitSeconds 600
#endif

#ifndef RunningWorkSilent
  // Which path a look takes: the silent wait, or the hand-run wizard's
  // Retry/Cancel box. installer.iss never defines this. The harness compiles
  // one installer with it set to False, so a /VERYSILENT /SUPPRESSMSGBOXES run
  // takes the hand-run path and the box answers its default (Cancel) unseen
  // and unheard: a box that would have been shown is a refusal in its log.
  #define RunningWorkSilent "WizardSilent"
#endif

#ifndef RunningWorkGraceAfterEndingMs
  // After this run ENDED something (a preview's server, the assistant's
  // engine), the hand-run wizard looks again for this long before it asks.
  // What it ended leaves remains that are about to go: a preview's
  // build_site.py python exits once its server is gone (measured on the real
  // installer, 2026-11-12: 0.3 s after the ending; B2, silent: nothing running
  // 1.24 s after it). Without this, the look that ended the server counted that
  // python as work and asked "still building or deploying" about a preview.
  // Real work beside a preview is still asked about, this much later.
  #define RunningWorkGraceAfterEndingMs 5000
#endif

const
  RwProcessQueryLimitedInformation = $1000;
  RwProcessCommandLineInformation = 60;
  RwWaitSeconds = {#RunningWorkWaitSeconds};
  RwGraceAfterEndingMs = {#RunningWorkGraceAfterEndingMs};

  // What a teacher reads. Plain words (CLAUDE.md rule 1): no "runtime",
  // "script", "process" or "toolchain". Windows mechanics with no mac
  // counterpart (the mac's updater is Sparkle), so they live here and the
  // reason is in documentation/12-windows-app.md.
  RwStillWorkingRetry =
    'Plantoir is still building or deploying a course.' + #13#10#13#10 +
    'Wait for it to finish, then click Retry. Or click Cancel to install another time.';
  RwRefusedForWork =
    'Plantoir is still building or deploying a course, so the new version was not installed. ' +
    'Run this installer again once that has finished.';
  RwRefusedForAssistant =
    'An assistant in another app is using Plantoir, so the new version was not installed.';
  RwRefusedReopened =
    'Plantoir was opened again, so the new version was not installed. It will be offered again.';

  // What the reopened app is told (AppUpdates.UpdateNotInstalledForWorkArgument).
  RwNotInstalledForWorkArgument = '--update-not-installed-for-work';

  // The markers in the state folder (AppUpdates.NotInstalledMarker and
  // AppUpdates.InstallingMarkerPrefix).
  RwNotInstalledMarker = 'update-not-installed.txt';
  RwInstallingMarkerPrefix = 'installing.';

function RwGetCurrentProcessId: Cardinal;
  external 'GetCurrentProcessId@kernel32.dll stdcall';

function RwEnumProcesses(lpidProcess: AnsiString; cb: Cardinal; var lpcbNeeded: Cardinal): BOOL;
  external 'K32EnumProcesses@kernel32.dll stdcall';
function RwOpenProcess(dwDesiredAccess: Cardinal; bInheritHandle: BOOL; dwProcessId: Cardinal): THandle;
  external 'OpenProcess@kernel32.dll stdcall';
function RwCloseHandle(hObject: THandle): BOOL;
  external 'CloseHandle@kernel32.dll stdcall';
function RwQueryFullProcessImageName(hProcess: THandle; dwFlags: Cardinal; lpExeName: String; var lpdwSize: Cardinal): BOOL;
  external 'QueryFullProcessImageNameW@kernel32.dll stdcall';
function RwNtQueryInformationProcess(ProcessHandle: THandle; ProcessInformationClass: Integer;
  ProcessInformation: AnsiString; ProcessInformationLength: Cardinal; var ReturnLength: Cardinal): Integer;
  external 'NtQueryInformationProcess@ntdll.dll stdcall';
function RwGetTickCount: Cardinal;
  external 'GetTickCount@kernel32.dll stdcall';

var
  // One look: the processes under {app}, in parallel arrays.
  RwPids: array of Cardinal;
  RwPaths: TArrayOfString;
  RwCommandLines: TArrayOfString;
  // Processes this installer has already tried to end. One still there on the
  // next look counts as work, so a process that cannot be ended is waited for
  // and refused like any other rather than "ended" for ever.
  RwTriedToEnd: array of Cardinal;
  // Processes already named in the setup log as waited for, so each is named once.
  RwLogged: array of Cardinal;
  // The Plantoir.exe processes under {app} at the FIRST look of this setup
  // (the app still quitting, a scheduled run). One that appears after it, on
  // the update path, is the teacher opening Plantoir again: refused at once.
  RwPlantoirAtStart: array of Cardinal;
  RwLookedOnce: Boolean;
  // When this setup last ended something (RwEnd), for the hand-run grace.
  RwEndedAny: Boolean;
  RwLastEndedTick: Cardinal;
  RwGraceLogged: Boolean;

function RwByte(const Buffer: AnsiString; Offset: Integer): Cardinal;
begin
  Result := Ord(Buffer[Offset + 1]);
end;

function RwDword(const Buffer: AnsiString; Offset: Integer): Cardinal;
begin
  Result := RwByte(Buffer, Offset) or (RwByte(Buffer, Offset + 1) shl 8) or
            (RwByte(Buffer, Offset + 2) shl 16) or (RwByte(Buffer, Offset + 3) shl 24);
end;

// The command line, or '' when it cannot be read. The answer is a
// UNICODE_STRING followed by its characters in the same buffer; the header is
// 8 bytes in a 32-bit caller (Setup is one) and 16 in a 64-bit one, and the
// characters (plus at most a terminator) fill the rest, so the header is what
// the returned length leaves over.
function RwCommandLineOf(Handle: THandle): String;
var
  Buffer: AnsiString;
  Returned, Chars, Header, I: Cardinal;
begin
  Result := '';
  Buffer := StringOfChar(#0, 65536);
  Returned := 0;
  if RwNtQueryInformationProcess(Handle, RwProcessCommandLineInformation, Buffer, 65536, Returned) <> 0 then
    Exit;
  if Returned < 8 then Exit;
  Chars := RwByte(Buffer, 0) or (RwByte(Buffer, 1) shl 8);
  if Returned < Chars then Exit;
  Header := Returned - Chars;
  if Header >= 16 then Header := 16 else Header := 8;
  if Header + Chars > 65536 then Exit;
  I := 0;
  while I + 1 < Chars do
  begin
    Result := Result + Chr(RwByte(Buffer, Header + I) or (RwByte(Buffer, Header + I + 1) shl 8));
    I := I + 2;
  end;
end;

// Fill RwPids/RwPaths/RwCommandLines with every process whose executable is
// under AppDir. False when the list of processes itself could not be had.
function RwLookUnder(const AppDir: String): Boolean;
var
  Ids: AnsiString;
  Needed, Count, I, Pid, Size, Room: Cardinal;
  Handle: THandle;
  Path, Prefix: String;
  N: Integer;
begin
  Result := False;
  SetArrayLength(RwPids, 0);
  SetArrayLength(RwPaths, 0);
  SetArrayLength(RwCommandLines, 0);
  Prefix := Lowercase(AddBackslash(AppDir));
  // K32EnumProcesses cannot say how many processes there are: it fills the
  // buffer, and a full buffer (Needed = its size) may have left some out. So
  // a full answer is asked again with twice the room, from 8,192 ids (a busy
  // PC runs about 300) up to 131,072; still full after that, the list counts
  // as unreadable, the safe default below. The harness cannot fill 8,192
  // ids, so this branch is reasoned, not run.
  Room := 8192;
  while True do
  begin
    Ids := StringOfChar(#0, 4 * Room);
    Needed := 0;
    if not RwEnumProcesses(Ids, 4 * Room, Needed) then Exit;
    if Needed < 4 * Room then Break;
    if Room >= 131072 then Exit;
    Room := Room * 2;
  end;
  Result := True;
  Count := Needed div 4;
  if Count = 0 then Exit;
  for I := 0 to Count - 1 do
  begin
    Pid := RwDword(Ids, I * 4);
    if Pid <= 4 then Continue;
    Handle := RwOpenProcess(RwProcessQueryLimitedInformation, False, Pid);
    if Handle = 0 then Continue;
    Path := StringOfChar(#0, 1024);
    Size := 1024;
    if RwQueryFullProcessImageName(Handle, 0, Path, Size) then
    begin
      SetLength(Path, Size);
      if Pos(Prefix, Lowercase(Path)) = 1 then
      begin
        N := GetArrayLength(RwPids);
        SetArrayLength(RwPids, N + 1);
        SetArrayLength(RwPaths, N + 1);
        SetArrayLength(RwCommandLines, N + 1);
        RwPids[N] := Pid;
        RwPaths[N] := Path;
        RwCommandLines[N] := RwCommandLineOf(Handle);
      end;
    end;
    RwCloseHandle(Handle);
  end;
end;

// A whole token of the command line, never a substring: `--serve` is what the
// launcher adds to Quartz for a preview and never for a build (preview.ps1
// Test-IsServing and scripts/stop_preview.py use the same separator).
function RwHasToken(const CommandLine, Token: String): Boolean;
var
  Padded: String;
begin
  Padded := ' ' + CommandLine + ' ';
  StringChangeEx(Padded, #9, ' ', True);
  Result := Pos(' ' + Token + ' ', Padded) > 0;
end;

// A preview's server: node.exe running Quartz's bootstrap-cli.mjs with
// --serve (build_site.py starts it as `node <output>\quartz\bootstrap-cli.mjs
// build --concurrency 1 --serve --port N --wsPort M`). A build's node has no
// --serve; wrangler's node runs wrangler's own script, never bootstrap-cli.mjs.
function RwIsPreviewServer(const Path, CommandLine: String): Boolean;
begin
  Result := (Lowercase(ExtractFileName(Path)) = 'node.exe') and
            (Pos('bootstrap-cli.mjs', Lowercase(CommandLine)) > 0) and
            RwHasToken(CommandLine, '--serve');
end;

function RwIn(const List: array of Cardinal; Pid: Cardinal): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 0 to GetArrayLength(List) - 1 do
    if List[I] = Pid then
    begin
      Result := True;
      Exit;
    end;
end;

function RwAlreadyTried(Pid: Cardinal): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 0 to GetArrayLength(RwTriedToEnd) - 1 do
    if RwTriedToEnd[I] = Pid then
    begin
      Result := True;
      Exit;
    end;
end;

procedure RwEnd(Pid: Cardinal; const Path, Why: String);
var
  ResultCode, N: Integer;
begin
  Log(Format('Running work: ending %s (pid %d, %s)', [Path, Pid, Why]));
  // /T: the server's own children go with it. taskkill.exe is in every
  // Windows; installer.iss already ends plantoir-mcp the same way.
  Exec('taskkill.exe', Format('/F /T /PID %d', [Pid]), '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  N := GetArrayLength(RwTriedToEnd);
  SetArrayLength(RwTriedToEnd, N + 1);
  RwTriedToEnd[N] := Pid;
  RwEndedAny := True;
  RwLastEndedTick := RwGetTickCount;
end;

// True while what this setup ended may still be leaving (the hand-run grace).
function RwJustEndedSomething: Boolean;
begin
  Result := RwEndedAny and (RwGetTickCount - RwLastEndedTick < RwGraceAfterEndingMs);
end;

// '' when nothing under AppDir is still working, so files may be changed now;
// otherwise the sentence the install is refused with. Updating: the app's own
// update (/PLANTOIRUPDATE=1). Silent: a silent install (wait up to
// RwWaitSeconds; no box can be answered) as against a hand-run wizard (Retry
// or Cancel, no time limit).
function RunningWorkRefusal(const AppDir: String; Updating, Silent: Boolean): String;
var
  Started, Elapsed: Cardinal;
  I, Work, Ended: Integer;
  Name, Line: String;
begin
  Result := '';
  Started := RwGetTickCount;
  while True do
  begin
    if not RwLookUnder(AppDir) then
    begin
      // The list of processes could not be had at all. Go ahead: refusing
      // every install on a machine where this one call fails would be a fault
      // of its own, and going ahead is what every installer before #700 did.
      Log('Running work: the list of processes could not be read; going ahead without looking');
      Exit;
    end;
    if not RwLookedOnce then
    begin
      RwLookedOnce := True;
      for I := 0 to GetArrayLength(RwPids) - 1 do
        if Lowercase(ExtractFileName(RwPaths[I])) = 'plantoir.exe' then
        begin
          SetArrayLength(RwPlantoirAtStart, GetArrayLength(RwPlantoirAtStart) + 1);
          RwPlantoirAtStart[GetArrayLength(RwPlantoirAtStart) - 1] := RwPids[I];
        end;
    end;
    Work := 0;
    Ended := 0;
    for I := 0 to GetArrayLength(RwPids) - 1 do
    begin
      Name := Lowercase(ExtractFileName(RwPaths[I]));
      Line := RwCommandLines[I];
      if RwAlreadyTried(RwPids[I]) then
      begin
        if not RwIn(RwLogged, RwPids[I]) then
        begin
          Log(Format('Running work: pid %d (%s) is still there after being ended; waiting for it', [RwPids[I], RwPaths[I]]));
          SetArrayLength(RwLogged, GetArrayLength(RwLogged) + 1);
          RwLogged[GetArrayLength(RwLogged) - 1] := RwPids[I];
        end;
        Work := Work + 1;
      end
      else if RwIsPreviewServer(RwPaths[I], Line) then
      begin
        RwEnd(RwPids[I], RwPaths[I], 'a preview''s server');
        Ended := Ended + 1;
      end
      else if Name = 'plantoir-mcp.exe' then
      begin
        if Updating then
        begin
          // The same refusal as InitializeSetup's, for one started after it
          // looked (bundle-8 ruling 2): it may be publishing in a folder the
          // app has never opened, and it serves for days, so no wait helps.
          Log(Format('Running work: an assistant in another app is connected (pid %d); refusing', [RwPids[I]]));
          Result := RwRefusedForAssistant;
          Exit;
        end;
        // A hand-run install ends it at ssInstall, as it always has.
      end
      else if Name = 'llama-server.exe' then
      begin
        if Updating then
        begin
          RwEnd(RwPids[I], RwPaths[I], 'the assistant''s engine, left by the app that quit');
          Ended := Ended + 1;
        end;
        // A hand-run install ends it at ssInstall, as it always has.
      end
      else if (Name = 'plantoir.exe') and Updating and
              (not RwHasToken(Line, '--run-scheduled-deploy')) and
              (not RwIn(RwPlantoirAtStart, RwPids[I])) then
      begin
        // The teacher opened Plantoir again while this waited: installing
        // under them is what must not happen. Refused at once, and nothing
        // is reopened (one is open).
        Log(Format('Running work: Plantoir was opened again (pid %d); refusing', [RwPids[I]]));
        Result := RwRefusedReopened;
        Exit;
      end
      else if (Name = 'plantoir.exe') and (not Updating) and
              (not RwHasToken(Line, '--run-scheduled-deploy')) then
      begin
        // A hand-run install: Restart Manager offers to close the window
        // (CloseApplications=yes), after this function, as it always has.
        // A scheduled run has no window and is work: it falls through below.
      end
      else
      begin
        if not RwIn(RwLogged, RwPids[I]) then
        begin
          // The image and pid only, never the command line: a deploy's can
          // name an account, and this log is kept in the app's Logs folder.
          Log(Format('Running work: waiting for %s (pid %d)', [RwPaths[I], RwPids[I]]));
          SetArrayLength(RwLogged, GetArrayLength(RwLogged) + 1);
          RwLogged[GetArrayLength(RwLogged) - 1] := RwPids[I];
        end;
        Work := Work + 1;
      end;
    end;

    if (Work = 0) and (Ended = 0) then
    begin
      Log('Running work: nothing under ' + AppDir + ' is running; going ahead');
      Exit;
    end;
    if Work > 0 then
    begin
      if Silent then
      begin
        Elapsed := (RwGetTickCount - Started) div 1000;
        if Elapsed >= RwWaitSeconds then
        begin
          Log(Format('Running work: still running after %d s; refusing, nothing changed', [Elapsed]));
          Result := RwRefusedForWork;
          Exit;
        end;
      end
      else if RwJustEndedSomething then
      begin
        // What this run just ended may still be leaving (a preview's python):
        // look again rather than ask about a preview (the hand-run grace).
        if not RwGraceLogged then
        begin
          Log(Format('Running work: just ended a preview or the assistant''s engine; looking again for up to %d ms before asking', [RwGraceAfterEndingMs]));
          RwGraceLogged := True;
        end;
      end
      else
      begin
        if SuppressibleMsgBox(RwStillWorkingRetry, mbError, MB_RETRYCANCEL, IDCANCEL) <> IDRETRY then
        begin
          Log('Running work: the teacher chose Cancel; refusing, nothing changed');
          Result := RwRefusedForWork;
          Exit;
        end;
        Log('Running work: the teacher chose Retry; looking again');
        Continue;
      end;
    end;
    // Look again: what was ended must be seen gone, and work that started
    // while this waited (a scheduled deploy firing) is seen by the next look.
    Sleep(1000);
  end;
end;

// True when a Plantoir window is already open from {app} (any Plantoir.exe
// there that is not a scheduled run), so a refusal must not start another.
function RwPlantoirIsOpen: Boolean;
var
  I: Integer;
begin
  Result := False;
  if not RwLookUnder(ExpandConstant('{app}')) then Exit;
  for I := 0 to GetArrayLength(RwPids) - 1 do
    if (Lowercase(ExtractFileName(RwPaths[I])) = 'plantoir.exe') and
       (not RwHasToken(RwCommandLines[I], '--run-scheduled-deploy')) then
    begin
      Result := True;
      Exit;
    end;
end;

// After a refusal on the update path: [Run] never runs after one, so this is
// the only way back into Plantoir. Never when a Plantoir window is already
// open (the teacher came back; a second copy is the fault #700's review found).
//   - Refused for work (after a wait of up to ten minutes): reopened only when
//     the teacher's Install and Reopen asked for it (/RELAUNCH=1). An at-quit
//     install (no /RELAUNCH) stays closed: the teacher quit, and a window
//     appearing minutes later on a classroom screen is a surprise. Either way
//     the refusal marker (below) puts the line on the trail at the next launch.
//   - Refused for an outside assistant: within a second, like InitializeSetup's
//     refusal (ruling 12), so reopened whenever /RETURNTO names the app, with
//     the argument that refusal has always used.
//   - Refused because Plantoir was opened again: nothing to reopen.
procedure RunningWorkReopenAfterRefusal(const Refusal: String; Relaunch: Boolean; const ReturnTo: String);
var
  ResultCode: Integer;
begin
  if (ReturnTo = '') or (Refusal = RwRefusedReopened) then Exit;
  if RwPlantoirIsOpen then
  begin
    Log('Running work: Plantoir is already open; not starting another copy');
    Exit;
  end;
  if Refusal = RwRefusedForAssistant then
    Exec(ReturnTo, '--update-not-installed', '', SW_SHOW, ewNoWait, ResultCode)
  else if Relaunch then
    Exec(ReturnTo, RwNotInstalledForWorkArgument, '', SW_SHOW, ewNoWait, ResultCode);
end;

// ---- Markers in the state folder (AppUpdates) --------------------------------

// The app's state folder: /STATEDIR= when the app was started with a
// redirected one (--state-dir; AppUpdates.InstallerArguments passes it), else
// {localappdata}\Plantoir, where an installed copy keeps it.
function RunningWorkStateFolder: String;
begin
  Result := ExpandConstant('{param:STATEDIR|}');
  if Result = '' then Result := ExpandConstant('{localappdata}\Plantoir');
end;

// A refusal leaves a record (#700 review): an at-quit refusal reopens nothing
// and setup's own log is only written when the app asked for one, so the next
// launch reads this, writes "update held while work is under way" with the
// version that waited, and deletes it (AppUpdates.ConsumeNotInstalledMarker).
procedure RunningWorkWriteRefusalMarker(const Reason: String);
begin
  ForceDirectories(RunningWorkStateFolder);
  if SaveStringToFile(AddBackslash(RunningWorkStateFolder) + RwNotInstalledMarker,
                      '{#AppVersion}' + #13#10 + Reason + #13#10, False) then
    Log('Running work: wrote the refusal marker (' + Reason + ')')
  else
    Log('Running work: could not write the refusal marker');
end;

function RwReasonOf(const Refusal: String): String;
begin
  if Refusal = RwRefusedForAssistant then Result := 'assistant'
  else if Refusal = RwRefusedReopened then Result := 'reopened'
  else Result := 'work';
end;

function RwInstallingMarker: String;
begin
  Result := AddBackslash(RunningWorkStateFolder) + RwInstallingMarkerPrefix + IntToStr(RwGetCurrentProcessId);
end;

// At ssInstall, once the last look found nothing: a scheduled run of Plantoir
// that starts during the copy waits while this is there (ScheduledRun,
// AppUpdates.LiveInstaller), as it waits for a tools copy. It helps only if
// the Plantoir.exe that starts is whole: one started while [Files] is
// replacing it may fail to start at all, which nothing here can prevent.
procedure RunningWorkInstallingBegins;
begin
  ForceDirectories(RunningWorkStateFolder);
  SaveStringToFile(RwInstallingMarker, IntToStr(RwGetCurrentProcessId) + #13#10 + 'PlantoirSetup' + #13#10, False);
end;

// At ssPostInstall and in DeinitializeSetup, so a failed or cancelled install
// cannot leave it (a marker left by a killed setup is stale: its process is
// gone, and the reader deletes it).
procedure RunningWorkInstallingEnds;
begin
  DeleteFile(RwInstallingMarker);
end;

// A finished install: an older refusal no longer explains anything.
procedure RunningWorkInstalledCleanly;
begin
  DeleteFile(AddBackslash(RunningWorkStateFolder) + RwNotInstalledMarker);
end;

// The one call installer.iss makes, from PrepareToInstall and again at the
// start of CurStepChanged(ssInstall): '' to go ahead, or the refusal (which
// PrepareToInstall returns, for exit code 7, and ssInstall turns into Abort,
// exit code 3). Every refusal, silent or hand-run, leaves the marker.
function RunningWorkBeforeChangingFiles(Updating, Relaunch: Boolean): String;
begin
  Result := RunningWorkRefusal(ExpandConstant('{app}'), Updating, {#RunningWorkSilent});
  if Result <> '' then
  begin
    RunningWorkWriteRefusalMarker(RwReasonOf(Result));
    if Updating then
      RunningWorkReopenAfterRefusal(Result, Relaunch, ExpandConstant('{param:RETURNTO|}'));
  end;
end;