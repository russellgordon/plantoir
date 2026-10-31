using Plantoir.Core.Assist;

namespace Plantoir.Tests;

/// <summary>
/// #690 (the mac's #610): the assistant's Open in Obsidian is reached through
/// fixed shapes matched in code, because the tool is hidden from the local
/// model (measured on the mac and failed on both tiers). Played from
/// <c>assist-cases.json</c> → <c>openInObsidian</c>: every <c>accepted</c>
/// sentence reaches <c>open_in_obsidian</c> with no arguments, and no
/// <c>nearMisses</c> or <c>recordedOnly</c> sentence does.
/// </summary>
public class OpenInObsidianPhrasingsContractTests
{
    private static System.Text.Json.Nodes.JsonNode Block => ContractLoader.LoadJson("assist-cases.json")["openInObsidian"]!;

    [Fact]
    public void EveryAcceptedSentenceOpensThePageWithNoArguments()
    {
        var accepted = Block["accepted"]!.AsArray().Select(node => node!.ToString()).ToList();
        Assert.NotEmpty(accepted);
        foreach (string sentence in accepted)
        {
            var matched = AssistCardCommand.Matching(sentence);
            Assert.True(matched is not null, $"\"{sentence}\" is accepted by the contract and matches nothing here.");
            Assert.Equal("open_in_obsidian", matched!.ToolName);
            Assert.Empty(matched.Arguments);
        }
    }

    [Fact]
    public void NoNearMissOrRecordedOnlySentenceReachesIt()
    {
        var sentences = Block["nearMisses"]!.AsArray().Concat(Block["recordedOnly"]!.AsArray())
            .Select(node => node!.ToString()).ToList();
        Assert.NotEmpty(sentences);
        foreach (string sentence in sentences)
        {
            var matched = AssistCardCommand.Matching(sentence);
            Assert.True(matched?.ToolName != "open_in_obsidian",
                $"\"{sentence}\" must not reach open_in_obsidian (the contract's near miss), and does here.");
        }
    }

    /// <summary>The tool is not on the local model's list (#690 owes 3): only the fixed shapes reach it.</summary>
    [Fact]
    public void TheLocalModelIsNotShownIt() =>
        Assert.DoesNotContain("open_in_obsidian", AssistAgent.ForTheLocalModel);
}
