using System.Text;
using FlaUI.Core.AutomationElements;
using FlaUI.Core.Definitions;
using FlaUI.Core.Tools;
using FlaUI.Core.WindowsAPI;
using Plantoir.Core.Assist;
using Plantoir.Core.Models;

namespace Plantoir.UiTests;

/// <summary>
/// #899 W8c-2b: Get Ready for the Start of the Year stopped part way keeps
/// its sheet as the one dialog on screen and shows Russell's offer
/// (<c>startOfYear.wording.stoppedPartWay</c>, then <c>restoreOffer</c>),
/// with two buttons: Restore Course (primary, the default, Enter) and Leave
/// As It Is (the close button, Escape). Go is made to stop part way by the
/// Debug build's <c>--start-of-year-stops-part-way-for-tests</c> (the
/// contract's first stopped case: the second page held open as it is swapped
/// in, the first not put back); a Release build has no such argument. Every
/// wait is on a condition, never a fixed delay.
/// </summary>
[Collection("drives the real app")]
public class StartOfYearRestoreOfferUiTests
{
    private const string Code = "SOY1W";
    private static readonly TimeSpan Patience = TimeSpan.FromSeconds(20);

    private static string DayTwo(DrivenApp app) =>
        Path.Combine(app.WorkspacePath, "courses", Code, "section1", "All Classes", "Unit 1, Day 2.md");

    private static int ArchivedCount(DrivenApp app) => Workspace.FindArchivedItems(app.WorkspacePath).Count;

    /// <summary>The plain year's two classes and their two concepts: Day 2 and Watt go into draft.</summary>
    private static void WriteTheCourse(string coursesDir)
    {
        string dir = Path.Combine(coursesDir, Code);
        var utf8 = new UTF8Encoding(false);
        Directory.CreateDirectory(Path.Combine(dir, "section1", "All Classes"));
        Directory.CreateDirectory(Path.Combine(dir, "Concepts"));
        Directory.CreateDirectory(Path.Combine(dir, "Media"));
        File.WriteAllText(Path.Combine(dir, "course_config.json"),
            "{\"course_code\":\"" + Code + "\",\"course_name\":\"Start of the Year\",\"num_sections\":1,\"section_numbers\":[1]," +
            "\"shared_folders\":[\"Concepts\"],\"per_section_folders\":[\"All Classes\"],\"shared_files\":[],\"per_section_files\":[]}", utf8);
        File.WriteAllText(Path.Combine(dir, "section1", "index.md"), $"# {Code}\n", utf8);
        void Class(string title, string link) => File.WriteAllText(Path.Combine(dir, "section1", "All Classes", title + ".md"),
            $"---\ncreated: 2026-09-08T07:00:00.000-0400\npublish: true\n---\nSee [[{link}]].\n", utf8);
        void Concept(string title) => File.WriteAllText(Path.Combine(dir, "Concepts", title + ".md"),
            "---\ncreatedForSection1: 2026-09-08T07:00:00.000-0400\npublishForSection1: true\n---\n", utf8);
        Class("Unit 1, Day 1", "Ohm's Law");
        Class("Unit 1, Day 2", "Watt");
        Concept("Ohm's Law");
        Concept("Watt");
    }

    /// <summary>Every ContentDialog on screen (each holds a dialog's own buttons).</summary>
    private static int DialogsOnScreen(DrivenApp app)
    {
        int count = 0;
        foreach (var popup in app.Window.FindAllDescendants(cf => cf.ByClassName("Popup").And(cf.ByControlType(ControlType.Window))))
        {
            try
            {
                if (popup.FindFirstDescendant(cf => cf.ByAutomationId("PrimaryButton")) is not null
                    || popup.FindFirstDescendant(cf => cf.ByAutomationId("CloseButton")) is not null) count++;
            }
            catch { }
        }
        return count;
    }

    /// <summary>Opens the sheet from the section's menu, presses Go, and waits for the offer.</summary>
    private static AutomationElement GoStopsPartWay(DrivenApp app)
    {
        app.PressRowMenuItem($"sidebar-{Code}-section1", StartOfYearWording.MenuItem);
        var sheet = Retry.WhileNull(() =>
        {
            var dialog = app.OpenDialog();
            return dialog?.FindFirstDescendant(cf => cf.ByAutomationId("PrimaryButton"))?.Name == StartOfYearWording.GoButton ? dialog : null;
        }, Patience, TimeSpan.FromMilliseconds(250)).Result;
        Assert.True(sheet is not null, "the Get Ready sheet never showed Go: " + app.AnsweredSoFar);
        sheet!.FindFirstDescendant(cf => cf.ByAutomationId("PrimaryButton"))!.AsButton().Invoke();
        var offer = Retry.WhileNull(() =>
        {
            var dialog = app.OpenDialog();
            return dialog?.FindFirstDescendant(cf => cf.ByAutomationId("PrimaryButton"))?.Name == StartOfYearWording.RestoreCourseButton ? dialog : null;
        }, Patience, TimeSpan.FromMilliseconds(250)).Result;
        Assert.True(offer is not null, "Go's sheet never became the offer; the dialog on screen: " + (app.OpenDialog()?.Name ?? "none"));
        return offer!;
    }

    private static DrivenApp Launch() =>
        new(WriteTheCourse, extraArguments: new[] { "--start-of-year-stops-part-way-for-tests" });

    [UiFact]
    public void TheOfferIsTheOneDialogWithItsTwoSentencesAndTwoButtons_EscapeLeavesItAsItIs()
    {
        using var app = Launch();
        var offer = GoStopsPartWay(app);
        string backupName = Path.GetFileName(Workspace.FindBackups(app.WorkspacePath).Single(b => b.CourseCode == Code).FilePath);

        Assert.Equal(1, DialogsOnScreen(app));
        string stopped = StartOfYearWording.Fill(StartOfYearWording.StoppedPartWay, ("section", "1"), ("course", Code));
        string restore = StartOfYearWording.Fill(StartOfYearWording.RestoreOffer, ("course", Code), ("backup", backupName));
        var first = offer.FindFirstDescendant(cf => cf.ByName(stopped));
        var second = offer.FindFirstDescendant(cf => cf.ByName(restore));
        Assert.True(first is not null, "the offer does not say stoppedPartWay");
        Assert.True(second is not null, "the offer does not say restoreOffer");
        Assert.True(first!.BoundingRectangle.Top < second!.BoundingRectangle.Top, "restoreOffer is not under stoppedPartWay");

        var primary = offer.FindFirstDescendant(cf => cf.ByAutomationId("PrimaryButton"))!;
        var close = offer.FindFirstDescendant(cf => cf.ByAutomationId("CloseButton"))!;
        var secondary = offer.FindFirstDescendant(cf => cf.ByAutomationId("SecondaryButton"));
        Assert.Equal(StartOfYearWording.RestoreCourseButton, primary.Name);
        Assert.Equal(StartOfYearWording.LeaveAsItIsButton, close.Name);
        Assert.True(secondary is null || secondary.IsOffscreen, "the offer shows a third button");
        // Microsoft's order: the "do it" button leftmost, the safe one rightmost.
        Assert.True(primary.BoundingRectangle.Left < close.BoundingRectangle.Left, "Restore Course is not left of Leave As It Is");

        int archivedBefore = ArchivedCount(app);
        string dayTwoBefore = File.ReadAllText(DayTwo(app));
        FlaUI.Core.Input.Keyboard.Type(VirtualKeyShort.ESCAPE);
        Assert.True(Retry.WhileFalse(() => app.OpenDialog() is null, Patience).Result, "Escape left the offer up");
        Assert.Equal(archivedBefore, ArchivedCount(app));
        Assert.Equal(dayTwoBefore, File.ReadAllText(DayTwo(app)));
        Assert.True(Workspace.FindBackups(app.WorkspacePath).Any(b => Path.GetFileName(b.FilePath) == backupName), "Leave As It Is lost the backup");
    }

    [UiFact]
    public void EnterIsRestoreCourseAndRestoresWithNoSecondQuestion()
    {
        using var app = Launch();
        GoStopsPartWay(app);
        Assert.Equal(1, DialogsOnScreen(app));
        int archivedBefore = ArchivedCount(app);

        FlaUI.Core.Input.Keyboard.Type(VirtualKeyShort.RETURN);
        // The course comes back as it was before Go: Day 2 is visible again, and the course as it was is archived first.
        Assert.True(Retry.WhileFalse(() => File.ReadAllText(DayTwo(app)).Contains("publish: true", StringComparison.Ordinal)
                                          && ArchivedCount(app) == archivedBefore + 1, Patience).Result,
            "Enter did not restore the course; the dialog on screen: " + (app.OpenDialog()?.Name ?? "none"));
        // No second question, and no error over it.
        Assert.True(Retry.WhileFalse(() => app.OpenDialog() is null, Patience).Result,
            "a dialog stayed up after Restore Course: " + (app.OpenDialog()?.Name ?? ""));
    }
}
