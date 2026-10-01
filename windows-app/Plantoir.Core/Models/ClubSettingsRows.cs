namespace Plantoir.Core.Models;

/// <summary>
/// Course Settings' LOCKED rows for a club's three settings (#274 item 6,
/// #387 item 3; <c>shared-rules.json</c> → <c>wizard.clubToggle.settingsRows</c>).
/// </summary>
/// <remarks>
/// <para><b>A row is drawn only when the course RECORDED its key</b> — present
/// with a non-blank string, surrounding spaces trimmed (<c>shownWhen</c>, mac
/// #376). The group and its caption go when no row is drawn. A value this app
/// does not know (a scheme a newer app wrote) IS drawn, as this app reads it.
/// The retired "Not recorded — …" sentence (<c>frontPageHeadingNotSet</c>) is
/// never built: Russell retired it 2026-09-27 because a row that can never
/// change and records nothing tells a teacher nothing, and showing a DERIVED
/// default ("Most Recent Class") would state something CODING's front page
/// does not say.</para>
/// </remarks>
public static class ClubSettingsRows
{
    public const string PageNamingLabel = "Class pages are named";
    public const string FrontPageHeadingLabel = "Front page heading";
    public const string NounLabel = "The assistant calls a page a";
    public const string LockedCaption =
        "Chosen when the course was made. An existing course keeps these; they cannot be changed here.";

    /// <summary>One locked row: the contract's key name, its label and its value.</summary>
    public sealed record Row(string Key, string Label, string Value);

    /// <summary>The rows to draw, in order; empty means no group at all.</summary>
    public static IReadOnlyList<Row> Shown(CourseConfiguration configuration)
    {
        var rows = new List<Row>();
        if (Recorded(configuration.ClassPageSchemeRaw))
            rows.Add(new Row("pageNaming", PageNamingLabel, $"“{configuration.Naming.Title(1, 1)}”"));
        if (Recorded(configuration.FrontPageHeading))
            rows.Add(new Row("frontPageHeading", FrontPageHeadingLabel, configuration.FrontPageHeading!));
        if (Recorded(configuration.ClassNounRaw))
            rows.Add(new Row("noun", NounLabel, configuration.ClassNoun == ClassNoun.Meeting ? "meeting" : "class"));
        return rows;
    }

    private static bool Recorded(string? raw) => !string.IsNullOrWhiteSpace(raw);
}
