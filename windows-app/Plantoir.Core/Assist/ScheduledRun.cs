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
/// Leases taken while waiting are released before any stand-down.</para>
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
                             DateTimeOffset? ScheduledFor, IReadOnlyList<string> Promised);

    public static string WriteJob(Job job) => new JsonObject
    {
        ["version"] = 1,
        ["taskName"] = job.TaskName,
        ["workingFolder"] = job.WorkingFolder,
        ["course"] = job.CourseCode,
        ["section"] = job.Section,
        ["scheduledFor"] = job.ScheduledFor?.UtcDateTime.ToString("O"),
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
            DateTimeOffset? scheduledFor = DateTimeOffset.TryParse(o["scheduledFor"]?.GetValue<string>(),
                System.Globalization.CultureInfo.InvariantCulture, System.Globalization.DateTimeStyles.RoundtripKind,
                out var when) ? when : null;
            var promised = (o["promised"] as JsonArray)?.Select(p => p?.GetValue<string>() ?? "")
                               .Where(p => p.Length > 0).ToList() ?? new List<string>();
            return new Job(name, folder, course, section, scheduledFor, promised);
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

    public const string SettingsCouldNotBeRead =
        "its settings could not be read when the time came, so there was no telling where to deploy it";

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
    }

    /// <summary>How the run ended — for the process's exit code and for tests.</summary>
    public enum Ending { Deployed, StoodDown, NoLongerStands, JobUnreadable }

    /// <summary>Run the job at <paramref name="jobPath"/> now.</summary>
    public static Ending Execute(string jobPath, World? world = null)
    {
        world ??= new World();
        if (ReadJob(jobPath) is not { } job) return Ending.JobUnreadable;

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
        var started = world.Now();
        WorkLease.Held? build = null, publish = null;
        WorkLease.Other? inTheWay;
        bool waited = false;
        while (true)
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
            if (world.Now() - started >= LongestWait) break;
            waited = true;
            world.Sleep(LookAgainEvery);
        }

        int seconds = (int)Math.Round((world.Now() - started).TotalSeconds);
        if (inTheWay is not null)
        {
            ActivityTrail.Note(ActivityTrail.Event.ScheduledPublishWaitedForTheCourse,
                $"waited {seconds} s for another program's {inTheWay.Kind} of the course (process {inTheWay.Pid}), and stood down",
                job.CourseCode, job.Section);
            StandDown(job, world, ScheduledPublishOutcome.Kind.CourseWasBusy, "");
            return Ending.StoodDown;
        }
        if (waited)
            ActivityTrail.Note(ActivityTrail.Event.ScheduledPublishWaitedForTheCourse,
                $"waited {seconds} s for another program on this computer to finish with the course, and went ahead",
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

            // 5. Write the wrapper from those settings, under the job's OWN
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
            world.RunWrapper(script);
        }
        finally
        {
            build?.Dispose();
            publish?.Dispose();
        }

        // One-shot: the task has done its job; clear it away so it cannot be
        // mistaken for one still to come. The wrapper's record stays.
        TaskScheduling.Cancel(new TaskScheduling.ScheduledTask(job.TaskName, job.WorkingFolder, job.CourseCode, job.Section, null));
        return Ending.Deployed;
    }

    /// <summary>
    /// Whether the job this run was started for still stands: its task is
    /// registered and its job file still names this run's moment. A run that
    /// outlived its cancellation would otherwise bring the deploy back.
    /// </summary>
    private static bool StillStands(Job job, string jobPath) =>
        TaskScheduling.Exists(job.TaskName)
        && ReadJob(jobPath) is { } now
        && now.ScheduledFor == job.ScheduledFor;

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
        TaskScheduling.Cancel(new TaskScheduling.ScheduledTask(job.TaskName, job.WorkingFolder, job.CourseCode, job.Section, null));
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

    /// <summary>Run the wrapper with PowerShell, non-interactively, and answer its exit code.</summary>
    private static int RunWrapperForReal(string script)
    {
        var info = new ProcessStartInfo
        {
            FileName = Path.Combine(Environment.SystemDirectory, "WindowsPowerShell", "v1.0", "powershell.exe"),
            CreateNoWindow = true,
            UseShellExecute = false,
            WorkingDirectory = Path.GetDirectoryName(script) ?? Environment.CurrentDirectory,
        };
        foreach (string argument in TaskScheduling.WrapperRunArguments(script)) info.ArgumentList.Add(argument);
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
