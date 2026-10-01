using System.Runtime.InteropServices;

namespace Plantoir.UiTests;

/// <summary>
/// The rule every negative UI check now goes through (bundle 11, V1), pinned
/// WITHOUT a desktop: these are plain facts, not [UiFact]s, so they run in any
/// <c>dotnet test</c> of this project. The must-fail the ruling asked for is
/// the first one: a tree that only ever times out turns an absence check RED,
/// where <c>Assert.Null(FindOrNull(...))</c> passed it.
/// </summary>
public class AssertAbsentRuleTests
{
    private const int UiaTimeout = unchecked((int)0x80131505);

    [Fact]
    public void ATreeThatNeverAnswersIsNotAnAbsence()
    {
        var error = Assert.Throws<Xunit.Sdk.XunitException>(() =>
            DrivenApp.AssertAbsentWith(() => throw new COMException("Operation timed out.", UiaTimeout),
                                       "deployButton", "the Deploy button",
                                       TimeSpan.FromMilliseconds(200), TimeSpan.FromMilliseconds(400)));
        Assert.Contains("Could not tell", error.Message);
    }

    [Fact]
    public void AnAnsweringTreeWithNothingThereIsAnAbsence() =>
        DrivenApp.AssertAbsentWith(() => null, "deployButton", "the Deploy button", TimeSpan.FromMilliseconds(200));

    [Fact]
    public void ATimeoutFollowedByAnAnswerIsAnAbsence()
    {
        int asked = 0;
        DrivenApp.AssertAbsentWith(() => ++asked < 3 ? throw new COMException("Operation timed out.", UiaTimeout) : null,
                                   "deployButton", "the Deploy button", TimeSpan.FromMilliseconds(200));
        Assert.Equal(3, asked);
    }
}
