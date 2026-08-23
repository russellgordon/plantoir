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
