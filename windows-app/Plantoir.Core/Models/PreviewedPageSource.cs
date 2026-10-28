using System.Text;
using System.Text.Json.Nodes;
using Plantoir.Core.Scripting;

namespace Plantoir.Core.Models;

/// <summary>
/// Which file a section's Open in Obsidian opens for the page that section's
/// preview is showing (#681; the mac's <c>PreviewedPageSource.swift</c>, #518)
/// — the address on screen, looked up in the list the build wrote beside the
/// site (<c>contracts/file-formats.json</c> → <c>pageSourcesList</c>).
/// </summary>
/// <remarks>
/// <para>Every rule here is a case in <c>contracts/shared-rules.json</c> →
/// <c>obsidianOpensThePreviewedPage</c>, run by
/// <c>ObsidianOpensThePreviewedPageContractTests</c> against the contract's own
/// fixture. <c>documentation/12-windows-app.md</c> → "Open in Obsidian opens the
/// page the preview shows on Windows (#681, the mac's #518)" says what differs
/// from the mac.</para>
///
/// <para>One difference is NTFS's and not a choice: a Mac may keep a name
/// decomposed (NFD) while the list, written by Python from the same name, may
/// carry it composed; APFS finds either spelling, NTFS treats them as two
/// different names. So a name the list gives that is not on disk as spelled is
/// looked for among its folder's entries by NFC, and the name FOUND is the one
/// opened.</para>
/// </remarks>
public static class PreviewedPageSource
{
    /// <summary>Why the press opened the section as before, rather than a page — the contract's <c>fallbacks</c> keys.</summary>
    public enum Fallback { NoPageShowing, NoList, NotInTheList, Collided, OutsideTheCourse, FileGone }

    /// <summary>What a section's Open in Obsidian opens.</summary>
    public abstract record Answer;

    /// <summary>
    /// The file behind the page on screen: <paramref name="File"/> is absolute,
    /// every name in it spelled as the folder holding it lists it - case and
    /// composed or decomposed accents both, read back from disk, since Obsidian
    /// looks the path up in its vault case-sensitively; <paramref name="Place"/>
    /// its place in the course folder without <c>.md</c>, with <c>/</c>, as the
    /// list spells it, for the trail and the reply.
    /// </summary>
    public sealed record Page(string File, string Place, bool Hidden) : Answer;

    /// <summary>What the press opened before #681: the section, or the course when it has no front page.</summary>
    public sealed record FellBack(Fallback Why) : Answer;

    /// <summary>The list's name, beside <c>public\</c> in the section's built output.</summary>
    public const string ListFileName = ".page-sources.json";

    /// <summary>The only version this app reads; any other is no list.</summary>
    public const int ListVersion = 1;

    // The trail's words: obsidianOpensThePreviewedPage.trail and .fallbacks,
    // pinned against the contract by the contract test.
    public const string TrailOpened = "opened {place} in Obsidian, the page the preview shows";
    public const string TrailOpenedHidden = "opened {place} in Obsidian, the page the preview shows (hidden from students)";
    public const string TrailFellBack = "opened the section in Obsidian, not a page of the preview: {why}";

    /// <summary>
    /// Where the build writes a section's list: the section's built output under
    /// the working folder's builds root, keyed by the course's FOLDER code.
    /// Under <c>--state-dir</c> the app's builds root moves and the launchers'
    /// does not (#664), so a UI test reads no list there.
    /// </summary>
    public static string ListPathFor(string workingFolder, string courseCode, int section) =>
        Path.Combine(BuildOutputLocation.ForSection(BuildOutputLocation.BuildsRootFor(workingFolder), courseCode, section), ListFileName);

    /// <summary>The list on disk, or null when it is missing, unreadable, not an object, or of another version.</summary>
    public static JsonObject? ReadList(string path)
    {
        try
        {
            if (!System.IO.File.Exists(path)) return null;
            return ParseList(System.IO.File.ReadAllText(path));
        }
        catch { return null; }
    }

    /// <summary>The list from its text, or null when this app cannot read it.</summary>
    public static JsonObject? ParseList(string text)
    {
        try { return Validated(JsonNode.Parse(text) as JsonObject); }
        catch { return null; }
    }

    private static JsonObject? Validated(JsonObject? list)
    {
        if (list is null) return null;
        if (list["version"] is not JsonValue version || !version.TryGetValue<int>(out int number) || number != ListVersion) return null;
        return list["pages"] is JsonObject ? list : null;
    }

    /// <summary>
    /// The file for <paramref name="address"/> — the preview's path below its
    /// root as <see cref="PreviewStartPage.Remember"/> gives it, or null when no
    /// page is showing — from the list, inside <paramref name="courseFolder"/> only.
    /// </summary>
    public static Answer Resolve(string? address, JsonObject? list, string courseFolder)
    {
        if (address is null) return new FellBack(Fallback.NoPageShowing);
        var pages = PagesOf(Validated(list));
        if (pages is null) return new FellBack(Fallback.NoList);

        JsonObject? entry = null;
        foreach (string key in LookupKeys(address))
        {
            if (pages.TryGetValue(key, out var found)) { entry = found; break; }
        }
        if (entry is null) return new FellBack(Fallback.NotInTheList);
        if (Flag(entry, "collided")) return new FellBack(Fallback.Collided);
        if (entry["source"] is not JsonValue sourceValue || !sourceValue.TryGetValue<string>(out var source) || source is null)
            return new FellBack(Fallback.NotInTheList);

        // The front page that is only an embed of a class opens the class
        // (ruling 1) while that file is there, with the class's OWN flag
        // (showsHidden): the trail speaks of the file that opens.
        if (entry["shows"] is JsonValue showsValue && showsValue.TryGetValue<string>(out var shows) && shows is not null)
        {
            var shown = FileFor(shows, Flag(entry, "showsHidden"), courseFolder);
            if (shown is Page) return shown;
        }
        return FileFor(source, Flag(entry, "hidden"), courseFolder);
    }

    /// <summary>
    /// The keys to look up, in order: '' is the front page; an address ending
    /// '/' is a folder's page first and then the page itself; any other the
    /// page and then the folder's page. Decoded once and put in NFC.
    /// </summary>
    public static IReadOnlyList<string> LookupKeys(string address)
    {
        string decoded = Uri.UnescapeDataString(address).Normalize(NormalizationForm.FormC);
        if (decoded.Length == 0) return ["index"];
        if (decoded.EndsWith('/'))
        {
            string withoutTheSlash = decoded[..^1];
            return withoutTheSlash.Length == 0 ? ["index"] : [decoded + "index", withoutTheSlash];
        }
        return [decoded, decoded + "/index"];
    }

    private static Dictionary<string, JsonObject>? PagesOf(JsonObject? list)
    {
        if (list?["pages"] is not JsonObject pages) return null;
        var result = new Dictionary<string, JsonObject>(StringComparer.Ordinal);
        foreach (var (key, value) in pages)
        {
            if (value is JsonObject entry) result[key.Normalize(NormalizationForm.FormC)] = entry;
        }
        return result;
    }

    private static bool Flag(JsonObject entry, string name) =>
        entry[name] is JsonValue value && value.TryGetValue<bool>(out bool flag) && flag;

    /// <summary>
    /// One file the list names, refused unless it is a page inside the course
    /// folder once links are followed, and still there.
    /// </summary>
    private static Answer FileFor(string source, bool hidden, string courseFolder)
    {
        if (!source.EndsWith(".md", StringComparison.Ordinal)) return new FellBack(Fallback.NotInTheList);

        string[] segments = source.Split('/', StringSplitOptions.RemoveEmptyEntries);
        // A '..' anywhere, or a segment that is itself rooted ("C:") or holds
        // a '\', is refused before anything is walked: the walk follows links
        // in its REAL path and not in its spelled one, so a '..' after a link
        // moves the two apart, and the spelled one - what Obsidian is handed -
        // could land outside the course while the real one is inside. The
        // build writes paths below the course and never a '..' (the contract's
        // Escape case is exactly one), so refusing it costs no real page.
        foreach (string segment in segments)
        {
            if (segment == ".." || segment.Contains('\\') || Path.IsPathRooted(segment))
                return new FellBack(Fallback.OutsideTheCourse);
        }

        string course = WorkingFolder.Resolved(courseFolder);
        string spelledCourse = Located(course, [], out string realCourse, out _) ?? course;
        string? onDisk = Located(course, segments, out string real, out bool missing);

        // Both inside the course: the real path (links followed), so a link
        // cannot reach out of it, and the spelled one, which is what opens.
        if (!IsInside(real, realCourse) || (onDisk is not null && !IsInside(onDisk, spelledCourse)))
            return new FellBack(Fallback.OutsideTheCourse);
        if (missing || onDisk is null || !System.IO.File.Exists(onDisk)) return new FellBack(Fallback.FileGone);

        string place = source[..^".md".Length].Normalize(NormalizationForm.FormC);
        return new Page(onDisk, place, hidden);
    }

    private static bool IsInside(string path, string folder) =>
        path.StartsWith(folder.TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase);

    /// <summary>
    /// Walks <paramref name="segments"/> down from <paramref name="start"/>:
    /// returns the path spelled as the names are on disk (links NOT followed,
    /// so it is what Obsidian knows the vault by), and in <paramref name="real"/>
    /// the same place with every link followed. A name not on disk as spelled
    /// is looked for by NFC (see the remarks on the class); once a name is
    /// missing, the rest is joined as written and <paramref name="missing"/> is set.
    /// </summary>
    private static string? Located(string start, IReadOnlyList<string> segments, out string real, out bool missing)
    {
        missing = false;
        string spelled = start;
        real = Followed(RealFromRoot(start));
        foreach (string segment in segments)
        {
            if (segment == ".") continue;
            if (missing)
            {
                spelled = Path.Combine(spelled, segment);
                real = Path.Combine(real, segment);
                continue;
            }
            string? name = NameOnDisk(real, segment);
            if (name is null)
            {
                missing = true;
                spelled = Path.Combine(spelled, segment);
                real = Path.Combine(real, segment);
                continue;
            }
            spelled = Path.Combine(spelled, name);
            real = Followed(Path.Combine(real, name));
        }
        try { real = Path.GetFullPath(real); } catch { }
        try { spelled = Path.GetFullPath(spelled); } catch { }
        return missing ? null : spelled;
    }

    /// <summary>Every link on the way down to <paramref name="path"/> followed, from its root.</summary>
    private static string RealFromRoot(string path)
    {
        string? root = Path.GetPathRoot(path);
        if (string.IsNullOrEmpty(root)) return path;
        string current = root;
        foreach (string part in path[root.Length..].Split(['\\', '/'], StringSplitOptions.RemoveEmptyEntries))
            current = Followed(Path.Combine(current, part));
        return current;
    }

    private static string Followed(string path)
    {
        try
        {
            FileSystemInfo info = Directory.Exists(path) ? new DirectoryInfo(path) : new FileInfo(path);
            if (info.Exists && info.LinkTarget is not null)
                return info.ResolveLinkTarget(returnFinalTarget: true)?.FullName ?? path;
        }
        catch { }
        return path;
    }

    /// <summary>
    /// The entry of <paramref name="folder"/> called <paramref name="name"/>,
    /// AS IT IS SPELLED ON DISK, or null when there is none. NTFS finds a name
    /// in any case, but Obsidian matches the path it is handed against its
    /// vault's files case-sensitively, so when the name is there the entry's
    /// own spelling is read back from the folder and that is what is opened.
    /// A name not there as written is looked for by NFC, comparing exactly
    /// (<see cref="StringComparison.Ordinal"/>): only the composed/decomposed
    /// difference is forgiven there, as on APFS.
    /// </summary>
    private static string? NameOnDisk(string folder, string name)
    {
        try
        {
            string exact = Path.Combine(folder, name);
            if (System.IO.File.Exists(exact) || Directory.Exists(exact))
            {
                string? sameButForCase = null;
                foreach (string entry in Directory.EnumerateFileSystemEntries(folder, name))
                {
                    string entryName = Path.GetFileName(entry);
                    if (string.Equals(entryName, name, StringComparison.Ordinal)) return entryName;
                    if (string.Equals(entryName, name, StringComparison.OrdinalIgnoreCase)) sameButForCase ??= entryName;
                }
                return sameButForCase ?? name;
            }
            if (!Directory.Exists(folder)) return null;
            string wanted = name.Normalize(NormalizationForm.FormC);
            foreach (string entry in Directory.EnumerateFileSystemEntries(folder))
            {
                string entryName = Path.GetFileName(entry);
                if (string.Equals(entryName.Normalize(NormalizationForm.FormC), wanted, StringComparison.Ordinal))
                    return entryName;
            }
        }
        catch { }
        return null;
    }

    /// <summary>
    /// The link Obsidian is handed: <c>obsidian://open?path=</c> and the absolute
    /// path, never the vault's name (two working folders can hold courses with
    /// the same name). <see cref="Uri.EscapeDataString"/> writes '+' as %2B,
    /// as <c>obsidianOpensThePreviewedPage.link</c> asks, and every separator
    /// too (<c>\</c> as %5C, ':' as %3A), which Obsidian decodes
    /// (<c>decodeURIComponent</c>; measured on Obsidian for Windows 1.14.5,
    /// <c>12-windows-app.md</c> → "Open in Obsidian opens the page the preview
    /// shows on Windows (#681, the mac's #518)").
    /// </summary>
    public static string ObsidianLink(string path) => "obsidian://open?path=" + Uri.EscapeDataString(path);

    /// <summary>The trail words for a section's press (the course and section are added by the trail).</summary>
    public static string TrailWords(Answer answer) => answer switch
    {
        Page { Hidden: true } page => TrailOpenedHidden.Replace("{place}", page.Place),
        Page page => TrailOpened.Replace("{place}", page.Place),
        FellBack fell => TrailFellBack.Replace("{why}", Why(fell.Why)),
        _ => throw new ArgumentOutOfRangeException(nameof(answer)),
    };

    /// <summary>The reason in words (<c>obsidianOpensThePreviewedPage.fallbacks</c>).</summary>
    public static string Why(Fallback reason) => reason switch
    {
        Fallback.NoPageShowing => "no preview page was showing",
        Fallback.NoList => "the preview's list of pages could not be read",
        Fallback.NotInTheList => "the page on screen is not one of the course's own files",
        Fallback.Collided => "two of the course's files make a page at that address",
        Fallback.OutsideTheCourse => "the page's file is not inside the course folder",
        Fallback.FileGone => "the page's file is no longer there",
        _ => throw new ArgumentOutOfRangeException(nameof(reason)),
    };

    /// <summary>The one trail line for a section's press that goes ahead ("page opened in Obsidian").</summary>
    public static void NoteThePress(Answer answer, string courseCode, int section) =>
        ActivityTrail.Note(ActivityTrail.Event.PageOpenedInObsidian, TrailWords(answer), courseCode, section);
}
