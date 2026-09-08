using System.Text.Json.Nodes;

namespace Plantoir.UiTests;

/// <summary>
/// The captions in Course Settings, read off the real window.
///
/// <para><b>Why this exists at all.</b> A caption is the one kind of
/// teacher-facing sentence a unit test cannot vouch for. Pinning
/// <c>SpecialNames.ContentStructureTip</c> against the contract proves the
/// words are right; it proves nothing about whether anybody ever sees them.
/// Delete the line that adds it to the form and every one of the unit tests
/// stays green while the sentence vanishes from the product — which is
/// precisely the regression <c>NoBlockedSentenceInTheContractIsUnusedHere</c>
/// was written to catch for the removal-blocked sentences, and which the
/// Content Structure tip is deliberately outside of, because it carries no
/// <c>reason</c> key.</para>
///
/// <para>Serialised with the other suites that drive the app: two at once
/// would fight over the foreground window.</para>
/// </summary>
[Collection("drives the real app")]
public class CourseSettingsCaptionUiTests
{
    private static string ContentStructureTip() =>
        JsonNode.Parse(File.ReadAllText(
            Path.Combine(AppContext.BaseDirectory, "contracts", "shared-rules.json")))!
            ["specialNames"]!["contentStructureTip"]!["message"]!.ToString();

    /// <summary>
    /// The tip is rendered in Course Settings, and it is the CONTRACT's
    /// sentence rather than one the view invented.
    ///
    /// <para>Read from the form rather than the window so a stray copy
    /// somewhere else could not satisfy it, and compared against the contract
    /// rather than against <c>SpecialNames</c> so that a constant edited to
    /// match a changed view still fails.</para>
    /// </summary>
    [UiFact]
    public void TheContentStructureTipIsOnScreenInCourseSettings()
    {
        using var app = new DrivenApp(CourseFixtures.WriteBoth);
        app.SelectCourse(CourseFixtures.Renamed);

        var form = app.Find("courseSettingsForm", "the Course Settings form");
        var said = DrivenApp.TextsUnder(form);

        Assert.Contains(ContentStructureTip(), said);
    }
}
