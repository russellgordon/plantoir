using Plantoir.Core.Assist;
using Plantoir.Core.Models;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// WHICH pages are days of teaching, asked through a real workspace on a real
/// folder tree rather than of the rule in isolation.
///
/// <para><c>ClassFolderContractTests</c> runs the shared contract against
/// <c>ClassFolderRule</c> itself, and passed all the way through the two
/// defects this file closes — because neither was in the rule. Both were in
/// what this app HANDED the rule: a list of folders wider than the one the mac
/// and <c>build_site.py</c> count, and a path reaching further up the disk
/// than the section. So these tests build the tree, open the workspace and ask
/// the questions a teacher's request turns into.</para>
///
/// <para>Issue #115, finished on Windows 2026-09-19.</para>
/// </summary>
public class ClassFolderMembershipTests : IDisposable
{
    private readonly string _parent = Directory.CreateTempSubdirectory("plantoir-membership").FullName;
    private readonly FakeLauncher _launcher = new();
    private string _folder = "";

    public void Dispose()
    {
        try { Directory.Delete(_parent, recursive: true); } catch { }
        GC.SuppressFinalize(this);
    }

    // ---- Where the teacher keeps their files is not a fact about the course ----

    /// <summary>
    /// A GUARD, not evidence of a fix: this is the defect #115 was opened for,
    /// and it was already closed on <c>dev</c> by <c>Plan()</c> passing a
    /// relative path. The test is here so that a future change which goes back
    /// to an absolute one fails on the sentence a teacher would say — "my
    /// working folder is called Classroom" — rather than only on the rule's
    /// own unit case.
    /// </summary>
    [Theory]
    [InlineData("Classroom")]
    [InlineData("All Classes")]
    [InlineData("Class")]
    public void WhatTheWorkingFolderIsCalledDecidesNothing(string workingFolderName)
    {
        OpenWorkspaceCalled(workingFolderName);
        AddCourse("ICS3U", perSectionFolders: new[] { "All Classes" });
        Page("ICS3U", "Concepts/Loops.md");
        Page("ICS3U", "section1/All Classes/Unit 1, Day 1.md");

        Assert.False(PlannedFor("ICS3U", 1, "Loops").IsClassPage);
        Assert.True(PlannedFor("ICS3U", 1, "Unit 1, Day 1").IsClassPage);
    }

    /// <summary>
    /// The same question one level down, and the part that was still live:
    /// <c>Relative()</c> is relative to the WORKING folder, so the path handed
    /// to the rule still carried <c>courses</c>, the course code and
    /// <c>sectionN</c> above it. A course-level SHARED folder a teacher called
    /// "All Classes" therefore made every page under it a lesson — of every
    /// section at once, since shared pages belong to all of them.
    /// </summary>
    [Fact]
    public void ASharedFolderNamedLikeTheClassFolderDoesNotMakeLessons()
    {
        OpenWorkspaceCalled("Teaching");
        AddCourse("ICS3U", perSectionFolders: new[] { "All Classes" });
        Page("ICS3U", "All Classes/Reference.md");                 // course-level: SHARED
        Page("ICS3U", "section1/All Classes/Unit 1, Day 1.md");    // the real class folder

        Assert.False(PlannedFor("ICS3U", 1, "Reference").IsClassPage);
        Assert.True(PlannedFor("ICS3U", 1, "Unit 1, Day 1").IsClassPage);
    }

    // ---- The narrowing changes two things a teacher can SEE ----------------

    /// <summary>
    /// Publish plans GROW. Link-following deliberately stops at class pages —
    /// a class is published because the teacher asked for it, not because
    /// another class linked to it — so a shared page the old wide path called
    /// a class was silently skipped. Demoting it to what it is makes it
    /// follow-able, and "publish Day 1 and everything it links to" now reaches
    /// it.
    /// </summary>
    [Fact]
    public void PublishingAClassNowReachesASharedPageInAFolderNamedLikeTheClassFolder()
    {
        OpenWorkspaceCalled("Teaching");
        AddCourse("ICS3U", perSectionFolders: new[] { "All Classes" });
        Page("ICS3U", "All Classes/Reference.md", unpublished: true);
        Page("ICS3U", "section1/All Classes/Unit 1, Day 1.md", unpublished: true,
             body: "See [[Reference]].");

        var plan = Open().PlanPublish("ICS3U", 1, new[] { "Unit 1, Day 1" }, includeLinked: true);

        var reference = Assert.Single(plan.Changes, c => c.Page.Title == "Reference");
        Assert.True(reference.BecauseLinked);
        Assert.True(reference.WillBeVisible);
    }

    /// <summary>
    /// The "introducing class" credit changes hands. An undated page that a
    /// class links to inherits that class's date, and the teacher is told
    /// which class brought it in. A shared page in a folder named like the
    /// class folder used to be eligible for that credit — and won it, because
    /// a course-level folder sorts before <c>section1</c> — so the teacher was
    /// told a page they never taught from was what introduced it.
    /// </summary>
    [Fact]
    public void TheClassCreditedWithIntroducingAPageIsARealClass()
    {
        OpenWorkspaceCalled("Teaching");
        AddCourse("ICS3U", perSectionFolders: new[] { "All Classes" });
        Page("ICS3U", "Concepts/Glossary.md", unpublished: true);
        Dated("ICS3U", "All Classes/Recap.md", "2026-09-10", unpublished: true,
              body: "See [[Glossary]].");
        Dated("ICS3U", "section1/All Classes/Unit 1, Day 1.md", "2026-09-10", unpublished: true,
              body: "See [[Glossary]].");

        var plan = Open().PlanPublish("ICS3U", 1, new[] { "Unit 1, Day 1" }, includeLinked: true);

        var move = Assert.Single(plan.DateMoves, m => m.Page.Title == "Glossary");
        Assert.Equal("Unit 1, Day 1", move.TakenFrom);
    }

    // ---- Which FOLDERS count: the shared membership rule -------------------

    /// <summary>
    /// The divergence this file's first half is about: Windows walked every
    /// <c>per_section_folder</c>, so a course configured
    /// <c>["All Classes","Handouts"]</c> counted its handouts as days of
    /// teaching — in the dated lists, in "publish every class from the 15th",
    /// in the next-class numbering — while the mac and <c>build_site.py</c>
    /// counted only "All Classes".
    /// </summary>
    [Fact]
    public void AFolderThatMentionsNoClassesHoldsNoClasses()
    {
        OpenWorkspaceCalled("Teaching");
        AddCourse("ICS3U", perSectionFolders: new[] { "All Classes", "Handouts" });
        Dated("ICS3U", "section1/All Classes/Unit 1, Day 1.md", "2026-09-10");
        Dated("ICS3U", "section1/Handouts/Lab Safety.md", "2026-09-11");

        var workspace = Open();
        var course = workspace.Course("ICS3U");

        Assert.Equal(new[] { "Unit 1, Day 1" }, Titles(workspace.ClassPages(course, 1)));
        Assert.Equal("Unit 1, Day 1",
            Path.GetFileNameWithoutExtension(workspace.ClassOn(course, 1, new DateOnly(2026, 9, 10))));

        // The handout is dated the 11th. Asked for that day's class, the
        // refusal has to say there is none — and the range it offers instead
        // is the proof that the handout is not being counted as one.
        var refusal = Assert.Throws<AssistRefusal>(
            () => workspace.ClassOn(course, 1, new DateOnly(2026, 9, 11)));
        Assert.Equal("ICS3U Section 1 has no class on 2026-09-11. " +
                     "Its classes run 2026-09-10 to 2026-09-10.", refusal.Message);
    }

    /// <summary>
    /// **A behaviour change a teacher can see, and the direction that SHRINKS
    /// what counts.** The shared rule falls back to ONE folder when no folder
    /// name mentions classes, so a course whose folders are
    /// <c>["Lessons","Labs"]</c> has both walked before this change and only
    /// "Lessons" after: the Labs pages leave the dated class lists, date-range
    /// publishing, the scheduled-deploy list and the class numbering. This is
    /// what the mac and the build have always done — the point of the change
    /// is that all three now agree — but it is a change, so it is pinned here
    /// rather than discovered.
    ///
    /// <para>Who is exposed: only a teacher who both renamed the class folder
    /// away from anything containing "class" AND added a second per-section
    /// folder. Every one of the shipped example payloads and skeletons
    /// configures exactly <c>["All Classes"]</c>.</para>
    /// </summary>
    [Fact]
    public void WhenNoFolderMentionsClassesOnlyTheFirstHoldsClasses()
    {
        OpenWorkspaceCalled("Teaching");
        AddCourse("ICS3U", perSectionFolders: new[] { "Lessons", "Labs" });
        Dated("ICS3U", "section1/Lessons/Unit 1, Day 1.md", "2026-09-10");
        Dated("ICS3U", "section1/Labs/Soldering.md", "2026-09-11");

        var workspace = Open();
        var course = workspace.Course("ICS3U");

        Assert.Equal(new[] { "Unit 1, Day 1" }, Titles(workspace.ClassPages(course, 1)));
        Assert.False(PlannedFor("ICS3U", 1, "Soldering").IsClassPage);
        Assert.True(PlannedFor("ICS3U", 1, "Unit 1, Day 1").IsClassPage);
    }

    /// <summary>
    /// The mirror of the same change, in the direction that WIDENS. A course
    /// with no per-section folders at all had no class pages here, because
    /// there was no folder to walk; the shared rule answers "All Classes" for
    /// it, so a section that has such a folder on disk anyway now has classes.
    /// </summary>
    [Fact]
    public void ACourseWithNoPerSectionFoldersFallsBackToAllClasses()
    {
        OpenWorkspaceCalled("Teaching");
        AddCourse("ICS3U", perSectionFolders: Array.Empty<string>());
        Dated("ICS3U", "section1/All Classes/Unit 1, Day 1.md", "2026-09-10");

        var workspace = Open();
        Assert.Equal(new[] { "Unit 1, Day 1" }, Titles(workspace.ClassPages(workspace.Course("ICS3U"), 1)));
    }

    /// <summary>
    /// The two lists that must not drift: the assistant's class pages and the
    /// sidebar's "which classes would this deploy leave out". Their comments
    /// have claimed to walk the same folders since both were written, and they
    /// did not — one walked <c>per_section_folders</c> while the other was
    /// being fixed would be the next version of the same bug, so the claim is
    /// asserted on a fixture instead of trusted.
    /// </summary>
    [Fact]
    public void TheScheduledDeployListAndTheClassPagesAgree()
    {
        OpenWorkspaceCalled("Teaching");
        AddCourse("ICS3U", perSectionFolders: new[] { "All Classes", "Handouts" });
        Dated("ICS3U", "section1/All Classes/Unit 1, Day 1.md", "2026-09-10", unpublished: true);
        Dated("ICS3U", "section1/Handouts/Lab Safety.md", "2026-09-11", unpublished: true);
        Page("ICS3U", "section1/All Classes/index.md", unpublished: true);

        var workspace = Open();
        var course = workspace.Course("ICS3U");

        // ClassPages answers in ABSOLUTE paths; the deploy list answers in file
        // names. Compared as names, they are the same set of pages.
        Assert.Equal(new[] { "Unit 1, Day 1" }, Titles(workspace.ClassPages(course, 1)));
        Assert.Equal(new[] { "Unit 1, Day 1" }, ScheduledDeploy.UnpublishedClassesIn(course, 1).ToArray());
    }

    // ---- Fixture -----------------------------------------------------------

    /// <summary>
    /// A working folder with the given NAME, which is the variable several of
    /// these tests are about — so it cannot be a random temp name.
    /// </summary>
    private void OpenWorkspaceCalled(string name)
    {
        _folder = Path.Combine(_parent, name);
        Directory.CreateDirectory(_folder);
        File.WriteAllText(Path.Combine(_folder, "preview.ps1"), "# marker");
        File.WriteAllText(Path.Combine(_folder, "deploy.ps1"), "# marker");
    }

    private AssistWorkspace Open() => new(_folder, _launcher);

    private PlannedPage PlannedFor(string code, int section, string title)
    {
        var plan = Open().PlanPublish(code, section, new[] { title }, includeLinked: false);
        return Assert.Single(plan.NamedPages);
    }

    private static string[] Titles(IEnumerable<string> paths) =>
        paths.Select(Path.GetFileNameWithoutExtension).ToArray()!;

    private void AddCourse(string code, string[] perSectionFolders)
    {
        string directory = Path.Combine(_folder, "courses", code);
        Directory.CreateDirectory(directory);
        string folders = string.Join(", ", perSectionFolders.Select(f => $"\"{f}\""));
        File.WriteAllText(Path.Combine(directory, "course_config.json"),
            $$"""
            {
              "course_code": "{{code}}",
              "course_name": "A course",
              "deploy_target": "netlify",
              "num_sections": 1,
              "per_section_folders": [{{folders}}],
              "per_section_files": ["Key Links.md"],
              "section_numbers": [1]
            }
            """);
    }

    private void Page(string course, string relative, bool unpublished = false, string body = "Body.")
    {
        Write(course, relative, Visibility(relative, unpublished), body);
    }

    private void Dated(string course, string relative, string date,
                       bool unpublished = false, string body = "Body.")
    {
        Write(course, relative,
              Visibility(relative, unpublished) + $"created: {date}T07:00:00.000-0400\n",
              body);
    }

    /// <summary>
    /// The right publish key for where the page sits: a section-local page
    /// uses <c>publish</c>, a course-level SHARED one uses
    /// <c>publishForSection1</c>. Several of these fixtures put a page in a
    /// course-level folder on purpose, and writing <c>publish: false</c> there
    /// says nothing at all about section 1 — the page reads as visible, and
    /// the test passes or fails for the wrong reason.
    /// </summary>
    private static string Visibility(string relative, bool unpublished)
    {
        string key = relative.StartsWith("section", StringComparison.OrdinalIgnoreCase)
            ? "publish"
            : "publishForSection1";
        return $"{key}: {(unpublished ? "false" : "true")}\n";
    }

    private void Write(string course, string relative, string frontmatter, string body)
    {
        string full = Path.Combine(_folder, "courses", course,
            relative.Replace('/', Path.DirectorySeparatorChar));
        Directory.CreateDirectory(Path.GetDirectoryName(full)!);
        File.WriteAllText(full, "---\n" + frontmatter + "---\n" + body + "\n");
    }
}
