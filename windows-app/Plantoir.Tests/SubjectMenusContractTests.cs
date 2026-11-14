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
    internal static JsonNode Rule => ContractLoader.LoadJson("shared-rules.json")["subjectMenus"]!;

    [Fact]
    public void EveryItemTheContractNamesIsAnItemHere_AndTheOtherWayRound()
    {
        var named = Rule["items"]!.AsArray().Select(n => n!.ToString()).ToList();
        var here = Enum.GetValues<SubjectMenuRules.Item>().Select(SubjectMenuRules.ContractName).ToList();
        // An item this app's menus do not have yet (the reference shelf's
        // groups, #827) is held open by name; the rest are the same names in
        // the same order, as before.
        var deferred = NamedGapLedger.GapsIn(NamedGapLedger.SubjectMenuItems, named, here);
        named = named.Where(name => !deferred.Contains(name)).ToList();
        // An item the contract renamed that this app still carries under its
        // older name (#897's Add Class…, owed by #927) stands in its place:
        // the older name must be here and gone from the contract, and it is
        // compared in the held name's position, so the order still holds.
        var contractNames = named.ToList();
        NamedGapLedger.StillNamed(NamedGapLedger.SubjectMenuItemsUnderAnOlderName, contractNames);
        named = contractNames.Select(name => SaidHereAs(name, contractNames, here)).ToList();
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
        // A situation this app cannot be in yet (a deployed folder shown in
        // the browser, #889) is held open by name; the rest as before.
        var deferred = NamedGapLedger.GapsIn(NamedGapLedger.SubjectMenuSituationKeys, keys, properties);
        Assert.Equal(keys.Where(k => !deferred.Contains(k)).OrderBy(k => k), properties);

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
        // A held item (see the fact above) is no member of SubjectMenuRules.Item,
        // which that fact's closed-check makes sure of, so it can never be
        // enabled here: it is taken out of what each case expects, and
        // everything else is compared as before.
        var held = NamedGapLedger.All.Where(entry => entry.Area == NamedGapLedger.SubjectMenuItems).Select(entry => entry.Key).ToHashSet();
        // A renamed item held under its older name is expected under that
        // name, in exactly the cases that enable the contract's (#927).
        var olderNames = NamedGapLedger.All.Where(entry => entry.Area == NamedGapLedger.SubjectMenuItemsUnderAnOlderName)
            .ToDictionary(entry => entry.Key, entry => NamedGapLedger.SubjectMenuItemsOlderNames[entry.Key]);
        int notRun = 0;
        int renamedEnabled = 0;
        foreach (var c in cases)
        {
            if (!CanBeIn(c["situation"]!.AsObject())) { notRun++; continue; }
            var expected = c["enabled"]!.AsArray().Select(n => n!.ToString()).Where(n => !held.Contains(n))
                .Select(n => olderNames.TryGetValue(n, out string? older) ? older : n)
                .OrderBy(n => n, StringComparer.Ordinal).ToList();
            renamedEnabled += c["enabled"]!.AsArray().Count(n => olderNames.ContainsKey(n!.ToString()));
            var actual = SubjectMenuRules.Enabled(Situation(c["situation"]!.AsObject()))
                .Select(SubjectMenuRules.ContractName).OrderBy(n => n, StringComparer.Ordinal).ToList();
            if (!expected.SequenceEqual(actual))
                failures.Add($"{c["why"]}\n  missing: {string.Join(", ", expected.Except(actual))}\n  extra: {string.Join(", ", actual.Except(expected))}");
        }
        Assert.True(failures.Count == 0, string.Join("\n", failures));
        Assert.True(cases.Count - notRun >= 21, $"only {cases.Count - notRun} cases run ({notRun} name a situation held open)");
        // Add Class… is enabled in five cases (#927: cases 7, 8, 16, 21 and
        // 22), three of them run here while #889's two situation keys are
        // held: a held rename that no case run enabled would hold nothing.
        if (olderNames.Count > 0)
            Assert.True(renamedEnabled >= 3, $"a renamed item held under its older name is enabled in only {renamedEnabled} of the cases run here (3 when this was written)");
    }

    /// <summary>
    /// <paramref name="name"/>, or the older name this app still carries it
    /// under when <see cref="NamedGapLedger.SubjectMenuItemsUnderAnOlderName"/>
    /// holds it: closed the day the contract's name is an item here, and
    /// refused if the older name is not an item here or is still one of the
    /// contract's (the caller checks the withdrawn direction with StillNamed).
    /// </summary>
    internal static string SaidHereAs(string name, IReadOnlyCollection<string> contractNames, IReadOnlyCollection<string> here)
    {
        var entry = NamedGapLedger.Holding(NamedGapLedger.SubjectMenuItemsUnderAnOlderName, name);
        if (entry is null) return name;
        Assert.False(here.Contains(name), NamedGapLedger.ClosedMessage(entry));
        Assert.True(NamedGapLedger.SubjectMenuItemsOlderNames.TryGetValue(name, out string? older),
            $"\"{name}\" is held under an older name, and NamedGapLedger.SubjectMenuItemsOlderNames gives none");
        Assert.True(here.Contains(older!), $"\"{name}\" is held as said here under \"{older}\", which is no item here");
        Assert.False(contractNames.Contains(older!), $"\"{name}\" is held as said here under \"{older}\", which the contract still names: that is no rename");
        return older!;
    }

    /// <summary>
    /// False for a case whose situation names a key <see cref="NamedGapLedger.SubjectMenuSituationKeys"/>
    /// holds open: this app has no such situation yet (the key is no property
    /// of <see cref="SubjectMenuRules.Situation"/>, which the fact above makes
    /// sure of), so the case cannot be put to it. It comes back the day the
    /// entry goes.
    /// </summary>
    internal static bool CanBeIn(JsonObject overrides)
    {
        var held = NamedGapLedger.All.Where(entry => entry.Area == NamedGapLedger.SubjectMenuSituationKeys).Select(entry => entry.Key).ToHashSet();
        return !overrides.Any(pair => held.Contains(pair.Key));
    }

    /// <summary>The contract's defaults, overlaid with one case's situation, as a <see cref="SubjectMenuRules.Situation"/>.</summary>
    internal static SubjectMenuRules.Situation Situation(JsonObject overrides)
    {
        Assert.True(CanBeIn(overrides), "a case naming a situation held open in NamedGapLedger cannot be put to this app");
        // A door this app does not have yet (GitHub Copilot, #884) greys
        // nothing here: its items are held open too.
        var heldDoors = NamedGapLedger.OutsideDoorsHeld(
            ContractLoader.LoadJson("app-rules.json")["outsideAgents"]!["agents"]!.AsArray().Select(a => a!["key"]!.ToString()));
        var merged = new Dictionary<string, JsonNode?>();
        foreach (var (key, value) in Rule["situationDefaults"]!.AsObject()) merged[key] = value;
        foreach (var (key, value) in overrides) merged[key] = value;
        foreach (string key in overrides.Select(pair => pair.Key))
            Assert.True(Rule["situationDefaults"]![key] is not null, $"a case names the situation key {key}, which situationDefaults does not");

        bool Flag(string key) => merged[key]!.GetValue<bool>();
        string rowName = merged["row"]!.ToString();
        var row = Enum.GetValues<SubjectMenuRules.Row>().Single(r => SubjectMenuRules.ContractName(r) == rowName);
        var blocked = merged["reviseBlocked"]!.AsArray()
            .Where(n => !heldDoors.Contains(n!.ToString()))
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
