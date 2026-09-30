using System;
using System.IO;
using System.Linq;
using System.Text.Json.Nodes;
using Plantoir.Core.Models;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// #358 (mac #330): the '— Edited' fingerprint's rule 2, against
/// <c>app-rules.json → publishedFreshness</c>: <c>fingerprintRules</c>,
/// <c>filesCountedUnderRule2.cases</c> (8) and <c>stampRuleCases.cases</c> (6).
/// </summary>
public class FingerprintRuleTests
{
    private static JsonNode Freshness => ContractLoader.LoadJson("app-rules.json")["publishedFreshness"]!;

    [Fact]
    public void TheRulesAreTheContracts()
    {
        var rules = Freshness["fingerprintRules"]!;
        Assert.Equal(rules["current"]!.GetValue<int>(), SectionPublishState.CurrentRule);
        Assert.Equal(rules["absentMeans"]!.GetValue<int>(), SectionPublishState.RuleWhenAbsent);
        Assert.Equal("edited", rules["unknownMeans"]!.ToString());
        Assert.Equal("fingerprintRule", rules["stampField"]!.ToString());
    }

    [Fact]
    public void EveryRule2FileCaseCountsAsTheContractSays()
    {
        var block = Freshness["filesCountedUnderRule2"]!;
        int section = block["sectionNumber"]!.GetValue<int>();
        foreach (var c in block["cases"]!.AsArray())
            Assert.True(SectionPublishState.CountsTowardFingerprint(c!["path"]!.ToString(), section, rule: 2) ==
                        c["counts"]!.GetValue<bool>(), c["path"]!.ToString());
    }

    [Fact]
    public void EveryStampRuleCaseIsEditedOrNotAsTheContractSays()
    {
        foreach (var c in Freshness["stampRuleCases"]!["cases"]!.AsArray())
        {
            string name = c!["name"]!.ToString();
            string course = Directory.CreateTempSubdirectory("fingerprint-rule-").FullName;
            try
            {
                Directory.CreateDirectory(Path.Combine(course, "Unit 1"));
                File.WriteAllText(Path.Combine(course, "Unit 1", "Lesson.md"), "# lesson");
                bool withPage = c["withoutTheHowITeachPage"]?.GetValue<bool>() != true;
                if (withPage) File.WriteAllText(Path.Combine(course, "How I Teach.md"), "# how I teach");

                if (c["sameUnderBothRules"]?.GetValue<bool>() == true)
                {
                    Assert.True(SectionPublishState.Fingerprint(course, 1, rule: 1) ==
                                SectionPublishState.Fingerprint(course, 1, rule: 2), name);
                    continue;
                }

                int? stampRule = c["stampRule"] is JsonValue v ? v.GetValue<int>() : null;
                int computedUnder = stampRule is null or 1 ? 1 : 2;   // an unknown rule: a value that WOULD match under rule 2, so only the refusal makes it edited
                string fingerprint = SectionPublishState.Fingerprint(course, 1, rule: computedUnder);
                Assert.True(SectionPublishState.RecordPublish(course, 1, fingerprint, new[] { "netlify" }), name);
                // Write the stamp's rule exactly as the case says: absent, known or unknown.
                string stampPath = SectionPublishState.StampPath(course, 1);
                var stamp = JsonNode.Parse(File.ReadAllText(stampPath))!.AsObject();
                stamp.Remove("fingerprintRule");
                if (stampRule is not null) stamp["fingerprintRule"] = stampRule.Value;
                File.WriteAllText(stampPath, stamp.ToJsonString());

                string change = c["change"]!.ToString();
                string changed = change == "howITeachPage" ? Path.Combine(course, "How I Teach.md")
                               : change == "lesson" ? Path.Combine(course, "Unit 1", "Lesson.md") : "";
                if (changed.Length > 0)
                {
                    File.WriteAllText(changed, "# rewritten with different bytes, and longer");
                    File.SetLastWriteTimeUtc(changed, DateTime.UtcNow.AddMinutes(1));
                }
                Assert.True(SectionPublishState.HasUnpublishedEdits(course, 1) == c["expectEdited"]!.GetValue<bool>(), name);
            }
            finally { try { Directory.Delete(course, recursive: true); } catch { } }
        }
    }

    [Fact]
    public void ANewStampRecordsTheCurrentRule()
    {
        string course = Directory.CreateTempSubdirectory("fingerprint-rule-").FullName;
        try
        {
            SectionPublishState.RecordPublish(course, 1, "abc", new[] { "netlify" });
            Assert.Equal(SectionPublishState.CurrentRule, SectionPublishState.ReadStamp(course, 1)!.FingerprintRule);
        }
        finally { try { Directory.Delete(course, recursive: true); } catch { } }
    }
}

/// <summary>
/// #357 (mac #343): a re-date's reply counts what was WRITTEN, and says one of
/// three sentences (class-planning.json → reDatingASection.reportedCounts).
/// </summary>
public class ReDateReplyTests
{
    [Fact]
    public void TheThreeSentencesAreTheContracts()
    {
        var wording = ContractLoader.LoadJson("assist-wording.json")["wording"]!;
        Assert.Equal(wording["reDated"]!.ToString(), Plantoir.Core.Assist.AssistWording.ReDated(12, 5));
        Assert.Equal(wording["reDatedOnlyPagesTheyUse"]!.ToString(), Plantoir.Core.Assist.AssistWording.ReDatedOnlyPagesTheyUse(3));
        Assert.Equal(wording["everyPageIsAlreadyOnItsDay"]!.ToString(), Plantoir.Core.Assist.AssistWording.EveryPageIsAlreadyOnItsDay("ICS3U", "1"));
    }

    [Fact]
    public void EachCaseSaysTheSentenceItsCountsCallFor()
    {
        var cases = ContractLoader.LoadJson("class-planning.json")["reDatingASection"]!["reportedCounts"]!["cases"]!.AsArray();
        foreach (var c in cases)
        {
            var expect = c!["expect"]!;
            int classes = expect["classesReDated"]!.GetValue<int>(), pages = expect["pagesTheyUseReDated"]!.GetValue<int>();
            string key = expect["sentence"]!.ToString();
            string said = Plantoir.Core.Assist.AssistWording.ReDatedSummary("ICS3U", "1", classes, pages);
            string want = key switch
            {
                "reDated" => Plantoir.Core.Assist.AssistWording.ReDated(classes, pages),
                "reDatedOnlyPagesTheyUse" => Plantoir.Core.Assist.AssistWording.ReDatedOnlyPagesTheyUse(pages),
                _ => Plantoir.Core.Assist.AssistWording.EveryPageIsAlreadyOnItsDay("ICS3U", "1"),
            };
            Assert.True(want == said, c["name"]!.ToString());
            Assert.DoesNotContain("-", said.Replace("Re-dated", "").Replace("re-dated", ""));
        }
    }
}
