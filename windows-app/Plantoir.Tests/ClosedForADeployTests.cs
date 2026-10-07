using Plantoir.Core.Scripting;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// #436 (mac #433's stack review): a serving preview another program's deploy
/// ended reads "Closed for a deploy", not "Something went wrong" — only when
/// ALL of the "preview closed for a deploy" event's conditions hold
/// (<c>shared-rules.json → activityTrail.mustRecord</c>, its <c>why</c>).
/// </summary>
public class ClosedForADeployTests
{
    // What the shared build's stop left in a serving preview's output, measured
    // on this PC: the server's check=True parent's own sentence.
    private const string Killed =
        "subprocess.CalledProcessError: Command '['node', 'quartz/bootstrap-cli.mjs', 'build', '--serve']' " +
        "returned non-zero exit status 15.";

    [Fact]
    public void AllConditionsTogetherAreAClosing() =>
        Assert.True(ScriptRunner.EndIsAClosingForADeploy(1, false, false, true, Killed, true));

    [Theory]
    [InlineData(0, false, false, true, true, "a preview that ended cleanly")]
    [InlineData(1, true, false, true, true, "a preview the teacher stopped")]
    [InlineData(1, false, true, true, true, "a run the teacher backed out of")]
    [InlineData(1, false, false, false, true, "a preview that never served is a failed build")]
    [InlineData(1, false, false, true, false, "no other program building: a failure of its own")]
    public void AnyConditionMissingIsNotAClosing(int exit, bool stopped, bool cancelled, bool serving, bool building, string why) =>
        Assert.False(ScriptRunner.EndIsAClosingForADeploy(exit, stopped, cancelled, serving, Killed, building), why);

    [Fact]
    public void AnEndWithoutTheStopsMarkIsAFailure() =>
        Assert.False(ScriptRunner.EndIsAClosingForADeploy(1, false, false, true,
            "Error: Cannot find module 'quartz'", true));

    [Fact]
    public void TheBadgeIsTheMacs() => Assert.Equal("Closed for a deploy", ScriptRunner.ClosedForADeployOutcome);
}
