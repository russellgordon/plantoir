namespace Plantoir.UiTests;

/// <summary>
/// The rule <see cref="SectionAndClassesUiTests"/> reads a menu's separators
/// by (<see cref="SectionAndClassesUiTests.SeparatorGaps"/>), pinned as plain
/// facts that need no desktop (#990 round 3, the second review's low: the old
/// rule was "more than 1 pixel over the smallest gap", measured at 100% only).
/// The gaps here are what a menu's item rectangles could give at different
/// scalings: every gap inside a group is one drawn spacing, rounded to device
/// pixels, and every gap across a separator is that spacing plus the
/// separator. The rule compares the gaps with each other, so the same rule
/// reads every scaling.
/// </summary>
public class SeparatorGapsRuleTests
{
    [Fact]
    public void AtOneHundredPercent_TheWiderGapsAreTheSeparators()
    {
        // Measured in the VM on 2026-11-20: 4 or 5 inside a group, 7 or 8 across.
        Assert.Equal(new HashSet<int> { 2, 5 }, SectionAndClassesUiTests.SeparatorGaps(new[] { 4, 5, 8, 4, 4, 7, 5 }));
    }

    /// <summary>
    /// MUST FAIL under the old rule, which read the 9 as a separator because
    /// it is more than 1 pixel over the 7: at a larger scaling one drawn
    /// spacing can round two ways that are 2 pixels apart.
    /// </summary>
    [Fact]
    public void AtALargerScaling_TwoRoundingsOfOneSpacingAreNotASeparator()
    {
        Assert.Equal(new HashSet<int> { 3 }, SectionAndClassesUiTests.SeparatorGaps(new[] { 7, 9, 7, 14, 9 }));
    }

    [Fact]
    public void GapsAllEqual_NoSeparator()
    {
        Assert.Empty(SectionAndClassesUiTests.SeparatorGaps(new[] { 4, 4, 4 }));
    }

    /// <summary>Gaps that do not fall into two clear sets fail the reading rather than guess.</summary>
    [Fact]
    public void GapsWithNoClearSplit_FailTheReading()
    {
        var error = Assert.Throws<Xunit.Sdk.XunitException>(() => SectionAndClassesUiTests.SeparatorGaps(new[] { 4, 6, 8, 10 }));
        Assert.Contains("cannot be read", error.Message);
    }
}
