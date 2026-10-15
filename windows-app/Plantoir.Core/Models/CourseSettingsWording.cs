namespace Plantoir.Core.Models;

/// <summary>
/// Course Settings' own words (#387, mac #369; <c>shared-rules.json</c> →
/// <c>courseSettingsWording</c>). Pinned by <c>CourseSettingsWordingTests</c>.
/// </summary>
/// <remarks>
/// "Language / region (Quartz locale)" named the site builder in a label a
/// teacher reads (CLAUDE.md rule 1) on both platforms; the wizard said
/// "Language / region". Both now say <see cref="LocaleLabel"/>, so the
/// setting has one name wherever it is chosen. REJECTED, as on the mac:
/// keeping "locale" in brackets (a word only a developer uses).
/// </remarks>
public static class CourseSettingsWording
{
    public const string LocaleLabel = "Language and region";
    public const string LocaleCaption = "Used for dates and the words on your website’s own pages.";
    public const string ColourSchemeNoneChosen = "Standard colours (none chosen)";

    // ---- Printing (#496; mac #454, #499) ------------------------------------
    // courseSettingsWording.printing*, pinned key by key by
    // PrintablePagesTests.EveryPrintingWordIsTheContracts, which fails on a
    // fourteenth key nobody added here.

    public const string PrintingHeader = "Printing";
    public const string PrintingSchoolName = "School name";
    public const string PrintingBlanks = "Blanks to fill in";
    public const string PrintingBlankName = "Name";
    public const string PrintingBlankDate = "Date";
    public const string PrintingBlankClassNumber = "Class #";
    public const string PrintingSchoolNameGoes = "School name prints";
    public const string PrintingCourseCodeGoes = "Course code prints";
    public const string PrintingTopLeft = "Top left";
    public const string PrintingBottomLeft = "Bottom left";
    public const string PrintingNotPrinted = "Not printed";
    public const string PrintingCaption =
        "Used on pages whose settings say printable: true, when a student or you press Print.";
    /// <summary>Stands for a page's own title in the sketch of the bottom-left
    /// corner, which prints the title before the course code (#499;
    /// <c>printablePages.footer</c>).</summary>
    public const string PrintingSampleTitle = "Page title";

    /// <summary>How a handout labels its question pages, for the corner
    /// sketch: <c>printablePages.words.pageLabel</c>, the words the page
    /// itself prints.</summary>
    public const string PrintedPageLabel = "Page {n} of {total}";

    /// <summary>The words for one print place (<see cref="CourseConfiguration.PrintPlaces"/>).</summary>
    public static string PrintingPlace(string place) => place switch
    {
        "header_left" => PrintingTopLeft,
        "footer_left" => PrintingBottomLeft,
        _ => PrintingNotPrinted,
    };

    /// <summary>The words for one blank (<see cref="CourseConfiguration.PrintBlankOrder"/>).</summary>
    public static string PrintingBlank(string blank) => blank switch
    {
        "name" => PrintingBlankName,
        "date" => PrintingBlankDate,
        _ => PrintingBlankClassNumber,
    };
}
