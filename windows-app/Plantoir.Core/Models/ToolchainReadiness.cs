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
    public sealed record Status(State State, int FilesChanged, int FilesFailed, double Seconds, string? Problem,
                                string? FirstFailedPath = null);

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
        lock (Gate) Folders.Clear();
        Copier = ToolchainMirror.RefreshToolchain;
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
    public static Task Ensure(string workspacePath, string bundledRoot, bool retryAFailedCopy = false)
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
            var copier = Copier;
            // Made INSIDE the lock, so a second caller that arrives a moment
            // later finds Copying and this very task, never a gap between them
            // — but STARTED only after "started" has been said, so no window
            // can hear "finished" first (a copy with nothing to do ends in
            // milliseconds).
            entry.Copy = copy = new Task(() => CopyNow(workspacePath, key, bundledRoot, copier));
        }
        RaiseChanged(workspacePath);
        copy.Start(TaskScheduler.Default);
        return copy;
    }

    private static void CopyNow(string workspacePath, string key, string bundledRoot,
                                Func<string, string, ToolchainMirror.CopyResult> copier)
    {
        var clock = Stopwatch.StartNew();
        string? marker = WriteMarker(workspacePath);
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
                                problem is null ? result.FirstFailedPath : null);
        lock (Gate)
        {
            if (Folders.TryGetValue(key, out var entry))
            {
                entry.State = status.State;
                entry.Last = status;
            }
        }
        // Only a copy that DID something, or failed, is worth a line: every
        // launch compares every file, and a line for each "nothing to do"
        // would bury the one that explains a slow first launch.
        if (result.Changed > 0 || result.Failed > 0)
        {
            try { ActivityTrail.Note(ActivityTrail.Event.WorkingFolderToolsCopied, TrailLine(workspacePath, status)); }
            catch { }
        }
        RaiseChanged(workspacePath);
    }

    /// <summary>
    /// The trail's line (<c>working folder tools copied</c>): what a teacher
    /// would recognise, with the counts and the seconds a slow or broken first
    /// launch is diagnosed from. The path is redacted on the way in.
    /// </summary>
    public static string TrailLine(string workspacePath, Status status)
    {
        string files = status.FilesChanged == 1 ? "1 file" : $"{status.FilesChanged} files";
        string seconds = status.Seconds.ToString("0.0", System.Globalization.CultureInfo.InvariantCulture);
        if (status.State == State.Ready)
            return $"got the working folder ready — {files} brought up to date in {seconds} s — {workspacePath}";
        string failed = status.FilesFailed == 1 ? "1 file" : $"{status.FilesFailed} files";
        string first = (status.FirstFailedPath, status.Problem) switch
        {
            ({ Length: > 0 } path, { Length: > 0 } why) => $" (first: {path}, {why})",
            ({ Length: > 0 } path, _) => $" (first: {path})",
            (_, { Length: > 0 } why) => $" ({why})",
            _ => "",
        };
        return $"could not finish getting the working folder ready — {failed} could not be copied or removed{first}, " +
               $"{files} brought up to date in {seconds} s; Preview and Deploy wait for Reload Courses — {workspacePath}";
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
    private static string? WriteMarker(string workspacePath)
    {
        try
        {
            if (!Directory.Exists(Workspace.CoursesDirectory(workspacePath))) return null;
            string path = MarkerPath(workspacePath, Environment.ProcessId);
            Directory.CreateDirectory(ActivityDirectory(workspacePath));
            SweepDeadMarkers(workspacePath);
            File.WriteAllText(path, WorkLease.LeaseBody(withStart: true));
            return path;
        }
        catch { return null; }
    }

    /// <summary>
    /// Removes markers left by a Plantoir that was killed mid-copy. They are
    /// already ignored by every reader; this only keeps them from piling up.
    /// Never this process's own, never a live one. Best-effort.
    /// </summary>
    private static void SweepDeadMarkers(string workspacePath)
    {
        foreach (var (marker, pid, alive) in Markers(workspacePath))
        {
            if (alive || pid == Environment.ProcessId) continue;
            try { File.Delete(marker); } catch { }
        }
    }

    /// <summary>Every marker in the folder, with its owner and whether that owner lives.</summary>
    private static List<(string Marker, int Pid, bool Alive)> Markers(string workspacePath)
    {
        var found = new List<(string, int, bool)>();
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
            found.Add((marker, pid, name is not null && WorkLease.OwnerIsAlive(pid, name, start, "toolchain-copying")));
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
    public static bool AnotherProgramIsGettingReady(string workspacePath) =>
        Markers(workspacePath).Any(marker => marker.Alive);
}
