using System.Diagnostics;
using Plantoir.Core.Models;

namespace Plantoir.Core.Assist;

/// <summary>
/// A file saying "this course is being worked on right now, by me", written by
/// whichever process is doing the work and read by the other.
///
/// Plantoir and the MCP server are separate processes with separate memory.
/// Preview leases and publish records live inside the app; an assist session
/// lives inside the server. Neither can see the other, and both build into
/// the section's build folder (see <c>BuildOutputLocation</c>; NOT <c>.merged_output</c>, which Windows stopped writing to in row 290) — which the build CLEARS before
/// writing it. So the loser of a race serves a half-written site, or publishes
/// files the other just deleted.
///
/// The protocol is deliberately the simplest thing that survives a crash: one
/// file per piece of work, named for the course, the kind of work and the
/// process id that owns it, carrying that process's name. A reader treats a
/// lease whose process is gone as gone too, so a killed session or a crashed
/// app cannot leave a course locked — no cleanup pass, no timeout to tune, no
/// lock file to get stuck.
///
/// **This is the shared registry from research/ai-assist/HISTORY.md part 3 (the MCP proposal), phase 2**, and it is
/// deliberately format-first rather than API-first so the mac side can adopt
/// the same files rather than the same code.
/// </summary>
public static class WorkLease
{
    /// <summary>An assistant is holding the course through the MCP server.</summary>
    public const string Assisting = "assist";

    /// <summary>The app is building or serving a preview.</summary>
    public const string Previewing = "preview";

    /// <summary>The app is building and deploying.</summary>
    public const string Publishing = "publish";

    /// <summary>
    /// Somebody is running a BUILD of this course right now — the narrow thing
    /// that genuinely cannot happen twice at once.
    ///
    /// The other three kinds say what somebody is DOING; this one says what
    /// they are doing that clashes. Both a build and a rebuild write into
    /// the section's build folder (see <c>BuildOutputLocation</c>; NOT <c>.merged_output</c>, which Windows stopped writing to in row 290), which the build clears first,
    /// so two at once lose each other's work. Nothing else conflicts: editing
    /// Markdown does not touch that folder, and a preview SERVER only reads it.
    ///
    /// It is held for the build and released the moment the build is done —
    /// not for the life of the session or the life of the preview server.
    /// Holding it that long is what made a teacher choose between watching
    /// their preview and talking to the assistant about it, which is exactly
    /// the pairing the assistant exists for.
    /// </summary>
    public const string Building = "build";

    /// <summary>
    /// A copy of the course is being zipped — the assistant's backup, made
    /// inside <c>plantoir-mcp</c> (#360, mac #351). The course is BUSY for
    /// every builder while it lasts, as on the mac: a build or a deploy started
    /// meanwhile would change the files under the zip.
    /// </summary>
    public const string Copying = "copy";

    private static string Directory(string workspacePath) =>
        Path.Combine(Workspace.CoursesDirectory(workspacePath), ".internal", "activity");

    /// <summary>
    /// When and by whom a lease was taken: line 3 of the file (UTC, .NET's
    /// round-trip "O" form) and this process's id. What the take-then-check
    /// rule compares (<c>shared-rules.json</c> → <c>workLeases.declining.takeThenCheck</c>).
    /// </summary>
    public sealed record Claim(string Moment, int Pid);

    /// <summary>A lease this process holds. Disposing releases it.</summary>
    public sealed class Held : IDisposable
    {
        private readonly string _path;
        private bool _done;

        internal Held(string path, Claim claim)
        {
            _path = path;
            Claim = claim;
        }

        /// <summary>This lease's moment and owner — the claim a build compares against.</summary>
        public Claim Claim { get; }

        public void Dispose()
        {
            if (_done) return;
            _done = true;
            try { File.Delete(_path); } catch { }
        }
    }

    /// <summary>
    /// Claim a course for this process. Disposing releases it; so does the
    /// process ending, since a lease whose owner is gone is ignored.
    /// </summary>
    public static Held Take(string workspacePath, string courseCode, string kind)
    {
        string path = Path.Combine(Directory(workspacePath),
            $"{courseCode.ToUpperInvariant()}.{kind}.{Environment.ProcessId}.lease");
        string moment = DateTime.UtcNow.ToString("O");
        try
        {
            System.IO.Directory.CreateDirectory(Directory(workspacePath));
            File.WriteAllText(path,
                $"{Environment.ProcessId}\n{Process.GetCurrentProcess().ProcessName}\n{moment}\n");
        }
        catch { /* an unwritable folder must not stop the work itself */ }
        return new Held(path, new Claim(moment, Environment.ProcessId));
    }

    /// <summary>
    /// What OTHER processes are currently doing to this course — "assist",
    /// "preview", "publish", "build" — with duplicates removed. Empty means free.
    ///
    /// Our own leases are excluded: a process is never in its own way, and
    /// including them would have the app refuse its own publish.
    /// </summary>
    public static IReadOnlyList<string> HeldBy(string workspacePath, string courseCode) =>
        Others(workspacePath)
            .Where(other => string.Equals(other.Course, courseCode, StringComparison.OrdinalIgnoreCase))
            .Where(other => other.Pid != Environment.ProcessId && other.Alive && other.HasName)
            .Select(other => other.Kind)
            .Distinct()
            .ToList();

    /// <summary>
    /// Whether ANOTHER live program holds a build or publish lease on any
    /// course in this working folder — the quit path's first question (#231).
    /// </summary>
    public static bool AnotherProgramIsWorkingIn(string workspacePath) =>
        Others(workspacePath).Any(other => other.Pid != Environment.ProcessId && other.Alive && other.HasName
                                           && other.Kind is Building or Publishing);

    /// <summary>
    /// The courses ANOTHER live program (a <c>plantoir-mcp</c> session, a
    /// second Plantoir) holds an <c>assist</c> lease on — so a backup delete
    /// keeps what that conversation may restore from (#283).
    /// </summary>
    public static IEnumerable<string> CoursesAssistedByAnotherProgram(string workspacePath) =>
        Others(workspacePath)
            .Where(other => other.Pid != Environment.ProcessId && other.Alive && other.HasName && other.Kind == Assisting)
            .Select(other => other.Course)
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToList();

    /// <summary>
    /// Every live lease in this working folder held by ANOTHER process, of
    /// any kind — what the update gate (#337) and the UI-test runner's busy
    /// check (#155) read.
    /// </summary>
    public static IReadOnlyList<Other> LiveLeasesOfOthers(string workspacePath) =>
        Others(workspacePath)
            .Where(other => other.Pid != Environment.ProcessId && other.Alive && other.HasName)
            .ToList();

    public static bool IsHeld(string workspacePath, string courseCode, string kind) =>
        HeldBy(workspacePath, courseCode).Contains(kind);

    // ---- Who stands in whose way (#156 / #289) ----------------------------

    /// <summary>Who is asking to build.</summary>
    public enum Asker
    {
        /// <summary>
        /// Preview or Deploy in the window, or an assistant's rebuild or deploy:
        /// declined by another program's build, publish OR preview. Stricter than
        /// this app's old "only build blocks": every build first ends that
        /// section's serving preview, so an outside rebuild took down the page
        /// the teacher was reading (#156's director ruling, adopted by #289).
        /// </summary>
        ABuild,

        /// <summary>
        /// A publish set for later: waits for another program's build or
        /// publish, never for a preview — a preview left open overnight must
        /// not cost the morning's publish.
        /// </summary>
        AScheduledPublish,

        /// <summary>
        /// An OUTSIDE assistant's deploy (#436, mac #433's
        /// <c>Asker.anOutsideDeploy</c>): goes ahead while a preview is only
        /// being served — Russell: "if the teacher asks Claude or Codex to
        /// deploy, it should be allowed to go ahead, even if a preview is
        /// running" — and is declined by a build, a publish or a copy. A
        /// preview still BUILDING holds a build lease beside its preview one,
        /// so it declines this too.
        /// </summary>
        AnOutsideDeploy,
    }

    /// <summary>What an outside assistant meets on a course (<c>workLeases.declining.outsideChanges</c>).</summary>
    public enum OutsideMeeting
    {
        /// <summary>Nothing that matters: no lease, or only assist/import ones.</summary>
        Nothing,
        /// <summary>A preview that has finished building and is only being SERVED: holds nothing back.</summary>
        AServedPreview,
        /// <summary>A site of the course is being BUILT (a build or publish lease): holds everything back.</summary>
        ABuild,
    }

    /// <summary>
    /// What an outside assistant meets, from the KINDS other programs hold on
    /// the course. PURE, and order-free on purpose: a preview still building
    /// holds <c>build</c> beside <c>preview</c>, and <c>build</c> must win
    /// whatever order the lease files were read in — otherwise a change is let
    /// through mid-build (the trap #433 names).
    /// </summary>
    public static OutsideMeeting OutsideMeets(IEnumerable<string> kinds)
    {
        var held = kinds.ToHashSet(StringComparer.Ordinal);
        if (held.Contains(Building) || held.Contains(Publishing)) return OutsideMeeting.ABuild;
        return held.Contains(Previewing) ? OutsideMeeting.AServedPreview : OutsideMeeting.Nothing;
    }

    /// <summary>
    /// A window's preview work lease, given up the moment a preview that had
    /// been SERVING ends (bundle A fix round, ruling 2): otherwise the lease
    /// outlived the preview — after another program's deploy closed it, an
    /// outside assistant went on being told a preview was open ("still shows
    /// the pages as they were", "deploying closed it") about one that was not.
    /// Returns what the caller should keep: null once released. Said on the
    /// trail when the end was a closing for a deploy.
    /// </summary>
    public static Held? LetGoWhenAServingPreviewEnds(Held? previewWork, bool isRunning, bool hasBeenServing,
                                                     bool closedForADeploy, string course, int section)
    {
        if (previewWork is null || isRunning || !hasBeenServing) return previewWork;
        previewWork.Dispose();
        if (closedForADeploy)
            Plantoir.Core.Scripting.ActivityTrail.Note(Plantoir.Core.Scripting.ActivityTrail.Event.PreviewClosedForADeploy,
                "the window let go of the closed preview's hold on the course, so nothing is told a preview is still open",
                course, section);
        return null;
    }

    /// <summary>The same, read off disk for this working folder (other live programs only).</summary>
    public static OutsideMeeting WhatAnOutsideChangeMeets(string workspacePath, string courseCode) =>
        OutsideMeets(HeldBy(workspacePath, courseCode));

    /// <summary>One lease file as a reader sees it.</summary>
    /// <param name="Moment">Line 3, or null when there is none.</param>
    /// <param name="Alive">What the liveness rule answered for its owner.</param>
    /// <param name="HasName">Whether line 2 names the owner. A build, preview
    /// or publish lease without one is treated as gone.</param>
    public sealed record Other(string Course, string Kind, int Pid, string? Moment, bool Alive, bool HasName = true);

    /// <summary>
    /// The first other program's lease that stands in the way of this
    /// asker's build, or null when nothing does. PURE: the contract's
    /// <c>workLeases.declining.cases</c> run straight through it.
    /// </summary>
    /// <param name="claim">
    /// Null for a look made BEFORE this program has taken its own build lease
    /// (every blocking lease counts). Otherwise this program's BUILD lease —
    /// never the earliest of its leases (the contract's last case shows the two
    /// builds that would allow) — and only leases taken before it count.
    /// </param>
    public static Other? FirstInTheWay(Asker asker, string courseCode, int myPid, Claim? claim, IEnumerable<Other> others)
    {
        string[] blocking = asker is Asker.AScheduledPublish or Asker.AnOutsideDeploy
            ? [Building, Publishing, Copying]
            : [Building, Publishing, Previewing, Copying];

        return others
            .Where(other => string.Equals(other.Course, courseCode, StringComparison.OrdinalIgnoreCase))
            .Where(other => other.Pid != myPid && other.Alive && other.HasName)
            .Where(other => blocking.Contains(other.Kind))
            .FirstOrDefault(other => claim is null || TakenBefore(other, claim));
    }

    /// <summary>
    /// Whether another lease was taken before this claim: an earlier moment,
    /// or the same moment and a lower process id. The moments are compared as
    /// TEXT, which is exact only for the one 28-character shape both apps
    /// write; anything else counts as earlier, because when the order cannot
    /// be told the other program is left alone.
    /// </summary>
    internal static bool TakenBefore(Other other, Claim claim)
    {
        if (other.Moment is not { } moment || !IsMomentShape(moment) || !IsMomentShape(claim.Moment))
            return true;
        int order = string.CompareOrdinal(moment, claim.Moment);
        return order < 0 || (order == 0 && other.Pid < claim.Pid);
    }

    private static bool IsMomentShape(string moment) =>
        System.Text.RegularExpressions.Regex.IsMatch(moment, @"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{7}Z$");

    /// <summary>
    /// The first lease in this working folder that stands in the way of this
    /// asker building the course, read off disk, or null when nothing does.
    /// Pass the claim of the build lease this program has JUST taken — take,
    /// then look, with nothing awaited in between.
    /// </summary>
    public static Other? InTheWay(Asker asker, string workspacePath, string courseCode, Claim? claim) =>
        FirstInTheWay(asker, courseCode, Environment.ProcessId, claim, Others(workspacePath));

    /// <summary>
    /// The trail's sentence for a decline (<c>build declined, course busy
    /// elsewhere</c>): what was asked for, what the other holds, its process.
    /// </summary>
    public static string DeclineTrailLine(string asked, Other other) =>
        $"{asked} declined — another program on this computer holds the course's {other.Kind} lease (process {other.Pid})";

    /// <summary>Every lease file in the folder, read.</summary>
    private static List<Other> Others(string workspacePath)
    {
        var found = new List<Other>();
        IEnumerable<string> files;
        try { files = System.IO.Directory.EnumerateFiles(Directory(workspacePath), "*.lease"); }
        catch { return found; }

        foreach (string file in files)
        {
            // <COURSE>.<kind>.<pid>.lease, read from the END: a name may hold dots.
            string[] parts = Path.GetFileName(file).Split('.');
            if (parts.Length < 4 || !int.TryParse(parts[^2], out int pid)) continue;
            string course = string.Join(".", parts[..^3]);
            string kind = parts[^3];

            string body;
            try { body = File.ReadAllText(file); }
            catch { continue; }
            var (name, start) = ReadBody(body);
            string[] lines = body.Replace("\r", "").Split('\n');
            string? moment = lines.Length > 2 && lines[2].Trim().Length > 0 ? lines[2].Trim() : null;

            found.Add(new Other(course, kind, pid, moment,
                name is not null && IsAliveOnThisMachine(pid, name, start), name is not null));
        }
        return found;
    }

    // ---- Reading a lease: file-formats.json → workLease -------------------

    /// <summary>
    /// The owner's name (line 2) and start (line 4, the mac's) from a lease's
    /// body, each null when absent or empty. Carriage returns and spaces round
    /// a line are not part of it. PURE: <c>workLease.bodyCases</c>.
    /// </summary>
    public static (string? Name, string? Start) ReadBody(string body)
    {
        string[] lines = body.Replace("\r", "").Split('\n');
        string? Line(int index) =>
            lines.Length > index && lines[index].Trim() is { Length: > 0 } text ? text : null;
        return (Line(1), Line(3));
    }

    // ---- Who counts as alive: shared-rules.json → workLeases.liveness -----

    /// <summary>What asking whether a process exists answered.</summary>
    public enum Signal { Exists, NoSuchProcess, NotPermitted, OtherError }

    /// <summary>What the process table answered.</summary>
    public enum TableAnswer { Entry, NoSuchProcess, CouldNotAsk, NotAsked }

    /// <summary>What the process table said about a process.</summary>
    /// <param name="Name">The process's name, or null.</param>
    /// <param name="Finished">It has exited but is still held (the mac's zombie).</param>
    /// <param name="Start">When it started, as the mac writes line 4, or null.</param>
    public sealed record TableEntry(string? Name, bool Finished, string? Start);

    /// <summary>
    /// The liveness rule, run on what was asked rather than on a live process,
    /// in the contract's order. PURE: <c>workLeases.liveness.cases</c>. Only a
    /// positive answer that nobody is there counts as gone; can't tell is ALIVE.
    /// </summary>
    public static bool IsAlive(int pid, Signal signal, TableAnswer answer, TableEntry? entry,
                               string? leaseName, string? leaseStart)
    {
        if (pid <= 0) return false;
        if (signal == Signal.NoSuchProcess) return false;
        if (answer == TableAnswer.NoSuchProcess) return false;
        if (answer == TableAnswer.Entry && entry is not null)
        {
            if (entry.Finished) return false;
            if (leaseName is not null && entry.Name is not null && !SameName(leaseName, entry.Name)) return false;
            if (leaseStart is not null && entry.Start is not null && leaseStart != entry.Start) return false;
        }
        return true;
    }

    /// <summary>
    /// Names compared without regard to case, on the first sixteen characters
    /// — all the mac's process table keeps. Harmless here, where the table
    /// keeps the whole name.
    /// </summary>
    private static bool SameName(string a, string b)
    {
        static string Cut(string name) => name.Length > 16 ? name[..16] : name;
        return string.Equals(Cut(a), Cut(b), StringComparison.OrdinalIgnoreCase);
    }

    /// <summary>
    /// The body of a lease this process writes: id, name, the moment (UTC,
    /// "O"), and — when <paramref name="withStart"/> — this process's START on
    /// line 4, the mac's spelling (seconds since 1970, a dot, six digits).
    /// The import lease carries line 4 since #244 (#245's ask): every copy of
    /// Plantoir is called Plantoir, so without the start a recycled id read as
    /// alive would refuse every retry of that import until the unrelated
    /// process exited.
    /// </summary>
    public static string LeaseBody(bool withStart)
    {
        using var me = Process.GetCurrentProcess();
        string body = $"{Environment.ProcessId}\n{me.ProcessName}\n{DateTime.UtcNow:O}\n";
        if (withStart)
        {
            try { body += StartMoment(me.StartTime) + "\n"; }
            catch { /* no start to record: the name check still applies */ }
        }
        return body;
    }

    /// <summary>
    /// Whether the process a lease names is alive here, by the liveness rule.
    /// An IMPORT lease with no name line is judged as written by Plantoir, the
    /// only program that ever wrote one (<c>workLeases.liveness</c>, the two
    /// import cases) — never on the id alone.
    /// </summary>
    public static bool OwnerIsAlive(int pid, string? recordedName, string? recordedStart, string kind) =>
        recordedName is null && kind != Importing
            ? false
            : IsAliveOnThisMachine(pid, recordedName ?? "Plantoir", recordedStart);

    /// <summary>The import lease's kind: a reference course's staging folder is being made.</summary>
    public const string Importing = "import";

    /// <summary>The liveness rule, asked of this machine's real process table.</summary>
    private static bool IsAliveOnThisMachine(int pid, string leaseName, string? leaseStart)
    {
        if (pid <= 0) return false;
        Process owner;
        try { owner = Process.GetProcessById(pid); }
        catch (ArgumentException) { return false; }                // no such process: stale
        catch { return true; }                                     // can't tell: assume busy

        try
        {
            bool finished;
            try { finished = owner.HasExited; }
            catch (System.ComponentModel.Win32Exception) { finished = false; }   // another account's: it exists
            string? start;
            try { start = StartMoment(owner.StartTime); }
            catch { start = null; }
            return IsAlive(pid, Signal.Exists, TableAnswer.Entry,
                new TableEntry(owner.ProcessName, finished, start), leaseName, leaseStart);
        }
        catch (InvalidOperationException) { return false; }        // exited while we looked: stale
        catch { return true; }                                     // can't tell: assume busy
    }

    /// <summary>A start time as the mac writes line 4: whole seconds since 1970, a dot, six digits of microseconds.</summary>
    private static string StartMoment(DateTime started)
    {
        long ticks = started.ToUniversalTime().Ticks - DateTime.UnixEpoch.Ticks;
        return $"{ticks / TimeSpan.TicksPerSecond}.{ticks % TimeSpan.TicksPerSecond / 10:D6}";
    }
    /// <summary>
    /// What a build or deploy turned away by another program's lease is told:
    /// <see cref="CourseIsBeingCopied"/> when that lease is a copy being saved
    /// (bundle 6a ruling 4, the mac's sentence), otherwise the window's
    /// <see cref="CourseIsBeingBuiltElsewhere"/> or the assistant's
    /// <see cref="CourseIsBusy"/>.
    /// </summary>
    public static string DeclinedInTheWindow(string course, string kind) =>
        kind == Copying ? AssistWording.CourseIsBeingCopied(course) : AssistWording.CourseIsBeingBuiltElsewhere(course);

    public static string DeclinedForTheAssistant(string course, string kind) =>
        kind == Copying ? AssistWording.CourseIsBeingCopied(course) : AssistWording.CourseIsBusy(course);

    /// <summary>
    /// What an OUTSIDE assistant is told when its rebuild or deploy is held
    /// back (#436): <see cref="AssistWording.CourseIsBeingBuilt"/>, or the
    /// copy sentence when the course is being zipped. Never
    /// <see cref="AssistWording.CourseIsBusy"/>, which keeps its other uses.
    /// </summary>
    public static string HeldBackForAnOutsideAssistant(string course, string kind) =>
        kind == Copying ? AssistWording.CourseIsBeingCopied(course) : AssistWording.CourseIsBeingBuilt(course);

}
