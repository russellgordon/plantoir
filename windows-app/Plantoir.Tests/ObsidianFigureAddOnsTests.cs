using System.Diagnostics;
using System.IO.Compression;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Text;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;

namespace Plantoir.Tests;

/// <summary>Runs only when <c>windows-app\Vendor\obsidian-addons</c> is fetched; says what to run when it is not (NativeVendorFact's precedent).</summary>
public sealed class CarriedAddOnsFactAttribute : FactAttribute
{
    public CarriedAddOnsFactAttribute()
    {
        if (!Directory.Exists(ObsidianFigureAddOnsTests.VendorCarried))
            Skip = "No carried add-ons here: run windows-app\\Vendor\\fetch-obsidian-addons.ps1 once in this clone.";
    }
}

/// <summary>
/// Obsidian's add-ons for diagrams and graphs (#581; the mac's
/// <c>ObsidianFigureAddOnsTests</c>, #495): every case list of
/// <c>contracts/shared-rules.json</c> → <c>obsidianAddOnsForFigures</c>, run
/// against <c>Plantoir.Core</c>. Sentences by KEY; nothing is retyped.
/// </summary>
[Collection(SharedActivityState.Name)]
public sealed class ObsidianFigureAddOnsTests : IDisposable
{
    private readonly string _root;

    public ObsidianFigureAddOnsTests()
    {
        _root = Directory.CreateTempSubdirectory("plantoir-581-").FullName;
        ObsidianFigureAddOnsThisRun.Forget();
    }

    public void Dispose()
    {
        ObsidianFigureAddOnsThisRun.Forget();
        try { Directory.Delete(_root, recursive: true); } catch { }
    }

    internal static JsonNode Contract => ContractLoader.LoadJson("shared-rules.json")["obsidianAddOnsForFigures"]!;

    internal static string VendorCarried => Path.Combine(ContractLoader.RepositoryRoot, "windows-app", "Vendor", ObsidianFigureAddOns.CarriedFolderName);

    internal static string Defaults => Path.Combine(ContractLoader.RepositoryRoot, "support", "obsidian_defaults", ".obsidian");

    private static readonly IReadOnlySet<string> AllKinds = ObsidianFigureAddOns.Pinned.Select(a => a.Kind).ToHashSet();

    // ---- addOns: the pins, the fetch and the build's check ------------------

    [Fact]
    public void ThePinsAreTheContracts()
    {
        var addOns = Contract["addOns"]!.AsArray();
        Assert.Equal(addOns.Count, ObsidianFigureAddOns.Pinned.Count);
        for (int i = 0; i < addOns.Count; i++)
        {
            var pinned = ObsidianFigureAddOns.Pinned[i];
            var entry = addOns[i]!;
            Assert.Equal(entry["kind"]!.ToString(), pinned.Kind);
            Assert.Equal(entry["id"]!.ToString(), pinned.Id);
            Assert.Equal(entry["name"]!.ToString(), pinned.Name);
            Assert.Equal(entry["version"]!.ToString(), pinned.Version);
            var files = entry["files"]!.AsArray();
            Assert.Equal(files.Count, pinned.Files.Count);
            for (int f = 0; f < files.Count; f++)
            {
                Assert.Equal(files[f]!["name"]!.ToString(), pinned.Files[f].Name);
                Assert.Equal(files[f]!["bytes"]!.GetValue<long>(), pinned.Files[f].Bytes);
                Assert.Equal(files[f]!["sha256"]!.ToString(), pinned.Files[f].Sha256);
            }
        }
    }

    [Fact]
    public void TheFetchScriptCarriesNoPinOfItsOwnAndReadsTheContracts()
    {
        string script = File.ReadAllText(Path.Combine(ContractLoader.RepositoryRoot, "windows-app", "Vendor", "fetch-obsidian-addons.ps1"));
        Assert.DoesNotMatch(new Regex("[0-9a-fA-F]{64}"), script);
        Assert.Contains("obsidianAddOnsForFigures", script);
        Assert.Contains("addOns", script);
    }

    [Fact]
    public void TheBuildCarriesTheAddOnsAndRefusesWithoutThem()
    {
        string project = File.ReadAllText(Path.Combine(ContractLoader.RepositoryRoot, "windows-app", "Plantoir", "Plantoir.csproj"));
        int pinnedFiles = Contract["addOns"]!.AsArray().Sum(a => a!["files"]!.AsArray().Count);
        Assert.Contains($"<_PlantoirAddOnFileCount>{pinnedFiles}</_PlantoirAddOnFileCount>", project);
        Assert.Contains("Include=\"..\\Vendor\\obsidian-addons\\**\" Link=\"obsidian-addons\\", project);
        Assert.Contains("<Target Name=\"CheckObsidianAddOns\" BeforeTargets=\"BeforeBuild;Publish\">", project);
        Assert.Contains("windows-app/Vendor/obsidian-addons/", File.ReadAllText(Path.Combine(ContractLoader.RepositoryRoot, ".gitignore")));
    }

    // ---- carried: the real files --------------------------------------------

    [CarriedAddOnsFact]
    public void TheCarriedFilesMatchThePinsAndNothingElseIsThere()
    {
        Assert.True(ObsidianFigureAddOns.CarriedCopyMatches(ObsidianFigureAddOns.Pinned, VendorCarried));
        var carried = Directory.EnumerateFiles(VendorCarried, "*", SearchOption.AllDirectories)
            .Select(f => Path.GetRelativePath(VendorCarried, f).Replace('\\', '/')).OrderBy(f => f, StringComparer.Ordinal).ToList();
        var expected = ObsidianFigureAddOns.Pinned.SelectMany(a => a.Files.Select(f => a.Id + "/" + f.Name)).OrderBy(f => f, StringComparer.Ordinal).ToList();
        Assert.Equal(expected, carried);

        string flipped = Path.Combine(_root, "flipped");
        foreach (string file in Directory.EnumerateFiles(VendorCarried, "*", SearchOption.AllDirectories))
        {
            string to = Path.Combine(flipped, Path.GetRelativePath(VendorCarried, file));
            Directory.CreateDirectory(Path.GetDirectoryName(to)!);
            File.Copy(file, to);
        }
        string main = Path.Combine(flipped, "obsidian-functionplot", "main.js");
        byte[] bytes = File.ReadAllBytes(main);
        bytes[100] ^= 1;
        File.WriteAllBytes(main, bytes);
        Assert.False(ObsidianFigureAddOns.CarriedCopyMatches(ObsidianFigureAddOns.Pinned, flipped));
        string course = NewCourse("flippedCourse");
        var results = ObsidianFigureAddOns.Install(ObsidianFigureAddOns.Pinned, course, flipped, Defaults);
        Assert.All(results, r => Assert.Equal(ObsidianFigureAddOns.OutcomeKind.RefusedCarriedCopy, r.Outcome.Kind));
        Assert.False(Directory.Exists(Path.Combine(course, ".obsidian")));
    }

    /// <summary>The real carried add-ons, written twice: the second pass changes no byte and no date, and writes no line.</summary>
    [CarriedAddOnsFact]
    public void ASecondPassChangesNoByteAndWritesNoLine()
    {
        string trail = RedirectTrail();
        try
        {
            string course = NewCourse("MPM2D");
            var watch = Stopwatch.StartNew();
            var first = ObsidianFigureAddOns.Install(ObsidianFigureAddOns.Pinned, course, VendorCarried, Defaults);
            watch.Stop();
            Assert.All(first, r => Assert.Equal(ObsidianFigureAddOns.OutcomeKind.Added, r.Outcome.Kind));
            var before = Snapshot(course);
            var second = ObsidianFigureAddOns.Install(ObsidianFigureAddOns.Pinned, course, VendorCarried, Defaults);
            Assert.All(second, r => Assert.Equal(ObsidianFigureAddOns.OutcomeKind.AlreadyThere, r.Outcome.Kind));
            Assert.Equal(before, Snapshot(course));
            ObsidianFigureAddOnsThisRun.NotePass("MPM2D", ObsidianFigureAddOnsTrail.Trigger.AfterAPreview, second);
            Assert.False(File.Exists(trail) && File.ReadAllText(trail).Contains("Obsidian add-ons"));
            Assert.True(watch.ElapsedMilliseconds < 5000, $"a first pass took {watch.ElapsedMilliseconds} ms");
        }
        finally { RestoreTrail(); }
    }

    // ---- figureFences.fences and whichPages ---------------------------------

    [Fact]
    public void EveryFigureFencesCaseReadsTheSame()
    {
        var cases = ContractLoader.LoadJson("shared-rules.json")["figureFences"]!["fences"]!["cases"]!.AsArray();
        Assert.True(cases.Count >= 13);
        foreach (var c in cases)
        {
            var counts = new Dictionary<string, int>();
            var got = new List<string>();
            foreach (var block in FigureFenceScan.Blocks(c!["page"]!.ToString()))
            {
                if (block.Nested || !AllKinds.Contains(block.Lang)) continue;
                counts[block.Lang] = counts.GetValueOrDefault(block.Lang) + 1;
                got.Add($"{block.Lang}#{counts[block.Lang]}@{block.Line}");
            }
            var expected = c["found"]!.AsArray().Select(f => $"{f!["engine"]}#{f["block"]}@{f["line"]}").ToList();
            Assert.True(expected.SequenceEqual(got), $"{c["name"]}: expected [{string.Join(", ", expected)}], got [{string.Join(", ", got)}]");
        }
    }

    [Fact]
    public void EveryWhichPagesCase()
    {
        var cases = Contract["whichPages"]!["cases"]!.AsArray();
        Assert.Equal(12, cases.Count);
        int n = 0;
        foreach (var c in cases)
        {
            string course = NewCourse($"pages{n++}");
            foreach (var (path, text) in c!["files"]!.AsObject())
            {
                string file = Path.Combine(course, path.Replace('/', '\\'));
                Directory.CreateDirectory(Path.GetDirectoryName(file)!);
                File.WriteAllText(file, text!.ToString(), new UTF8Encoding(false));
            }
            var needs = ObsidianFigureAddOns.AddOnsForKinds(ObsidianFigureAddOns.KindsUsed(course, AllKinds)).Select(a => a.Id).ToList();
            Assert.True(c["needs"]!.AsArray().Select(x => x!.ToString()).SequenceEqual(needs), $"{c["name"]}: got [{string.Join(", ", needs)}]");
        }
    }

    [Fact]
    public void AnEvictedPageIsNeverRead()
    {
        string course = NewCourse("evicted");
        File.WriteAllText(Path.Combine(course, "a.md"), "```functionplot\ny = x\n```\n");
        Assert.Empty(ObsidianFigureAddOns.KindsUsed(course, AllKinds, isEvicted: _ => true));
        Assert.Single(ObsidianFigureAddOns.KindsUsed(course, AllKinds, isEvicted: _ => false));
    }

    /// <summary>A folder link is not followed (no loop, nothing outside the course read), and a page under it does not count.</summary>
    [Fact]
    public void AFolderLinkIsNeverFollowed()
    {
        string course = NewCourse("linked");
        string outside = Path.Combine(_root, "outside");
        Directory.CreateDirectory(outside);
        File.WriteAllText(Path.Combine(outside, "a.md"), "```tikz\nx\n```\n");
        ReferenceFixtures.Junction(Path.Combine(course, "Linked"), outside);
        ReferenceFixtures.Junction(Path.Combine(course, "Loop"), course);
        Assert.Empty(ObsidianFigureAddOns.KindsUsed(course, AllKinds));
    }

    [Fact]
    public void TwoThousandPagesAreScannedQuickly()
    {
        string course = NewCourse("big");
        for (int i = 0; i < 2000; i++)
        {
            string folder = Path.Combine(course, $"Unit {i / 100}");
            Directory.CreateDirectory(folder);
            File.WriteAllText(Path.Combine(folder, $"Lesson {i}.md"), $"# Lesson {i}\n\nSome words about tikz.\n\n```python\nprint({i})\n```\n");
        }
        var watch = Stopwatch.StartNew();
        Assert.Empty(ObsidianFigureAddOns.KindsUsed(course, AllKinds));
        watch.Stop();
        Assert.True(watch.ElapsedMilliseconds < 3000, $"2,000 pages took {watch.ElapsedMilliseconds} ms");
    }

    /// <summary>
    /// The walker agrees with <c>scripts/markdown_code.py</c> → <c>fenced_blocks</c>
    /// on 2,000 generated pages (fixed seed): fences, list markers, nested
    /// containers, quotes, <c>%%</c>, CR LF, LONE CR, a byte-order mark and
    /// invalid UTF-8 — decoded the same way on both sides (<c>errors="replace"</c>).
    /// </summary>
    [Fact]
    public void TheWalkerAgreesWithThePythonOnGeneratedPages()
    {
        string pages = Path.Combine(_root, "fuzz");
        Directory.CreateDirectory(pages);
        var random = new Random(495581);
        string[] pieces =
        {
            "```tikz\n", "```functionplot\n", "~~~tikz\n", "````functionplot x\n", "```\n", "~~~\n", "````\n",
            "- ```tikz\n", "1. ```functionplot\n", "- - ```tikz\n", "1. > ```tikz\n", "> ```tikz\n", "> > ```functionplot\n",
            "> ```\n", "  ```\n", "%%\n", "%% a %%\n", "text\n", "\n", "- item\n", "   indented\n", "\t```tikz\n",
            "```tikz `x`\n", "```TikZ\n", "y = x^2\r\n", "a\rb\n", "\r\n", "# heading\n", "> quote\n",
        };
        var expectedPages = new List<string>();
        for (int i = 0; i < 2000; i++)
        {
            var bytes = new List<byte>();
            if (random.Next(20) == 0) bytes.AddRange(new byte[] { 0xEF, 0xBB, 0xBF });
            int count = random.Next(1, 14);
            for (int p = 0; p < count; p++)
            {
                bytes.AddRange(Encoding.UTF8.GetBytes(pieces[random.Next(pieces.Length)]));
                if (random.Next(40) == 0) bytes.Add(0xFF);
                if (random.Next(60) == 0) bytes.AddRange(new byte[] { 0xC3 });
            }
            File.WriteAllBytes(Path.Combine(pages, $"{i:D4}.md"), bytes.ToArray());
        }
        string script = Path.Combine(_root, "fenced.py");
        File.WriteAllText(script,
            "import json, os, sys\n" +
            "sys.path.insert(0, sys.argv[2])\n" +
            "import markdown_code\n" +
            "out = {}\n" +
            "for name in sorted(os.listdir(sys.argv[1])):\n" +
            "    text = open(os.path.join(sys.argv[1], name), 'rb').read().decode('utf-8', 'replace')\n" +
            "    out[name] = [[b['lang'], b['line'], bool(b['nested'])] for b in markdown_code.fenced_blocks(text)]\n" +
            "sys.stdout.write(json.dumps(out))\n");
        var start = new ProcessStartInfo("python") { RedirectStandardOutput = true, RedirectStandardError = true, UseShellExecute = false, CreateNoWindow = true, StandardOutputEncoding = Encoding.UTF8 };
        start.ArgumentList.Add("-I");
        start.ArgumentList.Add(script);
        start.ArgumentList.Add(pages);
        start.ArgumentList.Add(Path.Combine(ContractLoader.RepositoryRoot, "scripts"));
        using var python = Process.Start(start)!;
        string output = python.StandardOutput.ReadToEnd();
        string errors = python.StandardError.ReadToEnd();
        python.WaitForExit();
        Assert.True(python.ExitCode == 0, errors);
        var fromPython = JsonNode.Parse(output)!.AsObject();
        int withBlocks = 0;
        foreach (var (name, blocks) in fromPython)
        {
            string text = Encoding.UTF8.GetString(File.ReadAllBytes(Path.Combine(pages, name)));
            var ours = FigureFenceScan.Blocks(text).Select(b => $"{b.Lang}|{b.Line}|{b.Nested}").ToList();
            var theirs = blocks!.AsArray().Select(b => $"{b![0]}|{b[1]}|{b[2]!.GetValue<bool>()}").ToList();
            Assert.True(theirs.SequenceEqual(ours), $"{name}: python [{string.Join(", ", theirs)}], C# [{string.Join(", ", ours)}]");
            if (ours.Count > 0) withBlocks++;
        }
        Assert.Equal(2000, fromPython.Count);
        Assert.True(withBlocks > 1000, $"only {withBlocks} pages had a block");
    }

    // ---- answer ---------------------------------------------------------------

    [Fact]
    public void TheAnswerCasesAndTheToggle()
    {
        var answer = Contract["answer"]!;
        Assert.Equal(answer["values"]!.AsArray().Select(v => v!.ToString()),
            Enum.GetValues<ObsidianFigureAddOnsAnswer>().Select(ObsidianFigureAddOnsAnswers.Stored));
        Assert.Equal(answer["default"]!.ToString(), new AppSettings().ObsidianFigureAddOns);
        foreach (var c in answer["cases"]!.AsArray())
        {
            string? stored = c!["stored"]?.ToString();
            Assert.Equal(c["reads"]!.ToString(), ObsidianFigureAddOnsAnswers.Stored(ObsidianFigureAddOnsAnswers.Reading(stored)));
        }
        string path = Path.Combine(_root, "settings.json");
        var settings = new AppSettings();
        foreach (var t in answer["toggle"]!.AsArray())
        {
            settings.ChangeObsidianFigureAddOns(t!["on"]!.GetValue<bool>());
            Assert.Equal(t["stores"]!.ToString(), settings.ObsidianFigureAddOns);
        }
        Assert.False(settings.ChangeObsidianFigureAddOns(false));   // unchanged: nothing to say
        Assert.True(settings.ChangeObsidianFigureAddOns(true));
    }

    // ---- offerCases, previewCases, whichVaultOpens, sequence -----------------

    [Fact]
    public void EveryOfferCase()
    {
        var cases = Contract["offerCases"]!["cases"]!.AsArray();
        Assert.Equal(15, cases.Count);
        foreach (var c in cases)
        {
            var answer = ObsidianFigureAddOnsAnswers.Reading(c!["answer"]!.ToString());
            Assert.True(c["scans"]!.GetValue<bool>() == ObsidianFigureAddOnsOffer.Scans(
                c["reference"]!.GetValue<bool>(), c["obsidianInstalled"]!.GetValue<bool>(), answer, c["suppressedThisRun"]!.GetValue<bool>()),
                $"{c["name"]}: scans");
            var decision = ObsidianFigureAddOnsOffer.Decide(new ObsidianFigureAddOnsOffer.Situation(
                c["reference"]!.GetValue<bool>(), c["obsidianInstalled"]!.GetValue<bool>(), answer, c["suppressedThisRun"]!.GetValue<bool>(),
                c["wouldAdd"]!.GetValue<bool>(), c["vaultIsTheCourse"]!.GetValue<bool>(), c["courseOpenInObsidian"]!.GetValue<bool>(),
                c["reopenDeclinedThisRun"]!.GetValue<bool>()));
            Assert.True(c["decision"]!.ToString() == ContractCase(decision.ToString()), $"{c["name"]}: {decision}");
        }
    }

    [Fact]
    public void EveryPreviewCase()
    {
        var cases = Contract["previewCases"]!["cases"]!.AsArray();
        Assert.Equal(8, cases.Count);
        foreach (var c in cases)
        {
            var decision = ObsidianFigureAddOnsOffer.AfterAPreview(
                c!["reference"]!.GetValue<bool>(), c["obsidianInstalled"]!.GetValue<bool>(),
                ObsidianFigureAddOnsAnswers.Reading(c["answer"]!.ToString()), c["wouldAdd"]!.GetValue<bool>(),
                c["vaultIsTheCourse"]!.GetValue<bool>(), c["courseOpenInObsidian"]!.GetValue<bool>());
            Assert.True(c["decision"]!.ToString() == ContractCase(decision.ToString()), $"{c["name"]}: {decision}");
        }
    }

    [Fact]
    public void WhichVaultOpensCases()
    {
        foreach (var c in Contract["whichVaultOpens"]!["cases"]!.AsArray())
        {
            string registry = Registry(c!["vaults"]!.AsArray().Select(v => (v!.ToString(), false)).ToArray());
            string target = c["target"]!.ToString(), course = c["course"]!.ToString();
            Assert.True(c["opens"]?.ToString() == ObsidianFigureAddOnsOffer.VaultThatOpens(target, registry), $"{c["name"]}: opens");
            Assert.True(c["isTheCourse"]!.GetValue<bool>() == ObsidianFigureAddOnsOffer.VaultIsTheCourse(target, course, registry), $"{c["name"]}: isTheCourse");
        }
        // Windows' own spelling of the same rule: either separator, any case.
        string windows = Registry((@"C:\Users\t\courses\MPM2D", false));
        Assert.True(ObsidianFigureAddOnsOffer.VaultIsTheCourse(@"c:\users\t\courses\mpm2d\Section 1\index.md", @"C:\Users\t\courses\MPM2D", windows));
        Assert.Null(ObsidianFigureAddOnsOffer.VaultThatOpens(@"C:\Users\t\courses\MPM2D-old", windows));
    }

    [Fact]
    public void WhatCountsAsOpenInObsidian()
    {
        string course = @"C:\w\courses\MPM2D";
        string marked = Registry((course, true), (@"C:\w\courses\ICS3U", false));
        Assert.True(ObsidianFigureAddOnsOffer.CourseIsOpen(course, obsidianRunning: true, marked));
        Assert.False(ObsidianFigureAddOnsOffer.CourseIsOpen(course, obsidianRunning: false, marked));
        Assert.False(ObsidianFigureAddOnsOffer.CourseIsOpen(@"C:\w\courses\ICS3U", obsidianRunning: true, marked));
        // Unreadable while running: rewritten in place, so not knowing is not "closed".
        Assert.True(ObsidianFigureAddOnsOffer.CourseIsOpen(course, obsidianRunning: true, "{\"vaults\":"));
        Assert.True(ObsidianFigureAddOnsOffer.CourseIsOpen(course, obsidianRunning: true, null));
        Assert.Equal(new[] { course }, ObsidianFigureAddOnsOffer.VaultsOpen(true, marked));
        Assert.Empty(ObsidianFigureAddOnsOffer.VaultsOpen(false, marked));
    }

    [Fact]
    public void TheSequenceIsEightNumberedSteps()
    {
        var steps = Contract["sequence"]!.AsArray();
        Assert.Equal(Enumerable.Range(1, 8), steps.Select(s => s!["step"]!.GetValue<int>()));
        // Each step's route test is in ObsidianOpenRouteTests; the decision
        // names it reaches are the contract's own.
        var decisions = Contract["offerCases"]!["cases"]!.AsArray().Select(c => c!["decision"]!.ToString()).ToHashSet();
        Assert.Equal(Enum.GetNames<ObsidianFigureAddOnsOffer.Decision>().Select(ContractCase).ToHashSet(), decisions);
    }

    // ---- vaultCases -----------------------------------------------------------

    [Fact]
    public void EveryVaultCase()
    {
        SweepStaleDeniedFolders();
        var vault = Contract["vaultCases"]!;
        Assert.Equal(vault["outcomeNames"]!.AsArray().Select(n => n!.ToString()),
            Enum.GetNames<ObsidianFigureAddOns.OutcomeKind>().Select(ContractCase));
        var cases = vault["cases"]!.AsArray();
        Assert.Equal(23, cases.Count);
        int n = 0;
        foreach (var c in cases) RunVaultCase(c!, n++);
    }

    private void RunVaultCase(JsonNode c, int n)
    {
        string name = c["name"]!.ToString();
        string caseRoot = Path.Combine(_root, (c["before"]?["plugins"]?.ToString() == "readOnly" ? "plantoir-581-acl-" : "v") + n);
        string course = Path.Combine(caseRoot, "course");
        Directory.CreateDirectory(course);
        var (addOns, carried) = FakeAddOns(caseRoot, mismatched: c["carried"]?.ToString() == "mismatch");
        var needs = c["needs"]!.AsArray().Select(x => x!.ToString()).ToList();
        var needed = addOns.Where(a => needs.Contains(a.Id)).ToList();
        string defaults = c["defaults"]?.ToString() == "missing" ? Path.Combine(caseRoot, "no-defaults") : Defaults;

        var before = c["before"]!;
        string settings = Path.Combine(course, ".obsidian");
        string plugins = Path.Combine(settings, "plugins");
        switch (before["settings"]?.ToString() ?? "present")
        {
            case "present":
                Directory.CreateDirectory(settings);
                File.WriteAllText(Path.Combine(settings, "app.json"), "{}");
                break;
            case "presentWithoutAppJson":
                Directory.CreateDirectory(settings);
                break;
            case "link":
                string elsewhere = Path.Combine(caseRoot, "shared-settings");
                Directory.CreateDirectory(elsewhere);
                File.WriteAllText(Path.Combine(elsewhere, "app.json"), "{}");
                ReferenceFixtures.Junction(settings, elsewhere);
                break;
        }
        if (before["list"] is { } list) File.WriteAllText(Path.Combine(settings, ObsidianFigureAddOns.ListName), list.ToString(), new UTF8Encoding(false));
        if (before["plugins"]?.ToString() == "link")
        {
            string elsewhere = Path.Combine(caseRoot, "shared-plugins");
            Directory.CreateDirectory(elsewhere);
            ReferenceFixtures.Junction(plugins, elsewhere);
        }
        foreach (var (id, state) in before["addOns"]?.AsObject() ?? new JsonObject())
        {
            string folder = Path.Combine(plugins, id);
            if (state is JsonValue && state.ToString() == "file")
            {
                Directory.CreateDirectory(plugins);
                File.WriteAllText(folder, "not a folder");
                continue;
            }
            Directory.CreateDirectory(folder);
            File.WriteAllText(Path.Combine(folder, "main.js"), "the copy that was there");
            File.WriteAllText(Path.Combine(folder, "manifest.json"),
                state!["manifest"]?.ToString() == "unreadable" ? "{ not json" : $"{{\"id\":\"{id}\",\"version\":\"{state["version"]}\"}}");
            if (state["marker"]!.GetValue<bool>())
                File.WriteAllText(Path.Combine(folder, ObsidianFigureAddOns.MarkerName), ObsidianFigureAddOns.MarkerText(state["version"]?.ToString() ?? "0.5.2"));
        }
        foreach (var id in before["partial"]?.AsArray() ?? new JsonArray())
        {
            string partial = Path.Combine(plugins, id + ObsidianFigureAddOns.PartialSuffix);
            Directory.CreateDirectory(partial);
            File.WriteAllText(Path.Combine(partial, "main.js"), "half");
        }
        bool readOnly = before["plugins"]?.ToString() == "readOnly";
        if (readOnly) { Directory.CreateDirectory(plugins); DenyWriting(plugins); }

        List<ObsidianFigureAddOns.Result> results;
        try { results = ObsidianFigureAddOns.Install(needed, course, carried, defaults); }
        finally { if (readOnly) AllowWriting(plugins); }

        var expected = c["outcomes"]!.AsObject().ToDictionary(p => p.Key, p => p.Value!.ToString());
        var got = results.ToDictionary(r => r.AddOn.Id, r => r.Outcome.ContractName
            + (r.Outcome.Kind is ObsidianFigureAddOns.OutcomeKind.LeftAloneTheirs or ObsidianFigureAddOns.OutcomeKind.LeftAloneOtherVersion ? ":" + r.Outcome.Version : ""));
        Assert.True(expected.OrderBy(p => p.Key).SequenceEqual(got.OrderBy(p => p.Key)),
            $"{name}: expected {string.Join(", ", expected)}; got {string.Join(", ", got)}");

        string listPath = Path.Combine(settings, ObsidianFigureAddOns.ListName);
        if (c["listAfter"] is null) Assert.False(File.Exists(listPath), $"{name}: a list was written");
        else Assert.True(c["listAfter"]!.ToString() == File.ReadAllText(listPath), $"{name}: list is {File.ReadAllText(listPath)}");

        var written = c["written"]?.AsArray().Select(x => x!.ToString()).ToList() ?? new List<string>();
        foreach (var addOn in needed)
        {
            string folder = Path.Combine(plugins, addOn.Id);
            if (written.Contains(addOn.Id))
            {
                foreach (var file in addOn.Files)
                    Assert.True(File.ReadAllBytes(Path.Combine(carried, addOn.Id, file.Name)).SequenceEqual(File.ReadAllBytes(Path.Combine(folder, file.Name))),
                        $"{name}: {addOn.Id}/{file.Name} not written");
                Assert.Equal(ObsidianFigureAddOns.MarkerText(addOn.Version), File.ReadAllText(Path.Combine(folder, ObsidianFigureAddOns.MarkerName)));
            }
            else if (File.Exists(Path.Combine(folder, "main.js")))
                Assert.False(File.ReadAllBytes(Path.Combine(carried, addOn.Id, "main.js")).SequenceEqual(File.ReadAllBytes(Path.Combine(folder, "main.js"))),
                    $"{name}: {addOn.Id} was written");
        }
        if (c["partialAfter"] is not null)
            Assert.Empty(Directory.Exists(plugins) ? Directory.EnumerateDirectories(plugins, "*" + ObsidianFigureAddOns.PartialSuffix) : Array.Empty<string>());
        if (c["seeded"]?.GetValue<bool>() == true)
            Assert.Equal(File.ReadAllBytes(Path.Combine(Defaults, "app.json")), File.ReadAllBytes(Path.Combine(settings, "app.json")));
    }

    /// <summary>The deny ACL is what makes couldNotWrite: without it the same case writes (proves the case measures the ACL, not something else).</summary>
    [Fact]
    public void WithoutTheDenyTheReadOnlyCaseWrites()
    {
        string course = NewCourse("writable");
        Directory.CreateDirectory(Path.Combine(course, ".obsidian", "plugins"));
        File.WriteAllText(Path.Combine(course, ".obsidian", "app.json"), "{}");
        var (addOns, carried) = FakeAddOns(Path.Combine(_root, "writableCarried"), mismatched: false);
        File.SetAttributes(Path.Combine(course, ".obsidian", "plugins"), FileAttributes.ReadOnly | FileAttributes.Directory);
        var results = ObsidianFigureAddOns.Install(addOns, course, carried, Defaults);
        // The read-only ATTRIBUTE does not stop writes into a folder on Windows (#581's own note).
        Assert.All(results, r => Assert.Equal(ObsidianFigureAddOns.OutcomeKind.Added, r.Outcome.Kind));
    }

    // ---- listCases and the sidecar --------------------------------------------

    [Fact]
    public void EveryListCase()
    {
        var cases = Contract["listCases"]!["cases"]!.AsArray();
        Assert.Equal(11, cases.Count);
        foreach (var c in cases)
        {
            byte[]? data = c!["list"] is null ? null : Encoding.UTF8.GetBytes(c["list"]!.ToString());
            var adding = c["adding"]!.AsArray().Select(x => x!.ToString()).ToList();
            var after = ObsidianFigureAddOns.ListAfterAdding(adding, data);
            string got = after.Kind switch
            {
                ObsidianFigureAddOns.ListAfterKind.Unchanged => "unchanged",
                ObsidianFigureAddOns.ListAfterKind.Refused => "refused",
                _ => after.Text!,
            };
            Assert.True(c["after"]!.ToString() == got, $"{c["name"]}: {got}");
        }
    }

    /// <summary>JSON.stringify's escaping, not a general serializer's: non-ASCII and +&lt;&gt;&amp;' stay as they are.</summary>
    [Fact]
    public void TheListIsWrittenAsJsonStringifyWritesIt()
    {
        var after = ObsidianFigureAddOns.ListAfterAdding(new[] { "obsidian-tikzjax" },
            Encoding.UTF8.GetBytes("[\"café-plugin\",\"a+b<c>&'d\",\"quote\\\"back\\\\slash\",\"tab\\tline\\u0001\"]"));
        Assert.Equal("[\n  \"café-plugin\",\n  \"a+b<c>&'d\",\n  \"quote\\\"back\\\\slash\",\n  \"tab\\tline\\u0001\",\n  \"obsidian-tikzjax\"\n]", after.Text);
        Assert.DoesNotContain('\r', after.Text!);
    }

    [Fact]
    public void TheSidecarIsTheContracts()
    {
        var sidecar = Contract["sidecar"]!;
        Assert.Equal(sidecar["name"]!.ToString(), ObsidianFigureAddOns.MarkerName);
        Assert.Equal(sidecar["partialSuffix"]!.ToString(), ObsidianFigureAddOns.PartialSuffix);
        Assert.Equal(sidecar["text"]!.ToString().Replace("{version}", "0.5.2"), ObsidianFigureAddOns.MarkerText("0.5.2"));
    }

    /// <summary>A pass stopped after the rename and before the manifest leaves a folder Obsidian ignores, which the next pass replaces.</summary>
    [Fact]
    public void AStoppedPassIsReplacedByTheNext()
    {
        string course = NewCourse("stopped");
        var (addOns, carried) = FakeAddOns(Path.Combine(_root, "stoppedCarried"), mismatched: false);
        var tikz = addOns.Where(a => a.Id == "obsidian-tikzjax").ToList();
        Directory.CreateDirectory(Path.Combine(course, ".obsidian"));
        File.WriteAllText(Path.Combine(course, ".obsidian", "app.json"), "{}");
        string folder = Path.Combine(course, ".obsidian", "plugins", "obsidian-tikzjax");
        Directory.CreateDirectory(folder);
        File.WriteAllText(Path.Combine(folder, "main.js"), "half");
        File.WriteAllText(Path.Combine(folder, ObsidianFigureAddOns.MarkerName), ObsidianFigureAddOns.MarkerText("0.5.2"));
        Assert.Single(ObsidianFigureAddOns.WouldAdd(tikz, course));
        var results = ObsidianFigureAddOns.Install(tikz, course, carried, Defaults);
        Assert.Equal(ObsidianFigureAddOns.OutcomeKind.Added, results.Single().Outcome.Kind);
        Assert.True(File.Exists(Path.Combine(folder, "manifest.json")));
        Assert.Empty(ObsidianFigureAddOns.WouldAdd(tikz, course));
    }

    // ---- serialisation ----------------------------------------------------------

    [Fact]
    public async Task PassesNeverOverlap()
    {
        var (addOns, carried) = FakeAddOns(Path.Combine(_root, "queueCarried"), mismatched: false);
        ObsidianFigureAddOns.ForgetMostPassesAtOnce();
        var passes = Enumerable.Range(0, 8).Select(i =>
        {
            string course = NewCourse($"queue{i % 2}");
            return ObsidianFigureAddOnsQueue.InstallAsync(addOns, course, carried, Defaults);
        }).ToList();
        await Task.WhenAll(passes);
        Assert.Equal(1, ObsidianFigureAddOns.MostPassesAtOnce);
    }

    // ---- backups ------------------------------------------------------------------

    [Fact]
    public void BackupsLeavePlantoirsAddOnsOut()
    {
        int n = 0;
        foreach (var c in Contract["backups"]!["cases"]!.AsArray())
        {
            string courses = Path.Combine(_root, $"backups{n++}", "courses");
            string course = Path.Combine(courses, "MPM2D");
            Directory.CreateDirectory(course);
            File.WriteAllText(Path.Combine(course, "course_config.json"), "{}");
            string plugins = Path.Combine(course, ".obsidian", "plugins");
            File.WriteAllText(Path.Combine(Directory.CreateDirectory(Path.Combine(course, ".obsidian")).FullName, ObsidianFigureAddOns.ListName), "[]");
            foreach (var (folder, state) in c!["plugins"]!.AsObject())
            {
                string path = Path.Combine(plugins, folder);
                Directory.CreateDirectory(path);
                File.WriteAllText(Path.Combine(path, "main.js"), "code");
                if (state!["marker"]!.GetValue<bool>()) File.WriteAllText(Path.Combine(path, ObsidianFigureAddOns.MarkerName), ObsidianFigureAddOns.MarkerText("1"));
            }
            var model = new Course("MPM2D", course, CourseConfiguration.Load(Path.Combine(course, "course_config.json")));
            string zip = CourseArchiver.BackUpCourse(model, courses);
            using var archive = ZipFile.OpenRead(zip);
            var entries = archive.Entries.Select(e => e.FullName).ToHashSet();
            foreach (var kept in c["inZip"]!.AsArray()) Assert.Contains("MPM2D/" + kept, entries);
            foreach (var left in c["notInZip"]!.AsArray()) Assert.DoesNotContain("MPM2D/" + left, entries);
        }
    }

    // ---- wording and trail ------------------------------------------------------------

    private static readonly string[] WindowsKeys = { "offerMessage", "settingFooter" };

    [Fact]
    public void TheWordsAreTheContractsWithWindowsOwnTwo()
    {
        var wording = Contract["wording"]!.AsObject();
        var windows = Contract["windowsWording"]!.AsObject();
        Assert.Equal(WindowsKeys.OrderBy(k => k), windows.Select(p => p.Key).Where(k => k != "note").OrderBy(k => k));
        foreach (var (key, value) in wording)
        {
            if (key == "note") continue;
            string expected = (WindowsKeys.Contains(key) ? windows[key] : value)!.ToString();
            Assert.True(expected == OurWords(key), $"wording.{key} differs");
        }
        Assert.Equal(
            ObsidianFigureAddOnsWording.Filling(windows["offerMessage"]!.ToString(), "MPM2D") + "\n\n" + ObsidianFigureAddOnsWording.Filling(wording["offerWhileOpen"]!.ToString(), "MPM2D"),
            ObsidianFigureAddOnsWording.OfferText("MPM2D", courseIsOpen: true));
    }

    [Fact]
    public void TheWordsNeverNameTheMachinery()
    {
        string[] banned = { "plugin", "vault", "json", "folder", "script", "toolchain", "cannot", "docker", "container", "model" };
        foreach (var (key, _) in Contract["wording"]!.AsObject())
        {
            if (key == "note") continue;
            string outsideQuotes = Regex.Replace(OurWords(key), "“[^”]*”", "");
            foreach (string word in banned)
                Assert.False(outsideQuotes.Contains(word, StringComparison.OrdinalIgnoreCase), $"wording.{key} says {word}");
            Assert.DoesNotContain("Return", outsideQuotes);
        }
    }

    private static string OurWords(string key) => key switch
    {
        "offerTitle" => ObsidianFigureAddOnsWording.OfferTitle,
        "offerMessage" => ObsidianFigureAddOnsWording.OfferMessage,
        "offerWhileOpen" => ObsidianFigureAddOnsWording.OfferWhileOpen,
        "offerAdd" => ObsidianFigureAddOnsWording.OfferAdd,
        "offerNotNow" => ObsidianFigureAddOnsWording.OfferNotNow,
        "dontAskAgain" => ObsidianFigureAddOnsWording.DontAskAgain,
        "reopenTitle" => ObsidianFigureAddOnsWording.ReopenTitle,
        "reopenMessage" => ObsidianFigureAddOnsWording.ReopenMessage,
        "reopen" => ObsidianFigureAddOnsWording.Reopen,
        "later" => ObsidianFigureAddOnsWording.Later,
        "paneTitle" => ObsidianFigureAddOnsWording.PaneTitle,
        "settingLabel" => ObsidianFigureAddOnsWording.SettingLabel,
        "settingFooter" => ObsidianFigureAddOnsWording.SettingFooter,
        _ => throw new Xunit.Sdk.XunitException($"wording.{key} has no Windows constant"),
    };

    [Fact]
    public void TheTrailLinesAreTheContracts()
    {
        var trail = Contract["trail"]!;
        string Fill(string t, string course = "MPM2D") => t.Replace("{course}", course);
        Assert.Equal(Fill(trail["offered"]!["addThem"]!.ToString()), ObsidianFigureAddOnsTrail.Offered("MPM2D", ObsidianFigureAddOnsTrail.Answered.AddThem));
        Assert.Equal(Fill(trail["offered"]!["notNow"]!.ToString()), ObsidianFigureAddOnsTrail.Offered("MPM2D", ObsidianFigureAddOnsTrail.Answered.NotNow));
        Assert.Equal(Fill(trail["offered"]!["notNowDontAskAgain"]!.ToString()), ObsidianFigureAddOnsTrail.Offered("MPM2D", ObsidianFigureAddOnsTrail.Answered.NotNowDontAskAgain));
        Assert.Equal(Fill(trail["notTheVault"]!.ToString()), ObsidianFigureAddOnsTrail.NotTheVault("MPM2D"));
        Assert.Equal(Fill(trail["reopened"]!["reopened"]!.ToString()), ObsidianFigureAddOnsTrail.Reopened("MPM2D"));
        Assert.Equal(Fill(trail["reopened"]!["later"]!.ToString()), ObsidianFigureAddOnsTrail.ReopenDeclined("MPM2D"));
        Assert.Equal(Fill(trail["reopened"]!["didNotClose"]!.ToString()), ObsidianFigureAddOnsTrail.DidNotClose("MPM2D"));
        Assert.Equal(trail["settingChanged"]!["on"]!.ToString(), ObsidianFigureAddOnsTrail.SettingChanged(true));
        Assert.Equal(trail["settingChanged"]!["off"]!.ToString(), ObsidianFigureAddOnsTrail.SettingChanged(false));

        var pass = trail["pass"]!;
        foreach (var (trigger, words) in pass["triggers"]!.AsObject())
            Assert.Equal(words!.ToString(), ObsidianFigureAddOnsTrail.TriggerWords(Enum.Parse<ObsidianFigureAddOnsTrail.Trigger>(trigger, ignoreCase: true)));
        var tikz = ObsidianFigureAddOns.Pinned[0];
        foreach (var (part, template) in pass["parts"]!.AsObject())
        {
            var kind = Enum.Parse<ObsidianFigureAddOns.OutcomeKind>(part, ignoreCase: true);
            var result = new ObsidianFigureAddOns.Result(tikz, new ObsidianFigureAddOns.Outcome(kind, "0.6.0", "Access is denied."));
            string expected = template!.ToString().Replace("{name}", tikz.Name).Replace("{pinned}", tikz.Version)
                .Replace("{version}", "0.6.0").Replace("{reason}", "Access is denied.");
            Assert.Equal(expected, ObsidianFigureAddOnsTrail.Words(result));
        }
        foreach (var (refusal, words) in pass["refusals"]!.AsObject())
        {
            var outcome = new ObsidianFigureAddOns.Outcome(Enum.Parse<ObsidianFigureAddOns.OutcomeKind>(refusal, ignoreCase: true));
            string line = ObsidianFigureAddOnsTrail.Pass("MPM2D", ObsidianFigureAddOnsTrail.Trigger.OpenInObsidian, new[] { new ObsidianFigureAddOns.Result(tikz, outcome) })!;
            Assert.Equal(pass["refusalShape"]!.ToString().Replace("{course}", "MPM2D").Replace("{trigger}", "at Open in Obsidian").Replace("{refusal}", words!.ToString()), line);
        }
        Assert.Equal(pass["example"]!.ToString(), ObsidianFigureAddOnsTrail.Pass("MPM2D", ObsidianFigureAddOnsTrail.Trigger.OpenInObsidian, new[]
        {
            new ObsidianFigureAddOns.Result(tikz, new ObsidianFigureAddOns.Outcome(ObsidianFigureAddOns.OutcomeKind.Added)),
            new ObsidianFigureAddOns.Result(ObsidianFigureAddOns.Pinned[1], new ObsidianFigureAddOns.Outcome(ObsidianFigureAddOns.OutcomeKind.AlreadyThere)),
        }));
        Assert.Null(ObsidianFigureAddOnsTrail.Pass("MPM2D", ObsidianFigureAddOnsTrail.Trigger.AfterAPreview, new[]
        {
            new ObsidianFigureAddOns.Result(tikz, new ObsidianFigureAddOns.Outcome(ObsidianFigureAddOns.OutcomeKind.AlreadyThere)),
        }));
    }

    [Fact]
    public void ARefusalIsSaidOncePerCoursePerRunAndAnAddAlways()
    {
        string trail = RedirectTrail();
        try
        {
            var tikz = ObsidianFigureAddOns.Pinned[0];
            var refused = new[] { new ObsidianFigureAddOns.Result(tikz, new ObsidianFigureAddOns.Outcome(ObsidianFigureAddOns.OutcomeKind.RefusedLink)) };
            ObsidianFigureAddOnsThisRun.NotePass("MPM2D", ObsidianFigureAddOnsTrail.Trigger.OpenInObsidian, refused);
            ObsidianFigureAddOnsThisRun.NotePass("MPM2D", ObsidianFigureAddOnsTrail.Trigger.AfterAPreview, refused);
            ObsidianFigureAddOnsThisRun.NotePass("ICS3U", ObsidianFigureAddOnsTrail.Trigger.AfterAPreview, refused);
            var added = new[] { new ObsidianFigureAddOns.Result(tikz, new ObsidianFigureAddOns.Outcome(ObsidianFigureAddOns.OutcomeKind.Added)) };
            ObsidianFigureAddOnsThisRun.NotePass("MPM2D", ObsidianFigureAddOnsTrail.Trigger.AfterAPreview, added);
            ObsidianFigureAddOnsThisRun.NotePass("MPM2D", ObsidianFigureAddOnsTrail.Trigger.AfterAPreview, added);
            var lines = File.ReadAllLines(trail);
            Assert.Equal(1, lines.Count(l => l.Contains("MPM2D") && l.Contains("is a link")));   // whichever trigger said it first
            Assert.Equal(1, lines.Count(l => l.Contains("ICS3U")));
            Assert.Equal(2, lines.Count(l => l.Contains("TikZJax 0.5.2 added")));
        }
        finally { RestoreTrail(); }
    }

    // ---- helpers ----------------------------------------------------------------------

    internal static string ContractCase(string name) => char.ToLowerInvariant(name[0]) + name[1..];

    internal static string Registry(params (string Path, bool Open)[] vaults)
    {
        var registry = new JsonObject();
        var list = new JsonObject();
        int i = 0;
        foreach (var (path, open) in vaults)
        {
            var entry = new JsonObject { ["path"] = path, ["ts"] = 1 };
            if (open) entry["open"] = true;
            list[$"{i++:x16}"] = entry;
        }
        registry["vaults"] = list;
        return registry.ToJsonString();
    }

    private string NewCourse(string name)
    {
        string course = Path.Combine(_root, "courses-" + Guid.NewGuid().ToString("N")[..6], name);
        Directory.CreateDirectory(course);
        return course;
    }

    /// <summary>Small stand-ins for the pinned add-ons: the same ids, kinds, names, versions and file names, with pins this test computes.</summary>
    internal static (List<ObsidianFigureAddOn> AddOns, string Carried) FakeAddOns(string folder, bool mismatched)
    {
        string carried = Path.Combine(folder, "carried");
        var addOns = new List<ObsidianFigureAddOn>();
        foreach (var pinned in ObsidianFigureAddOns.Pinned)
        {
            var files = new List<CarriedFile>();
            foreach (var file in pinned.Files)
            {
                byte[] bytes = Encoding.UTF8.GetBytes(file.Name == "manifest.json"
                    ? $"{{\"id\":\"{pinned.Id}\",\"version\":\"{pinned.Version}\"}}"
                    : $"Plantoir's copy of {pinned.Id}/{file.Name}");
                string path = Path.Combine(carried, pinned.Id, file.Name);
                Directory.CreateDirectory(Path.GetDirectoryName(path)!);
                File.WriteAllBytes(path, bytes);
                files.Add(new CarriedFile(file.Name, bytes.Length, ObsidianFigureAddOns.Sha256(bytes)));
            }
            addOns.Add(pinned with { Files = files });
        }
        if (mismatched) File.WriteAllText(Path.Combine(carried, "obsidian-tikzjax", "main.js"), "Plantoir's copy of obsidian-tikzjax/main.jz");
        return (addOns, carried);
    }

    private static Dictionary<string, (string, DateTime)> Snapshot(string root) =>
        Directory.EnumerateFileSystemEntries(root, "*", SearchOption.AllDirectories).ToDictionary(
            p => p, p => (File.Exists(p) ? ObsidianFigureAddOns.Sha256(File.ReadAllBytes(p)) : "folder", File.GetLastWriteTimeUtc(p)));

    private string RedirectTrail()
    {
        string trail = Path.Combine(_root, "activity.txt");
        ActivityTrail.SetCustomLogPathForTesting(trail);
        return trail;
    }

    private static void RestoreTrail() => ActivityTrail.SetCustomLogPathForTesting(TestTrailRedirect.ScratchTrailPath);

    private static FileSystemAccessRule DenyRule() => new(
        WindowsIdentity.GetCurrent().User!, FileSystemRights.Write | FileSystemRights.Delete | FileSystemRights.DeleteSubdirectoriesAndFiles,
        InheritanceFlags.ContainerInherit | InheritanceFlags.ObjectInherit, PropagationFlags.None, AccessControlType.Deny);

    /// <summary>A folder nobody may write in, for this user, by SID: the read-only attribute does not stop writes into a folder on Windows.</summary>
    internal static void DenyWriting(string folder)
    {
        var info = new DirectoryInfo(folder);
        var security = info.GetAccessControl();
        security.AddAccessRule(DenyRule());
        info.SetAccessControl(security);
    }

    internal static void AllowWriting(string folder)
    {
        var info = new DirectoryInfo(folder);
        var security = info.GetAccessControl();
        security.RemoveAccessRuleAll(DenyRule());
        info.SetAccessControl(security);
    }

    /// <summary>A run killed mid-case leaves a denied folder behind; take the deny off and remove it before starting.</summary>
    private static void SweepStaleDeniedFolders()
    {
        foreach (string stale in Directory.EnumerateDirectories(Path.GetTempPath(), "plantoir-581-*"))
            foreach (string denied in Directory.EnumerateDirectories(stale, "plantoir-581-acl-*"))
            {
                try
                {
                    string plugins = Path.Combine(denied, "course", ".obsidian", "plugins");
                    if (Directory.Exists(plugins)) AllowWriting(plugins);
                    Directory.Delete(stale, recursive: true);
                }
                catch { }
            }
    }
}
