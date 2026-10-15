using Newtonsoft.Json.Linq;

namespace Plantoir.Core.Models;

/// <summary>
/// What a printed handout carries in its corners (#496; mac #454, #499),
/// composed by the BUILD's rule — <c>scripts/print_settings.py</c> →
/// <c>compose</c>, held against <c>shared-rules.json</c> →
/// <c>printablePages.corners.cases</c> — so Course Settings' sketch says what
/// the paper will say.
/// </summary>
/// <remarks>
/// The build is the authority: it writes the corners into each section's
/// Quartz on every build, and this app only draws a sketch of them. Where
/// the two could differ, this follows the Python — a <c>print_blanks</c> of
/// JSON null is Name and Date here, as it is on paper (the corners case
/// "blanks of null are the default"; the mac read it as no blanks until
/// told, rule 4).
/// </remarks>
public static class PrintCorners
{
    /// <summary>Each blank's line of underscores (<c>corners.blankLines</c>).</summary>
    public static readonly IReadOnlyDictionary<string, int> BlankLines =
        new Dictionary<string, int> { ["name"] = 24, ["date"] = 12, ["class_number"] = 6 };

    /// <summary>Between two blanks (<c>corners.blankJoin</c>).</summary>
    public const string BlankJoin = "     ";

    /// <summary>Between a school name and a course code in one corner.</summary>
    public const string Joiner = " · ";

    /// <summary>The three corners a course's settings decide; the fourth is always the page label.</summary>
    public sealed record Corners(string TopLeft, string TopRight, string BottomLeft);

    /// <summary>
    /// The corners for <paramref name="settings"/> (a course_config.json's
    /// object) in the course folder <paramref name="folder"/>.
    /// </summary>
    public static Corners Compose(JObject settings, string folder)
    {
        var configuration = CourseConfiguration.FromDictionary((JObject)settings.DeepClone());
        string school = PrintedSchoolName(settings);
        string code = DisplayedCode(configuration, folder);
        return Compose(school, configuration.PrintSchoolNameAt, code, configuration.PrintCourseCodeAt,
            configuration.PrintBlanks, full: true);
    }

    /// <summary>
    /// The sketch Course Settings draws, from the settings being edited: the
    /// same placement rule, the blanks drawn short (the sketch is a picture
    /// of the corners, not the paper's own line lengths, as on the mac), and
    /// the bottom-left corner led by <see cref="CourseSettingsWording.PrintingSampleTitle"/>,
    /// because the footer prints the page's title first (#499;
    /// <c>printablePages.footer</c>).
    /// </summary>
    public static (string TopLeft, string TopRight, string BottomLeft, string BottomRight) Sketch(
        CourseConfiguration configuration, string displayedCode)
    {
        var corners = Compose(configuration.PrintSchoolName.Trim(), configuration.PrintSchoolNameAt,
            (displayedCode ?? "").Trim().ToUpperInvariant(), configuration.PrintCourseCodeAt,
            configuration.PrintBlanks, full: false);
        string bottomLeft = corners.BottomLeft.Length == 0
            ? CourseSettingsWording.PrintingSampleTitle
            : CourseSettingsWording.PrintingSampleTitle + Joiner + corners.BottomLeft;
        string pageLabel = CourseSettingsWording.PrintedPageLabel.Replace("{n}", "1").Replace("{total}", "3");
        return (corners.TopLeft, corners.TopRight, bottomLeft, pageLabel);
    }

    private static Corners Compose(string school, string schoolAt, string code, string codeAt,
        IReadOnlyList<string> blanks, bool full)
    {
        var topLeft = new List<string>();
        var bottomLeft = new List<string>();
        void Place(string text, string at)
        {
            if (text.Length == 0) return;
            if (at == "header_left") topLeft.Add(text);
            else if (at == "footer_left") bottomLeft.Add(text);
        }
        Place(school, schoolAt);
        Place(code, codeAt);
        var blankTexts = blanks.Select(blank =>
            CourseSettingsWording.PrintingBlank(blank) + " " + new string('_', full ? BlankLines[blank] : 6));
        return new Corners(
            string.Join(Joiner, topLeft),
            string.Join(full ? BlankJoin : "   ", blankTexts),
            string.Join(Joiner, bottomLeft));
    }

    /// <summary>The school name, trimmed; none is "". Only text counts: the
    /// app writes nothing else, and the build's own reading of a number or a
    /// list (Python's str()) is not a school name anybody chose.</summary>
    private static string PrintedSchoolName(JObject settings) =>
        settings["print_school_name"] is JValue { Type: JTokenType.String } text ? ((string)text!).Trim() : "";

    /// <summary>
    /// The code a teacher reads, in capitals: <c>course_code</c> for a course
    /// kept for reference, the folder's name otherwise
    /// (<see cref="ReferenceCourse.ShownCode"/>'s rule).
    /// </summary>
    private static string DisplayedCode(CourseConfiguration configuration, string folder)
    {
        string code = folder;
        if (configuration.KeptForReference)
        {
            string stored = CourseCodeValidator.Normalize(configuration.CourseCode);
            if (stored.Length > 0) code = stored;
        }
        return code.Trim().ToUpperInvariant();
    }
}
