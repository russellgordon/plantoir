using FlaUI.Core.AutomationElements;
using FlaUI.Core.Input;
using FlaUI.Core.Tools;
using FlaUI.Core.WindowsAPI;
using Plantoir.Core.Assist;
using Xunit.Abstractions;

namespace Plantoir.UiTests;

/// <summary>
/// End to end, ruling U2 (4): Copy a Page from This Course… carried all the way
/// through — a VISIBLE page and the HIDDEN page it links to, copied through the
/// checklist, both arriving hidden in every section of the course they land in
/// (read from the files), a backup of that course taken first, and the built,
/// PUBLISHED destination site read back without either of them while its own
/// visible page is there. Then the refusals a teacher can meet, each one the
/// contract's sentence (copyingAPageBetweenCourses.wording, deserialised).
/// </summary>
[Collection("drives the real app")]
public class CopyAPageEndToEndUiTests
{
    private const string Source = "UICPS4";
    private const string Destination = "UICPD4";
    private const string Nowhere = "UINOW4";   // lists a folder that is not on disk, and has no pages
    private static readonly TimeSpan LongEnoughToPublish = TimeSpan.FromMinutes(15);

    private readonly ITestOutputHelper _output;
    public CopyAPageEndToEndUiTests(ITestOutputHelper output) => _output = output;

    private static string Copied(string marker) => $"Copied page: {marker}";

    [UiFact]
    public void ACopiedPageAndItsHiddenLinkArriveHiddenAndStayOutOfThePublishedSite()
    {
        string visibleInSource = EndToEnd.Marker("WasVisible"), hiddenInSource = EndToEnd.Marker("WasHidden");
        string ownPage = EndToEnd.Marker("DestOwn");
        string? published = null;
        using var app = new DrivenApp(courses =>
        {
            published = Path.Combine(Path.GetDirectoryName(Path.GetDirectoryName(courses)!)!, "published");
            Directory.CreateDirectory(published);
            string source = EndToEnd.WriteCourse(courses, Source, "Copying From", new[] { "Concepts" });
            EndToEnd.WritePage(Path.Combine(source, "Concepts", "Ohms Law.md"), "title: Ohms Law\npublish: true",
                               $"{Copied(visibleInSource)}\n\nSee [[Wattage]].");
            EndToEnd.WritePage(Path.Combine(source, "Concepts", "Wattage.md"), "title: Wattage\npublishForSection1: false",
                               Copied(hiddenInSource));
            string destination = EndToEnd.WriteCourse(courses, Destination, "Copying Into", new[] { "Concepts" },
                                                      EndToEnd.PublishesTo(published));
            EndToEnd.WritePage(Path.Combine(destination, "Concepts", "Welcome.md"), "title: Welcome", $"Already here: {ownPage}");
        });
        var wording = EndToEnd.CopyPageWording;

        // ---- The three questions, then the checklist, then the result.
        OpenCopyAPage(app, Source);
        ChoosePage(app, "Ohms");
        var copy = app.Find(CopyAPageDialogIds.Primary, "the Copy button").AsButton();
        Assert.True(Retry.WhileFalse(() => copy.IsEnabled, TimeSpan.FromSeconds(5)).Result, "Copy was not offered once a page was chosen");
        copy.Invoke();
        Assert.NotNull(app.FindOrNull("copyPageRow:Wattage", TimeSpan.FromSeconds(10)));   // the linked page, offered and ticked
        copy.Invoke();

        string expected = EndToEnd.Say(wording["copiedInto"]!, ("pages", "2"), ("course", Destination), ("folder", "Concepts"));
        Assert.True(Retry.WhileFalse(() => app.OpenDialog() is { } d && DrivenApp.TextsUnder(d).Contains(expected),
                                     TimeSpan.FromSeconds(60), TimeSpan.FromMilliseconds(400)).Result,
                    $"the result never said \"{expected}\"; it said: {DialogText(app)}");
        EndToEnd.CloseCopyAPage(app);

        // ---- On disk: both pages, hidden in the destination's one section, the source untouched.
        foreach (string page in new[] { "Ohms Law.md", "Wattage.md" })
        {
            string text = File.ReadAllText(Path.Combine(app.WorkspacePath, "courses", Destination, "Concepts", page));
            Assert.Contains("publishForSection1: false", text);
            Assert.Contains("publish: false", text);
            Assert.DoesNotContain("publish: true", text);   // the source's own flag is not carried beside it
        }
        Assert.Contains("publish: true", File.ReadAllText(Path.Combine(app.WorkspacePath, "courses", Source, "Concepts", "Ohms Law.md")));
        string backups = Path.Combine(app.WorkspacePath, "courses", "_backups", Destination);
        Assert.True(Directory.Exists(backups) && Directory.EnumerateFiles(backups, "*.zip").Any(),
                    $"no backup of {Destination} was taken before the copy");

        // ---- The destination's published site: its own page, and neither copy.
        app.SelectSection(Destination, 1);
        EndToEnd.DeployAndWait(app, LongEnoughToPublish);
        string site = Path.Combine(published!, "section1");
        Assert.NotEmpty(EndToEnd.FilesContaining(site, ownPage));
        Assert.Empty(EndToEnd.FilesContaining(site, visibleInSource));
        Assert.Empty(EndToEnd.FilesContaining(site, hiddenInSource));
    }

    [UiFact]
    public void TheRefusalsAreTheContractsSentences()
    {
        using var app = new DrivenApp(courses =>
        {
            string source = EndToEnd.WriteCourse(courses, Source, "Copying From", new[] { "Concepts" });
            EndToEnd.WritePage(Path.Combine(source, "Concepts", "Wattage.md"), "title: Wattage", "No links on this one.");
            EndToEnd.WriteCourse(courses, Destination, "Copying Into", new[] { "Concepts" });
            string nowhere = EndToEnd.WriteCourse(courses, Nowhere, "Nowhere To Put It", new[] { "Concepts" });
            Directory.Delete(Path.Combine(nowhere, "Concepts"));   // listed, not on disk
        });
        var wording = EndToEnd.CopyPageWording;

        // 1. A course with no page in a shared folder has nothing to offer.
        OpenCopyAPage(app, Nowhere);
        ExpectSentence(app, EndToEnd.Say(wording["thisCourseHasNoPagesToCopy"]!, ("course", Nowhere)));
        Assert.False(app.Find(CopyAPageDialogIds.Primary, "the Copy button").IsEnabled);
        EndToEnd.CloseCopyAPage(app);

        // 2. A destination whose folders are not on disk has nowhere to put it.
        OpenCopyAPage(app, Source);
        // The page first: typed into a picker just opened, as in the copy test.
        // Typed after a combo box had been driven, the keystrokes never reached
        // the picker (bundle 11, run 3) — a harness matter, not the product's.
        ChoosePage(app, "Watt");
        app.Find("copyPageDestination", "Copy into").AsComboBox().Select(Nowhere);
        ExpectSentence(app, EndToEnd.Say(wording["thatCourseHasNowhereToPutIt"]!, ("course", Nowhere)));
        Assert.False(app.Find(CopyAPageDialogIds.Primary, "the Copy button").IsEnabled);

        // 3. A destination being deployed right now is refused before anything is written.
        //    The lease is a real one, held by THIS process, exactly as a deploy holds it.
        app.Find("copyPageDestination", "Copy into").AsComboBox().Select(Destination);
        using (WorkLease.Take(app.WorkspacePath, Destination, WorkLease.Publishing))
        {
            var copy = app.Find(CopyAPageDialogIds.Primary, "the Copy button").AsButton();
            Assert.True(Retry.WhileFalse(() => copy.IsEnabled, TimeSpan.FromSeconds(5)).Result, "Copy was not offered");
            copy.Invoke();
            ExpectSentence(app, EndToEnd.Say(wording["thatCourseIsDeployingRightNow"]!, ("course", Destination)));
        }
        Assert.False(File.Exists(Path.Combine(app.WorkspacePath, "courses", Destination, "Concepts", "Wattage.md")),
                     "the page was copied into a course that was being deployed");
        EndToEnd.CloseCopyAPage(app);
    }

    // ---- Driving the dialog ------------------------------------------------

    private static void OpenCopyAPage(DrivenApp app, string course)
    {
        // The previous dialog fully gone first: a second ContentDialog cannot
        // open while one is still on screen.
        Retry.WhileFalse(() => app.OpenDialog() is null, TimeSpan.FromSeconds(10), TimeSpan.FromMilliseconds(250));
        app.PressRowMenuItem("sidebar-" + course, EndToEnd.CopyPageWording["menuItem"]!.ToString());
        Assert.NotNull(app.FindOrNull("copyPagePicker", TimeSpan.FromSeconds(10)));
    }

    /// <summary>The picker suggests only on TYPING (by design), so this types.</summary>
    private static void ChoosePage(DrivenApp app, string typed)
    {
        // Waited until it can be clicked: a dialog opened straight after
        // another one closed is still arriving, and a click then has no point
        // to land on (NoClickablePointException, runs 6 and 7 of bundle 11).
        // Re-found on every look: the closing dialog's picker can still be in
        // the tree for a moment, and it is the new one that has to be ready.
        AutomationElement? picker = null;
        Assert.True(Retry.WhileFalse(() =>
        {
            try
            {
                picker = app.FindOrNull("copyPagePicker", TimeSpan.FromMilliseconds(300));
                return picker is not null && !picker.IsOffscreen && picker.TryGetClickablePoint(out _);
            }
            catch { return false; }
        }, TimeSpan.FromSeconds(15), TimeSpan.FromMilliseconds(250)).Result, "the page picker never came on screen");
        Thread.Sleep(400);
        // The click and the typing below are REAL input, which goes to whatever
        // is under the pointer and in front: see DrivenApp.ClickMiddleOf.
        app.ClickMiddleOf(picker!);
        Keyboard.Type(typed);
        Thread.Sleep(600);
        Keyboard.Press(VirtualKeyShort.DOWN);
        Keyboard.Press(VirtualKeyShort.ENTER);
    }

    private static string DialogText(DrivenApp app) =>
        app.OpenDialog() is { } d ? string.Join(" | ", DrivenApp.TextsUnder(d)) : "<no dialog>";

    private static void ExpectSentence(DrivenApp app, string sentence) =>
        Assert.True(Retry.WhileFalse(() => app.OpenDialog() is { } d && DrivenApp.TextsUnder(d).Contains(sentence),
                                     TimeSpan.FromSeconds(15), TimeSpan.FromMilliseconds(300)).Result,
                    $"the dialog never said \"{sentence}\"; it said: {DialogText(app)}");
}
