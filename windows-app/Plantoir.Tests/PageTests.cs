using Plantoir.Core.Models;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// The page-level logic the MCP server stands on: which draft key governs a
/// page, editing that key without disturbing the teacher's file, and working
/// out what a class page links to.
/// </summary>
public class PageFrontmatterTests
{
    // ---- Which key governs the page -------------------------------------

    [Fact]
    public void ASectionLocalPageUsesThePlainPublishKey()
    {
        // A page under section1/ belongs to one section, so "publish" is
        // unambiguous — this is how All Classes pages are written.
        Assert.Equal("publish", PageFrontmatter.PublishKeyFor(1, isSectionLocal: true));
    }

    [Fact]
    public void ASharedPageUsesThePerSectionPublishKey()
    {
        // Concepts/ is copied into every section, so unpublishing it in
        // section 2 must not unpublish it in section 1.
        Assert.Equal("publishForSection2", PageFrontmatter.PublishKeyFor(2, isSectionLocal: false));
    }

    // ---- Reading a course that predates the change -----------------------

    [Fact]
    public void APageStillOnTheOldDraftKeyIsReadInverted()
    {
        // Courses written before the change keep working. build_site.py reads
        // the old keys too, so nothing has to be converted before it builds.
        Assert.True(PageFrontmatter.IsDraft("---\ndraft: true\n---\nbody\n", 1));
        Assert.False(PageFrontmatter.IsDraft("---\ndraft: false\n---\nbody\n", 1));
        Assert.True(PageFrontmatter.IsDraft("---\ndraftSection2: true\n---\nbody\n", 2));
    }

    [Fact]
    public void ThePublishKeyWinsOverALeftoverDraftKey()
    {
        // A page carrying both has already been migrated; the leftover must
        // not contradict the answer that replaced it.
        Assert.False(PageFrontmatter.IsDraft("---\ndraft: true\npublish: true\n---\nbody\n", 1));
    }

    [Fact]
    public void WritingVisibilityMigratesThePageAndDropsTheOldKey()
    {
        // Migration happens a page at a time, as things are touched — no
        // sweep, no flag day.
        var (text, edit) = PageFrontmatter.SetDraft(
            "---\ndraft: true\ntags:\n  - unit-1\n---\nbody\n", "publish", draft: false, sectionNumber: 1);

        Assert.Equal("---\npublish: true\ntags:\n  - unit-1\n---\nbody\n", text);
        Assert.True(edit.Changed);
    }

    [Fact]
    public void MigratingAPerSectionPageDropsOnlyItsOwnOldKey()
    {
        var (text, _) = PageFrontmatter.SetDraft(
            "---\ndraftSection1: true\ndraftSection2: false\n---\nbody\n",
            "publishForSection1", draft: false, sectionNumber: 1);

        Assert.Contains("publishForSection1: true", text);
        Assert.DoesNotContain("draftSection1", text);
        Assert.Contains("draftSection2: false", text);   // section 2 is not this call's business
    }

    // ---- Reading the effective state ------------------------------------

    [Fact]
    public void ThePerSectionKeyWinsOverThePlainOne()
    {
        // Matches process_frontmatter in build_site.py, which copies
        // draftSectionN over draft for the section being built.
        string page = "---\ndraft: false\ndraftSection2: true\n---\nbody\n";
        Assert.False(PageFrontmatter.IsDraft(page, 1));
        Assert.True(PageFrontmatter.IsDraft(page, 2));
    }

    [Fact]
    public void APageWithNoDraftKeyIsPublished()
    {
        Assert.False(PageFrontmatter.IsDraft("---\ntags:\n  - unit-1\n---\nbody\n", 1));
    }

    [Fact]
    public void APageWithNoFrontmatterIsPublished()
    {
        Assert.False(PageFrontmatter.IsDraft("Just a body, no frontmatter.\n", 1));
    }

    [Fact]
    public void AnIndentedDraftKeyIsNotThePagesOwnFlag()
    {
        // "draft:" nested under another mapping describes that mapping, not
        // the page. Reading it would report the wrong state; writing it would
        // change something else entirely.
        string page = "---\nreview:\n  draft: true\n---\nbody\n";
        Assert.False(PageFrontmatter.IsDraft(page, 1));
    }

    [Fact]
    public void AnUnterminatedBlockIsNotTreatedAsFrontmatter()
    {
        // Refuse to guess where the block ends rather than edit a body line.
        Assert.False(PageFrontmatter.IsDraft("---\ndraft: true\nbody with no closing fence\n", 1));
    }

    // ---- Editing ---------------------------------------------------------

    [Fact]
    public void SettingDraftLeavesEveryOtherLineByteForByte()
    {
        string page = "---\ncreatedSection1: 2026-11-20T08:00:00.000-0500\n" +
                      "draftSection1: false\nenableToc: true\ntags:\n  - physics\n---\n## The idea\n";
        var (text, edit) = PageFrontmatter.SetDraft(page, "publishForSection1", draft: true, sectionNumber: 1);

        // The new key takes the old one's PLACE, so the teacher's frontmatter
        // keeps its order — a reordered diff in a file Obsidian has open is
        // exactly the noise this class exists to avoid.
        Assert.Equal(
            "---\ncreatedSection1: 2026-11-20T08:00:00.000-0500\n" +
            "publishForSection1: false\nenableToc: true\ntags:\n  - physics\n---\n## The idea\n",
            text);
        Assert.True(edit.Changed);
        Assert.Equal(false, edit.Before);
        Assert.True(edit.After);
    }

    [Fact]
    public void SettingTheValueItAlreadyHasChangesNothing()
    {
        // The confirmation panel needs to be able to say "already published"
        // rather than proposing a no-op write.
        string page = "---\npublish: true\n---\nbody\n";
        var (text, edit) = PageFrontmatter.SetDraft(page, "publish", draft: false, sectionNumber: 1);
        Assert.Equal(page, text);
        Assert.False(edit.Changed);
        Assert.Equal("“Ohm’s Law” is already published", edit.Describe("Ohm’s Law"));
    }

    [Fact]
    public void AMissingKeyIsInsertedAtTheTopOfTheBlock()
    {
        // The top can never land inside a nested list or block scalar.
        string page = "---\ntags:\n  - unit-1\n---\nbody\n";
        var (text, edit) = PageFrontmatter.SetDraft(page, "publishForSection1", draft: true, sectionNumber: 1);
        Assert.Equal("---\npublishForSection1: false\ntags:\n  - unit-1\n---\nbody\n", text);
        Assert.Null(edit.Before);
    }

    [Fact]
    public void APageWithNoFrontmatterGetsABlockAndKeepsItsBody()
    {
        var (text, _) = PageFrontmatter.SetDraft("## Agenda\n\n1. Something\n", "publish", draft: true, sectionNumber: 1);
        Assert.Equal("---\npublish: false\n---\n## Agenda\n\n1. Something\n", text);
    }

    [Fact]
    public void ACommentAfterTheValueSurvives()
    {
        var (text, _) = PageFrontmatter.SetDraft(
            "---\npublish: true  # not ready yet\n---\nbody\n", "publish", draft: true, sectionNumber: 1);
        Assert.Equal("---\npublish: false # not ready yet\n---\nbody\n", text);
    }

    [Fact]
    public void EditingACrlfFileKeepsCrlfOnEveryLine()
    {
        // Obsidian has these files open; converting line endings would show up
        // as an all-lines-changed diff in the teacher's vault.
        string page = "---\r\npublish: true\r\ntags:\r\n  - unit-1\r\n---\r\nbody\r\n";
        var (text, _) = PageFrontmatter.SetDraft(page, "publish", draft: true, sectionNumber: 1);
        Assert.Equal("---\r\npublish: false\r\ntags:\r\n  - unit-1\r\n---\r\nbody\r\n", text);
        // No line may have been left with a bare LF.
        Assert.Equal(text.Split('\n').Length - 1, text.Split("\r\n").Length - 1);
    }

    [Fact]
    public void InsertingIntoACrlfFileUsesCrlfForTheNewLineToo()
    {
        string page = "---\r\ntags:\r\n  - unit-1\r\n---\r\nbody\r\n";
        var (text, _) = PageFrontmatter.SetDraft(page, "publishForSection1", draft: true, sectionNumber: 1);
        Assert.Equal("---\r\npublishForSection1: false\r\ntags:\r\n  - unit-1\r\n---\r\nbody\r\n", text);
    }

    [Fact]
    public void StoredValueTellsAbsentApartFromFalse()
    {
        Assert.Null(PageFrontmatter.StoredValue("---\ntags: []\n---\n", "draft"));
        Assert.Equal(false, PageFrontmatter.StoredValue("---\ndraft: false\n---\n", "draft"));
    }
}

public class PagePathTests : IDisposable
{
    private readonly string _root = Directory.CreateTempSubdirectory("plantoir-paths").FullName;

    public void Dispose()
    {
        try { Directory.Delete(_root, recursive: true); } catch { }
        GC.SuppressFinalize(this);
    }

    [Fact]
    public void APathInsideTheFolderResolves()
    {
        string page = PagePaths.ResolveInside(_root, "courses/ICS3U/section1/index.md");
        Assert.True(PagePaths.Contains(_root, page));
    }

    [Fact]
    public void ATraversalOutOfTheFolderIsRefused()
    {
        // The whole point of the server being locked to one folder.
        var refusal = Assert.Throws<OutsideWorkspaceException>(
            () => PagePaths.ResolveInside(_root, "courses/../../../Windows/System32/drivers/etc/hosts"));
        Assert.Equal("That path is outside this working folder, so it can’t be opened from here.",
            refusal.Message);
    }

    [Fact]
    public void AnAbsolutePathElsewhereIsRefused()
    {
        Assert.Throws<OutsideWorkspaceException>(
            () => PagePaths.ResolveInside(_root, OperatingSystem.IsWindows() ? @"C:\Windows\notepad.exe" : "/etc/hosts"));
    }

    [Fact]
    public void AnEmptyPathIsRefusedWithoutBlamingTheTeacher()
    {
        var refusal = Assert.Throws<OutsideWorkspaceException>(() => PagePaths.ResolveInside(_root, "  "));
        Assert.Equal("No page was named.", refusal.Message);
    }

    [Fact]
    public void ASiblingFolderWithASharedPrefixIsNotInside()
    {
        // "C:\work" must not appear to contain "C:\workshop".
        string sibling = _root + "shop";
        Assert.False(PagePaths.Contains(_root, sibling));
    }

    [Fact]
    public void SectionOfReadsTheLayoutRatherThanTheCaller()
    {
        string course = Path.Combine(_root, "courses", "ICS3U");
        Assert.Equal(2, PagePaths.SectionOf(course, Path.Combine(course, "section2", "All Classes", "Unit 1, Day 1.md")));
        Assert.Null(PagePaths.SectionOf(course, Path.Combine(course, "Concepts", "Ohm's Law.md")));
    }

    [Fact]
    public void BuildArtefactsAndOtherSectionsAreNotPages()
    {
        string course = Path.Combine(_root, "courses", "ICS3U");
        Write(course, "Concepts/Ohm's Law.md");
        Write(course, "section1/All Classes/Unit 1, Day 1.md");
        Write(course, "section2/All Classes/Unit 1, Day 1.md");
        Write(course, ".merged_output/section1/content/index.md");
        Write(course, ".obsidian/workspace.md");

        var pages = PagePaths.MarkdownPages(course, sectionNumber: 1);

        Assert.Contains(pages, p => p.EndsWith("Ohm's Law.md", StringComparison.Ordinal));
        Assert.Single(pages, p => p.EndsWith("Unit 1, Day 1.md", StringComparison.Ordinal));
        Assert.DoesNotContain(pages, p => p.Contains(".merged_output", StringComparison.Ordinal));
        Assert.DoesNotContain(pages, p => p.Contains(".obsidian", StringComparison.Ordinal));
    }

    private void Write(string course, string relative)
    {
        string full = Path.Combine(course, relative.Replace('/', Path.DirectorySeparatorChar));
        Directory.CreateDirectory(Path.GetDirectoryName(full)!);
        File.WriteAllText(full, "---\ndraft: false\n---\nbody\n");
    }
}

public class WikiLinkTests : IDisposable
{
    private readonly string _course = Directory.CreateTempSubdirectory("plantoir-links").FullName;

    public void Dispose()
    {
        try { Directory.Delete(_course, recursive: true); } catch { }
        GC.SuppressFinalize(this);
    }

    // ---- Parsing ---------------------------------------------------------

    [Fact]
    public void TheAgendaFormsAllParse()
    {
        // Taken from a real class page.
        string page = "## Agenda\n\n" +
                      "1. Discussion: [[What Counts as Evidence]]\n" +
                      "2. Concept: [[WHMIS and Lab Safety]] — pictograms\n" +
                      "3. Setup: [[Your Lab Notebook|your notebook]]\n" +
                      "4. ![[A Diagram]]\n" +
                      "5. [[Safety Contract#Signatures]]\n";
        var links = WikiLinks.Parse(page);

        Assert.Equal(5, links.Count);
        Assert.Equal("What Counts as Evidence", links[0].Target);
        Assert.Equal("your notebook", links[2].DisplayText);
        Assert.True(links[3].IsEmbed);
        Assert.Equal("Signatures", links[4].Heading);
        Assert.Equal("Safety Contract", links[4].Target);
    }

    [Fact]
    public void LinksInsideCodeAreNotLinks()
    {
        // A page explaining the syntax must not publish the pages it mentions.
        string page = "Write it like `[[Inline Example]]`.\n\n" +
                      "```\n[[Fenced Example]]\n```\n\n" +
                      "But [[Real Page]] counts.\n";
        var links = WikiLinks.Parse(page);
        Assert.Single(links);
        Assert.Equal("Real Page", links[0].Target);
    }

    // ---- Resolution ------------------------------------------------------

    [Fact]
    public void ABareNameResolvesAcrossTheCourse()
    {
        Write("Concepts/Ohm's Law.md");
        string classPage = Write("section1/All Classes/Unit 1, Day 2.md");

        var resolved = WikiLinks.Resolve(
            WikiLinks.Parse("Concept: [[Ohm's Law]]"), _course, 1, classPage);

        Assert.Single(resolved);
        Assert.Equal(LinkOutcome.Resolved, resolved[0].Outcome);
        Assert.EndsWith("Ohm's Law.md", resolved[0].Path!, StringComparison.Ordinal);
    }

    [Fact]
    public void AFullPathTargetResolvesToo()
    {
        Write("section1/All Classes/Thread 2, Day 8.md");
        var resolved = WikiLinks.Resolve(
            WikiLinks.Parse("[[section1/All Classes/Thread 2, Day 8|Thread 2, Day 8]]"), _course, 1);
        Assert.Equal(LinkOutcome.Resolved, resolved[0].Outcome);
    }

    [Fact]
    public void AnotherSectionsCopyIsNotAMatch()
    {
        // Resolving a section 1 class page must never reach into section 2.
        Write("section2/All Classes/Unit 9, Day 9.md");
        var resolved = WikiLinks.Resolve(WikiLinks.Parse("[[Unit 9, Day 9]]"), _course, 1);
        Assert.Equal(LinkOutcome.NotFound, resolved[0].Outcome);
    }

    [Fact]
    public void TwoPagesWithTheSameNameAreAmbiguousRatherThanGuessed()
    {
        Write("Concepts/Review.md");
        Write("Exercises/Review.md");

        var resolved = WikiLinks.Resolve(WikiLinks.Parse("[[Review]]"), _course, 1);

        Assert.Equal(LinkOutcome.Ambiguous, resolved[0].Outcome);
        Assert.Equal(2, resolved[0].Candidates.Count);
        Assert.Equal("“Review” matches 2 pages, so it’s unclear which one is meant.", resolved[0].Problem);
    }

    [Fact]
    public void AMissingTargetSaysSoPlainly()
    {
        var resolved = WikiLinks.Resolve(WikiLinks.Parse("[[Nowhere]]"), _course, 1);
        Assert.Equal("“Nowhere” doesn’t match any page in this section.", resolved[0].Problem);
    }

    [Fact]
    public void APageLinkingToItselfIsNotWorkToDo()
    {
        string self = Write("section1/All Classes/Unit 1, Day 2.md");
        var resolved = WikiLinks.Resolve(WikiLinks.Parse("[[Unit 1, Day 2]]"), _course, 1, self);
        Assert.Equal(LinkOutcome.SelfReference, resolved[0].Outcome);
    }

    [Fact]
    public void AnEmbeddedImageIsAnAttachmentNotAMissingPage()
    {
        // Otherwise the plan tells a teacher who did nothing wrong that
        // “diagram.png” doesn't match any page.
        var resolved = WikiLinks.Resolve(
            WikiLinks.Parse("![[diagram.png]] and ![[Media/handout.pdf]]"), _course, 1);

        Assert.Equal(2, resolved.Count);
        Assert.All(resolved, r => Assert.Equal(LinkOutcome.Attachment, r.Outcome));
        Assert.All(resolved, r => Assert.Null(r.Problem));
    }

    [Fact]
    public void ACurriculumPageIsNotMistakenForAnAttachment()
    {
        // Path.GetExtension("E2.6") is ".6". These pages are real, and named
        // exactly like this throughout the Curriculum folder.
        Write("Curriculum/E2.6.md");
        var resolved = WikiLinks.Resolve(WikiLinks.Parse("- [[E2.6]] — ![[E2.6#^text]]"), _course, 1);
        Assert.Equal(LinkOutcome.Resolved, Assert.Single(resolved).Outcome);
    }

    [Fact]
    public void TheSameTargetTwiceIsResolvedOnce()
    {
        Write("Concepts/Ohm's Law.md");
        var resolved = WikiLinks.Resolve(
            WikiLinks.Parse("[[Ohm's Law]] and again [[Ohm's Law|the law]]"), _course, 1);
        Assert.Single(resolved);
    }

    private string Write(string relative)
    {
        string full = Path.Combine(_course, relative.Replace('/', Path.DirectorySeparatorChar));
        Directory.CreateDirectory(Path.GetDirectoryName(full)!);
        File.WriteAllText(full, "---\ndraft: true\n---\nbody\n");
        return full;
    }
}
