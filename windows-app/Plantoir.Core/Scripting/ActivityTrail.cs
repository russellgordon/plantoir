using System;
using System.IO;
using Plantoir.Core.Models;

namespace Plantoir.Core.Scripting;

public static class ActivityTrail
{
    public enum Event
    {
        AppOpened,
        Machine,
        Helpers,
        WorkingFolderOpened,
        SettingsSaved,
        SettingsCouldNotBeSaved,
        TaskStarted,
        TaskFinished,
        AskedForACredential,
        AssistantOpened,
        AssistantReady,
        AssistantWouldNotStart,
        AssistantAsked,
        AssistantMatchedAFixedPhrase,
        AssistantChoseATool,
        AssistantCouldNotAnswer,
        /// <summary>
        /// The model's call named a course other than this window's, and the
        /// turn was refused (#180). Carries this window's course and section,
        /// the course AS THE MODEL SPELT IT, and the tool it had chosen —
        /// never the teacher's sentence and never the argument values. The
        /// pair of codes is what tells the guard doing its job apart from a
        /// model slip refused at the teacher's expense.
        /// </summary>
        AssistantWasAskedAboutAnotherCourse,
        AppSettingsOpened,
        AssistantModelChosen,
        AssistantModelDownloadStarted,
        AssistantModelDownloaded,
        AssistantModelDownloadFailed,
        AssistantModelRemoved,
        AssistantModelDownloadStopped,
        AssistantConfirmationChanged,
        SectionContentMarkedPublished,
        /// <summary>
        /// A section's leftover website-builder processes were ended.
        /// Carries the course, the section, and HOW MANY — the count is the
        /// point. Stopping a preview, closing a window or cancelling a
        /// publish asks the launcher to end whatever that section still has
        /// running, and nothing else on the trail separates "there was
        /// nothing left to stop" from "a build was still going and was
        /// ended". Those are the two competing explanations when a teacher
        /// reports a publish that stopped halfway.
        /// </summary>
        SectionProcessesReclaimed,
        /// <summary>
        /// A course folder was renamed from inside Plantoir. Carries the OLD
        /// and NEW folder names and the course - never anything from inside
        /// the folder. A rename is the one moment Plantoir witnesses the
        /// change, so it is the one line that can explain a course whose
        /// configuration stopped matching what is on disk.
        /// </summary>
        FolderRenamed,
        /// <summary>
        /// Adding a name to a course's folder list CREATED the folder. Recorded
        /// because the old behaviour was to write a configuration entry
        /// pointing at nothing, and a teacher who remembers the old behaviour
        /// needs to be able to see which it was.
        /// </summary>
        FolderCreated,
        /// <summary>
        /// A working folder was recognised as kept in sync by a cloud service.
        /// Carries the service's name — never the folder's path, which is a
        /// teacher's own filing and is redacted from the trail anyway.
        /// </summary>
        SyncedFolderNoticed,
        /// <summary>
        /// The teacher chose to use the synced folder anyway. Recorded because
        /// it is a decision Plantoir then remembers and stops asking about,
        /// and a teacher reporting "it never warned me" is asking about
        /// exactly this line.
        /// </summary>
        SyncedFolderAccepted,
        /// <summary>
        /// A folder a feature depends on was missing, renamed or emptied.
        /// Carries the check's NAME, never its wording.
        /// </summary>
        FolderProblemFound,
        /// <summary>
        /// A folder a feature depends on was put back, at the teacher's
        /// request. Separate from FolderProblemFound: one says something is
        /// wrong, the other says somebody acted on it.
        /// </summary>
        FolderProblemRepaired,
        /// <summary>
        /// A repair the teacher ASKED for that did not happen. Carries the
        /// course, the section and what was in the way -- never anything from
        /// inside it. Written today from ONE place only: the refusal when a
        /// folder named index.md sits where the front page belongs. A repair
        /// that simply failed (read-only volume, permissions) still records
        /// nothing, deliberately; the event is named for the OUTCOME rather
        /// than for its one cause so that gap can be closed later without a
        /// rename on either platform.
        /// </summary>
        FolderProblemNotRepaired,
        /// <summary>
        /// A build rewrote some of the teacher's own pages with their class's
        /// date (#279; the rule is the shared Python's). Carries the course,
        /// the section, the count and the pages' places in the course folder
        /// -- never anything written on them. Read from the build's
        /// PLANTOIR_DATED: line: from the console for a run the app watches
        /// (ScriptRunner), and from a scheduled publish's record
        /// (ScheduledHealthFindings).
        /// </summary>
        PagesDatedByTheBuild,
        /// <summary>
        /// A teacher put a section back to how it was when an assistant
        /// conversation started. Carries the course, the section and the
        /// backup's file name -- never a page. The one line that explains a
        /// section whose pages are older than the conversation that changed
        /// them; without it the trail shows six changes and then nothing.
        /// </summary>
        SectionRestored,
        AssistantEngineSaid,
        // The three below are named by contracts/shared-rules.json ->
        // activityTrail.mustRecord, which SharedRules_ActivityTrailEvents_Exist
        // pins as a set. They are declared here, with the site-health work, so
        // that suite is green; their call sites arrive with the Course
        // Settings exclusion and protection work. Declaring an event with no
        // caller is exactly what left FolderProblemFound dead for months --
        // so this is a note that they are owed a caller, not a precedent.

        /// <summary>
        /// A teacher removes a folder or file in Course Settings, taking it
        /// out of previews and deploys. Carries the course, the scope and the
        /// name -- never anything written on the page.
        /// </summary>
        ItemExcluded,
        /// <summary>
        /// A teacher adds a previously excluded folder or file back. To be
        /// recorded ONLY when the name really was excluded: an ordinary add is
        /// not a re-inclusion, and a trail line saying it was would be
        /// believed.
        /// </summary>
        ItemReIncluded,
        /// <summary>
        /// A teacher tries to remove or untick something a feature depends on
        /// and is shown why it cannot go. "I could not remove the folder" is a
        /// report support will receive; this line says which rule refused.
        /// </summary>
        RemovalBlocked,
        /// <summary>
        /// A rollover cut a section loose from last year's website. Carries
        /// the course, the section and — when there was a website to move away
        /// from — where last year's details were kept.
        /// </summary>
        /// <remarks>
        /// The same act turns off any publish that was set to happen on its
        /// own, so a teacher whose overnight publish stops happening has one
        /// line explaining both.
        /// </remarks>
        SectionStartedANewWebsite,
        /// <summary>
        /// A rollover kept last year's website. The OTHER answer, and the one
        /// a problem report is more likely to be about: a teacher writing in
        /// weeks later to say last year's class site was replaced is
        /// describing this branch.
        /// </summary>
        SectionKeptItsWebsite,
        /// <summary>
        /// A publish set to happen on its own stopped because it needed an
        /// answer. Carries the course, the section and which destination
        /// stopped — never the question's own text.
        /// </summary>
        /// <remarks>
        /// The one thing that can happen to a scheduled publish that a teacher
        /// would otherwise never find out about: it runs with the app closed,
        /// so a question it could not ask is seen by nobody. The question's
        /// TEXT is deliberately left out — it comes from a launcher's console,
        /// and a line naming a credential prompt would put a teacher's own
        /// words on the trail.
        /// </remarks>
        ScheduledPublishNeededAnAnswer,
        /// <summary>
        /// A publish set to happen on its own did not finish, for any reason
        /// other than a question — a revoked token, a network that was down, a
        /// build that failed. Carries the course, the section and which
        /// destination stopped.
        /// </summary>
        /// <remarks>
        /// <para>The same silence as <see cref="ScheduledPublishNeededAnAnswer"/>
        /// from a different cause, and a SEPARATE event on purpose. That one's
        /// own wording says a question went unasked, so filing a revoked token
        /// under it would make the trail say something untrue about the one run
        /// a teacher is trying to understand.</para>
        ///
        /// <para>Added 2026-09-09 when Russell widened the readout to ANY
        /// failed scheduled publish: a teacher should learn their overnight
        /// publish did not happen whatever the reason, because the SILENCE is
        /// the complaint rather than the cause. Recording only the question
        /// case leaves an ordinary overnight failure exactly as silent as it
        /// was before.</para>
        /// </remarks>
        ScheduledPublishDidNotFinish,
        /// <summary>
        /// A publish set to happen on its own went out. Carries the course, the
        /// section, and where it published.
        /// </summary>
        /// <remarks>
        /// The positive case, here for the same reason as the two failures read
        /// the other way round: a scheduled publish that leaves NO trace cannot
        /// be told from one that never happened. Without this line the trail
        /// can answer "why did my site not update?" and cannot answer "did
        /// it?", and a teacher wondering whether last night's publish went out
        /// has nowhere to look.
        /// </remarks>
        ScheduledPublishFinished,
        /// <summary>
        /// A build was declined because ANOTHER program on this computer holds
        /// the course's build, publish or preview lease (#289, mac #156).
        /// Carries the course, the section, what was asked for, what the other
        /// holds and its process id — never anything written on a page.
        /// </summary>
        BuildDeclinedCourseBusyElsewhere,
        /// <summary>
        /// A publish set for later found the course being built or published
        /// elsewhere and waited for it (#289). Carries how long, for whom, and
        /// whether it then went ahead or stood down — a publish that went out
        /// ten minutes late looks, from outside, exactly like one that misfired.
        /// </summary>
        ScheduledPublishWaitedForTheCourse,
        /// <summary>
        /// A deploy the teacher set to happen on its own was turned off by
        /// something other than them asking: the course or the section was
        /// removed (#239), the day it was set for had gone by, the course was
        /// still busy after the wait, or it could not deploy the way the course
        /// is set now. Carries the course, the section and WHICH.
        /// </summary>
        ScheduledDeployTurnedOff,
        /// <summary>
        /// A publish set for later read the course's settings when it ran
        /// (#347, mac #323) and found them different from what the teacher was
        /// told, or stood down over them. Written only when something differs.
        /// </summary>
        ScheduledPublishReadTheCoursesSettings,
        /// <summary>
        /// Quitting asked first, because a publish or a preview build was under
        /// way (#231). Carries what, in the words shown, and which button was
        /// pressed — "I closed it and it would not close" is the Keep Working
        /// branch and nothing else explains it. Never written when Windows is
        /// logging off: nothing is asked then.
        /// </summary>
        QuitAskedAboutWorkUnderWay,
        /// <summary>
        /// A remembered timetable named a date that cannot be a class date —
        /// the file was written by this app before #144, on a PC whose
        /// regional format uses another calendar — and was set aside, so the
        /// assistant asks for the timetable again and rewrites it. Windows
        /// only (`appliesOn: ["windows"]`): only this app ever wrote such a
        /// file.
        /// </summary>
        RememberedTimetableSetAside,
        SectionAdded,
        PageSettingsLeftAsTheyWere,
        ClassCopyNotMade,
        WordForAUnitRenamed,
    }

    public static string KeyFor(Event @event) => @event switch
    {
        Event.AppOpened => "app opened",
        Event.Machine => "machine described",
        Event.Helpers => "helpers described",
        Event.WorkingFolderOpened => "working folder opened",
        Event.SettingsSaved => "settings saved",
        Event.SettingsCouldNotBeSaved => "settings could not be saved",
        Event.TaskStarted => "task started",
        Event.TaskFinished => "task finished",
        Event.AskedForACredential => "asked for a publishing credential",
        Event.AssistantOpened => "assistant opened",
        Event.AssistantReady => "assistant ready",
        Event.AssistantWouldNotStart => "assistant would not start",
        Event.AssistantAsked => "assistant asked",
        Event.AssistantMatchedAFixedPhrase => "assistant matched a fixed phrase",
        Event.AssistantChoseATool => "assistant chose a tool",
        Event.AssistantCouldNotAnswer => "assistant could not answer",
        Event.AssistantWasAskedAboutAnotherCourse => "assistant was asked about another course",
        Event.AppSettingsOpened => "app settings opened",
        Event.AssistantModelChosen => "assistant model chosen",
        Event.AssistantModelDownloadStarted => "assistant model download started",
        Event.AssistantModelDownloaded => "assistant model downloaded",
        Event.AssistantModelDownloadFailed => "assistant model download failed",
        Event.AssistantModelRemoved => "assistant model removed",
        Event.AssistantModelDownloadStopped => "assistant model download stopped",
        Event.AssistantConfirmationChanged => "assistant confirmation changed",
        Event.SectionContentMarkedPublished => "section content marked published",
        Event.SectionProcessesReclaimed => "section processes reclaimed",
        Event.FolderRenamed => "folder renamed",
        Event.FolderCreated => "folder created",
        Event.SyncedFolderNoticed => "synced folder noticed",
        Event.SyncedFolderAccepted => "synced folder accepted",
        Event.FolderProblemFound => "folder problem found",
        Event.FolderProblemRepaired => "folder problem repaired",
        Event.FolderProblemNotRepaired => "folder problem not repaired",
        Event.PagesDatedByTheBuild => "pages dated by the build",
        Event.SectionRestored => "section restored",
        Event.AssistantEngineSaid => "assistant engine said",
        Event.ItemExcluded => "item excluded",
        Event.ItemReIncluded => "item re-included",
        Event.RemovalBlocked => "removal blocked",
        Event.SectionStartedANewWebsite => "section started a new website",
        Event.SectionKeptItsWebsite => "section kept its website",
        Event.ScheduledPublishNeededAnAnswer => "scheduled publish needed an answer",
        Event.ScheduledPublishDidNotFinish => "scheduled publish did not finish",
        Event.ScheduledPublishFinished => "scheduled publish finished",
        Event.BuildDeclinedCourseBusyElsewhere => "build declined, course busy elsewhere",
        Event.ScheduledPublishWaitedForTheCourse => "scheduled publish waited for the course",
        Event.ScheduledDeployTurnedOff => "scheduled deploy turned off",
        Event.ScheduledPublishReadTheCoursesSettings => "scheduled publish read the course's settings",
        Event.QuitAskedAboutWorkUnderWay => "quit asked about work under way",
        Event.RememberedTimetableSetAside => "remembered timetable set aside",
        Event.SectionAdded => "section added",
        Event.PageSettingsLeftAsTheyWere => "page settings left as they were",
        Event.ClassCopyNotMade => "class copy not made",
        Event.WordForAUnitRenamed => "word for a unit renamed",
        _ => throw new ArgumentOutOfRangeException(nameof(@event)),
    };

    public static string DefaultLogDirectory =>
        Plantoir.Core.Models.AppDataRoot.Combine("Logs");

    public static string DefaultLogPath => Path.Combine(DefaultLogDirectory, "activity.txt");

    private static string? _customLogPath;
    private static readonly object _lock = new();

    public static void SetCustomLogPathForTesting(string? path)
    {
        lock (_lock)
        {
            _customLogPath = path;
        }
    }

    public static string CurrentLogPath => _customLogPath ?? DefaultLogPath;

    public const string PromptPrefix = "  asked: ";

    public static void Note(Event @event, string what, DateTime? moment = null)
    {
        DateTime when = moment ?? DateTime.Now;
        string safeWhat = LogRedactor.Redacting(what);
        string entry = $"{DateText.Stamp(when)} · {safeWhat}";
        Append(entry);
    }

    public static void Note(Event @event, string what, string course, int section, DateTime? moment = null)
    {
        DateTime when = moment ?? DateTime.Now;
        string safeWhat = LogRedactor.Redacting(what);
        string entry = $"{DateText.Stamp(when)} · {course}/{section} · {safeWhat}";
        Append(entry);
    }

    public static void NotePrompt(string prompt, string course, int section, DateTime? moment = null)
    {
        DateTime when = moment ?? DateTime.Now;
        string safePrompt = LogRedactor.Redacting(prompt.Trim());
        string entry = $"{DateText.Stamp(when)} · {course}/{section} · asked a question\n{PromptPrefix}{safePrompt}";
        Append(entry);
    }

    /// <summary>The words for `page settings left as they were`, the mac's <c>pageSettingsLeftAsTheyWereLine</c> word for word.</summary>
    public static string PageSettingsLeftAsTheyWereLine(string act, int pages) =>
        $"left the settings of {(pages == 1 ? "1 page" : $"{pages} pages")} as they were while {act}: no room at the top for a new setting";

    public static void NoteLaunch()
    {
        Note(Event.AppOpened, "Plantoir opened — " + ProblemReportEnvironment.AppDescription);
        Note(Event.Machine, "running on " + ProblemReportEnvironment.SystemDescription);
        Note(Event.Helpers, "using " + ProblemReportEnvironment.HelperDescription);
    }

    public static void NoteLaunch(string appVersion, string buildNumber, int processId, string executablePath)
    {
        string safePath = LogRedactor.Redacting(executablePath);
        Note(Event.AppOpened, $"Plantoir {appVersion} ({buildNumber}) opened (PID {processId}, {safePath})");
        Note(Event.Machine, "running on " + ProblemReportEnvironment.SystemDescription);
        Note(Event.Helpers, "using " + ProblemReportEnvironment.HelperDescription);
    }

    /// <summary>
    /// The one lock every WRITER of the trail takes, across processes: the
    /// app, <c>plantoir-mcp.exe</c> and a scheduled run are separate
    /// processes writing one file, and <c>lock</c> covers threads of one.
    /// </summary>
    /// <remarks>
    /// <para><b>Measured, #303 (this Windows PC: Intel Core i5-8365U, 4 cores /
    /// 8 threads, 15.7 GB, NTFS, Windows 11 Pro 25H2 build 26200,
    /// 2026-09-30).</b> Two processes calling <see cref="Note(Event, string, DateTime?)"/>
    /// 500 times each, started on the same tick, five rounds: the old
    /// <c>File.AppendAllText</c> (which opens with <c>FileShare.Read</c>, so the
    /// second writer's open throws a sharing violation into an empty
    /// <c>catch</c>) kept <b>4,444 of 5,000</b>; three processes × three lines ×
    /// 100 bursts, the mac's shape, kept <b>682 of 900</b>. With this mutex:
    /// every line, both shapes (numbers in documentation/09 → "Two writers at
    /// once").</para>
    /// <para><b>REJECTED, measured:</b> <c>FileShare.ReadWrite</c> with one
    /// <c>Write</c> per line and no lock. The issue's first candidate, on the
    /// reasoning that an append-mode write lands at end-of-file — but .NET's
    /// <c>FileMode.Append</c> opens for ordinary write and keeps its OWN
    /// position, so two writers open at the same end and the second
    /// overwrites the first: 4,512 of 5,000, and 180 of 270. A retry loop on
    /// the sharing violation was rejected unmeasured, as the issue says: a
    /// guessed delay that still drops the line after its last retry.</para>
    /// <para><c>Local\</c>, not <c>Global\</c>: the trail is per user
    /// (<c>%LOCALAPPDATA%</c>), and every writer runs in the teacher's own
    /// session. Tests redirect the PATH, not the lock — one lock for every
    /// trail file on the machine costs nothing at one line at a time.</para>
    /// </remarks>
    private const string WritersMutexName = @"Local\PlantoirActivityTrail";

    private static void Append(string line)
    {
        lock (_lock)
        {
            try
            {
                string path = CurrentLogPath;
                string? dir = Path.GetDirectoryName(path);
                if (!string.IsNullOrEmpty(dir) && !Directory.Exists(dir))
                {
                    Directory.CreateDirectory(dir);
                }
                byte[] bytes = System.Text.Encoding.UTF8.GetBytes(line + Environment.NewLine);

                using var writers = new System.Threading.Mutex(false, WritersMutexName);
                bool held = false;
                try
                {
                    try { held = writers.WaitOne(TimeSpan.FromSeconds(5)); }
                    catch (System.Threading.AbandonedMutexException) { held = true; }   // a writer died holding it: ours now

                    // Written even when the wait timed out: a line that might
                    // interleave is better than a line certainly lost. Five
                    // seconds is far beyond one line's append (sub-millisecond).
                    using var stream = new FileStream(path, FileMode.Append, FileAccess.Write,
                        FileShare.ReadWrite | FileShare.Delete);
                    stream.Write(bytes, 0, bytes.Length);
                }
                finally
                {
                    if (held) writers.ReleaseMutex();
                }
            }
            catch
            {
                // Never fail caller if log write fails
            }
        }
    }
}
