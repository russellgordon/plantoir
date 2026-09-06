using System;
using System.IO;

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
        Event.AssistantEngineSaid => "assistant engine said",
        Event.ItemExcluded => "item excluded",
        Event.ItemReIncluded => "item re-included",
        Event.RemovalBlocked => "removal blocked",
        _ => throw new ArgumentOutOfRangeException(nameof(@event)),
    };

    public static string DefaultLogDirectory =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Plantoir", "Logs");

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
        string entry = $"{when:yyyy-MM-dd HH:mm:ss} · {safeWhat}";
        Append(entry);
    }

    public static void Note(Event @event, string what, string course, int section, DateTime? moment = null)
    {
        DateTime when = moment ?? DateTime.Now;
        string safeWhat = LogRedactor.Redacting(what);
        string entry = $"{when:yyyy-MM-dd HH:mm:ss} · {course}/{section} · {safeWhat}";
        Append(entry);
    }

    public static void NotePrompt(string prompt, string course, int section, DateTime? moment = null)
    {
        DateTime when = moment ?? DateTime.Now;
        string safePrompt = LogRedactor.Redacting(prompt.Trim());
        string entry = $"{when:yyyy-MM-dd HH:mm:ss} · {course}/{section} · asked a question\n{PromptPrefix}{safePrompt}";
        Append(entry);
    }

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
                File.AppendAllText(path, line + Environment.NewLine);
            }
            catch
            {
                // Never fail caller if log write fails
            }
        }
    }
}
