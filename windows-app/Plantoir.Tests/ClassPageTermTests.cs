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
}
