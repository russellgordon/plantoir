using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;

namespace Plantoir.Core.Scripting;

public class ProblemReportStore
{
    public string LogsDirectory { get; }
    public const int MostRetainedRuns = 20;
    public const string ActivityFileName = "activity.txt";

    public ProblemReportStore(string? logsDirectory = null)
    {
        LogsDirectory = logsDirectory ?? ActivityTrail.DefaultLogDirectory;
    }

    public static ProblemReportStore Standard
    {
        get
        {
            string currentPath = ActivityTrail.CurrentLogPath;
            string dir = Path.GetDirectoryName(currentPath) ?? ActivityTrail.DefaultLogDirectory;
            return new ProblemReportStore(dir);
        }
    }

    public string RunsFolder => Path.Combine(LogsDirectory, "runs");
    public string ActivityFile => Path.Combine(LogsDirectory, ActivityFileName);

    public IReadOnlyList<string> RunFilePaths()
    {
        if (!Directory.Exists(RunsFolder)) return Array.Empty<string>();
        return Directory.GetFiles(RunsFolder, "*.txt")
            .OrderByDescending(Path.GetFileName, StringComparer.Ordinal)
            .Take(MostRetainedRuns)
            .ToList();
    }

    /// <summary>
    /// Writes one finished task's transcript into the runs folder, redacting
    /// each line on the way in (the LogRedactor rule: what is on disk is
    /// already safe to hand over), and prunes the folder to
    /// <see cref="MostRetainedRuns"/>. Fills the gap the 2026-08-19 problem
    /// report exposed: the report promised "the last N tasks Plantoir ran for
    /// you" while nothing on Windows ever wrote one — three failed setups and
    /// the one file that said why was never made.
    /// </summary>
    public string SaveRunTranscript(string scriptName, string outcome, DateTime startedAt,
                                    IEnumerable<string> transcriptLines)
    {
        Directory.CreateDirectory(RunsFolder);
        string safeName = string.Concat(scriptName.Split(Path.GetInvalidFileNameChars()));
        string path = Path.Combine(RunsFolder, $"{startedAt:yyyy-MM-dd HHmmss} {safeName}.txt");
        var lines = new List<string>
        {
            $"{scriptName} — {outcome}",
            $"Started {startedAt:yyyy-MM-dd HH:mm:ss}.",
            "",
        };
        foreach (string line in transcriptLines)
            lines.Add(LogRedactor.Redacting(line));
        File.WriteAllLines(path, lines);
        PruneRuns();
        return path;
    }

    private void PruneRuns()
    {
        var stale = Directory.GetFiles(RunsFolder, "*.txt")
            .OrderByDescending(Path.GetFileName, StringComparer.Ordinal)
            .Skip(MostRetainedRuns);
        foreach (string path in stale)
        {
            try { File.Delete(path); } catch { }
        }
    }

    public string ActivityText(bool includingPrompts)
    {
        string path = ActivityFile;
        if (!File.Exists(path)) return "";
        string content = File.ReadAllText(path);
        if (includingPrompts) return content;

        var keptLines = content.Split('\n')
            .Where(line => !line.StartsWith(ActivityTrail.PromptPrefix, StringComparison.Ordinal));
        return string.Join("\n", keptLines);
    }

    public bool HasAnythingToReport
    {
        get
        {
            if (RunFilePaths().Count > 0) return true;
            return !string.IsNullOrWhiteSpace(ActivityText(includingPrompts: true));
        }
    }

    public bool HasAssistantPrompts
    {
        get
        {
            string text = ActivityText(includingPrompts: true);
            foreach (var line in text.Split('\n'))
            {
                if (line.StartsWith(ActivityTrail.PromptPrefix, StringComparison.Ordinal))
                    return true;
            }
            return false;
        }
    }
}
