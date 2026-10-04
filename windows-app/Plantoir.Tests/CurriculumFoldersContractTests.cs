using System.Text.Json.Nodes;
using Newtonsoft.Json.Linq;
using Plantoir.Core.Models;

namespace Plantoir.Tests;

/// <summary>
/// One coverage map per declared curriculum folder (GitHub issue #345, the
/// mac's #128): <c>curriculumFoldersResolution</c>,
/// <c>curriculumFolderProtection</c>, <c>curriculumFoldersOffer</c>,
/// <c>renameFolder.materialisesOnRename.curriculumFoldersCases</c> and
/// <c>curriculumRules.coveragePageTitles</c>, each against the Core function
/// the app calls.
/// </summary>
public class CurriculumFoldersContractTests
{
    private static JsonNode Rules => ContractLoader.LoadJson("shared-rules.json");
    private static JsonNode SpecialNamesNode => Rules["specialNames"]!;
    private static List<string> Strings(JsonNode? node) =>
        node is JsonArray array ? array.Select(n => n!.ToString()).ToList() : new List<string>();

    private static JToken? Token(JsonNode? node) => node is null ? null : JToken.Parse(node.ToJsonString());

    [Fact]
    public void EveryResolutionCaseMapsResolvesAndTitlesAsTheContractSays()
    {
        var cases = SpecialNamesNode["curriculumFoldersResolution"]!["cases"]!.AsArray();
        Assert.True(cases.Count >= 16, $"curriculumFoldersResolution lost cases: {cases.Count} (16 when this was written)");

        var failures = new List<string>();
        foreach (var c in cases)
        {
            var declared = CurriculumFolderRule.Declared(Token(c!["curriculumFolders"]), Token(c["curriculumFolder"]));
            var result = CurriculumFolderRule.Resolve(declared, Strings(c["folders"]), Strings(c["withPages"]),
                c["withLetterFirstPages"] is JsonArray letterFirst ? Strings(letterFirst) : null);
            void Same(string what, IReadOnlyList<string> actual)
            {
                var expected = Strings(c![what]);
                if (!expected.SequenceEqual(actual))
                    failures.Add($"{c["name"]}: {what} expected [{string.Join(", ", expected)}], got [{string.Join(", ", actual)}]");
            }
            Same("mapped", result.Mapped);
            Same("resolved", result.Resolved);
            Same("titles", result.Titles);
        }
        Assert.True(failures.Count == 0, string.Join("\n", failures));
    }

    [Fact]
    public void TheSingularResolutionIsGoneFromTheContract() =>
        Assert.Null(SpecialNamesNode["curriculumFolderResolution"]);

    [Fact]
    public void EveryCoverageTitleCaseIsTheContracts()
    {
        var cases = Rules["curriculumRules"]!["coveragePageTitles"]!["cases"]!.AsArray();
        Assert.True(cases.Count >= 7);
        foreach (var c in cases)
            Assert.Equal(Strings(c!["titles"]),
                CurriculumRules.CoveragePageTitles(Strings(c["folders"]), c["primary"]?.ToString()));
    }

    [Fact]
    public void EveryProtectionCaseIsDecidedAsTheContractSays()
    {
        var cases = SpecialNamesNode["curriculumFolderProtection"]!["cases"]!.AsArray();
        Assert.True(cases.Count >= 11, $"curriculumFolderProtection lost cases: {cases.Count} (11 when this was written)");

        var failures = new List<string>();
        foreach (var c in cases)
        {
            bool wizard = c!["surface"]!.ToString() == "wizard";
            var resolved = Strings(c["resolved"]);
            var context = new ProtectionContext(
                InWizard: wizard,
                CurriculumCoverageEnabled: c["coverageOn"]!.GetValue<bool>(),
                CurriculumPagesEnabled: c["pagesOn"]!.GetValue<bool>(),
                Jurisdiction: SpecialNames.DefaultJurisdiction,
                ResolvedCurriculumFolder: resolved.FirstOrDefault(),
                GradedFolders: Array.Empty<string>(),
                PerSectionFolders: new[] { "All Classes", "Labs" },
                ResolvedCurriculumFolders: resolved,
                DeclaredPayloadFolder: c["declaredPayloadFolder"]?.ToString());
            var protection = ItemProtectionRule.CurriculumFolderProtection(c["folder"]!.ToString(), context);

            string kind = c["kind"]!.ToString();
            string? sentence = c["sentence"]?.ToString();
            string? expectedText = sentence switch
            {
                "curriculumFolderBlockedByCoverageSetting" => SpecialNames.CurriculumFolderBlockedByCoverageSetting,
                "curriculumFolderBlockedByCoverageMap" => SpecialNames.CurriculumFolderBlockedByCoverageMap,
                "curriculumFolderBlockedByCurriculumPages" => SpecialNames.CurriculumFolderBlockedByCurriculumPages(SpecialNames.DefaultJurisdiction),
                "removeCurriculumFolderWithItsMapConfirmation" => SpecialNames.RemoveCurriculumFolderWithItsMapMessage,
                "removeCurriculumFolderConfirmation" => SpecialNames.RemoveCurriculumFolderMessage,
                _ => null,
            };
            string actualKind = protection is null ? "notACurriculumFolder"
                : protection.IsBlocked ? "blocked" : protection.AsksFirst ? "consequential" : "ordinary";
            string? actualText = protection is null ? null : protection.IsBlocked ? protection.Reason : protection.Message;
            if (actualKind != kind || actualText != expectedText)
                failures.Add($"{c["name"]}: expected {kind} ({sentence}), got {actualKind} (\"{actualText}\")");
        }
        Assert.True(failures.Count == 0, string.Join("\n", failures));
    }

    [Fact]
    public void TheWithItsMapSentenceIsTheContracts()
    {
        var sentence = SpecialNamesNode["removeCurriculumFolderWithItsMapConfirmation"]!;
        Assert.Equal(sentence["title"]!.ToString().Replace("{name}", "X"), SpecialNames.RemoveCurriculumFolderWithItsMapTitle("X"));
        Assert.Equal(sentence["message"]!.ToString(), SpecialNames.RemoveCurriculumFolderWithItsMapMessage);
    }

    [Fact]
    public void EveryOfferCaseOffersTicksAndWritesAsTheContractSays()
    {
        var offer = SpecialNamesNode["curriculumFoldersOffer"]!;
        Assert.Equal(offer["label"]!.ToString(), CurriculumFoldersOffer.Label);
        Assert.Equal(offer["caption"]!.ToString(), CurriculumFoldersOffer.Caption);
        Assert.Equal(offer["lastStaysTicked"]!.ToString(), CurriculumFoldersOffer.LastStaysTicked);

        var cases = offer["cases"]!.AsArray();
        Assert.True(cases.Count >= 10, $"curriculumFoldersOffer lost cases: {cases.Count} (10 when this was written)");
        var failures = new List<string>();
        foreach (var c in cases)
        {
            var folders = Strings(c!["folders"]);
            var declared = Strings(c["declared"]);
            var mapped = Strings(c["mapped"]);
            var ticked = CurriculumFoldersOffer.Ticked(folders, declared, mapped);
            if (c["offered"] is JsonArray offered && !Strings(offered).SequenceEqual(CurriculumFoldersOffer.Offered(folders, declared)))
                failures.Add($"{c["name"]}: offered [{string.Join(", ", CurriculumFoldersOffer.Offered(folders, declared))}]");
            if (c["ticked"] is JsonArray tickedExpected && !Strings(tickedExpected).SequenceEqual(ticked))
                failures.Add($"{c["name"]}: ticked [{string.Join(", ", ticked)}]");
            if (c["tick"] is JsonNode tick)
            {
                var writes = CurriculumFoldersOffer.Tick(ticked, tick.ToString());
                if (!Strings(c["writes"]).SequenceEqual(writes)) failures.Add($"{c["name"]}: tick wrote [{string.Join(", ", writes)}]");
            }
            if (c["untick"] is JsonNode untick)
            {
                var writes = CurriculumFoldersOffer.Untick(ticked, untick.ToString());
                bool refused = c["writes"] is null;
                if (refused ? writes is not null : writes is null || !Strings(c["writes"]).SequenceEqual(writes))
                    failures.Add($"{c["name"]}: untick wrote {(writes is null ? "nothing" : "[" + string.Join(", ", writes) + "]")}");
            }
        }
        Assert.True(failures.Count == 0, string.Join("\n", failures));
    }

    [Fact]
    public void EveryRenameCaseWritesTheCurriculumKeysAsTheContractSays()
    {
        var cases = SpecialNamesNode["renameFolder"]!["materialisesOnRename"]!["curriculumFoldersCases"]!.AsArray();
        Assert.True(cases.Count >= 5, $"curriculumFoldersCases lost cases: {cases.Count} (5 when this was written)");
        Assert.Equal(new[] { "class_folder", "curriculum_folders" },
            Strings(SpecialNamesNode["renameFolder"]!["materialisesOnRename"]!["keys"]));

        var failures = new List<string>();
        foreach (var c in cases)
        {
            var before = JObject.Parse(c!["before"]!.ToJsonString());
            before["per_section_folders"] = new JArray("All Classes");
            var scope = c["scope"]!.ToString() == "shared" ? FolderScope.Shared : FolderScope.PerSection;
            var after = SpecialFolderRenamer.Renaming(before, c["old"]!.ToString(), c["new"]!.ToString(), scope,
                Strings(c["withPages"]));
            foreach (var (key, expected) in c["after"]!.AsObject())
            {
                string expectedJson = expected is null ? "null" : expected.ToJsonString();
                string actualJson = after[key] is null || after[key]!.Type == JTokenType.Null
                    ? "null" : after[key]!.ToString(Newtonsoft.Json.Formatting.None);
                if (JToken.Parse(expectedJson).ToString(Newtonsoft.Json.Formatting.None) != actualJson)
                    failures.Add($"{c["name"]}: {key} expected {expectedJson}, got {actualJson}");
            }
        }
        Assert.True(failures.Count == 0, string.Join("\n", failures));
    }

    /// <summary>The configuration writes BOTH keys, the legacy one naming the primary; an empty list removes both.</summary>
    [Fact]
    public void TheListAndTheLegacyKeyAreWrittenTogether()
    {
        var config = CourseConfiguration.FromDictionary(new JObject { ["curriculum_folder"] = "Curriculum" });
        Assert.Equal(new[] { "Curriculum" }, config.CurriculumFolders);
        config.CurriculumFolders = new List<string> { "Ontario Curriculum", "College Board Curriculum" };
        Assert.Equal("Ontario Curriculum", config.Values["curriculum_folder"]!.ToString());
        Assert.Equal(2, ((JArray)config.Values["curriculum_folders"]!).Count);
        config.CurriculumFolders = new List<string>();
        Assert.Null(config.Values["curriculum_folders"]);
        Assert.Null(config.Values["curriculum_folder"]);
    }
}
