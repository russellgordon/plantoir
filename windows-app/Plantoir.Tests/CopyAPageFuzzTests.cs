using System.Diagnostics;
using System.Text;
using System.Text.Json.Nodes;
using Plantoir.Core.Models;
using Xunit;
using Xunit.Abstractions;

namespace Plantoir.Tests;

/// <summary>
/// The guard in <see cref="CopyPageFrontmatter"/> is a hand-written language;
/// the build reads with PyYAML. These tests are the evidence that what the
/// guard CERTIFIES the build HIDES — fuzz-backed, not proven (#247, bundle-6
/// ruling 6, review M3):
/// <list type="bullet">
/// <item>every builderAgreement case the contract calls agreeing is hidden by the real build;</item>
/// <item>N generated sources (fixed seed; <c>PLANTOIR_FUZZ_N</c> to go bigger), composed and
/// certified here, are each hidden in sections 1–4 by the real build, ZERO exceptions;</item>
/// <item>every page Plantoir ships (example content and skeletons) is certified — ZERO false refusals.</item>
/// </list>
/// </summary>
public class CopyAPageFuzzTests
{
    private readonly ITestOutputHelper _output;

    public CopyAPageFuzzTests(ITestOutputHelper output) => _output = output;

    [Fact]
    public void EveryAgreeingContractCaseIsHiddenByTheRealBuild()
    {
        var cases = ContractLoader.LoadJson("shared-rules.json")["copyingAPageBetweenCourses"]!["builderAgreement"]!["cases"]!
            .AsArray().Where(c => c!["builderAgrees"]!.GetValue<bool>()).ToList();
        var answers = BuildFrontmatterOracle.Ask(cases.Select(c => c!["text"]!.ToString()).ToList());
        for (int i = 0; i < cases.Count; i++)
            Assert.True(answers[i].HiddenEverywhere, $"{cases[i]!["name"]}: the build did not hide it ({answers[i].Problem})");
        Assert.True(cases.Count >= 10);
    }

    [Fact]
    public void WhatTheGuardCertifiesTheBuildHides()
    {
        int n = int.TryParse(Environment.GetEnvironmentVariable("PLANTOIR_FUZZ_N"), out int asked) ? asked : 5000;
        var random = new Random(20260930);
        var clock = Stopwatch.StartNew();
        var certified = new List<(string Source, string Composed)>();
        int refused = 0;
        for (int i = 0; i < n; i++)
        {
            string source = Generate(random);
            var sections = Enumerable.Range(1, 3).Where(_ => random.Next(2) == 0).DefaultIfEmpty(1).ToList();
            string? composed = CopyPageFrontmatter.Compose(source, sections);
            if (composed is not null && CopyPageFrontmatter.IsCertainlyHidden(composed, sections)) certified.Add((source, composed));
            else refused++;
        }
        long composeMs = clock.ElapsedMilliseconds;
        clock.Restart();
        var answers = new List<BuildFrontmatterOracle.Answer>();
        foreach (var chunk in certified.Chunk(20_000))
            answers.AddRange(BuildFrontmatterOracle.Ask(chunk.Select(c => c.Composed).ToList()));
        long oracleMs = clock.ElapsedMilliseconds;

        var published = certified.Zip(answers).Where(pair => !pair.Second.HiddenEverywhere).ToList();
        if (Environment.GetEnvironmentVariable("PLANTOIR_FUZZ_DUMP") is { Length: > 0 } dump)
            File.WriteAllText(dump, string.Join("\n====\n", published.Select(p => $"{p.First.Composed}\n-> {p.Second.Problem} {string.Join(",", p.Second.HiddenIn)}")));
        _output.WriteLine($"fuzz: {n} sources, {certified.Count} certified, {refused} refused, " +
                          $"{published.Count} certified-and-not-hidden; compose {composeMs} ms, build oracle {oracleMs} ms");
        Assert.True(certified.Count >= n / 10, $"only {certified.Count} of {n} certified - the generator has stopped exercising the guard");
        Assert.True(refused >= n / 10, $"only {refused} of {n} refused - the generator has stopped exercising the refusals");
        Assert.True(published.Count == 0,
            $"{published.Count} pages certified hidden here were NOT hidden by the build. First:\n" +
            string.Join("\n====\n", published.Take(3).Select(p => $"{p.First.Composed}\n-> {p.Second.Problem} {string.Join(",", p.Second.HiddenIn)}")));
    }

    [Fact]
    public void EveryPagePlantoirShipsIsCertified()
    {
        string root = ContractLoader.RepositoryRoot;
        var pages = new[] { "example_content", "skeletons" }
            .SelectMany(folder => Directory.EnumerateFiles(Path.Combine(root, "support", folder), "*.md", SearchOption.AllDirectories))
            .ToList();
        var refusedPages = pages.Where(page =>
        {
            string text = File.ReadAllText(page);
            string? composed = CopyPageFrontmatter.Compose(text, new[] { 1, 2 });
            return composed is null || !CopyPageFrontmatter.IsCertainlyHidden(composed, new[] { 1, 2 });
        }).ToList();
        _output.WriteLine($"shipped: {pages.Count} pages, {refusedPages.Count} refused");
        Assert.True(pages.Count >= 10_000, $"only {pages.Count} shipped pages found");
        Assert.True(refusedPages.Count == 0, $"{refusedPages.Count} false refusals, first: " +
            string.Join(", ", refusedPages.Take(5).Select(p => Path.GetRelativePath(root, p))));
    }

    // ---- The generator --------------------------------------------------------

    private static readonly string[] Keys =
    {
        "title", "tags", "created", "description", "enableToc", "aliases", "publish", "draft",
        "publishForSection1", "publishForSection2", "draftSection1", "createdSection1", "draftSectionTwo",
        "createdForSectionTwo", "yes", "on", "No", "null", "1st", "\"publish\"", "'draft'", "a b", "k\u00e9", "_x",
    };

    private static readonly string[] Values =
    {
        "Recursion", "false", "true", "TRUE", "False", "false true", "\"false\"", "'false'", "\"a\"b\"", "\"Pacific & Alpine\"",
        "'it''s'", "&a 1", "*a", "!tag x", "|", ">-", "[]", "[a, b]", "{a: 1}", "2025-09-01", "2025-09-93",
        "2026-02-29", "2026-02-29T07:00:00-04:00", "2026-02-29T07:00:00.000-0400", "2025-10-14 25:00:00", "a: b",
        "a #b", "a:", "%x", "@x", "`x", "0b_", "0x1F", "1_000", "1:30", ",comma", "\"unclosed", "a\u0301b", "a: \u0301b",
        "3rd Edition", "_underscore", "~", "a\u2028b", "a\u000bb", "a\tb", "x\u00a0y", "\u00e9t\u00e9", "Q&A", "50%", "a*b",
    };

    private static readonly string[] OddLines =
    {
        "  ---", "---", "----", "...", "%YAML 1.2", "- one", "  - one", "    - two", "  continued", "  about time: 10am",
        "   \t ", "\ttitle: X", "# note", "  # note", "", "  nested: 1", "title:A page", "key: |", "  ---", "  two",
        "publish:", "  false", "draft:", "  true", "-- -", "? complex", "<<: *a",
    };

    /// <summary>One source page: a settings block of ordinary and odd lines, sometimes with no block, a BOM, CRLF or a lone CR.</summary>
    private static string Generate(Random random)
    {
        var lines = new List<string>();
        int shape = random.Next(10);
        if (shape == 0) return "Just a body with --- in it\n---\nmore\n";
        string fence = random.Next(8) switch { 0 => "----", 1 => "---  ", 2 => "  ---", _ => "---" };
        if (random.Next(10) == 0) lines.Add("");
        lines.Add(fence);
        int count = random.Next(1, 9);
        string? listKey = null;
        for (int i = 0; i < count; i++)
        {
            int kind = random.Next(10);
            if (kind < 5)
            {
                string key = Keys[random.Next(Keys.Length)];
                string value = Values[random.Next(Values.Length)];
                lines.Add($"{key}: {value}");
                listKey = null;
            }
            else if (kind < 7)
            {
                string key = Keys[random.Next(Keys.Length)];
                lines.Add($"{key}:");
                int indent = random.Next(3) == 0 ? 4 : 2;
                for (int item = random.Next(0, 3); item > 0; item--)
                    lines.Add(new string(' ', random.Next(5) == 0 ? (indent == 2 ? 4 : 2) : indent) + "- " + Values[random.Next(Values.Length)]);
                listKey = key;
            }
            else
            {
                lines.Add(OddLines[random.Next(OddLines.Length)]);
            }
        }
        if (random.Next(12) != 0) lines.Add(random.Next(6) == 0 ? "  ---" : "---");
        lines.Add(random.Next(4) == 0 ? "Body\n---\nafter a rule" : "Body");
        string newline = random.Next(8) == 0 ? "\r\n" : "\n";
        var text = new StringBuilder(string.Join(newline, lines)).Append(newline);
        if (random.Next(25) == 0) text.Replace("\n", "\r", 0, Math.Min(text.Length, 20));   // a lone CR near the top
        if (random.Next(20) == 0) text.Insert(0, '\ufeff');
        _ = listKey;
        return text.ToString();
    }
}
