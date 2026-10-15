using System.Text;
using System.Text.Json.Nodes;
using FlaUI.Core.AutomationElements;
using FlaUI.Core.Definitions;
using FlaUI.Core.Input;
using FlaUI.Core.Tools;
using FlaUI.Core.WindowsAPI;
using Xunit.Abstractions;

namespace Plantoir.UiTests;

/// <summary>
/// Printable pages through the real window (#496; the mac's #454): Course
/// Settings → Printing writes its keys and says so on the trail, a course
/// whose file holds an unknown blank and place opens clean, the question
/// before a teacher's own CLAUDE.md is changed, and the preview pane handing
/// a new-window link to the browser. Written 2026-10-15 with the desktop
/// LOCKED: UNPROVEN until their first run on an unlocked desktop.
/// </summary>
[Collection("drives the real app")]
public class CourseSettingsPrintingUiTests
{
    private const string Odd = "ICS4U";

    /// <summary>The two ordinary fixtures, plus a course whose printing settings hold an unknown blank, an unknown place and a school name of spaces (freshOpenCases case 9).</summary>
    private static void Fixtures(string courses)
    {
        CourseFixtures.WriteBoth(courses);
        EndToEnd.WriteCourse(courses, Odd, "Computer Science", new[] { "Concepts" }, config =>
        {
            config["print_blanks"] = new JsonArray("seat", "class_number", "name");
            config["print_school_name_at"] = "top";
            config["print_course_code_at"] = 7;
            config["print_school_name"] = "   ";
        });
    }

    [UiFact]
    public void TurningOnABlankIsSavedInPrintOrderAndTheTrailSaysSo()
    {
        using var app = new DrivenApp(Fixtures);
        app.SelectCourse(CourseFixtures.NeverAsked);
        Thread.Sleep(1500);
        Assert.False(app.Find("saveButton", "Save").IsEnabled, "Save is enabled on a fresh open");

        app.Find("printBlank_class_number", "the Class # switch").AsToggleButton().Toggle();
        Assert.True(Retry.WhileFalse(() => app.Find("saveButton", "Save").IsEnabled, TimeSpan.FromSeconds(3)).Result,
                    "turning a blank on did not enable Save");
        Assert.Contains("Class #", app.Find("printCornersSketch", "the corner sketch").Name + string.Join(" ",
            DrivenApp.TextsUnder(app.Find("printCornersSketch", "the corner sketch"))));
        app.Find("saveButton", "Save").AsButton().Invoke();
        Assert.True(Retry.WhileFalse(() => app.Find("savedConfirmation", "the note beside Save").Name.StartsWith("Saved"),
                                     TimeSpan.FromSeconds(3)).Result);

        var saved = JsonNode.Parse(File.ReadAllText(Path.Combine(app.WorkspacePath, "courses", CourseFixtures.NeverAsked, "course_config.json")))!;
        Assert.Equal("[\"name\",\"date\",\"class_number\"]", saved["print_blanks"]!.ToJsonString());
        Assert.Contains($"saved the settings for {CourseFixtures.NeverAsked}; printing: blanks Name, Date → Name, Date, Class #",
                        MenuBar.Trail(app));
    }

    [UiFact]
    public void ACourseWithAnUnknownBlankAndPlaceOpensWithNothingToSave()
    {
        using var app = new DrivenApp(Fixtures);
        app.SelectCourse(Odd);
        Thread.Sleep(2000);   // TextChanged arrives late in WinUI (plan review L9)
        Assert.False(app.Find("saveButton", "Save").IsEnabled, "Save is enabled on a fresh open of unknown printing values");
        var saved = JsonNode.Parse(File.ReadAllText(Path.Combine(app.WorkspacePath, "courses", Odd, "course_config.json")))!;
        Assert.Equal("[\"seat\",\"class_number\",\"name\"]", saved["print_blanks"]!.ToJsonString());
    }
}

[Collection("drives the real app")]
public class GuidanceAskUiTests
{
    private const string Own = "# My own notes for Claude\n\nAlways use British spelling.\n";

    [UiFact]
    public void ATeachersOwnFileIsAskedAboutAndEscapeLeavesItAlone()
    {
        using var app = new DrivenApp(CourseFixtures.WriteBoth,
            beforeLaunch: folder => File.WriteAllText(Path.Combine(folder, "CLAUDE.md"), Own, new UTF8Encoding(false)));
        string claude = Path.Combine(app.WorkspacePath, "CLAUDE.md");

        // AGENTS.md is not there: written without asking, holding the section alone.
        Assert.True(Retry.WhileFalse(() => File.Exists(Path.Combine(app.WorkspacePath, "AGENTS.md")), TimeSpan.FromSeconds(30)).Result,
                    "AGENTS.md was never written into a fresh working folder");
        var dialog = Retry.WhileNull(() => app.FindOrNull("guidanceAskDialog"), TimeSpan.FromSeconds(30)).Result
                     ?? Retry.WhileNull(() => app.OpenDialog(), TimeSpan.FromSeconds(5)).Result;
        Assert.NotNull(dialog);
        Assert.Contains("CLAUDE.md", string.Join(" ", DrivenApp.TextsUnder(dialog!)));

        app.BringToFront();
        Keyboard.Press(VirtualKeyShort.ESCAPE);
        Assert.True(Retry.WhileFalse(() => app.FindOrNull("guidanceAskDialog", TimeSpan.Zero) is null, TimeSpan.FromSeconds(5)).Result);

        Assert.Equal(Own, File.ReadAllText(claude));
        // The answer is recorded on a task of its own after the dialog closes
        // (ToolchainReadiness.Answer runs on Task.Run): give it a moment (M-2).
        Assert.True(Retry.WhileFalse(() => File.Exists(Path.Combine(app.StateDirectory, "agent-guidance-declined.json")),
                                     TimeSpan.FromSeconds(5)).Result, "Not Now was not remembered");
        const string asked = "asked before adding Plantoir's section to CLAUDE.md in the working folder — not now";
        Assert.True(Retry.WhileFalse(() => MenuBar.Trail(app).Contains(asked), TimeSpan.FromSeconds(5)).Result,
                    "the trail never said what was asked: " + asked);
        Assert.True(File.Exists(Path.Combine(app.WorkspacePath, ".claude", "skills", "plantoir-printing", "SKILL.md")),
                    "the skills are written whatever the answer");
    }
}

[Collection("drives the real app")]
public class PreviewHandsLinksToTheBrowserUiTests
{
    private const string Code = "PRT2O";
    private static readonly TimeSpan LongEnoughToBuild = TimeSpan.FromMinutes(15);
    private readonly ITestOutputHelper _output;

    public PreviewHandsLinksToTheBrowserUiTests(ITestOutputHelper output) => _output = output;

    [UiFact]
    public void ALinkThatOpensANewWindowGoesToTheBrowserAndTheTrailNamesOnlyItsKind()
    {
        string marker = EndToEnd.Marker("Links");
        using var app = new DrivenApp(courses =>
        {
            string dir = EndToEnd.WriteCourse(courses, Code, "Printing Course", new[] { "Concepts" },
                frontPage: $"---\ntitle: {Code}\n---\n# Front\n\n{marker}\n\n<a id=\"pdf\" href=\"Media/Key.pdf\" target=\"_blank\">Answer key</a>\n");
            File.WriteAllBytes(Path.Combine(dir, "Media", "Key.pdf"), Encoding.ASCII.GetBytes("%PDF-1.4\n%%EOF\n"));
        });
        app.SelectSection(Code, 1);
        app.WillServe(Code, 1);
        app.Find("previewButton", "the Preview button").AsButton().Invoke();
        Assert.True(app.WaitAnsweringDialogs(() => EndToEnd.ServedFrontPage(marker) is not null, LongEnoughToBuild),
                    "the preview never served its front page" + app.AnsweredSoFar);

        // The link, as the web view's own accessibility tree offers it.
        var link = Retry.WhileNull(() => app.Window.FindFirstDescendant(cf =>
            cf.ByControlType(ControlType.Hyperlink).And(cf.ByName("Answer key"))), TimeSpan.FromSeconds(60)).Result;
        Assert.NotNull(link);
        app.BringToFront();
        link!.Click();

        string opened = Path.Combine(app.StateDirectory, "links-opened.txt");
        Assert.True(Retry.WhileFalse(() => File.Exists(opened) && File.ReadAllText(opened).Contains("Key.pdf"), TimeSpan.FromSeconds(15)).Result,
                    "the PDF link was not handed to the browser (links-opened.txt never named it)");
        _output.WriteLine(File.ReadAllText(opened));
        Assert.Contains("127.0.0.1", File.ReadAllText(opened));
        Assert.Contains($"{Code}/1 · preview page opened in the web browser — the page's own PDF (the front page)", MenuBar.Trail(app));
        Assert.DoesNotContain("Key.pdf", MenuBar.Trail(app));
    }
}
