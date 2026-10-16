using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace Plantoir.Core.Models;

/// <summary>
/// The page each section's preview last showed, kept across quits (#514; the
/// mac's 504-1: per SECTION, the section's own window being what a teacher
/// comes back to). A PATH below the site's root ("" for the front page),
/// never an address: the port changes between runs.
/// </summary>
/// <remarks>
/// <para>Kept in <c>%LOCALAPPDATA%\Plantoir\last-viewed-pages.json</c> — the
/// state folder, so <c>--state-dir</c> moves it — and deliberately NOT in
/// <see cref="AppSettings"/>: that file is rewritten whole by every window
/// that saves a setting, and a parse failure there resets every setting, so a
/// page remembered on each click would be one more writer racing for it. Not
/// a contract format either: only this app reads it (the mac keeps its own,
/// in a preference).</para>
/// <para>Keyed by the working folder (<see cref="WorkingFolder.IsTheSame"/>),
/// the course code (any case) and the section: a folder moved or a course
/// renamed starts with nothing remembered, and Preview at Last Viewed then
/// opens the front page and says why on the trail. Nothing is pruned when a
/// folder is missing — it may be on a drive that is not plugged in (#320).
/// Written only on a change, through a temporary file; an unreadable file
/// reads as nothing remembered.</para>
/// </remarks>
public static class LastViewedPages
{
    /// <summary>How many sections are remembered, newest kept.</summary>
    public const int Keep = 500;

    private static readonly object Gate = new();

    /// <summary>Where the pages are kept. Read on every call, so a redirected state folder is followed.</summary>
    public static string FilePath => FilePathForTests ?? AppDataRoot.Combine("last-viewed-pages.json");

    /// <summary>A test's own file. Null in the app.</summary>
    internal static string? FilePathForTests { get; set; }

    private sealed class Page
    {
        [JsonProperty("folder")] public string Folder { get; set; } = "";
        [JsonProperty("course")] public string Course { get; set; } = "";
        [JsonProperty("section")] public int Section { get; set; }
        [JsonProperty("path")] public string Path { get; set; } = "";
        [JsonProperty("noted")] public DateTime Noted { get; set; }
    }

    /// <summary>The remembered path for a section ("" for the front page), or null when it was never navigated in.</summary>
    public static string? PageFor(string folder, string course, int section)
    {
        lock (Gate)
        {
            foreach (var page in Load())
                if (Matches(page, folder, course, section)) return page.Path;
            return null;
        }
    }

    /// <summary>
    /// Remembers <paramref name="path"/> for a section. Refuses anything that
    /// is not a path below a root (an address, a leading slash). False when
    /// nothing was written — unchanged, refused, or the write failed.
    /// </summary>
    public static bool Remember(string folder, string course, int section, string path, DateTime? now = null)
    {
        if (string.IsNullOrEmpty(folder) || string.IsNullOrEmpty(course) || section <= 0) return false;
        if (path.Contains("://", StringComparison.Ordinal) || path.StartsWith('/')) return false;
        lock (Gate)
        {
            var pages = Load();
            var existing = pages.FirstOrDefault(page => Matches(page, folder, course, section));
            if (existing is not null && existing.Path == path) return false;
            if (existing is not null) pages.Remove(existing);
            pages.Insert(0, new Page
            {
                Folder = WorkingFolder.Resolved(folder),
                Course = course,
                Section = section,
                Path = path,
                Noted = (now ?? DateTime.UtcNow).ToUniversalTime(),
            });
            if (pages.Count > Keep) pages.RemoveRange(Keep, pages.Count - Keep);
            return Save(pages);
        }
    }

    private static bool Matches(Page page, string folder, string course, int section) =>
        page.Section == section
        && string.Equals(page.Course, course, StringComparison.OrdinalIgnoreCase)
        && WorkingFolder.IsTheSame(page.Folder, folder);

    private static List<Page> Load()
    {
        try
        {
            if (!File.Exists(FilePath)) return [];
            var root = JObject.Parse(File.ReadAllText(FilePath));
            var pages = root["pages"]?.ToObject<List<Page>>() ?? [];
            // Newest first, whatever order the file holds them in.
            return pages.Where(page => page.Folder.Length > 0 && page.Course.Length > 0 && page.Section > 0)
                        .OrderByDescending(page => page.Noted).ToList();
        }
        catch { return []; }
    }

    private static bool Save(List<Page> pages)
    {
        try
        {
            Directory.CreateDirectory(System.IO.Path.GetDirectoryName(FilePath)!);
            string json = JsonConvert.SerializeObject(new { pages }, Formatting.Indented,
                new JsonSerializerSettings { DateFormatString = "yyyy-MM-ddTHH:mm:ssZ", DateTimeZoneHandling = DateTimeZoneHandling.Utc });
            AgentGuidance.WriteAtomically(FilePath, json);
            return true;
        }
        catch { return false; }
    }
}
