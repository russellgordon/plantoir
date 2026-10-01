using System.Diagnostics;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using Plantoir.Core.Models;

using Plantoir.Core.Scripting;

namespace Plantoir.Core.Assist;

/// <summary>
/// Handing a deploy to Windows Task Scheduler, via schtasks.
///
/// schtasks rather than the TaskScheduler COM library on purpose: it needs no
/// extra dependency, it is present on every Windows this app runs on, and its
/// failures arrive as text a teacher can be shown. The equivalent on macOS is
/// launchd, which is why the decision of WHETHER to schedule — and every word
/// the teacher reads — lives in Plantoir.Core, and only this last step is
/// Windows-specific.
///
/// <para><b>What the task runs, since bundle 3 (#347, #289, #239).</b> The
/// task no longer runs a PowerShell wrapper written when the teacher pressed
/// Schedule. It runs PLANTOIR — <c>Plantoir.exe --run-scheduled-deploy
/// &lt;job&gt;</c> — with no window, and <see cref="ScheduledRun"/> decides at
/// the moment itself: whether it is too late to be worth doing, whether
/// another program is building the course (it waits up to ten minutes),
/// whether the task still stands, and where the course deploys NOW. Only
/// then does it write the wrapper, from the course's settings as they are at
/// that moment, and run it. The mac's launchd job has launched the app since
/// v1.2.0; this is the same shape, recommended as option (a) on #347.</para>
///
/// <para><b>One task per section per WORKING FOLDER</b> (#309, mac #237):
/// <c>Plantoir deploy {CODE} section {N} {folder id}</c>, the id being
/// <see cref="FolderContainers.FolderIdentifier"/> — the one this folder's
/// builds folder already uses. A task is FOUND by the working folder its own
/// job (or, for a task set before the update, its own wrapper) names, never
/// by rebuilding the name, so a task set under the old name keeps being
/// shown, cancelled and run until it drains.</para>
///
/// It deliberately does not ask for a wake timer. See ScheduledDeploy for why.
/// </summary>
public static class TaskScheduling
{
    /// <summary>
    /// The date formats schtasks might want, most likely first. Which one is
    /// correct depends on the machine's locale, and it accepts exactly one.
    /// </summary>
    private static void PutBack(string jobPath, string kept)
    {
        try
        {
            if (File.Exists(kept)) File.Move(kept, jobPath, overwrite: true);
            else File.Delete(jobPath);
        }
        catch { }
    }

    /// <summary>
    /// The task's definition: one start at <paramref name="when"/>, run as the
    /// teacher, on battery too and not stopped by unplugging, and run as soon
    /// as possible after a start that was missed (the lateness window then
    /// decides whether it is still worth doing).
    /// </summary>
    internal static string TaskXml(string runner, string taskName, DateTime when, string token = "")
    {
        static string X(string v) => System.Security.SecurityElement.Escape(v);
        string user = $"{Environment.UserDomainName}\\{Environment.UserName}";
        string start = when.ToString("yyyy-MM-dd'T'HH:mm:ss", System.Globalization.CultureInfo.InvariantCulture);
        return $"""
            <?xml version="1.0" encoding="UTF-16"?>
            <Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
              <Triggers><TimeTrigger><StartBoundary>{start}</StartBoundary><Enabled>true</Enabled></TimeTrigger></Triggers>
              <Principals><Principal id="Author"><UserId>{X(user)}</UserId><LogonType>InteractiveToken</LogonType><RunLevel>LeastPrivilege</RunLevel></Principal></Principals>
              <Settings>
                <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
                <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
                <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
                <StartWhenAvailable>true</StartWhenAvailable>
                <ExecutionTimeLimit>PT72H</ExecutionTimeLimit>
                <Enabled>true</Enabled>
              </Settings>
              <Actions Context="Author"><Exec><Command>{X(runner)}</Command><Arguments>{X($"{RunArgument} \"{taskName}\"" + (token.Length > 0 ? $" {TokenArgument} {token}" : ""))}</Arguments></Exec></Actions>
            </Task>
            """;
    }

    /// <summary>What the task passes Plantoir to say "run this scheduled deploy now".</summary>
    public const string RunArgument = "--run-scheduled-deploy";

    /// <summary>
    /// The setting's token, carried by the task beside its name (ruling 8): a
    /// run whose task token is not the job's does nothing and leaves the task,
    /// so a crash between writing a new job and replacing the task cannot run
    /// the OLD task on the NEW job.
    /// </summary>
    public const string TokenArgument = "--token";

    /// <summary>
    /// What a scheduled run's command line asks for: the job to run (a task
    /// name, or a job path taken as is) and the task's token, or null when the
    /// line is not a scheduled run. Program.Main's parsing, here so it is
    /// tested (bundle 4 fix review M1).
    /// </summary>
    public static (string JobPath, string? Token)? ScheduledRunFrom(IReadOnlyList<string> args)
    {
        int run = args.ToList().IndexOf(RunArgument);
        if (run < 0 || run + 1 >= args.Count) return null;
        string named = args[run + 1];
        string job = named.EndsWith(".job.json", StringComparison.OrdinalIgnoreCase) ? named : JobPath(named);
        int at = args.ToList().IndexOf(TokenArgument);
        string? token = at >= 0 && at + 1 < args.Count ? args[at + 1] : null;
        return (job, token);
    }

    // ---- Names --------------------------------------------------------------

    /// <summary>
    /// The name a section's scheduled deploy carries in THIS working folder
    /// (#309): one per code, section and folder, machine-wide.
    /// </summary>
    public static string NameFor(string courseCode, int sectionNumber, string workingFolder) =>
        $"{OldNameFor(courseCode, sectionNumber)} {FolderContainers.FolderIdentifier(workingFolder)}";

    /// <summary>
    /// The name every task carried before #309 — the code and the section and
    /// nothing else, so two working folders holding ICS3U section 1 shared
    /// ONE task. Kept only to recognise such a task; never to make one.
    /// </summary>
    internal static string OldNameFor(string courseCode, int sectionNumber) =>
        $"Plantoir deploy {courseCode.ToUpperInvariant()} section {sectionNumber}";

    private const string NamePrefix = "Plantoir deploy ";

    // ---- Scheduling -----------------------------------------------------------

    /// <summary>
    /// Set (or replace) this working folder's scheduled deploy of one section.
    /// Returns null on success, or the reason it could not be scheduled.
    /// </summary>
    /// <remarks>
    /// <para>Writes a small JOB file — which folder, course, section, when it
    /// was meant for and where it was promised to go — and registers a task
    /// that hands that file to Plantoir. The destinations are NOT baked in:
    /// the run reads the course's settings when it fires (#347).
    /// <paramref name="promised"/> is only what the teacher was TOLD, so the run
    /// can say on the trail when the two differ.</para>
    ///
    /// <para>A task this folder set before #309, under the old name, is
    /// removed only AFTER the new one is accepted, so a refusal hands the old
    /// one back rather than losing it (the mac's review M1).</para>
    /// </remarks>
    public static string? Schedule(string workingFolder, string courseCode, int section, DateTime when,
                                   IReadOnlyList<CourseConfiguration.DeployDestination> promised)
    {
        // The launcher does the deploy, exactly as the app does it.
        if (!File.Exists(Path.Combine(workingFolder, "deploy.ps1")))
            return CouldNotBeSet(courseCode, section, when, null, null,
                $"There is no deploy.ps1 in {workingFolder}, so there is nothing to schedule.");

        if (RunnerExecutable() is not { } runner)
            return CouldNotBeSet(courseCode, section, when, null, null,
                "Plantoir could not find its own program on this computer, so it cannot deploy later on its own. " +
                "Deploy this section yourself instead.");

        string taskName = NameFor(courseCode, section, workingFolder);
        var existing = For(workingFolder, courseCode, section);
        // Read BEFORE anything is written (#261): once the new task is in,
        // the old one has left nothing behind to ask about.
        var replacing = WhatSchedulingReplaces(workingFolder, courseCode, section);
        DateTime? replacedMoment = replacing is null ? null : MomentOf(replacing);

        // The job goes into place BEFORE the task is replaced (bundle 3 fix
        // round, ruling 3): a run finishing in between reads the NEW job, sees
        // a token that is not its own, and leaves the new task alone. The old
        // job is kept aside so a refusal can put it back exactly.
        string jobPath = JobPath(taskName);
        string kept = jobPath + ".kept";
        string token = Guid.NewGuid().ToString("N");
        try
        {
            Directory.CreateDirectory(ScheduledScriptsDirectory());
            if (File.Exists(jobPath)) File.Copy(jobPath, kept, overwrite: true);
            var job = new ScheduledRun.Job(taskName, workingFolder, courseCode, section,
                new DateTimeOffset(when).ToUniversalTime(),
                promised.Select(DeployCommand.DestinationDescription).ToList(),
                token);
            File.WriteAllText(jobPath, ScheduledRun.WriteJob(job));
        }
        catch (Exception error)
        {
            PutBack(jobPath, kept);
            return CouldNotBeSet(courseCode, section, when, replacing, replacedMoment,
                $"The scheduled deploy could not be written down: {error.Message}");
        }

        // Registered from XML (ruling 1): schtasks /Create /SC ONCE leaves
        // DisallowStartIfOnBatteries and StopIfGoingOnBatteries TRUE and no
        // StartWhenAvailable, so a laptop on battery never published and one
        // unplugged mid-run was killed mid-upload. The XML also carries the
        // moment in one invariant form, so no locale date format is guessed,
        // and keeps the command short (the task's NAME, not the job's path).
        string xmlPath = Path.Combine(Path.GetTempPath(), $"plantoir-task-{Guid.NewGuid():N}.xml");
        var (exitCode, output) = (1, "");
        try
        {
            File.WriteAllText(xmlPath, TaskXml(runner, taskName, when, token), System.Text.Encoding.Unicode);
            (exitCode, output) = Run(["/Create", "/F", "/TN", taskName, "/XML", xmlPath]);
        }
        catch (Exception error) { output = error.Message; }
        finally { try { File.Delete(xmlPath); } catch { } }

        if (exitCode != 0)
        {
            PutBack(jobPath, kept);
            return CouldNotBeSet(courseCode, section, when, replacing, replacedMoment,
                $"Windows would not accept the scheduled task: {output.Trim()}");
        }
        try { File.Delete(kept); } catch { }

        // Set before #309 under the old name: retired now that the new one
        // stands, or the section would deploy twice.
        if (existing is { } old && old.Name != taskName) Cancel(old);

        // Recorded only once the new one is accepted, from the reading taken
        // before the old one went — and not for the same minute, which
        // replaces nothing a teacher could tell apart.
        if (replacedMoment is { } was && !SameMinute(was, when))
            ActivityTrail.Note(ActivityTrail.Event.ScheduledDeployReplaced,
                $"replaced the deploy set for {Stamp(was)} with one set for {Stamp(when)}", courseCode, section);

        ForgetTheList();
        return null;
    }

    // ---- What a schedule replaces (#261) ------------------------------------

    /// <summary>
    /// The scheduled deploy that setting this section in this folder would
    /// replace, or null.
    /// </summary>
    /// <remarks>
    /// <para><b>Read by NAME, across every task on the computer</b>, because
    /// that is what <see cref="Schedule"/> overwrites: <c>/Create /F</c> on
    /// <see cref="NameFor"/>, plus this folder's task from before #309 under
    /// the old name, which it retires. The trap #261 names is copying the
    /// cancel path's folder filter: <see cref="For"/> finds a task only through
    /// the folder its JOB names, and a task whose job file cannot be read
    /// belongs to no folder there — yet <c>/Create /F</c> still replaces it,
    /// silently. Asking by name cannot miss it.</para>
    ///
    /// <para>Since #309 names carry the folder, a task another working folder
    /// set for the same code is a DIFFERENT task and is not replaced — so it is
    /// not named here either. That is the mac's #237, closed on this side by
    /// construction.</para>
    /// </remarks>
    public static ScheduledTask? WhatSchedulingReplaces(string workingFolder, string courseCode, int section)
    {
        string name = NameFor(courseCode, section, workingFolder);
        return All().FirstOrDefault(task => task.Name == name) ?? For(workingFolder, courseCode, section);
    }

    /// <summary>
    /// The moment the deploy a schedule would replace is set for — or null
    /// when there is none, it is set for the same minute, or it has passed,
    /// which are the three cases in which nothing is said.
    /// </summary>
    public static DateTime? MomentItWouldReplace(string workingFolder, string courseCode, int section,
                                                 DateTime when, DateTime now)
    {
        if (WhatSchedulingReplaces(workingFolder, courseCode, section) is not { } task) return null;
        if (MomentOf(task) is not { } at) return null;
        if (at <= now || SameMinute(at, when)) return null;
        return at;
    }

    /// <summary>What Windows says the task will run at, or what its job was set for.</summary>
    private static DateTime? MomentOf(ScheduledTask task) =>
        task.NextRun ?? ScheduledRun.ReadJob(JobPath(task.Name))?.ScheduledFor?.LocalDateTime;

    private static bool SameMinute(DateTime a, DateTime b) =>
        a.Date == b.Date && a.Hour == b.Hour && a.Minute == b.Minute;

    private static string Stamp(DateTime moment) =>
        moment.ToString("yyyy-MM-dd HH:mm", System.Globalization.CultureInfo.InvariantCulture);

    /// <summary>
    /// Record a schedule that could not be set, and tell apart what the
    /// failure LEFT (#261). A failed write here happens before the old task is
    /// touched — <c>/Create /F</c> is refused whole, and the old job is put
    /// back — so the old one normally still stands, and the sentence says so.
    /// If it has gone anyway, that is recorded as "turned off", never claimed
    /// to stand.
    /// </summary>
    private static string CouldNotBeSet(string courseCode, int section, DateTime when,
                                        ScheduledTask? replacing, DateTime? replacedMoment, string problem)
    {
        ForgetTheList();
        string line = $"could not set a deploy for {Stamp(when)}";
        string said = problem;
        if (replacing is not null)
        {
            if (Exists(replacing.Name))
            {
                string was = replacedMoment is { } at ? $" set for {Stamp(at)}" : "";
                line += $"; the deploy already{was} still stands";
                if (replacedMoment is { } moment)
                    said += $" The deploy already set for {moment:dddd d MMMM, h:mm tt} still stands.";
            }
            else
            {
                ActivityTrail.Note(ActivityTrail.Event.ScheduledDeployTurnedOff,
                    "turned off: a new deploy was set in its place and could not be accepted" +
                    (replacedMoment is { } gone ? $"; it had been set for {Stamp(gone)}" : ""),
                    courseCode, section);
            }
        }
        ActivityTrail.Note(ActivityTrail.Event.ScheduledDeployCouldNotBeSet, line, courseCode, section);
        return said;
    }

    /// <summary>
    /// How Task Scheduler starts the run: Plantoir itself, told which task it
    /// is — by its own NAME, from which <see cref="JobPath"/> finds the job, so
    /// the run never recomputes a name (#309's trap). Quoted: names and install
    /// paths hold spaces.
    /// </summary>
    internal static string TaskRunCommand(string runner, string taskName) =>
        $"\"{runner}\" {RunArgument} \"{taskName}\"";

    /// <summary>
    /// Which Plantoir.exe a task should start. The app scheduling from its own
    /// window is that program; plantoir-mcp (a separate executable) is told by
    /// the app that started it (<c>PLANTOIR_APP_PATH</c>), or finds the app
    /// beside itself or where it is installed. Null when none can be found —
    /// then nothing is scheduled rather than a task that can never run.
    /// </summary>
    public static string? RunnerExecutable()
    {
        if (RunnerExecutableForTests is { } forTests) return forTests;

        string? fromTheApp = Environment.GetEnvironmentVariable("PLANTOIR_APP_PATH");
        if (!string.IsNullOrWhiteSpace(fromTheApp) && File.Exists(fromTheApp)) return fromTheApp;

        string? self = Environment.ProcessPath;
        if (self is not null && string.Equals(Path.GetFileName(self), "Plantoir.exe", StringComparison.OrdinalIgnoreCase))
            return self;

        string beside = Path.Combine(AppContext.BaseDirectory, "Plantoir.exe");
        if (File.Exists(beside)) return beside;

        string installed = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs", "Plantoir", "Plantoir.exe");
        return File.Exists(installed) ? installed : null;
    }

    /// <summary>Stands in for <see cref="RunnerExecutable"/> in tests.</summary>
    internal static string? RunnerExecutableForTests;

    // ---- Finding a folder's tasks ------------------------------------------

    /// <summary>One scheduled deploy, as Windows and its own files describe it.</summary>
    /// <param name="Name">The task's real name — the one it is cancelled by.</param>
    /// <param name="WorkingFolder">The working folder its job or wrapper names; null when neither can be read.</param>
    /// <param name="NextRun">What Windows says, or null.</param>
    public sealed record ScheduledTask(string Name, string? WorkingFolder, string CourseCode, int Section, DateTime? NextRun)
    {
        /// <summary>Set before #309, under the folder-less name.</summary>
        public bool HasTheOldName => !Regex.IsMatch(Name, @" [0-9a-f]{8}$");
    }

    /// <summary>
    /// Every Plantoir scheduled deploy on this computer — any working folder.
    /// One <c>schtasks /Query</c> for the lot, remembered for two seconds,
    /// because the sidebar asks for each section as it draws.
    /// </summary>
    public static IReadOnlyList<ScheduledTask> All()
    {
        lock (ListGate)
        {
            if (_list is { } fresh && DateTime.UtcNow - _listTakenAt < TimeSpan.FromSeconds(2)) return fresh;
        }

        var found = new List<ScheduledTask>();
        var (exitCode, output) = Run(["/Query", "/FO", "CSV", "/NH"]);
        if (exitCode == 0)
        {
            foreach (string line in output.Split('\n'))
            {
                var fields = CsvFields(line.Trim());
                if (fields.Count < 2) continue;
                string name = fields[0].TrimStart('\\');
                if (!name.StartsWith(NamePrefix, StringComparison.Ordinal)) continue;
                if (found.Any(task => task.Name == name)) continue;
                DateTime? nextRun = DateTime.TryParse(fields[1], out var when) ? when : null;
                if (Describe(name, nextRun) is { } task) found.Add(task);
            }
        }

        lock (ListGate)
        {
            _list = found;
            _listTakenAt = DateTime.UtcNow;
        }
        return found;
    }

    private static readonly object ListGate = new();
    private static List<ScheduledTask>? _list;
    private static DateTime _listTakenAt;

    /// <summary>Forget the remembered list — after anything that changes it.</summary>
    public static void ForgetTheList()
    {
        lock (ListGate) { _list = null; }
    }

    /// <summary>
    /// This working folder's scheduled deploys, and only this folder's: the
    /// same course code in last year's working folder is a different alarm
    /// (<c>scheduledDeployCancellation.scopedToOneWorkingFolder</c>).
    /// </summary>
    public static IReadOnlyList<ScheduledTask> InFolder(string workingFolder)
    {
        string mine = FolderContainers.FolderIdentifier(workingFolder);
        return All().Where(task => task.WorkingFolder is { } folder
                                   && FolderContainers.FolderIdentifier(folder) == mine).ToList();
    }

    /// <summary>
    /// This folder's scheduled deploy of one section, or null. A course code is
    /// compared upper-cased — the form a task set before #309 keeps it in.
    /// When a new and an old one both stand, the new one answers.
    /// </summary>
    public static ScheduledTask? For(string workingFolder, string courseCode, int section) =>
        InFolder(workingFolder)
            .Where(task => SameCode(task.CourseCode, courseCode) && task.Section == section)
            .OrderBy(task => task.HasTheOldName)
            .FirstOrDefault();

    /// <summary>When this folder's deploy of a section will run, or null if none is set.</summary>
    public static DateTime? NextRun(string workingFolder, string courseCode, int section) =>
        For(workingFolder, courseCode, section)?.NextRun;

    internal static bool SameCode(string a, string b) =>
        string.Equals(a.ToUpperInvariant(), b.ToUpperInvariant(), StringComparison.Ordinal);

    /// <summary>
    /// Which folder, course and section a task is about — read off its own job,
    /// or for a task set before the update, off the wrapper it runs, or last
    /// of all off its name (which names no folder, so such a task belongs to
    /// none and is left alone).
    /// </summary>
    private static ScheduledTask? Describe(string name, DateTime? nextRun)
    {
        if (ScheduledRun.ReadJob(JobPath(name)) is { } job)
            return new ScheduledTask(name, job.WorkingFolder, job.CourseCode, job.Section, nextRun);

        var named = Regex.Match(name, @"^Plantoir deploy (.+) section (\d+)( [0-9a-f]{8})?$");
        if (!named.Success) return null;
        string code = named.Groups[1].Value;
        int section = int.Parse(named.Groups[2].Value);

        var (folder, said) = WhatTheWrapperNames(name);
        return new ScheduledTask(name, folder, said ?? code, section, nextRun);
    }

    /// <summary>
    /// The working folder and course code a wrapper written before bundle 3
    /// names — how a task set under the old scheme is tied to its folder.
    /// </summary>
    private static (string? Folder, string? Course) WhatTheWrapperNames(string taskName)
    {
        try
        {
            string wrapper = WrapperScriptPath(taskName);
            if (!File.Exists(wrapper)) return (null, null);
            string text = File.ReadAllText(wrapper);
            var where = Regex.Match(text, @"\$toolchainScripts = Join-Path '((?:[^']|'')*)' '\.toolchain\\scripts'");
            var said = Regex.Match(text, @"@\(\$kind, \$where, '((?:[^']|'')*)', '(\d+)'\)");
            return (where.Success ? where.Groups[1].Value.Replace("''", "'") : null,
                    said.Success ? said.Groups[1].Value.Replace("''", "'") : null);
        }
        catch { return (null, null); }
    }

    /// <summary>
    /// The working folder a task set before #309 for this course and section
    /// runs in, read off its wrapper, or null when that cannot be known.
    /// </summary>
    public static string? WorkingFolderOfTheOldTask(string courseCode, int section) =>
        WhatTheWrapperNames(OldNameFor(courseCode, section)).Folder;

    /// <summary>The fields of one line of schtasks' CSV.</summary>
    private static List<string> CsvFields(string line)
    {
        var fields = new List<string>();
        foreach (Match field in Regex.Matches(line, "\"((?:[^\"]|\"\")*)\""))
            fields.Add(field.Groups[1].Value.Replace("\"\"", "\""));
        return fields;
    }

    // ---- Where the files live -------------------------------------------------

    /// <summary>
    /// Where the job files and wrapper scripts are written —
    /// %LOCALAPPDATA%\Plantoir\scheduled, not a temp folder, because the
    /// task may fire hours or days later and a temp-folder sweep must never
    /// be the reason an overnight deploy silently does nothing.
    /// </summary>
    public static string ScheduledScriptsDirectory() =>
        ScheduledDirectoryForTests ?? Plantoir.Core.Models.AppDataRoot.Combine("scheduled");

    /// <summary>
    /// Moves the job files and wrappers into a test's own folder. Process-wide,
    /// so a class that sets it belongs in the SharedActivityState collection
    /// and must put it back.
    /// </summary>
    internal static string? ScheduledDirectoryForTests;

    internal static string WrapperScriptPath(string taskName) =>
        Path.Combine(ScheduledScriptsDirectory(), SafeName(taskName) + ".ps1");

    /// <summary>The job a task hands to Plantoir: which folder, course and section, and for when.</summary>
    public static string JobPath(string taskName) =>
        Path.Combine(ScheduledScriptsDirectory(), SafeName(taskName) + ".job.json");

    /// <summary>Single-quotes a value for PowerShell, escaping any embedded quote.</summary>
    private static string PsQuote(string value) => "'" + value.Replace("'", "''") + "'";

    /// <summary>
    /// Writes the wrapper: fingerprint the section first (via the bundled
    /// Python — see <c>scripts/section_fingerprint.py</c>), then one
    /// un-chained invocation of deploy.ps1 per destination (one destination
    /// failing must not stop the others from being tried), then — only if
    /// every destination succeeded, and only if the fingerprint could be
    /// taken — a sentinel file for <see cref="ScheduledDeployCompletion"/> to
    /// pick up and apply the next time the app runs. Returns the script's
    /// path, or null if it could not be written.
    /// </summary>
    /// <summary>
    /// Internal rather than private so the suite can read the script this
    /// writes. There is no runner behind a generated wrapper — it is executed
    /// by Task Scheduler at 6 a.m. with nobody watching — so the only gate
    /// available is asserting the TEXT, and the ordering inside it is
    /// load-bearing (see the health-capture block).
    /// </summary>
    internal static string? WriteWrapperScript(
        string taskName, string workingFolder, string launcherPath, string courseCode, int section,
        string courseDirectory, IReadOnlyList<string> excludedSelfPublishingSubpaths,
        IReadOnlyList<CourseConfiguration.DeployDestination> destinations, string cloudflareAccountID)
    {
        try
        {
            Directory.CreateDirectory(ScheduledScriptsDirectory());

            string excludedArray = string.Join(", ", excludedSelfPublishingSubpaths.Select(PsQuote));
            string destinationTypesArray = string.Join(", ", destinations.Select(d => PsQuote(d.Type)));
            string destinationNamesArray = string.Join(", ", destinations.Select(d => PsQuote(DeployCommand.DestinationDescription(d))));

            // Where this run says how it turned out, and where a run that got
            // through clears an earlier failure. Computed once, outside every
            // branch that writes it.
            //
            // BAKED from AppDataRoot at write time, where $healthDir and
            // $pendingDir in this same script resolve $env:LOCALAPPDATA at RUN
            // time. Identical in production, and baking is the correct one of
            // the two here: the app READS this folder through AppDataRoot, so a
            // run started with --state-dir writes and reads the same place. The
            // other two are the ones that would disagree with the app under
            // that flag — a third shape of the leak AppDataRoot's own doc
            // comment warns about, named here rather than quietly added to.
            string outcomeDir = ScheduledPublishOutcome.Directory();

            var lines = new List<string>
            {
                "# Generated by Plantoir for a scheduled deploy.",
                "# See TaskScheduling.WriteWrapperScript and documentation/05-build-pipeline.md,",
                "# \"A scheduled deploy needs its own path to the same record\".",
                "",
                "# ---- How this run turned out --------------------------------------------",
                "# The app is CLOSED while this runs, so a run that leaves nothing behind is",
                "# indistinguishable from one that never happened — in both directions. The",
                "# app reads this the next time it opens and tells the teacher.",
                "#",
                "# Four lines: what happened, where, the course, the section. Destinations",
                "# are joined with '|', the one character Windows forbids in a path, and the",
                "# APP turns the list into a sentence — MultiDestinationDeployRunner's",
                "# JoinedWithAnd already knows how to say one out loud, and a second copy of",
                "# that in generated shell is a copy nothing tests.",
                "#",
                "# The course and section are IN the record rather than read back off its",
                "# filename, which HealthRecordName has already flattened: a code containing",
                "# anything but letters and digits would come back as a course that does not",
                "# exist, and it is the trail line that would say so.",
                "#",
                "# NEVER the question's own text or the launcher's error: those come from a",
                "# console nobody is watching, and a line naming a credential prompt would",
                "# put a teacher's own words where the app can repeat them.",
                $"$destinationNames = @({destinationNamesArray})",
                $"$outcomeDir = {PsQuote(outcomeDir)}",
                $"$outcomeFile = (Join-Path $outcomeDir {PsQuote(HealthRecordName(courseCode, section, workingFolder))})",
                "function Write-Outcome([string]$kind, [string]$where) {",
                "  try {",
                "    New-Item -ItemType Directory -Force -Path $outcomeDir | Out-Null",
                // Assembled OUTSIDE the watched folder and moved in (#218): the
                // app's watcher fires on the create, and a record written in
                // place can be read empty at that instant (the mac: 0 of 40).
                "    $assembling = Join-Path (Split-Path -Parent $outcomeDir) ('outcome-' + [Guid]::NewGuid().ToString('N') + '.partial')",
                $"    Set-Content -LiteralPath $assembling -Value @($kind, $where, {PsQuote(courseCode)}, {PsQuote(section.ToString())}) -Encoding utf8",
                "    Move-Item -LiteralPath $assembling -Destination $outcomeFile -Force",
                // The mark saying this record's trail line has been written
                // belongs to the PREVIOUS run. Left behind, a record written
                // within the same second as that mark would be read as already
                // said, and the teacher would get no line for tonight.
                $"    Remove-Item -LiteralPath ($outcomeFile + {PsQuote(ScheduledPublishOutcome.NotedSuffix)}) -Force -ErrorAction SilentlyContinue",
                "  } catch { }",
                "}",
                "",
                "# ---- Fingerprint the section BEFORE anything runs -----------------------",
                "# Matches the mac's launchd path: the fingerprint is taken right before the",
                "# deploy actually happens, not when the teacher scheduled it, so an edit made",
                "# in between still shows up correctly either way.",
                "$fingerprint = $null",
                "try {",
                $"  $nativeRuntime = $env:PLANTOIR_RUNTIME",
                "  if (-not $nativeRuntime) {",
                "    $appRuntime = Join-Path $env:LOCALAPPDATA 'Programs\\Plantoir\\runtime'",
                "    if (Test-Path (Join-Path $appRuntime 'manifest.json')) { $nativeRuntime = $appRuntime }",
                "  }",
                "  if ($nativeRuntime) {",
                "    $pythonExe = Join-Path $nativeRuntime 'python\\python.exe'",
                $"    $toolchainScripts = Join-Path {PsQuote(workingFolder)} '.toolchain\\scripts'",
                $"    $scriptsDir = if (Test-Path $toolchainScripts) {{ $toolchainScripts }} else {{ Join-Path {PsQuote(workingFolder)} 'scripts' }}",
                "    $fpScript = Join-Path $scriptsDir 'section_fingerprint.py'",
                "    if ((Test-Path $pythonExe) -and (Test-Path $fpScript)) {",
                // --rule BEFORE the positional arguments (the only place the
                // script reads it), and the rule goes into the sentinel so the
                // app records the stamp under the rule the value was taken
                // under (#358 / mac #330).
                $"      $fpArgs = @('--rule', '{SectionPublishState.CurrentRule}', {PsQuote(courseDirectory)}, {section}{(excludedArray.Length > 0 ? ", " + excludedArray : "")})",
                "      $fpOutput = & $pythonExe $fpScript @fpArgs 2>$null",
                "      if ($LASTEXITCODE -eq 0 -and $fpOutput) { $fingerprint = ([string]$fpOutput).Trim() }",
                "    }",
                "  }",
                "} catch { $fingerprint = $null }",
                "",
                "# ---- Build first, always -----------------------------------------------",
                "# A scheduled deploy had NO build step at all: it published whatever",
                "# happened to be in the builds folder, however old, and if nothing was",
                "# there it failed. The mac's launchd script has always tested freshness",
                "# and rebuilt when stale; this side simply never did.",
                "#",
                "# Unconditionally, rather than repeating the freshness test in shell.",
                "# This runs while the teacher is asleep, so a minute of rebuilding that",
                "# was not strictly needed costs nothing, and a freshness test written a",
                "# THIRD time — after the app's and the launcher's — is a third thing to",
                "# drift. --build-only also stops any preview still serving this section,",
                "# so it cannot overwrite what is about to go out.",
                "#",
                "# The build's output is CAPTURED, because the folder checks run inside it",
                "# and print PLANTOIR_HEALTH: lines that nothing would otherwise read: this",
                "# runs with the app closed, so the console they go to is gone by morning.",
                "# Per run, into a file deleted immediately afterwards — the mac reads its",
                "# findings out of a launchd log opened with O_APPEND and had to record the",
                "# log's SIZE beforehand to avoid re-finding last week's markers every",
                "# night. A per-run capture cannot have that bug at all.",
                "#",
                "# If the capture cannot be set up, the build runs plainly. Losing the",
                "# findings is a pity; losing the publish is not acceptable.",
                "$healthDir = $null",
                "$buildLog = $null",
                "$buildErrLog = $null",
                "try {",
                $"  $healthDir = Join-Path $env:LOCALAPPDATA {PsQuote(Path.Combine("Plantoir", "scheduled", "folder-problems"))}",
                "  New-Item -ItemType Directory -Force -Path $healthDir | Out-Null",
                $"  $buildLog = Join-Path $healthDir ({PsQuote(SafeName(taskName))} + '-' + [Guid]::NewGuid().ToString('N') + '.log')",
                "} catch { $healthDir = $null; $buildLog = $null }",
                "",
                "# Redirected by the OPERATING SYSTEM, into a child process — never",
                "# through a PowerShell pipeline. `preview.ps1` sets",
                "# $ErrorActionPreference = 'Stop', and in Windows PowerShell 5.1 merging a",
                "# native command's stderr into the pipeline (`2>&1`, `*>&1`, even",
                "# `2>$null`) turns the first stderr LINE into a TERMINATING",
                "# NativeCommandError that propagates out of the callee and kills this",
                "# wrapper with it: no exit code, no scan, no deploy, and nothing said.",
                "# The build inherits stderr to node and npm, and any Python traceback",
                "# lands there too — which is exactly the failing run whose findings",
                "# matter most. Measured on 5.1.26100: a piped callee died at its first",
                "# stderr line and took its caller with it, where the same callee run",
                "# plainly finished and returned 5.",
                "#",
                "# Start-Process also gives an exit code that does not depend on",
                "# $LASTEXITCODE surviving a pipeline. stdout and stderr must go to",
                "# DIFFERENT files (Start-Process refuses one file for both); the markers",
                "# are on stdout, and the error file is scanned too rather than assumed",
                "# empty.",
                "if ($buildLog) {",
                "  $buildErrLog = $buildLog + '.err'",
                // Built as a variable rather than continued across lines: a
                // backtick continuation in generated shell is one stray trailing
                // space away from silently splitting the command.
                // ONE STRING, with the quoting done here — not an ARRAY.
                // Start-Process joins an array with spaces and quotes nothing,
                // so a working folder whose name contains a space (every
                // Desktop folder, most OneDrive paths, and the machine this was
                // written on has one called "scheduled deploy test") is split
                // at the space and powershell.exe reports "Processing -File
                // 'C:\...\scheduled' failed because the file does not have a
                // '.ps1' extension". Measured: exit -196608, no build, no
                // findings, no deploy — every night, silently.
                "  $buildArgs = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File \"' + " +
                    $"{PsQuote(Path.Combine(workingFolder, "preview.ps1"))} + '\" \"' + {PsQuote(courseCode)} + '\" \"' + {PsQuote(section.ToString())} + '\" --build-only --non-interactive'",
                "  $proc = Start-Process -FilePath 'powershell.exe' -ArgumentList $buildArgs -Wait -PassThru -NoNewWindow -RedirectStandardOutput $buildLog -RedirectStandardError $buildErrLog",
                "  $buildExitFromChild = $proc.ExitCode",
                "} else {",
                $"  & {PsQuote(Path.Combine(workingFolder, "preview.ps1"))} {PsQuote(courseCode)} {PsQuote(section.ToString())} --build-only --non-interactive",
                "  $buildExitFromChild = $null",
                "}",
                "# Saved AT ONCE. Everything below runs commands of its own, and the guard",
                "# that decides whether anything is published must test THIS build's code.",
                "# The captured path takes it from the child process rather than from",
                "# $LASTEXITCODE, which is one fewer thing that has to survive.",
                "if ($null -ne $buildExitFromChild) { $buildExit = $buildExitFromChild } else { $buildExit = $LASTEXITCODE }",
                "",
                "# ---- What the build said about the folders --------------------------------",
                "# BEFORE the failure guard, deliberately. Since 2026-09-01 a section with no",
                "# index.md exits NON-ZERO from --build-only, and that is exactly the run",
                "# whose findings the teacher most needs in the morning: scanning after the",
                "# guard would say nothing about the one failure that explains itself.",
                "#",
                "# The lines are copied VERBATIM and parsed in C# with the same parser a live",
                "# build uses. No JSON is interpreted in shell.",
                "if ($buildLog -and (Test-Path -LiteralPath $buildLog)) {",
                "  try {",
                $"    $healthFile = Join-Path $healthDir {PsQuote(HealthRecordName(courseCode, section, workingFolder))}",
                "    $scanned = @($buildLog)",
                "    if ($buildErrLog -and (Test-Path -LiteralPath $buildErrLog)) { $scanned += $buildErrLog }",
                "    # -Encoding UTF8 because OS-level redirection writes the child's own",
                "    # bytes with no BOM, and Select-String would otherwise read them as",
                "    # ANSI and mangle any non-ASCII inside a sentence.",
                "    # PLANTOIR_DATED: too (#279): the pages this build rewrote with their",
                "    # class's date, which the app names on the trail when it reads this.",
                "    $markers = @(Select-String -LiteralPath $scanned -SimpleMatch 'PLANTOIR_HEALTH:','PLANTOIR_DATED:' -Encoding UTF8 | ForEach-Object { $_.Line })",
                "    if ($markers.Count -gt 0) {",
                "      Set-Content -LiteralPath $healthFile -Value $markers -Encoding utf8",
                "    } else {",
                "      # Nothing wrong this time: clear anything an earlier run left, so a",
                "      # problem the teacher has since put right stops being reported.",
                "      Remove-Item -LiteralPath $healthFile -Force -ErrorAction SilentlyContinue",
                "    }",
                "  } catch { }",
                "  Remove-Item -LiteralPath $buildLog -Force -ErrorAction SilentlyContinue",
                "  if ($buildErrLog) { Remove-Item -LiteralPath $buildErrLog -Force -ErrorAction SilentlyContinue }",
                "}",
                "",
                "# A build that stopped is a publish that never started, and the teacher",
                "# hears about it for the same reason they hear about a publish that",
                "# stopped: nothing else will tell them. Exit 3 is preview.ps1's refusal —",
                "# it asked something and nobody was here — and is told apart from an",
                "# ordinary build failure because the two need different sentences: one",
                "# has a question to answer, the other has something to look at.",
                "#",
                "# Neither names a destination, because none was reached (#137, #297).",
                "# ANY code but 3 is a build that did not finish - never only 1: a",
                "# launcher that could not be run at all exits with another code.",
                "if ($buildExit -eq 3) {",
                $"  Write-Outcome {PsQuote(ScheduledPublishOutcome.Word(ScheduledPublishOutcome.Kind.BuildNeededAnAnswer))} ''",
                "  Write-Host 'Building this section needed an answer, so nothing was published.'",
                "  exit 1",
                "} elseif ($buildExit -ne 0) {",
                $"  Write-Outcome {PsQuote(ScheduledPublishOutcome.Word(ScheduledPublishOutcome.Kind.BuildDidNotFinish))} ''",
                "  Write-Host 'Could not build this section, so nothing was published.'",
                "  exit 1",
                "}",
                "",
                "# ---- Deploy to every destination — un-chained, on purpose ---------------",
                "$allSucceeded = $true",
                // Whether anything has already been recorded about this run.
                // Kept across the whole loop so the record survives a later
                // destination succeeding, and so the FIRST destination that
                // stopped is the one reported — across both kinds of stopping,
                // not one flag each. A course can publish to several places and
                // only one may have gone wrong; overwriting would tell the
                // teacher about the last thing that went wrong rather than the
                // first.
                "$alreadyRecorded = $false",
            };

            foreach (var destination in destinations)
            {
                // `unattended: true` is what puts --non-interactive on this
                // line, and asking DeployCommand for it is the point: the flag
                // used to be appended here as text, which made this a SECOND
                // place that had to agree with app-rules.json ->
                // deployArguments about where in the argument list it goes. The
                // contract now carries the scheduled shape as its own cases,
                // and one function answers them.
                //
                // Without the flag this line is the whole defect: deploy.py's
                // site-name prompt either blocks for ever (measured at 45
                // minutes) or takes its default silently and publishes the
                // teacher's site to an address nobody chose.
                var arguments = DeployCommand.Arguments(
                    courseCode, section, destination, cloudflareAccountID, unattended: true);
                string quotedArgs = string.Join(" ", arguments.Select(PsQuote));

                if (destination.Type == "cloudflare_pages")
                {
                    // CAPTURED, the build leg's way (#395): deploy.py prints
                    // PLANTOIR_CLOUDFLARE_REMADE: when it had to make the
                    // section's Cloudflare project again, and with the app
                    // closed nothing else would read it. Start-Process with
                    // OS-level redirection, never a pipeline (see the build
                    // leg's comment: a 5.1 pipeline turns a stderr line into a
                    // terminating error). The marker lines are APPENDED to the
                    // section's record, which ScheduledHealthFindings reads into
                    // the trail's 'cloudflare project made again'. Only this
                    // destination can print the marker, so the others run as
                    // before. If the capture cannot be set up, the leg runs plainly.
                    string commandLineArgs = string.Join(" ", arguments.Select(a => "\"" + a + "\""));
                    lines.Add("if ($healthDir) {");
                    lines.Add($"  $deployLog = Join-Path $healthDir ({PsQuote(SafeName(taskName))} + '-deploy-' + [Guid]::NewGuid().ToString('N') + '.log')");
                    lines.Add($"  $deployArgs = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File \"' + {PsQuote(launcherPath)} + '\" ' + {PsQuote(commandLineArgs)}");
                    lines.Add("  $legProc = Start-Process -FilePath 'powershell.exe' -ArgumentList $deployArgs -Wait -PassThru -NoNewWindow -RedirectStandardOutput $deployLog -RedirectStandardError ($deployLog + '.err')");
                    lines.Add("  $legExit = $legProc.ExitCode");
                    lines.Add("  try {");
                    lines.Add($"    $remadeRecord = Join-Path $healthDir {PsQuote(HealthRecordName(courseCode, section, workingFolder))}");
                    lines.Add($"    $remade = @(Select-String -LiteralPath @($deployLog, ($deployLog + '.err')) -SimpleMatch {PsQuote(CloudflareProjectRemade.Marker)} -Encoding UTF8 -ErrorAction SilentlyContinue | ForEach-Object {{ $_.Line }})");
                    lines.Add("    if ($remade.Count -gt 0) { Add-Content -LiteralPath $remadeRecord -Value $remade -Encoding utf8 }");
                    lines.Add("  } catch { }");
                    lines.Add("  Remove-Item -LiteralPath $deployLog, ($deployLog + '.err') -Force -ErrorAction SilentlyContinue");
                    lines.Add("} else {");
                    lines.Add($"  & {PsQuote(launcherPath)} {quotedArgs}");
                    lines.Add("  $legExit = $LASTEXITCODE");
                    lines.Add("}");
                }
                else
                {
                    lines.Add($"& {PsQuote(launcherPath)} {quotedArgs}");
                    lines.Add("$legExit = $LASTEXITCODE");
                }

                // Exit 3 is deploy.py's NEEDS_AN_ANSWER and means that alone.
                // Tested BEFORE the general non-zero branch, because it is also
                // non-zero: a run that needed an answer did not succeed either.
                //
                // Both branches record, and both are behind ONE
                // $alreadyRecorded flag rather than one flag each. That is what
                // makes "the first destination that stopped wins" true across
                // the two KINDS as well as within each: Netlify stopping for a
                // question and the folder leg then failing ordinarily must
                // leave the question, which is the thing the teacher can act
                // on, rather than the later and vaguer complaint.
                //
                // An ordinary failure was recorded NOWHERE until 2026-09-09, so
                // a revoked token overnight was exactly as silent as the bug
                // this whole feature was built to end. Russell's reasoning: the
                // SILENCE is the complaint, not the cause.
                string name = PsQuote(DeployCommand.DestinationDescription(destination));
                string question = PsQuote(
                    ScheduledPublishOutcome.Word(ScheduledPublishOutcome.Kind.NeededAnAnswer));
                string failure = PsQuote(
                    ScheduledPublishOutcome.Word(ScheduledPublishOutcome.Kind.DidNotFinish));

                lines.Add("if ($legExit -eq 3) {");
                lines.Add("  $allSucceeded = $false");
                lines.Add("  if (-not $alreadyRecorded) {");
                lines.Add("    $alreadyRecorded = $true");
                lines.Add($"    Write-Outcome {question} {name}");
                lines.Add("  }");
                lines.Add("} elseif ($legExit -ne 0) {");
                lines.Add("  $allSucceeded = $false");
                lines.Add("  if (-not $alreadyRecorded) {");
                lines.Add("    $alreadyRecorded = $true");
                lines.Add($"    Write-Outcome {failure} {name}");
                lines.Add("  }");
                lines.Add("}");
            }

            // A run that GOT THROUGH — every destination, exit zero — and only
            // AFTER every destination has run, replaces whatever an earlier
            // night left with the good news. One write rather than a delete
            // followed by a write: it is the same file, and there is no moment
            // in between where a section that published perfectly well has no
            // record at all.
            //
            // Two things were wrong here in turn before this, and both were the
            // same mistake made smaller. Clearing inside the LOOP meant a course
            // publishing to two places whose Netlify leg stopped for a question
            // and whose folder leg then succeeded had the note deleted by the
            // second leg, and the teacher was never told why the first did not
            // go out. Then clearing on "nothing needed an answer" meant an
            // ORDINARY failure cleared it too: Monday stops for a question and
            // leaves a note, Tuesday the token is revoked and every leg exits 1,
            // Monday's note is deleted, and the teacher was told about neither
            // night. $allSucceeded is the condition every sentence describing
            // this already used; the code has agreed with them since 2026-09-09.
            lines.Add("");
            lines.Add("if ($allSucceeded) {");
            lines.Add($"  Write-Outcome {PsQuote(ScheduledPublishOutcome.Word(ScheduledPublishOutcome.Kind.Succeeded))} ($destinationNames -join '|')");
            lines.Add("}");

            lines.AddRange(new[]
            {
                "",
                "# ---- Record what went out, for the app to pick up ------------------------",
                "if ($allSucceeded -and $fingerprint) {",
                $"  $pendingDir = Join-Path $env:LOCALAPPDATA {PsQuote(Path.Combine("Plantoir", "scheduled", "pending"))}",
                "  New-Item -ItemType Directory -Force -Path $pendingDir | Out-Null",
                "  $sentinel = [ordered]@{",
                $"    courseCode = {PsQuote(courseCode)}",
                $"    sectionNumber = {section}",
                $"    courseDirectory = {PsQuote(courseDirectory)}",
                "    fingerprint = $fingerprint",
                $"    fingerprintRule = {SectionPublishState.CurrentRule}",
                $"    destinationTypes = @({destinationTypesArray})",
                "    destinationNames = $destinationNames",
                "    completedAtUtc = (Get-Date).ToUniversalTime().ToString('o')",
                "  } | ConvertTo-Json",
                $"  $sentinelPath = Join-Path $pendingDir ({PsQuote(SafeName(taskName))} + '-' + [Guid]::NewGuid().ToString('N') + '.json')",
                "  Set-Content -LiteralPath $sentinelPath -Value $sentinel -Encoding utf8",
                "}",
            });

            string scriptPath = WrapperScriptPath(taskName);
            File.WriteAllLines(scriptPath, lines);
            return scriptPath;
        }
        catch
        {
            return null;
        }
    }

    /// <summary>
    /// The arguments <see cref="ScheduledRun"/> hands <c>powershell.exe</c> to
    /// run the wrapper it has just written.
    ///
    /// <para><b>-NonInteractive is load-bearing, not tidiness.</b> Nobody is
    /// there to answer a question at 6 a.m. Without it, a `Read-Host` in
    /// anything the wrapper calls simply BLOCKS: the run sits at an invisible
    /// prompt until Task Scheduler's own limit (three days, by default), and
    /// the teacher's site is never updated and nothing says why. With it,
    /// `Read-Host` throws instead, the wrapper exits non-zero, and the run
    /// fails visibly.</para>
    ///
    /// <para>The question that made this real: <c>preview.ps1</c> asks
    /// "Continue anyway?" when the section is not listed in
    /// <c>course_config.json</c> — which is exactly the state a course is left
    /// in when one of its sections is archived while a scheduled deploy for
    /// that section still exists.</para>
    /// </summary>
    internal static IReadOnlyList<string> WrapperRunArguments(string scriptPath) =>
        ["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", scriptPath];

    /// <summary>
    /// What the wrapper calls the file it leaves this section's folder problems
    /// in, and what <see cref="ScheduledHealthFindings"/> looks for — and the
    /// name of the run's outcome record (<see cref="ScheduledPublishOutcome"/>),
    /// in its own directory.
    ///
    /// <para>One function rather than two matching string literals, because a
    /// mismatch between the writer and the reader fails in the quietest way
    /// available: the record would be written faithfully every night and read
    /// never, and everything else would look healthy.</para>
    ///
    /// <para><b>Keyed by the working folder too (#309).</b> Once two folders can
    /// each hold a deploy of ICS3U section 1, both runs would clear and write one
    /// record the same morning and erase each other's news:
    /// <c>ICS3U-section1.&lt;folder id&gt;.txt</c>, as the mac files its own.</para>
    /// </summary>
    public static string HealthRecordName(string courseCode, int sectionNumber, string workingFolder) =>
        RecordNameWithId(courseCode, sectionNumber, FolderContainers.FolderIdentifier(workingFolder));

    internal static string RecordNameWithId(string courseCode, int sectionNumber, string folderId) =>
        $"{SafeName(courseCode)}-section{sectionNumber}.{folderId}.txt";

    /// <summary>
    /// The folder-less name every record had before #309. A task set before the
    /// update still writes it; <see cref="ScheduledPublishOutcome"/> files such
    /// a record under its folder's name when it next sweeps.
    /// </summary>
    public static string OldHealthRecordName(string courseCode, int sectionNumber) =>
        $"{SafeName(courseCode)}-section{sectionNumber}.txt";

    private static string SafeName(string taskName) =>
        new string(taskName.Select(c => char.IsLetterOrDigit(c) ? c : '-').ToArray());

    // ---- Cancelling -------------------------------------------------------------

    /// <summary>
    /// Remove one scheduled deploy, by the name it really has. Returns null on
    /// success. Also removes its job and wrapper — schtasks deleting the task
    /// does not delete a file it merely pointed at, and a leftover one is not
    /// runnable on its own so it is simply litter.
    /// </summary>
    public static string? Cancel(ScheduledTask task) => CancelByName(task.Name);

    private static string? CancelByName(string taskName)
    {
        // The stand-in stands in for the WHOLE operation, not only for
        // schtasks, unless the test has moved the files somewhere of its own:
        // these paths resolve through AppDataRoot, which nothing redirects in a
        // test process, so without the guard a test driving Cancel would delete
        // a real teacher's job — and that damage is quieter than the one the
        // seam already prevents: the task survives with nothing to run. Found
        // by review, on a machine that had a real ICD2O wrapper sitting in that
        // folder while the suite ran.
        var (exitCode, output) = Run(["/Delete", "/F", "/TN", taskName]);
        ForgetTheList();
        if (exitCode != 0) return output.Trim();
        if (SchtasksForTests is null || ScheduledDirectoryForTests is not null)
        {
            try { File.Delete(WrapperScriptPath(taskName)); } catch { }
            try { File.Delete(JobPath(taskName)); } catch { }
        }
        return null;
    }

    /// <summary>
    /// Turn off every scheduled deploy THIS working folder holds for a course
    /// — or for one section of it — asking the SCHEDULER what exists rather
    /// than the course's section list, because a section removed on an earlier
    /// build took its number out of the settings and left its task behind
    /// (<c>scheduledDeployCancellation.cases</c>, "remove a whole course").
    /// Another folder's deploy of the same code is never touched.
    /// </summary>
    /// <returns>The sections turned off, and the first refusal (null when every one went).</returns>
    public static (IReadOnlyList<int> TurnedOff, string? Problem) CancelFor(string workingFolder, string courseCode, int? section = null)
    {
        var turnedOff = new List<int>();
        foreach (var task in InFolder(workingFolder)
                     .Where(task => SameCode(task.CourseCode, courseCode))
                     .Where(task => section is null || task.Section == section)
                     .ToList())
        {
            if (Cancel(task) is { } problem) return (turnedOff, problem);
            if (!turnedOff.Contains(task.Section)) turnedOff.Add(task.Section);
        }
        turnedOff.Sort();
        return (turnedOff, null);
    }

    /// <summary>Whether a task by this exact name is registered.</summary>
    public static bool Exists(string taskName) => Run(["/Query", "/TN", taskName]).ExitCode == 0;

    /// <summary>
    /// Stands in for <c>schtasks.exe</c>, so a test can drive scheduling
    /// without a real scheduled task.
    /// </summary>
    /// <remarks>
    /// <para><b>Not convenience — the alternative deletes a teacher's real
    /// publish.</b> <see cref="Cancel"/> runs <c>schtasks /Delete /F</c>
    /// against the real Task Scheduler, and the fixture course in this suite
    /// is ICS3U, which is a course a teacher plausibly has. A test that
    /// exercised the rollover's "turn off the scheduled publish" branch with
    /// no seam would silently remove whoever is running the suite's own
    /// overnight publish. The mac reached the same conclusion about
    /// <c>launchctl</c> and injects a runner for it.</para>
    ///
    /// <para>Process-wide, so anything setting it belongs in the
    /// <c>SharedActivityState</c> serialized collection and must put it back.</para>
    /// </remarks>
    internal static Func<IReadOnlyList<string>, (int ExitCode, string Output)>? SchtasksForTests
    {
        get => _schtasksForTests;
        set { _schtasksForTests = value; ForgetTheList(); }
    }

    private static Func<IReadOnlyList<string>, (int ExitCode, string Output)>? _schtasksForTests;

    private static (int ExitCode, string Output) Run(IEnumerable<string> arguments)
    {
        if (SchtasksForTests is { } stand_in) return stand_in(arguments.ToList());

        var info = new ProcessStartInfo
        {
            FileName = Path.Combine(Environment.SystemDirectory, "schtasks.exe"),
            CreateNoWindow = true,
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
        };
        foreach (string argument in arguments) info.ArgumentList.Add(argument);

        try
        {
            using var process = Process.Start(info);
            if (process is null) return (1, "schtasks could not be started.");
            var error = process.StandardError.ReadToEndAsync();
            string output = process.StandardOutput.ReadToEnd() + error.Result;
            process.WaitForExit(30_000);
            return (process.ExitCode, output);
        }
        catch (Exception error) { return (1, error.Message); }
    }
}
