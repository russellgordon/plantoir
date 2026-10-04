using System;
using System.IO;
using System.Linq;
using Newtonsoft.Json.Linq;
using Plantoir.Core.Models;
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
    private string ConfigPath => Path.Combine(_dir, "course_config.json");
    public void Dispose() { try { Directory.Delete(_dir, true); } catch { } }

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
        windowA.Write(ConfigPath);
        windowB.Values["show_reading_time"] = true;
        var report = windowB.Write(ConfigPath);

        var onDisk = JObject.Parse(File.ReadAllText(ConfigPath));
        Assert.Equal(new[] { "Media", "All Classes" }, onDisk["hidden"]!.Select(t => t.ToString()));
        Assert.True(onDisk["show_reading_time"]!.Value<bool>());
        Assert.Equal(new[] { "hidden" }, report.KeptFromElsewhere);
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
        windowA.Write(ConfigPath);

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
