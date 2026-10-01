using System.Text;
using System.Text.Json.Nodes;
using FlaUI.Core.AutomationElements;
using FlaUI.Core.Definitions;
using FlaUI.Core.Input;
using FlaUI.Core.Tools;

namespace Plantoir.UiTests;

/// <summary>
/// A course kept for reference, through the real window (#241): what is
/// WITHHELD is absent (not disabled), the summary replaces the settings form,
/// and the calm note comes before Obsidian. The marked course is made by
/// writing its settings — no lock is needed, because nothing here depends on
/// one — and nothing presses Deploy, Preview or Import.
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
            config["shared_folders"] = new JsonArray();
            config["per_section_folders"] = new JsonArray();
            config["shared_files"] = new JsonArray();
            config["per_section_files"] = new JsonArray();
            string dir = Path.Combine(coursesDir, folder);
            Directory.CreateDirectory(Path.Combine(dir, "section1"));
            File.WriteAllText(Path.Combine(dir, "section1", "index.md"), "# Section 1\n", new UTF8Encoding(false));
            File.WriteAllText(Path.Combine(dir, "course_config.json"), config.ToJsonString(), new UTF8Encoding(false));
        }
    }

    private static string NeverDeployed() =>
        JsonNode.Parse(File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "contracts", "shared-rules.json")))!
            ["referenceCourses"]!["wording"]!["neverDeployed"]!.ToString().Replace("{course}", "ICS3U");

    private static void Click(DrivenApp app, string automationId, string describedAs) =>
        app.Find(automationId, describedAs).Click();

    [UiFact]
    public void AReferenceCourseHasNoDeployButtonAndNoRepairButton()
    {
        using var app = new DrivenApp(WriteCourses);

        Click(app, "sidebar-" + Folder, "the reference course's row");
        var summary = app.Find("referenceSummary", "the read-only summary");
        Assert.Contains(NeverDeployed(), DrivenApp.TextsUnder(summary));
        Assert.Null(app.FindOrNull("courseSettingsForm", TimeSpan.FromSeconds(2)));      // the form is not drawn

        Click(app, $"sidebar-{Folder}-section1", "its section");
        Assert.NotNull(app.FindOrNull("SectionTitle", TimeSpan.FromSeconds(8)));
        Assert.Null(app.FindOrNull("DeployButton", TimeSpan.FromSeconds(2)));            // ABSENT, not disabled
        Assert.Contains(NeverDeployed(), DrivenApp.TextsUnder(app.Window));

        // And the live course of the same code still has its button.
        Click(app, "sidebar-ICS3U-section1", "the live course's section");
        Assert.NotNull(app.FindOrNull("DeployButton", TimeSpan.FromSeconds(8)));
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
