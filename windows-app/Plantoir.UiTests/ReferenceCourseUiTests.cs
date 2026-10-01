using System.Text;
using System.Text.Json.Nodes;
using FlaUI.Core.AutomationElements;
using FlaUI.Core.Definitions;
using FlaUI.Core.Input;
using FlaUI.Core.Tools;
using Plantoir.Core.Models;

namespace Plantoir.UiTests;

/// <summary>
/// A course kept for reference, through the real window (#241): what is
/// WITHHELD is absent (not disabled), the summary replaces the settings form,
/// the calm note comes before Obsidian, the pages are LOCKED on disk, Keep a
/// Copy for Reference… makes one and refuses a second for the same year in the
/// contract's words, and a reference course is never a place Copy a Page puts
/// anything. The marked course is made by writing its settings; the app locks
/// it when it reads the folder, as it does every reference course.
/// </summary>
[Collection("drives the real app")]
public class ReferenceCourseUiTests
{
    private const string Folder = "ICS3U-2025";

    private static void WriteCourses(string coursesDir)
    {
        foreach (var (folder, config) in new[]
                 {
                     ("ICS3U", new JsonObject { ["course_code"] = "ICS3U", ["course_name"] = "Computer Science" }),
                     (Folder, new JsonObject
                     {
                         ["course_code"] = "ICS3U", ["course_name"] = "Computer Science",
                         ["kept_for_reference"] = true, ["reference_school_year"] = 2025,
                         ["deploy_target"] = "local_folder", ["deploy_folder_path"] = "",
                     }),
                 })
        {
            config["num_sections"] = 1;
            config["section_numbers"] = new JsonArray(1);
            config["shared_folders"] = new JsonArray("Concepts");
            config["per_section_folders"] = new JsonArray();
            config["shared_files"] = new JsonArray();
            config["per_section_files"] = new JsonArray();
            string dir = Path.Combine(coursesDir, folder);
            Directory.CreateDirectory(Path.Combine(dir, "section1"));
            Directory.CreateDirectory(Path.Combine(dir, "Concepts"));
            File.WriteAllText(Path.Combine(dir, "section1", "index.md"), "# Section 1\n", new UTF8Encoding(false));
            // A page in a shared folder, so Copy a Page has something to offer
            // and its answer about DESTINATIONS is the one being asked.
            File.WriteAllText(Path.Combine(dir, "Concepts", "Recursion.md"), "---\ntitle: Recursion\n---\nBody\n", new UTF8Encoding(false));
            File.WriteAllText(Path.Combine(dir, "course_config.json"), config.ToJsonString(), new UTF8Encoding(false));
        }
    }

    private static string NeverDeployed() =>
        EndToEnd.Say(EndToEnd.ReferenceWording["neverDeployed"]!, ("course", "ICS3U"));

    private static void Click(DrivenApp app, string automationId, string describedAs) =>
        app.Find(automationId, describedAs).Click();

    [UiFact]
    public void AReferenceCourseHasNoDeployButtonAndNoRepairButton()
    {
        using var app = new DrivenApp(WriteCourses);

        Click(app, "sidebar-" + Folder, "the reference course's row");
        var summary = app.Find("referenceSummary", "the read-only summary");
        var said = DrivenApp.TextsUnder(summary);
        Assert.Contains(NeverDeployed(), said);
        Assert.Contains(EndToEnd.ReferenceWording["pagesAreLocked"]!.ToString(), said);   // it says so
        Assert.Null(app.FindOrNull("courseSettingsForm", TimeSpan.FromSeconds(2)));      // the form is not drawn

        app.SelectSection(Folder, 1, shownCode: "ICS3U");
        // "deployButton", the id the XAML sets — before bundle 11 this looked
        // for "DeployButton", which matches nothing, so "absent" passed whether
        // or not the button was drawn.
        Assert.Null(app.FindOrNull("deployButton", TimeSpan.FromSeconds(2)));            // ABSENT, not disabled
        Assert.Contains(NeverDeployed(), DrivenApp.TextsUnder(app.Window));

        // And the live course of the same code still has its button.
        app.SelectSection("ICS3U", 1);
        Assert.NotNull(app.FindOrNull("deployButton", TimeSpan.FromSeconds(8)));
    }

    [UiFact]
    public void ItsPagesAreLockedOnDiskAndTheLiveCoursesAreNot()
    {
        using var app = new DrivenApp(WriteCourses);
        string kept = Path.Combine(app.WorkspacePath, "courses", Folder, "Concepts", "Recursion.md");
        string live = Path.Combine(app.WorkspacePath, "courses", "ICS3U", "Concepts", "Recursion.md");
        // Locked off the interface's thread when the folder is read, so waited for.
        Assert.True(Retry.WhileFalse(() => EndToEnd.WritingIsRefused(kept), TimeSpan.FromSeconds(20), TimeSpan.FromMilliseconds(500)).Result,
                    $"a page of the reference course could still be written: {kept}");
        Assert.False(EndToEnd.WritingIsRefused(live), "a page of the course being taught was locked");
    }

    [UiFact]
    public void KeepACopyMakesALockedReferenceCourseAndRefusesASecondForTheSameYear()
    {
        using var app = new DrivenApp(WriteCourses);
        var today = DateOnly.FromDateTime(DateTime.Now);

        app.PressRowMenuItem("sidebar-ICS3U", EndToEnd.ReferenceWording["keepACopyMenuItem"]!.ToString());
        var name = Retry.WhileNull(() => app.OpenDialog()?.FindFirstDescendant(cf => cf.ByControlType(ControlType.Edit)),
                                   TimeSpan.FromSeconds(10), TimeSpan.FromMilliseconds(250)).Result
                   ?? throw new Xunit.Sdk.XunitException("Keep a Copy offered no folder name");
        string folder = name.Patterns.Value.Pattern.Value.Value;
        Assert.Equal($"ICS3U-{SchoolYear.StartingYear(today)}", folder);   // referenceCourses.importing.folderNameProduced
        app.Find("PrimaryButton", "Keep a Copy").AsButton().Invoke();

        Assert.NotNull(Retry.WhileNull(() => app.FindOrNull("sidebar-" + folder, TimeSpan.FromSeconds(1)),
                                       TimeSpan.FromSeconds(60), TimeSpan.FromMilliseconds(500)).Result);
        string copy = Path.Combine(app.WorkspacePath, "courses", folder);
        var config = JsonNode.Parse(File.ReadAllText(Path.Combine(copy, "course_config.json")))!;
        Assert.True(config["kept_for_reference"]!.GetValue<bool>());
        Assert.Equal("ICS3U", config["course_code"]!.ToString());
        Assert.True(Retry.WhileFalse(() => EndToEnd.WritingIsRefused(Path.Combine(copy, "Concepts", "Recursion.md")),
                                     TimeSpan.FromSeconds(20), TimeSpan.FromMilliseconds(500)).Result,
                    "the copy's pages are not locked");
        Assert.False(EndToEnd.WritingIsRefused(Path.Combine(app.WorkspacePath, "courses", "ICS3U", "Concepts", "Recursion.md")),
                     "keeping a copy locked the course being taught");

        // A second copy for the same school year: the sentence beside the field, and no button to press.
        app.PressRowMenuItem("sidebar-ICS3U", EndToEnd.ReferenceWording["keepACopyMenuItem"]!.ToString());
        string refusal = EndToEnd.Say(EndToEnd.ReferenceWording["codeAlreadyInThatYear"]!,
                                      ("code", "ICS3U"), ("year", SchoolYear.Label(SchoolYear.StartingYear(today))));
        Assert.True(Retry.WhileFalse(() => app.OpenDialog() is { } d && DrivenApp.TextsUnder(d).Contains(refusal),
                                     TimeSpan.FromSeconds(10), TimeSpan.FromMilliseconds(300)).Result,
                    $"the second Keep a Copy never said \"{refusal}\"");
        Assert.False(app.Find("PrimaryButton", "Keep a Copy").IsEnabled, "a second copy for the same year could be made");
        app.Find("CloseButton", "Cancel").AsButton().Invoke();
    }

    [UiFact]
    public void AReferenceCourseIsReadByCopyAPageButNeverWrittenTo()
    {
        using var app = new DrivenApp(WriteCourses);
        var wording = EndToEnd.CopyPageWording;

        // From the course being taught: the only other course is kept for
        // reference, so there is nowhere to copy into.
        app.PressRowMenuItem("sidebar-ICS3U", wording["menuItem"]!.ToString());
        string nowhere = wording["thereIsNoCourseToCopyInto"]!.ToString();
        Assert.True(Retry.WhileFalse(() => app.OpenDialog() is { } d && DrivenApp.TextsUnder(d).Contains(nowhere),
                                     TimeSpan.FromSeconds(10), TimeSpan.FromMilliseconds(300)).Result,
                    $"Copy a Page never said \"{nowhere}\"");
        app.Find(CopyAPageDialogIds.Close, "Cancel").AsButton().Invoke();

        // From the reference course: offered (it only READS the course), and
        // the course being taught is where a page would go.
        app.PressRowMenuItem("sidebar-" + Folder, wording["menuItem"]!.ToString());
        var into = app.Find("copyPageDestination", "Copy into").AsComboBox();
        into.Expand();   // a closed WinUI combo box reports no items
        var offered = Retry.WhileEmpty(() => into.Items, TimeSpan.FromSeconds(5), TimeSpan.FromMilliseconds(250)).Result;
        string[] names = offered?.Select(i => i.Text).ToArray() ?? Array.Empty<string>();
        into.Collapse();
        Assert.Equal(new[] { "ICS3U" }, names);
        app.Find(CopyAPageDialogIds.Close, "Cancel").AsButton().Invoke();
    }

    [UiFact]
    public void TheCalmNoteIsShownBeforeObsidianOpens()
    {
        using var app = new DrivenApp(WriteCourses);
        var row = app.Find("sidebar-" + Folder, "the reference course's row");
        row.RightClick();
        var item = Retry.WhileNull(
            () => app.Window.Automation.GetDesktop().FindFirstDescendant(cf => cf.ByName("Open in Obsidian").And(cf.ByControlType(ControlType.MenuItem))),
            TimeSpan.FromSeconds(5), TimeSpan.FromMilliseconds(200)).Result;
        Assert.NotNull(item);
        // The withheld items are not in the menu at all.
        var desktop = app.Window.Automation.GetDesktop();
        foreach (string withheld in new[] { "Rename Course", "Add Section…", "Keep a Copy for Reference…", "Revise with local AI assistant…" })
            Assert.Null(desktop.FindFirstDescendant(cf => cf.ByName(withheld).And(cf.ByControlType(ControlType.MenuItem))));
        if (!item!.IsEnabled)
        {
            Keyboard.Press(FlaUI.Core.WindowsAPI.VirtualKeyShort.ESCAPE);
            return;   // no Obsidian on this machine: the note is reached only through it
        }
        item.Click();
        var note = app.FindOrNull("referenceCalmNote", TimeSpan.FromSeconds(5))
                   ?? Retry.WhileNull(() => desktop.FindFirstDescendant(cf => cf.ByName("About this course’s pages")),
                       TimeSpan.FromSeconds(5), TimeSpan.FromMilliseconds(200)).Result;
        Assert.NotNull(note);
        var cancel = desktop.FindFirstDescendant(cf => cf.ByName("Cancel").And(cf.ByControlType(ControlType.Button)));
        cancel?.Click();
    }
}
