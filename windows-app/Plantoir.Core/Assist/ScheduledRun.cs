using System.Diagnostics;
using System.Text.Json;
using System.Text.Json.Nodes;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;

namespace Plantoir.Core.Assist;

/// <summary>
/// What a publish set for later does when its moment comes: Plantoir, started
/// by Task Scheduler with no window (<c>Plantoir.exe --run-scheduled-deploy
/// &lt;job&gt;</c>), decides whether and where to deploy, and only then writes
/// the wrapper and runs it.
/// </summary>
/// <remarks>
/// <para><b>Why the app and not the wrapper (#347's option (a)).</b> Until
/// bundle 3 the task ran a PowerShell wrapper written when the teacher
/// pressed Schedule, with the destinations and the Account ID baked in, so a
/// teacher who then changed where the course deploys published to the OLD
/// place and was told it succeeded — and nothing could wait for the course,
/// check the lateness window or take a lease, because no Plantoir code ran at
/// the moment itself. Option (b), re-implementing the refusals in PowerShell,
/// was rejected on #347 as a third copy of them; (c), re-registering at Save,
/// misses every other writer of the settings. <c>plantoir-mcp.exe</c> was
/// considered as the host and loses: a console program, with no identity a
/// notification could carry.</para>
///
/// <para><b>The order is the contract's</b>
/// (<c>scheduledDeployCancellation.theDestination.order</c>): the lateness
/// window first; then waiting for the course; then whether the task still
/// stands; then the settings — so a Save made while the run waited counts.
/// Leases taken while waiting are released before any stand-down. Since #477
/// the wait also covers a live copy of the folder's tools by another program,
/// and after the settings the run brings those tools up to date itself,
/// holding its leases, before it writes the wrapper
/// (documentation/07-deployment.md → "On Windows since bundle 3: the
/// scheduled run is Plantoir").</para>
///
/// <para><b>Tasks set before bundle 3 drain.</b> They run
/// <c>powershell.exe -File &lt;baked .ps1&gt;</c>, one-shot; migrating them at
/// app start was rejected (it rewrites an alarm the teacher set, through the
/// step that can lose it, for a task that removes itself by running). They
/// keep the old behaviour for their one remaining run, and their records are
/// filed under their folder by <see cref="ScheduledPublishOutcome.RefileOldNamedRecordsIn"/>.</para>
/// </remarks>
public static class ScheduledRun
{
    /// <summary>
    /// How long a publish set for later waits for another program's build or
    /// publish of the course before it stands down (<c>shared-rules.json</c> →
    /// <c>workLeases.declining.scheduledPublishWait</c>): ten minutes, on the
    /// WALL clock, so a computer that sleeps does not pause the count.
    /// </summary>
    public static readonly TimeSpan LongestWait = TimeSpan.FromSeconds(600);

    /// <summary>How often it looks again while it waits.</summary>
    public static readonly TimeSpan LookAgainEvery = TimeSpan.FromSeconds(15);

    // ---- The job --------------------------------------------------------------

    /// <summary>What a task hands the run: which folder, course and section, for when, and what the teacher was told.</summary>
    /// <param name="Promised">Where the teacher was told it would go, as destination descriptions — NEVER read to decide where it goes.</param>
    public sealed record Job(string TaskName, string WorkingFolder, string CourseCode, int Section,
                             DateTimeOffset? ScheduledFor, IReadOnlyList<string> Promised, string Token = "");

    public static string WriteJob(Job job) => new JsonObject
    {
        ["version"] = 1,
        ["taskName"] = job.TaskName,
        ["workingFolder"] = job.WorkingFolder,
        ["course"] = job.CourseCode,
        ["section"] = job.Section,
        ["scheduledFor"] = job.ScheduledFor?.UtcDateTime.ToString("O"),
        ["token"] = job.Token,
        ["promised"] = new JsonArray(job.Promised.Select(p => (JsonNode?)JsonValue.Create(p)).ToArray()),
    }.ToJsonString(new JsonSerializerOptions { WriteIndented = true });

    /// <summary>The job at this path, or null when it is missing or unreadable.</summary>
    public static Job? ReadJob(string path)
    {
        try
        {
            if (!File.Exists(path)) return null;
            if (JsonNode.Parse(File.ReadAllText(path)) is not JsonObject o) return null;
            string? name = o["taskName"]?.GetValue<string>();
            string? folder = o["workingFolder"]?.GetValue<string>();
            string? course = o["course"]?.GetValue<string>();
            int section = o["section"]?.GetValue<int>() ?? 0;
            if (name is null || folder is null || course is null || section <= 0) return null;
            // Written by this app in the round-trip "O" form, read back the same way.
            string? stored = o["scheduledFor"]?.GetValue<string>();
            DateTimeOffset? scheduledFor = DateTimeOffset.TryParse(stored, System.Globalization.CultureInfo.InvariantCulture, System.Globalization.DateTimeStyles.RoundtripKind, out var when) ? when : null;
            var promised = (o["promised"] as JsonArray)?.Select(p => p?.GetValue<string>() ?? "")
                               .Where(p => p.Length > 0).ToList() ?? new List<string>();
            string token = o["token"]?.GetValue<string>() ?? "";
            return new Job(name, folder, course, section, scheduledFor, promised, token);
        }
        catch { return null; }
    }

    // ---- How late is too late (#239) -------------------------------------------

    /// <summary>
    /// Whether a run this far from its moment stands down
    /// (<c>scheduledDeployCancellation.howLateIsTooLate</c>): the distance
    /// between two absolute instants, either way round, against the course's
    /// window — never a calendar. A moment that cannot be read RUNS: a deploy
    /// the teacher asked for beats a refusal nobody sees.
    /// </summary>
    public static bool IsTooLate(TimeSpan? lateBy, int windowDays) =>
        lateBy is { } late && Math.Abs(late.TotalSeconds) > TimeSpan.FromDays(windowDays).TotalSeconds;

    // ---- Where it goes, read at the run (#347) ----------------------------------

    /// <summary>What the settings as they are now say the run should do.</summary>
    /// <param name="DeploysTo">The destinations to deploy to, in order; null when it stands down.</param>
    /// <param name="Refusal">The key it stands down with, and the destination it names.</param>
    /// <param name="NotesTheChange">Whether the trail should say where it was set to go and where it goes now.</param>
    /// <param name="Reason">The clause a stand-down's sentence carries, empty when it goes ahead.</param>
    public sealed record Decision(IReadOnlyList<CourseConfiguration.DeployDestination>? DeploysTo,
                                  ScheduledDeploy.Refusal? Refusal, bool NotesTheChange, string Reason);

    /// <summary>
    /// The settings as they are at the run, checked the way the schedule sheet
    /// checked them except for the time (<c>theDestination</c>). Reads nothing
    /// but the course folder's site markers, which is what the contract's
    /// cases play.
    /// </summary>
    public static Decision Decide(Course? course, int section, string cloudflareAccountID, IReadOnlyList<string> promised)
    {
        if (course is null)
            return new Decision(null, new ScheduledDeploy.Refusal("settingsCouldNotBeRead"), false,
                SettingsCouldNotBeRead);

        var destinations = course.Configuration.AllDeployDestinations;
        var now = destinations.Select(DeployCommand.DestinationDescription).ToList();
        bool differs = promised.Count > 0 && !promised.SequenceEqual(now);

        if (ScheduledDeploy.RefusalOf(course, section, cloudflareAccountID) is { } refusal)
        {
            // A reference course is never deployed, whatever it was set to;
            // a destination unchanged since the teacher was told is not "a
            // change" even when it now refuses (the folder is gone since).
            return new Decision(null, refusal, differs && refusal.Key != "keptForReference",
                ReasonClause(refusal));
        }
        return new Decision(destinations, null, differs, "");
    }

    /// <summary>The clause a stand-down's sentence carries as {reason}: true at any moment, no remedy, no path.</summary>
    public static string ReasonClause(ScheduledDeploy.Refusal refusal) => refusal.Key switch
    {
        "keptForReference" => "it is a course kept for reference, which is never deployed",
        "deployFolderNeedsAttention" => "the folder it deploys to needs attention in this course’s settings, under Deploying",
        "cloudflareAccountMissing" => "it deploys to Cloudflare Pages, which needs your Account ID, and no Account ID that works is set",
        "additionalDeployFolderNeedsAttention" => "a folder it also deploys to needs attention in this course’s settings, under Deploying",
        "additionalCloudflareAccountMissing" => "it also deploys to Cloudflare Pages, which needs your Account ID, and no Account ID that works is set",
        "neverDeployed" => $"it has never been deployed to {refusal.Destination}, and the first deploy there asks what to call the website",
        "additionalDestinationNeverDeployed" => $"it has never been deployed to {refusal.Destination}, and the first deploy there asks what to call that site",
        "settingsCouldNotBeRead" => SettingsCouldNotBeRead,
        _ => throw new ArgumentOutOfRangeException(nameof(refusal)),
    };

    // ---- What a Save says about them (#347; savingSettings.scheduledDeploys) --

    /// <summary>
    /// After a Course Settings Save, one sentence per section of the course with
    /// a deploy set to happen on its own in THIS working folder and still to
    /// come: it cannot go ahead the way the course is set now (said whether or
    /// not the Save changed anything), or — when the Save changed where the
    /// course deploys — it will go where the course deploys now. Otherwise
    /// nothing. Nothing is refused or undone: the run checks again anyway.
    /// </summary>
    /// <param name="scheduled">This folder's deploys of the course: section and moment.</param>
    /// <param name="before">The course's destinations in the file BEFORE this Save.</param>
    public static IReadOnlyList<string> WhatASaveSays(
        IEnumerable<(int Section, DateTime Moment)> scheduled, Course after,
        IReadOnlyList<CourseConfiguration.DeployDestination> before, string cloudflareAccountID)
    {
        var now = after.Configuration.AllDeployDestinations;
        bool changed = !before.Select(d => (d.Type, d.Path)).SequenceEqual(now.Select(d => (d.Type, d.Path)));
        var said = new List<string>();
        foreach (var (section, moment) in scheduled.OrderBy(s => s.Section))
        {
            var decision = Decide(after, section, cloudflareAccountID, []);
            if (decision.DeploysTo is null)
                said.Add($"Section {section} is set to deploy on its own on {moment:dddd d MMMM, h:mm tt}, but it could not " +
                         $"go ahead the way this course is set now: {decision.Reason}. Put that right and it will go ahead as set.");
            else if (changed)
                said.Add($"Section {section}’s deploy set for {moment:dddd d MMMM, h:mm tt} will go to " +
                         $"{string.Join(", ", decision.DeploysTo.Select(DeployCommand.DestinationDescription))} now.");
        }
        return said;
    }

    /// <summary>
    /// This working folder's deploys of the course still to come, with their
    /// moments — read from the jobs, since the task's own next-run time is
    /// written in the machine's locale.
    /// </summary>
    public static IReadOnlyList<(int Section, DateTime Moment)> StillToCome(string workingFolder, string courseCode) =>
        TaskScheduling.InFolder(workingFolder)
            .Where(task => TaskScheduling.SameCode(task.CourseCode, courseCode))
            .Select(task => (task.Section, Moment: ReadJob(TaskScheduling.JobPath(task.Name))?.ScheduledFor?.LocalDateTime ?? task.NextRun))
            .Where(entry => entry.Moment is { } when && when > DateTime.Now)
            .Select(entry => (entry.Section, entry.Moment!.Value))
            .ToList();

    public const string SettingsCouldNotBeRead =
        "its settings could not be read when the time came, so there was no telling where to deploy it";

    /// <summary>
    /// The clause for a deploy the run could not get ready: its wrapper could
    /// not be written — and, since #477, the folder's tools could not be
    /// brought up to date, or another program was still copying them at the
    /// end of the run's ten minutes. True for all three, and the contract's
    /// own words (<c>wrapperCouldNotBeWritten</c>), so no contract change.
    /// </summary>
    public const string WrapperCouldNotBeWritten =
        "Plantoir could not get the deploy ready on this computer when the time came";

    // ---- The run --------------------------------------------------------------

    /// <summary>What the run touches outside itself, so a test can stand in for it.</summary>
    public sealed class World
    {
        public Func<DateTimeOffset> Now { get; init; } = () => DateTimeOffset.Now;
        public Action<TimeSpan> Sleep { get; init; } = Thread.Sleep;
        public Func<string> CloudflareAccountID { get; init; } = () => AppSettings.Load().CloudflareAccountId;
        /// <summary>Runs the written wrapper and answers its exit code.</summary>
        public Func<string, int> RunWrapper { get; init; } = RunWrapperForReal;
        public string OutcomeDirectory { get; init; } = ScheduledPublishOutcome.Directory();

        /// <summary>
        /// The app's recipe, beside the program (#477): the run brings the
        /// folder's launchers and tools up to date from it before it builds.
        /// Null: no refresh (the tests that are not about it; the program
        /// sets it).
        /// </summary>
        public string? BundledToolchainRoot { get; init; }

        /// <summary>
        /// The process id of a LIVE program copying the tools into this
        /// working folder now, never this run's own, or null (#477) — read from
        /// the <c>toolchain-copying.&lt;pid&gt;</c> markers.
        /// </summary>
        public Func<string, int?> CopyingTheFolder { get; init; } = folder =>
            ToolchainReadiness.LiveCopiers(folder, exceptThisProcess: true) is { Count: > 0 } pids ? pids[0] : null;
    }

    /// <summary>How the run ended — for the process's exit code and for tests.</summary>
    public enum Ending { Deployed, StoodDown, NoLongerStands, JobUnreadable }

    /// <summary>Run the job at <paramref name="jobPath"/> now.</summary>
    public static Ending Execute(string jobPath, World? world = null, string? taskToken = null)
    {
        world ??= new World();
        if (ReadJob(jobPath) is not { } job) return Ending.JobUnreadable;
        // Ruling 8: the task was set with another job than this one (a crash
        // between writing a new job and replacing the task). Do nothing, and
        // leave the task alone.
        if (!string.IsNullOrEmpty(taskToken) && taskToken != job.Token) return Ending.NoLongerStands;

        var course = ReadCourse(job.WorkingFolder, job.CourseCode);

        // 1. The lateness window (#239): read at the run, off disk; a job too
        // late stands down whatever its settings say. Unreadable settings give
        // the default here — the opposite of the destination's rule below.
        int window = course?.Configuration.ScheduledDeployMayRunLateDays ?? CourseConfiguration.DefaultMayRunLateDays;
        TimeSpan? lateBy = job.ScheduledFor is { } moment ? world.Now() - moment : null;
        if (IsTooLate(lateBy, window))
        {
            StandDown(job, world, ScheduledPublishOutcome.Kind.TooLateToRun, "");
            return Ending.StoodDown;
        }

        // 2. Wait for the course (#289): another program's build or publish,
        // never a preview. Take, then look — only leases taken before this
        // run's build lease count — on the wall clock, fifteen seconds at a time.
        //
        // Since #477 it also waits, in the same window and on the same clock,
        // while another program is copying the tools into the working folder
        // (a window opened on the folder just before 06:30, after an update):
        // building then would build from a mix of old and new files. It takes
        // no lease while a copy is live, and a copy still live at ten minutes
        // stands it down as a deploy it could not get ready — never "the course
        // was busy", which would be a false sentence about the course.
        var started = world.Now();
        WorkLease.Held? build = null, publish = null;
        WorkLease.Other? inTheWay;
        int? copying;
        int? copier = null;
        bool waited = false, metACopy = false, metTheCourse = false;
        while (true)
        {
            inTheWay = null;
            copying = world.CopyingTheFolder(job.WorkingFolder);
            if (copying is not null)
            {
                metACopy = true;
                copier = copying;
            }
            else
            {
                inTheWay = WorkLease.InTheWay(WorkLease.Asker.AScheduledPublish, job.WorkingFolder, job.CourseCode, claim: null);
                if (inTheWay is null)
                {
                    build = WorkLease.Take(job.WorkingFolder, job.CourseCode, WorkLease.Building);
                    publish = WorkLease.Take(job.WorkingFolder, job.CourseCode, WorkLease.Publishing);
                    inTheWay = WorkLease.InTheWay(WorkLease.Asker.AScheduledPublish, job.WorkingFolder, job.CourseCode, build.Claim);
                    if (inTheWay is null) break;
                    build.Dispose();
                    publish.Dispose();
                    build = publish = null;
                }
                metTheCourse = true;
            }
            if (world.Now() - started >= LongestWait) break;
            waited = true;
            world.Sleep(LookAgainEvery);
        }

        int seconds = (int)Math.Round((world.Now() - started).TotalSeconds);
        if (copying is not null)
        {
            ActivityTrail.Note(ActivityTrail.Event.ScheduledPublishWaitedForTheCourse,
                $"waited {seconds} s for Plantoir to finish getting the working folder ready (process {copying}), and stood down",
                job.CourseCode, job.Section);
            StandDown(job, world, ScheduledPublishOutcome.Kind.CouldNotRunAsSetNow, WrapperCouldNotBeWritten);
            return Ending.StoodDown;
        }
        if (inTheWay is not null)
        {
            ActivityTrail.Note(ActivityTrail.Event.ScheduledPublishWaitedForTheCourse,
                $"waited {seconds} s for another program's {inTheWay.Kind} of the course (process {inTheWay.Pid}), and stood down",
                job.CourseCode, job.Section);
            StandDown(job, world, ScheduledPublishOutcome.Kind.CourseWasBusy, "");
            return Ending.StoodDown;
        }
        if (waited)
            ActivityTrail.Note(ActivityTrail.Event.ScheduledPublishWaitedForTheCourse, WaitedLine(seconds, metTheCourse, metACopy, copier),
                job.CourseCode, job.Section);

        try
        {
            // 3. Still standing? A task cancelled or set again while this run
            // waited deploys nothing and writes nothing: the teacher did that.
            if (!StillStands(job, jobPath)) return Ending.NoLongerStands;

            // 4. The settings as they are NOW (#347) — re-read, since a Save
            // made during the wait counts.
            course = ReadCourse(job.WorkingFolder, job.CourseCode);
            var decision = Decide(course, job.Section, world.CloudflareAccountID(), job.Promised);
            if (decision.DeploysTo is null)
            {
                NoteTheSettings(job, course, decision, wentAhead: false);
                build?.Dispose();
                publish?.Dispose();
                build = publish = null;
                StandDown(job, world, ScheduledPublishOutcome.Kind.CouldNotRunAsSetNow, decision.Reason);
                return Ending.StoodDown;
            }
            if (decision.NotesTheChange) NoteTheSettings(job, course, decision, wentAhead: true);

            // 5a. Bring the folder's tools up to date (#477), holding both
            // leases, BEFORE the wrapper: its fingerprint step and the build it
            // runs read .toolchain\, and must read the tools this program
            // carries — not the ones from before an update nobody has opened
            // the app since. The copy writes the same marker the window's does,
            // so plantoir-mcp refuses meanwhile and a window's later copy waits
            // its turn; a copy by another program still running at the run's
            // ten minutes stands it down, as does a copy that failed.
            if (world.BundledToolchainRoot is { } bundled)
            {
                var turns = new ToolchainReadiness.TakingTurns(world.Sleep, () => world.Now() - started >= LongestWait);
                ToolchainReadiness.RefreshWorkspace(job.WorkingFolder, bundled, retryAFailedCopy: true, turns,
                                                    (job.CourseCode, job.Section)).GetAwaiter().GetResult();
                if (ToolchainReadiness.StateOf(job.WorkingFolder) == ToolchainReadiness.State.Failed)
                {
                    if (ToolchainReadiness.LastCopyOf(job.WorkingFolder) is { GaveUpWaiting: true } notStarted)
                        ActivityTrail.Note(ActivityTrail.Event.ScheduledPublishWaitedForTheCourse,
                            $"waited {(int)Math.Round((world.Now() - started).TotalSeconds)} s for Plantoir to finish getting " +
                            $"the working folder ready (process {notStarted.WaitedForPid}), and stood down",
                            job.CourseCode, job.Section);
                    build?.Dispose();
                    publish?.Dispose();
                    build = publish = null;
                    StandDown(job, world, ScheduledPublishOutcome.Kind.CouldNotRunAsSetNow, WrapperCouldNotBeWritten);
                    return Ending.StoodDown;
                }
                // A cold copy takes minutes (94–120 s measured): a cancellation
                // or a re-set made meanwhile must not be deployed over.
                if (!StillStands(job, jobPath)) return Ending.NoLongerStands;
            }

            // 5b. Write the wrapper from those settings, under the job's OWN
            // name, and run it. The name is never recomputed (#309's trap).
            string launcher = Path.Combine(job.WorkingFolder, "deploy.ps1");
            var excluded = SectionPublishState.SelfPublishingSubpaths(course!.DirectoryPath, decision.DeploysTo);
            if (TaskScheduling.WriteWrapperScript(job.TaskName, job.WorkingFolder, launcher, job.CourseCode, job.Section,
                    course.DirectoryPath, excluded, decision.DeploysTo, world.CloudflareAccountID()) is not { } script)
            {
                build?.Dispose();
                publish?.Dispose();
                build = publish = null;
                StandDown(job, world, ScheduledPublishOutcome.Kind.CouldNotRunAsSetNow, WrapperCouldNotBeWritten);
                return Ending.StoodDown;
            }
            // #475: nobody is awake at half six to be asked about classes dated
            // after the next class, so the deploy goes out as it is — read
            // here, from the settings and pages it is about to deploy, on the
            // run's own day, and recorded below only once it HAS deployed.
            var later = ClassesDatedLater.FlaggedIn(course, job.Section, DateOnly.FromDateTime(world.Now().LocalDateTime));
            // The wrapper's success record is read against the REAL clock that
            // dates its file, never world.Now (a test's pinned morning), so
            // both sides of the comparison are this computer's local time.
            var ranAt = DateTime.Now;
            world.RunWrapper(script);
            NoteTheClassesThatWentOut(job, world, later, ranAt);
        }
        finally
        {
            build?.Dispose();
            publish?.Dispose();
        }

        // One-shot: the task has done its job; clear it away so it cannot be
        // mistaken for one still to come. The wrapper's record stays.
        ClearIfStillMine(job, TaskScheduling.JobPath(job.TaskName));
        return Ending.Deployed;
    }

    /// <summary>
    /// The trail's line for a run that waited and then went ahead
    /// (<c>scheduled publish waited for the course</c>): what stood in the way
    /// — another program's work on the course, a copy of the folder's tools
    /// (#477), or both — and, for a copy, which program.
    /// </summary>
    internal static string WaitedLine(int seconds, bool metTheCourse, bool metACopy, int? copier) =>
        (metTheCourse, metACopy) switch
        {
            (true, true) => $"waited {seconds} s for another program on this computer to finish with the course " +
                            $"and for Plantoir to finish getting the working folder ready (process {copier}), and went ahead",
            (false, true) => $"waited {seconds} s for Plantoir to finish getting the working folder ready (process {copier}), and went ahead",
            _ => $"waited {seconds} s for another program on this computer to finish with the course, and went ahead",
        };

    /// <summary>
    /// "deployed with classes dated after the next class: …" (#475,
    /// <c>laterClassesWentOut</c>) — written only when the wrapper left its
    /// SUCCESS record during this run. Never on the wrapper's exit code: it is
    /// 0 whether or not the deploy got through (the mac measured gating on it
    /// writing the line after a failed deploy, its fixes review A), and a
    /// record older than this run is an earlier night's.
    /// </summary>
    private static void NoteTheClassesThatWentOut(Job job, World world, IReadOnlyList<ClassesDatedLater.Page> later,
                                                  DateTime ranAt)
    {
        if (ClassesDatedLater.WentOutLine(later) is not { } line) return;
        if (ScheduledPublishOutcome.ReadFrom(world.OutcomeDirectory, job.CourseCode, job.Section, job.WorkingFolder)
                is not { Outcome: ScheduledPublishOutcome.Kind.Succeeded } record) return;
        // A second's slack for the file system's clock against this one.
        if (record.When < ranAt.AddSeconds(-1)) return;
        ActivityTrail.Note(ActivityTrail.Event.LaterClassesWentOut, line, job.CourseCode, job.Section);
    }

    /// <summary>
    /// Clear this run's task away — but only while its job still names THIS
    /// run's moment. A teacher who sets the section again while a long deploy
    /// runs, or while the run waits for the course, gets a new task under the
    /// SAME name (one per section per folder); deleting by name then would
    /// delete the deploy they have just set.
    /// </summary>
    private static void ClearIfStillMine(Job job, string jobPath)
    {
        // By the token each setting writes, not by the moment: a re-set for
        // the SAME minute is still a different deploy (ruling 3).
        if (ReadJob(jobPath) is { } now && !IsTheSameSetting(now, job)) return;
        TaskScheduling.Cancel(new TaskScheduling.ScheduledTask(job.TaskName, job.WorkingFolder, job.CourseCode, job.Section, null));
    }

    /// <summary>
    /// Whether the job this run was started for still stands: its task is
    /// registered and its job file still names this run's moment. A run that
    /// outlived its cancellation would otherwise bring the deploy back.
    /// </summary>
    private static bool StillStands(Job job, string jobPath) =>
        TaskScheduling.Exists(job.TaskName)
        && ReadJob(jobPath) is { } now
        && IsTheSameSetting(now, job);

    private static bool IsTheSameSetting(Job a, Job b) =>
        a.Token.Length > 0 || b.Token.Length > 0 ? a.Token == b.Token : a.ScheduledFor == b.ScheduledFor;

    private static void NoteTheSettings(Job job, Course? course, Decision decision, bool wentAhead)
    {
        string was = job.Promised.Count > 0 ? MultiDestinationDeployRunner.JoinedWithAnd(job.Promised.ToList()) : "nowhere recorded";
        string now = course is null
            ? "settings that could not be read"
            : MultiDestinationDeployRunner.JoinedWithAnd(course.Configuration.AllDeployDestinations
                .Select(DeployCommand.DestinationDescription).ToList());
        string line = wentAhead
            ? $"was set to deploy to {was}; the course deploys to {now} now, so it went there"
            : $"was set to deploy to {was}; the course deploys to {now} now, and it stood down — {decision.Reason}";
        ActivityTrail.Note(ActivityTrail.Event.ScheduledPublishReadTheCoursesSettings, line, job.CourseCode, job.Section);
    }

    /// <summary>
    /// Deploy nothing, clear the task away so it cannot recur, and leave the
    /// record the section shows (its trail line, <c>scheduled deploy turned
    /// off</c>, is written by the sweep that reads it, as every scheduled
    /// line on this side is).
    /// </summary>
    private static void StandDown(Job job, World world, ScheduledPublishOutcome.Kind kind, string reason)
    {
        try
        {
            ScheduledPublishOutcome.Record(world.OutcomeDirectory, job.CourseCode, job.Section, kind, reason, job.WorkingFolder);
        }
        catch { /* the task still goes: a record that cannot be written must not leave it to recur */ }
        ClearIfStillMine(job, TaskScheduling.JobPath(job.TaskName));
    }

    /// <summary>
    /// The course the job names, from the course folders listed under
    /// <c>courses\</c> — never by asking whether <c>courses\&lt;CODE&gt;</c>
    /// exists, because the volume answers yes for a DIFFERENT course one letter
    /// case away (#239's fifth trap). An exact name wins; otherwise one unique
    /// match ignoring case; otherwise none. Null when it cannot be read.
    /// </summary>
    public static Course? ReadCourse(string workingFolder, string courseCode)
    {
        try
        {
            string courses = Workspace.CoursesDirectory(workingFolder);
            var names = Directory.EnumerateDirectories(courses).Select(Path.GetFileName).OfType<string>().ToList();
            string? folder = names.FirstOrDefault(name => name == courseCode);
            if (folder is null)
            {
                var near = names.Where(name => string.Equals(name, courseCode, StringComparison.OrdinalIgnoreCase)).ToList();
                if (near.Count != 1) return null;
                folder = near[0];
            }
            string directory = Path.Combine(courses, folder);
            string config = Path.Combine(directory, "course_config.json");
            if (!File.Exists(config)) return null;
            return new Course(courseCode, directory, CourseConfiguration.FromBytes(File.ReadAllBytes(config)));
        }
        catch { return null; }
    }

    /// <summary>
    /// How the wrapper is started. It is handed this run's trail folder
    /// (#682), and its own children - <c>preview.ps1 --build-only</c> and each
    /// <c>deploy.ps1</c> leg, started with <c>Start-Process</c> - inherit it,
    /// so the launchers' lines land in the same trail as this run's. ONLY the
    /// trail: handing <c>PLANTOIR_RUNTIME</c> here too would change which
    /// runtime a task uses (the wrapper falls back to the installed one),
    /// which is its own question (#702).
    /// </summary>
    internal static ProcessStartInfo WrapperStartInfo(string script)
    {
        var info = new ProcessStartInfo
        {
            FileName = Path.Combine(Environment.SystemDirectory, "WindowsPowerShell", "v1.0", "powershell.exe"),
            CreateNoWindow = true,
            UseShellExecute = false,
            WorkingDirectory = Path.GetDirectoryName(script) ?? Environment.CurrentDirectory,
        };
        info.EnvironmentVariables[LauncherEnvironment.TrailVariable] = ActivityTrail.CurrentLogDirectory;
        foreach (string argument in TaskScheduling.WrapperRunArguments(script)) info.ArgumentList.Add(argument);
        return info;
    }

    /// <summary>Run the wrapper with PowerShell, non-interactively, and answer its exit code.</summary>
    private static int RunWrapperForReal(string script)
    {
        var info = WrapperStartInfo(script);
        try
        {
            using var process = Process.Start(info);
            if (process is null) return 1;
            process.WaitForExit();
            return process.ExitCode;
        }
        catch { return 1; }
    }
}
