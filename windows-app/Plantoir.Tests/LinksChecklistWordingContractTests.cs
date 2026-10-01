using System.Reflection;
using Plantoir.Core.Assist;
using Xunit;

namespace Plantoir.Tests;

/// <summary>shared-rules.json → linksChecklist.wording, key by key, and its machineryCheck (#392).</summary>
public class LinksChecklistWordingContractTests
{
    private static readonly string[] NotSentences = { "fill", "machineryCheck" };

    [Fact]
    public void EveryKeyIsAMemberWithTheContractsWords()
    {
        var wording = ContractLoader.LoadJson("shared-rules.json")!["linksChecklist"]!["wording"]!.AsObject();
        var members = typeof(LinksChecklistWording).GetFields(BindingFlags.Public | BindingFlags.Static)
            .ToDictionary(f => f.Name, f => (string)f.GetValue(null)!);
        foreach (var (key, value) in wording)
        {
            if (NotSentences.Contains(key)) continue;
            string name = char.ToUpperInvariant(key[0]) + key[1..];
            Assert.True(members.ContainsKey(name), $"linksChecklist.wording.{key} has no member here.");
            Assert.Equal(value!.ToString(), members[name]);
        }
        Assert.Equal(wording.Count - NotSentences.Length, members.Count);
    }

    [Fact]
    public void NoSentenceNamesTheMachinery()
    {
        string[] machinery = { "file", "script", "build step", "walk", "frontmatter", "link graph", "offer", "json", "marker" };
        foreach (var field in typeof(LinksChecklistWording).GetFields(BindingFlags.Public | BindingFlags.Static))
        {
            string sentence = ((string)field.GetValue(null)!).ToLowerInvariant();
            foreach (string word in machinery)
                Assert.False(System.Text.RegularExpressions.Regex.IsMatch(sentence, $@"\b{word}\b"),
                    $"{field.Name} names the machinery (“{word}”).");
        }
    }

    [Fact]
    public void FillFillsEveryValueInOnePass()
    {
        string said = LinksChecklistWording.Fill(LinksChecklistWording.PublishButton,
            new Dictionary<string, string> { ["count"] = "{pages}", ["pages"] = LinksChecklistWording.Pages(2) });
        Assert.Equal("Publish {pages} pages", said);
    }
}
