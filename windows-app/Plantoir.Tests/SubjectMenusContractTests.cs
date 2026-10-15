using System.Text.Json.Nodes;
using Plantoir.Core.Models;

namespace Plantoir.Tests;

/// <summary>
/// <c>contracts/shared-rules.json</c> → <c>subjectMenus</c> (#488, the mac's
/// #457): which File, Course, Section and View items can be used in each
/// situation, deserialised and run against <see cref="SubjectMenuRules"/>. The
/// mac runs the identical cases in <c>SubjectMenuRulesTests</c>. The menu bar's
/// SHAPE (titles, order, keys) is platform mechanics and is not here.
/// </summary>
public class SubjectMenusContractTests
{
    private static JsonNode Rule => ContractLoader.LoadJson("shared-rules.json")["subjectMenus"]!;

    [Fact]
    public void EveryItemTheContractNamesIsAnItemHere_AndTheOtherWayRound()
    {
        var named = Rule["items"]!.AsArray().Select(n => n!.ToString()).ToList();
        var here = Enum.GetValues<SubjectMenuRules.Item>().Select(SubjectMenuRules.ContractName).ToList();
        Assert.Equal(named, here);   // the same names, in the same order
        foreach (string name in named)
            Assert.Equal(name, SubjectMenuRules.ContractName(SubjectMenuRules.ItemNamed(name)!.Value));
        Assert.Null(SubjectMenuRules.ItemNamed("noSuchItem"));
    }

    [Fact]
    public void EverySituationKeyIsAPropertyHere_WithTheContractsDefault()
    {
        var defaults = Rule["situationDefaults"]!.AsObject();
        var keys = Rule["situationKeys"]!.AsObject().Select(pair => pair.Key).ToList();
        Assert.Equal(keys.OrderBy(k => k), defaults.Select(pair => pair.Key).OrderBy(k => k));
        var properties = typeof(SubjectMenuRules.Situation).GetProperties()
            .Select(p => char.ToLowerInvariant(p.Name[0]) + p.Name[1..])
            .Where(name => name != "equalityContract")
            .OrderBy(name => name)
            .ToList();
        Assert.Equal(keys.OrderBy(k => k), properties);

        var fresh = new SubjectMenuRules.Situation();
        Assert.Equal(SubjectMenuRules.Enabled(Situation(new JsonObject())), SubjectMenuRules.Enabled(fresh));
        Assert.Equal(SubjectMenuRules.Row.None, fresh.Row);
        Assert.Empty(fresh.ReviseBlocked);
    }

    [Fact]
    public void EveryCaseEnablesExactlyWhatTheContractSays()
    {
        var cases = Rule["cases"]!.AsArray().Select(c => c!).ToList();
        Assert.True(cases.Count >= 21, $"subjectMenus.cases: {cases.Count} (21 when this was written)");
        var failures = new List<string>();
        foreach (var c in cases)
        {
            var expected = c["enabled"]!.AsArray().Select(n => n!.ToString()).OrderBy(n => n, StringComparer.Ordinal).ToList();
            var actual = SubjectMenuRules.Enabled(Situation(c["situation"]!.AsObject()))
                .Select(SubjectMenuRules.ContractName).OrderBy(n => n, StringComparer.Ordinal).ToList();
            if (!expected.SequenceEqual(actual))
                failures.Add($"{c["why"]}\n  missing: {string.Join(", ", expected.Except(actual))}\n  extra: {string.Join(", ", actual.Except(expected))}");
        }
        Assert.True(failures.Count == 0, string.Join("\n", failures));
    }

    /// <summary>The contract's defaults, overlaid with one case's situation, as a <see cref="SubjectMenuRules.Situation"/>.</summary>
    private static SubjectMenuRules.Situation Situation(JsonObject overrides)
    {
        var merged = new Dictionary<string, JsonNode?>();
        foreach (var (key, value) in Rule["situationDefaults"]!.AsObject()) merged[key] = value;
        foreach (var (key, value) in overrides) merged[key] = value;
        foreach (string key in overrides.Select(pair => pair.Key))
            Assert.True(Rule["situationDefaults"]![key] is not null, $"a case names the situation key {key}, which situationDefaults does not");

        bool Flag(string key) => merged[key]!.GetValue<bool>();
        string rowName = merged["row"]!.ToString();
        var row = Enum.GetValues<SubjectMenuRules.Row>().Single(r => SubjectMenuRules.ContractName(r) == rowName);
        var blocked = merged["reviseBlocked"]!.AsArray()
            .Select(n => Enum.GetValues<SubjectMenuRules.ReviseTarget>().Single(t => SubjectMenuRules.ContractName(t) == n!.ToString()))
            .ToHashSet();
        return new SubjectMenuRules.Situation
        {
            HasFolder = Flag("hasFolder"),
            FolderGettingReady = Flag("folderGettingReady"),
            SheetIsUp = Flag("sheetIsUp"),
            Row = row,
            KeptForReference = Flag("keptForReference"),
            StructuralHold = Flag("structuralHold"),
            Busy = Flag("busy"),
            Copying = Flag("copying"),
            Deploying = Flag("deploying"),
            HasSchedule = Flag("hasSchedule"),
            HasStartOfYearUndo = Flag("hasStartOfYearUndo"),
            HasLinksOffer = Flag("hasLinksOffer"),
            ReviseBlocked = blocked,
            ObsidianInstalled = Flag("obsidianInstalled"),
            SettingsMaySave = Flag("settingsMaySave"),
            SettingsMayRevert = Flag("settingsMayRevert"),
            PreviewButtonEnabled = Flag("previewButtonEnabled"),
            DeployButtonEnabled = Flag("deployButtonEnabled"),
            PreviewIsShowing = Flag("previewIsShowing"),
            PreviewIsRunning = Flag("previewIsRunning"),
            LastChangeIsHere = Flag("lastChangeIsHere"),
            VerbIsRunning = Flag("verbIsRunning"),
            CanGoBack = Flag("canGoBack"),
            CanGoForward = Flag("canGoForward"),
        };
    }
}
