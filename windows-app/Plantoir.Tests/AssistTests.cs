using Plantoir.Core.Assist;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// The operations an assistant is allowed to ask for. These are the tests that
/// stand in for the safety argument: a plan that reads honestly, a refusal
/// that never guesses, and a write that cannot happen without a backup.
/// </summary>
public class AssistWorkspaceTests : IDisposable
{
    private readonly string _folder = Directory.CreateTempSubdirectory("plantoir-assist").FullName;
    private readonly FakeLauncher _launcher = new();

    public AssistWorkspaceTests()
    {
        File.WriteAllText(Path.Combine(_folder, "preview.ps1"), "# marker");
        File.WriteAllText(Path.Combine(_folder, "deploy.ps1"), "# marker");
        AddCourse("ICS3U", "Introduction to Computer Science", 1, 2);
    }

    public void Dispose()
    {
        try { Directory.Delete(_folder, recursive: true); } catch { }
        GC.SuppressFinalize(this);
    }

    private AssistWorkspace Open() => new(_folder, _launcher);

    // ---- Refusals name what exists --------------------------------------

    [Fact]
    public void AnUnknownFolderIsRefusedWithTheReasonAndTheFix()
    {
        string empty = Directory.CreateTempSubdirectory("plantoir-empty").FullName;
        var refusal = Assert.Throws<AssistRefusal>(() => new AssistWorkspace(empty, _launcher));
        Assert.Contains("isn’t a Plantoir working folder", refusal.Message);
        Directory.Delete(empty, recursive: true);
    }

    [Fact]
    public void AnInventedCourseCodeIsRefusedAndTheRealOnesAreNamed()
    {
        // The measured failure this defends against: asked to "clean up my
        // course", the small model proposed backing up MCV4U — a code it made
        // up, for a request naming no course at all.
        var refusal = Assert.Throws<AssistRefusal>(() => Open().Course("MCV4U"));
        Assert.Equal("There’s no course called “MCV4U” in this working folder. The courses here are ICS3U.",
            refusal.Message);
    }

    [Fact]
    public void ACourseCodeIsMatchedWhateverTheCasing()
    {
        Assert.Equal("ICS3U", Open().Course("ics3u").Code);
    }

    [Fact]
    public void AnUnknownSectionIsRefusedAndTheRealOnesAreNamed()
    {
        var workspace = Open();
        var refusal = Assert.Throws<AssistRefusal>(() => workspace.Section(workspace.Course("ICS3U"), 9));
        Assert.Equal("There’s no section 9 in ICS3U. ICS3U has sections 1 and 2.", refusal.Message);
    }

    [Fact]
    public void ATitleMatchingTwoPagesIsRefusedRatherThanPicked()
    {
        // Publishing the wrong page is the failure the whole design exists to
        // avoid, so an ambiguous title is never resolved by choosing.
        Page("ICS3U", "Concepts/Review.md", draftSection1: true);
        Page("ICS3U", "Exercises/Review.md", draftSection1: true);

        var workspace = Open();
        var refusal = Assert.Throws<AssistRefusal>(
            () => workspace.Page(workspace.Course("ICS3U"), 1, "Review"));
        Assert.Contains("has 2 pages called “Review”", refusal.Message);
        Assert.Contains("Say which one you mean.", refusal.Message);
    }

    // ---- The plan --------------------------------------------------------

    [Fact]
    public void ThePlanPicksTheRightKeyForSharedAndSectionLocalPages()
    {
        // The single most error-prone thing in the whole feature, and the one
        // no model should ever be asked to decide.
        Page("ICS3U", "Concepts/Ohm's Law.md", draftSection1: true);
        Page("ICS3U", "section1/All Classes/Unit 2, Day 3.md", draft: true,
             body: "Concept: [[Ohm's Law]]");

        var plan = Open().PlanPublish("ICS3U", 1, new[] { "Unit 2, Day 3" }, includeLinked: true);

        Assert.Equal("publish", Assert.Single(plan.Named).FrontmatterKey);
        Assert.Equal("publishForSection1", Assert.Single(plan.Linked).FrontmatterKey);
    }

    [Fact]
    public void ThePlanReadsAsASentenceATeacherCanCheck()
    {
        Page("ICS3U", "Concepts/Ohm's Law.md", draftSection1: true);
        Page("ICS3U", "section1/All Classes/Unit 2, Day 3.md", draft: true,
             body: "Concept: [[Ohm's Law]]");

        var plan = Open().PlanPublish("ICS3U", 1, new[] { "Unit 2, Day 3" }, includeLinked: true);

        // Every changing page names its display title and transition.
        Assert.Equal(
            "ICS3U Section 1: publishing.\n\n" +
            "2 pages would change:\n" +
            "“Unit 2, Day 3” will become visible.\n" +
            "“Ohm's Law” will become visible.",
            plan.Describe());
    }

    [Fact]
    public void APlanThatWouldChangeNothingSaysSoAndCountsTheLinksItFollowed()
    {
        Page("ICS3U", "Concepts/Ohm's Law.md", draftSection1: false);
        Page("ICS3U", "section1/All Classes/Unit 2, Day 3.md", draft: false,
             body: "Concept: [[Ohm's Law]]");

        var plan = Open().PlanPublish("ICS3U", 1, new[] { "Unit 2, Day 3" }, includeLinked: true);

        Assert.True(plan.ChangesNothing);
        Assert.Contains("No page's visibility would change.", plan.Describe());
        Assert.Contains("2 pages are already visible.", plan.Describe());
    }

    [Fact]
    public void TheLinkCountAndTheChangeCountAreNeverTheSamePhrase()
    {
        Page("ICS3U", "Concepts/Ohm's Law.md", draftSection1: true);
        Page("ICS3U", "Exercises/Ohm's Law Practice.md", draftSection1: false);
        Page("ICS3U", "section1/All Classes/Unit 4, Day 5.md", draft: false,
             body: "[[Ohm's Law]] and [[Ohm's Law Practice]]");

        string description = Open()
            .PlanPublish("ICS3U", 1, new[] { "Unit 4, Day 5" }, includeLinked: true).Describe();

        Assert.Contains("1 page would change:\n“Ohm's Law” will become visible.", description);
        Assert.Contains("2 pages are already visible.", description);
    }

    [Fact]
    public void AnUnresolvableLinkIsReportedRatherThanDroppedQuietly()
    {
        Page("ICS3U", "section1/All Classes/Unit 2, Day 3.md", draft: true,
             body: "Concept: [[A Page That Does Not Exist]]");

        var plan = Open().PlanPublish("ICS3U", 1, new[] { "Unit 2, Day 3" }, includeLinked: true);

        Assert.Equal("“A Page That Does Not Exist” doesn’t match any page in this section.",
            Assert.Single(plan.Problems));
        Assert.Contains("1 page would change:\n“Unit 2, Day 3” will become visible.", plan.Describe());
    }

    [Fact]
    public void HidingIsPlannedWithTheOppositePolarity()
    {
        Page("ICS3U", "section1/All Classes/Unit 2, Day 3.md", draft: false);
        var plan = Open().PlanPublish("ICS3U", 1, new[] { "Unit 2, Day 3" }, includeLinked: false, draft: true);
        Assert.StartsWith("ICS3U Section 1: unpublishing.", plan.Describe());
        Assert.Contains("“Unit 2, Day 3” will become hidden.", plan.Describe());
        Assert.True(Assert.Single(plan.Named).WillChange);
    }

    // ---- What the single-page surface could not express -------------------

    [Fact]
    public void SeveralPagesArePlannedAsOneChange()
    {
        // 25 classes used to mean 25 calls and 25 deploys.
        for (int day = 2; day <= 5; day++)
            Page("ICS3U", $"section1/All Classes/Unit 1, Day {day}.md", draft: false);

        var plan = Open().PlanPublish("ICS3U", 1,
            new[] { "Unit 1, Day 2", "Unit 1, Day 3", "Unit 1, Day 4", "Unit 1, Day 5" },
            includeLinked: false, draft: true);

        Assert.Equal(4, plan.Named.Count());
        Assert.StartsWith("ICS3U Section 1: unpublishing.\n\n4 pages would change:", plan.Describe());
    }


    [Fact]
    public void ACourseLevelPageCanBeNamedDirectly()
    {
        // The Safety Contract case: a page linked from a class that must stay
        // up AND one that must come down. Naming it directly is the only way
        // to express "leave this one alone" — with class-page-only tools the
        // constraint was unsatisfiable.
        Page("ICS3U", "Setup/Safety Contract.md", draftSection1: true);

        var plan = Open().PlanPublish("ICS3U", 1, new[] { "Safety Contract" }, includeLinked: false);

        var page = Assert.Single(plan.Named);
        Assert.Equal("publishForSection1", page.FrontmatterKey);
        Assert.True(page.WillChange);
    }

    [Fact]
    public void APageReachedFromTwoClassesIsCountedOnce()
    {
        Page("ICS3U", "Setup/Safety Contract.md", draftSection1: false);
        Page("ICS3U", "section1/All Classes/Unit 1, Day 2.md", draft: false, body: "[[Safety Contract]]");
        Page("ICS3U", "section1/All Classes/Unit 1, Day 3.md", draft: false, body: "[[Safety Contract]]");

        var plan = Open().PlanPublish("ICS3U", 1,
            new[] { "Unit 1, Day 2", "Unit 1, Day 3" }, includeLinked: true, draft: true);

        Assert.Single(plan.Linked);
        Assert.Equal(3, plan.Pages.Count);
    }

    // ---- "Oops" ------------------------------------------------------------

    [Fact]
    public async Task TheWrongClassPublishedInAHurryCanBeTakenBack()
    {
        var history = new UndoHistory();
        var workspace = new AssistWorkspace(_folder, _launcher, undo: history);
        Page("ICS3U", "section1/All Classes/Unit 1, Day 2.md", draft: true, body: "[[Ohm's Law]]");
        Page("ICS3U", "Concepts/Ohm's Law.md", draftSection1: true);
        string page = Path.Combine(_folder, "courses", "ICS3U", "section1", "All Classes", "Unit 1, Day 2.md");
        string concept = Path.Combine(_folder, "courses", "ICS3U", "Concepts", "Ohm's Law.md");

        await workspace.Apply(workspace.PlanPublish("ICS3U", 1, new[] { "Unit 1, Day 2" },
            includeLinked: true, publishes: false));
        Assert.Contains("publish: true", File.ReadAllText(page));
        Assert.Contains("publishForSection1: true", File.ReadAllText(concept));

        var result = history.Undo();

        Assert.True(result.Succeeded);
        Assert.Empty(result.Skipped);
        Assert.Contains("publish: false", File.ReadAllText(page));
        Assert.Contains("publishForSection1: false", File.ReadAllText(concept));
        // PAST TENSE. This clause is read back inside AssistWording.Undid —
        // "Earlier, you {change}." — so a gerund makes a broken sentence.
        Assert.Contains("published “Unit 1, Day 2”", result.Description);
        Assert.StartsWith("Earlier, you published “Unit 1, Day 2”",
                          AssistWording.Undid(result.Description));
    }

    [Fact]
    public async Task UndoingRefusesToOverwriteWorkSomebodyElseDidSince()
    {
        // The teacher edited the page in Obsidian after publishing. Our copy
        // of "before" is stale, and writing it back would throw their work
        // away — so that file is named and left alone.
        var history = new UndoHistory();
        var workspace = new AssistWorkspace(_folder, _launcher, undo: history);
        Page("ICS3U", "section1/All Classes/Unit 1, Day 2.md", draft: true);
        string page = Path.Combine(_folder, "courses", "ICS3U", "section1", "All Classes", "Unit 1, Day 2.md");

        await workspace.Apply(workspace.PlanPublish("ICS3U", 1, new[] { "Unit 1, Day 2" },
            includeLinked: false, publishes: false));
        File.AppendAllText(page, "\nA sentence the teacher typed afterwards.\n");

        var result = history.Undo();

        Assert.Empty(result.Restored);
        Assert.Single(result.Skipped);
        Assert.Contains("A sentence the teacher typed afterwards.", File.ReadAllText(page));
        // Still on the list, so it can be retried.
        Assert.Single(history.Entries);
    }

    [Fact]
    public async Task UndoStepsBackThroughSeveralChanges()
    {
        var history = new UndoHistory();
        var workspace = new AssistWorkspace(_folder, _launcher, undo: history);
        Page("ICS3U", "section1/All Classes/Unit 1, Day 1.md", draft: true);
        Page("ICS3U", "section1/All Classes/Unit 1, Day 2.md", draft: true);

        await workspace.Apply(workspace.PlanPublish("ICS3U", 1, new[] { "Unit 1, Day 1" },
            includeLinked: false, publishes: false));
        await workspace.Apply(workspace.PlanPublish("ICS3U", 1, new[] { "Unit 1, Day 2" },
            includeLinked: false, publishes: false));
        Assert.Equal(2, history.Entries.Count);

        history.Undo();
        Assert.Contains("publish: false", File.ReadAllText(Path.Combine(
            _folder, "courses", "ICS3U", "section1", "All Classes", "Unit 1, Day 2.md")));
        Assert.Contains("publish: true", File.ReadAllText(Path.Combine(
            _folder, "courses", "ICS3U", "section1", "All Classes", "Unit 1, Day 1.md")));

        history.Undo();
        Assert.Contains("publish: false", File.ReadAllText(Path.Combine(
            _folder, "courses", "ICS3U", "section1", "All Classes", "Unit 1, Day 1.md")));
        Assert.Empty(history.Entries);
    }

    [Fact]
    public void UndoingWithNothingToUndoSaysSoPlainly()
    {
        var history = new UndoHistory();
        var result = history.Undo();
        Assert.False(result.Succeeded);
        Assert.Equal("This conversation hasn’t changed anything yet.", result.Description);
    }

    [Fact]
    public async Task AnOperationThatChangedNothingIsNotRememberedAsUndoable()
    {
        // Otherwise "undo" would burn a step doing nothing, and the teacher
        // would have to ask twice to reach the change they meant.
        var history = new UndoHistory();
        var workspace = new AssistWorkspace(_folder, _launcher, undo: history);
        Page("ICS3U", "section1/All Classes/Unit 1, Day 2.md", draft: false);

        await workspace.Apply(workspace.PlanPublish("ICS3U", 1, new[] { "Unit 1, Day 2" },
            includeLinked: false, publishes: false));

        Assert.Empty(history.Entries);
    }

    // ---- Hiding: safe, not a mirror ----------------------------------------

    [Fact]
    public void HidingLeavesAPageAnotherVisibleClassStillUses()
    {
        // The Safety Contract case. Publishing leaves no record of who
        // published what, so hiding cannot be a true inverse — but it can
        // refuse to take down anything still in use, which is the half that
        // matters.
        Page("ICS3U", "section1/All Classes/Unit 1, Day 1.md", draft: false,
             body: "Setup: [[Safety Contract]]");
        Page("ICS3U", "section1/All Classes/Unit 1, Day 2.md", draft: false,
             body: "Also: [[Safety Contract]] and [[Just Mine]]");
        Page("ICS3U", "Setup/Safety Contract.md", draftSection1: false);
        Page("ICS3U", "Concepts/Just Mine.md", draftSection1: false);

        var plan = Open().PlanPublish("ICS3U", 1, new[] { "Unit 1, Day 2" },
            includeLinked: true, draft: true);

        Assert.DoesNotContain(plan.Pages, p => p.Title == "Safety Contract");
        Assert.Contains(plan.Pages, p => p.Title == "Just Mine");
        Assert.Contains(plan.Problems, p => p.Contains("another class students can still see links to it"));
        Assert.Empty(plan.Dangling);
    }

    [Fact]
    public void APageOnlyHiddenClassesUseComesDown()
    {
        // The other side of the same rule: nothing visible reaches it, so
        // there is nothing to break.
        Page("ICS3U", "section1/All Classes/Unit 1, Day 1.md", draft: true,
             body: "Setup: [[Shared Only With Hidden]]");
        Page("ICS3U", "section1/All Classes/Unit 1, Day 2.md", draft: false,
             body: "Also: [[Shared Only With Hidden]]");
        Page("ICS3U", "Setup/Shared Only With Hidden.md", draftSection1: false);

        var plan = Open().PlanPublish("ICS3U", 1, new[] { "Unit 1, Day 2" },
            includeLinked: true, draft: true);

        Assert.Contains(plan.Pages, p => p.Title == "Shared Only With Hidden");
    }

    [Fact]
    public void HidingSeveralClassesAtOnceDoesNotCountThemAsStillUsingAPage()
    {
        // Both classes are on their way out, so the page they share comes
        // down with them.
        Page("ICS3U", "section1/All Classes/Unit 1, Day 1.md", draft: false, body: "[[Shared]]");
        Page("ICS3U", "section1/All Classes/Unit 1, Day 2.md", draft: false, body: "[[Shared]]");
        Page("ICS3U", "Concepts/Shared.md", draftSection1: false);

        var plan = Open().PlanPublish("ICS3U", 1,
            new[] { "Unit 1, Day 1", "Unit 1, Day 2" }, includeLinked: true, draft: true);

        Assert.Contains(plan.Pages, p => p.Title == "Shared");
    }

    [Fact]
    public void CurriculumIsNeverHidden()
    {
        Page("ICS3U", "section1/All Classes/Unit 1, Day 2.md", draft: false,
             body: "Expectation: [[B2.1]]");
        Page("ICS3U", "Ontario Curriculum/B2.1.md", draftSection1: false);

        var plan = Open().PlanPublish("ICS3U", 1, new[] { "Unit 1, Day 2" },
            includeLinked: true, draft: true);

        Assert.DoesNotContain(plan.Pages, p => p.Title == "B2.1");
        Assert.Contains(plan.Problems, p => p.Contains("the curriculum"));
    }

    // ---- Two hops out ------------------------------------------------------

    [Fact]
    public void PublishingFollowsASecondHopSoNoVisiblePagePointsAtAHiddenOne()
    {
        // A class links to a concept; the concept links to the expectations
        // behind it. One hop leaves a visible page pointing at a hidden one.
        Page("ICS3U", "section1/All Classes/Unit 2, Day 3.md", draft: true, body: "Concept: [[Recursion]]");
        Page("ICS3U", "Concepts/Recursion.md", draftSection1: true, body: "See [[E2.6]] and [[E2.2]].");
        Page("ICS3U", "Curriculum/E2.6.md", draftSection1: true);
        Page("ICS3U", "Curriculum/E2.2.md", draftSection1: true);

        var plan = Open().PlanPublish("ICS3U", 1, new[] { "Unit 2, Day 3" }, includeLinked: true);

        Assert.Contains(plan.Pages, p => p.Title == "E2.6" && !p.Draft);
        Assert.Contains(plan.Pages, p => p.Title == "E2.2" && !p.Draft);
        Assert.Empty(plan.Dangling);
    }

    [Fact]
    public void ASecondHopPageAlreadyPublishedKeepsItsStateAndItsDate()
    {
        // It belongs to whatever published it. Left entirely alone.
        Page("ICS3U", "section1/All Classes/Unit 2, Day 3.md", draft: true, body: "Concept: [[Recursion]]");
        Page("ICS3U", "Concepts/Recursion.md", draftSection1: true, body: "See [[E2.6]].");
        Write("ICS3U", "Curriculum/E2.6.md",
              "draftSection1: false\ncreatedSection1: 2026-01-05T07:00:00.000-0400");
        Page("ICS3U", "section1/All Classes/Unit 2, Day 3.md", draft: true, body: "Concept: [[Recursion]]");

        var plan = Open().PlanPublish("ICS3U", 1, new[] { "Unit 2, Day 3" }, includeLinked: true);

        Assert.DoesNotContain(plan.Pages, p => p.Title == "E2.6");
        Assert.DoesNotContain(plan.InheritedDates, d => d.Title == "E2.6");
    }

    [Fact]
    public void ASecondHopPageTakesTheDateOfTheClassThatBroughtItIn()
    {
        Write("ICS3U", "section1/All Classes/Unit 2, Day 3.md",
              "draft: true\ncreated: 2026-10-05T07:00:00.000-0400", "Concept: [[Recursion]]");
        Page("ICS3U", "Concepts/Recursion.md", draftSection1: true, body: "See [[E2.6]].");
        Page("ICS3U", "Curriculum/E2.6.md", draftSection1: true);

        var plan = Open().PlanPublish("ICS3U", 1, new[] { "Unit 2, Day 3" }, includeLinked: true);

        Assert.Equal(new DateOnly(2026, 10, 5),
            Assert.Single(plan.InheritedDates, d => d.Title == "E2.6").New);
    }

    [Fact]
    public void HidingNeverFollowsASecondHop()
    {
        // Each extra hop can swallow a page a still-published class needs, and
        // the further out it goes the less a teacher can see it happening.
        Page("ICS3U", "section1/All Classes/Unit 2, Day 3.md", draft: false, body: "Concept: [[Recursion]]");
        Page("ICS3U", "Concepts/Recursion.md", draftSection1: false, body: "See [[E2.6]].");
        Page("ICS3U", "Curriculum/E2.6.md", draftSection1: false);

        var plan = Open().PlanPublish("ICS3U", 1, new[] { "Unit 2, Day 3" },
            includeLinked: true, draft: true);

        Assert.Contains(plan.Pages, p => p.Title == "Recursion");
        Assert.DoesNotContain(plan.Pages, p => p.Title == "E2.6");
    }

    [Fact]
    public void PublishingAClassNeverDragsAnotherClassLive()
    {
        // "Publish tomorrow's class" must not put next week's lesson in front
        // of students because something mentioned it.
        Page("ICS3U", "section1/All Classes/Unit 2, Day 3.md", draft: true,
             body: "Recap of [[Unit 2, Day 1]], concept [[Recursion]]");
        Page("ICS3U", "section1/All Classes/Unit 2, Day 1.md", draft: true);
        Page("ICS3U", "Concepts/Recursion.md", draftSection1: true, body: "See [[Unit 2, Day 9]].");
        Page("ICS3U", "section1/All Classes/Unit 2, Day 9.md", draft: true);

        var plan = Open().PlanPublish("ICS3U", 1, new[] { "Unit 2, Day 3" }, includeLinked: true);

        Assert.DoesNotContain(plan.Pages, p => p.Title == "Unit 2, Day 1");   // one hop
        Assert.DoesNotContain(plan.Pages, p => p.Title == "Unit 2, Day 9");   // two hops
        Assert.Contains(plan.Pages, p => p.Title == "Recursion");

        // Not published, but not hidden either: the dead links are reported so
        // the teacher can publish those classes deliberately if they meant to.
        Assert.Contains(plan.Dangling, d => d.To.EndsWith("Unit 2, Day 1.md", StringComparison.Ordinal));
        Assert.Contains(plan.Dangling, d => d.To.EndsWith("Unit 2, Day 9.md", StringComparison.Ordinal));
    }

    private void Write(string course, string relative, string frontmatter, string body = "Body.")
    {
        string full = Path.Combine(_folder, "courses", course,
            relative.Replace('/', Path.DirectorySeparatorChar));
        Directory.CreateDirectory(Path.GetDirectoryName(full)!);
        File.WriteAllText(full, $"---\n{frontmatter}\n---\n{body}\n");
    }

    // ---- Publishing the day's class, end to end ---------------------------

    /// <summary>A section index shaped like the example content's.</summary>
    private void Index(string course, int section, string showing, string created)
    {
        string body = showing.Length == 0
            ? "# Most Recent Class\n\n![[Key Links]]\n"
            : $"# Most Recent Class\n![[{showing}]]\n\n![[Key Links]]\n";
        string full = Path.Combine(_folder, "courses", course, $"section{section}", "index.md");
        Directory.CreateDirectory(Path.GetDirectoryName(full)!);
        File.WriteAllText(full,
            $"---\ntitle: Section {section}\ncreated: {created}T07:00:00.000-0400\ndraft: false\n---\n{body}");
    }

    private void DatedClass(string course, string title, string date, bool draft, string body = "Body.") =>
        File.WriteAllText(EnsurePath(course, $"section1/All Classes/{title}.md"),
            $"---\npublish: {(draft ? "false" : "true")}\ncreated: {date}T07:00:00.000-0400\n---\n{body}\n");

    private string EnsurePath(string course, string relative)
    {
        string full = Path.Combine(_folder, "courses", course,
            relative.Replace('/', Path.DirectorySeparatorChar));
        Directory.CreateDirectory(Path.GetDirectoryName(full)!);
        return full;
    }

    [Fact]
    public void APageUsedByTwoClassesKeepsTheDateOfTheOneThatIntroducedIt()
    {
        // The teacher's case: Unit 2, Day 3 uses a concept first; Unit 2,
        // Day 4 uses it again. It keeps Day 3's date, whichever is published.
        DatedClass("ICS3U", "Unit 2, Day 3", "2026-10-05", draft: true, body: "[[Recursion]]");
        DatedClass("ICS3U", "Unit 2, Day 4", "2026-10-06", draft: true, body: "Again: [[Recursion]]");
        Page("ICS3U", "Concepts/Recursion.md", draftSection1: true);
        Index("ICS3U", 1, "", "2026-10-01");
        var workspace = Open();

        // Publishing the FIRST class dates it to that class.
        var first = workspace.PlanPublish("ICS3U", 1, new[] { "Unit 2, Day 3" }, includeLinked: true);
        Assert.Equal(new DateOnly(2026, 10, 5), Assert.Single(first.InheritedDates).New);

        // Publishing the SECOND leaves it on the first class's date.
        var second = workspace.PlanPublish("ICS3U", 1, new[] { "Unit 2, Day 4" }, includeLinked: true);
        Assert.Equal(new DateOnly(2026, 10, 5), Assert.Single(second.InheritedDates).New);
    }

    [Fact]
    public async Task PublishingTheSecondClassLeavesTheSharedPagesDateAlone()
    {
        // End to end, in the order a teacher would do it: publish Day 3, then
        // Day 4, and check the concept never moved off Day 3's date.
        DatedClass("ICS3U", "Unit 2, Day 3", "2026-10-05", draft: true, body: "[[Recursion]]");
        DatedClass("ICS3U", "Unit 2, Day 4", "2026-10-06", draft: true, body: "Again: [[Recursion]]");
        Page("ICS3U", "Concepts/Recursion.md", draftSection1: true);
        Index("ICS3U", 1, "", "2026-10-01");
        var workspace = Open();

        await workspace.Apply(workspace.PlanPublish("ICS3U", 1, new[] { "Unit 2, Day 3" },
            includeLinked: true, publishes: false));
        await workspace.Apply(workspace.PlanPublish("ICS3U", 1, new[] { "Unit 2, Day 4" },
            includeLinked: true, publishes: false));

        string concept = File.ReadAllText(
            Path.Combine(_folder, "courses", "ICS3U", "Concepts", "Recursion.md"));
        Assert.Contains("createdSection1: 2026-10-05", concept);   // Day 3's date, not Day 4's
        Assert.Contains("publishForSection1: true", concept);
    }

    [Fact]
    public void ASharedPageThatWasNeverDatedIsStillGivenTheIntroducingClassesDate()
    {
        // The case the old rule got wrong: skipping anything more than one
        // class links to left a never-dated page on whatever it happened to
        // have. Publishing either class now dates it from Day 3.
        DatedClass("ICS3U", "Unit 2, Day 3", "2026-10-05", draft: true, body: "[[Recursion]]");
        DatedClass("ICS3U", "Unit 2, Day 4", "2026-10-06", draft: true, body: "Again: [[Recursion]]");
        Page("ICS3U", "Concepts/Recursion.md", draftSection1: true);   // no date at all
        Index("ICS3U", 1, "", "2026-10-01");

        var plan = Open().PlanPublish("ICS3U", 1, new[] { "Unit 2, Day 4" }, includeLinked: true);

        var dated = Assert.Single(plan.InheritedDates);
        Assert.Equal("Recursion", dated.Title);
        Assert.Null(dated.Current);
        Assert.Equal(new DateOnly(2026, 10, 5), dated.New);
    }

    [Fact]
    public void PublishingTheDaysClassMovesTheFrontPageAndTheDatesWithIt()
    {
        // The whole of "publish tomorrow's class", in one plan.
        DatedClass("ICS3U", "Unit 1, Day 1", "2026-09-08", draft: false, body: "[[Shared Page]]");
        DatedClass("ICS3U", "Unit 1, Day 2", "2026-09-09", draft: true,
                   body: "Concept: [[Only Mine]] and [[Shared Page]]");
        Page("ICS3U", "Concepts/Only Mine.md", draftSection1: true);
        Page("ICS3U", "Concepts/Shared Page.md", draftSection1: true);
        Index("ICS3U", 1, "Unit 1, Day 1", "2026-09-08");

        var workspace = Open();
        var plan = workspace.PlanPublish("ICS3U", 1, new[] { "Unit 1, Day 2" }, includeLinked: true);

        // Only Mine is used by this class alone, so it takes this class's date.
        Assert.Equal(new DateOnly(2026, 9, 9),
            Assert.Single(plan.InheritedDates, d => d.Title == "Only Mine").New);

        // Shared Page is used by Day 1 too, so it takes DAY 1's date — the
        // class that introduced it — not the one being published.
        Assert.Equal(new DateOnly(2026, 9, 8),
            Assert.Single(plan.InheritedDates, d => d.Title == "Shared Page").New);

        // …and it is published either way.
        Assert.Contains(plan.Pages, p => p.Title == "Shared Page" && !p.Draft);

        Assert.Equal("Unit 1, Day 2", plan.Index!.ToClass);
        Assert.Equal(new DateOnly(2026, 9, 9), plan.Index.ToDate);
    }

    [Fact]
    public async Task ApplyingItRewritesTheIndexEmbedAndNothingElse()
    {
        DatedClass("ICS3U", "Unit 1, Day 1", "2026-09-08", draft: false);
        DatedClass("ICS3U", "Unit 1, Day 2", "2026-09-09", draft: true);
        Index("ICS3U", 1, "Unit 1, Day 1", "2026-09-08");

        var workspace = Open();
        await workspace.Apply(workspace.PlanPublish("ICS3U", 1, new[] { "Unit 1, Day 2" },
            includeLinked: false, publishes: false));

        string index = File.ReadAllText(Path.Combine(_folder, "courses", "ICS3U", "section1", "index.md"));
        Assert.Contains("# Most Recent Class\n![[Unit 1, Day 2]]", index);
        Assert.Contains("created: 2026-09-09T07:00:00.000-0400", index);
        Assert.Contains("![[Key Links]]", index);      // the rest of the body untouched
        Assert.Contains("title: Section 1", index);
        Assert.DoesNotContain("Unit 1, Day 1", index);
    }

    [Fact]
    public void PublishingAnOlderMissedClassDoesNotDragTheFrontPageBackwards()
    {
        // "Most Recent Class" is computed, not remembered — so catching up on
        // a class from last week leaves the front page where it belongs.
        DatedClass("ICS3U", "Unit 1, Day 1", "2026-09-08", draft: true);
        DatedClass("ICS3U", "Unit 1, Day 5", "2026-09-14", draft: false);
        Index("ICS3U", 1, "Unit 1, Day 5", "2026-09-14");

        var plan = Open().PlanPublish("ICS3U", 1, new[] { "Unit 1, Day 1" }, includeLinked: false);

        Assert.Equal("Unit 1, Day 5", plan.Index!.ToClass);
        Assert.False(plan.Index.WillChange);
    }

    [Fact]
    public void HidingTheNewestClassFallsBackToThePreviousOne()
    {
        // The same computed rule, in the other direction, with no code for it.
        DatedClass("ICS3U", "Unit 1, Day 1", "2026-09-08", draft: false);
        DatedClass("ICS3U", "Unit 1, Day 2", "2026-09-09", draft: false);
        Index("ICS3U", 1, "Unit 1, Day 2", "2026-09-09");

        var plan = Open().PlanPublish("ICS3U", 1, new[] { "Unit 1, Day 2" },
            includeLinked: false, draft: true);

        Assert.Equal("Unit 1, Day 1", plan.Index!.ToClass);
        Assert.Equal(new DateOnly(2026, 9, 8), plan.Index.ToDate);
    }

    [Fact]
    public void AnIndexWithNoMostRecentClassHeadingIsReportedNotInvented()
    {
        DatedClass("ICS3U", "Unit 1, Day 2", "2026-09-09", draft: true);
        File.WriteAllText(EnsurePath("ICS3U", "section1/index.md"),
            "---\ntitle: Section 1\ncreated: 2026-09-08T07:00:00.000-0400\ndraft: false\n---\n");

        var plan = Open().PlanPublish("ICS3U", 1, new[] { "Unit 1, Day 2" }, includeLinked: false);

        Assert.True(plan.Index!.HeadingMissing);
        Assert.False(plan.Index.WillChange);
        Assert.Contains("“Unit 1, Day 2” will become visible.", plan.Describe());
    }

    [Fact]
    public void TheClassOnADayIsFoundByItsOwnDate()
    {
        DatedClass("ICS3U", "Unit 1, Day 1", "2026-09-08", draft: false);
        DatedClass("ICS3U", "Unit 1, Day 2", "2026-09-09", draft: true);
        var workspace = Open();

        string found = workspace.ClassOn(workspace.Course("ICS3U"), 1, new DateOnly(2026, 9, 9));

        Assert.EndsWith("Unit 1, Day 2.md", found, StringComparison.Ordinal);
    }

    [Fact]
    public void ADayWithNoClassSaysWhenTheClassesActuallyRun()
    {
        DatedClass("ICS3U", "Unit 1, Day 1", "2026-09-08", draft: false);
        var workspace = Open();

        var refusal = Assert.Throws<AssistRefusal>(
            () => workspace.ClassOn(workspace.Course("ICS3U"), 1, new DateOnly(2026, 12, 25)));

        Assert.Equal("ICS3U Section 1 has no class on 2026-12-25. " +
                     "Its classes run 2026-09-08 to 2026-09-08.", refusal.Message);
    }

    [Fact]
    public void TwoClassesOnOneDayAreRefusedRatherThanPicked()
    {
        DatedClass("ICS3U", "Unit 1, Day 1", "2026-09-08", draft: false);
        DatedClass("ICS3U", "Unit 1, Day 2", "2026-09-08", draft: true);
        var workspace = Open();

        var refusal = Assert.Throws<AssistRefusal>(
            () => workspace.ClassOn(workspace.Course("ICS3U"), 1, new DateOnly(2026, 9, 8)));

        Assert.Contains("has 2 classes on 2026-09-08", refusal.Message);
        Assert.Contains("Say which one you mean.", refusal.Message);
    }

    // ---- The first publish, and cutting loose from last year --------------


    [Fact]
    public void RollingOverCutsTheSectionLooseButKeepsTheOldSitesDetails()
    {
        // The marker names a site with the year in it. Rolling over without
        // removing it would republish over last year's URL, which last year's
        // students may still be reading. Renamed rather than deleted: it holds
        // the site id, and there is no other way back to it.
        var workspace = Open();
        var course = workspace.Course("ICS3U");

        string? kept = workspace.ReleaseSite(course, 1);

        Assert.NotNull(kept);
        Assert.False(File.Exists(Path.Combine(_folder, "courses", "ICS3U", ".netlify_sites", "section1.json")));
        string keptFull = Path.Combine(_folder, kept!.Replace('/', Path.DirectorySeparatorChar));
        Assert.True(File.Exists(keptFull));
        Assert.Contains("ics3u-s1-2026-gordon", File.ReadAllText(keptFull));
    }

    [Fact]
    public void CuttingLooseASectionThatNeverHadASiteSaysNothingHappened()
    {
        File.Delete(Path.Combine(_folder, "courses", "ICS3U", ".netlify_sites", "section2.json"));
        var workspace = Open();
        Assert.Null(workspace.ReleaseSite(workspace.Course("ICS3U"), 2));
    }

    // ---- A session locked to one course ----------------------------------

    [Fact]
    public void ALockedSessionCannotReachAnotherCourse()
    {
        // The request was about one course, so reaching another is never
        // right. A lock holds however the conversation wanders; an
        // instruction in a prompt does not.
        AddCourse("SNC1W", "Science", 1);
        var workspace = new AssistWorkspace(_folder, _launcher, lockedCourse: "ICS3U");

        var refusal = Assert.Throws<AssistRefusal>(() => workspace.Course("SNC1W"));

        Assert.Equal("This session is working on ICS3U only, so SNC1W can’t be reached from here. " +
                     "Start again from SNC1W in Plantoir to work on that course.", refusal.Message);
    }

    [Fact]
    public void ALockedSessionDoesNotEvenListTheOtherCourses()
    {
        AddCourse("SNC1W", "Science", 1);
        var workspace = new AssistWorkspace(_folder, _launcher, lockedCourse: "ICS3U");
        Assert.Equal("ICS3U", Assert.Single(workspace.Courses()).Code);
    }

    [Fact]
    public void ALockedSessionStillWorksOnItsOwnCourse()
    {
        var workspace = new AssistWorkspace(_folder, _launcher, lockedCourse: "ics3u");
        Assert.Equal("ICS3U", workspace.Course("ICS3U").Code);
    }

    [Fact]
    public void LockingToACourseThatIsNotThereFailsAtStartupNotMidConversation()
    {
        var refusal = Assert.Throws<AssistRefusal>(
            () => new AssistWorkspace(_folder, _launcher, lockedCourse: "NOPE1"));
        Assert.Contains("There’s no course called “NOPE1”", refusal.Message);
    }

    // ---- Telling the app an assistant is at work --------------------------

    [Fact]
    public void ALeaseHeldByThisProcessIsNotAConflictWithItself()
    {
        // A process is never in its own way; counting our own lease would have
        // the app refuse its own publish.
        using var lease = WorkLease.Take(_folder, "ICS3U", WorkLease.Assisting);
        Assert.Empty(WorkLease.HeldBy(_folder, "ICS3U"));
    }

    [Fact]
    public void TheServerRefusesToBuildWhilePlantoirIsBuildingTheSameCourse()
    {
        // The other half of the protocol: the app writes what it is doing and
        // the server reads it. Both build into .merged_output/section<N>/,
        // which the build clears before writing.
        Page("ICS3U", "section1/All Classes/Unit 2, Day 3.md", draft: true);
        using var child = StartALongRunningChild();
        try
        {
            WriteWorkLease("ICS3U", WorkLease.Building, child.Id, child.ProcessName);
            var workspace = Open();
            var plan = workspace.PlanPublish("ICS3U", 1, new[] { "Unit 2, Day 3" }, includeLinked: false);

            var refusal = Assert.ThrowsAsync<AssistRefusal>(() => workspace.Apply(plan)).Result;

            Assert.Contains("Plantoir is building ICS3U right now", refusal.Message);
            Assert.Contains("Reading and planning are fine meanwhile.", refusal.Message);
            Assert.Empty(_launcher.Runs);                 // never got as far as a build
            Assert.Contains("publish: false",
                File.ReadAllText(Path.Combine(_folder, "courses", "ICS3U",
                    "section1", "All Classes", "Unit 2, Day 3.md")));   // and never edited
        }
        finally { try { child.Kill(entireProcessTree: true); } catch { } }
    }

    [Fact]
    public void AnOpenPreviewNeverStopsTheAssistantFromWorking()
    {
        // The whole point of a separate window: the teacher watches the preview
        // of the section while asking for the next change to it. A preview
        // lease is held for as long as the SERVER runs, so treating it as a
        // conflict meant a teacher had to close the very thing they were using
        // to judge the assistant's work. Only an in-flight BUILD is exclusive.
        Page("ICS3U", "section1/All Classes/Unit 2, Day 3.md", draft: true);
        using var child = StartALongRunningChild();
        try
        {
            WriteWorkLease("ICS3U", WorkLease.Previewing, child.Id, child.ProcessName);
            var workspace = Open();
            var plan = workspace.PlanPublish("ICS3U", 1, new[] { "Unit 2, Day 3" }, includeLinked: false);

            var result = workspace.Apply(plan).Result;

            Assert.True(result.Succeeded);
            Assert.Contains("publish: true",
                File.ReadAllText(Path.Combine(_folder, "courses", "ICS3U",
                    "section1", "All Classes", "Unit 2, Day 3.md")));
        }
        finally { try { child.Kill(entireProcessTree: true); } catch { } }
    }

    [Fact]
    public void ReadingAndPlanningStayAvailableWhilePlantoirIsBusy()
    {
        // A preview rebuilds from source, so an edit lands rather than
        // clashes. Only building is blocked.
        Page("ICS3U", "section1/All Classes/Unit 2, Day 3.md", draft: true);
        using var child = StartALongRunningChild();
        try
        {
            WriteWorkLease("ICS3U", WorkLease.Previewing, child.Id, child.ProcessName);
            var workspace = Open();

            Assert.NotEmpty(workspace.Pages(workspace.Course("ICS3U"), 1));
            var plan = workspace.PlanPublish("ICS3U", 1, new[] { "Unit 2, Day 3" }, includeLinked: false);
            Assert.Single(plan.Changing);
        }
        finally { try { child.Kill(entireProcessTree: true); } catch { } }
    }

    [Fact]
    public void PlantoirBusyOnAnotherCourseDoesNotBlockThisOne()
    {
        AddCourse("SNC1W", "Science", 1);
        Page("ICS3U", "section1/All Classes/Unit 2, Day 3.md", draft: true);
        using var child = StartALongRunningChild();
        try
        {
            WriteWorkLease("SNC1W", WorkLease.Publishing, child.Id, child.ProcessName);
            var workspace = Open();
            var plan = workspace.PlanPublish("ICS3U", 1, new[] { "Unit 2, Day 3" }, includeLinked: false);

            var result = workspace.Apply(plan).Result;

            Assert.True(result.Succeeded);
        }
        finally { try { child.Kill(entireProcessTree: true); } catch { } }
    }

    [Fact]
    public void LinkGraphFollowingLinksExclusionsAndVisibleReferrers()
    {
        Assert.True(LinkGraph.IsLandingPage(@"C:\courses\ICS3U\section1\All Classes\index.md"));
        Assert.True(LinkGraph.IsLandingPage(@"C:\courses\ICS3U\shared\Concepts\index.md"));
        Assert.False(LinkGraph.IsLandingPage(@"C:\courses\ICS3U\shared\Concepts\Variables.md"));

        Assert.True(LinkGraph.IsCurriculum(@"C:\courses\ICS3U\shared\Ontario Curriculum\A1.1.md"));
        Assert.True(LinkGraph.IsCurriculum(@"C:\courses\ICS3U\shared\Curriculum\Expectations.md"));
        Assert.False(LinkGraph.IsCurriculum(@"C:\courses\ICS3U\shared\Concepts\Curriculum.md")); // filename alone doesn't make it curriculum

        var keyLinksTargets = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            @"C:\courses\ICS3U\shared\Key Links Target.md"
        };
        Assert.True(LinkGraph.IsExcludedFromSweep(@"C:\courses\ICS3U\shared\Key Links Target.md", keyLinksTargets));
        Assert.True(LinkGraph.IsExcludedFromSweep(@"C:\courses\ICS3U\section1\Key Links.md"));
        Assert.True(LinkGraph.IsExcludedFromSweep(@"C:\courses\ICS3U\section1\index.md"));
        Assert.True(LinkGraph.IsExcludedFromSweep(@"C:\courses\ICS3U\shared\Curriculum\A1.1.md"));
        Assert.False(LinkGraph.IsExcludedFromSweep(@"C:\courses\ICS3U\shared\Tasks\Project.md", keyLinksTargets));
    }

    [Fact]
    public void CheckSectionReturnsExpectedSummary()
    {
        AddCourse("MCV4U", "Calculus", 1);
        Page("MCV4U", "section1/All Classes/Unit 1, Day 1.md", draft: false);
        Page("MCV4U", "section1/All Classes/Unit 1, Day 2.md", draft: false);

        var workspace = Open();
        var tools = new Plantoir.Mcp.PlantoirTools(workspace);
        string result = tools.CheckSection("MCV4U", 1);

        Assert.Contains("Students would see 2 pages in MCV4U Section 1.", result);
        Assert.Contains("None of the visible pages link to unpublished pages, ensuring that all links are functional and point to published content.", result);
        Assert.Contains("Nothing is being previewed at the moment. Say “Preview” if you would like to look the section over.", result);
    }

    private void WriteWorkLease(string course, string kind, int pid, string name)
    {
        string directory = Path.Combine(_folder, "courses", ".internal", "activity");
        Directory.CreateDirectory(directory);
        File.WriteAllText(Path.Combine(directory, $"{course}.{kind}.{pid}.lease"),
            $"{pid}\n{name}\n2026-08-13T00:00:00Z\n");
    }

    [Fact]
    public void ALeaseWhoseOwnerIsGoneIsNotALease()
    {
        // A killed session must not lock a course forever, and this needs no
        // cleanup pass and no timeout to tune. Uses a real process that has
        // really exited, so the test cannot pass by accident.
        // The name is written from what it WAS, since a process that has
        // exited will not tell you its name any more.
        var child = StartAndStopAChild();
        WriteAssistLease("ICS3U", child.Id, "cmd");

        Assert.False(WorkLease.IsHeld(_folder, "ICS3U", WorkLease.Assisting));
    }

    [Fact]
    public void AnAliveOwnerWithADifferentNameIsARecycledProcessIdNotASession()
    {
        // Process ids get reused. Comparing the name too stops whatever the
        // operating system handed the number to next from holding a course.
        // A live process is used, so only the name can decide it.
        using var child = StartALongRunningChild();
        try
        {
            WriteAssistLease("ICS3U", child.Id, "definitely-not-that-program");
            Assert.False(WorkLease.IsHeld(_folder, "ICS3U", WorkLease.Assisting));

            // …and the same live process WITH its real name does hold it.
            WriteAssistLease("ICS3U", child.Id, child.ProcessName);
            Assert.True(WorkLease.IsHeld(_folder, "ICS3U", WorkLease.Assisting));
        }
        finally { try { child.Kill(entireProcessTree: true); } catch { } }
    }

    private void WriteAssistLease(string course, int pid, string name) =>
        WriteWorkLease(course, WorkLease.Assisting, pid, name);

    private static System.Diagnostics.Process StartAndStopAChild()
    {
        var child = System.Diagnostics.Process.Start(
            new System.Diagnostics.ProcessStartInfo("cmd.exe", "/c exit")
            { CreateNoWindow = true, UseShellExecute = false })!;
        child.WaitForExit();
        return child;
    }

    private static System.Diagnostics.Process StartALongRunningChild() =>
        System.Diagnostics.Process.Start(
            new System.Diagnostics.ProcessStartInfo("cmd.exe", "/c pause")
            { CreateNoWindow = true, UseShellExecute = false, RedirectStandardInput = true })!;

    [Fact]
    public void AnAssistantOnOneCourseLeavesEveryOtherCourseFree()
    {
        // The whole point of a per-course lease: a teacher revising ICS3U with
        // Claude can still preview and publish everything else.
        AddCourse("SNC1W", "Science", 1);
        using var child = StartALongRunningChild();
        try
        {
            WriteAssistLease("ICS3U", child.Id, child.ProcessName);

            Assert.Equal("Available once you finish revising with Claude",
                Plantoir.Core.Models.CourseActivity.BusyReason(_folder, "ICS3U"));
            Assert.Null(Plantoir.Core.Models.CourseActivity.BusyReason(_folder, "SNC1W"));
            Assert.Null(Plantoir.Core.Models.CourseActivity.BusyReason(_folder, "EXC2O"));
        }
        finally { try { child.Kill(entireProcessTree: true); } catch { } }
    }

    [Fact]
    public void ReleasingALeaseRemovesIt()
    {
        var lease = WorkLease.Take(_folder, "ICS3U", WorkLease.Assisting);
        string path = Path.Combine(_folder, "courses", ".internal", "activity",
            $"ICS3U.{WorkLease.Assisting}.{Environment.ProcessId}.lease");
        Assert.True(File.Exists(path));
        lease.Dispose();
        Assert.False(File.Exists(path));
    }

    // ---- Pages that are never hidden -------------------------------------

    [Fact]
    public void APageKeyLinksPointsAtIsNeverHiddenByALinkSweep()
    {
        // Key Links is the section's year-round signposts. Hiding one because
        // some class happened to link to it takes away the signpost, not the
        // lesson — a teacher had to protect exactly this set by hand.
        Page("ICS3U", "section1/Key Links.md", draft: false, body: "- [[How Marks Work]]");
        Page("ICS3U", "Setup/How Marks Work.md", draftSection1: false);
        Class("ICS3U", "Unit 1, Day 2", "2026-09-09");
        File.AppendAllText(Path.Combine(_folder, "courses", "ICS3U",
            "section1", "All Classes", "Unit 1, Day 2.md"), "See [[How Marks Work]].\n");

        var plan = Open().PlanPublish("ICS3U", 1, new[] { "Unit 1, Day 2" },
            includeLinked: true, draft: true);

        Assert.DoesNotContain(plan.Pages, p => p.Title == "How Marks Work");
        Assert.Contains(plan.Problems, p => p.Contains("left published"));
    }

    [Fact]
    public void NamingAProtectedPageOutrightSaysSoByName()
    {
        // Silently dropping a page somebody explicitly asked for is worse
        // than telling them it will not happen.
        Page("ICS3U", "section1/Key Links.md", draft: false, body: "- [[How Marks Work]]");
        Page("ICS3U", "Setup/How Marks Work.md", draftSection1: false);

        var plan = Open().PlanPublish("ICS3U", 1, new[] { "How Marks Work" },
            includeLinked: false, draft: true);

        Assert.Contains(plan.Problems, p => p.Contains("“How Marks Work” is never hidden"));
        Assert.Empty(plan.Pages);
    }

    [Fact]
    public void AnIndexPageIsNeverHidden()
    {
        // All Classes/index.md is where a student who missed a class is told
        // to start. (Only one index here: two would be an ambiguous title,
        // which is a different refusal and would hide what this is testing.)
        Page("ICS3U", "section1/All Classes/index.md", draft: false);

        var plan = Open().PlanPublish("ICS3U", 1, new[] { "index" }, includeLinked: false, draft: true);

        Assert.Contains(plan.Problems, p => p.Contains("is never hidden"));
        Assert.Empty(plan.Pages);
    }

    [Fact]
    public void ProtectionAppliesToHidingOnlyNotPublishing()
    {
        Page("ICS3U", "section1/Key Links.md", draft: false, body: "- [[How Marks Work]]");
        Page("ICS3U", "Setup/How Marks Work.md", draftSection1: true);

        var plan = Open().PlanPublish("ICS3U", 1, new[] { "How Marks Work" },
            includeLinked: false, draft: false);

        Assert.True(Assert.Single(plan.Named).WillChange);   // publishing it is fine
        Assert.Empty(plan.Problems);
    }

    // ---- What students would actually meet -------------------------------

    [Fact]
    public void ThePlanWarnsWhenAVisiblePageWouldPointAtAHiddenOne()
    {
        Class("ICS3U", "Unit 1, Day 2", "2026-09-09");
        File.AppendAllText(Path.Combine(_folder, "courses", "ICS3U",
            "section1", "All Classes", "Unit 1, Day 2.md"), "Concept: [[Ohm's Law]]\n");
        Page("ICS3U", "Concepts/Ohm's Law.md", draftSection1: true, body: "See [[E2.6]].");
        Page("ICS3U", "Curriculum/E2.6.md", draftSection1: true, body: "Source: [[About These Expectations]].");
        Page("ICS3U", "Curriculum/About These Expectations.md", draftSection1: true);

        var plan = Open().PlanPublish("ICS3U", 1, new[] { "Unit 1, Day 2" }, includeLinked: true);

        // Transitive link following publishes all reachable pages so students never hit a dead end
        Assert.Contains(plan.Pages, p => p.Title == "E2.6");
        Assert.Contains(plan.Pages, p => p.Title == "About These Expectations");
        Assert.Empty(plan.Dangling);
    }

    [Fact]
    public void ThePlanWarnsWhenHidingBreaksAPageThatStaysVisible()
    {
        // The same defect from the other end, and the reason hiding must not
        // silently follow links to the end: a page some published class still
        // needs would be swallowed.
        Class("ICS3U", "Unit 1, Day 1", "2026-09-08");
        File.AppendAllText(Path.Combine(_folder, "courses", "ICS3U",
            "section1", "All Classes", "Unit 1, Day 1.md"), "Concept: [[Photosynthesis]]\n");
        Page("ICS3U", "Concepts/Photosynthesis.md", draftSection1: false);

        var plan = Open().PlanPublish("ICS3U", 1, new[] { "Photosynthesis" },
            includeLinked: false, draft: true);

        var dangling = Assert.Single(plan.Dangling);
        Assert.EndsWith("Unit 1, Day 1.md", dangling.From, StringComparison.Ordinal);
    }

    [Fact]
    public void AConsistentPlanWarnsAboutNothing()
    {
        Class("ICS3U", "Unit 1, Day 2", "2026-09-09");
        var plan = Open().PlanPublish("ICS3U", 1, new[] { "Unit 1, Day 2" }, includeLinked: true, draft: true);
        Assert.Empty(plan.Dangling);
        Assert.DoesNotContain("point at an unpublished page", plan.Describe());
    }

    [Fact]
    public void UnreferencedPagesAreFoundBecauseNoLinkRuleEverWill()
    {
        // Quartz publishes every non-draft page and lists it in the explorer,
        // so a page nothing links to is still visible to students.
        Class("ICS3U", "Unit 1, Day 1", "2026-09-08");
        Page("ICS3U", "Concepts/Astronomical Phenomena.md", draftSection1: false);

        var workspace = Open();
        var (graph, _) = workspace.Inspect(workspace.Course("ICS3U"), 1);

        Assert.Contains(graph.Unreferenced(),
            p => p.EndsWith("Astronomical Phenomena.md", StringComparison.Ordinal));
    }

    /// <summary>
    /// A class page that nothing links to is a class page, not an orphan.
    ///
    /// Classes are the ROOTS of a section: everything else must be reachable
    /// FROM one, and a class is reached through the site's own navigation of
    /// All Classes. Reporting them made a healthy course look broken — ICD2O
    /// Section 1 said "83 visible pages are linked from nowhere" and listed
    /// its lessons, 83 of the 85 it has. The mac has never done this.
    /// </summary>
    [Fact]
    public void ClassPagesAreRootsRatherThanOrphans()
    {
        Class("ICS3U", "Unit 1, Day 1", "2026-09-08");
        Class("ICS3U", "Unit 1, Day 2", "2026-09-09");
        Page("ICS3U", "Concepts/Astronomical Phenomena.md", draftSection1: false);

        var workspace = Open();
        var course = workspace.Course("ICS3U");
        var (graph, _) = workspace.Inspect(course, 1);
        var classPages = workspace.ClassPages(course, 1)
            .Select(Path.GetFullPath).ToHashSet(StringComparer.OrdinalIgnoreCase);

        // Nothing links to either class — which is the normal state.
        Assert.Contains(graph.Unreferenced(), p => p.EndsWith("Unit 1, Day 1.md", StringComparison.Ordinal));

        var reported = graph.Unreferenced(classPages: classPages);
        Assert.DoesNotContain(reported, p => p.EndsWith("Unit 1, Day 1.md", StringComparison.Ordinal));
        Assert.DoesNotContain(reported, p => p.EndsWith("Unit 1, Day 2.md", StringComparison.Ordinal));

        // And a genuinely stranded page is still reported, or the exclusion
        // would have bought silence rather than accuracy.
        Assert.Contains(reported, p => p.EndsWith("Astronomical Phenomena.md", StringComparison.Ordinal));
    }

    /// <summary>
    /// The same thing through the tool a teacher actually reaches, because
    /// the defect was in what <c>check_section</c> SAID, not in the graph.
    /// </summary>
    [Fact]
    public void CheckSectionDoesNotCallEveryLessonStranded()
    {
        Class("ICS3U", "Unit 1, Day 1", "2026-09-08");
        Class("ICS3U", "Unit 1, Day 2", "2026-09-09");

        // check_section says the same thing to both audiences, so it returns
        // plain text rather than two halves.
        string said = new Plantoir.Mcp.PlantoirTools(Open()).CheckSection("ICS3U", 1);

        Assert.DoesNotContain("linked from nowhere", said);
        Assert.DoesNotContain("Unit 1, Day 1", said);
    }

    /// <summary>
    /// What the preview is doing is read off the LEASE FILES, because this
    /// runs in plantoir-mcp and PreviewLeases is an in-memory static
    /// belonging to the app. Reading that one meant "Nothing is being
    /// previewed at the moment" was said every time, whatever was on screen —
    /// including to a teacher who had pressed Preview thirty seconds earlier.
    /// </summary>
    [Fact]
    public void CheckSectionReadsThePreviewStateAcrossProcesses()
    {
        Class("ICS3U", "Unit 1, Day 1", "2026-09-08");
        var tools = new Plantoir.Mcp.PlantoirTools(Open());

        // Nothing running: the offer to look it over.
        Assert.Contains("Nothing is being previewed", tools.CheckSection("ICS3U", 1));

        using var child = StartALongRunningChild();
        try
        {
            // Building: say so, rather than that nothing is happening.
            WriteWorkLease("ICS3U", WorkLease.Previewing, child.Id, child.ProcessName);
            WriteWorkLease("ICS3U", WorkLease.Building, child.Id, child.ProcessName);
            string building = tools.CheckSection("ICS3U", 1);
            Assert.Contains("The preview is building now", building);
            Assert.DoesNotContain("Nothing is being previewed", building);

            // Showing: nothing at all. They are looking at it.
            File.Delete(Path.Combine(_folder, "courses", ".internal", "activity",
                                     $"ICS3U.{WorkLease.Building}.{child.Id}.lease"));
            string showing = tools.CheckSection("ICS3U", 1);
            Assert.DoesNotContain("Nothing is being previewed", showing);
            Assert.DoesNotContain("is building now", showing);
        }
        finally { try { child.Kill(entireProcessTree: true); } catch { } }
    }

    // ---- Choosing classes by date ----------------------------------------

    [Fact]
    public void ClassesCanBeChosenByDateRatherThanNamed()
    {
        // "Every class from the 15th onwards" is a comparison, and comparisons
        // are what the model must never be doing on a teacher's behalf.
        Class("ICS3U", "Unit 1, Day 1", "2026-09-08");
        Class("ICS3U", "Unit 1, Day 2", "2026-09-09");
        Class("ICS3U", "Unit 1, Day 3", "2026-09-15");
        Class("ICS3U", "Unit 1, Day 4", "2026-09-16");

        var plan = Open().PlanPublish("ICS3U", 1, Array.Empty<string>(),
            includeLinked: false, draft: true, onOrAfter: new DateOnly(2026, 9, 15));

        Assert.Equal(new[] { "Unit 1, Day 3", "Unit 1, Day 4" },
            plan.Named.Select(p => p.Title));
    }

    [Fact]
    public void ADateRangeExcludesItsEndDate()
    {
        Class("ICS3U", "Unit 1, Day 1", "2026-09-08");
        Class("ICS3U", "Unit 1, Day 2", "2026-09-15");

        var plan = Open().PlanPublish("ICS3U", 1, Array.Empty<string>(),
            includeLinked: false, draft: true, before: new DateOnly(2026, 9, 15));

        Assert.Equal("Unit 1, Day 1", Assert.Single(plan.Named).Title);
    }

    [Fact]
    public void ADateRuleNeverSweepsUpTheSectionsOwnIndexPages()
    {
        // The dangerous case, and the reason "class page" is read from
        // per_section_folders rather than from dates alone: a section's
        // index.md, its folder index and its Key Links page all carry the SAME
        // date as the first class. Hiding them takes down the site's front
        // door for a request that only mentioned classes.
        Class("ICS3U", "Unit 1, Day 1", "2026-09-08");
        Dated("ICS3U", "section1/index.md", "2026-09-08");
        Dated("ICS3U", "section1/All Classes/index.md", "2026-09-08");
        Dated("ICS3U", "section1/Key Links.md", "2026-09-08");

        var plan = Open().PlanPublish("ICS3U", 1, Array.Empty<string>(),
            includeLinked: false, draft: true, onOrAfter: new DateOnly(2026, 9, 1));

        Assert.Equal("Unit 1, Day 1", Assert.Single(plan.Named).Title);
        Assert.DoesNotContain(plan.Pages, p => p.RelativePath.EndsWith("index.md", StringComparison.Ordinal));
        Assert.DoesNotContain(plan.Pages, p => p.RelativePath.EndsWith("Key Links.md", StringComparison.Ordinal));
    }

    [Fact]
    public void AnUndatedClassIsNeverSweptUpByADateRule()
    {
        Class("ICS3U", "Unit 1, Day 1", "2026-09-08");
        Page("ICS3U", "section1/All Classes/Scratch.md", draft: false);   // no date at all

        var plan = Open().PlanPublish("ICS3U", 1, Array.Empty<string>(),
            includeLinked: false, draft: true, onOrAfter: new DateOnly(2026, 1, 1));

        Assert.Equal("Unit 1, Day 1", Assert.Single(plan.Named).Title);
    }

    [Fact]
    public void ADateRangeMatchingNothingSaysSoRatherThanPlanningAnEmptyChange()
    {
        Class("ICS3U", "Unit 1, Day 1", "2026-09-08");

        var plan = Open().PlanPublish("ICS3U", 1, Array.Empty<string>(),
            includeLinked: false, draft: true, onOrAfter: new DateOnly(2027, 1, 1));

        Assert.Contains("No class in ICS3U Section 1 falls in that date range.", plan.Problems);
        Assert.Contains("No page's visibility would change.", plan.Describe());
        Assert.True(plan.ChangesNothing);
    }

    [Fact]
    public void AnImpossibleDateRangeIsRefusedRatherThanSilentlyEmpty()
    {
        Class("ICS3U", "Unit 1, Day 1", "2026-09-08");
        var refusal = Assert.Throws<AssistRefusal>(() => Open().PlanPublish("ICS3U", 1,
            Array.Empty<string>(), includeLinked: false, draft: true,
            onOrAfter: new DateOnly(2026, 10, 1), before: new DateOnly(2026, 9, 1)));
        Assert.Equal("No class can be on or after 2026-10-01 and also before 2026-09-01.", refusal.Message);
    }

    [Fact]
    public void NamingNothingAndGivingNoDatesIsRefused()
    {
        var refusal = Assert.Throws<AssistRefusal>(() => Open().PlanPublish("ICS3U", 1,
            Array.Empty<string>(), includeLinked: false));
        Assert.Equal("No page was named, and no dates were given to choose classes by.", refusal.Message);
    }

    [Fact]
    public void ThePlanShowsEachClassesDateSoADateRangeCanBeChecked()
    {
        Class("ICS3U", "Unit 1, Day 2", "2026-09-09");
        var plan = Open().PlanPublish("ICS3U", 1, Array.Empty<string>(),
            includeLinked: false, draft: true, onOrAfter: new DateOnly(2026, 9, 1));
        Assert.Contains("“Unit 1, Day 2” will become hidden.", plan.Describe());
    }


    [Fact]
    public async Task RebuildingThePreviewNeverDeploys()
    {
        // The safety valve: an assistant builds a preview and stops. Making
        // something visible to students is the teacher's own action, taken in
        // Plantoir in front of the site they are about to change.
        Page("ICS3U", "section1/All Classes/Unit 2, Day 3.md", draft: true);
        var workspace = Open();

        var result = await workspace.RebuildPreview("ICS3U", 1);

        Assert.True(result.Succeeded);
        Assert.Contains("No content was changed.", result.Message);
        Assert.Contains("deploy it there when you're happy", result.Message);
        Assert.Equal(new[] { "preview" }, _launcher.Runs.Select(r => r.Launcher));   // never "deploy"
        Assert.Contains("publish: false",
            File.ReadAllText(Path.Combine(_folder, "courses", "ICS3U", "section1", "All Classes", "Unit 2, Day 3.md")));
    }

    [Fact]
    public async Task DeployingIsItsOwnAskAndNeverASideEffect()
    {
        // The reconciliation of two things that sound contradictory: the
        // teacher stays in control of what students see, AND the assistant can
        // deploy. Deploying is never a side effect of changing pages.
        Page("ICS3U", "section1/All Classes/Unit 2, Day 3.md", draft: true);
        var workspace = Open();

        await workspace.Apply(workspace.PlanPublish("ICS3U", 1, new[] { "Unit 2, Day 3" }, includeLinked: false));
        Assert.Equal(new[] { "preview" }, _launcher.Runs.Select(r => r.Launcher));   // publishing: preview only

        var result = await workspace.Deploy("ICS3U", 1);

        Assert.True(result.Succeeded);
        // Contract wording (assist-wording.json → "deployed"), not the
        // bespoke sentence this used to say — found to have drifted from
        // the contract while porting multi-destination deploy (entry 305).
        Assert.Equal(AssistWording.Deployed("ICS3U", "1"), result.Message);
        Assert.Equal(new[] { "preview", "preview", "deploy" }, _launcher.Runs.Select(r => r.Launcher));
    }

    [Fact]
    public async Task AFirstEverDeployIsSentBackToPlantoirForTheSiteName()
    {
        // deploy.py asks what to call the website, and stdin is closed here,
        // so the launcher would die with an unhandled EOFError minutes in.
        File.Delete(Path.Combine(_folder, "courses", "ICS3U", ".netlify_sites", "section1.json"));
        var workspace = Open();

        var refusal = await Assert.ThrowsAsync<AssistRefusal>(() => workspace.Deploy("ICS3U", 1));

        Assert.Contains("has never been deployed", refusal.Message);
        Assert.Empty(_launcher.Runs);
    }

    [Fact]
    public async Task ACloudflareSectionIsSentBackToPlantoirToDeploy()
    {
        AddCourse("SNC1W", "Science", 1, deployTarget: "cloudflare_pages");
        var workspace = Open();

        var refusal = await Assert.ThrowsAsync<AssistRefusal>(() => workspace.Deploy("SNC1W", 1));

        Assert.Contains("needs the account ID Plantoir stores", refusal.Message);
        Assert.Empty(_launcher.Runs);
    }

    [Fact]
    public async Task PublishingBuildsAPreviewAndStopsThere()
    {
        Page("ICS3U", "section1/All Classes/Unit 2, Day 3.md", draft: true);
        var workspace = Open();

        await workspace.Apply(workspace.PlanPublish("ICS3U", 1, new[] { "Unit 2, Day 3" }, includeLinked: false));

        Assert.Equal(new[] { "preview" }, _launcher.Runs.Select(r => r.Launcher));
        Assert.Equal(new[] { "ICS3U", "1", "--build-only" }, _launcher.Runs[0].Arguments);
    }

    [Fact]
    public void TheTermsAreExplainedOncePerSectionAndThenRemembered()
    {
        // A teacher told "I've published tomorrow's class" will reasonably
        // hear "students can see it now". Said plainly the first time, and
        // never again — a tool that re-explains itself gets skimmed.
        Assert.False(Briefing.AlreadyExplained(_folder, "ICS3U", 1));

        Briefing.MarkExplained(_folder, "ICS3U", 1);

        Assert.True(Briefing.AlreadyExplained(_folder, "ICS3U", 1));
        Assert.False(Briefing.AlreadyExplained(_folder, "ICS3U", 2));   // per section, not per course
    }

    [Fact]
    public void TheBriefingSeparatesPublishingFromDeploying()
    {
        string words = Briefing.Words("ICS3U", 1, "Netlify");

        // Publishing is explained by WHERE THE PAGE APPEARS — the teacher's own
        // preview — because that is what it actually does.
        Assert.Contains("built into your site", words);
        Assert.Contains("shows up in your preview", words);

        // And never by who may edit it. An earlier wording said unpublished
        // pages "stay yours to edit", which is true of every page and so
        // implied, wrongly, that publishing one gives it away.
        Assert.Contains("stays yours to edit", words);
        Assert.DoesNotContain("Unpublished pages stay in your folder", words);

        // Deploying is the only thing students ever see, and the briefing must
        // describe what the assistant ACTUALLY does. It said "I never do it",
        // which was true until deploy_section went back into the local tool
        // set — a promise the tools no longer kept, and worse than the jargon
        // this exists to explain.
        Assert.Contains("Deploying", words);
        Assert.Contains("Netlify", words);
        Assert.DoesNotContain("I never do it", words);
        Assert.Contains("only if you ask me to", words);
        Assert.Contains("never deploy without being asked", words);
        Assert.Contains("Nothing reaches students until you say so", words);
    }

    [Fact]
    public void TheBriefingNamesWhereThisCourseActuallyDeploys()
    {
        // Not "the folder you publish into", which describes rather than names
        // and tells a teacher with two courses going to two places nothing.
        string directory = Path.Combine(_folder, "courses", "TEJ2O");
        Directory.CreateDirectory(directory);
        File.WriteAllText(Path.Combine(directory, "course_config.json"),
            """
            {
              "course_code": "TEJ2O",
              "course_name": "Technology",
              "deploy_target": "local_folder",
              "deploy_folder_path": "C:\\Sites\\tej2o",
              "num_sections": 1,
              "section_numbers": [1]
            }
            """);

        string toFolder = AssistWorkspace.DestinationOf(Open().Course("TEJ2O"));
        Assert.Equal(@"C:\Sites\tej2o", toFolder);
        Assert.Contains(@"C:\Sites\tej2o", Briefing.Words("TEJ2O", 1, toFolder));

        // And the other two destinations say their own names.
        Assert.Contains("Cloudflare Pages", Briefing.Words("ICS3U", 1, "Cloudflare Pages"));
        Assert.Contains("Netlify", Briefing.Words("ICS3U", 1, "Netlify"));
    }

    [Fact]
    public void ReadRememberedTimetable_WhenEmpty_OffersToAskForDates()
    {
        var tools = new Plantoir.Mcp.PlantoirTools(Open());
        string result = tools.ReadRememberedTimetable("ICS3U", 1).Detail();
        Assert.Contains(AssistWording.MayIAskForYourDates, result);
        Assert.Contains("I don’t know when ICS3U Section 1 meets yet", result);
    }

    [Fact]
    public void ReadRememberedTimetable_WhenScopeAll_ReturnsEveryDate()
    {
        var dates = new[] { new DateOnly(2026, 9, 8), new DateOnly(2026, 9, 10), new DateOnly(2026, 9, 14) };
        TimetableMemory.Write(_folder, "ICS3U", 1, dates, "test sheet", new DateOnly(2026, 9, 1));

        var tools = new Plantoir.Mcp.PlantoirTools(Open());
        var answer = tools.ReadRememberedTimetable("ICS3U", 1, scope: "all");
        string result = answer.Detail();
        Assert.Contains("All 3 dates for ICS3U Section 1", answer.Summary());
        Assert.Contains("2026-09-08", result);
        Assert.Contains("2026-09-10", result);
        Assert.Contains("2026-09-14", result);
    }

    [Fact]
    public void ReadRememberedTimetable_WhenRevise_OffersToAskForDates()
    {
        var dates = new[] { new DateOnly(2026, 9, 8) };
        TimetableMemory.Write(_folder, "ICS3U", 1, dates, "test sheet", new DateOnly(2026, 9, 1));

        var tools = new Plantoir.Mcp.PlantoirTools(Open());
        string result = tools.ReadRememberedTimetable("ICS3U", 1, revise: "yes").Detail();
        Assert.Contains(AssistWording.MayIAskForYourDates, result);
        Assert.Contains("open for editing", result);
    }

    [Fact]
    public async Task ReDateClasses_WhenNoDatesOnRecord_OffersToAskForDates()
    {
        var tools = new Plantoir.Mcp.PlantoirTools(Open());
        string result = (await tools.ReDateClasses("ICS3U", 1)).Detail();
        Assert.Contains(AssistWording.MayIAskForYourDates, result);
        Assert.Contains("I don’t know when ICS3U Section 1 meets", result);
    }

    [Fact]
    public async Task ReDateClasses_UsesRememberedTimetableWhenTimetableOmitted()
    {
        Page("ICS3U", "section1/All Classes/Unit 1, Day 1.md", draft: true);
        Page("ICS3U", "section1/All Classes/Unit 1, Day 2.md", draft: true);

        var dates = new[] { new DateOnly(2026, 9, 8), new DateOnly(2026, 9, 10) };
        TimetableMemory.Write(_folder, "ICS3U", 1, dates, "test sheet", new DateOnly(2026, 9, 1));

        var tools = new Plantoir.Mcp.PlantoirTools(Open());
        string result = (await tools.ReDateClasses("ICS3U", 1)).Summary();
        Assert.Contains("Re-dated 2 classes", result);
    }

    [Fact]
    public async Task ReDateClasses_WithOverflow_MarksOverflowClassesAsDraftAndRepointsIndex()
    {
        Page("ICS3U", "section1/All Classes/Unit 1, Day 1.md", draft: false);
        Page("ICS3U", "section1/All Classes/Unit 1, Day 2.md", draft: false);
        Page("ICS3U", "section1/All Classes/Unit 1, Day 3.md", draft: false);

        string indexPath = Path.Combine(_folder, "courses", "ICS3U", "section1", "index.md");
        File.WriteAllText(indexPath, "---\ntitle: Home\n---\n# Most Recent Class\n![[Unit 1, Day 3]]\n");

        var dates = new[] { new DateOnly(2026, 9, 8), new DateOnly(2026, 9, 10) };
        TimetableMemory.Write(_folder, "ICS3U", 1, dates, "test sheet", new DateOnly(2026, 9, 1));

        var workspace = Open();
        var remembered = TimetableMemory.Read(workspace.FolderPath, "ICS3U", 1);
        Assert.NotNull(remembered);
        var timetable = Timetable.FromDates(remembered.Dates, remembered.Source);
        var plan = workspace.PlanReDate("ICS3U", 1, timetable, Array.Empty<string>(), Array.Empty<int>());
        Assert.Equal(1, plan.Overflowing);
        var overflowDate = plan.Dates.FirstOrDefault(d => d.Title == "Unit 1, Day 3");
        Assert.NotNull(overflowDate);
        Assert.True(overflowDate.Unpublishes);

        var result = workspace.ApplyReDate(plan);
        Assert.True(result.Succeeded);

        string page3Text = File.ReadAllText(Path.Combine(_folder, "courses", "ICS3U", "section1", "All Classes", "Unit 1, Day 3.md"));
        Assert.True(Plantoir.Core.Models.PageFrontmatter.IsDraft(page3Text, 1));

        string page1Text = File.ReadAllText(Path.Combine(_folder, "courses", "ICS3U", "section1", "All Classes", "Unit 1, Day 1.md"));
        Assert.False(Plantoir.Core.Models.PageFrontmatter.IsDraft(page1Text, 1));

        string page2Text = File.ReadAllText(Path.Combine(_folder, "courses", "ICS3U", "section1", "All Classes", "Unit 1, Day 2.md"));
        Assert.False(Plantoir.Core.Models.PageFrontmatter.IsDraft(page2Text, 1));

        string newIndex = File.ReadAllText(indexPath);
        Assert.Contains("![[Unit 1, Day 2]]", newIndex);
    }

    [Fact]
    public void ReadRememberedTimetable_FormatsUpcomingClasses()
    {
        Page("ICS3U", "section1/All Classes/Unit 1, Day 1.md", draft: false);
        var dates = new[] { new DateOnly(2026, 9, 8), new DateOnly(2026, 9, 10), new DateOnly(2026, 9, 12) };
        TimetableMemory.Write(_folder, "ICS3U", 1, dates, "test sheet", new DateOnly(2026, 9, 1));

        var tools = new Plantoir.Mcp.PlantoirTools(Open());
        var answer = tools.ReadRememberedTimetable("ICS3U", 1);
        string detail = answer.Detail();

        Assert.Contains("ICS3U Section 1", detail);
        Assert.Contains("2026-09-08", detail);
        Assert.Contains("2026-09-10", detail);
        Assert.Contains("2026-09-12", detail);
        Assert.Contains("Where they came from: test sheet", detail);
    }

    // ---- Applying --------------------------------------------------------

    [Fact]
    public async Task ApplyingBacksUpBeforeItChangesAnything()
    {
        // Row 106 built whole-course backups for exactly this scenario, so
        // undo is a real button rather than advice.
        Page("ICS3U", "section1/All Classes/Unit 2, Day 3.md", draft: true);
        var workspace = Open();
        var plan = workspace.PlanPublish("ICS3U", 1, new[] { "Unit 2, Day 3" }, includeLinked: false, publishes: false);

        var result = await workspace.Apply(plan);

        Assert.True(result.Succeeded);
        Assert.NotNull(result.BackupPath);
        Assert.True(File.Exists(result.BackupPath));
    }

    [Fact]
    public async Task ApplyingOnlyTouchesTheRequestedSectionsFlag()
    {
        Page("ICS3U", "Concepts/Ohm's Law.md", draftSection1: true, draftSection2: true);
        Page("ICS3U", "section1/All Classes/Unit 2, Day 3.md", draft: true, body: "Concept: [[Ohm's Law]]");

        var workspace = Open();
        await workspace.Apply(workspace.PlanPublish("ICS3U", 1, new[] { "Unit 2, Day 3" }, includeLinked: true, publishes: false));

        string text = File.ReadAllText(Path.Combine(_folder, "courses", "ICS3U", "Concepts", "Ohm's Law.md"));
        Assert.Contains("publishForSection1: true", text);
        Assert.Contains("publishForSection2: false", text);   // section 2 is none of this operation's business
    }


    [Fact]
    public async Task AFailedBuildStopsBeforePublishingAndSaysWhatSurvived()
    {
        Page("ICS3U", "section1/All Classes/Unit 2, Day 3.md", draft: true);
        _launcher.FailOn = "preview";
        var workspace = Open();

        var result = await workspace.Apply(workspace.PlanPublish("ICS3U", 1, new[] { "Unit 2, Day 3" }, includeLinked: false));

        Assert.False(result.Succeeded);
        Assert.Contains("the preview couldn’t be built", result.Message);
        Assert.Single(_launcher.Runs);                       // deploy never ran
        Assert.NotNull(result.BackupPath);                   // and the backup is still there
    }

    [Fact]
    public async Task AFailureDoesNotClaimPagesChangedWhenNoneDid()
    {
        // This message used to read "The pages were changed and backed up"
        // whatever happened — including when the plan had just established
        // that nothing needed changing. A teacher reading that goes looking
        // for damage that was never done.
        Page("ICS3U", "section1/All Classes/Unit 2, Day 3.md", draft: false);
        _launcher.FailOn = "preview";
        var workspace = Open();

        var result = await workspace.Apply(
            workspace.PlanPublish("ICS3U", 1, new[] { "Unit 2, Day 3" }, includeLinked: false));

        Assert.False(result.Succeeded);
        Assert.StartsWith("No page needed changing, and the course was backed up", result.Message);
        Assert.DoesNotContain("pages were changed", result.Message);
    }



    // ---- Fixtures --------------------------------------------------------

    private void AddCourse(string code, string name, params int[] sections) =>
        AddCourse(code, name, sections.Length == 0 ? new[] { 1 } : sections, "netlify");

    private void AddCourse(string code, string name, int section, string deployTarget) =>
        AddCourse(code, name, new[] { section }, deployTarget);

    private void AddCourse(string code, string name, int[] sections, string deployTarget)
    {
        string directory = Path.Combine(_folder, "courses", code);
        Directory.CreateDirectory(directory);
        File.WriteAllText(Path.Combine(directory, "course_config.json"),
            $$"""
            {
              "course_code": "{{code}}",
              "course_name": "{{name}}",
              "deploy_target": "{{deployTarget}}",
              "num_sections": {{sections.Length}},
              "per_section_folders": ["All Classes"],
              "per_section_files": ["Key Links.md"],
              "section_numbers": [{{string.Join(", ", sections)}}]
            }
            """);

        // A course that has been published before. Without a site marker the
        // server refuses to publish, because the first publish asks the
        // teacher what to call the site and that can only happen in Plantoir.
        if (deployTarget == "netlify") foreach (int section in sections) MarkPublished(code, section);
    }

    private void MarkPublished(string code, int section)
    {
        string directory = Path.Combine(_folder, "courses", code, ".netlify_sites");
        Directory.CreateDirectory(directory);
        File.WriteAllText(Path.Combine(directory, $"section{section}.json"),
            $$"""{"name": "{{code.ToLowerInvariant()}}-s{{section}}-2026-gordon"}""");
    }

    /// <summary>A class page: inside the per-section folder, with a date.</summary>
    private void Class(string course, string title, string date) =>
        Dated(course, $"section1/All Classes/{title}.md", date);

    private void Dated(string course, string relative, string date)
    {
        string full = Path.Combine(_folder, "courses", course,
            relative.Replace('/', Path.DirectorySeparatorChar));
        Directory.CreateDirectory(Path.GetDirectoryName(full)!);
        File.WriteAllText(full,
            $"---\ndraft: false\ncreated: {date}T07:00:00.000-0400\n---\nBody.\n");
    }

    private void Page(string course, string relative, bool? draft = null,
                      bool? draftSection1 = null, bool? draftSection2 = null, string body = "Body.")
    {
        string full = Path.Combine(_folder, "courses", course,
            relative.Replace('/', Path.DirectorySeparatorChar));
        Directory.CreateDirectory(Path.GetDirectoryName(full)!);

        // Fixtures are written in the vocabulary the app now uses: publish,
        // not draft, and the opposite polarity. The parameters keep their
        // "draft" names because that is what a test READS as — "publish: false"
        // means the page is not visible — and flipping every call site would
        // obscure what each test is actually about.
        var frontmatter = new List<string>();
        if (draft is { } d) frontmatter.Add($"publish: {(d ? "false" : "true")}");
        if (draftSection1 is { } one) frontmatter.Add($"publishForSection1: {(one ? "false" : "true")}");
        if (draftSection2 is { } two) frontmatter.Add($"publishForSection2: {(two ? "false" : "true")}");

        File.WriteAllText(full, "---\n" + string.Join("\n", frontmatter) + "\n---\n" + body + "\n");
    }
}

/// <summary>Records launcher runs instead of starting Docker.</summary>
internal sealed class FakeLauncher : ILauncherRunner
{
    public record Run(string Launcher, string[] Arguments);

    public List<Run> Runs { get; } = new();

    /// <summary>Which launcher, if any, should report failure.</summary>
    public string? FailOn { get; set; }

    Task<LaunchOutcome> ILauncherRunner.Run(string launcher, IReadOnlyList<string> arguments,
                                            string workingFolder, IProgress<string>? progress,
                                            CancellationToken cancellation)
    {
        Runs.Add(new Run(launcher, arguments.ToArray()));
        return Task.FromResult(launcher == FailOn
            ? new LaunchOutcome(false, "It went wrong.")
            : new LaunchOutcome(true, "Done."));
    }
}
