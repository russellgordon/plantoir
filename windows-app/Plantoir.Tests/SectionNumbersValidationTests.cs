using Plantoir.Core.Models;
using Xunit;

namespace Plantoir.Tests;

public class SectionNumbersValidationTests
{
    [Fact]
    public void GoodInputPassesQuietly()
    {
        Assert.Null(SectionNumbersRule.Problem("1"));
        Assert.Null(SectionNumbersRule.Problem("1,3"));
        Assert.Null(SectionNumbersRule.Problem(" 1 , 3 , 5 "));
    }

    [Fact]
    public void SpacesInsteadOfCommasGetTheCommaHint()
    {
        string? problem = SectionNumbersRule.Problem("1 3 5");
        Assert.Equal("Use commas between section numbers — e.g. 1,3,5.", problem);
    }

    [Fact]
    public void StrayLetterIsNamed()
    {
        string? problem = SectionNumbersRule.Problem("1a,3 4");
        Assert.NotNull(problem);
        Assert.Contains("“1a”", problem);
    }

    [Fact]
    public void TheSilentDropCaseIsCaught()
    {
        Assert.NotNull(SectionNumbersRule.Problem("1,3 5"));
    }

    [Fact]
    public void EmptyAndPunctuationShapes()
    {
        Assert.NotNull(SectionNumbersRule.Problem(""));
        Assert.Equal("There’s an empty spot between commas.", SectionNumbersRule.Problem("1,,3"));
        Assert.Equal("There’s an empty spot between commas.", SectionNumbersRule.Problem("1,"));
    }

    [Fact]
    public void ZeroAndDuplicates()
    {
        Assert.Equal("“0” isn’t a section number — sections are 1 or higher.", SectionNumbersRule.Problem("0,1"));
        Assert.Equal("Section 1 is listed more than once.", SectionNumbersRule.Problem("1,3,1"));
    }

    [Fact]
    public void TeacherNeedNotTeachSectionOne()
    {
        Assert.Null(SectionNumbersRule.Problem("2,4,5"));
        Assert.Null(SectionNumbersRule.Problem("3"));
        Assert.Null(SectionNumbersRule.Problem("7,2"));
    }
}
