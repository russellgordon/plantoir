using Plantoir.Core.Assist;
using Plantoir.Core.Models;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// What a course calls a unit, and the parsing that depends on it.
///
/// <para>The contract's own <c>pageNaming</c> cases are run by
/// <c>ClassPlanningContractTests</c>; these cover the half that is this app's
/// own — the default, the two wizard refusals, and the fact that a wrong word
/// fails SILENTLY rather than loudly, which is why the parsing half mattered
/// more than the naming half.</para>
/// </summary>
public class ClassPageTermTests
{
    [Theory]
    [InlineData(null, "Unit")]
    [InlineData("", "Unit")]
    [InlineData("   ", "Unit")]
    [InlineData("Module", "Module")]
    [InlineData("  Thread  ", "Thread")]
    public void AnAbsentOrEmptyWordMeansUnit(string? given, string expected)
    {
        // Absent and empty are deliberately NOT distinguished the way
        // graded_folders distinguishes them: there is no sensible reading of
        // "the teacher cleared the word", and a course whose class pages had
        // no name could not be built.
        Assert.Equal(expected, ClassPageTerm.Cleaned(given));
    }

    [Fact]
    public void ADigitIsRefusedBecauseTheNumberAfterItIsTheUnitsOwn()
    {
        Assert.NotNull(ClassPageTerm.Problem("Unit1"));
        Assert.Contains("number", ClassPageTerm.Problem("Week 2")!);
    }

    [Fact]
    public void ACommaIsRefusedBecauseItSeparatesTheUnitFromTheDay()
    {
        Assert.Contains("comma", ClassPageTerm.Problem("Thread,")!);
    }

    [Theory]
    [InlineData("Module")]
    [InlineData("Thread")]
    [InlineData("")]
    [InlineData(null)]
    public void AnOrdinaryWordIsAccepted(string? word)
    {
        Assert.Null(ClassPageTerm.Problem(word));
    }

    [Fact]
    public void AWordWithRegexPunctuationCannotBecomeADifferentPattern()
    {
        // Regex.Escape is not decoration: the word comes from a teacher's own
        // configuration, and one containing "(" or "+" would otherwise quietly
        // become a different pattern, or fail to compile mid-build.
        Assert.NotNull(UnitDay.Parse("C++ 2, Day 3", "C++"));
        Assert.Null(UnitDay.Parse("Cxx 2, Day 3", "C++"));
        Assert.Equal(2, UnitDay.Parse("C++ 2, Day 3", "C++")!.Value.Unit);
    }

    [Fact]
    public void AModuleCourseDoesNotReadAUnitPageAsAClassPage()
    {
        // The load-bearing case, and the one that fails silently if it is got
        // wrong: nothing REFUSES, the coverage map simply finds nothing to
        // count and falls back to every published page.
        Assert.Null(UnitDay.Parse("Unit 2, Day 3", "Module"));
        Assert.NotNull(UnitDay.Parse("Module 2, Day 3", "Module"));
    }

    [Fact]
    public void TheDefaultWordStillReadsTheCoursesEveryTeacherAlreadyHas()
    {
        Assert.Equal(new UnitDay(2, 3), UnitDay.Parse("Unit 2, Day 3", null));
        Assert.Equal(new UnitDay(2, 3), UnitDay.Parse("Unit 2, Day 3"));
        Assert.Equal(new UnitDay(2, 3), UnitDay.Parse("Unit 2, Day 3", ""));
    }

    [Fact]
    public void TheTitleIsWrittenInTheCoursesOwnWord()
    {
        Assert.Equal("Module 4, Day 1", new UnitDay(4, 1).TitleIn("Module"));
        Assert.Equal("Unit 4, Day 1", new UnitDay(4, 1).TitleIn(null));
        Assert.Equal("Unit 4, Day 1", new UnitDay(4, 1).Title);
    }

    [Fact]
    public void TheNextClassIsFoundInTheCoursesOwnWord()
    {
        var titles = new[] { "Module 1, Day 1", "Module 1, Day 2", "Field Trip" };

        // Parsed with the right word, the next class follows the last one.
        Assert.Equal(new UnitDay(1, 3), NextClassPlanner.NextUnitAndDay(titles, "Module"));
        Assert.Equal(new UnitDay(2, 1), NextClassPlanner.FirstDayOfANewUnit(titles, "Module"));

        // Parsed with the default, this course looks empty — which is how a
        // Module course would be offered "Unit 1, Day 1" when it already has
        // thirty pages.
        Assert.Equal(new UnitDay(1, 1), NextClassPlanner.NextUnitAndDay(titles));
    }

    [Fact]
    public void TheCaptionShowsTheTeacherWhatTheirWordProduces()
    {
        Assert.Equal("Class pages will be named 'Thread 1, Day 1'.", ClassPageTerm.Caption("Thread"));
        Assert.Equal("Class pages will be named 'Unit 1, Day 1'.", ClassPageTerm.Caption(""));
    }

    [Fact]
    public void AUnitIsNamedByTheCoursesWordOrByTheLiteralUnit()
    {
        // BOTH, and each direction is a real failure. Accepting only the
        // course's word refuses requests the app itself generates: the
        // fixed-shape card emits "Unit 4" and the model echoes "Unit" from the
        // system prompt's examples. Accepting only "unit" is the opposite
        // failure and is the one that shipped first — "Module 4" was not
        // recognised as a unit at all and came back as an unknown page.
        Assert.Equal(4, PublishPlan.UnitNamed("Module 4", "Module"));
        Assert.Equal(4, PublishPlan.UnitNamed("Unit 4", "Module"));
        Assert.Equal(4, PublishPlan.UnitNamed("module 4.", "Module"));
        Assert.Equal(4, PublishPlan.UnitNamed("Unit 4", (string?)null));
    }

    [Fact]
    public void NamingADayIsAPageRatherThanAUnit()
    {
        Assert.Null(PublishPlan.UnitNamed("Module 4, Day 3", "Module"));
        Assert.Null(PublishPlan.UnitNamed("Module", "Module"));
        Assert.Null(PublishPlan.UnitNamed("Field Trip", "Module"));
    }

    [Fact]
    public void TheRecordedClassFolderCannotBeRemoved()
    {
        // Blocking only the literal "All Classes" was right until
        // `class_folder` existed. Now that a course can call its class folder
        // "All Days", blocking only the literal would let a teacher remove the
        // folder the next-class button and the schedule write into.
        var context = new ProtectionContext(
            InWizard: false,
            CurriculumCoverageEnabled: false,
            CurriculumPagesEnabled: false,
            Jurisdiction: SpecialNames.DefaultJurisdiction,
            ResolvedCurriculumFolder: null,
            GradedFolders: new[] { "Tasks" },
            PerSectionFolders: new[] { "All Days", "Handouts" },
            ResolvedClassFolder: "All Days");

        Assert.True(ItemProtectionRule.For("All Days", ItemList.PerSectionFolders, context).IsBlocked);
        // Another per-section folder is as removable as it ever was.
        Assert.False(ItemProtectionRule.For("Handouts", ItemList.PerSectionFolders, context).IsBlocked);
    }

    [Fact]
    public void ACourseThatNeverRecordedOneStillProtectsAllClasses()
    {
        var context = new ProtectionContext(
            InWizard: false,
            CurriculumCoverageEnabled: false,
            CurriculumPagesEnabled: false,
            Jurisdiction: SpecialNames.DefaultJurisdiction,
            ResolvedCurriculumFolder: null,
            GradedFolders: new[] { "Tasks" },
            PerSectionFolders: new[] { "All Classes", "Handouts" },
            ResolvedClassFolder: null);

        Assert.True(ItemProtectionRule.For("All Classes", ItemList.PerSectionFolders, context).IsBlocked);
    }

    /// <summary>
    /// #431 (Russell, 2026-10-03: Windows matches the mac). A course that
    /// recorded no class_folder protects only the literal "All Classes" from
    /// removal: never the first per-section folder, and never one that merely
    /// mentions "class". Through <see cref="CourseSettingsProtection"/>, which
    /// is what Course Settings asks. The naming rule (where a new class page is
    /// written) keeps its guess; this is only what is PROTECTED.
    /// </summary>
    [Theory]
    [InlineData(null, "Handouts", false)]          // the first folder, no "class": the old guess protected it
    [InlineData(null, "Class Pages", false)]       // mentions "class": the old guess protected it too
    [InlineData(null, "All Classes", true)]        // the literal, always
    [InlineData("Handouts", "Handouts", true)]     // a recorded name, whatever it says
    [InlineData("  handouts ", "Handouts", true)]  // trimmed, compared without case
    public void OnlyARecordedNameOrAllClassesIsProtectedAsTheClassFolder(string? recorded, string folder, bool blocked)
    {
        var values = new Newtonsoft.Json.Linq.JObject
        {
            ["course_code"] = "TEST",
            ["section_numbers"] = new Newtonsoft.Json.Linq.JArray(1),
            ["per_section_folders"] = new Newtonsoft.Json.Linq.JArray("Handouts", "Class Pages", "All Classes", "Worksheets"),
            ["graded_folders"] = new Newtonsoft.Json.Linq.JArray(),
        };
        if (recorded is not null) values["class_folder"] = recorded;
        var config = CourseConfiguration.FromDictionary(values);
        var protection = ItemProtectionRule.For(folder, ItemList.PerSectionFolders,
            CourseSettingsProtection.For(config, new List<WalkedFolder>(), (string?)null));
        Assert.Equal(blocked, protection.IsBlocked && protection.Reason == SpecialNames.ClassFolderBlocked);
    }

    [Fact]
    public void ARecordedKeyWithStrayWhitespaceStillNamesTheFolder()
    {
        Assert.Equal("All Days", ClassFolderRule.Name("  All Days  ", new[] { "All Days", "Tasks" }));
    }
}
