using System.Collections.Generic;
using System.Linq;
using System.Text.Json.Nodes;
using Plantoir.Core.Models;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// Pointing qualified links at a folder's new name.
///
/// <para>The "must NOT change" half is the important one: a rewriter that
/// matched substrings would rename folders the teacher never touched, and one
/// that was blind to web addresses would repoint a link at somebody else's
/// website.</para>
/// </summary>
public class FolderPathRewriterTests
{
    private static string Rewrite(string text) => FolderPathRewriter.Rewritten(text, "Tasks", "Assignments");

    // ------------------------------------------------ what must be rewritten

    [Fact]
    public void AQualifiedWikiLinkFollowsTheFolder()
    {
        Assert.Equal("[[Assignments/Quiz 1]]", Rewrite("[[Tasks/Quiz 1]]"));
    }

    [Fact]
    public void ATransclusionFollowsTheFolder()
    {
        Assert.Equal("![[Assignments/diagram.png]]", Rewrite("![[Tasks/diagram.png]]"));
    }

    [Fact]
    public void AFolderDeepInAPathIsFound()
    {
        // A full vault path: ANY segment is a candidate, not only the first.
        Assert.Equal("[[ICS3U/section1/Assignments/Quiz 1]]",
                     Rewrite("[[ICS3U/section1/Tasks/Quiz 1]]"));
    }

    [Fact]
    public void AnAliasAndAHeadingAreLeftAlone()
    {
        // Both are the teacher's own words.
        Assert.Equal("[[Assignments/Quiz 1#Marking|the quiz]]",
                     Rewrite("[[Tasks/Quiz 1#Marking|the quiz]]"));
    }

    [Fact]
    public void AMarkdownLinkFollowsTheFolder()
    {
        Assert.Equal("[the quiz](Assignments/Quiz 1.md)", Rewrite("[the quiz](Tasks/Quiz 1.md)"));
        Assert.Equal("![](Assignments/diagram.png)", Rewrite("![](Tasks/diagram.png)"));
    }

    [Fact]
    public void APercentEncodedSegmentStaysEncoded()
    {
        // Obsidian writes Markdown links percent-encoded; handing it back a
        // decoded path would give it a link it cannot follow.
        Assert.Equal("[q](All%20Assignments/Quiz%201.md)",
                     FolderPathRewriter.Rewritten("[q](All%20Tasks/Quiz%201.md)", "All Tasks", "All Assignments"));
    }

    [Fact]
    public void ARelativePathIsStillRewritten()
    {
        Assert.Equal("[q](./Assignments/Quiz 1.md)", Rewrite("[q](./Tasks/Quiz 1.md)"));
    }

    [Fact]
    public void MatchingIgnoresCase()
    {
        // Windows filesystems are case-insensitive but case-preserving, so a
        // link written "tasks/" names the same folder.
        Assert.Equal("[[Assignments/Quiz 1]]", Rewrite("[[tasks/Quiz 1]]"));
    }

    // -------------------------------------------- what must NOT be rewritten

    [Fact]
    public void ABarePageLinkIsUntouched()
    {
        // The fact that makes this feature safe: Obsidian resolves a bare link
        // by searching the vault, so moving the folder leaves it working.
        Assert.Equal("[[Quiz 1]]", Rewrite("[[Quiz 1]]"));
    }

    [Fact]
    public void APageNamedAfterTheFolderIsUntouched()
    {
        // The match stops before the last segment, so a FILE called Tasks.md
        // is never a candidate.
        Assert.Equal("[[Tasks]]", Rewrite("[[Tasks]]"));
        Assert.Equal("[[Unit 1/Tasks]]", Rewrite("[[Unit 1/Tasks]]"));
        Assert.Equal("[q](Unit 1/Tasks.md)", Rewrite("[q](Unit 1/Tasks.md)"));
    }

    [Fact]
    public void AFolderWhoseNameMerelyContainsTheOldOneIsUntouched()
    {
        Assert.Equal("[[Extra Tasks/Quiz 1]]", Rewrite("[[Extra Tasks/Quiz 1]]"));
        Assert.Equal("[[Tasks Archive/Quiz 1]]", Rewrite("[[Tasks Archive/Quiz 1]]"));
    }

    [Fact]
    public void PlainProseMentioningTheFolderIsUntouched()
    {
        Assert.Equal("Put your work in the Tasks folder, in Tasks/ if you like.",
                     Rewrite("Put your work in the Tasks folder, in Tasks/ if you like."));
    }

    [Fact]
    public void AWebAddressIsNeverRewritten()
    {
        // The one that was got wrong on the mac: `Tasks` sits in this URL as an
        // ordinary segment, and the walk is blind to what a path MEANS.
        Assert.Equal("[handout](https://example.com/Tasks/handout.pdf)",
                     Rewrite("[handout](https://example.com/Tasks/handout.pdf)"));
    }

    [Fact]
    public void OtherSchemesAreLeftAloneToo()
    {
        Assert.Equal("[mail](mailto:someone@example.com/Tasks/x)",
                     Rewrite("[mail](mailto:someone@example.com/Tasks/x)"));
        Assert.Equal("[o](obsidian://open?vault=v&file=Tasks/Quiz)",
                     Rewrite("[o](obsidian://open?vault=v&file=Tasks/Quiz)"));
    }

    [Fact]
    public void AnAbsolutePathOnThisMachineIsNeverRewritten()
    {
        Assert.Equal(@"[x](C:/Users/teacher/Tasks/Quiz 1.md)", Rewrite(@"[x](C:/Users/teacher/Tasks/Quiz 1.md)"));
        Assert.Equal("[x](/Users/teacher/Tasks/Quiz 1.md)", Rewrite("[x](/Users/teacher/Tasks/Quiz 1.md)"));
    }

    [Fact]
    public void RenamingToTheSameNameChangesNothing()
    {
        Assert.Equal("[[Tasks/Quiz 1]]", FolderPathRewriter.Rewritten("[[Tasks/Quiz 1]]", "Tasks", "Tasks"));
    }

    [Fact]
    public void NothingAtAllIsNotACrash()
    {
        Assert.Equal("", FolderPathRewriter.Rewritten("", "Tasks", "Assignments"));
        Assert.Equal("x", FolderPathRewriter.Rewritten("x", "", "Assignments"));
        Assert.Equal("x", FolderPathRewriter.Rewritten("x", "Tasks", ""));
    }

    // ---------------------------------------------------------- the counting

    [Fact]
    public void CountingFindsOnlyQualifiedLinks()
    {
        string page = "[[Tasks/Quiz 1]] and [[Quiz 2]] and [q](Tasks/Quiz%203.md) and [[Extra Tasks/Q]]";
        Assert.Equal(2, FolderPathRewriter.Count(page, "Tasks"));
    }

    [Fact]
    public void CountingIsZeroWhenNothingPointsIn()
    {
        Assert.Equal(0, FolderPathRewriter.Count("[[Quiz 1]] and some prose about Tasks", "Tasks"));
        Assert.Equal(0, FolderPathRewriter.Count("", "Tasks"));
    }

    [Fact]
    public void CountingIgnoresTheWeb()
    {
        Assert.Equal(0, FolderPathRewriter.Count("[h](https://example.com/Tasks/handout.pdf)", "Tasks"));
    }

    // ------------------------------- how the new name is SPELLED (2026-09-06)
    //
    // The cases these five facts used to retype are now DESERIALISED from the
    // contract by the theory below, which is why three of them were failing
    // here and nothing said so: `Uri.EscapeDataString` over-encodes `&`, `,`,
    // `+`, `'`, `!` and `*`, and only the later cases exercise any of them. The
    // five stay as named regression anchors — the ones written when the
    // Markdown-destination defect was found, and that a reader looking for
    // "what broke" will search for by name — and
    // TheHandWrittenAnchorsStillMatchTheContract keeps them honest by asserting
    // that each one the contract also carries is still there.

    private static JsonNode LinkRewritingRules()
    {
        JsonNode root = ContractLoader.LoadJson("shared-rules.json");
        return root["specialNames"]!["renameFolder"]!["linkRewriting"]!;
    }

    public static TheoryData<string, string, string, string, string> ContractCases()
    {
        var data = new TheoryData<string, string, string, string, string>();
        foreach (JsonNode? entry in LinkRewritingRules()["cases"]!.AsArray())
        {
            data.Add(entry!["given"]!.ToString(),
                     entry["oldName"]!.ToString(),
                     entry["newName"]!.ToString(),
                     entry["expect"]!.ToString(),
                     entry["why"]?.ToString() ?? "");
        }
        return data;
    }

    /// <summary>
    /// Every case the contract carries, run rather than retyped.
    /// </summary>
    [Theory]
    [MemberData(nameof(ContractCases))]
    public void TheNewNameIsSpelledTheWayTheContractSays(
        string given, string oldName, string newName, string expect, string why)
    {
        Assert.Equal(expect, FolderPathRewriter.Rewritten(given, oldName, newName));
        Assert.False(string.IsNullOrWhiteSpace(why),
                     "Renaming “" + oldName + "” to “" + newName +
                     "” has no reason written down beside it");
    }

    /// <summary>
    /// The escaping set is MEASURED against Quartz rather than chosen, so the
    /// contract writes it down and this asserts the code carries the identical
    /// string. It is the check that catches a character quietly added to or
    /// dropped from the constant — no behavioural test can see that on its own,
    /// because a test walks the characters the CODE has.
    /// </summary>
    [Fact]
    public void TheEscapingSetIsTheContractsCharacterForCharacter()
    {
        Assert.Equal(LinkRewritingRules()["escapingSet"]!["leaveUnescaped"]!.ToString(),
                     FolderPathRewriter.CharactersThatSurviveQuartzUndecoded);
    }

    public static TheoryData<char> CharactersLeftUnescaped()
    {
        var data = new TheoryData<char>();
        foreach (char character in LinkRewritingRules()["escapingSet"]!["leaveUnescaped"]!.ToString())
            data.Add(character);
        return data;
    }

    /// <summary>
    /// A character the contract says survives untouched must come through a
    /// rename untouched.
    ///
    /// <para>The one that matters is <c>&amp;</c>. Quartz resolves an internal
    /// link with JavaScript's <c>decodeURI</c>, which leaves <c>%26</c> alone,
    /// and then slugs <c>&amp;</c> to <c>-and-</c> and <c>%</c> to
    /// <c>-percent</c> — so an over-encoded "Tasks &amp; Quizzes" 404s for
    /// students while looking perfectly healthy in Obsidian.</para>
    /// </summary>
    [Theory]
    [MemberData(nameof(CharactersLeftUnescaped))]
    public void ACharacterTheContractLeavesAloneSurvivesARename(char character)
    {
        // The space in "New " is what makes escaping run at all; the character
        // under test then has to come out the other side as itself.
        Assert.Equal("[q](New%20" + character + "/Quiz.md)",
                     FolderPathRewriter.Rewritten("[q](Tasks/Quiz.md)", "Tasks", "New " + character));
    }

    /// <summary>
    /// Anything the contract does NOT list is percent-encoded, and the point of
    /// encoding it is that Quartz gets the real name back.
    /// </summary>
    [Fact]
    public void ACharacterOutsideTheSetIsEncoded()
    {
        Assert.Equal("[q](Caf%C3%A9%20Notes/Quiz.md)",
                     FolderPathRewriter.Rewritten("[q](Tasks/Quiz.md)", "Tasks", "Café Notes"));
        Assert.Equal("[q](Unit%20%5B2%5D/Quiz.md)",
                     FolderPathRewriter.Rewritten("[q](Tasks/Quiz.md)", "Tasks", "Unit [2]"));
        // Encoded as UTF-8 BYTES, which is why the encoder walks bytes rather
        // than characters: a per-char loop splits a surrogate pair and writes
        // two invalid sequences for one letter.
        Assert.Equal("[q](New%20%F0%9F%8E%B5/Quiz.md)",
                     FolderPathRewriter.Rewritten("[q](Tasks/Quiz.md)", "Tasks", "New \U0001F3B5"));
    }

    /// <summary>
    /// A wikilink keeps the plain spelling whatever the name contains, which is
    /// the mirror-image mistake this rule has to avoid making.
    /// </summary>
    [Fact]
    public void AWikiLinkKeepsAPlainNameWhateverItContains()
    {
        Assert.Equal("[[Work(new)/Quiz 1]]",
                     FolderPathRewriter.Rewritten("[[Tasks/Quiz 1]]", "Tasks", "Work(new)"));
    }

    /// <summary>
    /// Rewriting the same page twice produces the same text, because a rename
    /// interrupted between the move and the settings write is resumed and
    /// re-runs the relinking pass over pages it may already have changed.
    /// </summary>
    [Fact]
    public void RelinkingTwiceChangesNothingTheSecondTime()
    {
        string once = FolderPathRewriter.Rewritten(
            "[q](Tasks/Quiz.md) and [[Tasks/Quiz 1]]", "Tasks", "All Tasks");
        Assert.Equal("[q](All%20Tasks/Quiz.md) and [[All Tasks/Quiz 1]]", once);
        Assert.Equal(once, FolderPathRewriter.Rewritten(once, "Tasks", "All Tasks"));
    }

    /// <summary>
    /// The completeness half. The theory above runs whatever the contract
    /// carries, so a case the mac ADDS cannot go unrun — but a case the mac
    /// CHANGES or drops would quietly leave one of the named anchors below
    /// guarding nothing, still passing, and no longer describing the shared
    /// rule. This names each anchor against the case it mirrors, ANSWER
    /// included — comparing inputs alone would miss a case whose expected
    /// text the mac changed.
    ///
    /// <para>Two of the anchors' assertions are deliberately absent from this
    /// map, and saying so is the point of writing it out. The wikilink half of
    /// APlainNewNameIsNotEscapedForNoReason, and the whole of
    /// AnAlreadyEncodedMarkdownSegmentStaysEncodedForAPlainNewName, are LOCAL
    /// regression tests with no contract case behind them — the second is the
    /// only test here of "an encoded FILE name beside a plain new folder name",
    /// which is the shape that made the original defect hard to see by eye.</para>
    /// </summary>
    [Fact]
    public void TheHandWrittenAnchorsStillMatchTheContract()
    {
        var anchors = new Dictionary<string, (string Given, string Old, string New, string Expect)>
        {
            ["ANewNameWithASpaceIsEscapedInAMarkdownLink (encoded file name)"] =
                ("[q](Tasks/Quiz%201.md)", "Tasks", "All Tasks", "[q](All%20Tasks/Quiz%201.md)"),
            ["ANewNameWithASpaceIsEscapedInAMarkdownLink (plain file name)"] =
                ("[q](Tasks/Quiz.md)", "Tasks", "All Tasks", "[q](All%20Tasks/Quiz.md)"),
            ["BracketsInANewNameAreEscapedInAMarkdownLinkToo"] =
                ("[q](Tasks/Quiz.md)", "Tasks", "Work(new)", "[q](Work%28new%29/Quiz.md)"),
            ["AWikiLinkKeepsTheSpaceRatherThanEscapingIt"] =
                ("[[Tasks/Quiz 1]]", "Tasks", "All Tasks", "[[All Tasks/Quiz 1]]"),
            ["APlainNewNameIsNotEscapedForNoReason (Markdown half)"] =
                ("[q](Tasks/Quiz.md)", "Tasks", "Assignments", "[q](Assignments/Quiz.md)"),
        };

        // The EXPECTED text is part of the comparison, not just the inputs. A
        // mac that changed a case's answer while keeping its inputs would leave
        // the anchor passing and quietly contradicting the contract — the
        // theory above would fail, but the anchor is what a reader trusts.
        List<(string Given, string Old, string New, string Expect)> carried = LinkRewritingRules()["cases"]!
            .AsArray()
            .Select(entry => (entry!["given"]!.ToString(),
                              entry["oldName"]!.ToString(),
                              entry["newName"]!.ToString(),
                              entry["expect"]!.ToString()))
            .ToList();

        foreach (KeyValuePair<string, (string Given, string Old, string New, string Expect)> anchor in anchors)
            Assert.True(carried.Contains(anchor.Value),
                        anchor.Key + " guards a case the contract no longer carries as written: " +
                        anchor.Value.Given + " — “" + anchor.Value.Old +
                        "” to “" + anchor.Value.New + "”, expecting " + anchor.Value.Expect);
    }

    // --------------------- the anchors themselves, kept by name (2026-09-06)

    [Fact]
    public void ANewNameWithASpaceIsEscapedInAMarkdownLink()
    {
        // A Markdown destination ends at the first SPACE — the pattern is
        // literally [^)\s]+ — so this rename used to produce
        // "[q](All Tasks/Quiz%201.md)", which neither Obsidian nor Quartz can
        // follow. It broke every Markdown-style link into the folder, in a
        // teacher's own pages, and said nothing.
        Assert.Equal("[q](All%20Tasks/Quiz%201.md)",
                     FolderPathRewriter.Rewritten("[q](Tasks/Quiz%201.md)", "Tasks", "All Tasks"));
        // ...and the same when the old segment was NOT encoded: what decides
        // it is what the NEW name needs, not what the old one looked like.
        Assert.Equal("[q](All%20Tasks/Quiz.md)",
                     FolderPathRewriter.Rewritten("[q](Tasks/Quiz.md)", "Tasks", "All Tasks"));
    }

    [Fact]
    public void BracketsInANewNameAreEscapedInAMarkdownLinkToo()
    {
        // A closing bracket would end the destination just as a space does.
        Assert.Equal("[q](Work%28new%29/Quiz.md)",
                     FolderPathRewriter.Rewritten("[q](Tasks/Quiz.md)", "Tasks", "Work(new)"));
    }

    [Fact]
    public void AWikiLinkKeepsTheSpaceRatherThanEscapingIt()
    {
        // The mirror-image mistake. "[[All Tasks/Quiz 1]]" is exactly how
        // Obsidian writes a wikilink with a space in it; escaping there would
        // hand it a link it cannot follow.
        Assert.Equal("[[All Tasks/Quiz 1]]",
                     FolderPathRewriter.Rewritten("[[Tasks/Quiz 1]]", "Tasks", "All Tasks"));
    }

    [Fact]
    public void APlainNewNameIsNotEscapedForNoReason()
    {
        // Escaping everything would be safe and unreadable. A name that needs
        // nothing keeps its plain spelling.
        Assert.Equal("[q](Assignments/Quiz.md)",
                     FolderPathRewriter.Rewritten("[q](Tasks/Quiz.md)", "Tasks", "Assignments"));
        Assert.Equal("[[Assignments/Quiz 1]]",
                     FolderPathRewriter.Rewritten("[[Tasks/Quiz 1]]", "Tasks", "Assignments"));
    }

    [Fact]
    public void AnAlreadyEncodedMarkdownSegmentStaysEncodedForAPlainNewName()
    {
        // The original rule, still right for this case — and the shape that
        // made the defect hard to see: the %20 belongs to the FILE name, so the
        // folder segment "Tasks" was never encoded at all.
        Assert.Equal("[q](Assignments/Quiz%201.md)",
                     FolderPathRewriter.Rewritten("[q](Tasks/Quiz%201.md)", "Tasks", "Assignments"));
    }
}
