using System.Diagnostics;
using Plantoir.Core.Assist;
using Plantoir.Core.Scripting;

namespace Plantoir.Core.Models;

/// <summary>
/// Whether a working folder's copy of the app's tools (<c>.toolchain\</c>) is
/// ready to build from, and the ONE place that copy is started (#473).
///
/// <para><b>Why it exists.</b> The first launch after an update copies the new
/// bundled recipe into the working folder. That used to happen inside
/// <c>WorkspaceViewModel.Reload()</c>, on the UI thread, inside the
/// <c>MainWindow</c> constructor — so the teacher clicked Plantoir and saw no
/// window at all for 119.7 s and 93.7 s (two launches, 2026-10-07, Intel Core
/// i5-8365U, Windows 11 Pro 26200, read from startup.log). Now the window
/// appears at once, the copy runs on a background thread, and anything that
/// builds from the copied tools is disabled with a reason until it is done.
/// <c>documentation/12-windows-app.md</c> → "Getting a folder ready after an
/// update (#473)" has the reasoning and what was rejected.</para>
///
/// <para><b>One copy per folder per process.</b> Keyed on the folder path,
/// case-insensitively (the old <c>FoldersWithFreshToolchain</c> set's rule):
/// a second window on the same folder JOINS the copy already running rather
/// than starting another into the same files. A folder is marked ready only
/// after a pass in which nothing failed; the old set was filled BEFORE the
/// copy and every failure was swallowed, so a half-copied folder counted as
/// fresh for the rest of the run.</para>
///
/// <para><b>Other programs.</b> <c>plantoir-mcp</c> cannot see this process's
/// memory, so for the length of a copy a marker file,
/// <c>courses\.internal\activity\toolchain-copying.&lt;pid&gt;</c>, says so on
/// disk (<see cref="AnotherProgramIsGettingReady"/>). Not a <c>.lease</c>
/// name on purpose: lease readers, the update gate's sweep and reference
/// staging all read <c>*.lease</c>, and this is not a hold on any course.</para>
///
/// <para><b>Copies take turns (#477).</b> Two programs copying into one folder
/// at once is not harmless here: measured on an i5-8365U (Windows 11 Pro 26200,
/// 2026-10-15), two copies of 2,004 files started on the same tick failed 36
/// times across 5 runs with sharing violations (0x80070020) — the bytes ended
/// up right, but each copier would have reported a FAILED copy. So every copy
/// writes its marker FIRST and then waits while a live marker written before
/// its own (an earlier moment, or the same moment and a lower process id)
/// stands — <see cref="MustWaitFor"/>. How long it waits is the CALLER's
/// policy (<see cref="TakingTurns"/>): a window waits until the other copy is
/// done, with its banner up; the scheduled run gives up at its ten minutes and
/// stands down. The scheduled run copies too, through
/// <see cref="RefreshWorkspace"/>, before it builds.</para>
/// </summary>
public static class ToolchainReadiness
{
    /// <summary>Where a working folder stands.</summary>
    public enum State
    {
        /// <summary>Nothing has asked for a copy in this process (tests, captures, a non-working folder).</summary>
        NotStarted,
        /// <summary>A copy is running now.</summary>
        Copying,
        /// <summary>A copy finished with nothing failing.</summary>
        Ready,
        /// <summary>A copy finished with at least one file it could not copy or delete, or threw.</summary>
        Failed,
    }

    /// <summary>
    /// What the last copy of a folder did. <paramref name="FirstFailedPath"/>
    /// is the first file it could not copy or remove (from the working folder
    /// down), and <paramref name="Problem"/> why — that file's error, or the
    /// error that stopped the copy outright.
    /// </summary>
    /// <param name="GaveUpWaiting">The copy never started: another program's
    /// copy of the folder was still running when the caller's wait ran out
    /// (<see cref="TakingTurns.GiveUp"/>). Nothing was written.</param>
    /// <param name="WaitedForPid">The program whose copy this one waited for, if it waited.</param>
    public sealed record Status(State State, int FilesChanged, int FilesFailed, double Seconds, string? Problem,
                                string? FirstFailedPath = null, bool GaveUpWaiting = false, int? WaitedForPid = null);

    /// <summary>
    /// How a copy that finds an earlier live copy of the folder waits for it:
    /// <paramref name="Pause"/> between looks, and <paramref name="GiveUp"/>
    /// asked after each look. The window's (<see cref="WaitUntilDone"/>) never
    /// gives up; the scheduled run's gives up on its own ten-minute clock.
    /// </summary>
    public sealed record TakingTurns(Action<TimeSpan> Pause, Func<bool> GiveUp);

    /// <summary>A window's turn-taking: look every half second, never give up.</summary>
    public static TakingTurns WaitUntilDone => new(span => Pause(span), () => false);

    /// <summary>How often a waiting copy looks again.</summary>
    public static readonly TimeSpan LookAgainEvery = TimeSpan.FromMilliseconds(500);

    /// <summary>The pause between looks. A seam for tests; the app never changes it.</summary>
    internal static Action<TimeSpan> Pause { get; set; } = Thread.Sleep;

    /// <summary>
    /// Where startup.log lines go (the app sets it to <c>App.LogDiagnostic</c>):
    /// a copy that waited for another, or gave up waiting. Null: said nowhere.
    /// </summary>
    public static Action<string>? Diagnostic { get; set; }

    // ---- The words a teacher reads (rule 1: no machinery) ----------------

    /// <summary>The banner's title while a folder is being got ready.</summary>
    public const string GettingReadyTitle = "Getting this folder ready…";

    /// <summary>
    /// The banner's message while a folder is being got ready — also the
    /// tooltip on every button it disables, and what a refused Preview,
    /// Deploy or New Course says. "Deploy" because that is the button's caption.
    /// </summary>
    public const string GettingReadyMessage =
        "Plantoir is copying what it needs into this folder. Preview and Deploy will work in a moment.";

    /// <summary>The error banner, tooltip and refusal when the copy could not finish.</summary>
    public const string CouldNotGetReady =
        "Plantoir couldn't finish getting this folder ready. Choose Reload Courses from the File menu to try again.";

    /// <summary>
    /// How long a copy must still be running after the window appears before
    /// the banner opens: the ordinary launch, with nothing to copy, compares
    /// every file and takes about half a second — a banner for that would
    /// flash. The buttons are disabled for that half second regardless.
    /// </summary>
    public static readonly TimeSpan BannerDelay = TimeSpan.FromSeconds(1);

    /// <summary>The name a window's UI Automation readiness status takes for each state.</summary>
    public static string AutomationStatus(State state) => state switch
    {
        State.Copying => "copying",
        State.Failed => "failed",
        _ => "ready",
    };

    // ---- The registry ------------------------------------------------------

    private sealed class Entry
    {
        public State State;
        public Task Copy = Task.CompletedTask;
        public Status? Last;
        /// <summary>The copier has STARTED writing — not merely waiting its turn (#484 waits only for these).</summary>
        public bool Writing;
        /// <summary>A closing window waited for this copy (#484): the trail line says so.</summary>
        public bool WaitedForBeforeClosing;
        /// <summary>The scheduled deploy this copy was made for, if any: the trail line says so.</summary>
        public (string Course, int Section)? ForAScheduledDeploy;
    }

    private static readonly object Gate = new();
    private static readonly Dictionary<string, Entry> Folders = new(StringComparer.OrdinalIgnoreCase);

    /// <summary>
    /// The copy itself. A seam for tests (a slow copy, a failing one); the app
    /// never changes it.
    /// </summary>
    internal static Func<string, string, ToolchainMirror.CopyResult> Copier { get; set; } = ToolchainMirror.RefreshToolchain;

    /// <summary>
    /// Raised with the folder's path whenever its state changes — when a copy
    /// starts and when it ends. ON ANY THREAD: a subscriber marshals to its
    /// own. Static, so a window that subscribes must unsubscribe when it
    /// goes, or it is rooted for the life of the process.
    /// </summary>
    public static event Action<string>? Changed;

    /// <summary>Forget every folder and put the real copier back. Tests only.</summary>
    internal static void Reset()
    {
        lock (Gate)
        {
            Folders.Clear();
            _holdingBack = false;
        }
        Copier = ToolchainMirror.RefreshToolchain;
        Pause = Thread.Sleep;
    }

    private static string Key(string workspacePath)
    {
        try { return Path.GetFullPath(workspacePath).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar); }
        catch { return workspacePath; }
    }

    /// <summary>Where this folder stands in this process.</summary>
    public static State StateOf(string? workspacePath)
    {
        if (string.IsNullOrEmpty(workspacePath)) return State.NotStarted;
        lock (Gate) return Folders.TryGetValue(Key(workspacePath), out var entry) ? entry.State : State.NotStarted;
    }

    /// <summary>What the last finished copy of this folder did, or null.</summary>
    public static Status? LastCopyOf(string? workspacePath)
    {
        if (string.IsNullOrEmpty(workspacePath)) return null;
        lock (Gate) return Folders.TryGetValue(Key(workspacePath), out var entry) ? entry.Last : null;
    }

    /// <summary>
    /// Start the copy for this folder if none has run, and return the task
    /// that finishes when the folder is ready (or failed). Never blocks.
    ///
    /// <list type="bullet">
    /// <item>Ready: nothing to do, a finished task.</item>
    /// <item>Copying: the copy ALREADY RUNNING is returned — a second window
    /// on the folder joins it.</item>
    /// <item>Failed: tried again only when <paramref name="retryAFailedCopy"/>
    /// — File → Reload Courses, or a window newly pointed at the folder.
    /// The sidebar's many routine reloads (a rename, an archive, a restore)
    /// do not, or a folder that cannot be written would be hammered by a
    /// two-minute copy after every one of them.</item>
    /// <item>Not a working folder (no <c>preview.ps1</c>): nothing, and it
    /// stays NotStarted — the same rule the copy itself had.</item>
    /// </list>
    /// </summary>
    /// <param name="turns">How to wait for another program's copy of the
    /// folder; null is a window's (<see cref="WaitUntilDone"/>).</param>
    /// <param name="forAScheduledDeploy">The scheduled deploy this copy is made
    /// for: its trail line names the course and section and says so.</param>
    public static Task Ensure(string workspacePath, string bundledRoot, bool retryAFailedCopy = false,
                              TakingTurns? turns = null, (string Course, int Section)? forAScheduledDeploy = null)
    {
        if (string.IsNullOrEmpty(workspacePath) || !ToolchainMirror.IsAWorkingFolder(workspacePath))
            return Task.CompletedTask;
        string key = Key(workspacePath);
        // The mac's own check (WorkspaceModel.shouldMirrorToolchain): a folder
        // counted ready whose recipe has since gone from disk — deleted by
        // hand, a sync client, a restore — is copied again. One File.Exists,
        // so cheap enough for every Reload.
        bool recipeStillThere = File.Exists(Path.Combine(workspacePath, ".toolchain", ToolchainMirror.RecipeRootFiles[0]));
        Task copy;
        lock (Gate)
        {
            if (!Folders.TryGetValue(key, out var entry)) Folders[key] = entry = new Entry();
            switch (entry.State)
            {
                case State.Ready when recipeStillThere:
                case State.Copying:
                    return entry.Copy;
                case State.Failed when !retryAFailedCopy:
                    return entry.Copy;
            }
            entry.State = State.Copying;
            entry.Writing = false;
            entry.WaitedForBeforeClosing = false;
            entry.ForAScheduledDeploy = forAScheduledDeploy;
            var copier = Copier;
            var waiting = turns ?? WaitUntilDone;
            // Made INSIDE the lock, so a second caller that arrives a moment
            // later finds Copying and this very task, never a gap between them
            // — but STARTED only after "started" has been said, so no window
            // can hear "finished" first (a copy with nothing to do ends in
            // milliseconds).
            entry.Copy = copy = new Task(() => CopyNow(workspacePath, key, bundledRoot, copier, waiting));
        }
        RaiseChanged(workspacePath);
        copy.Start(TaskScheduler.Default);
        return copy;
    }

    private static void CopyNow(string workspacePath, string key, string bundledRoot,
                                Func<string, string, ToolchainMirror.CopyResult> copier, TakingTurns turns)
    {
        var clock = Stopwatch.StartNew();
        var (marker, myMoment) = WriteMarker(workspacePath);

        // Take, then look (#477): only a live copy whose marker was written
        // BEFORE this one's holds it back, so two copies never wait for each
        // other. A closing window holds back a copy that has not started
        // writing yet (#484), so its wait cannot miss one that starts later:
        // the check and the "writing" mark are made under the same lock the
        // close takes its snapshot under.
        int? waitedFor = null;
        bool gaveUp = false;
        while (true)
        {
            int? earlier = myMoment is null ? null : EarlierCopierThan(workspacePath, myMoment);
            if (earlier is null)
            {
                bool go = false;
                lock (Gate)
                {
                    if (!_holdingBack)
                    {
                        if (Folders.TryGetValue(key, out var started)) started.Writing = true;
                        go = true;
                    }
                }
                if (go) break;
            }
            else waitedFor ??= earlier;
            if (turns.GiveUp()) { gaveUp = true; break; }
            turns.Pause(LookAgainEvery);
        }

        if (gaveUp)
        {
            if (marker is not null) { try { File.Delete(marker); } catch { } }
            clock.Stop();
            Diagnostic?.Invoke($"tools copy for '{workspacePath}' did not start: another copy (process {waitedFor}) " +
                               $"was still running after {clock.Elapsed.TotalSeconds:0.0} s of waiting");
            var notStarted = new Status(State.Failed, 0, 0, clock.Elapsed.TotalSeconds,
                                        "another copy of the folder was still running", null,
                                        GaveUpWaiting: true, WaitedForPid: waitedFor);
            lock (Gate)
            {
                if (Folders.TryGetValue(key, out var entry))
                {
                    entry.State = State.Failed;
                    entry.Last = notStarted;
                    entry.Writing = false;
                }
            }
            RaiseChanged(workspacePath);
            return;
        }
        if (waitedFor is not null)
            Diagnostic?.Invoke($"tools copy for '{workspacePath}' waited {clock.Elapsed.TotalSeconds:0.0} s " +
                               $"for another copy (process {waitedFor}) to finish first");

        ToolchainMirror.CopyResult result;
        string? problem = null;
        try
        {
            result = copier(workspacePath, bundledRoot);
        }
        catch (Exception error)
        {
            result = new ToolchainMirror.CopyResult(0, 1);
            problem = error.Message;
        }
        finally
        {
            if (marker is not null) { try { File.Delete(marker); } catch { } }
        }
        clock.Stop();

        bool ready = result.Failed == 0;
        var status = new Status(ready ? State.Ready : State.Failed, result.Changed, result.Failed,
                                clock.Elapsed.TotalSeconds, problem ?? result.FirstProblem,
                                problem is null ? result.FirstFailedPath : null, WaitedForPid: waitedFor);
        bool waitedBeforeClosing = false;
        (string Course, int Section)? forADeploy = null;
        lock (Gate)
        {
            if (Folders.TryGetValue(key, out var entry))
            {
                entry.State = status.State;
                entry.Last = status;
                entry.Writing = false;
                waitedBeforeClosing = entry.WaitedForBeforeClosing;
                forADeploy = entry.ForAScheduledDeploy;
            }
        }
        // Only a copy that DID something, or failed, is worth a line: every
        // launch compares every file, and a line for each "nothing to do"
        // would bury the one that explains a slow first launch.
        if (result.Changed > 0 || result.Failed > 0)
        {
            try
            {
                string line = TrailLine(workspacePath, status, forADeploy is not null, waitedBeforeClosing);
                if (forADeploy is { } deploy)
                    ActivityTrail.Note(ActivityTrail.Event.WorkingFolderToolsCopied, line, deploy.Course, deploy.Section);
                else
                    ActivityTrail.Note(ActivityTrail.Event.WorkingFolderToolsCopied, line);
            }
            catch { }
        }
        RaiseChanged(workspacePath);
    }

    /// <summary>
    /// The trail's line (<c>working folder tools copied</c>): what a teacher
    /// would recognise, with the counts and the seconds a slow or broken first
    /// launch is diagnosed from. The path is redacted on the way in.
    /// </summary>
    /// <param name="forAScheduledDeploy">The copy a scheduled run made before
    /// it built (#477): said, and a failure says the deploy stood down rather
    /// than pointing at a menu nobody is there to open.</param>
    /// <param name="waitedBeforeClosing">A closing window waited for this copy (#484).</param>
    public static string TrailLine(string workspacePath, Status status, bool forAScheduledDeploy = false,
                                   bool waitedBeforeClosing = false)
    {
        string files = status.FilesChanged == 1 ? "1 file" : $"{status.FilesChanged} files";
        string seconds = status.Seconds.ToString("0.0", System.Globalization.CultureInfo.InvariantCulture);
        string what = forAScheduledDeploy ? "the working folder ready for a scheduled deploy" : "the working folder ready";
        string closing = waitedBeforeClosing ? ", and Plantoir waited for it before closing" : "";
        if (status.State == State.Ready)
            return $"got {what} — {files} brought up to date in {seconds} s{closing} — {workspacePath}";
        string failed = status.FilesFailed == 1 ? "1 file" : $"{status.FilesFailed} files";
        string first = (status.FirstFailedPath, status.Problem) switch
        {
            ({ Length: > 0 } path, { Length: > 0 } why) => $" (first: {path}, {why})",
            ({ Length: > 0 } path, _) => $" (first: {path})",
            (_, { Length: > 0 } why) => $" ({why})",
            _ => "",
        };
        string after = forAScheduledDeploy ? "the scheduled deploy stood down" : "Preview and Deploy wait for Reload Courses";
        return $"could not finish getting {what} — {failed} could not be copied or removed{first}, " +
               $"{files} brought up to date in {seconds} s{closing}; {after} — {workspacePath}";
    }

    private static void RaiseChanged(string workspacePath)
    {
        var handlers = Changed;
        if (handlers is null) return;
        foreach (Action<string> handler in handlers.GetInvocationList())
        {
            try { handler(workspacePath); } catch { /* one window's failure must not stop another's */ }
        }
    }

    // ---- What a refused action says ---------------------------------------

    /// <summary>
    /// The sentence that refuses Preview, Deploy or a new course in this
    /// folder right now, or null when nothing stands in the way. NotStarted is
    /// never refused: tests, the marketing captures and the picker's own
    /// set-up drive folders no Reload has ensured.
    /// </summary>
    public static string? Refusal(string? workspacePath) => RefusalFor(StateOf(workspacePath));

    /// <summary>The refusal for a state. PURE.</summary>
    public static string? RefusalFor(State state) => state switch
    {
        State.Copying => GettingReadyMessage,
        State.Failed => CouldNotGetReady,
        _ => null,
    };

    /// <summary>Whether actions that build from the tools may be pressed. PURE.</summary>
    public static bool ActionsEnabled(State state) => RefusalFor(state) is null;

    /// <summary>What the window's banner shows for a state. PURE.</summary>
    /// <param name="pastTheDelay">Whether <see cref="BannerDelay"/> has gone by
    /// since the window appeared — a copy shorter than that shows no banner.</param>
    public static Banner BannerFor(State state, bool pastTheDelay) => state switch
    {
        State.Copying when pastTheDelay => new Banner(true, false, GettingReadyTitle, GettingReadyMessage),
        State.Failed => new Banner(true, true, null, CouldNotGetReady),
        _ => new Banner(false, false, null, null),
    };

    /// <summary>The banner: open or not, an error or not, and its words.</summary>
    public sealed record Banner(bool IsOpen, bool IsError, string? Title, string? Message);

    // ---- The marker other programs read ------------------------------------

    /// <summary>The marker file's name prefix.</summary>
    public const string MarkerPrefix = "toolchain-copying.";

    private static string ActivityDirectory(string workspacePath) =>
        Path.Combine(Workspace.CoursesDirectory(workspacePath), ".internal", "activity");

    /// <summary>Where a process's marker for this folder lives.</summary>
    public static string MarkerPath(string workspacePath, int pid) =>
        Path.Combine(ActivityDirectory(workspacePath), MarkerPrefix + pid);

    /// <summary>
    /// Written for the length of a copy, deleted after it whatever happened.
    /// Only when <c>courses\</c> exists: creating it here would turn a folder
    /// with no courses yet into one with an empty list. Best-effort.
    /// </summary>
    /// <returns>The marker's path and the moment written on its line 3 — the
    /// moment this copy takes its turn by — or nulls when none was written.</returns>
    private static (string? Path, string? Moment) WriteMarker(string workspacePath)
    {
        try
        {
            if (!Directory.Exists(Workspace.CoursesDirectory(workspacePath))) return (null, null);
            string path = MarkerPath(workspacePath, Environment.ProcessId);
            Directory.CreateDirectory(ActivityDirectory(workspacePath));
            SweepDeadMarkers(workspacePath);
            // Written under another name and MOVED into place, so no reader —
            // another Plantoir's sweep included — ever sees the marker empty.
            string writing = Path.Combine(ActivityDirectory(workspacePath), $"writing-{MarkerPrefix}{Environment.ProcessId}.tmp");
            string body = WorkLease.LeaseBody(withStart: true);
            File.WriteAllText(writing, body);
            File.Move(writing, path, overwrite: true);
            return (path, MomentIn(body));
        }
        catch { return (null, null); }
    }

    /// <summary>A marker body's line 3, the moment it was written (UTC, "O"), or null.</summary>
    private static string? MomentIn(string body)
    {
        string[] lines = body.Replace("\r", "").Split('\n');
        return lines.Length > 2 && lines[2].Trim() is { Length: > 0 } moment ? moment : null;
    }

    /// <summary>
    /// Removes markers left by a Plantoir that was killed mid-copy. They are
    /// already ignored by every reader; this only keeps them from piling up.
    /// Never this process's own, never a live one. Best-effort.
    /// </summary>
    private static void SweepDeadMarkers(string workspacePath)
    {
        foreach (var (marker, pid, alive, parsed, _) in Markers(workspacePath))
        {
            // Never one whose body did not read: a marker caught mid-write by
            // a writer that does not move it into place would be empty for a
            // moment while its owner is LIVE, and deleting it then would hide
            // that copy from plantoir-mcp. Nothing released writes it that way
            // (this app writes to a temporary name and moves it); the rule is
            // kept so a future writer cannot be hidden either.
            if (!parsed || alive || pid == Environment.ProcessId) continue;
            try { File.Delete(marker); } catch { }
        }
    }

    /// <summary>Every marker in the folder, with its owner and whether that owner lives.</summary>
    private static List<(string Marker, int Pid, bool Alive, bool Parsed, string? Moment)> Markers(string workspacePath)
    {
        var found = new List<(string, int, bool, bool, string?)>();
        IEnumerable<string> markers;
        try { markers = Directory.EnumerateFiles(ActivityDirectory(workspacePath), MarkerPrefix + "*").ToList(); }
        catch { return found; }
        foreach (string marker in markers)
        {
            string suffix = Path.GetFileName(marker)[MarkerPrefix.Length..];
            if (!int.TryParse(suffix, out int pid)) continue;
            string body;
            try { body = File.ReadAllText(marker); }
            catch { continue; }
            var (name, start) = WorkLease.ReadBody(body);
            found.Add((marker, pid, name is not null && WorkLease.OwnerIsAlive(pid, name, start, "toolchain-copying"),
                       name is not null, MomentIn(body)));
        }
        return found;
    }

    /// <summary>
    /// Whether a LIVE program is copying the tools into this folder right now,
    /// read from the markers on disk — what <c>plantoir-mcp</c> asks before it
    /// runs a launcher. A marker whose process is gone, or whose id now
    /// belongs to another process (a different start time on line 4), counts
    /// for nothing: a killed Plantoir must not lock the assistant out.
    /// </summary>
    /// <param name="exceptThisProcess">Leave this process's own marker out —
    /// what the scheduled run asks, so it never waits for itself.</param>
    public static bool AnotherProgramIsGettingReady(string workspacePath, bool exceptThisProcess = false) =>
        LiveCopiers(workspacePath, exceptThisProcess).Count > 0;

    /// <summary>The process ids of the live programs copying into this folder now.</summary>
    public static IReadOnlyList<int> LiveCopiers(string workspacePath, bool exceptThisProcess = false) =>
        Markers(workspacePath)
            .Where(marker => marker.Alive && !(exceptThisProcess && marker.Pid == Environment.ProcessId))
            .Select(marker => marker.Pid)
            .ToList();

    /// <summary>
    /// Whether a copy whose marker says <paramref name="myMoment"/> must wait
    /// for another live copy whose marker says <paramref name="otherMoment"/>
    /// (#477): the other was written first — an earlier moment, or the same
    /// moment and a lower process id (<c>WorkLease.TakenBefore</c>'s order).
    /// PURE. A moment that is not the one 28-character shape both apps write
    /// counts as NOT earlier (the plan review's M2): <c>TakenBefore</c>
    /// answers "earlier" there, which is right for a lease nobody waits on in
    /// turn, but two copies facing one unreadable marker would both wait for
    /// it to the end. Never waits for itself.
    /// </summary>
    public static bool MustWaitFor(string myMoment, int myPid, string? otherMoment, int otherPid)
    {
        if (otherPid == myPid) return false;
        if (otherMoment is null || !WorkLease.IsMomentShape(otherMoment) || !WorkLease.IsMomentShape(myMoment)) return false;
        int order = string.CompareOrdinal(otherMoment, myMoment);
        return order < 0 || (order == 0 && otherPid < myPid);
    }

    /// <summary>A live copy of this folder that went before this process's, or null.</summary>
    private static int? EarlierCopierThan(string workspacePath, string myMoment)
    {
        foreach (var marker in Markers(workspacePath))
            if (marker.Alive && MustWaitFor(myMoment, Environment.ProcessId, marker.Moment, marker.Pid))
                return marker.Pid;
        return null;
    }

    // ---- The refresh: the window's and the scheduled run's (#477) ----------

    /// <summary>
    /// Bring a working folder's launchers and tools up to date from the recipe
    /// at <paramref name="bundledRoot"/>: the launchers that already exist,
    /// synchronously, then the copy through <see cref="Ensure"/>. What the
    /// window does on every Reload, and — since #477 — what the scheduled run
    /// does before it writes its wrapper, so a 06:30 deploy after an update
    /// builds with the new tools even when nobody has opened the app since.
    /// <para><b>Does nothing without a recipe there</b> (its first root file,
    /// the Dockerfile): mirroring from a missing folder would DELETE the
    /// working folder's tools, because the mirror removes what its source
    /// lacks.</para>
    /// </summary>
    public static Task RefreshWorkspace(string workspacePath, string bundledRoot, bool retryAFailedCopy = false,
                                        TakingTurns? turns = null, (string Course, int Section)? forAScheduledDeploy = null)
    {
        if (string.IsNullOrEmpty(bundledRoot) || !File.Exists(Path.Combine(bundledRoot, ToolchainMirror.RecipeRootFiles[0])))
        {
            Diagnostic?.Invoke($"tools copy for '{workspacePath}' skipped: no recipe at '{bundledRoot}'");
            return Task.CompletedTask;
        }
        ToolchainMirror.RefreshLaunchers(workspacePath, bundledRoot);
        return Ensure(workspacePath, bundledRoot, retryAFailedCopy, turns, forAScheduledDeploy);
    }

    // ---- Closing while a copy writes (#484) --------------------------------

    /// <summary>Set by a closing window: copies still waiting their turn do not start.</summary>
    private static bool _holdingBack;
}
