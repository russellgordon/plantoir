using System.Text.Json.Nodes;
using Plantoir.Core.Assist;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// shared-rules.json → linksChecklist.followingARow (#399 / mac #385) and
/// .comingWithAClass (#405 / mac #398): the PURE cases, through the one toggle
/// function the sheet's checkbox calls.
/// </summary>
public class LinksChecklistGateContractTests
{
    private static JsonNode Checklist => ContractLoader.LoadJson("shared-rules.json")!["linksChecklist"]!;

    public static IEnumerable<object[]> Following() =>
        ContractLoader.LoadJson("shared-rules.json")!["linksChecklist"]!["followingARow"]!["cases"]!.AsArray()
            .Select(c => new object[] { "followingARow", c!["name"]!.ToString() });

    public static IEnumerable<object[]> Coming() =>
        ContractLoader.LoadJson("shared-rules.json")!["linksChecklist"]!["comingWithAClass"]!["cases"]!.AsArray()
            .Select(c => new object[] { "comingWithAClass", c!["name"]!.ToString() });

    [Theory]
    [MemberData(nameof(Following))]
    [MemberData(nameof(Coming))]
    public void Case_MatchesContract(string list, string name)
    {
        var c = Checklist[list]!["cases"]!.AsArray().First(x => x!["name"]!.ToString() == name)!;
        var rows = c["rows"]!.AsArray().Select(r => new LinksChecklistRow(
            r!["place"]!.ToString(), r["group"]!.ToString(), r["ticked"]!.GetValue<bool>(),
            r["dependsOn"]!.AsArray().Select(d => d!.ToString()).ToList())).ToList();
        var brings = (c["brings"] as JsonObject ?? new JsonObject())
            .ToDictionary(p => p.Key, p => (IReadOnlyList<string>)p.Value!.AsArray().Select(x => x!.ToString()).ToList());
        var ticks = LinksChecklist.StartingTicks(rows);
        foreach (var step in c["steps"]?.AsArray() ?? new JsonArray())
        {
            if (step!["tick"] is { } on) LinksChecklist.Toggle(rows, ticks, brings, on.ToString(), true);
            else LinksChecklist.Toggle(rows, ticks, brings, step["untick"]!.ToString(), false);
        }

        var going = LinksChecklist.Going(rows, ticks);
        var coming = LinksChecklist.ComingWith(rows, ticks, brings);
        var locked = LinksChecklist.Locked(rows, going, coming);
        Assert.Equal(Set(c["expectGoing"]), going.Order().ToList());
        Assert.Equal(Set(c["expectLocked"]), locked.Order().ToList());
        if (c["expectComesWith"] is JsonObject expected)
            Assert.Equal(expected.Select(p => $"{p.Key}:{p.Value}").Order(), coming.Select(p => $"{p.Key}:{p.Value}").Order());
        if (c["expectShownTicked"] is { } shown)
            Assert.Equal(Set(shown), LinksChecklist.ShownTicked(going, coming).Order().ToList());
        if (c["expectShown"] is JsonArray order)
            Assert.Equal(order.Select(p => $"{p![0]}@{p[1]}"),
                         LinksChecklist.ShownOrder(rows).Select(x => $"{x.Place}@{x.Depth}"));
    }

    private static List<string> Set(JsonNode? node) =>
        (node as JsonArray ?? new JsonArray()).Select(x => x!.ToString()).Order().ToList();
}
