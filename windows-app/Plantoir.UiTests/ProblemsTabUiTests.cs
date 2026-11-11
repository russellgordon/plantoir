using System.Diagnostics;
using System.Text;
using System.Text.Json.Nodes;
using FlaUI.Core.AutomationElements;
using FlaUI.Core.Definitions;
using FlaUI.Core.Input;
using FlaUI.Core.Tools;
using FlaUI.Core.WindowsAPI;
using Plantoir.Core.Models;

namespace Plantoir.UiTests;

/// <summary>
/// A section's Problems tab, its marker and its alert (#734, the mac's #717),
/// driven through the real window: what no unit test can see — that the alert
/// reaches the screen mid-build with the contract's words, that Show opens the
/// tab and puts the keyboard in the table, that every box, header and button
/// has a name a screen reader can say, that the covered page leaves the Tab
/// order, that the sidebar's warning says why, and that a clean build takes
/// all of it away. The rules are pinned by <c>SectionProblemsContractTests</c>
/// and <c>SectionProblemsStoreTests</c> in Plantoir.Tests.
/// </summary>
/// <remarks>
/// Two kinds of fixture. The two previews build for real (a missing Media
/// folder, and a shared page whose settings cannot be read — deterministic,
/// no engine), into the real builds root, which <c>DrivenApp</c> deletes.
/// The others SEED a record where the launchers would have written it, which
/// is how a build the window did not watch (the MCP server's, a terminal's,
/// a scheduled one) reaches it — and is quick.
/// </remarks>
[Collection("drives the real app")]
public class ProblemsTabUiTests
{
    private const string Code = "MPM2D";
    private static readonly TimeSpan LongEnough = TimeSpan.FromMinutes(10);
    private static readonly UTF8Encoding Utf8 = new(false);

    private static JsonNode Words => EndToEnd.Contract()["sectionProblems"]!["words"]!;

    private static string Word(string key, params (string, string)[] fills) => EndToEnd.Say(Words[key]!, fills);

    /// <summary>A measurement: to the console, and to PLANTOIR_UI_MEASURE_FILE when it is set (a passing test's console is not shown).</summary>
    private static void Measured(string what)
    {
        Console.WriteLine("MEASURED: " + what);
        if (Environment.GetEnvironmentVariable("PLANTOIR_UI_MEASURE_FILE") is { Length: > 0 } file)
            try { File.AppendAllText(file, $"{DateTime.Now:HH:mm:ss} {what}{Environment.NewLine}"); } catch { }
    }

    private static string TrailOf(DrivenApp app)
    {
        string path = Path.Combine(app.StateDirectory, "Logs", "activity.txt");
        return File.Exists(path) ? File.ReadAllText(path) : "";
    }

    /// <summary>The dialog on screen named <paramref name="title"/>; any other ordinary dialog met meanwhile is answered with Close and noted.</summary>
    private static AutomationElement WaitForDialog(DrivenApp app, string title, TimeSpan within)
    {
        AutomationElement? found = null;
        app.WaitAnsweringDialogs(() => (found = app.OpenDialog()) is { } d && d.Name == title, within, except: title);
        return found is { } dialog && dialog.Name == title
            ? dialog
            : throw new Xunit.Sdk.XunitException($"the dialog \"{title}\" never appeared." + app.AnsweredSoFar
                                                 + NewCourseWizardUiTests.ConsoleTail(app));
    }

    /// <summary>Presses Preview until it has really started (its face reads Stop Preview): a press while the folder is still being made ready does nothing.</summary>
    private static void StartThePreview(DrivenApp app)
    {
        for (int attempt = 1; attempt <= 3; attempt++)
        {
            var button = app.Find("previewButton", "the Preview button");
            if (button.IsEnabled) button.AsButton().Invoke();
            if (Retry.WhileFalse(() => app.Find("previewButton", "the Preview button").Name == "Stop Preview" || app.OpenDialog() is not null,
                                 TimeSpan.FromSeconds(20)).Result)
                return;
        }
        throw new Xunit.Sdk.XunitException("Preview never started: " + app.Find("previewButton", "the Preview button").HelpText);
    }

    private static AutomationElement Button(AutomationElement dialog, string id) =>
        dialog.FindFirstDescendant(cf => cf.ByAutomationId(id)) ?? throw new Xunit.Sdk.XunitException($"the dialog has no {id}");

    /// <summary>
    /// Whether the element is SHOWN: in the tree and on screen. A collapsed
    /// SelectorBar's items are still listed by UI Automation, marked off
    /// screen (measured here), so presence alone says nothing.
    /// </summary>
    private static bool Showing(DrivenApp app, string id)
    {
        try { return app.FindOrNull(id, TimeSpan.FromMilliseconds(200)) is { } found && !found.IsOffscreen; }
        catch { return false; }
    }

    /// <summary>An element's ItemStatus, empty when it has none (UI Automation reports an empty one as not supported).</summary>
    private static string Status(AutomationElement? element)
    {
        try { return element?.Properties.ItemStatus.ValueOrDefault ?? ""; } catch { return ""; }
    }

    private static bool IsSelected(DrivenApp app, string id) =>
        app.FindOrNull(id, TimeSpan.FromMilliseconds(300)) is { } item
        && item.Patterns.SelectionItem.IsSupported && item.Patterns.SelectionItem.Pattern.IsSelected.Value;

    private static string FocusedId(DrivenApp app)
    {
        try { return app.Window.Automation.FocusedElement()?.AutomationId ?? ""; } catch { return ""; }
    }

    /// <summary>The ids of the focused element and every parent above it, up to the window.</summary>
    private static List<string> FocusedAndAbove(DrivenApp app)
    {
        var ids = new List<string>();
        try
        {
            var walker = app.Window.Automation.TreeWalkerFactory.GetControlViewWalker();
            for (var node = app.Window.Automation.FocusedElement(); node is not null; node = walker.GetParent(node))
            {
                ids.Add(node.Properties.AutomationId.ValueOrDefault ?? "");
                if (ids.Count > 40) break;
            }
        }
        catch { }
        return ids;
    }

    // ---- 1. A real preview, a missing Media folder --------------------------

    /// <summary>
    /// The alert comes up MID-build with the contract's title and buttons;
    /// Show opens the Problems tab with the keyboard on the row; the row, its
    /// box, its repair and the sort headers are named; Space ticks it; the
    /// sidebar's warning and the row's help say why; the covered page leaves
    /// the Tab order and is the same page when Website comes back; the repair
    /// in the row puts the folder back, Preview Again builds clean, and the
    /// tab, its bar and the warning go — with no second alert.
    /// </summary>
    [UiFact]
    public void APreviewThatFindsAProblemRaisesTheAlert_ShowOpensTheTab_AndACleanBuildTakesItAway()
    {
        string front = EndToEnd.Marker("Front");
        using var app = new DrivenApp(courses =>
        {
            string dir = EndToEnd.WriteCourse(courses, Code, "Maths", new[] { "Concepts" },
                                              frontPage: $"---\ntitle: {Code}\n---\n# {front}\n");
            Directory.Delete(Path.Combine(dir, "Media"));
        });
        app.SelectSection(Code, 1);
        app.WillServe(Code, 1);
        string title = Word("alertTitleOne", ("course", Code), ("section", "1"));

        var clock = Stopwatch.StartNew();
        StartThePreview(app);
        var alert = WaitForDialog(app, title, LongEnough);
        Measured($"the alert was on screen {clock.Elapsed.TotalSeconds:0.0} s after Preview was pressed.");
        Assert.Contains(Word("alertMessage"), DrivenApp.TextsUnder(alert));
        Assert.Equal(Word("show"), Button(alert, "PrimaryButton").Name);
        string repairTitle = SiteHealthRepair.ButtonTitle(new[] { new SiteHealthFinding("mediaFolderMissing", "", "", true, Code, 1) })!;
        Assert.Equal(repairTitle, Button(alert, "SecondaryButton").Name);
        Assert.Equal(SiteHealthRepair.CloseTitle(besideAnotherButton: true, isARepair: false), Button(alert, "CloseButton").Name);
        Assert.Null(alert.FindFirstDescendant(cf => cf.ByControlType(ControlType.CheckBox)));

        Button(alert, "PrimaryButton").AsButton().Invoke();
        Assert.True(Retry.WhileFalse(() => IsSelected(app, "sectionTabProblems"), TimeSpan.FromSeconds(10)).Result, "Show did not select the Problems tab");
        const string RowId = "problemRow-mediaFolderMissing";
        var row = app.Find(RowId, "the Media folder's row");
        Assert.Contains(SectionProblemsWording.LabelOfKind("mediaFolderMissing"), row.Name);
        Assert.Contains(Word("wholeCourse"), row.Name);
        Assert.False(string.IsNullOrWhiteSpace(row.HelpText), "the row's help text says the whole problem");
        Assert.True(Retry.WhileFalse(() => FocusedAndAbove(app).Contains(RowId), TimeSpan.FromSeconds(5)).Result,
                    $"after Show the keyboard is on the problem's row; it was on {string.Join(" < ", FocusedAndAbove(app))}");

        // Names a screen reader says.
        var box = app.Find("problemTick-mediaFolderMissing", "the row's box");
        Assert.StartsWith(Word("columnIncluded") + ":", box.Name);
        Assert.Contains(SectionProblemsWording.LabelOfKind("mediaFolderMissing"), box.Name);
        var repair = app.Find("problemRepair-mediaFolderMissing", "the row's repair button");
        Assert.StartsWith(repairTitle + ":", repair.Name);
        Assert.Contains(Word("wholeCourse"), repair.Name);
        foreach (string column in new[] { "Kind", "Page", "FirstFound", "LastFound" })
            Assert.False(string.IsNullOrWhiteSpace(app.Find("problemsSort-" + column, column + "'s header").Name));
        Assert.Equal("sorted ascending", Status(app.Find("problemsSort-Kind", "Kind's header")));
        app.Find("problemsSort-Page", "Page's header").AsButton().Invoke();
        Assert.True(Retry.WhileFalse(() => Status(app.Find("problemsSort-Page", "Page's header")) == "sorted ascending", TimeSpan.FromSeconds(3)).Result);
        Assert.Equal("", Status(app.Find("problemsSort-Kind", "Kind's header")));
        app.Find("problemsSort-Page", "Page's header").AsButton().Invoke();
        Assert.True(Retry.WhileFalse(() => Status(app.Find("problemsSort-Page", "Page's header")) == "sorted descending", TimeSpan.FromSeconds(3)).Result);

        // Space on the row flips its box and says so.
        // Focus, not a click: the middle of the row is its Problem cell, whose
        // repair button a click could press.
        app.Find(RowId, "the Media folder's row").Focus();
        Keyboard.Type(VirtualKeyShort.SPACE);
        Assert.True(Retry.WhileFalse(() => Status(app.Find(RowId, "the row")) == "not ticked", TimeSpan.FromSeconds(3)).Result, "Space unticked the row");
        Assert.Equal(ToggleState.Off, app.Find("problemTick-mediaFolderMissing", "the box").AsCheckBox().ToggleState);
        Keyboard.Type(VirtualKeyShort.SPACE);
        Assert.True(Retry.WhileFalse(() => Status(app.Find(RowId, "the row")) == "ticked", TimeSpan.FromSeconds(3)).Result, "Space ticked it again");

        // The sidebar: one warning, named, and said on the row.
        var badge = app.Find($"problemsBadge-{Code}-section1", "the section's warning");
        Assert.Contains(Word("markerHelp"), badge.Name);
        Assert.Contains(Word("markerHelp"), app.Find($"sidebar-{Code}-section1", "the section's row").HelpText);

        // The covered page: served meanwhile, out of the Tab order while
        // Problems shows, and the same page when Website comes back.
        Assert.True(app.WaitAnsweringDialogs(() => EndToEnd.ServedFrontPage(front) is not null, LongEnough),
                    "the preview was never served" + app.AnsweredSoFar);
        app.ClickMiddleOf(app.Find("sectionTabWebsite", "the Website tab"));
        Assert.True(Retry.WhileFalse(() => Status(app.FindOrNull("openInBrowserButton")).StartsWith("loaded 200", StringComparison.Ordinal),
                                     LongEnough).Result, "the preview never loaded");
        string loaded = Status(app.Find("openInBrowserButton", "Open in Browser"));
        for (int round = 1; round <= 3; round++)
        {
            app.ClickMiddleOf(app.Find("sectionTabProblems", "the Problems tab"));
            Assert.True(Retry.WhileFalse(() => app.FindOrNull("previewWebView", TimeSpan.FromMilliseconds(200)) is null, TimeSpan.FromSeconds(5)).Result,
                        "the covered web view left the UI Automation tree");
            for (int press = 0; press < 12; press++)
            {
                Keyboard.Type(VirtualKeyShort.TAB);
                Thread.Sleep(120);
                Assert.DoesNotContain("previewWebView", FocusedAndAbove(app));
            }
            app.ClickMiddleOf(app.Find("sectionTabWebsite", "the Website tab"));
            Assert.NotNull(app.FindOrNull("previewWebView", TimeSpan.FromSeconds(5)));
            Assert.Equal(loaded, Status(app.Find("openInBrowserButton", "Open in Browser")));
        }

        // The repair in the row: the folder comes back; Preview Again builds clean.
        app.ClickMiddleOf(app.Find("sectionTabProblems", "the Problems tab"));
        app.Find("problemRepair-mediaFolderMissing", "the row's repair button").AsButton().Invoke();
        var outcome = Retry.WhileNull(() => app.OpenDialog(), TimeSpan.FromSeconds(10)).Result
                      ?? throw new Xunit.Sdk.XunitException("the repair said nothing");
        Assert.True(Directory.Exists(Path.Combine(app.WorkspacePath, "courses", Code, "Media")), "the repair put the Media folder back");
        Button(outcome, "PrimaryButton").AsButton().Invoke();   // Preview Again
        Assert.True(app.WaitAnsweringDialogs(() => !Showing(app, "sectionTabWebsite"), LongEnough),
                    "a clean build took the tab bar away" + app.AnsweredSoFar);
        Assert.DoesNotContain(app.Answered, said => said.StartsWith(title, StringComparison.Ordinal));
        Assert.True(Retry.WhileFalse(() => !Showing(app, $"problemsBadge-{Code}-section1"), TimeSpan.FromSeconds(10)).Result,
                    "the section's warning went with the clean build");

        string trail = TrailOf(app);
        Assert.Contains($"{Code}/1 · the preview found 1 new and 0 fewer problems (new: mediaFolderMissing; gone: none)", trail);
        Assert.Contains($"{Code}/1 · answered the alert about new problems: Show", trail);
        Assert.Contains($"{Code}/1 · the preview found 0 new and 1 fewer problems (new: none; gone: mediaFolderMissing)", trail);
    }

    /// <summary>
    /// The page under the Problems tab keeps its place: a long front page
    /// scrolled part-way down reads the same scroll, the same page and the
    /// same Back state after Problems and Website three times each way. Read
    /// through the page's own scroll pattern, which the web view hands to UI
    /// Automation.
    /// </summary>
    [UiFact]
    public void TheCoveredPageKeepsItsPageAndItsScroll()
    {
        string front = EndToEnd.Marker("Long");
        var body = new StringBuilder($"# {front}\n\n");
        for (int paragraph = 1; paragraph <= 250; paragraph++) body.Append($"Paragraph {paragraph} of a long front page.\n\n");
        using var app = new DrivenApp(courses =>
        {
            string dir = EndToEnd.WriteCourse(courses, Code, "Maths", new[] { "Concepts" },
                                              frontPage: $"---\ntitle: {Code}\n---\n{body}");
            Directory.Delete(Path.Combine(dir, "Media"));
        });
        app.SelectSection(Code, 1);
        app.WillServe(Code, 1);
        StartThePreview(app);
        Assert.True(app.WaitAnsweringDialogs(() => Status(app.FindOrNull("openInBrowserButton", TimeSpan.FromMilliseconds(300)))
                                                       .StartsWith("loaded 200", StringComparison.Ordinal), LongEnough),
                    "the preview never loaded" + app.AnsweredSoFar);
        AutomationElement Document() =>
            Retry.WhileNull(() => app.FindOrNull("previewWebView", TimeSpan.FromSeconds(2))?
                                    .FindFirstDescendant(cf => cf.ByControlType(ControlType.Document)),
                            TimeSpan.FromSeconds(15)).Result
            ?? throw new Xunit.Sdk.XunitException("the web view hands no document to UI Automation");
        var page = Document();
        Assert.True(page.Patterns.Scroll.IsSupported, "the page's scroll is readable");
        page.Patterns.Scroll.Pattern.SetScrollPercent(-1, 60);
        Thread.Sleep(800);
        double before = Document().Patterns.Scroll.Pattern.VerticalScrollPercent.Value;
        string loaded = Status(app.Find("openInBrowserButton", "Open in Browser"));
        bool back = app.Find("previewBackButton", "Back").IsEnabled;
        Assert.True(before > 30, $"the page scrolled part-way down (it read {before:0.0} %)");
        for (int round = 1; round <= 3; round++)
        {
            app.ClickMiddleOf(app.Find("sectionTabProblems", "the Problems tab"));
            Assert.True(Retry.WhileFalse(() => app.FindOrNull("previewWebView", TimeSpan.FromMilliseconds(200)) is null, TimeSpan.FromSeconds(5)).Result);
            Thread.Sleep(500);
            app.ClickMiddleOf(app.Find("sectionTabWebsite", "the Website tab"));
            Thread.Sleep(800);
            double after = Document().Patterns.Scroll.Pattern.VerticalScrollPercent.Value;
            Measured($"round {round}: the page read {after:0.0} % down after Problems and back (it was {before:0.0} %).");
            Assert.True(Math.Abs(after - before) < 1, $"round {round}: the scroll moved from {before:0.0} % to {after:0.0} %");
            Assert.Equal(loaded, Status(app.Find("openInBrowserButton", "Open in Browser")));
            Assert.Equal(back, app.Find("previewBackButton", "Back").IsEnabled);
        }
    }

    // ---- 2. A shared page fixed and built in another section ----------------

    /// <summary>
    /// Section 1 meets a shared page whose settings cannot be read; the page
    /// is put right and Section 2 is previewed; Section 1's row then reads
    /// "fixed in the source" and its warning stays — its deployed site still
    /// carries the broken page until its own next build (#717 ruling 11).
    /// </summary>
    [UiFact]
    public void ASharedPageFixedInAnotherSectionReadsFixedInTheSource_AndKeepsTheWarning()
    {
        string front = EndToEnd.Marker("Front");
        string broken = "---\npublishForSection1: true\npublishForSection2: true\ntitle: [unclosed\n---\nBody\n";
        string page = "";
        using var app = new DrivenApp(courses =>
        {
            string dir = EndToEnd.WriteCourse(courses, Code, "Maths", new[] { "Concepts" }, config =>
            {
                config["num_sections"] = 2;
                config["section_numbers"] = new JsonArray(1, 2);
            }, frontPage: $"---\ntitle: {Code}\n---\n# {front}\n");
            Directory.CreateDirectory(Path.Combine(dir, "section2", "All Classes"));
            File.WriteAllText(Path.Combine(dir, "section2", "index.md"), $"---\ntitle: {Code}\n---\n# {front}\n", Utf8);
            page = Path.Combine(dir, "Concepts", "Broken.md");
            File.WriteAllText(page, broken, Utf8);
        });
        app.SelectSection(Code, 1);
        app.WillServe(Code, 1);
        StartThePreview(app);
        Assert.True(app.WaitAnsweringDialogs(() => app.FindOrNull($"problemsBadge-{Code}-section1", TimeSpan.FromMilliseconds(300)) is not null, LongEnough),
                    "Section 1's build never marked the section" + app.AnsweredSoFar + NewCourseWizardUiTests.ConsoleTail(app));
        string recordOne = Path.Combine(app.RealBuildsRoot, Code, "section1", SectionProblemsRecord.FileName);
        // The alert came with the warning: answered (Not Now) before going on.
        Assert.True(app.WaitAnsweringDialogs(() => app.Answered.Count > 0 && app.OpenDialog() is null, TimeSpan.FromSeconds(60)), "the alert was not raised and answered" + app.AnsweredSoFar);
        var first = SectionProblemsRecord.Read(recordOne) ?? throw new Xunit.Sdk.XunitException("no record for Section 1");
        var row = first.Rows.Single(r => r.Kind == "pageSettingsUnreadable");

        File.WriteAllText(page, "---\npublishForSection1: true\npublishForSection2: true\ntitle: Fixed\n---\nBody\n", Utf8);
        app.SelectSection(Code, 2);
        app.WillServe(Code, 2);
        StartThePreview(app);
        string recordTwo = Path.Combine(app.RealBuildsRoot, Code, "section2", SectionProblemsRecord.FileName);
        Assert.True(app.WaitAnsweringDialogs(() => SectionProblemsRecord.Read(recordTwo) is { } r && r.PagesShown.Contains(row.Page), LongEnough),
                    "Section 2's build never wrote its record showing the page" + app.AnsweredSoFar);
        Assert.Empty(SectionProblemsRecord.Read(recordTwo)!.Rows);
        Thread.Sleep(2000);
        Assert.False(Showing(app, $"problemsBadge-{Code}-section2"), "Section 2's warning: its own build was clean");

        app.SelectSection(Code, 1);
        Assert.NotNull(app.FindOrNull($"problemsBadge-{Code}-section1", TimeSpan.FromSeconds(5)));
        app.ClickMiddleOf(app.Find("sectionTabProblems", "the Problems tab"));
        var fixedText = app.FindOrNull("problemFixedInTheSource-" + row.Id, TimeSpan.FromSeconds(10))
                        ?? throw new Xunit.Sdk.XunitException("Section 1's row does not read fixed in the source");
        Assert.Equal(Word("fixedInTheSource"), fixedText.Name);
    }

    // ---- 3. Seeded records: a build this window did not watch ---------------

    private static string SeededRecord(string course, int section, string alertKey, int rows, DateTime builtAt)
    {
        var made = new JsonArray();
        for (int index = 0; index < rows; index++)
        {
            string place = $"Unit {index / 10 + 1}/Lesson {index % 10 + 1} — 50% & <more> | \"quoted\"";
            made.Add(new JsonObject
            {
                ["id"] = $"pageSettingsUnreadable|{place}",
                ["kind"] = "pageSettingsUnreadable",
                ["page"] = place,
                ["reason"] = "",
                ["item"] = $"“{place}”",
                ["sentence"] = $"The settings at the top of “{place}” in {course} Section {section} could not be read.",
                ["detail"] = "Check the lines between the two --- lines.",
                ["fixable"] = false,
                ["prompt"] = "p",
                ["from"] = "build",
                ["firstSeen"] = builtAt.AddMinutes(-index).ToString("yyyy-MM-ddTHH:mm:ssZ"),
                ["lastSeen"] = builtAt.ToString("yyyy-MM-ddTHH:mm:ssZ"),
            });
        }
        var record = new JsonObject
        {
            ["version"] = 1, ["course"] = course, ["section"] = section, ["buildId"] = alertKey,
            ["builtAt"] = builtAt.ToString("yyyy-MM-ddTHH:mm:ssZ"), ["occasion"] = "preview",
            ["pagesShown"] = new JsonArray(), ["before"] = new JsonArray(), ["siteSaidComplete"] = true,
            ["alertKey"] = alertKey,
            ["changed"] = new JsonObject { ["new"] = new JsonArray(made.Select(r => (JsonNode?)JsonValue.Create(r!["id"]!.ToString())).ToArray()), ["gone"] = new JsonArray() },
            ["rows"] = made,
        };
        return record.ToJsonString();
    }

    private static void Seed(string workspace, string course, int section, string json)
    {
        string path = SectionProblemsRecord.PathFor(
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Plantoir", "builds",
                         FolderContainers.FolderIdentifier(workspace)), course, section);
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, json, Utf8);
    }

    private static void TwoSections(string courses) =>
        EndToEnd.WriteCourse(courses, Code, "Maths 50% & <more>", new[] { "Concepts" }, config =>
        {
            config["num_sections"] = 2;
            config["section_numbers"] = new JsonArray(1, 2);
        });

    /// <summary>
    /// Opening a section onto a record nobody has answered raises the alert;
    /// one already answered (in the answers file a relaunch reads) does not —
    /// though its tab and warning are there. And the keyboard: the bar's arrow
    /// keys change the tab, Tab reaches the table, Space ticks; awkward page
    /// names are shown as written.
    /// </summary>
    [UiFact]
    public void OpeningOntoAnUnansweredRecordRaisesTheAlert_AndAnAnsweredOneDoesNot()
    {
        using var app = new DrivenApp(TwoSections, beforeLaunch: workspace =>
        {
            var now = DateTime.UtcNow;
            Seed(workspace, Code, 1, SeededRecord(Code, 1, "ALERT-ONE", 2, now));
            Seed(workspace, Code, 2, SeededRecord(Code, 2, "ALERT-TWO", 1, now));
            // Section 2's alert was answered yesterday: the file a relaunch reads.
            // (The harness has already pointed this process at the run's state folder.)
            var kept = ProblemsAcknowledgements.Read(workspace);
            kept.RememberAnswered("ALERT-TWO", Code, 2);
            kept.Write(workspace);
        });
        app.SelectSection(Code, 2);
        Assert.True(Retry.WhileFalse(() => Showing(app, "sectionTabWebsite"), TimeSpan.FromSeconds(10)).Result, "the tab bar shows");
        Assert.NotNull(app.FindOrNull($"problemsBadge-{Code}-section2", TimeSpan.FromSeconds(5)));
        Thread.Sleep(3000);
        Assert.Null(app.OpenDialog());

        app.SelectSection(Code, 1);
        string several = Word("alertTitleSeveral", ("count", "2"), ("course", Code), ("section", "1"));
        var alert = WaitForDialog(app, several, TimeSpan.FromSeconds(20));
        Assert.Null(alert.FindFirstDescendant(cf => cf.ByAutomationId("SecondaryButton")));   // nothing new has a repair
        Button(alert, "CloseButton").AsButton().Invoke();                                      // Not Now
        Assert.True(Retry.WhileFalse(() => app.OpenDialog() is null, TimeSpan.FromSeconds(5)).Result);
        Assert.True(IsSelected(app, "sectionTabWebsite"), "Not Now leaves the Website tab");

        // Answered now: away and back raises nothing.
        app.SelectSection(Code, 2);
        app.SelectSection(Code, 1);
        Thread.Sleep(3000);
        Assert.Null(app.OpenDialog());
        Assert.Contains($"{Code}/1 · answered the alert about new problems: Not Now", TrailOf(app));

        // The keyboard: Right on the bar chooses Problems; Tab reaches the table; Space ticks.
        app.ClickMiddleOf(app.Find("sectionTabWebsite", "the Website tab"));
        Measured($"after a click on Website the focus was on {string.Join(" < ", FocusedAndAbove(app).Take(4))}.");
        Keyboard.Type(VirtualKeyShort.RIGHT);
        Thread.Sleep(300);
        Measured($"after Right the focus was on {string.Join(" < ", FocusedAndAbove(app).Take(4))}.");
        bool followedFocus = Retry.WhileFalse(() => IsSelected(app, "sectionTabProblems"), TimeSpan.FromSeconds(2)).Result;
        Measured($"on the tab bar, Right {(followedFocus ? "chose Problems by itself" : "moved the focus only; Space chose it")}.");
        if (!followedFocus) Keyboard.Type(VirtualKeyShort.SPACE);
        if (!Retry.WhileFalse(() => IsSelected(app, "sectionTabProblems"), TimeSpan.FromSeconds(2)).Result)
        {
            Measured("Space did not choose it either; Return did " + "(see the next line).");
            Keyboard.Type(VirtualKeyShort.RETURN);
        }
        Assert.True(Retry.WhileFalse(() => IsSelected(app, "sectionTabProblems"), TimeSpan.FromSeconds(5)).Result,
                    "the keyboard on the bar chose Problems");
        string? reached = null;
        for (int press = 0; press < 6 && reached is null; press++)
        {
            Keyboard.Type(VirtualKeyShort.TAB);
            Thread.Sleep(150);
            reached = FocusedAndAbove(app).FirstOrDefault(id => id.StartsWith("problemRow-", StringComparison.Ordinal));
        }
        Assert.True(reached is not null, $"Tab never reached a row; it was on {string.Join(" < ", FocusedAndAbove(app))}");
        Keyboard.Type(VirtualKeyShort.SPACE);
        Assert.True(Retry.WhileFalse(() => Status(app.Find(reached!, "the row")) == "not ticked", TimeSpan.FromSeconds(3)).Result);

        // Shown as written, whatever a teacher typed.
        string awkward = "Unit 1/Lesson 1 — 50% & <more> | \"quoted\"";
        Assert.NotNull(app.FindOrNull("problemRow-pageSettingsUnreadable|" + awkward, TimeSpan.FromSeconds(3)));
        Assert.Contains(awkward, DrivenApp.TextsUnder(app.Find("problemsTable", "the table")));
        Assert.Contains(SectionProblemsWording.IntroFor("MPM2D", 1), DrivenApp.TextsUnder(app.Window));
    }

    /// <summary>
    /// 300 rows: how long the tab takes to show, and that every row is made
    /// up front and the last can be scrolled to (review change 4). A
    /// measurement first; it fails only past two seconds, which a teacher
    /// would feel.
    /// </summary>
    [UiFact]
    public void ThreeHundredRowsShowInTime()
    {
        using var app = new DrivenApp(TwoSections, beforeLaunch: workspace =>
        {
            Seed(workspace, Code, 1, SeededRecord(Code, 1, "MANY", 300, DateTime.UtcNow));
            // (The harness has already pointed this process at the run's state folder.)
            var kept = ProblemsAcknowledgements.Read(workspace);
            kept.RememberAnswered("MANY", Code, 1);
            kept.Write(workspace);
        });
        var clock = Stopwatch.StartNew();
        app.SelectSection(Code, 1);
        Measured($"the section with 300 problems opened in {clock.Elapsed.TotalMilliseconds:0} ms (including the click and the title).");
        Assert.True(Retry.WhileFalse(() => Showing(app, "sectionTabProblems"), TimeSpan.FromSeconds(10)).Result, "the tab bar never showed");
        Measured($"the tab bar was on screen {clock.Elapsed.TotalMilliseconds:0} ms after the section was clicked.");
        var tab = app.FindOrNull("sectionTabProblems", TimeSpan.FromSeconds(10)) ?? throw new Xunit.Sdk.XunitException("no tab bar; the window holds: "
            + string.Join(", ", app.Window.FindAllDescendants().Select(e => { try { return $"{e.ControlType}:{e.AutomationId}:{e.Name}"; } catch { return "?"; } }).Take(120)));
        clock.Restart();
        app.ClickMiddleOf(tab);
        var table = Retry.WhileNull(() => app.FindOrNull("problemsTable", TimeSpan.FromMilliseconds(100)), TimeSpan.FromSeconds(10)).Result
                    ?? throw new Xunit.Sdk.XunitException("the table never showed");
        double shown = clock.Elapsed.TotalMilliseconds;
        string built = Status(table);
        Measured($"Problems shown {shown:0} ms after the click; the view said \"{built}\".");
        Assert.StartsWith("built 300 rows in", built);
        var items = Retry.WhileEmpty(() => table.FindAllDescendants(cf => cf.ByControlType(ControlType.ListItem)),
                                     TimeSpan.FromSeconds(5)).Result ?? Array.Empty<AutomationElement>();
        Measured($"UI Automation lists {items.Length} of the 300 rows before scrolling (a ListView realises the rows it shows).");
        Assert.NotEmpty(items);
        // The last row can be reached: scrolled to the bottom, it is there.
        Assert.True(table.Patterns.Scroll.IsSupported, "the table scrolls");
        table.Patterns.Scroll.Pattern.SetScrollPercent(-1, 100);
        const string LastPlace = "Unit 30/Lesson 10";
        Assert.True(Retry.WhileFalse(() => table.FindAllDescendants(cf => cf.ByControlType(ControlType.ListItem))
                                              .Any(item => item.Name.Contains(LastPlace, StringComparison.Ordinal)),
                                     TimeSpan.FromSeconds(5)).Result, "the 300th row is there at the bottom");
        Assert.True(shown < 2000, $"the tab took {shown:0} ms to show 300 rows");
    }
}
