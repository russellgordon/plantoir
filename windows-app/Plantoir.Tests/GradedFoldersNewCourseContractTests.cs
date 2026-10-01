using System.Text.Json.Nodes;
using Newtonsoft.Json.Linq;
using Plantoir.Core.Catalogs;

namespace Plantoir.Tests;

/// <summary>
/// <c>shared-rules.json</c> → <c>gradedFolders.newCourse</c> (#317, the mac's
/// #292): a new course taking ready-made pages is written the MANIFEST's marks
/// pool, read the way the command line's <c>graded_folders_for</c> reads it.
///
/// <para>Runs against <see cref="ExampleContentCatalog.MarksPool(JObject)"/>,
/// the Core function <c>NewCourseDialog.BuildConfiguration</c> writes from —
/// a view cannot be pinned, so this is the honest limit: it proves the pool the
/// dialog is handed, not that the dialog's branch is taken. Every
/// <c>manifestCases</c> entry runs; every <c>cases</c> entry that applies to
/// Windows and takes example content runs against the real payload. The one
/// that needs a feature this app does not have yet (a club, #274) is held open by name in
/// <see cref="NamedGapLedger"/>.</para>
/// </summary>
public class GradedFoldersNewCourseContractTests
{
    private static JsonNode NewCourse =>
        ContractLoader.LoadJson("shared-rules.json")["gradedFolders"]!["newCourse"]!;

    private static string ExampleContentRoot
    {
        get
        {
            var dir = new DirectoryInfo(AppContext.BaseDirectory);
            for (int i = 0; i < 10 && dir is not null; i++, dir = dir.Parent)
            {
                string candidate = Path.Combine(dir.FullName, "support", "example_content");
                if (Directory.Exists(candidate)) return candidate;
            }
            throw new DirectoryNotFoundException("support/example_content was not found above the test assembly.");
        }
    }

    [Fact]
    public void EveryManifestCaseGivesTheCommandLinesPool()
    {
        var cases = NewCourse["manifestCases"]!.AsArray();
        Assert.True(cases.Count >= 8, $"manifestCases lost cases: {cases.Count}");

        var failures = cases
            .Select(c => (name: c!["name"]!.ToString(),
                          expect: c["expect"]!.AsArray().Select(n => n!.ToString()).ToList(),
                          actual: ExampleContentCatalog.MarksPool(JObject.Parse(c["manifest"]!.ToJsonString())).ToList()))
            .Where(result => !result.expect.SequenceEqual(result.actual))
            .Select(result => $"{result.name}: expected [{string.Join(", ", result.expect)}], got [{string.Join(", ", result.actual)}]")
            .ToList();
        Assert.True(failures.Count == 0, string.Join("\n", failures));
    }

    [Fact]
    public void EveryCaseThatAppliesHereIsWrittenTheContractsPool()
    {
        var cases = NewCourse["cases"]!.AsArray()
            .Where(c => c!["appliesOn"] is null || c["appliesOn"]!.AsArray().Any(p => p!.ToString() == "windows"))
            .ToList();
        var names = cases.Select(c => c!["name"]!.ToString()).ToList();

        var results = cases.Select(c => (name: c!["name"]!.ToString(), problems: Run(c))).ToList();
        var passing = results.Where(r => r.problems.Count == 0).Select(r => r.name);
        var deferred = NamedGapLedger.GapsIn(NamedGapLedger.GradedFoldersNewCourseCases, names, passing);

        var unexplained = results
            .Where(r => r.problems.Count > 0 && !deferred.Contains(r.name))
            .SelectMany(r => r.problems.Select(problem => $"{r.name}: {problem}"))
            .ToList();
        Assert.True(unexplained.Count == 0, string.Join("\n", unexplained));
    }

    /// <summary>What went wrong for one case, or nothing. A case this runner cannot express yet fails, and is ledgered.</summary>
    private static List<string> Run(JsonNode c)
    {
        bool taken = c["exampleContent"]?.ToString() == "taken";
        bool club = c["club"]?.GetValue<bool>() ?? false;
        if (club)
            return new List<string> { "not runnable here yet: this app has no clubs" };
        bool startsFromSkeleton = c["startsFromSkeleton"]?.GetValue<bool>() ?? true;
        List<string>? wizardPool = c["wizardGradedFolders"]?.AsArray().Select(n => n!.ToString()).ToList();

        var codes = c["everyPayload"]?.GetValue<bool>() == true
            ? Directory.GetDirectories(ExampleContentRoot)
                .Where(dir => File.Exists(Path.Combine(dir, "manifest.json")))
                .Select(Path.GetFileName)
                .Select(code => code!)
                .ToList()
            : new List<string> { c["courseCode"]!.ToString() };
        Assert.True(codes.Count > 0, "no payloads were found");

        var problems = new List<string>();
        foreach (string code in codes)
        {
            // Through the function NewCourseDialog.BuildConfiguration writes
            // from (#250), so a DECLINED payload is run too, not only a taken one.
            var keys = NewCourseAnswers.Decide(ExampleContentRoot,
                Path.Combine(ContractLoader.RepositoryRoot, "support", "skeletons"),
                new NewCourseAnswers.Choices(code, taken, startsFromSkeleton, true,
                    WizardStructure.Defaults(false) with { GradedFolders = wizardPool })).Keys;
            if (keys["graded_folders"] is not JArray written) { problems.Add($"{code}: no graded_folders would be written"); continue; }
            var pool = written.Select(t => t.ToString()).ToList();

            List<string> expect;
            if (c["expect"] is JsonValue symbol && symbol.ToString() == "manifest")
            {
                var manifest = JObject.Parse(File.ReadAllText(ExampleContentCatalog.ManifestPath(ExampleContentRoot, code)!));
                if (manifest["graded_folders"] is not JArray declared)
                {
                    problems.Add($"{code}: the manifest declares no graded_folders, which the case requires");
                    continue;
                }
                expect = declared.Select(name => name.ToString()).ToList();
            }
            else
            {
                expect = c["expect"]!.AsArray().Select(name => name!.ToString()).ToList();
            }

            if (!expect.SequenceEqual(pool))
                problems.Add($"{code}: expected [{string.Join(", ", expect)}], got [{string.Join(", ", pool)}]");
        }
        return problems;
    }
}
