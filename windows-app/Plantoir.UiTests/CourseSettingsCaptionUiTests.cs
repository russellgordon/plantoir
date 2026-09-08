using System.Text.Json.Nodes;
using FlaUI.Core.AutomationElements;
using FlaUI.Core.Definitions;
using FlaUI.Core.Tools;

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

    private static string MarksCaption() =>
        JsonNode.Parse(File.ReadAllText(
            Path.Combine(AppContext.BaseDirectory, "contracts", "shared-rules.json")))!
            ["gradedFolders"]!["wording"]!["caption"]!.ToString();


    /// <summary>
    /// The tip is rendered in Course Settings, it is the CONTRACT's sentence
    /// rather than one the view invented, and it can actually be brought into
    /// view.
    ///
    /// <para>Read from the form rather than the window so a stray copy
    /// somewhere else could not satisfy it, and compared against the contract
    /// rather than against <c>SpecialNames</c> so that a constant edited to
    /// match a changed view still fails.</para>
    ///
    /// <para><b>Presence is checked separately from visibility, for the reason
    /// <c>SpecialFoldersHelpUiTests.TheButtonIsInCourseSettingsWhereATeacherCanSeeIt</c>
    /// was written.</b> Being in the UIA tree passes for a control scrolled off
    /// the bottom of this same long form, and the caption sits below all four
    /// list editors. So the form is walked with its own Scroll pattern until
    /// the caption is inside the form's viewport — a plain TextBlock in a
    /// StackPanel offers no ScrollItem pattern of its own, so asking it to
    /// bring itself into view would scroll nothing while appearing to.</para>
    /// </summary>
    [UiFact]
    public void TheContentStructureTipIsOnScreenInCourseSettings()
    {
        using var app = new DrivenApp(CourseFixtures.WriteBoth);
        app.SelectCourse(CourseFixtures.Renamed);

        var form = app.Find("courseSettingsForm", "the Course Settings form");
        ScrollUntilVisible(form, ContentStructureTip(), "the Content Structure tip");
    }

    /// <summary>
    /// Assert a sentence is both PRESENT in the form and can be brought into
    /// its viewport.
    ///
    /// <para>The two are different claims and the second is the one that
    /// matters: being in the UIA tree passes for a control scrolled off the
    /// bottom of this long form. The form is walked with its OWN Scroll
    /// pattern — a TextBlock in a StackPanel offers no ScrollItem pattern, so
    /// asking the caption to bring itself into view would scroll nothing while
    /// appearing to.</para>
    /// </summary>
    private static void ScrollUntilVisible(AutomationElement form, string sentence, string describedAs)
    {
        Assert.Contains(sentence, DrivenApp.TextsUnder(form));

        var scroll = form.Patterns.Scroll.PatternOrDefault;
        Assert.True(scroll is not null, "the Course Settings form offers no scroll pattern");

        bool visible = false;
        for (int step = 0; step <= 10 && !visible; step++)
        {
            scroll!.SetScrollPercent(-1, Math.Min(100, step * 10));
            visible = Retry.WhileFalse(() =>
            {
                var caption = form.FindAllDescendants(cf => cf.ByControlType(ControlType.Text))
                                  .FirstOrDefault(t => SafeName(t) == sentence);
                return caption is not null
                       && !caption.IsOffscreen
                       && !caption.BoundingRectangle.IsEmpty
                       && form.BoundingRectangle.Contains(caption.BoundingRectangle);
            }, TimeSpan.FromSeconds(1), TimeSpan.FromMilliseconds(150)).Result;
        }

        Assert.True(visible,
            $"{describedAs} never came into view anywhere in the Course Settings form");
    }

    /// <summary>A name that cannot throw when the element has gone.</summary>
    private static string SafeName(AutomationElement element)
    {
        try { return element.Name ?? ""; } catch { return ""; }
    }

    /// <summary>
    /// The Marks caption is on screen too, and it is the contract's.
    ///
    /// <para>Its own test rather than a second assertion in the one above,
    /// because it sits FURTHER down the form — Marks comes after Sidebar
    /// Visibility on this platform — and a shared scroll walk would leave
    /// whichever failed ambiguous about which caption was missing.</para>
    ///
    /// <para>It also pins WHERE the caption is drawn, which is a contract
    /// requirement rather than a preference: <c>gradedFolders.wording.rule</c>
    /// says the caption goes BELOW its list, because it reads "a page in one of
    /// these" and above the list "these" followed the section header "Marks"
    /// and referred to nothing. An earlier version of this test claimed to
    /// guard that and did not — it asserted only that the sentence was on
    /// screen, and passed just as happily with the caption back on top.</para>
    /// </summary>
    [UiFact]
    public void TheMarksCaptionIsOnScreenBelowItsList()
    {
        using var app = new DrivenApp(CourseFixtures.WriteBoth);
        app.SelectCourse(CourseFixtures.Renamed);

        var form = app.Find("courseSettingsForm", "the Course Settings form");
        string caption = MarksCaption();
        ScrollUntilVisible(form, caption, "the Marks caption");

        // Tree order is draw order here: the form is a StackPanel, so the
        // caption's position among the form's descendants is where a teacher
        // meets it. Compared against the marks CHECKBOXES rather than the list
        // title, because the title is a Text like the caption and the point is
        // that the caption comes after the whole control.
        string marksTitle = JsonNode.Parse(File.ReadAllText(
            Path.Combine(AppContext.BaseDirectory, "contracts", "shared-rules.json")))!
            ["gradedFolders"]!["wording"]!["listTitle"]!.ToString();

        var everything = form.FindAllDescendants();
        int lastTickBox = -1, captionAt = -1;
        for (int i = 0; i < everything.Length; i++)
        {
            string id = SafeAutomationId(everything[i]);
            if (id.StartsWith($"member:{marksTitle}:", StringComparison.Ordinal)) lastTickBox = i;
            if (captionAt < 0 && SafeName(everything[i]) == caption) captionAt = i;
        }

        Assert.True(lastTickBox >= 0, $"no marks tick-boxes found under 'member:{marksTitle}:'");
        Assert.True(captionAt > lastTickBox,
            $"the Marks caption is drawn at {captionAt}, before the last tick-box at {lastTickBox} "
            + "- gradedFolders.wording.rule says it belongs BELOW its list");
    }

    /// <summary>An automation id that cannot throw when the element has gone.</summary>
    private static string SafeAutomationId(AutomationElement element)
    {
        try { return element.AutomationId ?? ""; } catch { return ""; }
    }
}
