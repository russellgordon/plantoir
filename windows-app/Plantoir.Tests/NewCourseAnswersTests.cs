using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using Plantoir.Core.Catalogs;

namespace Plantoir.Tests;

/// <summary>
/// What the New Course wizard writes for its Starting Content answers
/// (<see cref="NewCourseAnswers"/>), GitHub issue #250.
///
/// <para><b>The thing that must not move.</b> The six files in
/// <c>Goldens/</c> were captured BEFORE a line of #250's fix was written, by a
/// throwaway test running the old rule (example content EXISTING suppressed the
/// skeleton) over the same inputs: ADA1O, MCV4U (the only family whose marks
/// pool is not <c>["Tasks"]</c>), MCMPR11 (the default family, and BC) and
/// ICS4U with the ready-made pages TAKEN, plus AMU3M with the skeleton on and
/// off for the ~1,900 codes with no payload. A teacher who takes the pages must
/// still get exactly those keys. The mac's technique, copied
/// (<c>mac-app/Tests/Goldens/</c>).</para>
/// </summary>
public class NewCourseAnswersTests
{
    private static string Ex => WizardSkeletonToggleTests.ExampleContentRoot;
    private static string Sk => WizardSkeletonToggleTests.SkeletonsRoot;

    private static JObject Decide(string code, bool prepopulate, bool skeleton, bool includeCurriculum = true) =>
        NewCourseAnswers.Decide(Ex, Sk, new NewCourseAnswers.Choices(
            code, prepopulate, skeleton, includeCurriculum, WizardStructure.Defaults(false))).Keys;

    [Theory]
    [InlineData("ADA1O-taken", "ADA1O", true)]
    [InlineData("MCV4U-taken", "MCV4U", true)]
    [InlineData("MCMPR11-taken", "MCMPR11", true)]
    [InlineData("ICS4U-taken", "ICS4U", true)]
    [InlineData("AMU3M-skeleton-on", "AMU3M", true)]
    [InlineData("AMU3M-skeleton-off", "AMU3M", false)]
    public void ACourseTakingTheReadyMadePagesIsWrittenExactlyAsBefore(string golden, string code, bool skeleton)
    {
        string expected = File.ReadAllText(Path.Combine(
            ContractLoader.RepositoryRoot, "windows-app", "Plantoir.Tests", "Goldens", golden + ".json")).Replace("\r\n", "\n");
        string actual = Decide(code, prepopulate: true, skeleton).ToString(Formatting.Indented).Replace("\r\n", "\n") + "\n";
        Assert.Equal(expected, actual);
    }

    /// <summary>
    /// The bug itself, in the file: ICS4U declined, skeleton kept. Before #250
    /// this wrote <c>use_skeleton: false</c> and the factory folders, and
    /// <c>setup_course.py</c> made 18 pages where the skeleton makes 47.
    /// </summary>
    [Fact]
    public void ADeclinedPayloadWritesTheSubjectsSkeleton()
    {
        var keys = Decide("ICS4U", prepopulate: false, skeleton: true);
        var family = SkeletonCatalog.GetFamily(Sk, "ICS4U")!;

        Assert.False(keys["prepopulate_example_content"]!.Value<bool>());
        Assert.True(keys["use_skeleton"]!.Value<bool>());
        Assert.Equal(family.SharedFolders, keys["shared_folders"]!.Select(t => t.ToString()));
    }

    [Fact]
    public void DecliningBothWritesEmptyFolders()
    {
        var keys = Decide("ICS4U", prepopulate: false, skeleton: false);

        Assert.False(keys["prepopulate_example_content"]!.Value<bool>());
        Assert.False(keys["use_skeleton"]!.Value<bool>());
        Assert.Equal(WizardDefaults.SharedFolders, keys["shared_folders"]!.Select(t => t.ToString()));
    }
}
