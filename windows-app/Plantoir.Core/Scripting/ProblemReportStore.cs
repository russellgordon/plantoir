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

    /// <summary>Said first when what the teacher typed was left out (<c>problemReportTrail.promptsLeftOutNote</c>).</summary>
    public const string PromptsLeftOutNote = "(What the teacher typed was left out of this report.)";

    /// <summary>Said next when shown lines carry characters that could not be read (<c>problemReportTrail.unreadableCharactersNote</c>).</summary>
    public const string UnreadableCharactersNoteTemplate =
        "(Some characters on {count} of these lines could not be read, and are shown as \uFFFD.)";

    public static string UnreadableCharactersNote(int lines) =>
        UnreadableCharactersNoteTemplate.Replace("{count}", lines.ToString(System.Globalization.CultureInfo.InvariantCulture), StringComparison.Ordinal);

    public string ActivityText(bool includingPrompts)
    {
        string path = ActivityFile;
        if (!File.Exists(path)) return "";
        byte[] bytes;
        try { bytes = File.ReadAllBytes(path); }
        catch (IOException) { return ""; }
        catch (UnauthorizedAccessException) { return ""; }
        return ActivityText(bytes, includingPrompts);
    }

    /// <summary>
    /// The trail as it goes into a problem report (<c>shared-rules.json</c> →
    /// <c>problemReportTrail</c>; GitHub issue #316, the mac's #301).
    /// </summary>
    /// <remarks>
    /// <para>Read LENIENTLY: the file has writers that are not the app — every
    /// launcher appends with a plain write that passes any byte — and a
    /// teacher can open it in any editor, so one unreadable byte must not lose
    /// the report (it emptied the whole report on the mac). .NET's UTF-8
    /// decoder replaces each maximal ill-formed sequence with one U+FFFD and
    /// never drops or merges a line, which is the contract's reading.</para>
    ///
    /// <para>Then two notes at the top, in that order: that the teacher's words
    /// were left out (only when a prompt line WAS dropped), and how many of the
    /// SHOWN lines carry U+FFFD — counted by ordinal search, so a replacement
    /// already in the file counts too, and a damaged prompt line left out does
    /// not. A readable file with the prompts included comes back exactly as it
    /// is on disk.</para>
    /// </remarks>
    public static string ActivityText(byte[] bytes, bool includingPrompts)
    {
        int start = bytes.Length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF ? 3 : 0;
        string content = new System.Text.UTF8Encoding(false, false).GetString(bytes, start, bytes.Length - start);

        var lines = content.Split('\n').ToList();
        bool promptsDropped = false;
        if (!includingPrompts)
        {
            int before = lines.Count;
            lines = lines.Where(line => !line.StartsWith(ActivityTrail.PromptPrefix, StringComparison.Ordinal)).ToList();
            promptsDropped = lines.Count < before;
        }

        int unreadable = lines.Count(line => line.Contains('\uFFFD', StringComparison.Ordinal));
        var notes = new List<string>();
        if (promptsDropped) notes.Add(PromptsLeftOutNote);
        if (unreadable > 0) notes.Add(UnreadableCharactersNote(unreadable));
        return string.Join("\n", notes.Concat(lines));
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
