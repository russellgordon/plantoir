using System.Text;
using Plantoir.Core.Models;

namespace Plantoir.Core.Assist;

/// <summary>
/// Class pages students can see that are dated after the NEXT class day
/// (#475, the mac's <c>ClassesDatedLater</c>): a lesson put up early by
/// mistake, caught at Deploy before it goes out.
/// </summary>
/// <remarks>
/// <para><b>The rule is the contract's</b>, <c>class-planning.json</c> →
/// <c>futureDatedClasses</c>, and <c>FutureDatedClassesContractTests</c> runs
/// its cases on real files through this reader. In short: a class page is a
/// page in the section's class folders (<see cref="ClassFolderRule"/>, folder
/// MEMBERSHIP, so a club's "Week 5" counts), never an <c>index.md</c>; the
/// next class day is the earliest date strictly after today among them,
/// hidden ones included — so tomorrow's class, published the evening before
/// on purpose, is never asked about, and a hidden 9th does not shelter a
/// published 14th; flagged is a class students can see (as the BUILT site
/// reads it, an unreadable flag counting as visible) dated after that day,
/// unless the teacher kept it at that same date (<see cref="LaterClassesKept"/>).</para>
///
/// <para><b>The date is the day as WRITTEN</b> — the first ten characters of
/// <c>created</c>, never converted to this computer's zone, and never
/// <c>AssistWorkspace.DateOf</c>, which parses a moment: the class on
/// <c>2026-10-09T00:30+1300</c> is the 9th's class wherever the computer is.</para>
///
/// <para><b>Today is the caller's</b>, decided once when the question is put:
/// an answer given after midnight acts on the list asked about. Nothing here
/// reads a clock, so the contract's cases and the scenarios pin it.</para>
/// </remarks>
public static class ClassesDatedLater
{
    /// <summary>One class page, as the rule sees it.</summary>
    /// <param name="Place">Its place in the course folder, without <c>.md</c>, precomposed: <c>section1/All Classes/Unit 2, Day 5</c>.</param>
    /// <param name="Title">Its file name without <c>.md</c>.</param>
    /// <param name="Date">The day its <c>created</c> names, as written; null when it has none.</param>
    /// <param name="Visible">Whether students meet it on the built site.</param>
    public sealed record Page(string Place, string Title, DateOnly? Date, bool Visible);

    /// <summary>The earliest class date strictly after <paramref name="today"/>, hidden pages included; null when none is.</summary>
    public static DateOnly? NextClassDay(DateOnly today, IEnumerable<Page> classPages)
    {
        DateOnly? earliest = null;
        foreach (var page in classPages)
        {
            if (page.Date is not { } date || date <= today) continue;
            if (earliest is { } soFar && soFar <= date) continue;
            earliest = date;
        }
        return earliest;
    }

    /// <summary>
    /// The rule: the class pages students can see dated after the next class
    /// day, less any kept at that same date — by date, then title.
    /// </summary>
    public static IReadOnlyList<Page> Flagged(IReadOnlyList<Page> classPages, DateOnly today,
                                              IReadOnlyList<LaterClassesKept.Row> kept)
    {
        if (NextClassDay(today, classPages) is not { } next) return Array.Empty<Page>();
        return classPages
            .Where(page => page.Visible && page.Date is { } date && date > next)
            .Where(page => !kept.Any(row => row.Place == page.Place && row.Date == DateText.Iso(page.Date!.Value)))
            .OrderBy(page => page.Date)
            .ThenBy(page => page.Title, StringComparer.OrdinalIgnoreCase)
            .ToList();
    }

    /// <summary>
    /// What would be asked about for one section on <paramref name="today"/>,
    /// read from disk: its class pages and the kept record. Empty for a course
    /// kept for reference, which is never deployed.
    /// </summary>
    public static IReadOnlyList<Page> FlaggedIn(Course course, int section, DateOnly today)
    {
        if (ReferenceCourse.IsKeptForReference(course)) return Array.Empty<Page>();
        return Flagged(ClassPages(course, section), today, LaterClassesKept.Read(course.DirectoryPath, section));
    }

    /// <summary>
    /// The same question asked of pages a teacher is about to PUBLISH
    /// (Section ▸ Publish Pages…): which of <paramref name="places"/> would be
    /// flagged once visible. The next class day is the section's own, counted
    /// over every class page as it is.
    /// </summary>
    public static IReadOnlyList<Page> FlaggedIfPublishing(Course course, int section, DateOnly today,
                                                          IEnumerable<string> places)
    {
        if (ReferenceCourse.IsKeptForReference(course)) return Array.Empty<Page>();
        var picked = places.Select(PlaceKey).ToHashSet(StringComparer.Ordinal);
        var pages = ClassPages(course, section)
            .Select(page => picked.Contains(page.Place) ? page with { Visible = true } : page)
            .ToList();
        return Flagged(pages, today, LaterClassesKept.Read(course.DirectoryPath, section))
            .Where(page => picked.Contains(page.Place))
            .ToList();
    }

    /// <summary>
    /// The section's class pages, read from disk: the folders the shared
    /// membership rule counts, never an <c>index.md</c> — the walk
    /// <c>AssistWorkspace.ClassPages</c> makes — with each page's visibility
    /// as the built site reads it and its date as written.
    /// </summary>
    public static IReadOnlyList<Page> ClassPages(Course course, int section)
    {
        var found = new List<Page>();
        var folders = ClassFolderRule.Names(course.Configuration.ClassFolder, course.Configuration.PerSectionFolders);
        foreach (string folder in folders)
        {
            string root = Path.Combine(course.SectionDirectory(section), folder);
            if (!Directory.Exists(root)) continue;
            foreach (string path in PagePaths.MarkdownPages(root, section))
            {
                if (string.Equals(Path.GetFileName(path), "index.md", StringComparison.OrdinalIgnoreCase)) continue;
                string text;
                try { text = File.ReadAllText(path); }
                catch { continue; }
                bool sectionLocal = PagePaths.IsSectionLocal(course.DirectoryPath, path);
                found.Add(new Page(
                    PlaceOf(course.DirectoryPath, path),
                    Path.GetFileNameWithoutExtension(path),
                    DateWritten(text, section, sectionLocal),
                    !PageFrontmatter.IsDraft(text, section)));
            }
        }
        return found;
    }

    /// <summary>
    /// The first ten characters of the page's <c>created</c> (its section's
    /// key for a page shared between sections), as written; null when there
    /// is none or it does not start with a day.
    /// </summary>
    internal static DateOnly? DateWritten(string pageText, int section, bool sectionLocal)
    {
        string? raw = PageFrontmatter.StoredText(pageText, PageFrontmatter.CreatedKeyFor(section, sectionLocal))
                      ?? PageFrontmatter.StoredText(pageText, "created");
        if (raw is null) return null;
        string value = PageFrontmatter.ScalarText(raw);
        if (value.Length < 10) return null;
        return DateOnly.TryParseExact(value[..10], "yyyy-MM-dd", System.Globalization.CultureInfo.InvariantCulture,
                                      System.Globalization.DateTimeStyles.None, out var day)
            ? day : null;
    }

    /// <summary>
    /// A page's place in the course folder, without <c>.md</c>, folders joined
    /// by "/", in precomposed Unicode — spelled as the links checklist spells
    /// a place (<see cref="LinksChecklist.Key"/>), so a place one writes is a
    /// place the other finds.
    /// </summary>
    public static string PlaceOf(string courseDirectory, string pagePath) =>
        PlaceKey(SectionVerbs.PageName(courseDirectory, pagePath));

    /// <summary>A place as written anywhere, compared in composed form.</summary>
    public static string PlaceKey(string place) => place.Replace('\\', '/').Normalize(NormalizationForm.FormC);

    // ---- The trail's words ------------------------------------------------

    /// <summary><c>laterClassesAsked</c>: where it was asked, how many were flagged, and the answer — counts only.</summary>
    public static string AskedLine(string route, int flagged, int hidden, int kept) =>
        $"asked about classes dated after the next class at {route} — {flagged} flagged, {hidden} hidden, {kept} kept published";

    /// <summary><c>laterClassesAsked</c>, cancelled: nothing written, nothing deployed.</summary>
    public static string CancelledLine(string route, int flagged) =>
        $"asked about classes dated after the next class at {route} — {flagged} flagged, cancelled";

    /// <summary>
    /// <c>laterClassesHeldADeployBack</c>: an assistant's deploy refused while
    /// classes dated later wait on an answer. The contract's line, "{N} with
    /// no answer" — who asked is not part of it.
    /// </summary>
    public static string HeldBackLine(int count) =>
        $"a deploy was held back for classes dated after the next class — {(count == 1 ? "1 class" : $"{count} classes")} with no answer";

    /// <summary>
    /// <c>laterClassesWentOut</c>: a scheduled deploy went out with them —
    /// places, at most ten, the rest counted; names, never anything written
    /// on a page. Null when nothing was flagged.
    /// </summary>
    public static string? WentOutLine(IReadOnlyList<Page> flagged)
    {
        if (flagged.Count == 0) return null;
        string line = string.Join("; ", flagged.Take(10).Select(page => page.Place));
        if (flagged.Count > 10) line += $"; and {flagged.Count - 10} more";
        return "deployed with classes dated after the next class: " + line;
    }
}

/// <summary>
/// What the teacher answered when asked about classes dated after the next
/// class (#475) — at Deploy, or at the in-app assistant's deploy.
/// </summary>
public enum LaterClassesAnswer
{
    /// <summary>Nothing to ask about: the deploy goes ahead.</summary>
    NothingToAsk,

    /// <summary>Answered: the ticked are hidden (or none was ticked), the rest kept; the deploy goes ahead.</summary>
    GoAhead,

    /// <summary>Cancel, Escape, or a hide that left a ticked class visible: nothing deployed.</summary>
    Cancelled,

    /// <summary>Something is already up on the window, so this could not be asked (never waited on).</summary>
    CannotAsk,

    /// <summary>
    /// The in-app assistant's deploy only: classes are flagged and no window
    /// could show the section to ask in. Refused with
    /// <c>deployHasClassesDatedLaterAndNoWindow</c>, naming
    /// <see cref="LaterClassesAtADeploy.Unasked"/>.
    /// </summary>
    NoWindow,
}

/// <summary>
/// What the in-app assistant's deploy met at the question (#475): the answer,
/// and — for <see cref="LaterClassesAnswer.NoWindow"/> — the classes nobody
/// could be asked about, by title, for the sentence that names them.
/// </summary>
public readonly record struct LaterClassesAtADeploy(LaterClassesAnswer Answer, IReadOnlyList<string>? Unasked = null)
{
    public static implicit operator LaterClassesAtADeploy(LaterClassesAnswer answer) => new(answer);
}
