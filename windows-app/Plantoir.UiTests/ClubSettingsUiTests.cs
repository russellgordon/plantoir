using System.Text.Json.Nodes;
using FlaUI.Core.AutomationElements;

namespace Plantoir.UiTests;

/// <summary>
/// A club's LOCKED rows in Course Settings (#274 item 6, #387 item 3; mac
/// #376), read off the real window: drawn for a club that recorded them, with
/// the recorded values, the caption under them and Rename… disabled — and
/// NOT drawn at all for an ordinary course. A unit test proves the rule
/// (<c>ClubWizardTests.TheLockedRowsAreShownOnlyWhenRecorded</c>); only this
/// proves a teacher sees it. Written 2026-10-01 with the desktop locked:
/// UNPROVEN until its first run on an unlocked desktop.
/// </summary>
[Collection("drives the real app")]
public class ClubSettingsUiTests
{
    private static JsonNode SettingsRows() =>
        JsonNode.Parse(File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "contracts", "shared-rules.json")))!
            ["wizard"]!["clubToggle"]!["settingsRows"]!;

    [UiFact]
    public void AClubsLockedRowsAreDrawnWithWhatItRecorded()
    {
        using var app = new DrivenApp(CourseFixtures.WriteBothAndAClub);
        app.SelectCourse(CourseFixtures.Club);

        Assert.Equal("Most Recent Meeting", app.Find("clubLockedRow_frontPageHeading", "the front page heading row").Name);
        Assert.Equal("“Week 1”", app.Find("clubLockedRow_pageNaming", "the page naming row").Name);
        Assert.Equal("meeting", app.Find("clubLockedRow_noun", "the noun row").Name);
        // Read off the whole window: the rows' group is a StackPanel, and a
        // panel has no automation peer, so its id "clubLockedRows" never
        // reaches the tree (measured on the first unlocked run, bundle 11).
        Assert.Contains(SettingsRows()["lockedCaption"]!.ToString(), DrivenApp.TextsUnder(app.Window));
        Assert.False(app.Find("renameUnitWordButton", "Rename…").IsEnabled,
                     "Rename… is enabled for a numbered course; a club's word is chosen once, in the wizard.");
    }

    [UiFact]
    public void AnOrdinaryCourseHasNoLockedRows()
    {
        using var app = new DrivenApp(CourseFixtures.WriteBothAndAClub);
        app.SelectCourse(CourseFixtures.NeverAsked);

        // Not "clubLockedRows" (a panel, never in the tree, so it passed
        // vacuously): the rows themselves, and the caption.
        Assert.Null(app.FindOrNull("clubLockedRow_noun", TimeSpan.FromSeconds(2)));
        Assert.DoesNotContain(SettingsRows()["lockedCaption"]!.ToString(), DrivenApp.TextsUnder(app.Window));
        Assert.True(app.Find("renameUnitWordButton", "Rename…").IsEnabled);
    }
}
