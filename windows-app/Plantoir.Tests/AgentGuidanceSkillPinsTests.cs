using System.Text;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using Plantoir.Core.Models;

namespace Plantoir.Tests;

/// <summary>
/// The guidance skills say what the contract pins (#794, #795, #796, #798;
/// the mac's <c>PrintablePagesTests</c> twins, names kept). Every phrase,
/// skill name, starter, macro, template and name is read from
/// <c>shared-rules.json</c> at run time; nothing here retypes one. Each test
/// checks what <see cref="AgentGuidance.Write"/> puts in a working folder, in
/// both homes, after a real pass into this class's temporary folder, never
/// the source under <c>support\</c>. A separate file from
/// <c>AgentGuidanceTests.cs</c>, sharing its fixtures, so another branch can
/// change that file at the same time.
/// </summary>
public partial class AgentGuidanceTests
{
    private static JsonNode AssessmentGuidance =>
        ContractLoader.LoadJson("shared-rules.json")["assessment"]!["agentGuidance"]!;

    /// <summary>
    /// Every run of white space, a line break included, as one space
    /// (<c>mustSay.rule</c>), so re-wrapping a paragraph never breaks a pin.
    /// The mac's <c>foldingWhiteSpace</c>, its pattern copied.
    /// </summary>
    private static string FoldingWhiteSpace(string text) =>
        Regex.Replace(text, @"\s+", " ");

    /// <summary>
    /// The same, with the <c>&gt;</c> marks that begin a callout's or a
    /// quote's lines dropped as well, so a sentence wrapped inside
    /// <c>&gt; </c> lines is found. The mac's
    /// <c>foldingWhiteSpaceAndQuoteMarks</c>, its pattern copied.
    /// </summary>
    private static string FoldingWhiteSpaceAndQuoteMarks(string text)
    {
        string joined = Regex.Replace(text, @"\s*\n[ \t]*(?:>[ \t]*)*", " ");
        return FoldingWhiteSpace(joined);
    }

    /// <summary>Either folded form of the file holding the folded phrase is a match (<c>mustSay.rule</c>).</summary>
    private static bool Says(string file, string phrase)
    {
        string wanted = FoldingWhiteSpace(phrase);
        if (FoldingWhiteSpace(file).Contains(wanted, StringComparison.Ordinal))
            return true;
        return FoldingWhiteSpaceAndQuoteMarks(file).Contains(wanted, StringComparison.Ordinal);
    }

    /// <summary>How many times <paramref name="wanted"/> occurs, without overlap, as the mac counts it.</summary>
    private static int TimesFound(string text, string wanted)
    {
        int times = 0;
        int from = 0;
        while (true)
        {
            int at = text.IndexOf(wanted, from, StringComparison.Ordinal);
            if (at < 0)
                return times;
            times += 1;
            from = at + wanted.Length;
        }
    }

    private static List<string> TextsIn(JsonNode list)
    {
        var texts = new List<string>();
        foreach (JsonNode? item in list.AsArray())
            texts.Add(item!.ToString());
        return texts;
    }

    private static string ReadUtf8(string path) => File.ReadAllText(path, new UTF8Encoding(false));

    private string WrittenPath(string home, string skillName, string relativePath) =>
        Path.Combine(_folder, home, "skills", skillName, relativePath.Replace('/', Path.DirectorySeparatorChar));

    /// <summary>
    /// The matching rule itself, on literal text, so it is proved and not
    /// assumed: a phrase wrapped across a CRLF line break matches by the
    /// first form; one wrapped inside <c>&gt; </c> quote lines matches only
    /// by the second; a phrase with a word changed matches by neither.
    /// </summary>
    [Theory]
    [InlineData("Keep the river\r\nwide and slow.", "the river wide and slow", true, true)]
    [InlineData("> Keep the river\r\n> wide and slow.", "the river wide and slow", false, true)]
    [InlineData("> Keep the river\n>> wide and slow.", "the river wide and slow", false, true)]
    [InlineData("Keep the river\r\nwide and slow.", "the river deep and slow", false, false)]
    public void APhraseIsMatchedAsMustSaysRuleSays(string file, string phrase, bool firstForm, bool secondForm)
    {
        string wanted = FoldingWhiteSpace(phrase);
        Assert.Equal(firstForm, FoldingWhiteSpace(file).Contains(wanted, StringComparison.Ordinal));
        Assert.Equal(secondForm, FoldingWhiteSpaceAndQuoteMarks(file).Contains(wanted, StringComparison.Ordinal));
        Assert.Equal(firstForm || secondForm, Says(file, phrase));
    }

    /// <summary>
    /// The walk behind <see cref="EverySkillSaysWhatTheContractSaysItMust"/>:
    /// every problem found in the written folder, one line each, and how many
    /// skills had their phrases checked. A held skill must not be written; any
    /// other key must name a skill written in both homes whose SKILL.md says
    /// every phrase; a key that names nothing written is a problem, never a
    /// pass on nothing.
    /// </summary>
    private List<string> WhatTheWrittenSkillsDoNotSay(JsonObject mustSay, JsonObject heldSkills, out int pinnedSkills)
    {
        var problems = new List<string>();
        pinnedSkills = 0;
        foreach (KeyValuePair<string, JsonNode?> entry in mustSay)
        {
            string skillName = entry.Key;
            if (skillName == "rule")
                continue;
            if (heldSkills.ContainsKey(skillName))
            {
                // Held (#750, #894): its pins are checked against its kept
                // folder by its own Python tests; here it must not be written.
                foreach (string home in AgentGuidance.SkillHomes)
                {
                    if (File.Exists(WrittenPath(home, skillName, "SKILL.md")))
                        problems.Add($"{home}: {skillName} is held, and it is written");
                }
                continue;
            }
            if (entry.Value is not JsonArray phraseList)
            {
                problems.Add($"{skillName} must be a list of phrases");
                continue;
            }
            List<string> phrases = TextsIn(phraseList);
            if (phrases.Count == 0)
            {
                problems.Add($"{skillName} pins no phrase");
                continue;
            }
            pinnedSkills += 1;
            foreach (string home in AgentGuidance.SkillHomes)
            {
                string file = WrittenPath(home, skillName, "SKILL.md");
                if (!File.Exists(file))
                {
                    problems.Add($"{home}: mustSay names {skillName}, and no such skill is written");
                    continue;
                }
                string skill = ReadUtf8(file);
                foreach (string phrase in phrases)
                {
                    if (!Says(skill, phrase))
                        problems.Add($"{home}: {skillName} must say {phrase}");
                }
            }
        }
        return problems;
    }

    /// <summary>
    /// #794 (the mac's <c>PrintablePagesTests.testEverySkillSaysWhatTheContractSaysItMust</c>,
    /// #758): after one pass, every key of
    /// <c>printablePages.agentGuidance.mustSay</c> but <c>rule</c> names a
    /// skill written in both homes whose SKILL.md says each phrase, matched
    /// as <c>mustSay.rule</c> says; a held skill is written in neither home.
    /// </summary>
    [Fact]
    public void EverySkillSaysWhatTheContractSaysItMust()
    {
        JsonObject mustSay = Contract["mustSay"]!.AsObject();
        JsonObject heldSkills = Contract["held"]!["skills"]!.AsObject();
        Assert.Empty(Pass().Failures);

        List<string> problems = WhatTheWrittenSkillsDoNotSay(mustSay, heldSkills, out int pinnedSkills);

        Assert.True(problems.Count == 0, string.Join("\n", problems));
        Assert.True(pinnedSkills > 0, "mustSay pins no skill at all");
    }
}
