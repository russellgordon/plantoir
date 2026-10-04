using System.Text.Json.Nodes;
using Plantoir.Core.Assist;
using Plantoir.Core.Models;

namespace Plantoir.Tests;

/// <summary>
/// #438 (the mac's #418/#410, Russell 2026-10-03): a contract sentence that
/// names the teacher's computer is written ONCE, with <c>{machine}</c>, and
/// this app fills it with <c>specialNames.platformWording.machine.windows</c>.
/// Driven off <c>machine.usedIn</c>, both ways: a sentence the contract adds
/// to the list with no Windows rendering here fails by name, and a list that
/// misses a string carrying the placeholder fails too (it would reach a
/// Windows teacher as "{machine}"). The mac pins the same list with
/// <c>SharedRulesContractTests.testEveryMachinePlaceholderIsRecorded</c>.
/// </summary>
public class MachineWordContractTests
{
    private static JsonNode Machine =>
        ContractLoader.LoadJson("shared-rules.json")["specialNames"]!["platformWording"]!["machine"]!;

    private static string PreviewPs1 =>
        File.ReadAllText(Path.Combine(ContractLoader.RepositoryRoot, "preview.ps1"));

    /// <summary>
    /// Each <c>usedIn</c> entry, and how this app says the filled sentence.
    /// A check returns null when it holds, or what is wrong.
    /// </summary>
    private static readonly Dictionary<string, Func<string, string?>> Said = new()
    {
        ["shared-rules.json:appUpdates.wording.elsewhereWork"] = filled =>
            filled == UpdateWording.ElsewhereWork("{course}") ? null : $"UpdateWording says \"{UpdateWording.ElsewhereWork("{course}")}\"",
        ["app-rules.json:previewPorts.whenThePreviewNeverAppears.cases[1].sentence"] = filled =>
            filled == PreviewReachability.Sentence(PreviewReachability.Verdict.TheSiteNeverAnswered)
                ? null : $"PreviewReachability says \"{PreviewReachability.Sentence(PreviewReachability.Verdict.TheSiteNeverAnswered)}\"",
        // The launcher prints it; test_launcher_rules.ps1 checks the same line
        // through LauncherRulesContractTests.
        ["app-rules.json:previewPorts.whenNoBlockIsFree.sentence[1]"] = filled =>
            PreviewPs1.Contains("Write-Host \"" + filled + "\"") ? null : "preview.ps1 does not print it word for word",
    };

    [Fact]
    public void TheWordIsTheContracts()
    {
        Assert.Equal(Machine["placeholder"]!.ToString(), MachineWord.Placeholder);
        Assert.Equal(Machine["windows"]!.ToString(), MachineWord.Name);
        Assert.Equal("restart this PC", MachineWord.Fill("restart this {machine}"));
    }

    [Fact]
    public void EverySentenceTheContractWritesWithTheMachineIsSaidFilled()
    {
        string placeholder = Machine["placeholder"]!.ToString();
        string word = Machine["windows"]!.ToString();
        var usedIn = Machine["usedIn"]!.AsArray().Select(e => e!.ToString()).ToList();
        Assert.NotEmpty(usedIn);
        Assert.Equal(usedIn.OrderBy(e => e, StringComparer.Ordinal), Said.Keys.OrderBy(e => e, StringComparer.Ordinal));

        foreach (string entry in usedIn)
        {
            int colon = entry.IndexOf(':');
            JsonNode? node = ContractLoader.LoadJson(entry[..colon]);
            foreach (string step in entry[(colon + 1)..].Split('.'))
            {
                string name = step.Contains('[') ? step[..step.IndexOf('[')] : step;
                node = node![name];
                if (step.Contains('['))
                    node = node![int.Parse(step[(step.IndexOf('[') + 1)..step.IndexOf(']')])];
            }
            string sentence = node!.ToString();
            Assert.True(sentence.Contains(placeholder), $"{entry} does not carry {placeholder}: {sentence}");
            string filled = sentence.Replace(placeholder, word);
            Assert.DoesNotContain("Mac", filled);
            string? wrong = Said[entry](filled);
            Assert.True(wrong is null, $"{entry}: {wrong}; the contract's, filled: \"{filled}\"");
        }
    }

    /// <summary>The Windows-only copies the fill replaced are gone from the contract (#438).</summary>
    [Fact]
    public void TheSupersededWindowsCopiesAreGone()
    {
        Assert.Null(ContractLoader.LoadJson("shared-rules.json")["appUpdates"]!["windowsWording"]!["elsewhereWorkOnWindows"]);
        var noBlock = ContractLoader.LoadJson("app-rules.json")["previewPorts"]!["whenNoBlockIsFree"]!;
        Assert.Null(noBlock["sentenceOnWindows"]);
        Assert.Null(noBlock["sentenceOnWindowsWhy"]);
    }

    /// <summary>
    /// <c>usedIn</c> names every string in <c>contracts/</c> that carries the
    /// placeholder — the record itself, under <c>specialNames.platformWording</c>,
    /// excepted, as on the mac.
    /// </summary>
    [Fact]
    public void EveryPlaceholderInTheContractsIsRecorded()
    {
        string placeholder = Machine["placeholder"]!.ToString();
        var found = new List<string>();
        string dir = Path.Combine(ContractLoader.RepositoryRoot, "contracts");
        int files = 0;
        foreach (string path in Directory.GetFiles(dir, "*.json").OrderBy(p => p, StringComparer.Ordinal))
        {
            string file = Path.GetFileName(path);
            Walk(JsonNode.Parse(File.ReadAllText(path)), "", p =>
            {
                if (!p.StartsWith("specialNames.platformWording.", StringComparison.Ordinal)) found.Add(file + ":" + p);
            });
            files++;
        }
        Assert.True(files >= 10, "the walk did not read the contract files");
        Assert.Equal(
            Machine["usedIn"]!.AsArray().Select(e => e!.ToString()).OrderBy(e => e, StringComparer.Ordinal),
            found.OrderBy(e => e, StringComparer.Ordinal));

        void Walk(JsonNode? node, string at, Action<string> carries)
        {
            switch (node)
            {
                case JsonObject o:
                    foreach (var (key, child) in o) Walk(child, at.Length == 0 ? key : at + "." + key, carries);
                    break;
                case JsonArray a:
                    for (int i = 0; i < a.Count; i++) Walk(a[i], $"{at}[{i}]", carries);
                    break;
                case JsonValue v when v.TryGetValue<string>(out var s) && s.Contains(placeholder):
                    carries(at);
                    break;
            }
        }
    }
}
