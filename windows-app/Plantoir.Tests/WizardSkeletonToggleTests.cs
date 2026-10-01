using System.Text.Json.Nodes;
using Plantoir.Core.Catalogs;

namespace Plantoir.Tests;

/// <summary>
/// <c>shared-rules.json</c> → <c>wizard.skeletonToggle</c>: what the structure
/// editor holds after the skeleton toggle (and the example-content toggle) is
/// turned, case by case, through <see cref="WizardStructure"/> — the pure seam
/// <c>NewCourseDialog</c> calls (GitHub issue #169).
///
/// <para>What this does NOT prove, said as the contract says it: the runner
/// implements the <c>typeAnotherCode</c> guard itself, so the case pins the
/// RULE. <see cref="TheDialogsAdoptEntryPointReadsTheToggle"/> is this side's
/// own check against the real entry point.</para>
/// </summary>
public class WizardSkeletonToggleTests
{
    private static JsonNode Toggle =>
        ContractLoader.LoadJson("shared-rules.json")["wizard"]!["skeletonToggle"]!;

    internal static string SkeletonsRoot => Path.Combine(ContractLoader.RepositoryRoot, "support", "skeletons");
    internal static string ExampleContentRoot => Path.Combine(ContractLoader.RepositoryRoot, "support", "example_content");

    private static List<string> Strings(JsonNode? node) =>
        node!.AsArray().Select(n => n!.ToString()).ToList();

    [Fact]
    public void TheVocabularyIsThisAppsOwnDefaults()
    {
        var lists = Toggle["lists"]!;
        Assert.Equal(Strings(lists["factory"]!["sharedFolders"]), WizardDefaults.SharedFolders);
        Assert.Equal(Strings(lists["factory"]!["sharedFiles"]), WizardDefaults.SharedFiles);
        Assert.Equal(Strings(lists["factory"]!["perSectionFolders"]), WizardDefaults.PerSectionFolders);
        Assert.Equal(Strings(lists["factory"]!["perSectionFiles"]), WizardDefaults.PerSectionFiles);
        Assert.Equal(Strings(lists["lcs"]!["sharedFolders"]), WizardDefaults.LcsSharedFolders);
        Assert.Equal(Strings(lists["lcs"]!["sharedFiles"]), WizardDefaults.LcsSharedFiles);
    }

    [Fact]
    public void EveryCaseLeavesTheEditorAsTheContractSays()
    {
        var cases = Toggle["cases"]!.AsArray();
        Assert.True(cases.Count >= 17, $"wizard.skeletonToggle lost cases: {cases.Count} (17 when this was written)");

        var failures = cases.SelectMany(c => Run(c!)).ToList();
        Assert.True(failures.Count == 0, string.Join("\n", failures));
    }

    /// <summary>
    /// The one thing a case cannot reach: the dialog's own adopt entry point
    /// must read the toggle, or a teacher who declined the skeleton and then
    /// fixed a typo in the code is handed it back.
    /// </summary>
    [Fact]
    public void TheDialogsAdoptEntryPointReadsTheToggle()
    {
        string source = File.ReadAllText(Path.Combine(
            ContractLoader.RepositoryRoot, "windows-app", "Plantoir", "Views", "NewCourseDialog.cs"));
        int start = source.IndexOf("private void AdoptSkeletonStructure()", StringComparison.Ordinal);
        Assert.True(start >= 0, "AdoptSkeletonStructure was not found");
        string body = source.Substring(start, source.IndexOf("StructureToAdopt", start, StringComparison.Ordinal) - start);
        Assert.Contains("if (!_startsFromSkeleton) return;", body);
        Assert.Contains("WizardStructure.RestoringDefaults(", source);
        Assert.Contains("WizardStructure.Adopting(", source);
    }

    /// <summary>The whole case, played from its fixture; every problem found, as a sentence.</summary>
    internal static List<string> Run(JsonNode c)
    {
        string name = c["name"]!.ToString();
        var given = c["given"]!;
        string code = given["courseCode"]?.ToString() ?? Toggle["courseCode"]!.ToString();
        string otherCode = Toggle["otherCourseCode"]!.ToString();
        bool lcs = given["usesLCSTerminology"]!.GetValue<bool>();
        // ABSENT MEANS TRUE: where a new wizard opens.
        bool taking = given["takesExampleContent"]?.GetValue<bool>() ?? true;
        bool toggleOn = true;

        var family = SkeletonCatalog.GetFamily(SkeletonsRoot, code);
        if (family is null) return new List<string> { $"{name}: no skeleton family for {code}" };

        IReadOnlyList<string>? Resolve(JsonNode? value, string slot)
        {
            if (value is JsonArray literal) return literal.Select(n => n!.ToString()).ToList();
            string symbol = value!.ToString();
            IReadOnlyList<string> SkeletonSlot() => slot switch
            {
                "sharedFolders" => family.SharedFolders,
                "sharedFiles" => family.SharedFiles,
                "perSectionFolders" => family.PerSectionFolders,
                "perSectionFiles" => family.PerSectionFiles,
                _ => SkeletonCatalog.AdoptedGradedFolders(family),
            };
            IReadOnlyList<string> FactorySlot(bool useLcs) => slot switch
            {
                "sharedFolders" => useLcs ? WizardDefaults.LcsSharedFolders : WizardDefaults.SharedFolders,
                "sharedFiles" => useLcs ? WizardDefaults.LcsSharedFiles : WizardDefaults.SharedFiles,
                "perSectionFolders" => WizardDefaults.PerSectionFolders,
                "perSectionFiles" => WizardDefaults.PerSectionFiles,
                _ => throw new InvalidOperationException($"{symbol} has no {slot} slot"),
            };
            return symbol switch
            {
                "skeleton" => SkeletonSlot(),
                "skeletonReversed" => SkeletonSlot().Reverse().ToList(),
                "factory" => FactorySlot(false),
                "lcs" => FactorySlot(true),
                "lcsFlippedFromSkeleton" => WizardDefaults.SwitchingFactoryItems(
                    SkeletonSlot(), FactorySlot(true), FactorySlot(false)),
                _ => throw new InvalidOperationException($"unknown symbol {symbol}"),
            };
        }

        var givenLists = given["lists"]!;
        var lists = new WizardStructure.Lists(
            Resolve(givenLists["sharedFolders"], "sharedFolders")!,
            Resolve(givenLists["sharedFiles"], "sharedFiles")!,
            Resolve(givenLists["perSectionFolders"], "perSectionFolders")!,
            Resolve(givenLists["perSectionFiles"], "perSectionFiles")!,
            Resolve(givenLists["gradedFolders"], "gradedFolders"));
        WizardStructure.Lists? snapshot = given["hasSnapshot"]!.GetValue<bool>()
            ? WizardStructure.Adopting(family)
            : null;

        void Adopt(string forCode)
        {
            if (!toggleOn) return;
            var adopted = SkeletonCatalog.StructureToAdopt(ExampleContentRoot, SkeletonsRoot, forCode, taking,
                lists.SharedFolders, WizardDefaults.SharedFolders, WizardDefaults.LcsSharedFolders);
            if (adopted is null) return;
            snapshot = WizardStructure.Adopting(adopted);
            lists = snapshot;
        }

        void Restore()
        {
            lists = WizardStructure.RestoringDefaults(lists, snapshot, lcs);
            snapshot = null;
        }

        foreach (string step in Strings(c["steps"]))
        {
            switch (step)
            {
                case "turnOn": toggleOn = true; Adopt(code); break;
                case "turnOff": toggleOn = false; Restore(); break;
                case "typeAnotherCode": code = otherCode; Adopt(code); break;
                case "declineExampleContent": taking = false; Adopt(code); break;
                case "takeExampleContent": taking = true; Restore(); break;
                default: return new List<string> { $"{name}: unknown step {step}" };
            }
        }

        var problems = new List<string>();
        var expect = c["expect"]!;
        void Compare(string slot, IReadOnlyList<string> actual)
        {
            var expected = Resolve(expect[slot], slot)!;
            if (!expected.SequenceEqual(actual))
                problems.Add($"{name}: {slot} expected [{string.Join(", ", expected)}], got [{string.Join(", ", actual)}]");
        }
        Compare("sharedFolders", lists.SharedFolders);
        Compare("sharedFiles", lists.SharedFiles);
        Compare("perSectionFolders", lists.PerSectionFolders);
        Compare("perSectionFiles", lists.PerSectionFiles);
        Compare("gradedFolders", WizardStructure.EffectiveGradedFolders(lists));

        if (c["expectSavedUseSkeleton"] is JsonNode saved)
        {
            bool written = SkeletonCatalog.HasSkeleton(ExampleContentRoot, SkeletonsRoot, code, taking) && toggleOn;
            if (written != saved.GetValue<bool>())
                problems.Add($"{name}: use_skeleton expected {saved}, would be written {written}");
        }
        return problems;
    }
}
