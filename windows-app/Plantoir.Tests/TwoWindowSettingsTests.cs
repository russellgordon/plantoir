using System;
using System.IO;
using System.Linq;
using Newtonsoft.Json.Linq;
using Plantoir.Core.Models;
using Plantoir.Core.Undo;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// #272 (mac #265): two windows on one working folder each hold their own copy
/// of a course's settings, so a Save writes only what THIS copy changed —
/// <c>shared-rules.json → savingSettings.cases</c> — and Revert reads the file.
/// </summary>
public class TwoWindowSettingsTests : IDisposable
{
    private readonly string _dir = Directory.CreateTempSubdirectory("two-windows-").FullName;
    private string Folder => Path.Combine(_dir, "wf");
    private string CourseFolder => Path.Combine(Folder, "courses", "ICS3U");
    private string ConfigPath => Path.Combine(CourseFolder, "course_config.json");

    public TwoWindowSettingsTests()
    {
        Directory.CreateDirectory(CourseFolder);
        File.WriteAllText(Path.Combine(Folder, Workspace.MarkerLauncher), "");
    }

    public void Dispose() { try { Directory.Delete(_dir, true); } catch { } }

    /// <summary>
    /// The window's Save, as Course Settings makes it since #899 W8-12
    /// (<see cref="CourseConfiguration.SaveCourseSettings(Course)"/>, one
    /// step), on this test's own list.
    /// </summary>
    private CourseConfiguration.SaveReport Save(CourseConfiguration window)
    {
        var list = new UndoForThisProcess(Path.Combine(_dir, "state", "undo"), UndoMode.Shadow, null);
        var door = new UndoDoor(list.Journal, list.Mode, list.Maintainers, trail: list.Trail);
        return CourseConfiguration.SaveCourseSettings(new Course("ICS3U", CourseFolder, window), list, door);
    }

    private static JObject Obj(System.Text.Json.Nodes.JsonNode? node) => JObject.Parse(node!.ToJsonString());

    [Fact]
    public void EverySavingCaseMergesAsTheContractSays()
    {
        var cases = ContractLoader.LoadJson("shared-rules.json")["savingSettings"]!["cases"]!.AsArray();
        Assert.Equal(5, cases.Count);
        foreach (var c in cases)
        {
            string name = c!["name"]!.ToString();
            var (written, kept, replaced) = CourseConfiguration.Merged(Obj(c["base"]), Obj(c["onDisk"]), Obj(c["mine"]));
            Assert.True(JToken.DeepEquals(Obj(c["written"]), written), $"{name}: wrote {written}");
            Assert.True(c["keptFromElsewhere"]!.AsArray().Select(k => k!.ToString()).OrderBy(k => k, StringComparer.Ordinal)
                .SequenceEqual(kept.OrderBy(k => k, StringComparer.Ordinal)), $"{name}: kept {string.Join(",", kept)}");
            Assert.True(c["replacedChangesFromElsewhere"]!.AsArray().Select(k => k!.ToString())
                .SequenceEqual(replaced), $"{name}: replaced {string.Join(",", replaced)}");
        }
    }

    /// <summary>The measurement, as a test: two loaded copies, the reported failure.</summary>
    [Fact]
    public void TheOtherWindowsHidesSurviveAStaleWindowsSave()
    {
        File.WriteAllText(ConfigPath, """{"hidden":["Media","Tasks","Style"],"show_reading_time":false}""");
        var windowA = CourseConfiguration.Load(ConfigPath);
        var windowB = CourseConfiguration.Load(ConfigPath);

        windowA.Values["hidden"] = new JArray("Media", "All Classes");
        Save(windowA);
        windowB.Values["show_reading_time"] = true;
        var report = Save(windowB);

        var onDisk = JObject.Parse(File.ReadAllText(ConfigPath));
        Assert.Equal(new[] { "Media", "All Classes" }, onDisk["hidden"]!.Select(t => t.ToString()));
        Assert.True(onDisk["show_reading_time"]!.Value<bool>());
        Assert.Equal(new[] { "hidden" }, report.KeptFromElsewhere);
        Assert.False(windowB.HasUnsavedChanges);
    }

    /// <summary>
    /// #272 as named: a stale window's Save of the SAME member wins, whole
    /// list, and its report says it replaced the change made elsewhere (the
    /// list that chooses the status line's sentence), keeping nothing.
    /// </summary>
    [Fact]
    public void AStaleWindowsSaveOfTheSameMemberWinsAndSaysItReplacedIt()
    {
        File.WriteAllText(ConfigPath, """{"hidden":["Media","Tasks","Style"],"show_reading_time":false}""");
        var windowA = CourseConfiguration.Load(ConfigPath);
        var windowB = CourseConfiguration.Load(ConfigPath);

        windowA.Values["hidden"] = new JArray("Media", "All Classes");
        Save(windowA);
        windowB.Values["hidden"] = new JArray("Tasks");
        var report = Save(windowB);

        var onDisk = JObject.Parse(File.ReadAllText(ConfigPath));
        Assert.Equal(new[] { "Tasks" }, onDisk["hidden"]!.Select(t => t.ToString()));
        Assert.Equal(new[] { "hidden" }, report.ReplacedChangesFromElsewhere);
        Assert.Empty(report.KeptFromElsewhere);
        Assert.False(windowB.HasUnsavedChanges);
    }

    [Fact]
    public void RevertReadsTheFileAndAnUnchangedCopyRereadsIt()
    {
        File.WriteAllText(ConfigPath, """{"hidden":["Media"]}""");
        var windowA = CourseConfiguration.Load(ConfigPath);
        var windowB = CourseConfiguration.Load(ConfigPath);
        var windowC = CourseConfiguration.Load(ConfigPath);
        windowB.Values["footer_html"] = "unsaved in B";

        windowA.Values["hidden"] = new JArray("Media", "Tasks", "Style");
        Save(windowA);

        Assert.False(windowB.RereadIfNothingUnsaved(ConfigPath));   // unsaved: left alone
        Assert.True(windowC.RereadIfNothingUnsaved(ConfigPath));
        Assert.Equal(3, ((JArray)windowC.Values["hidden"]!).Count);

        windowB.RevertToFile(ConfigPath);
        Assert.Equal(3, ((JArray)windowB.Values["hidden"]!).Count);   // A's hides, not B's remembered one
        Assert.False(windowB.HasUnsavedChanges);
    }

    [Fact]
    public void TheReplacedSidebarSentenceIsTheContracts() =>
        Assert.Equal(ContractLoader.LoadJson("shared-rules.json")["specialNames"]!["settingsSaveReplacedSidebarChange"]!["message"]!.ToString(),
                     CourseConfiguration.SaveReplacedSidebarChange);
}
