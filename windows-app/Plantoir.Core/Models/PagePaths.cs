using System.Text.RegularExpressions;

namespace Plantoir.Core.Models;

/// <summary>
/// Where a page sits, and whether it is somewhere we are allowed to touch.
///
/// Every path an outside caller hands us — an AI assistant over MCP, most of
/// all — is treated as hostile until it resolves to a real location inside the
/// working folder. The check is done on the FULL resolved path, after symlinks
/// and <c>..</c> have been flattened, because "courses/ICS3U/../../../etc" is
/// a perfectly ordinary-looking string right up until it isn't.
/// </summary>
public static class PagePaths
{
    /// <summary>Folders that are the toolchain's business, never a teacher's page.</summary>
    public static readonly IReadOnlyList<string> NotContent = new[]
    {
        ".merged_output", ".netlify_sites", ".obsidian", ".git", "node_modules", "_backups",
    };

    /// <summary>
    /// True when <paramref name="candidate"/> is <paramref name="root"/> or
    /// sits underneath it. Compared as full paths with a trailing separator,
    /// so <c>C:\work</c> does not appear to contain <c>C:\workshop</c>.
    /// </summary>
    public static bool Contains(string root, string candidate)
    {
        string rootFull = WithSeparator(Path.GetFullPath(root));
        string candidateFull = Path.GetFullPath(candidate);
        if (PathsEqual(WithSeparator(candidateFull), rootFull)) return true;
        return candidateFull.StartsWith(rootFull, PathComparison);
    }

    /// <summary>
    /// True when <paramref name="candidate"/> is a curriculum page of the
    /// course at <paramref name="courseDirectory"/>: some FOLDER between the
    /// course and the page has "curriculum" in its name, case-insensitively
    /// (shared-rules.json → followingLinks.neverTakenDownByFollowingLinks,
    /// curriculumRules.isCurriculumPage). The file name never counts (#615):
    /// "Curriculum Coverage.md" in an ordinary folder is an ordinary page, as
    /// it is on the mac (<c>AssistCurriculumMentions.isCurriculum(pageAt:in:)</c>).
    ///
    /// Only folders INSIDE the course are read, so a working folder called
    /// "Curriculum Work" does not make every page curriculum. A RELATIVE
    /// candidate is false rather than read against the process's working
    /// directory — which is what a path relative to the WORKING folder (a
    /// <c>PlannedPage.RelativePath</c>) would silently be; resolve it with
    /// <see cref="ResolveInside"/> first. A page outside the course, or a path
    /// that cannot be read, is false too.
    /// </summary>
    public static bool IsCurriculum(string courseDirectory, string candidate)
    {
        if (string.IsNullOrWhiteSpace(courseDirectory) || string.IsNullOrWhiteSpace(candidate)) return false;
        if (!Path.IsPathFullyQualified(candidate)) return false;

        string relative;
        try { relative = Path.GetRelativePath(Path.GetFullPath(courseDirectory), Path.GetFullPath(candidate)); }
        catch { return false; }
        if (Path.IsPathRooted(relative)) return false;                    // another drive

        var segments = relative.Split(new[] { Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar },
                                      StringSplitOptions.RemoveEmptyEntries);
        if (segments.Length == 0 || segments[0] == "..") return false;    // outside the course
        for (int i = 0; i < segments.Length - 1; i++)                     // folders only, never the file name
            if (segments[i].Contains("curriculum", StringComparison.OrdinalIgnoreCase)) return true;
        return false;
    }

    /// <summary>
    /// What a teacher calls this page (Quartz displayName).
    /// Follows contracts/shared-rules.json -> pageNaming:
    /// 1. the frontmatter title, unless it is literally "index"
    /// 2. for a file called index.md, the name of its FOLDER
    /// 3. otherwise the file name without .md
    /// </summary>
    public static string DisplayTitle(string filePath, string pageText)
    {
        string? declared = PageFrontmatter.StoredText(pageText, "title");
        if (!string.IsNullOrWhiteSpace(declared))
        {
            string tidied = declared.Trim('"', '\'', ' ', '\t', '\r', '\n');
            if (!string.IsNullOrEmpty(tidied) && !string.Equals(tidied, "index", StringComparison.OrdinalIgnoreCase))
            {
                return tidied;
            }
        }
        string fileName = Path.GetFileNameWithoutExtension(filePath);
        if (string.Equals(fileName, "index", StringComparison.OrdinalIgnoreCase))
        {
            string? dir = Path.GetFileName(Path.GetDirectoryName(filePath));
            if (!string.IsNullOrEmpty(dir))
            {
                return dir;
            }
        }
        return fileName;
    }

    /// <summary>
    /// Resolve a caller-supplied path against <paramref name="root"/> and
    /// confirm it stays inside. Throws <see cref="OutsideWorkspaceException"/>
    /// otherwise — a refusal, not a clamp: silently rewriting a path to
    /// something "safe" would act on a file nobody asked about.
    /// </summary>
    public static string ResolveInside(string root, string relativeOrAbsolute)
    {
        string raw = relativeOrAbsolute.Trim();
        if (raw.Length == 0)
            throw new OutsideWorkspaceException("No page was named.");

        string combined = Path.IsPathRooted(raw) ? raw : Path.Combine(root, raw);
        string full;
        try { full = Path.GetFullPath(combined); }
        catch (Exception error) { throw new OutsideWorkspaceException($"That path can’t be read: {error.Message}"); }

        if (!Contains(root, full))
            throw new OutsideWorkspaceException(
                "That path is outside this working folder, so it can’t be opened from here.");
        return full;
    }

    /// <summary>
    /// The section number when a path sits under <c>section&lt;N&gt;/</c> of
    /// its course, or null when it is course-level (shared by every section).
    /// This is what decides between a plain <c>draft:</c> and a per-section
    /// <c>draftSection&lt;N&gt;:</c>, so it reads the layout on disk rather
    /// than trusting anyone's claim about the page.
    /// </summary>
    public static int? SectionOf(string courseDirectory, string pagePath)
    {
        string relative;
        try { relative = Path.GetRelativePath(Path.GetFullPath(courseDirectory), Path.GetFullPath(pagePath)); }
        catch { return null; }
        if (relative.StartsWith("..", StringComparison.Ordinal)) return null;

        string first = relative.Split(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar)[0];
        var match = Regex.Match(first, @"^section(\d+)$", RegexOptions.IgnoreCase);
        return match.Success && int.TryParse(match.Groups[1].Value, out int number) ? number : null;
    }

    /// <summary>True when the page belongs to exactly one section.</summary>
    public static bool IsSectionLocal(string courseDirectory, string pagePath) =>
        SectionOf(courseDirectory, pagePath) is not null;

    /// <summary>
    /// Every Markdown page of a course that could be published, newest layout
    /// rules applied: build artefacts, Obsidian's own folder and backups are
    /// not pages. When <paramref name="sectionNumber"/> is given, other
    /// sections' folders are left out too — a class page in section 1 has no
    /// business linking into section 2.
    /// </summary>
    public static List<string> MarkdownPages(string courseDirectory, int? sectionNumber = null)
    {
        var pages = new List<string>();
        Walk(courseDirectory);
        pages.Sort(StringComparer.OrdinalIgnoreCase);
        return pages;

        void Walk(string directory)
        {
            IEnumerable<string> entries;
            try { entries = Directory.EnumerateFileSystemEntries(directory); }
            catch { return; }

            foreach (string entry in entries)
            {
                string name = Path.GetFileName(entry);
                bool isDirectory;
                try { isDirectory = (File.GetAttributes(entry) & FileAttributes.Directory) != 0; }
                catch { continue; }

                if (isDirectory)
                {
                    if (name.StartsWith('.') || NotContent.Contains(name, StringComparer.OrdinalIgnoreCase))
                        continue;
                    // A sectionN folder that is not OUR section is another
                    // section's content; skip it rather than resolve into it.
                    var match = Regex.Match(name, @"^section(\d+)$", RegexOptions.IgnoreCase);
                    if (match.Success && sectionNumber is { } wanted &&
                        int.TryParse(match.Groups[1].Value, out int found) && found != wanted)
                        continue;
                    Walk(entry);
                }
                else if (name.EndsWith(".md", StringComparison.OrdinalIgnoreCase) && !name.StartsWith('.'))
                {
                    pages.Add(entry);
                }
            }
        }
    }

    private static StringComparison PathComparison =>
        OperatingSystem.IsWindows() ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal;

    private static bool PathsEqual(string a, string b) => string.Equals(a, b, PathComparison);

    private static string WithSeparator(string path) =>
        path.EndsWith(Path.DirectorySeparatorChar) ? path : path + Path.DirectorySeparatorChar;
}

/// <summary>A caller asked for something outside the folder the server is locked to.</summary>
public sealed class OutsideWorkspaceException(string message) : Exception(message);
