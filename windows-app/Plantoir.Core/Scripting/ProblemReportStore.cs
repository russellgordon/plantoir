using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using Plantoir.Core.Models;

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
        return NewestFirst(Directory.GetFiles(RunsFolder, "*.txt"))
            .Take(MostRetainedRuns)
            .ToList();
    }

    /// <summary>
    /// Newest transcript first, by when the file was last written, with the
    /// name as the tie-break.
    ///
    /// <para>Not by name alone, which is what this did until #144. The name
    /// begins with a date, and until then that date was rendered in the
    /// machine's default calendar — <c>2569-…</c> on a PC whose regional
    /// format is Thai. Ordinally, every such name outranks every real
    /// <c>2026-…</c> one, so the moment the names became Gregorian, a runs
    /// folder that already held twenty old transcripts would have kept those
    /// twenty for ever and deleted each NEW transcript on arrival — the
    /// problem report showing the twenty oldest runs and never the one the
    /// teacher was reporting. The file system's clock has no calendar, so it
    /// orders old names and new ones alike.</para>
    /// </summary>
    private static IEnumerable<string> NewestFirst(IEnumerable<string> paths) =>
        paths.OrderByDescending(File.GetLastWriteTimeUtc)
             .ThenByDescending(Path.GetFileName, StringComparer.Ordinal);

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
        string path = Path.Combine(RunsFolder, $"{DateText.Invariant(startedAt, "yyyy-MM-dd HHmmss")} {safeName}.txt");
        var lines = new List<string>
        {
            $"{scriptName} — {outcome}",
            $"Started {DateText.Stamp(startedAt)}.",
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
        var stale = NewestFirst(Directory.GetFiles(RunsFolder, "*.txt"))
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
