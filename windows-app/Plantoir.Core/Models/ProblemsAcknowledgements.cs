using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace Plantoir.Core.Models;

/// <summary>
/// What a teacher has ANSWERED about each section's problems, and which
/// changes are already on the trail — one small file per working folder,
/// <c>%LOCALAPPDATA%\Plantoir\problems-acknowledged\&lt;folder id&gt;.json</c>
/// (<c>sectionProblems.alert</c>; #717 plan review, HIGH 2). The mac keeps the
/// same shape under its Application Support, so the two are easy to compare,
/// though nothing shares the file.
/// </summary>
/// <remarks>
/// <para><b>Never in the record</b>, which the build rewrites, and never in the
/// teacher's folder. Under <see cref="AppDataRoot"/>, so <c>--state-dir</c>
/// and the unit suite keep their own — unlike the record, which is where the
/// launchers built (<see cref="BuildOutputLocation.WhereTheLaunchersBuild"/>).</para>
///
/// <para>Per section key <c>"&lt;course lowercased&gt;/&lt;section&gt;"</c>: two
/// lists, <c>answered</c> and <c>noted</c>, each the last
/// <see cref="Kept"/> keys (<c>alert.acknowledgedKept</c>), oldest dropped
/// first. Written whole and atomically; a file that cannot be written costs
/// at most one alert raised again.</para>
/// </remarks>
public sealed class ProblemsAcknowledgements
{
    /// <summary>How many keys of each list are kept per section.</summary>
    public const int Kept = 20;

    private readonly Dictionary<string, List<string>> _answered = new(StringComparer.Ordinal);
    private readonly Dictionary<string, List<string>> _noted = new(StringComparer.Ordinal);

    /// <summary>Every read-modify-write of any working folder's file, in this process.</summary>
    internal static readonly object Gate = new();

    public static string FolderPath => AppDataRoot.Combine("problems-acknowledged");

    /// <summary>One working folder's file, named by the eight characters its builds folder is.</summary>
    public static string PathFor(string workingFolder) =>
        Path.Combine(FolderPath, FolderContainers.FolderIdentifier(workingFolder) + ".json");

    public static string SectionKeyFor(string courseCode, int sectionNumber) =>
        $"{courseCode.ToLowerInvariant()}/{sectionNumber}";

    /// <summary>The file for <paramref name="workingFolder"/>, or an empty one. Never throws.</summary>
    public static ProblemsAcknowledgements Read(string workingFolder)
    {
        var read = new ProblemsAcknowledgements();
        try
        {
            string path = PathFor(workingFolder);
            if (!File.Exists(path)) return read;
            if (JsonNode.Parse(Patiently(() => File.ReadAllText(path))) is not JsonObject root) return read;
            if (root["sections"] is not JsonObject sections) return read;
            foreach (var (name, value) in sections)
            {
                if (value is not JsonObject entry) continue;
                read._answered[name] = SectionProblemsRecord.Texts(entry["answered"]).ToList();
                read._noted[name] = SectionProblemsRecord.Texts(entry["noted"]).ToList();
            }
        }
        catch (Exception) { }
        return read;
    }

    public IReadOnlySet<string> Answered(string courseCode, int sectionNumber) =>
        _answered.TryGetValue(SectionKeyFor(courseCode, sectionNumber), out var list)
            ? list.ToHashSet(StringComparer.Ordinal) : new HashSet<string>();

    public IReadOnlySet<string> Noted(string courseCode, int sectionNumber) =>
        _noted.TryGetValue(SectionKeyFor(courseCode, sectionNumber), out var list)
            ? list.ToHashSet(StringComparer.Ordinal) : new HashSet<string>();

    public void RememberAnswered(string alertKey, string courseCode, int sectionNumber) =>
        Remember(_answered, alertKey, courseCode, sectionNumber);

    public void RememberNoted(string alertKey, string courseCode, int sectionNumber) =>
        Remember(_noted, alertKey, courseCode, sectionNumber);

    private static void Remember(Dictionary<string, List<string>> lists, string key, string courseCode, int sectionNumber)
    {
        string name = SectionKeyFor(courseCode, sectionNumber);
        lists[name] = Adding(key, lists.TryGetValue(name, out var list) ? list : new List<string>()).ToList();
    }

    /// <summary><paramref name="list"/> with <paramref name="key"/> last, at most <see cref="Kept"/> long, oldest dropped.</summary>
    public static IReadOnlyList<string> Adding(string key, IReadOnlyList<string> list)
    {
        var kept = list.Where(existing => existing != key).ToList();
        kept.Add(key);
        while (kept.Count > Kept) kept.RemoveAt(0);
        return kept;
    }

    /// <summary>Written whole and atomically (a temporary file moved over the old one). Never throws.</summary>
    public void Write(string workingFolder)
    {
        try
        {
            var sections = new JsonObject();
            foreach (string name in _answered.Keys.Union(_noted.Keys).OrderBy(n => n, StringComparer.Ordinal))
                sections[name] = new JsonObject
                {
                    ["answered"] = new JsonArray((_answered.TryGetValue(name, out var a) ? a : new List<string>()).Select(k => (JsonNode)k).ToArray()),
                    ["noted"] = new JsonArray((_noted.TryGetValue(name, out var n) ? n : new List<string>()).Select(k => (JsonNode)k).ToArray()),
                };
            var root = new JsonObject { ["sections"] = sections, ["version"] = 1 };
            string path = PathFor(workingFolder);
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            string temporary = path + "." + Environment.ProcessId + ".tmp";
            File.WriteAllText(temporary, root.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));
            Patiently(() => { File.Move(temporary, path, overwrite: true); return ""; });
        }
        catch (Exception) { }
    }

    /// <summary>
    /// Tried again a few times on a sharing violation: a virus scanner or a
    /// sync client can hold a file just written for a moment, and a replace or
    /// a read refused then would lose an answer (seen once in the full UI run,
    /// 2026-11-11: an alert answered Not Now was raised again on returning).
    /// </summary>
    private static string Patiently(Func<string> act)
    {
        for (int attempt = 1; ; attempt++)
        {
            try { return act(); }
            catch (IOException) when (attempt < 6) { System.Threading.Thread.Sleep(40 * attempt); }
        }
    }
}
