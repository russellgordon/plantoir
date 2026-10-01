using System.Text.Json.Nodes;
using FlaUI.Core.AutomationElements;
using FlaUI.Core.Tools;

namespace Plantoir.UiTests;

/// <summary>
/// Save in Course Settings through the real window (#387, mac #364 #373; #272's
/// Save notices): a freshly opened course reads clean (the failure a model test
/// cannot see is a CONTROL writing on first draw); moving where the course
/// publishes to a place with a problem holds Save back and SAYS so beside it;
/// and a Save with no preview open says "Saved" without offering Preview Again.
/// Written 2026-10-01 with the desktop LOCKED: UNPROVEN until its first run on
/// an unlocked desktop (ruling R10).
/// </summary>
[Collection("drives the real app")]
public class CourseSettingsSaveUiTests
{
    private static string SaveHeldBackOpening() =>
        JsonNode.Parse(File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "contracts", "shared-rules.json")))!
            ["courseSettingsWording"]!["saveHeldBack"]!.ToString().Split("{reason}")[0];

    [UiFact]
    public void AFreshlyOpenedCourseHasNothingToSave()
    {
        using var app = new DrivenApp(CourseFixtures.WriteBothAndAClub);
        foreach (string code in new[] { CourseFixtures.NeverAsked, CourseFixtures.Club })
        {
            app.SelectCourse(code);
            Thread.Sleep(1500);   // let every control draw and settle
            Assert.False(app.Find("saveButton", "Save").IsEnabled, $"{code}: Save is enabled on a fresh open");
            Assert.False(app.Find("revertButton", "Revert").IsEnabled, $"{code}: Revert is enabled on a fresh open");
        }
    }

    [UiFact]
    public void MovingThePublishingToAFolderNotYetChosenIsHeldBackAndSaysWhy()
    {
        using var app = new DrivenApp(CourseFixtures.WriteBothAndAClub);
        app.SelectCourse(CourseFixtures.NeverAsked);

        app.Find("deployTargetPicker", "Deploy to").AsComboBox().Select(2);   // "A folder on this PC", no folder yet
        Assert.True(Retry.WhileFalse(() => app.Find("revertButton", "Revert").IsEnabled, TimeSpan.FromSeconds(3)).Result);
        Assert.False(app.Find("saveButton", "Save").IsEnabled, "Save is enabled for a move to a folder not chosen");
        Assert.StartsWith(SaveHeldBackOpening(), app.Find("savedConfirmation", "the note beside Save").Name);

        app.Find("deployTargetPicker", "Deploy to").AsComboBox().Select(0);   // back to Netlify: nothing unsaved
        Assert.True(Retry.WhileFalse(() => !app.Find("revertButton", "Revert").IsEnabled, TimeSpan.FromSeconds(3)).Result);
        // An EMPTY TextBlock reports no Name at all (PropertyNotSupported,
        // measured on the second run of bundle 11) — that is the empty note.
        string note;
        try { note = app.Find("savedConfirmation", "the note beside Save").Properties.Name.ValueOrDefault ?? ""; }
        catch (FlaUI.Core.Exceptions.PropertyNotSupportedException) { note = ""; }
        Assert.Equal("", note);
    }

    [UiFact]
    public void ASaveWithNoPreviewOpenSaysSavedAndOffersNoPreviewAgain()
    {
        using var app = new DrivenApp(CourseFixtures.WriteBothAndAClub);
        app.SelectCourse(CourseFixtures.NeverAsked);

        var name = app.Find("courseNameField", "Course name").AsTextBox();
        name.Text = "Functions and Relations";
        Assert.True(Retry.WhileFalse(() => app.Find("saveButton", "Save").IsEnabled, TimeSpan.FromSeconds(3)).Result);
        app.Find("saveButton", "Save").AsButton().Invoke();

        Assert.True(Retry.WhileFalse(() => app.Find("savedConfirmation", "the note beside Save").Name.StartsWith("Saved"),
                                     TimeSpan.FromSeconds(3)).Result);
        app.AssertAbsent("previewAgainButton", "Preview Again", TimeSpan.FromSeconds(1));
    }
}
