using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;
using Newtonsoft.Json.Linq;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;

namespace Plantoir.Core.Assist;

/// <summary>
/// Preview offers to show TODAY's class on the section's front page (#406,
/// mac #397; <c>class-planning.json</c> → <c>todaysClassOnTheFrontPage</c>).
/// </summary>
/// <remarks>
/// <para><b>Asked from the Preview BUTTON only.</b> Never from plantoir-mcp,
/// the assistant's preview, a scheduled deploy, a repair's rebuild, Start of
/// the Year or Course Settings: those would block on a question nobody may be
/// watching. This type decides and writes; the section window is the only
/// caller that asks (<c>SectionDetailView.OfferTodaysClass</c>), and a source
/// test pins that no other file calls <see cref="Offer"/>.</para>
///
/// <para><b>Today is the teacher's clock and the page's day as WRITTEN</b> —
/// the first ten characters of its <c>created</c>, never converted
/// (<c>sectionIndexPointer.dateCases.why</c>). Only a class CERTAINLY visible
/// is offered: a <c>publish:</c> this app cannot read is hidden by the build.
/// A front page with no class line is not asked about, although this app's
/// pointer would insert one: where a class belongs on such a page is the
/// teacher's (<c>whenNoClassIsTransclusion</c>).</para>
///
/// <para><b>Rejected</b> (the contract's list): the build detecting it (the
/// answer would come after the preview was built, and the container's clock is
/// not the teacher's); asking inside every preview; following the pointer's own
/// newest-visible target (offers tomorrow's class published early); remembering
/// Not Today for the whole section, or in the app's preferences.</para>
/// </remarks>
public static class TodaysClassOnTheFrontPage
{
    // ---- Wording (todaysClassOnTheFrontPage.wording; pinned by TodaysClassContractTests)

    public static string Question(string @class) => $"Show {@class} on the front page?";
    public static string Because(ClassNoun noun, string shown) =>
        $"Today’s {Noun(noun)} is published, but the front page still shows {shown}.";
    public const string Show = "Show on Front Page";
    public const string NotToday = "Not Today";
    public const string NotChangedTitle = "The Front Page Was Not Changed";
    public static string NoLongerOffered(ClassNoun noun) =>
        $"The front page or today’s {Noun(noun)} changed while you were deciding, so it was left as it is.";
    public static string CouldNotSave(string shown) => $"The front page could not be saved, so it still shows {shown}.";

    private static string Noun(ClassNoun noun) => noun == ClassNoun.Meeting ? "meeting" : "class";

    /// <summary>The class offered and the class the line names, both by file name.</summary>
    public sealed record Offering(string Show, string Shows, string ShowPath);

    /// <summary>What Show on Front Page did.</summary>
    public enum Outcome { Written, AlreadyShows, NoLongerOffered, CouldNotSave }

    private static readonly Regex WrittenDay = new(@"^(\d{4}-\d{2}-\d{2})", RegexOptions.CultureInvariant);

    /// <summary>The day a class is for in this section, the first ten characters as written; null when none.</summary>
    internal static DateOnly? DayAsWritten(string text, int section, bool isSectionLocal)
    {
        string? raw = PageFrontmatter.StoredText(text, PageFrontmatter.CreatedKeyFor(section, isSectionLocal))
                      ?? (isSectionLocal ? null : PageFrontmatter.StoredText(text, "created"));
        if (raw is null) return null;
        string value = raw.Trim().Trim('"', '\'');
        var match = WrittenDay.Match(value);
        return match.Success && DateOnly.TryParseExact(match.Groups[1].Value, "yyyy-MM-dd",
                   CultureInfo.InvariantCulture, DateTimeStyles.None, out var day)
            ? day : null;
    }

    private sealed record ClassFacts(string Path, string Name, bool CertainlyVisible, DateOnly? Day, UnitDay? Number);

    /// <summary>
    /// Whether to ask, and about what — or null. Reads the real files.
    /// </summary>
    /// <param name="classPages">The section's class pages (full paths).</param>
    /// <param name="indexPath">The section's front page.</param>
    public static Offering? Offer(Course course, int section, IReadOnlyList<string> classPages, string indexPath,
                                  DateOnly today)
    {
        if (course.Configuration.KeptForReference) return null;
        if (!File.Exists(indexPath)) return null;
        try
        {
            var attributes = File.GetAttributes(indexPath);
            if (attributes.HasFlag(FileAttributes.ReparsePoint) || attributes.HasFlag(FileAttributes.ReadOnly)) return null;
        }
        catch { return null; }

        string indexText;
        try { indexText = File.ReadAllText(indexPath); } catch { return null; }

        var naming = course.Configuration.Naming;
        var classes = classPages.Select(path =>
        {
            string text;
            try { text = File.ReadAllText(path); } catch { text = ""; }
            bool local = PagePaths.IsSectionLocal(course.DirectoryPath, path);
            string name = System.IO.Path.GetFileNameWithoutExtension(path);
            return new ClassFacts(path, name,
                text.Length > 0 && PageFrontmatter.Visibility(text, section) == PageVisibility.Visible,
                text.Length > 0 ? DayAsWritten(text, section, local) : null,
                naming.Parse(name));
        }).ToList();

        // (1) Today's class: certainly visible, dated today; the higher of the
        // course's own numbering breaks a tie.
        var todays = classes.Where(c => c.CertainlyVisible && c.Day == today)
            .OrderByDescending(c => c.Number ?? new UnitDay(0, 0))
            .FirstOrDefault();
        if (todays is null) return null;

        // (2) The line, found exactly as sectionIndexPointer.found says.
        if (SectionIndex.CurrentlyShowing(indexText, classes.Select(c => c.Name).ToList()) is not { } shownName) return null;
        var shown = classes.First(c => string.Equals(c.Name, shownName, StringComparison.OrdinalIgnoreCase));

        // (3) Not already right: a certainly visible class dated today or later.
        if (shown.CertainlyVisible && shown.Day is { } shownDay && shownDay >= today) return null;

        // (4) Not declined today for this class.
        if (DeclinedToday(course, section, today) == todays.Name) return null;

        return new Offering(todays.Name, shown.Name, todays.Path);
    }

    // ---- Not Today (file-formats.json → frontPageNotToday)

    public static string NotTodayPath(Course course, int section) =>
        System.IO.Path.Combine(course.DirectoryPath, ".publish_state", $"section{section}.front-page-not-today.json");

    /// <summary>The class declined on <paramref name="today"/>, or null.</summary>
    public static string? DeclinedToday(Course course, int section, DateOnly today)
    {
        try
        {
            var record = JObject.Parse(File.ReadAllText(NotTodayPath(course, section)));
            return (string?)record["day"] == today.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture)
                ? (string?)record["class"] : null;
        }
        catch { return null; }
    }

    /// <summary>Not Today: remembered for that section, the day asked and the class offered.</summary>
    public static void RecordNotToday(Course course, int section, DateOnly askedOn, Offering offering)
    {
        string path = NotTodayPath(course, section);
        Directory.CreateDirectory(System.IO.Path.GetDirectoryName(path)!);
        var record = new JObject
        {
            ["version"] = "1",
            ["day"] = askedOn.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture),
            ["class"] = offering.Show,
        };
        File.WriteAllText(path, record.ToString(Newtonsoft.Json.Formatting.Indented) + "\n", new UTF8Encoding(false));
        Note(course, section, $"left the front page as it was — Not Today: {offering.Show} offered, it showed {offering.Shows}");
    }

    /// <summary>
    /// Show on Front Page: read the page AGAIN, decide again for the day the
    /// question was asked, and write only the class that was asked about. An
    /// answer after midnight, or after a later class was published in
    /// Obsidian, writes nothing.
    /// </summary>
    /// <param name="pointerFor">The pointer facts for a class (the workspace's <c>PointerFor</c>).</param>
    /// <param name="tail">The time and offset the section's pages carry.</param>
    public static Outcome ShowOnTheFrontPage(Course course, int section, IReadOnlyList<string> classPages, string indexPath,
                                             DateOnly askedOn, Offering asked,
                                             Func<string, SectionIndex.Pointer> pointerFor, string tail)
    {
        var again = Offer(course, section, classPages, indexPath, askedOn);
        if (again is null)
        {
            bool showsIt = false;
            try
            {
                showsIt = string.Equals(SectionIndex.CurrentlyShowing(File.ReadAllText(indexPath),
                    classPages.Select(p => System.IO.Path.GetFileNameWithoutExtension(p)).ToList()),
                    asked.Show, StringComparison.OrdinalIgnoreCase);
            }
            catch { }
            Note(course, section, showsIt
                ? $"left the front page as it was — already showed today's class: {asked.Show} offered, it showed {asked.Show}"
                : $"left the front page as it was — it changed while the teacher was asked: {asked.Show} offered, it showed {asked.Shows}");
            return showsIt ? Outcome.AlreadyShows : Outcome.NoLongerOffered;
        }
        if (!string.Equals(again.Show, asked.Show, StringComparison.OrdinalIgnoreCase))
        {
            Note(course, section, $"left the front page as it was — it changed while the teacher was asked: {asked.Show} offered, it showed {again.Shows}");
            return Outcome.NoLongerOffered;
        }

        try
        {
            string text = File.ReadAllText(indexPath);
            var day = DayAsWritten(File.ReadAllText(again.ShowPath), section, PagePaths.IsSectionLocal(course.DirectoryPath, again.ShowPath))!.Value;
            if (SectionIndex.PointedAndDated(text, pointerFor(again.ShowPath), day, tail) is not { } written)
                throw new IOException("the front page's class line could not be rewritten");
            File.WriteAllText(indexPath, written, new UTF8Encoding(false));
        }
        catch
        {
            Note(course, section, $"left the front page as it was — could not be saved: {asked.Show} offered, it showed {asked.Shows}");
            return Outcome.CouldNotSave;
        }
        ActivityTrail.Note(ActivityTrail.Event.PutTodaysClassOnTheFrontPage,
            $"{course.Code}/{section} · put today's class on the front page — {asked.Show} in place of {again.Shows}");
        return Outcome.Written;
    }

    private static void Note(Course course, int section, string what) =>
        ActivityTrail.Note(ActivityTrail.Event.LeftTheFrontPageAsItWas, $"{course.Code}/{section} · {what}");
}
