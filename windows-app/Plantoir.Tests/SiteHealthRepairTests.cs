using System.Text;
using System.Text.Json.Nodes;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;

namespace Plantoir.Tests;

/// <summary>
/// Putting a folder problem right: what is offered, what is refused, and what
/// the teacher is told afterwards.
///
/// <para>The tests that matter here are the ones about NOT doing something — a
/// teacher's own front page surviving a repair, and a check with no real repair
/// never acquiring a button. A repair that satisfies its check without
/// restoring the feature is worse than no repair, because the warning goes away
/// and the site stays wrong.</para>
/// </summary>
/// <remarks>
/// In the serialized collection because a successful repair writes to the
/// activity trail, whose log path is a process-wide static.
/// </remarks>
[Collection(SharedActivityState.Name)]
public class SiteHealthRepairTests : IDisposable
{
    private readonly string _trailPath;
    private readonly string _root;

    public SiteHealthRepairTests()
    {
        _trailPath = Path.Combine(Path.GetTempPath(), $"plantoir-trail-{Guid.NewGuid():N}.txt");
        ActivityTrail.SetCustomLogPathForTesting(_trailPath);
        _root = Path.Combine(Path.GetTempPath(), $"plantoir-repair-{Guid.NewGuid():N}");
    }

    public void Dispose()
    {
        ActivityTrail.SetCustomLogPathForTesting(TestTrailRedirect.ScratchTrailPath);
        try { File.Delete(_trailPath); } catch { }
        try { Directory.Delete(_root, recursive: true); } catch { }
    }

    private string Trail() => File.Exists(_trailPath) ? File.ReadAllText(_trailPath) : "";

    private const string ConfigJson =
        "{\"course_code\": \"ICS3U\", \"course_name\": \"Introduction to Computer Science\", " +
        "\"section_numbers\": [1, 2], \"num_sections\": 2}";

    private Course MakeCourse(string copy = "")
    {
        string courseDir = Path.Combine(_root, "courses" + copy, "ICS3U");
        Directory.CreateDirectory(courseDir);
        File.WriteAllText(Path.Combine(courseDir, "course_config.json"), ConfigJson);
        return new Course("ICS3U", courseDir,
                          CourseConfiguration.FromBytes(Encoding.UTF8.GetBytes(ConfigJson)));
    }

    private static SiteHealthFinding Finding(string name, bool fixable = true, int section = 1) =>
        new(name, "A sentence.", "Some detail.", fixable, "ICS3U", section);

    // ---- What may be offered --------------------------------------------

    [Theory]
    [InlineData("curriculumCoverageFoundNothing")]
    [InlineData("courseTeachesNothing")]
    [InlineData("handWrittenCoveragePage")]
    [InlineData("noGradedFolders")]
    public void ACheckWithNoRealRepairIsNeverOffered(string name)
    {
        // The point of the whole design: recreating an empty curriculum folder
        // would silence the warning and leave the map missing.
        var finding = Finding(name, fixable: true);
        Assert.False(SiteHealthRepair.CanRepair(finding));
        Assert.Null(SiteHealthRepair.ButtonTitle(new[] { finding }));
    }

    [Fact]
    public void TheFlagAloneIsNotEnoughAndNeitherIsTheNameAlone()
    {
        // The flag means "this kind of thing is repairable"; the name is what
        // says THIS app has a repair. Both, or no button.
        Assert.True(SiteHealthRepair.CanRepair(Finding("mediaFolderMissing", fixable: true)));
        Assert.False(SiteHealthRepair.CanRepair(Finding("mediaFolderMissing", fixable: false)));
        Assert.False(SiteHealthRepair.CanRepair(Finding("noGradedFolders", fixable: true)));
    }

    [Fact]
    public void TheButtonNamesTheOneThingItWillDo()
    {
        Assert.Equal("Put the Media folder back",
            SiteHealthRepair.ButtonTitle(new[] { Finding("mediaFolderMissing") }));
        Assert.Equal("Add the missing page",
            SiteHealthRepair.ButtonTitle(new[] { Finding("sectionIndexMissing") }));
        Assert.Equal("Put them back",
            SiteHealthRepair.ButtonTitle(new[] { Finding("mediaFolderMissing"), Finding("sectionIndexMissing") }));
    }

    // ---- Never overwrite -------------------------------------------------

    [Fact]
    public void ATeachersOwnFrontPageSurvivesARepair()
    {
        // The test that matters. A repair that overwrote this would destroy the
        // teacher's work in the act of "helping".
        var course = MakeCourse();
        string sectionDir = course.SectionDirectory(1);
        Directory.CreateDirectory(sectionDir);
        string index = Path.Combine(sectionDir, "index.md");
        const string theirs = "---\ntitle: Welcome to my class\n---\n\nRead this first.\n";
        File.WriteAllText(index, theirs);

        var result = SiteHealthRepair.RestoreIndex(1, course);

        Assert.Equal(SiteHealthRepair.Result.AlreadyFine, result);
        Assert.Equal(theirs, File.ReadAllText(index));
        // Nobody acted, so nothing is claimed on the trail.
        Assert.DoesNotContain("put the front page back", Trail());
    }

    [Fact]
    public void AMediaFolderThatIsAlreadyThereIsLeftAloneAndIsNotAFailure()
    {
        var course = MakeCourse();
        string media = Path.Combine(course.DirectoryPath, "Media");
        Directory.CreateDirectory(media);
        File.WriteAllText(Path.Combine(media, "diagram.png"), "not really a png");

        Assert.Equal(SiteHealthRepair.Result.AlreadyFine, SiteHealthRepair.RestoreMedia(course));
        Assert.True(File.Exists(Path.Combine(media, "diagram.png")));
    }

    // ---- Doing it --------------------------------------------------------

    [Fact]
    public void TheRestoredFrontPageCarriesTheCourseNameAndNothingElse()
    {
        var course = MakeCourse();

        Assert.Equal(SiteHealthRepair.Result.Restored, SiteHealthRepair.RestoreIndex(2, course));

        string index = Path.Combine(course.SectionDirectory(2), "index.md");
        // Character for character with the mac: the same button on the two
        // platforms must not write differently titled pages into a vault.
        Assert.Equal("---\ntitle: Introduction to Computer Science\n---\n", File.ReadAllText(index));
        // And it lands in the section it was asked about, not just somewhere.
        Assert.False(File.Exists(Path.Combine(course.SectionDirectory(1), "index.md")));
        Assert.Contains("put the front page back", Trail());
        Assert.Contains("ICS3U/2", Trail());
    }

    [Fact]
    public void TheRestoredMediaFolderIsEmptyAndIsRecordedAgainstTheCourse()
    {
        var course = MakeCourse();

        Assert.Equal(SiteHealthRepair.Result.Restored, SiteHealthRepair.RestoreMedia(course));

        string media = Path.Combine(course.DirectoryPath, "Media");
        Assert.True(Directory.Exists(media));
        Assert.Empty(Directory.GetFileSystemEntries(media));
        Assert.Contains("put the Media folder back", Trail());
        // Media belongs to the whole course; a section number here would name
        // a section the finding may not even be about.
        Assert.DoesNotContain("ICS3U/1 ·", Trail());
    }

    // ---- Refusing rather than inventing structure ------------------------

    [Fact]
    public void AMalformedLineCannotConjureASectionZeroFolder()
    {
        // SiteHealthFinding.Parse falls back to section 0 when the field is
        // missing or the wrong type. Creating section0 would invent structure
        // the course does not have.
        var course = MakeCourse();

        Assert.Equal(SiteHealthRepair.Result.Failed, SiteHealthRepair.RestoreIndex(0, course));
        Assert.False(Directory.Exists(Path.Combine(course.DirectoryPath, "section0")));
    }

    [Fact]
    public void AFolderSittingWhereTheFrontPageBelongsIsRefusedAndLeftExactlyAsItIs()
    {
        // File.Exists answers false for a directory, so without an explicit
        // check the write fails and the teacher is sent to see whether their
        // disk is read-only — which is not the problem. This used to answer
        // Failed, which was honest and still sent them to the wrong place;
        // the mac's bare existence check answered ALREADY FINE, which was
        // worse. Both now refuse, with a sentence of their own — contract
        // siteHealth.repair.refusedWhenSomethingIsInTheWay.
        var course = MakeCourse();
        string folder = Path.Combine(course.SectionDirectory(1), "index.md");
        Directory.CreateDirectory(folder);
        File.WriteAllText(Path.Combine(folder, "their-page.md"), "theirs");

        Assert.Equal(SiteHealthRepair.Result.Refused, SiteHealthRepair.RestoreIndex(1, course));

        // Nothing moved, renamed or deleted: the folder may hold their pages.
        Assert.True(Directory.Exists(folder));
        Assert.Equal("theirs", File.ReadAllText(Path.Combine(folder, "their-page.md")));

        // The refusal leaves a line, because the folder in the way is something
        // the teacher will very likely have moved by the time they report it.
        Assert.Contains("ICS3U/1", Trail());
        Assert.Contains("found a folder called index.md where the front page belongs, and left it alone", Trail());
    }

    [Fact]
    public void ARefusalIsReportedWithItsOwnSentenceAndNotThePermissionsAdvice()
    {
        var course = MakeCourse();
        Directory.CreateDirectory(Path.Combine(course.SectionDirectory(2), "index.md"));

        var outcome = SiteHealthRepair.OutcomeOfRepairing(
            new[] { Finding("sectionIndexMissing", section: 2) }, course);

        Assert.Equal("Plantoir could not put that back.", outcome!.Headline);
        Assert.Equal(SiteHealthRepair.FolderWhereTheFrontPageBelongs("ICS3U", 2), outcome.Detail);
        // "check the folder isn't locked or read-only" is not what is wrong.
        Assert.DoesNotContain(SiteHealthRepair.CouldNotExplanation, outcome.Detail);
        Assert.False(outcome.CanRebuild);
    }

    [Fact]
    public void WhenBothKindsOfFailureHappenTheGenericAdviceComesFirstAndTheRefusalLast()
    {
        // A file where Media belongs (simply failed) AND a folder where the
        // front page belongs (refused). The paragraph must end on the step the
        // teacher can actually take, not on advice that does not apply to it.
        var course = MakeCourse();
        File.WriteAllText(Path.Combine(course.DirectoryPath, "Media"), "a file, not a folder");
        Directory.CreateDirectory(Path.Combine(course.SectionDirectory(1), "index.md"));

        var outcome = SiteHealthRepair.OutcomeOfRepairing(
            new[] { Finding("mediaFolderMissing"), Finding("sectionIndexMissing", section: 1) }, course);

        Assert.Equal("Plantoir could not put that back.", outcome!.Headline);
        Assert.Equal(
            SiteHealthRepair.CouldNotExplanation + " " +
            SiteHealthRepair.FolderWhereTheFrontPageBelongs("ICS3U", 1),
            outcome.Detail);
        Assert.False(outcome.CanRebuild);
    }

    [Fact]
    public void ARefusalBesideARestoreNamesBothAndOffersNoPreview()
    {
        var course = MakeCourse();
        Directory.CreateDirectory(Path.Combine(course.SectionDirectory(1), "index.md"));

        var outcome = SiteHealthRepair.OutcomeOfRepairing(
            new[] { Finding("mediaFolderMissing"), Finding("sectionIndexMissing", section: 1) }, course);

        Assert.Equal("Put the Media folder back.", outcome!.Headline);
        Assert.Equal(
            "Could not put the front page back. " +
            SiteHealthRepair.FolderWhereTheFrontPageBelongs("ICS3U", 1),
            outcome.Detail);
        Assert.False(outcome.CanRebuild);
    }

    [Fact]
    public void TwoRefusedSectionsAreTwoSentencesBecauseEachNamesItsOwnFolder()
    {
        var course = MakeCourse();
        Directory.CreateDirectory(Path.Combine(course.SectionDirectory(1), "index.md"));
        Directory.CreateDirectory(Path.Combine(course.SectionDirectory(2), "index.md"));

        var outcome = SiteHealthRepair.OutcomeOfRepairing(
            new[] { Finding("sectionIndexMissing", section: 1), Finding("sectionIndexMissing", section: 2) },
            course);

        Assert.Equal(
            SiteHealthRepair.FolderWhereTheFrontPageBelongs("ICS3U", 1) + " " +
            SiteHealthRepair.FolderWhereTheFrontPageBelongs("ICS3U", 2),
            outcome!.Detail);
    }

    [Fact]
    public void TwoRepairsAreNamedInOneSentence()
    {
        var course = MakeCourse();
        var outcome = SiteHealthRepair.OutcomeOfRepairing(
            new[] { Finding("mediaFolderMissing"), Finding("sectionIndexMissing") }, course);

        Assert.Equal("Put the Media folder and the front page back.", outcome!.Headline);
        Assert.Equal(SiteHealthRepair.NotOnTheSiteYet, outcome.Detail);
        Assert.True(outcome.CanRebuild);
    }

    /// <summary>
    /// The cases under <c>siteHealth.repair.reportedOncePerFinding</c>, built
    /// exactly as its <c>howToRunACase</c> says: one finding per listed
    /// section, all of the named check, all fixable, for a course whose
    /// sections are exactly the listed numbers; <c>frontPage</c> says what is
    /// on disk before the repair. The report and the results are asked of
    /// SEPARATE copies of the course, because every repair runs as it goes.
    /// </summary>
    /// <remarks>
    /// This replaced a hand-written test that pinned the same rule. Both apps
    /// return one entry per finding — this side shipped the shape first — and
    /// the rule became contract data on 2026-09-07 so it is checked against one
    /// source on both sides rather than proved twice in parallel.
    /// </remarks>
    public static IEnumerable<object[]> ReportedOncePerFindingCases()
    {
        var cases = ContractLoader.LoadJson("shared-rules.json")["siteHealth"]!["repair"]!
            ["reportedOncePerFinding"]!["cases"]!.AsArray();
        foreach (var c in cases)
            yield return new object[] { c!["note"]!.ToString(), c.ToJsonString() };
    }

    [Theory]
    [MemberData(nameof(ReportedOncePerFindingCases))]
    public void ARepairReportsOneResultPerFindingNeverOnePerCheckName(string note, string caseJson)
    {
        var c = JsonNode.Parse(caseJson)!;
        string check = c["check"]!.ToString();
        var sections = c["sections"]!.AsArray();
        var expectResults = c["expectResults"]!.AsArray().Select(r => r!.ToString()).ToList();

        var findings = sections
            .Select(sec => Finding(check, section: sec!["number"]!.GetValue<int>()))
            .ToList();

        // One copy of the course for the results, one for the report.
        var forResults = MakeCourse("results");
        var forReport = MakeCourse("report");
        foreach (var course in new[] { forResults, forReport })
        {
            Assert.Equal(sections.Select(sec => sec!["number"]!.GetValue<int>()).OrderBy(n => n),
                         course.Configuration.SectionNumbers.OrderBy(n => n));
            foreach (var sec in sections)
            {
                int number = sec!["number"]!.GetValue<int>();
                string frontPage = sec["frontPage"]!.ToString();
                if (frontPage == "theTeachersOwn")
                {
                    Directory.CreateDirectory(course.SectionDirectory(number));
                    File.WriteAllText(Path.Combine(course.SectionDirectory(number), "index.md"), "theirs");
                }
                else Assert.Equal("missing", frontPage);
            }
        }

        var results = SiteHealthRepair.Repair(findings, forResults);
        Assert.Equal(expectResults,
                     results.Select(r => Vocabulary(r.Result)).ToList());
        // In the order given, so the finding beside each answer is the one
        // it is about.
        Assert.Equal(findings.Select(f => f.Section), results.Select(r => r.Finding.Section));

        var outcome = SiteHealthRepair.OutcomeOfRepairing(findings, forReport);
        Assert.Equal(c["expectHeadline"]!.ToString(), outcome!.Headline);
        Assert.Equal(c["expectCanRebuild"]!.GetValue<bool>(), outcome.CanRebuild);

        // A teacher's own page survived, whichever copy it was on.
        foreach (var sec in sections)
        {
            if (sec!["frontPage"]!.ToString() != "theTeachersOwn") continue;
            int number = sec["number"]!.GetValue<int>();
            foreach (var course in new[] { forResults, forReport })
                Assert.Equal("theirs", File.ReadAllText(Path.Combine(course.SectionDirectory(number), "index.md")));
        }
        Assert.NotEmpty(note);
    }

    /// <summary>The contract's answer words, mapped onto this app's results.</summary>
    private static string Vocabulary(SiteHealthRepair.Result result) => result switch
    {
        SiteHealthRepair.Result.Restored => "restored",
        SiteHealthRepair.Result.AlreadyFine => "alreadyFine",
        SiteHealthRepair.Result.Failed => "failed",
        SiteHealthRepair.Result.Refused => "refused",
        _ => throw new ArgumentOutOfRangeException(nameof(result)),
    };

    [Fact]
    public void WhenEverythingFailedTheHeadlineDoesNotTryToNameThem()
    {
        // Deliberate: with nothing put back there is no "Put X back." sentence
        // to lead with, and the explanation is the same for either. The helper
        // that DOES name two is pinned beside it, because the two-name join is
        // otherwise only exercised on the success path.
        var course = MakeCourse();
        File.WriteAllText(Path.Combine(course.DirectoryPath, "Media"), "a file, not a folder");

        var outcome = SiteHealthRepair.OutcomeOfRepairing(
            new[] { Finding("mediaFolderMissing"), Finding("sectionIndexMissing", section: 9) }, course);

        Assert.Equal("Plantoir could not put that back.", outcome!.Headline);
        Assert.Equal(SiteHealthRepair.CouldNotExplanation, outcome.Detail);
        Assert.False(outcome.CanRebuild);

        Assert.Equal("Could not put the Media folder and the front page back.",
            SiteHealthRepair.WhatCouldNotBePutBack(new[] { "mediaFolderMissing", "sectionIndexMissing" }));
    }

    [Fact]
    public void AFileSittingWhereTheMediaFolderBelongsIsAFailureNotAnAlreadyFine()
    {
        var course = MakeCourse();
        File.WriteAllText(Path.Combine(course.DirectoryPath, "Media"), "a file, not a folder");

        Assert.Equal(SiteHealthRepair.Result.Failed, SiteHealthRepair.RestoreMedia(course));
    }

    // ---- What the teacher is told ---------------------------------------

    [Fact]
    public void NothingRepairableMeansNothingIsReported()
    {
        var course = MakeCourse();
        Assert.Null(SiteHealthRepair.OutcomeOfRepairing(
            new[] { Finding("curriculumCoverageFoundNothing") }, course));
    }

    [Fact]
    public void PressingTwiceReadsAsAlreadyPutRightRatherThanAsAPermissionsProblem()
    {
        var course = MakeCourse();
        var findings = new[] { Finding("mediaFolderMissing") };

        var first = SiteHealthRepair.OutcomeOfRepairing(findings, course);
        var second = SiteHealthRepair.OutcomeOfRepairing(findings, course);

        Assert.Equal("Put the Media folder back.", first!.Headline);
        Assert.Equal("That is already put right.", second!.Headline);
        Assert.Equal("Nothing needed changing.", second.Detail);
        // Nothing changed, so there is nothing to go and look at.
        Assert.False(second.CanRebuild);
    }

    [Fact]
    public void APartialFailureNamesTheHalfThatDidNotComeBack()
    {
        // Media can be restored; the front page cannot, because section 9 is
        // not a section of this course.
        var course = MakeCourse();
        var outcome = SiteHealthRepair.OutcomeOfRepairing(
            new[] { Finding("mediaFolderMissing"), Finding("sectionIndexMissing", section: 9) }, course);

        Assert.Equal("Put the Media folder back.", outcome!.Headline);
        Assert.Contains("Could not put the front page back.", outcome.Detail);
        Assert.Contains(SiteHealthRepair.CouldNotExplanation, outcome.Detail);
        // Something did not come back, so "Preview Again" would be showing the
        // teacher a site that is still wrong.
        Assert.False(outcome.CanRebuild);
    }

    [Fact]
    public void AFailureOnItsOwnIsReportedRatherThanClosingSilently()
    {
        var course = MakeCourse();
        var outcome = SiteHealthRepair.OutcomeOfRepairing(
            new[] { Finding("sectionIndexMissing", section: 9) }, course);

        Assert.Equal("Plantoir could not put that back.", outcome!.Headline);
        Assert.Equal(SiteHealthRepair.CouldNotExplanation, outcome.Detail);
        Assert.False(outcome.CanRebuild);
    }

    [Fact]
    public void TheOccasionChangesTheSentenceAndNotTheOffer()
    {
        var building = SiteHealthRepair.OutcomeOfRepairing(
            new[] { Finding("mediaFolderMissing") }, MakeCourse(), SiteHealthRepair.Occasion.Building);

        // A second course, so the first one's repair does not make this one a
        // no-op.
        string otherRoot = Path.Combine(_root, "other");
        Directory.CreateDirectory(Path.Combine(otherRoot, "courses", "ICS3U"));
        var otherCourse = new Course("ICS3U", Path.Combine(otherRoot, "courses", "ICS3U"),
                                     CourseConfiguration.FromBytes(Encoding.UTF8.GetBytes(ConfigJson)));
        var publishing = SiteHealthRepair.OutcomeOfRepairing(
            new[] { Finding("mediaFolderMissing") }, otherCourse, SiteHealthRepair.Occasion.Publishing);

        Assert.Equal(SiteHealthRepair.NotOnTheSiteYet, building!.Detail);
        Assert.Equal(SiteHealthRepair.NotPublishedYet, publishing!.Detail);
        // The preview is offered on BOTH occasions — the reversal recorded in
        // shared-rules.json -> siteHealth.repair.afterwards.
        Assert.True(building.CanRebuild);
        Assert.True(publishing.CanRebuild);
    }

    [Fact]
    public void ThePublishSentenceDoesNotAssertAPublishThatMayNeverHaveHappened()
    {
        // It is shown after a FAILED deploy too, and for a section publishing
        // for the first time nothing has ever gone out.
        Assert.DoesNotContain("last published", SiteHealthRepair.NotPublishedYet);
        Assert.DoesNotContain("students still see", SiteHealthRepair.NotPublishedYet);
        Assert.Contains("until you publish again", SiteHealthRepair.NotPublishedYet);
    }
}
