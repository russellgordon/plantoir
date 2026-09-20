using Plantoir.Core.Models;

namespace Plantoir.Core.Assist;

/// <summary>
/// The section's front page, and the one class it puts at the top.
///
/// A section index carries a "Most Recent Class" heading with a single embed
/// under it:
///
/// <code>
/// # Most Recent Class
/// ![[Unit 4, Day 5]]
///
/// ![[Help Sessions]]
/// ![[Key Links]]
/// </code>
///
/// **Which class that is gets COMPUTED, never remembered** — it is the newest
/// class by date that is published in this section. That one decision makes
/// the whole thing correct in both directions and idempotent: publishing an
/// older class the teacher had missed does not drag the front page backwards,
/// and taking the newest class back down falls back to the previous one
/// without a line of code for the case. Recomputing after any change to a
/// class's draft state is enough.
///
/// This is the only place anything here edits a page's BODY rather than its
/// frontmatter, so it holds the same line: find the one line, change it, leave
/// every other byte alone. The teacher's index page may be open in Obsidian.
/// </summary>
public static class SectionIndex
{
    /// <summary>The heading the embed lives under.</summary>
    public const string Heading = "# Most Recent Class";

    public static string PathFor(Course course, int sectionNumber) =>
        Path.Combine(course.SectionDirectory(sectionNumber), "index.md");

    /// <summary>
    /// The newest published class in this section, or null when none is.
    ///
    /// <paramref name="overrides"/> lets a plan ask "what WOULD be most recent
    /// if these pages changed", so the proposal and the result agree.
    /// </summary>
    public static string? MostRecentPublished(
        Course course, int sectionNumber, IReadOnlyList<string> classPages,
        IReadOnlyDictionary<string, bool>? overrides = null,
        IReadOnlyDictionary<string, DateOnly>? dateOverrides = null)
    {
        string? best = null;
        DateOnly bestDate = default;

        foreach (string page in classPages)
        {
            string full = Path.GetFullPath(page);
            string text;
            try { text = File.ReadAllText(page); } catch { continue; }

            bool draft = overrides is not null && overrides.TryGetValue(full, out bool wanted)
                ? wanted
                : PageFrontmatter.IsDraft(text, sectionNumber);
            if (draft) continue;

            DateOnly? date = dateOverrides is not null && dateOverrides.TryGetValue(full, out var moved)
                ? moved
                : PageFrontmatter.CreatedOn(text, sectionNumber,
                    PagePaths.IsSectionLocal(course.DirectoryPath, page));
            if (date is not { } when) continue;

            if (best is null || when > bestDate)
            {
                best = page;
                bestDate = when;
            }
            else if (when == bestDate && best is not null)
            {
                // The course's own word: a tie on date is broken by which page
                // is LATER in the course, and in a Module course neither name
                // parses under the default word, so the tie-break would fall
                // back to whichever file was walked first.
                string unitWord = course.Configuration.UnitWord;
                var currentUd = UnitDay.Parse(Path.GetFileNameWithoutExtension(best), unitWord);
                var newUd = UnitDay.Parse(Path.GetFileNameWithoutExtension(page), unitWord);
                if (newUd is not null && (currentUd is null || newUd.Value.CompareTo(currentUd.Value) > 0))
                {
                    best = page;
                    bestDate = when;
                }
            }
        }
        return best;
    }

    /// <summary>What the index says now: the embedded page's name, or null.</summary>
    public static string? CurrentlyShowing(string indexText)
    {
        if (FindEmbedLine(indexText.Split('\n')) is not { } at) return null;
        string line = indexText.Split('\n')[at].Trim();
        int open = line.IndexOf("[[", StringComparison.Ordinal);
        int close = line.IndexOf("]]", StringComparison.Ordinal);
        if (open < 0 || close <= open) return null;
        string target = line[(open + 2)..close];
        int bar = target.IndexOf('|');
        return (bar >= 0 ? target[..bar] : target).Trim();
    }

    /// <summary>
    /// The index text with its Most Recent Class embed pointing at
    /// <paramref name="className"/>. Returns null when the page has no such
    /// heading — a course that was not built from the example structure — so
    /// the caller can say so rather than inventing a layout for it.
    /// </summary>
    public static string? WithMostRecent(string indexText, string className)
    {
        var lines = indexText.Split('\n');
        if (FindHeadingLine(lines) is not { } heading) return null;

        string embed = "![[" + className + "]]";
        if (FindEmbedLine(lines) is { } at)
        {
            if (lines[at].TrimEnd('\r').Trim() == embed) return indexText;   // already right
            lines[at] = embed + (lines[at].EndsWith('\r') ? "\r" : "");
            return string.Join("\n", lines);
        }

        // The heading is there but nothing under it yet.
        var rebuilt = new List<string>(lines);
        rebuilt.Insert(heading + 1, embed + (lines[heading].EndsWith('\r') ? "\r" : ""));
        return string.Join("\n", rebuilt);
    }

    private static int? FindHeadingLine(string[] lines)
    {
        for (int i = 0; i < lines.Length; i++)
            if (string.Equals(lines[i].TrimEnd('\r').Trim(), Heading, StringComparison.OrdinalIgnoreCase))
                return i;
        return null;
    }

    /// <summary>
    /// The first embed after the heading, skipping blank lines. Stops at the
    /// next heading, so an index with several sections cannot have the wrong
    /// one rewritten.
    /// </summary>
    private static int? FindEmbedLine(string[] lines)
    {
        if (FindHeadingLine(lines) is not { } heading) return null;
        for (int i = heading + 1; i < lines.Length; i++)
        {
            string line = lines[i].TrimEnd('\r').Trim();
            if (line.Length == 0) continue;
            if (line.StartsWith('#')) return null;                       // next section: no embed here
            return line.StartsWith("![[", StringComparison.Ordinal) ? i : null;
        }
        return null;
    }
}
