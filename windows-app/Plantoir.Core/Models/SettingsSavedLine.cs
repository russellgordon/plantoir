namespace Plantoir.Core.Models;

/// <summary>
/// The <c>settings saved</c> trail line (<c>activityTrail.mustRecord</c>),
/// built here rather than inline in Course Settings' Save so it can be
/// tested. Since #496 (mac #454) it says what a Save changed about PRINTING:
/// whether the school name was set, changed or cleared — never the name,
/// which is something a teacher wrote (rule 5) — the blanks before → after,
/// and where the school name and the course code print, before → after;
/// only the parts that changed. The printing clause sits where the mac puts
/// it (<c>SettingsSaveNotice.trailLine</c>): after the course, before what
/// the Save kept or replaced from elsewhere.
/// </summary>
/// <remarks>
/// This line already differed from the mac's before #496 (Windows says
/// "; kept from elsewhere: X" and has no "— sidebar:" part); that is left as
/// it was, and only the printing clause is shared word for word.
/// </remarks>
public static class SettingsSavedLine
{
    /// <summary>The printing settings as one Save found or left them.</summary>
    public sealed record PrintingSnapshot(string SchoolName, IReadOnlyList<string> Blanks, string SchoolNameAt, string CourseCodeAt)
    {
        /// <summary>What a course with no printing settings prints.</summary>
        public static readonly PrintingSnapshot Defaults = new("", ["name", "date"], "header_left", "footer_left");

        public static PrintingSnapshot From(CourseConfiguration configuration) => new(
            configuration.PrintSchoolName.Trim(), configuration.PrintBlanks,
            configuration.PrintSchoolNameAt, configuration.PrintCourseCodeAt);
    }

    /// <summary>
    /// What a Save changed about printing, or null when it changed nothing. A
    /// file that could not be read before the Save (null) compares with the
    /// defaults.
    /// </summary>
    public static string? PrintingClause(PrintingSnapshot? before, PrintingSnapshot after)
    {
        var earlier = before ?? PrintingSnapshot.Defaults;
        var parts = new List<string>();
        if (earlier.SchoolName != after.SchoolName)
        {
            parts.Add(earlier.SchoolName.Length == 0 ? "school name set"
                : after.SchoolName.Length == 0 ? "school name cleared"
                : "school name changed");
        }
        if (!earlier.Blanks.SequenceEqual(after.Blanks))
            parts.Add("blanks " + BlankWords(earlier.Blanks) + " → " + BlankWords(after.Blanks));
        if (earlier.SchoolNameAt != after.SchoolNameAt)
            parts.Add("school name " + PlaceWords(earlier.SchoolNameAt) + " → " + PlaceWords(after.SchoolNameAt));
        if (earlier.CourseCodeAt != after.CourseCodeAt)
            parts.Add("course code " + PlaceWords(earlier.CourseCodeAt) + " → " + PlaceWords(after.CourseCodeAt));
        return parts.Count == 0 ? null : string.Join("; ", parts);
    }

    /// <summary>The whole line: "saved the settings for X", then printing, then what was kept or replaced.</summary>
    public static string Compose(string courseCode, CourseConfiguration.SaveReport report,
        PrintingSnapshot? printingBefore, PrintingSnapshot printingAfter)
    {
        string line = "saved the settings for " + courseCode;
        if (PrintingClause(printingBefore, printingAfter) is { } clause) line += "; printing: " + clause;
        if (report.KeptFromElsewhere.Count > 0)
            line += "; kept from elsewhere: " + string.Join(", ", report.KeptFromElsewhere);
        if (report.ReplacedChangesFromElsewhere.Count > 0)
            line += "; replaced a change made elsewhere to: " + string.Join(", ", report.ReplacedChangesFromElsewhere);
        return line;
    }

    private static string BlankWords(IReadOnlyList<string> blanks) =>
        blanks.Count == 0 ? "none" : string.Join(", ", blanks.Select(CourseSettingsWording.PrintingBlank));

    private static string PlaceWords(string place) => CourseSettingsWording.PrintingPlace(place).ToLowerInvariant();
}
