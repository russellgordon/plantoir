using System.Text.Json.Nodes;
using FlaUI.Core.AutomationElements;
using FlaUI.Core.Tools;
using Plantoir.Core.Models;

namespace Plantoir.UiTests;

/// <summary>
/// End to end, ruling U2 (2): File › Import Courses for Reference…, the
/// WINDOWS folder picker driven like a teacher drives it, the sheet, Import,
/// the done screen in the contract's words, and the result read back — the
/// course in the sidebar under Reference Courses with its section, its pages
/// on disk and LOCKED, last year's built website left behind, and the folder
/// it came from untouched. Then the two refusals a teacher meets most.
/// </summary>
[Collection("drives the real app")]
public class ImportForReferenceUiTests
{
    private const string Code = "UIREF4";

    /// <summary>Last year's working folder, beside this run's: its pages last changed in February 2026, so the year proposed is 2025–26.</summary>
    private static string WriteLastYear(DrivenApp app, string marker)
    {
        string lastYear = app.Scratch("last year");
        string courses = Path.Combine(lastYear, "courses");
        string dir = EndToEnd.WriteCourse(courses, Code, "Last Year's Course", new[] { "Concepts" });
        EndToEnd.WritePage(Path.Combine(dir, "Concepts", "Loops.md"), "title: Loops", $"From last year: {marker}");
        // Last year's built website, which is never copied (importing.leftBehind).
        Directory.CreateDirectory(Path.Combine(dir, ".merged_output", "section1", "public"));
        File.WriteAllText(Path.Combine(dir, ".merged_output", "section1", "public", "index.html"), "<html>old build</html>");
        var february = new DateTime(2026, 2, 10, 12, 0, 0);
        foreach (string file in Directory.EnumerateFiles(dir, "*.md", SearchOption.AllDirectories))
            File.SetLastWriteTime(file, february);
        return lastYear;
    }

    [UiFact]
    public void AnOldWorkingFolderIsImportedShelvedByYearAndLocked()
    {
        using var app = new DrivenApp(CourseFixtures.WriteBoth);
        string marker = EndToEnd.Marker("Imported");
        string lastYear = WriteLastYear(app, marker);
        string sourcePage = Path.Combine(lastYear, "courses", Code, "Concepts", "Loops.md");
        var sourceStamp = File.GetLastWriteTimeUtc(sourcePage);
        var wording = EndToEnd.ImportWording;

        EndToEnd.PressMenuBarItem(app, "File", "fileImportForReference");
        EndToEnd.ChooseInFolderPicker(app, lastYear);

        // The sheet: everything ticked (a working folder was chosen), Import offered.
        var import = Retry.WhileNull(() => app.OpenDialog()?.FindFirstDescendant(cf => cf.ByAutomationId("PrimaryButton")),
                                     TimeSpan.FromSeconds(20), TimeSpan.FromMilliseconds(300)).Result
                     ?? throw new Xunit.Sdk.XunitException("the import sheet never opened");
        Assert.Equal(wording["importButton"]!.ToString(), import.Name);
        var sheet = DrivenApp.TextsUnder(app.OpenDialog()!);
        Assert.Contains(wording["explanation"]!.ToString(), sheet);
        Assert.Contains(wording["builtWebsitesAreNotCopied"]!.ToString(), sheet);
        Assert.True(Retry.WhileFalse(() => import.IsEnabled, TimeSpan.FromSeconds(5)).Result, "Import was not offered for a ticked course");
        import.AsButton().Invoke();

        // The done screen, in the contract's words.
        string doneTitle = wording["doneTitle"]!.ToString();
        string where = wording["whereTheyAre"]!.ToString();
        string importedOpening = EndToEnd.Say(wording["imported"]!, ("course", Code)).Split("{year}")[0];
        Assert.True(Retry.WhileFalse(() => app.OpenDialog() is { } d && DrivenApp.TextsUnder(d).Contains(where),
                                     TimeSpan.FromSeconds(120), TimeSpan.FromMilliseconds(500)).Result,
                    $"the import never said \"{where}\"");
        var done = app.OpenDialog()!;
        var doneSaid = DrivenApp.TextsUnder(done);
        Assert.Contains(doneTitle, doneSaid.Append(done.Name));
        Assert.Contains(doneSaid, line => line.StartsWith(importedOpening, StringComparison.Ordinal));
        done.FindFirstDescendant(cf => cf.ByAutomationId("CloseButton"))!.AsButton().Invoke();

        // The sidebar: Reference Courses › 2025–26 › the course, with its section.
        string folder = $"{Code}-2025";   // importing.folderNameProduced, for the year its pages were changed in
        Assert.NotNull(app.FindOrNull("referenceGroup", TimeSpan.FromSeconds(10)));
        Assert.NotNull(app.FindOrNull("referenceYear-2025", TimeSpan.FromSeconds(10)));
        Assert.NotNull(app.FindOrNull("sidebar-" + folder, TimeSpan.FromSeconds(10)));
        Assert.NotNull(app.FindOrNull($"sidebar-{folder}-section1", TimeSpan.FromSeconds(10)));

        // On disk: marked and filed, its page there and locked, the old build left behind.
        string copied = Path.Combine(app.WorkspacePath, "courses", folder);
        var config = JsonNode.Parse(File.ReadAllText(Path.Combine(copied, "course_config.json")))!;
        Assert.True(config["kept_for_reference"]!.GetValue<bool>());
        Assert.Equal(2025, config["reference_school_year"]!.GetValue<int>());
        Assert.Equal(Code, config["course_code"]!.ToString());
        string page = Path.Combine(copied, "Concepts", "Loops.md");
        Assert.Contains(marker, File.ReadAllText(page));
        Assert.True(EndToEnd.WritingIsRefused(page), "an imported page could be written to");
        Assert.False(Directory.Exists(Path.Combine(copied, ".merged_output")), "last year's built website was copied");

        // The folder it came from is exactly as it was.
        Assert.Equal(sourceStamp, File.GetLastWriteTimeUtc(sourcePage));
        Assert.False(EndToEnd.WritingIsRefused(sourcePage), "the folder imported FROM was locked");
        Assert.False(File.ReadAllText(Path.Combine(lastYear, "courses", Code, "course_config.json")).Contains("kept_for_reference"),
                     "the folder imported FROM was marked");

        // And the summary a teacher opens says what it is.
        app.Find("sidebar-" + folder, "the imported course's row").Click();
        var summary = DrivenApp.TextsUnder(app.Find("referenceSummary", "the read-only summary"));
        Assert.Contains(EndToEnd.Say(EndToEnd.ReferenceWording["neverDeployed"]!, ("course", Code)), summary);
    }

    [UiFact]
    public void TheOpenFolderAndAnEmptyFolderAreRefusedInTheContractsWords()
    {
        using var app = new DrivenApp(CourseFixtures.WriteBoth);
        var wording = EndToEnd.ImportWording;

        // The working folder already open: route 1's job, said by name.
        EndToEnd.PressMenuBarItem(app, "File", "fileImportForReference");
        EndToEnd.ChooseInFolderPicker(app, app.WorkspacePath);
        ExpectRefusal(app, wording["thatIsTheFolderYouHaveOpen"]!.ToString());

        // A folder with no course in it.
        string empty = app.Scratch("nothing here");
        File.WriteAllText(Path.Combine(empty, "September.md"), "notes\n");
        EndToEnd.PressMenuBarItem(app, "File", "fileImportForReference");
        EndToEnd.ChooseInFolderPicker(app, empty);
        ExpectRefusal(app, EndToEnd.Say(wording["noCoursesThere"]!, ("folder", "nothing here")));

        Assert.Null(app.FindOrNull("referenceGroup", TimeSpan.FromSeconds(1)));   // nothing was shelved
    }

    private static void ExpectRefusal(DrivenApp app, string sentence)
    {
        Assert.True(Retry.WhileFalse(() => app.OpenDialog() is { } d && DrivenApp.TextsUnder(d).Contains(sentence),
                                     TimeSpan.FromSeconds(20), TimeSpan.FromMilliseconds(300)).Result,
                    $"the import never refused with \"{sentence}\"; the dialog said: "
                    + (app.OpenDialog() is { } d ? string.Join(" | ", DrivenApp.TextsUnder(d)) : "<no dialog>"));
        app.OpenDialog()!.FindFirstDescendant(cf => cf.ByAutomationId("CloseButton"))!.AsButton().Invoke();
        Assert.True(Retry.WhileFalse(() => app.OpenDialog() is null, TimeSpan.FromSeconds(5)).Result, "the refusal would not close");
    }
}
