using Plantoir.Core.Catalogs;
using Plantoir.Core.Models;

namespace Plantoir.Tests;

/// <summary>
/// <see cref="CourseConfiguration.CurriculumPagesOffered"/> (GitHub issue #252):
/// a declined payload keeps its curriculum when the skeleton is kept. The
/// contract cases (<c>expectSavedIncludeCurriculumPages</c>) run in
/// <see cref="WizardSkeletonToggleTests"/>; these are the three codes the
/// mac measured, one per shape.
/// </summary>
public class CurriculumPagesOfferedTests
{
    private static bool Offered(string code, bool taking, bool skeleton) =>
        CourseConfiguration.CurriculumPagesOffered(
            WizardSkeletonToggleTests.ExampleContentRoot, WizardSkeletonToggleTests.SkeletonsRoot, code, taking, skeleton);

    [Fact]
    public void ADeclinedOntarioPayloadKeepingItsSkeletonKeepsItsCurriculum() =>
        Assert.True(Offered("ICS4U", taking: false, skeleton: true));

    [Fact]
    public void ADeclinedBritishColumbiaPayloadOnTheGeneralSkeletonKeepsItsCurriculum() =>
        Assert.True(Offered("MCMPR11", taking: false, skeleton: true));

    [Fact]
    public void ACodeWithNoPayloadHasNoCurriculumToOffer() =>
        Assert.False(Offered("ICS2O", taking: false, skeleton: true));

    [Fact]
    public void DecliningTheSkeletonTooDeclinesTheCurriculum() =>
        Assert.False(Offered("ICS4U", taking: false, skeleton: false));

    [Fact]
    public void TakingThePayloadOffersItsCurriculumWhateverTheSkeletonToggleSays() =>
        Assert.True(Offered("ICS4U", taking: true, skeleton: false));

    /// <summary>The written file, end to end through the dialog's Core half.</summary>
    [Fact]
    public void ADeclinedPayloadKeepingItsSkeletonIsWrittenWithItsCurriculumPages()
    {
        var keys = NewCourseAnswers.Decide(WizardSkeletonToggleTests.ExampleContentRoot, WizardSkeletonToggleTests.SkeletonsRoot,
            new NewCourseAnswers.Choices("ICS4U", Prepopulate: false, StartsFromSkeleton: true, IncludeCurriculum: true,
                WizardStructure.Defaults(false))).Keys;
        Assert.True(keys["include_curriculum_pages"]!.ToObject<bool>());
        Assert.True(keys["use_skeleton"]!.ToObject<bool>());
    }
}
