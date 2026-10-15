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
