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
}
