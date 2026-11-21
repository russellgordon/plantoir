using Plantoir.Core.Scripting;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// #1026: a stop's two-second kill fallback (<c>ScriptRunner.CancelByUser</c>)
/// belongs to the run it was set for. A run started on the same runner inside
/// the two seconds, which Stop then Preview again makes a two-second gesture,
/// is never terminated by it. Each test awaits the fallback's own completion
/// (the task <c>CancelByUser</c> returns), never a clock of its own.
/// </summary>
public class StopFallbackOwnsItsRunTests
{
    [Fact]
    public async Task ARunStartedInsideTheGraceOutlivesTheEarlierStopsFallback()
    {
        var runner = new ScriptRunner();
        runner.StageAsRunningForCapture(Array.Empty<TaskMilestone>(), "building\n");
        int stoppedRun = runner.CurrentRunNumber;

        Task fallback = runner.CancelByUser();
        // The stopped run ends on Control-C, and the next preview starts at
        // once on the same runner, all inside the grace.
        runner.FinishRunNumber(stoppedRun, 0);
        runner.StageAsRunningForCapture(Array.Empty<TaskMilestone>(), "building again\n");
        Assert.False(fallback.IsCompleted, "the grace was over before the second run started; the test proves nothing");

        await fallback;

        Assert.True(runner.IsRunning, "the second run was ended by the first stop's fallback");
        Assert.Equal(0, runner.FallbackTerminations);
    }

    [Fact]
    public async Task ARunThatIgnoresControlCIsStillTerminatedByItsOwnFallback()
    {
        var runner = new ScriptRunner();
        runner.StageAsRunningForCapture(Array.Empty<TaskMilestone>(), "building\n");

        await runner.CancelByUser();

        Assert.Equal(1, runner.FallbackTerminations);
    }
}
