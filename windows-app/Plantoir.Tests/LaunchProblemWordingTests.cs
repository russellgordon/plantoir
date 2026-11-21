using Plantoir.Core.Assist;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;

namespace Plantoir.Tests;

/// <summary>
/// #928 items 8 and 9 (the mac's <c>ScriptRunnerLaunchProblemTests</c>): a
/// launch problem is a sentence a teacher reads under "Cannot Preview Yet",
/// so it names no file and carries no system text. The launcher's name and
/// the system's description go to <see cref="ScriptRunner.LaunchProblemDetail"/>,
/// which only the trail reads.
/// </summary>
public class LaunchProblemWordingTests
{
    private static readonly string[] MachineryWords = { ".sh", ".ps1", ".py", "launcher", "script" };

    private static void SaysNoMachinery(string sentence, string where)
    {
        foreach (string word in MachineryWords)
            Assert.False(sentence.Contains(word, StringComparison.OrdinalIgnoreCase),
                         $"{where} names \"{word}\": {sentence}");
    }

    [Fact]
    public void EveryLaunchProblemNamesNoMachinery()
    {
        SaysNoMachinery(ScriptRunner.CouldNotGetStarted, "the launch failure");
        SaysNoMachinery(ScriptRunner.FolderIsMissingAPiece, "the missing launcher");
        SaysNoMachinery(ToolchainReadiness.RefusalFor(ToolchainReadiness.State.Copying)!, "the tools being copied");
        SaysNoMachinery(ToolchainReadiness.RefusalFor(ToolchainReadiness.State.Failed)!, "the tools that failed to copy");
    }

    /// <summary>Met for real: a run in a folder with no launcher.</summary>
    [Fact]
    public void AMissingLauncherIsSaidWithoutItsNameAndTheTrailKeepsIt()
    {
        string emptyFolder = Path.Combine(Path.GetTempPath(), $"plantoir-928-{Guid.NewGuid():N}");
        Directory.CreateDirectory(emptyFolder);
        try
        {
            var runner = new ScriptRunner();
            runner.Run("preview.ps1", new[] { "ICS3U", "1" }, emptyFolder);
            Assert.False(runner.IsRunning);
            Assert.Null(runner.LastExitCode);
            Assert.Equal(ScriptRunner.FolderIsMissingAPiece, runner.LaunchProblem);
            SaysNoMachinery(runner.LaunchProblem!, "the run's launch problem");
            Assert.DoesNotContain(emptyFolder, runner.LaunchProblem!);
            Assert.Equal("the working folder has no preview.ps1", runner.LaunchProblemDetail);
            Assert.Equal(PreviewStarts.RunStanding.CouldNotStart,
                         PreviewStarts.HowTheRunStands(runner.IsRunning, runner.LastExitCode, runner.LaunchProblem));

            Assert.Equal("the preview could not start, and the teacher was told why: "
                         + ScriptRunner.FolderIsMissingAPiece + " (the working folder has no preview.ps1)",
                         PreviewStarts.CouldNotStartLine(runner.LaunchProblem!, runner.LaunchProblemDetail));
        }
        finally
        {
            try { Directory.Delete(emptyFolder, true); } catch { }
        }
    }

    /// <summary>The scheduled deploy's refusal for a missing launcher drops the file and the folder the same way.</summary>
    [Fact]
    public void TheScheduledDeploysRefusalNamesNoFileOrFolder()
    {
        SaysNoMachinery(TaskScheduling.NothingToSchedule, "the scheduled deploy's refusal");
        Assert.DoesNotContain(":\\", TaskScheduling.NothingToSchedule);
    }
}
