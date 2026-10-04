using System.Text;
using System.Text.Json.Nodes;
using FlaUI.Core.AutomationElements;
using FlaUI.Core.Tools;

namespace Plantoir.UiTests;

/// <summary>
/// The links checklist (#392, #399, #405), driven through the real section
/// window: a fresh checklist the build left behind is offered when the
/// section opens; a row a class BRINGS is shown ticked and disabled once that
/// class is ticked; the button counts the rows shown ticked.
/// </summary>
/// <remarks>
/// What no unit test can see: that the rows are REACHABLE, that the
/// coming-with state reaches the checkbox a teacher looks at, and that the
/// button's words follow it. The rules themselves are pinned by
/// <c>LinksChecklistContractTests</c> in Plantoir.Tests. Nothing is published:
/// the test presses Not Now.
/// </remarks>
[Collection("drives the real app")]
public class LinksChecklistUiTests
{
    private const string Code = "SPH3U";
    private const string ClassPlace = "section1/All Classes/Unit 1, Day 2";
    private const string WorksheetPlace = "Concepts/Worksheet";

    private static void WriteCourseWithAnOffer(string coursesDir)
    {
        string dir = Path.Combine(coursesDir, Code);
        var config = new JsonObject
        {
            ["course_code"] = Code,
            ["course_name"] = "Physics",
            ["shared_folders"] = new JsonArray("Concepts"),
            ["per_section_folders"] = new JsonArray("All Classes"),
            ["shared_files"] = new JsonArray(),
            ["per_section_files"] = new JsonArray(),
            ["num_sections"] = 1,
            ["section_numbers"] = new JsonArray(1),
        };
        Directory.CreateDirectory(Path.Combine(dir, "Concepts"));
        Directory.CreateDirectory(Path.Combine(dir, "section1", "All Classes"));
        var utf8 = new UTF8Encoding(false);
        File.WriteAllText(Path.Combine(dir, "course_config.json"), config.ToJsonString(), utf8);
        File.WriteAllText(Path.Combine(dir, "section1", "index.md"), $"# {Code}\n", utf8);
        File.WriteAllText(Path.Combine(dir, "section1", "All Classes", "Unit 1, Day 1.md"),
            "---\npublish: true\ncreated: 2026-09-08T07:00:00.000-0400\n---\nToday.\n", utf8);
        File.WriteAllText(Path.Combine(dir, "section1", "All Classes", "Unit 1, Day 2.md"),
            "---\npublish: false\ncreated: 2026-09-09T07:00:00.000-0400\n---\nSee [[Worksheet]].\n", utf8);
        File.WriteAllText(Path.Combine(dir, "Concepts", "Worksheet.md"),
            "---\npublishForSection1: false\n---\nQuestions.\n", utf8);

        // The offer a build leaves, written AFTER the pages so it is fresh.
        Thread.Sleep(50);
        string state = Path.Combine(dir, ".publish_state");
        Directory.CreateDirectory(state);
        var offer = new JsonObject
        {
            ["version"] = 1, ["course"] = Code, ["section"] = 1, ["buildId"] = "20260930T120000Z-test",
            ["builtAt"] = "2026-09-30T12:00:00Z", ["firstClass"] = null,
            ["pages"] = new JsonArray(
                new JsonObject
                {
                    ["place"] = WorksheetPlace, ["title"] = "Worksheet", ["group"] = "fromAClass", ["ticked"] = false,
                    ["firstUsedIn"] = ClassPlace, ["linkedFrom"] = new JsonArray(), ["dependsOn"] = new JsonArray(),
                },
                new JsonObject
                {
                    ["place"] = ClassPlace, ["title"] = "Unit 1, Day 2", ["group"] = "class", ["ticked"] = false,
                    ["date"] = "2026-09-09", ["linkedFrom"] = new JsonArray(), ["dependsOn"] = new JsonArray(),
                }),
        };
        File.WriteAllText(Path.Combine(state, "section1.links-checklist.json"), offer.ToJsonString(), utf8);
    }

    private static string RowId(string place) => "linksChecklistRow:" + place.Normalize(NormalizationForm.FormC);

    [UiFact]
    public void ARowAClassBringsIsShownTickedAndDisabledAndTheButtonCountsIt()
    {
        using var app = new DrivenApp(WriteCourseWithAnOffer);
        app.SelectCourse(Code);
        var section = app.Find($"sidebar-{Code}-section1", "the sidebar entry for Section 1");
        AutomationElement? classRow = null;
        for (int attempt = 0; attempt < 3 && classRow is null; attempt++)
        {
            app.ClickMiddleOf(section);
            classRow = app.FindOrNull(RowId(ClassPlace), TimeSpan.FromSeconds(8));
        }
        Assert.True(classRow is not null, "the links checklist was not offered when the section opened");

        var worksheet = app.Find(RowId(WorksheetPlace), "the worksheet's row").AsCheckBox();
        var publish = app.Find("linksChecklistPublish", "the Publish button");
        Assert.True(worksheet.IsEnabled, "before the class is ticked, the worksheet is the teacher's own to tick");

        classRow!.AsCheckBox().Toggle();

        Assert.True(Retry.WhileFalse(() => worksheet.ToggleState == FlaUI.Core.Definitions.ToggleState.On,
                                     TimeSpan.FromSeconds(3)).Result,
                    "a row the ticked class brings is shown ticked");
        Assert.False(worksheet.IsEnabled, "and disabled until the class is unticked");
        Assert.Contains(DrivenApp.TextsUnder(app.Window), t => t.StartsWith("comes with", StringComparison.Ordinal));
        Assert.Equal("Publish 2 pages", publish.Name);

        // Nothing published: Not Now writes only the answer.
        app.Find("linksChecklistNotNow", "Not Now").AsButton().Invoke();
        string page = File.ReadAllText(Path.Combine(app.WorkspacePath, "courses", Code, "Concepts", "Worksheet.md"));
        Assert.Contains("publishForSection1: false", page);
    }
}
