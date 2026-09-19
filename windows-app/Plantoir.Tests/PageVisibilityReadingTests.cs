using Plantoir.Core.Assist;
using Plantoir.Core.Models;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// The three-way reading of a page's visibility flag.
///
/// <para><c>contracts/file-formats.json</c> → <c>pageVisibility.readingCases</c>
/// carries the 54 answers the two apps must agree on, and
/// <c>ContractTests.FileFormats_PageVisibilityReadingCases</c> runs those. This
/// file covers the half the shared list deliberately leaves out: the forms
/// where this app says <c>CannotTell</c>, and the corners it handles rather
/// than refusing.</para>
///
/// <para>The shared list cannot carry the <c>CannotTell</c> forms, because a
/// case there states what the SITE does and this app's reporting answer is
/// <c>visible</c> whatever the site does. Pinning <c>expectVisible: true</c>
/// for a form the site HIDES — a value on the line below the key, say — would
/// oblige the mac to be wrong in the same direction rather than merely allow
/// it. So they are pinned here, at the level where the answer is honest:
/// <c>CannotTell</c> is its own answer, reporting collapses it to visible, and
/// nothing that writes to a teacher's file is allowed to collapse it at
/// all.</para>
///
/// <para>Everything asserted here about what the BUILD does was measured on
/// 2026-09-18 by running the form through the real image — python-frontmatter
/// 1.3.0 / PyYAML 6.0.3, then gray-matter with js-yaml on <c>JSON_SCHEMA</c>,
/// then <c>patches/publish.ts</c>'s own expression. The measurement lives on
/// the mac in <c>scripts/check_visibility_against_the_site.py</c>, re-run by
/// every <c>verify.sh</c>; this file is the Windows twin of the mac's
/// <c>PageVisibilityReadingTests.swift</c> and asserts the same forms.
/// Issue #140.</para>
/// </summary>
public class PageVisibilityReadingTests
{
    /// <summary>A frontmatter fragment, as a whole page.</summary>
    private static string Page(string frontmatter) =>
        "---\n" + frontmatter + "\n---\n\nThe lesson.\n";

    private static PageVisibility Answer(string frontmatter, int section = 1) =>
        PageVisibilityReader.Answer(Page(frontmatter), section);

    // ---- The forms this app refuses to guess at ---------------------------

    /// <summary>
    /// Each of these is a page the BUILD has a definite opinion about. This app
    /// does not, and says so rather than picking a side.
    /// </summary>
    [Fact]
    public void TheFormsThisAppWillNotGuessAt()
    {
        // Measured: the build HIDES every one of these.
        Assert.Equal(PageVisibility.CannotTell, Answer("publish:\n  false"));
        Assert.Equal(PageVisibility.CannotTell, Answer("publish: !!str false"));
        Assert.Equal(PageVisibility.CannotTell, Answer("publish: >-\n  false"));
        Assert.Equal(PageVisibility.CannotTell, Answer("publish: |-\n  false"));
        Assert.Equal(PageVisibility.CannotTell, Answer("publish: &flag false"));
        Assert.Equal(PageVisibility.CannotTell, Answer("flag: &flag false\npublish: *flag"));
        Assert.Equal(PageVisibility.CannotTell, Answer("publish: \"fal\\u0073e\""));
        Assert.Equal(PageVisibility.CannotTell, Answer("publish: 'fal''se'"));
        Assert.Equal(PageVisibility.CannotTell, Answer("publish: \"false"));

        // Measured: the build PUBLISHES these, but each could run over more
        // than one line, and getting a flow collection wrong is not worth the
        // few teachers who would ever write one.
        Assert.Equal(PageVisibility.CannotTell, Answer("publish: [false]"));
        Assert.Equal(PageVisibility.CannotTell, Answer("publish: {a: false}"));

        // Measured: the build stops entirely on these, so there is no site
        // verdict to mirror.
        Assert.Equal(PageVisibility.CannotTell, Answer("title: x\n\tpublish: false"));
        Assert.Equal(PageVisibility.CannotTell,
            PageVisibilityReader.Answer("---\npublish: false\nBody.\n", 1));
    }

    /// <summary>
    /// Each of these STOPS the build, so there is no site verdict to mirror and
    /// this reader must not offer one. Reading them as ordinary strings called
    /// them all published.
    /// </summary>
    [Fact]
    public void TheFormsTheBuildItselfCannotRead()
    {
        Assert.Equal(PageVisibility.CannotTell, Answer("publish: - false"));
        Assert.Equal(PageVisibility.CannotTell, Answer("publish: %"));
        Assert.Equal(PageVisibility.CannotTell, Answer("publish: @x"));
        Assert.Equal(PageVisibility.CannotTell, Answer("publish: `x"));
        Assert.Equal(PageVisibility.CannotTell, Answer("publish: false: true"));
    }

    /// <summary>
    /// A value below the key. Measured: the build reads it and HIDES the page,
    /// over a blank line as happily as not.
    /// </summary>
    [Fact]
    public void AValueBelowTheKeyIsNotFollowedEvenOverABlankLine()
    {
        Assert.Equal(PageVisibility.CannotTell, Answer("publish:\n\n  false"));
        Assert.Equal(PageVisibility.CannotTell, Answer("draft:\n\n  true"));
        Assert.Equal(PageVisibility.CannotTell, Answer("publishForSection1:\n  false"));
    }

    /// <summary>
    /// A colon has to be followed by a space, a tab or the end of the line, or
    /// the line is not a mapping at all.
    /// </summary>
    [Fact]
    public void AColonWithNoSpaceAfterItIsNotAKey()
    {
        // Measured: a page whose whole frontmatter is `publish:false` reaches
        // Quartz with NO keys and is published; one with another key beside it
        // stops the build. Either way this is not the page's flag, and reading
        // it as one called a live page hidden.
        Assert.Equal(PageVisibility.SaysNothing, Answer("publish:false"));
        Assert.Equal(PageVisibility.SaysNothing, Answer("publish:true"));
        Assert.Equal(PageVisibility.SaysNothing, Answer("draft:true"));
    }

    /// <summary>
    /// YAML's whitespace is a space and a tab, and the Mac's Option-Space is
    /// neither. .NET's <c>Trim()</c> strips it, which is why nothing in the
    /// reader uses one.
    /// </summary>
    [Fact]
    public void OnlySpacesAndTabsAreWhitespace()
    {
        // Measured: `publish: false<NBSP>` beside another key is the STRING
        // "false " and the page is PUBLISHED.
        Assert.Equal(PageVisibility.Visible, Answer("publish: false \ntitle: x"));
        Assert.Equal(PageVisibility.SaysNothing, Answer("publish: false"));
        Assert.Equal(PageVisibility.Hidden, Answer("publish: false\t"));
    }

    /// <summary>python-frontmatter's fence is three dashes OR MORE.</summary>
    [Fact]
    public void ALongerFenceIsStillFrontmatter()
    {
        // Measured: both of these hide the page. Requiring exactly `---` read
        // them as pages with no frontmatter at all, which is "visible".
        Assert.Equal(PageVisibility.Hidden,
            PageVisibilityReader.Answer("----\npublish: false\n----\nBody.\n", 1));
        Assert.Equal(PageVisibility.Hidden,
            PageVisibilityReader.Answer("---\npublish: false\n----\nBody.\n", 1));
    }

    /// <summary>An indented <c># note</c> is a comment, not a value.</summary>
    [Fact]
    public void AnIndentedCommentIsNotAValue()
    {
        Assert.Equal(PageVisibility.Visible, Answer("publish: true\n  # mine"));
        Assert.Equal(PageVisibility.Visible, Answer("publish:\n  # mine"));
        Assert.Equal(PageVisibility.CannotTell, Answer("publish:\n  # mine\n  false"));
    }

    /// <summary>
    /// A key of one of the four names, indented under something else. It may be
    /// nothing to do with the page, and it may be everything.
    /// </summary>
    [Fact]
    public void AnIndentedKeyIsNotThisPagesFlag()
    {
        Assert.Equal(PageVisibility.CannotTell, Answer("meta:\n  publish: false"));
        Assert.Equal(PageVisibility.CannotTell, Answer("something:\n  draft: true"));
    }

    /// <summary>The whole reason <c>CannotTell</c> exists as a separate answer.</summary>
    [Fact]
    public void ReportingErrsVisibleAndNeverHidden()
    {
        string unreadable = Page("publish: !!str false");
        Assert.False(PageFrontmatter.IsDraft(unreadable, 1));
        Assert.Null(PageFrontmatter.StoredDraft(unreadable, 1));
    }

    // ---- The corners this app handles rather than refusing ----------------

    [Fact]
    public void APageWithNoFrontmatterSaysNothing()
    {
        Assert.Equal(PageVisibility.SaysNothing, PageVisibilityReader.Answer("Just a page.\n", 1));
        Assert.Equal(PageVisibility.SaysNothing, Answer("title: Unit 1, Day 1"));
    }

    [Fact]
    public void ABlankLineBeforeTheOpeningFenceIsStillFrontmatter()
    {
        // Measured: python-frontmatter accepts it, so the build reads the
        // block and hides the page.
        Assert.Equal(PageVisibility.Hidden,
            PageVisibilityReader.Answer("\n---\npublish: false\n---\nBody.\n", 1));
    }

    [Fact]
    public void AWindowsWrittenFileReadsTheSame()
    {
        Assert.Equal(PageVisibility.Hidden,
            PageVisibilityReader.Answer("---\r\npublish: false\r\n---\r\nBody.\r\n", 1));
    }

    [Fact]
    public void WhitespaceAroundTheValueIsNotPartOfIt()
    {
        Assert.Equal(PageVisibility.Hidden, Answer("publish:\tfalse"));
        Assert.Equal(PageVisibility.Hidden, Answer("publish:     false"));
        Assert.Equal(PageVisibility.Hidden, Answer("publish: false   "));
    }

    [Fact]
    public void TheLastOfTwoIdenticalKeysWins()
    {
        Assert.Equal(PageVisibility.Hidden, Answer("publish: true\npublish: false"));
        Assert.Equal(PageVisibility.Visible, Answer("publish: false\npublish: true"));
        Assert.Equal(PageVisibility.Visible, Answer("draftSection1: true\ndraftSection1: false"));
    }

    [Fact]
    public void TheFourKeysAreConsultedInTheBuildsOwnOrder()
    {
        Assert.Equal(PageVisibility.Hidden, Answer("publishForSection1: false\npublish: true"));
        Assert.Equal(PageVisibility.Hidden, Answer("publish: false\ndraftSection1: false"));
        Assert.Equal(PageVisibility.Hidden, Answer("draftSection1: true\ndraft: false"));
        Assert.Equal(PageVisibility.SaysNothing, Answer("publishForSection2: false"));
    }

    /// <summary>
    /// The first key PRESENT decides, whether or not this app can read it.
    /// Falling through an unreadable key to the next one was the old reader's
    /// bug: the build never falls through, so a page whose
    /// <c>publishForSection1</c> is a tag and whose <c>publish</c> is <c>true</c>
    /// is not a published page — it is a page this app will not answer for.
    /// </summary>
    [Fact]
    public void AnUnreadableKeyIsNotFallenThrough()
    {
        Assert.Equal(PageVisibility.CannotTell, Answer("publishForSection1: !!str false\npublish: true"));
        Assert.Equal(PageVisibility.CannotTell, Answer("publish: [false]\ndraft: true"));
    }

    [Fact]
    public void AKeyThatIsNullPublishesThePage()
    {
        Assert.Equal(PageVisibility.Visible, Answer("publish:"));
        Assert.Equal(PageVisibility.Visible, Answer("publish: ~"));
        Assert.Equal(PageVisibility.Visible, Answer("publish: null"));
        Assert.Equal(PageVisibility.Visible, Answer("publish: NULL"));
        Assert.Equal(PageVisibility.Visible, Answer("publish: #why"));
        Assert.Equal(PageVisibility.Visible, Answer("publish:\ntitle: x"));
        Assert.Equal(PageVisibility.Visible, Answer("draft:"));
    }

    [Fact]
    public void ACommentIsOnlyAComment()
    {
        Assert.Equal(PageVisibility.Visible, Answer("publish: true # why"));
        Assert.Equal(PageVisibility.Hidden, Answer("publish: false # why"));
        Assert.Equal(PageVisibility.Visible, Answer("publish: true#x"));
        Assert.Equal(PageVisibility.Visible, Answer("publish: false#x"));
        Assert.Equal(PageVisibility.Visible, Answer("publish: \"a # false\""));
        Assert.Equal(PageVisibility.Hidden, Answer("publish: \"false\" # why"));
    }

    [Fact]
    public void QuotingChangesTheAnswerBothWays()
    {
        Assert.Equal(PageVisibility.Hidden, Answer("publish: \"false\""));
        // One capital letter apart, because publish.ts compares strings
        // exactly. Never "simplify" this into a case-insensitive compare.
        Assert.Equal(PageVisibility.Visible, Answer("publish: \"False\""));
        Assert.Equal(PageVisibility.Visible, Answer("publish: 'no'"));
        Assert.Equal(PageVisibility.Visible, Answer("draft: \"yes\""));
        Assert.Equal(PageVisibility.Hidden, Answer("draft: yes"));
        Assert.Equal(PageVisibility.Hidden, Answer("draft: \"true\""));
        Assert.Equal(PageVisibility.Hidden, Answer("draft: '  true  '"));
    }

    [Fact]
    public void TheNineSpellingsAndNothingElse()
    {
        foreach (string spelling in new[] { "true", "True", "TRUE", "yes", "Yes", "YES", "on", "On", "ON" })
        {
            Assert.Equal(PageVisibility.Visible, Answer("publish: " + spelling));
            Assert.Equal(PageVisibility.Hidden, Answer("draft: " + spelling));
        }
        foreach (string spelling in new[] { "false", "False", "FALSE", "no", "No", "NO", "off", "Off", "OFF" })
        {
            Assert.Equal(PageVisibility.Hidden, Answer("publish: " + spelling));
            Assert.Equal(PageVisibility.Visible, Answer("draft: " + spelling));
        }
        foreach (string spelling in new[] { "tRue", "fAlSe", "nO", "oN", "oFf", "y", "n", "Y", "N", "0", "1", "maybe" })
            Assert.Equal(PageVisibility.Visible, Answer("publish: " + spelling));
        foreach (string spelling in new[] { "TrUe", "\"true\"", "\"True\"" })
            Assert.Equal(PageVisibility.Hidden, Answer("draft: " + spelling));
        foreach (string spelling in new[] { "maybe", "1", "y", "\"yes\"" })
            Assert.Equal(PageVisibility.Visible, Answer("draft: " + spelling));
    }

    [Fact]
    public void AKeySpelledTheOtherLegalWays()
    {
        Assert.Equal(PageVisibility.Hidden, Answer("publish : false"));
        Assert.Equal(PageVisibility.Hidden, Answer("\"publish\": false"));
        Assert.Equal(PageVisibility.Hidden, Answer("'publish': false"));
        Assert.Equal(PageVisibility.SaysNothing, Answer("published: false"));
        Assert.Equal(PageVisibility.SaysNothing, Answer("publishForSection11: false"));
    }

    /// <summary>
    /// Reading does not depend on where the page lives — the build consults all
    /// four keys on every page it copies. This was this app's blind spot too:
    /// until 2026-09-19 a course-level page's plain <c>publish: false</c> was
    /// never even looked at, so the page reported visible while the build hid
    /// it.
    /// </summary>
    [Fact]
    public void WhereThePageLivesChangesNothingAboutTheRead()
    {
        Assert.Equal(PageVisibility.Hidden, Answer("publish: false", section: 2));
        Assert.Equal(PageVisibility.Hidden, Answer("publishForSection1: false"));
        Assert.Equal(true, PageFrontmatter.StoredDraft(Page("publish: false"), 2));
    }
}

/// <summary>
/// The writing half: a writer never collapses <c>CannotTell</c>, rewrites the
/// line the READER read, sets the LAST of two, and edits the block the reader
/// found.
/// </summary>
public class PageVisibilityWritingTests
{
    /// <summary>
    /// Reporting says this page is visible; the writer must not act on that.
    /// Before the certainty flag, "publish this page" on a page whose flag
    /// reads <c>cannot tell</c> answered <i>It's already been published</i> and
    /// wrote nothing, while the build was holding the page back.
    /// </summary>
    [Fact]
    public void AWriterWritesTheFlagOutRatherThanTrustingTheCollapse()
    {
        string unreadable = "---\npublish: !!str false\n---\nBody.\n";

        var (published, publishedEdit) = PageFrontmatter.SetDraft(unreadable, "publish", draft: false, 1);
        Assert.True(publishedEdit.Changed);
        Assert.Equal("---\npublish: true\n---\nBody.\n", published);

        var (hidden, hiddenEdit) = PageFrontmatter.SetDraft(unreadable, "publish", draft: true, 1);
        Assert.True(hiddenEdit.Changed);
        Assert.Equal("---\npublish: false\n---\nBody.\n", hidden);
    }

    /// <summary>
    /// A page that already SAYS what was asked, however oddly it says it, is
    /// left alone — and that is a CONFIDENT reading, not a collapsed one.
    /// </summary>
    [Fact]
    public void APageThatAlreadySaysItIsLeftAlone()
    {
        foreach (string value in new[] { "maybe", "on", "true # why", "\"False\"", "y" })
        {
            string text = $"---\npublish: {value}\n---\nBody.\n";
            var (after, edit) = PageFrontmatter.SetDraft(text, "publish", draft: false, 1);
            Assert.False(edit.Changed);
            Assert.Equal(text, after);
        }
        foreach (string value in new[] { "no", "off", "FALSE", "false # not ready" })
        {
            string text = $"---\npublish: {value}\n---\nBody.\n";
            var (after, edit) = PageFrontmatter.SetDraft(text, "publish", draft: true, 1);
            Assert.False(edit.Changed);
            Assert.Equal(text, after);
        }
    }

    /// <summary>
    /// The writer must rewrite the line the READER read, or the two disagree
    /// about which line the build is looking at.
    /// </summary>
    [Fact]
    public void TheWriterRewritesTheLineTheReaderRead()
    {
        // A quoted key was invisible to the writer's plain prefix test, so it
        // inserted a SECOND `publish: true` above it — and PyYAML keeps the
        // LAST of two, so the page stayed hidden while the teacher was told it
        // had been published.
        foreach (string frontmatter in new[] { "\"publish\": false", "publish : false", "'publish': false" })
        {
            string before = $"---\n{frontmatter}\n---\nBody.\n";
            var (after, _) = PageFrontmatter.SetDraft(before, "publish", draft: false, 1);
            Assert.Equal(PageVisibility.Visible, PageVisibilityReader.Answer(after, 1));
            Assert.Equal(1, after.Split('\n').Count(line => line.Contains("publish", StringComparison.Ordinal)));
        }
    }

    /// <summary>
    /// The writer has to find the same BLOCK the reader found, or it edits a
    /// different page from the one it read. Measured: prepending a block of its
    /// own leaves the teacher's real frontmatter behind it as BODY TEXT,
    /// printed to their students.
    /// </summary>
    [Fact]
    public void TheWriterEditsTheBlockTheReaderFound()
    {
        var (longer, _) = PageFrontmatter.SetDraft("----\npublish: false\n----\nBody.\n", "publish", draft: false, 1);
        Assert.Equal("----\npublish: true\n----\nBody.\n", longer);

        var (blankFirst, _) = PageFrontmatter.SetDraft("\n---\npublish: false\n---\nBody.\n", "publish", draft: false, 1);
        Assert.Equal("\n---\npublish: true\n---\nBody.\n", blankFirst);

        var (mismatched, _) = PageFrontmatter.SetDraft("---\npublish: false\n----\nBody.\n", "publish", draft: false, 1);
        Assert.Equal("---\npublish: true\n----\nBody.\n", mismatched);
    }

    /// <summary>And it must set the LAST of two, because that is the one the build reads.</summary>
    [Fact]
    public void TheWriterSetsTheLastOfTwoIdenticalKeys()
    {
        var (twice, _) = PageFrontmatter.SetDraft(
            "---\npublish: true\npublish: false\ntitle: x\n---\nBody.\n", "publish", draft: false, 1);
        Assert.Equal("---\npublish: true\npublish: true\ntitle: x\n---\nBody.\n", twice);
        Assert.Equal(PageVisibility.Visible, PageVisibilityReader.Answer(twice, 1));

        var (legacyTwice, _) = PageFrontmatter.SetDraft(
            "---\ndraft: false\ndraft: true\n---\nBody.\n", "publish", draft: true, 1);
        Assert.Equal("---\npublish: false\n---\nBody.\n", legacyTwice);
    }

    /// <summary>
    /// A <c>#</c> inside quotes is not a comment, and splitting the line at it
    /// left an unbalanced quote — frontmatter the build cannot parse at all,
    /// written into the teacher's file by an ordinary "hide this page".
    /// </summary>
    [Fact]
    public void AHashInsideQuotesIsNotAComment()
    {
        var (after, edit) = PageFrontmatter.SetDraft(
            "---\npublish: \"false # why\"\n---\nBody.\n", "publish", draft: true, 1);
        Assert.True(edit.Changed);
        Assert.Equal("---\npublish: false\n---\nBody.\n", after);
        Assert.Equal(PageVisibility.Hidden, PageVisibilityReader.Answer(after, 1));
    }

    /// <summary>
    /// The gate reads all FOUR keys while the write goes to the one the page's
    /// folder decides on. A section-local page carrying a stray
    /// <c>publishForSection1</c> is what the build reads first, so "hide this"
    /// must still write — and #149's copy-a-class path leans on exactly this.
    /// </summary>
    [Fact]
    public void TheGateReadsEveryKeyEvenThoughTheWriteGoesToOne()
    {
        string page = "---\npublishForSection1: false\npublish: true\n---\nBody.\n";
        var (unchanged, edit) = PageFrontmatter.SetDraft(page, "publish", draft: true, 1);
        Assert.False(edit.Changed);
        Assert.Equal(page, unchanged);

        var (changed, publishing) = PageFrontmatter.SetDraft(page, "publish", draft: false, 1);
        Assert.True(publishing.Changed);
        Assert.Contains("publish: true", changed, StringComparison.Ordinal);
    }

    // The ten `writingCases` in contracts/file-formats.json all pass against
    // this writer — replayed here on 2026-09-19, all ten, including case 8
    // (`publish: maybe` asked to be PUBLISHED, expecting no rewrite), which
    // needed the certainty gate above. Running them as data belongs to
    // FileFormatContractTests, which still answers `writingRules` with
    // hand-written assertions: that adoption is issue #138, and
    // contracts/README.md still says Windows does not run the list.
}

/// <summary>
/// Where a collapsed "visible" would decide to SKIP A WRITE.
///
/// <para>Four places on the mac, four here: the plan's "already right" list,
/// the nothing-to-do sentence, the whole-unit count of what would move, and the
/// date a linked page inherits. Each needs the certainty flag beside the
/// answer, or "publish this page" on a page whose flag reads <c>cannot tell</c>
/// answers <i>It's already been published</i> and writes nothing while the
/// build holds the page back.</para>
/// </summary>
public class PageVisibilityCertaintyTests : IDisposable
{
    private readonly string _folder = Directory.CreateTempSubdirectory("plantoir-certainty").FullName;
    private readonly FakeLauncher _launcher = new();

    public PageVisibilityCertaintyTests()
    {
        File.WriteAllText(Path.Combine(_folder, "preview.ps1"), "# marker");
        File.WriteAllText(Path.Combine(_folder, "deploy.ps1"), "# marker");
        Directory.CreateDirectory(Path.Combine(_folder, "courses", "ICS3U"));
        File.WriteAllText(Path.Combine(_folder, "courses", "ICS3U", "course_config.json"),
            """
            {
              "course_code": "ICS3U",
              "course_name": "Computer Science",
              "deploy_target": "netlify",
              "num_sections": 1,
              "per_section_folders": ["All Classes"],
              "per_section_files": [],
              "section_numbers": [1]
            }
            """);
    }

    public void Dispose()
    {
        try { Directory.Delete(_folder, recursive: true); } catch { }
        GC.SuppressFinalize(this);
    }

    private AssistWorkspace Open() => new(_folder, _launcher);

    private string Write(string relative, string frontmatter, string body = "The lesson.")
    {
        string full = Path.Combine(_folder, "courses", "ICS3U",
            relative.Replace('/', Path.DirectorySeparatorChar));
        Directory.CreateDirectory(Path.GetDirectoryName(full)!);
        File.WriteAllText(full, "---\n" + frontmatter + "---\n" + body + "\n");
        return full;
    }

    /// <summary>A class page whose flag is a form no reader here will guess at.</summary>
    private string UnreadableClass(string title = "Unit 1, Day 1", string date = "2026-09-08") =>
        Write($"section1/All Classes/{title}.md",
              $"title: {title}\npublish: !!str false\ncreated: {date}T07:00:00.000-0400\n");

    [Fact]
    public void APageWhoseFlagCannotBeReadIsNotOnTheAlreadyRightList()
    {
        UnreadableClass();
        var plan = Open().PlanPublish("ICS3U", 1, new[] { "Unit 1, Day 1" }, includeLinked: false);

        Assert.Empty(plan.AlreadyRight);
        var change = Assert.Single(plan.Changes);
        Assert.Equal("Unit 1, Day 1", change.Page.Title);
        Assert.False(change.Page.VisibilityIsCertain);
    }

    [Fact]
    public void ThereIsNoNothingToDoSentenceForAPageWhoseFlagCannotBeRead()
    {
        UnreadableClass();
        var plan = Open().PlanPublish("ICS3U", 1, new[] { "Unit 1, Day 1" }, includeLinked: false);
        Assert.Null(plan.NothingToDoSentence);

        // The control: the same page saying plainly what was asked for.
        Write("section1/All Classes/Unit 1, Day 2.md",
              "title: Unit 1, Day 2\npublish: true\ncreated: 2026-09-10T07:00:00.000-0400\n");
        var settled = Open().PlanPublish("ICS3U", 1, new[] { "Unit 1, Day 2" }, includeLinked: false);
        Assert.Equal("It's already been published.", settled.NothingToDoSentence);
    }

    [Fact]
    public void TheWholeUnitCountIncludesAPageWhoseFlagCannotBeRead()
    {
        UnreadableClass();
        var result = Open().PlanWholeUnit("ICS3U", 1, unit: 1, publishing: true);

        Assert.True(result.HasPages);
        Assert.Equal(1, result.MovingCount);
        Assert.Null(result.AlreadyDoneSentence);
    }

    [Fact]
    public void APageWhoseFlagCannotBeReadStillTakesTheDateOfTheClassThatBroughtIt()
    {
        Write("section1/All Classes/Unit 1, Day 1.md",
              "title: Unit 1, Day 1\npublish: false\ncreated: 2026-09-08T07:00:00.000-0400\n",
              "Concept: [[Ohm's Law]].");
        Write("Concepts/Ohm's Law.md",
              "title: Ohm's Law\npublishForSection1: !!str false\ncreated: 2026-01-01T07:00:00.000-0400\n");

        var plan = Open().PlanPublish("ICS3U", 1, new[] { "Unit 1, Day 1" }, includeLinked: true);

        var move = Assert.Single(plan.DateMoves, m => m.Page.Title == "Ohm's Law");
        Assert.Equal(new DateOnly(2026, 9, 8), move.To);
    }

    /// <summary>
    /// End to end, which is the sentence the residue was really about: asked to
    /// publish a page whose flag cannot be read, the file is WRITTEN rather
    /// than the teacher being told it was already published.
    /// </summary>
    [Fact]
    public async Task APageWhoseFlagCannotBeReadIsWrittenRatherThanAnsweredFor()
    {
        string path = UnreadableClass();
        var workspace = Open();

        await workspace.Apply(
            workspace.PlanPublish("ICS3U", 1, new[] { "Unit 1, Day 1" }, includeLinked: false),
            preview: false);

        string after = File.ReadAllText(path);
        Assert.Contains("publish: true", after, StringComparison.Ordinal);
        Assert.DoesNotContain("!!str", after, StringComparison.Ordinal);
    }
}
