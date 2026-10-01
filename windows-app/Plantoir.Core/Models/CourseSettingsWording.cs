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
}
