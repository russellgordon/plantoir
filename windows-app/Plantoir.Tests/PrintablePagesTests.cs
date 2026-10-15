using System.Reflection;
using System.Text.Json.Nodes;
using Newtonsoft.Json.Linq;
using Plantoir.Core.Models;

namespace Plantoir.Tests;

/// <summary>
/// Printable pages on Windows (#496; the mac's #454, #499): Course Settings →
/// Printing, the <c>settings saved</c> line's printing clause, the guidance
/// for assistants and the preview pane's hand-over to the web browser.
/// Names mirror the mac's <c>PrintablePagesTests.swift</c> where a test does
/// the same job. Every case is read from <c>contracts/shared-rules.json</c> →
/// <c>printablePages</c>, never retyped.
/// </summary>
public sealed partial class PrintablePagesTests : IDisposable
{
    private readonly string _folder = Path.Combine(Path.GetTempPath(), "plantoir-printable-" + Guid.NewGuid().ToString("N"));

    public PrintablePagesTests() => Directory.CreateDirectory(_folder);

    public void Dispose()
    {
        try
        {
            foreach (var file in Directory.EnumerateFiles(_folder, "*", SearchOption.AllDirectories))
                File.SetAttributes(file, FileAttributes.Normal);
            Directory.Delete(_folder, recursive: true);
        }
        catch { }
    }

    private static JsonNode Printable => ContractLoader.LoadJson("shared-rules.json")["printablePages"]!;

    private static CourseConfiguration Config(string json) =>
        CourseConfiguration.FromBytes(System.Text.Encoding.UTF8.GetBytes(json));

    // ---- Course Settings → Printing: the getters --------------------------

    [Fact]
    public void ACourseWithNoPrintSettingsReadsTheDefaults()
    {
        var config = Config("{\"course_code\": \"ICS3U\"}");
        Assert.Equal("", config.PrintSchoolName);
        Assert.Equal(["name", "date"], config.PrintBlanks);
        Assert.Equal("header_left", config.PrintSchoolNameAt);
        Assert.Equal("footer_left", config.PrintCourseCodeAt);
        Assert.False(config.HasUnsavedChanges);
    }

    [Fact]
    public void UnknownValuesReadAsNothingOrTheDefaultAndAreNotWrittenBack()
    {
        var config = Config("{\"course_code\": \"ICS3U\", \"print_blanks\": [\"seat\", \"class_number\", \"name\"], " +
                            "\"print_school_name_at\": \"top\", \"print_course_code_at\": 7, \"print_school_name\": \"   \"}");
        Assert.Equal(["name", "class_number"], config.PrintBlanks);
        Assert.Equal("header_left", config.PrintSchoolNameAt);
        Assert.Equal("footer_left", config.PrintCourseCodeAt);
        Assert.Equal("   ", config.PrintSchoolName);

        // What the form does on open: set every control from the getters.
        // A setter given what it would read back changes nothing.
        config.PrintBlanks = config.PrintBlanks;
        config.PrintSchoolNameAt = config.PrintSchoolNameAt;
        config.PrintCourseCodeAt = config.PrintCourseCodeAt;
        config.PrintSchoolName = config.PrintSchoolName;

        Assert.Equal(new JArray("seat", "class_number", "name"), config.Values["print_blanks"]);
        Assert.Equal("top", (string?)config.Values["print_school_name_at"]);
        Assert.Equal("   ", (string?)config.Values["print_school_name"]);
        Assert.False(config.HasUnsavedChanges);
    }

    [Fact]
    public void AnEmptyListMeansNoBlanks()
    {
        Assert.Empty(Config("{\"print_blanks\": []}").PrintBlanks);
        Assert.Empty(Config("{\"print_blanks\": \"name\"}").PrintBlanks);
    }

    [Fact]
    public void ANullListIsTheDefault()
    {
        // Held against the BUILD: print_settings._blanks reads null as absent,
        // so the paper prints Name and Date (plan review H3; the corners case
        // "blanks of null are the default").
        var config = Config("{\"print_blanks\": null}");
        Assert.Equal(["name", "date"], config.PrintBlanks);
        var corners = PrintCorners.Compose(JObject.Parse("{\"print_blanks\": null}"), "ICS3U");
        Assert.StartsWith("Name ", corners.TopRight);
        Assert.Contains("Date ", corners.TopRight);
    }

    [Fact]
    public void BlanksAreWrittenInPrintOrderAndAnEmptySchoolNameRemovesTheKey()
    {
        var config = Config("{\"course_code\": \"ICS3U\", \"print_school_name\": \"Lakefield\"}");
        config.PrintBlanks = ["class_number", "name"];
        Assert.Equal(new JArray("name", "class_number"), config.Values["print_blanks"]);

        config.PrintSchoolName = "  ";
        Assert.Null(config.Values["print_school_name"]);
        config.PrintSchoolName = "Lakefield College School";
        Assert.Equal("Lakefield College School", (string?)config.Values["print_school_name"]);
        config.PrintSchoolName = "";
        Assert.Null(config.Values["print_school_name"]);

        config.PrintSchoolNameAt = "none";
        config.PrintCourseCodeAt = "header_left";
        Assert.Equal("none", (string?)config.Values["print_school_name_at"]);
        Assert.Equal("header_left", (string?)config.Values["print_course_code_at"]);
    }

    [Fact]
    public void EveryCornersCaseHoldsAsTheContractSays()
    {
        var cases = Printable["corners"]!["cases"]!.AsArray();
        Assert.True(cases.Count >= 13, "printablePages.corners.cases shrank");
        foreach (var c in cases)
        {
            string name = c!["name"]!.ToString();
            var corners = PrintCorners.Compose(JObject.Parse(c["settings"]!.ToJsonString()), c["folder"]!.ToString());
            Assert.True(c["expect"]!["topLeft"]!.ToString() == corners.TopLeft, $"{name}: topLeft is \"{corners.TopLeft}\"");
            Assert.True(c["expect"]!["topRight"]!.ToString() == corners.TopRight, $"{name}: topRight is \"{corners.TopRight}\"");
            Assert.True(c["expect"]!["bottomLeft"]!.ToString() == corners.BottomLeft, $"{name}: bottomLeft is \"{corners.BottomLeft}\"");
        }
        Assert.Equal(Printable["corners"]!["blankJoin"]!.ToString(), PrintCorners.BlankJoin);
        foreach (var (blank, length) in PrintCorners.BlankLines)
            Assert.Equal(Printable["corners"]!["blankLines"]![blank]!.GetValue<int>(), length);
    }

    [Fact]
    public void TheSketchLeadsTheBottomLeftCornerWithThePagesTitle()
    {
        var config = Config("{\"course_code\": \"ICS3U\"}");
        var sketch = PrintCorners.Sketch(config, "ics3u");
        Assert.Equal(CourseSettingsWording.PrintingSampleTitle + " · ICS3U", sketch.BottomLeft);
        Assert.Equal("Page 1 of 3", sketch.BottomRight);
        config.PrintCourseCodeAt = "none";
        Assert.Equal(CourseSettingsWording.PrintingSampleTitle, PrintCorners.Sketch(config, "ICS3U").BottomLeft);
    }

    [Fact]
    public void EveryPrintingWordIsTheContracts()
    {
        var wording = ContractLoader.LoadJson("shared-rules.json")["courseSettingsWording"]!.AsObject();
        var mine = typeof(CourseSettingsWording).GetFields(BindingFlags.Public | BindingFlags.Static)
            .Where(f => f.IsLiteral && f.Name.StartsWith("Printing", StringComparison.Ordinal) && f.Name != "PrintedPageLabel")
            .ToDictionary(f => char.ToLowerInvariant(f.Name[0]) + f.Name[1..], f => (string)f.GetRawConstantValue()!);
        var theirs = wording.Where(p => p.Key.StartsWith("printing", StringComparison.Ordinal)).ToList();
        Assert.Equal(13, theirs.Count);
        foreach (var (key, value) in theirs)
        {
            Assert.True(mine.TryGetValue(key, out var said), $"courseSettingsWording.{key} has no constant here");
            Assert.Equal(value!.ToString(), said);
        }
        Assert.Equal(theirs.Count, mine.Count);
        Assert.Equal(Printable["words"]!["pageLabel"]!.ToString(), CourseSettingsWording.PrintedPageLabel);
        foreach (var (blank, key) in new[] { ("name", "blankName"), ("date", "blankDate"), ("class_number", "blankClassNumber") })
            Assert.Equal(Printable["words"]![key]!.ToString(), CourseSettingsWording.PrintingBlank(blank));
    }

    // ---- The settings saved line ------------------------------------------

    private static SettingsSavedLine.PrintingSnapshot Snapshot(string json) =>
        SettingsSavedLine.PrintingSnapshot.From(Config(json));

    [Fact]
    public void NothingChangedSaysNothing()
    {
        Assert.Null(SettingsSavedLine.PrintingClause(Snapshot("{}"), Snapshot("{}")));
        // A file with no settings compares with the defaults, and so does a
        // null list (the build's reading).
        Assert.Null(SettingsSavedLine.PrintingClause(null, Snapshot("{\"print_blanks\": null}")));
        Assert.Null(SettingsSavedLine.PrintingClause(Snapshot("{\"print_school_name\": \"Lakefield\"}"),
            Snapshot("{\"print_school_name\": \"  Lakefield \"}")));
    }

    [Fact]
    public void TheSchoolNameIsSetChangedOrClearedAndNeverNamed()
    {
        string? set = SettingsSavedLine.PrintingClause(Snapshot("{}"), Snapshot("{\"print_school_name\": \"Lakefield\"}"));
        string? changed = SettingsSavedLine.PrintingClause(Snapshot("{\"print_school_name\": \"Lakefield\"}"),
            Snapshot("{\"print_school_name\": \"Lakefield College School\"}"));
        string? cleared = SettingsSavedLine.PrintingClause(Snapshot("{\"print_school_name\": \"Lakefield\"}"), Snapshot("{}"));
        Assert.Equal("school name set", set);
        Assert.Equal("school name changed", changed);
        Assert.Equal("school name cleared", cleared);
        foreach (var line in new[] { set, changed, cleared }) Assert.DoesNotContain("Lakefield", line);
    }

    [Fact]
    public void BlanksAndPlacesSayBeforeAndAfter()
    {
        Assert.Equal("blanks Name, Date → Name, Date, Class #",
            SettingsSavedLine.PrintingClause(null, Snapshot("{\"print_blanks\": [\"name\", \"date\", \"class_number\"]}")));
        Assert.Equal("blanks Name, Date → none",
            SettingsSavedLine.PrintingClause(null, Snapshot("{\"print_blanks\": []}")));
        Assert.Equal("school name top left → not printed; course code bottom left → top left",
            SettingsSavedLine.PrintingClause(null,
                Snapshot("{\"print_school_name_at\": \"none\", \"print_course_code_at\": \"header_left\"}")));
    }

    [Fact]
    public void TheSettingsSavedLineCarriesThePrintingClause()
    {
        var report = new CourseConfiguration.SaveReport(["hidden"], []);
        Assert.Equal("saved the settings for ICS3U; printing: school name set; kept from elsewhere: hidden",
            SettingsSavedLine.Compose("ICS3U", report, Snapshot("{}"), Snapshot("{\"print_school_name\": \"Lakefield\"}")));
        Assert.Equal("saved the settings for ICS3U",
            SettingsSavedLine.Compose("ICS3U", new CourseConfiguration.SaveReport([], []), Snapshot("{}"), Snapshot("{}")));
    }
}

/// <summary>The preview pane hands pages to the browser (#496; the mac's tests, names kept).</summary>
public sealed class PreviewBrowserHandoffTests
{
    private static JsonNode Printable => ContractLoader.LoadJson("shared-rules.json")["printablePages"]!;

    [Fact]
    public void OnlyThePreviewsOwnPagesAndTheContractsModesAreOpened()
    {
        Assert.Equal("http://localhost:8461/Unit-1/Worksheet-3#plantoir-print=questionsOnly&paper=landscape",
            PreviewBrowserHandoff.PrintAddress("http://localhost:8461/Unit-1/Worksheet-3", "questionsOnly", "landscape")?.AbsoluteUri);
        Assert.Null(PreviewBrowserHandoff.PrintAddress("https://example.com/x", "questionsOnly", "portrait"));
        Assert.Null(PreviewBrowserHandoff.PrintAddress("file:///C:/Windows/win.ini", "questionsOnly", "portrait"));
        Assert.Null(PreviewBrowserHandoff.PrintAddress("http://localhost:8461/x", "everything", "portrait"));
        Assert.Null(PreviewBrowserHandoff.PrintAddress("http://localhost:8461/x", "questionsOnly", "a4"));

        Assert.Equal(Printable["modes"]!["list"]!.AsArray().Select(m => m!["mode"]!.ToString()), PreviewBrowserHandoff.Modes);
        var papers = Printable["paper"]!["cases"]!.AsArray()
            .Where(c => (c!["paper"]!.ToString(), c["size"]!.ToString()) is ("portrait", "letter") or ("landscape", "letter landscape"))
            .Select(c => c!["paper"]!.ToString());
        Assert.Equal(papers, PreviewBrowserHandoff.Papers);
    }

    [Fact]
    public void ThePrintMessageOpensThePageAndTellsTheTrail()
    {
        // What the shim forwards: {plantoirPrint: {mode, paper, url}}.
        var request = PreviewBrowserHandoff.FromMessage(
            "{\"plantoirPrint\":{\"mode\":\"withAnswersAtTheEnd\",\"paper\":\"portrait\",\"url\":\"http://localhost:8461/Unit-1/Worksheet-3\"}}");
        Assert.NotNull(request);
        Assert.Equal("http://localhost:8461/Unit-1/Worksheet-3#plantoir-print=withAnswersAtTheEnd&paper=portrait", request!.Value.Address.AbsoluteUri);
        Assert.Equal("preview page opened in the web browser — to print it with the answers at the end (Unit-1/Worksheet-3)",
            PreviewBrowserHandoff.TrailWords(request.Value.Address, request.Value.Address, PreviewBrowserHandoff.Why.PrintHandout,
                request.Value.Mode, request.Value.Paper));

        // No paper (a page built before #499) is portrait.
        var old = PreviewBrowserHandoff.FromMessage("{\"plantoirPrint\":{\"mode\":\"answersOnly\",\"url\":\"http://localhost:8461/x\"}}");
        Assert.Equal("portrait", old?.Paper);
        var sideways = PreviewBrowserHandoff.FromMessage(
            "{\"plantoirPrint\":{\"mode\":\"answersOnly\",\"paper\":\"landscape\",\"url\":\"http://localhost:8461/Unit-1/Worksheet-3\"}}")!.Value;
        Assert.Equal("preview page opened in the web browser — to print it answers only, on landscape paper (Unit-1/Worksheet-3)",
            PreviewBrowserHandoff.TrailWords(sideways.Address, sideways.Address, PreviewBrowserHandoff.Why.PrintHandout, sideways.Mode, sideways.Paper));

        // Anything else is refused: another site, another shape, not JSON.
        Assert.Null(PreviewBrowserHandoff.FromMessage("{\"plantoirPrint\":{\"mode\":\"answersOnly\",\"url\":\"https://example.com/x\"}}"));
        Assert.Null(PreviewBrowserHandoff.FromMessage("{\"mode\":\"answersOnly\",\"url\":\"http://localhost:8461/x\"}"));
        Assert.Null(PreviewBrowserHandoff.FromMessage("\"print\""));
        Assert.Null(PreviewBrowserHandoff.FromMessage("not json"));

        // The browser gets 127.0.0.1, as Open in Browser does; the fragment survives.
        Assert.Equal("http://127.0.0.1:8461/Unit-1/Worksheet-3#plantoir-print=withAnswersAtTheEnd&paper=portrait",
            PreviewBrowserHandoff.ForTheBrowser(request.Value.Address).AbsoluteUri);
    }

    [Fact]
    public void TheTrailWordsMatchTheContractsExampleLine()
    {
        var events = ContractLoader.LoadJson("shared-rules.json")["activityTrail"]!["mustRecord"]!.AsArray();
        string example = events.First(e => e!["event"]!.ToString() == "preview page opened in the web browser")!["line"]!.ToString();
        var printed = new Uri("http://localhost:8461/Unit-1/Worksheet-3#plantoir-print=withAnswersAtTheEnd&paper=portrait");
        Assert.Equal(example, "{course}/{section} · " +
            PreviewBrowserHandoff.TrailWords(printed, printed, PreviewBrowserHandoff.Why.PrintHandout, "withAnswersAtTheEnd", "portrait"));
        Assert.Equal("preview page opened in the web browser — the page's own PDF (Unit-1/Worksheet-3)",
            PreviewBrowserHandoff.TrailWords(new Uri("http://localhost:8461/Unit-1/Worksheet-3"),
                new Uri("http://localhost:8461/Media/Key.pdf"), PreviewBrowserHandoff.Why.NewWindow));
        Assert.Equal("preview page opened in the web browser — a link to another page of the site (the front page)",
            PreviewBrowserHandoff.TrailWords(new Uri("http://127.0.0.1:8461/"),
                new Uri("http://127.0.0.1:8461/Unit-1"), PreviewBrowserHandoff.Why.NewWindow));
    }

    [Fact]
    public void ALinksDestinationNeverReachesTheTrail()
    {
        var page = new Uri("http://localhost:8461/Unit-1/Worksheet-3");
        foreach (string secret in new[]
                 {
                     "https://docs.google.com/document/d/1AbcSecretDocId/edit?usp=sharing",
                     "https://zoom.us/j/81234567890",
                     "mailto:teacher@school.ca",
                 })
        {
            string line = PreviewBrowserHandoff.TrailWords(page, new Uri(secret), PreviewBrowserHandoff.Why.NewWindow);
            Assert.Equal("preview page opened in the web browser — a link to another site (Unit-1/Worksheet-3)", line);
        }
        Assert.Equal("preview page opened in the web browser — a link to another site (an unknown page)",
            PreviewBrowserHandoff.TrailWords(new Uri("https://example.com/x"), new Uri("https://example.com/y"), PreviewBrowserHandoff.Why.NewWindow));
        Assert.True(PreviewBrowserHandoff.IsHandedOver(new Uri("mailto:teacher@school.ca")));
        Assert.False(PreviewBrowserHandoff.IsHandedOver(new Uri("file:///C:/Windows/win.ini")));
    }

    [Fact]
    public void TheShimGivesThePageTheShapeItsPrintCodeLooksFor()
    {
        // print.inline.ts checks window.webkit.messageHandlers.plantoirPrint
        // and posts {mode, paper, url}; the shim must offer exactly that name.
        string printScript = File.ReadAllText(Path.Combine(ContractLoader.RepositoryRoot,
            "support", "quartz", "components", "scripts", "print.inline.ts"));
        Assert.Contains("messageHandlers", printScript);
        Assert.Contains(PreviewBrowserHandoff.MessageName, printScript);
        Assert.Contains("window.webkit", PreviewBrowserHandoff.PrintShim);
        Assert.Contains("messageHandlers.plantoirPrint", PreviewBrowserHandoff.PrintShim);
        Assert.Contains("window.chrome.webview.postMessage({plantoirPrint:m})", PreviewBrowserHandoff.PrintShim);
    }
}
