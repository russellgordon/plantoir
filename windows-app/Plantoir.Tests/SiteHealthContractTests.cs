using System.Text.Json.Nodes;
using Plantoir.Core.Models;

namespace Plantoir.Tests;

/// <summary>
/// The site-health contract, run against this app's own parser.
///
/// Every case here is deserialised from
/// <c>contracts/shared-rules.json</c> -> <c>siteHealth</c>. Nothing is
/// retyped: a sentence written into a test file is the copy that keeps
/// passing after the product's words change, which is the whole reason the
/// contract exists.
/// </summary>
public class SiteHealthContractTests
{
    private static JsonNode SiteHealth =>
        ContractLoader.LoadJson("shared-rules.json")["siteHealth"]!;

    /// <summary>The marker this app looks for is the one the build prints.</summary>
    [Fact]
    public void Marker_MatchesContract()
    {
        string prefix = SiteHealth["marker"]!["prefix"]!.ToString();
        Assert.Equal(SiteHealthFinding.Marker, prefix);
    }

    public static TheoryData<string> MarkerExamples()
    {
        var data = new TheoryData<string>();
        foreach (var example in SiteHealth["marker"]!["examples"]!.AsArray())
            data.Add(example!.ToString());
        return data;
    }

    /// <summary>
    /// The contract's own example lines parse, carrying every field. These are
    /// real lines copied from a build, so a parser that passes here handles
    /// what the launcher actually emits.
    /// </summary>
    [Theory]
    [MemberData(nameof(MarkerExamples))]
    public void ContractExampleLines_Parse(string line)
    {
        var finding = SiteHealthFinding.Parse(line);
        Assert.NotNull(finding);
        Assert.NotEmpty(finding!.Name);
        Assert.NotEmpty(finding.Sentence);
        Assert.NotEmpty(finding.Detail);
        Assert.NotEmpty(finding.Course);
        Assert.True(finding.Section > 0);
    }

    public static TheoryData<string, bool> ContractChecks()
    {
        var data = new TheoryData<string, bool>();
        foreach (var check in SiteHealth["checks"]!.AsArray())
            data.Add(check!["name"]!.ToString(), check["fixable"]!.GetValue<bool>());
        return data;
    }

    /// <summary>
    /// Every check in the contract survives a round trip through the parser
    /// with its own sentence and detail intact -- including
    /// <c>noGradedFolders</c>, which is the check this piece added. A check
    /// added to the contract on either platform arrives here as a new case
    /// without anybody editing this file.
    /// </summary>
    [Theory]
    [MemberData(nameof(ContractChecks))]
    public void EveryContractCheck_SurvivesTheLine(string name, bool fixable)
    {
        var check = SiteHealth["checks"]!.AsArray()
            .First(c => c!["name"]!.ToString() == name)!;
        string sentence = check["sentence"]!.ToString()
            .Replace("{course}", "ICS3U").Replace("{section}", "1");
        string detail = check["detail"]!.ToString();

        var payload = new JsonObject
        {
            ["name"] = name,
            ["sentence"] = sentence,
            ["detail"] = detail,
            ["fixable"] = fixable,
            ["course"] = "ICS3U",
            ["section"] = 1,
        };

        var finding = SiteHealthFinding.Parse($"{SiteHealthFinding.Marker} {payload.ToJsonString()}");

        Assert.NotNull(finding);
        Assert.Equal(name, finding!.Name);
        Assert.Equal(sentence, finding.Sentence);
        Assert.Equal(detail, finding.Detail);
        Assert.Equal(fixable, finding.Fixable);
        Assert.Equal("ICS3U", finding.Course);
        Assert.Equal(1, finding.Section);
    }

    /// <summary>
    /// A Fix button is offered for exactly the checks the contract says it may
    /// be offered for -- decided from the NAME, not from the fixable flag.
    /// </summary>
    [Theory]
    [MemberData(nameof(ContractChecks))]
    public void RepairIsOfferedForExactlyTheContractsChecks(string name, bool fixable)
    {
        var repair = SiteHealth["repair"]!;
        var offered = repair["offered"]!["checks"]!.AsArray()
            .Select(c => c!.ToString()).ToHashSet();
        var neverOffered = repair["neverOffered"]!["checks"]!.AsArray()
            .Select(c => c!.ToString()).ToHashSet();

        Assert.True(offered.Contains(name) || neverOffered.Contains(name),
            $"The contract classifies every check as offered or never offered; {name} is in neither.");

        var finding = new SiteHealthFinding(name, "s", "d", fixable, "ICS3U", 1);
        Assert.Equal(offered.Contains(name), finding.CanBeRepaired);
    }

    /// <summary>
    /// <c>noGradedFolders</c> in particular is never repairable. Named on its
    /// own because it is the check this piece added, and because an existence
    /// fix would not assign marks to any page -- the Fix button would report
    /// success having changed nothing a teacher wanted changed.
    /// </summary>
    [Fact]
    public void NoGradedFolders_IsNeverOfferedARepair()
    {
        var neverOffered = SiteHealth["repair"]!["neverOffered"]!["checks"]!.AsArray()
            .Select(c => c!.ToString()).ToList();
        Assert.Contains("noGradedFolders", neverOffered);

        var finding = new SiteHealthFinding("noGradedFolders", "s", "d", false, "ICS3U", 1);
        Assert.False(finding.CanBeRepaired);
    }

    /// <summary>
    /// The code's repairable list holds nothing the contract has not approved.
    /// The theory above only visits names the contract knows; this catches a
    /// name added to the code and to neither list.
    /// </summary>
    [Fact]
    public void TheCodeOffersNoRepairTheContractDoesNot()
    {
        var repair = SiteHealth["repair"]!;
        var offered = repair["offered"]!["checks"]!.AsArray()
            .Select(c => c!.ToString()).ToHashSet();
        var neverOffered = repair["neverOffered"]!["checks"]!.AsArray()
            .Select(c => c!.ToString()).ToHashSet();

        Assert.Equal(offered, SiteHealthFinding.RepairableChecks.ToHashSet());

        // The other half, pinned against the CODE rather than against the
        // contract's own consistency: no name the contract forbids a repair
        // for may appear in this app's repairable list.
        Assert.Empty(neverOffered.Intersect(SiteHealthFinding.RepairableChecks));
    }

    /// <summary>
    /// The trail line carries the stable check NAME, never the product
    /// wording. <c>activityTrail.mustRecord</c> -> "folder problem found" says
    /// so, and the reason is that the sentence gets reworded while the name is
    /// what a person searching the trail can match against the contract.
    /// </summary>
    [Fact]
    public void TheTrailLineCarriesTheCheckNameAndNotTheWording()
    {
        var check = SiteHealth["checks"]!.AsArray()
            .First(c => c!["name"]!.ToString() == "noGradedFolders")!;
        string wording = check["sentence"]!.ToString();

        var finding = new SiteHealthFinding("noGradedFolders", wording, "d", false, "ICS3U", 1);

        Assert.Contains("noGradedFolders", finding.TrailSentence);
        Assert.DoesNotContain(wording, finding.TrailSentence);
    }

    // ---- Parsing the shape the launcher actually produces ---------------

    [Fact]
    public void OrdinaryBuildOutputIsNotAFinding()
    {
        Assert.Null(SiteHealthFinding.Parse("Building ICS3U Section 1..."));
        Assert.Null(SiteHealthFinding.Parse(""));
        Assert.Null(SiteHealthFinding.Parse(null));
    }

    [Fact]
    public void AMalformedHealthLineIsIgnoredRatherThanThrowing()
    {
        Assert.Null(SiteHealthFinding.Parse($"{SiteHealthFinding.Marker} not json at all"));
        Assert.Null(SiteHealthFinding.Parse($"{SiteHealthFinding.Marker} {{}}"));
        Assert.Null(SiteHealthFinding.Parse(SiteHealthFinding.Marker));
    }

    [Fact]
    public void AFindingIsStillFoundWhenGluedToOtherOutput()
    {
        string line = "  ...done. " + SiteHealth["marker"]!["examples"]!.AsArray()[0]!.ToString();
        Assert.NotNull(SiteHealthFinding.Parse(line));
    }

    [Fact]
    public void TheSameProblemFromTwoBuildsIsReportedOnce()
    {
        string example = SiteHealth["marker"]!["examples"]!.AsArray()[0]!.ToString();
        string other = SiteHealth["marker"]!["examples"]!.AsArray()[1]!.ToString();

        // Expected names come from the same two lines, not from a literal:
        // the ORDER of the contract's examples carries no product meaning, and
        // a test that goes red when somebody reorders them is a test nobody
        // trusts.
        var expected = new[]
        {
            SiteHealthFinding.Parse(example)!.Name,
            SiteHealthFinding.Parse(other)!.Name,
        };
        Assert.NotEqual(expected[0], expected[1]);

        var findings = SiteHealthFinding.FindingsIn(new[]
        {
            "Building...", example, "Building again...", example, other,
        });

        Assert.Equal(2, findings.Count);
        Assert.Equal(expected, findings.Select(f => f.Name).ToArray());
    }

    [Fact]
    public void TheSameCheckInTwoSectionsIsTwoProblems()
    {
        string One(int section) =>
            $"{SiteHealthFinding.Marker} {{\"name\": \"sectionIndexMissing\", \"sentence\": \"s\", " +
            $"\"detail\": \"d\", \"fixable\": true, \"course\": \"ICS3U\", \"section\": {section}}}";

        var findings = SiteHealthFinding.FindingsIn(new[] { One(1), One(2), One(1) });

        Assert.Equal(2, findings.Count);
        Assert.Equal(new[] { 1, 2 }, findings.Select(f => f.Section).ToArray());
    }
}
