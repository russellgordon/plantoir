using Plantoir.Core.Assist;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// Pins the `/TR` quoting bug found 2026-08-23, from a real report: a
/// scheduled deploy set the night before never fired. `TaskScheduling`
/// used to build the stored command with `\\\"` (a literal backslash
/// followed by a quote — two characters) instead of a real embedded quote,
/// so `schtasks /Query ... /XML` showed `&lt;Arguments&gt;` holding
/// `\"C:\...\script.ps1\"` verbatim — a path PowerShell's `-File` could
/// never resolve. The task ran (Task Scheduler's own "Last Run Time" was
/// populated) and still did nothing, which is what made it so easy to miss:
/// nothing about SCHEDULING failed, only the run itself, silently, hours
/// later with nobody watching. Since bundle 3 the task runs Plantoir with a
/// job file (#347), and the same rule holds for both paths it carries.
/// </summary>
public class TaskSchedulingTests
{
    [Fact]
    public void TaskRunCommand_UsesARealQuoteCharacter_NotABackslashAndAQuote()
    {
        string command = TaskScheduling.TaskRunCommand(
            @"C:\Users\lenov\AppData\Local\Programs\Plantoir\Plantoir.exe",
            @"C:\Users\lenov\AppData\Local\Plantoir\scheduled\test.job.json");

        // The literal two-character sequence backslash-then-quote must never
        // appear — that is exactly the bug. Real quote characters round each
        // path instead.
        Assert.DoesNotContain("\\\"", command);
        Assert.Equal(
            "\"C:\\Users\\lenov\\AppData\\Local\\Programs\\Plantoir\\Plantoir.exe\" --run-scheduled-deploy " +
            "\"C:\\Users\\lenov\\AppData\\Local\\Plantoir\\scheduled\\test.job.json\"",
            command);
    }

    [Fact]
    public void TaskRunCommand_QuotesPathsContainingSpaces()
    {
        // The case that actually broke — a path with spaces in it.
        string command = TaskScheduling.TaskRunCommand(
            @"C:\Program Files\Plantoir\Plantoir.exe", @"C:\Users\a teacher\scheduled\x.job.json");

        Assert.DoesNotContain("\\\"", command);
        Assert.StartsWith("\"C:\\Program Files\\Plantoir\\Plantoir.exe\" --run-scheduled-deploy \"", command);
        Assert.EndsWith("x.job.json\"", command);
    }

    [Fact]
    public void TheWrapperIsRunNonInteractively()
    {
        // Nobody is there to answer a question at 6 a.m. `preview.ps1` asks
        // "Continue anyway?" when a section is not listed in
        // course_config.json - which is exactly the state a course is left in
        // when one of its sections is archived while a scheduled deploy for
        // that section still exists. Without -NonInteractive the run sits at
        // an invisible prompt until Task Scheduler's own limit (three days by
        // default): the teacher's site is never updated and nothing says why.
        // With it, Read-Host throws, the wrapper exits non-zero, and the run
        // fails visibly.
        Assert.Contains("-NonInteractive", TaskScheduling.WrapperRunArguments(@"C:\x\y.ps1"));
    }

    [Fact]
    public void ATasksNameCarriesTheWorkingFoldersId()
    {
        // #309: one task per code, section and working folder, machine-wide.
        string folder = Path.GetTempPath();
        Assert.Equal($"Plantoir deploy ICS3U section 1 {Plantoir.Core.Models.FolderContainers.FolderIdentifier(folder)}",
                     TaskScheduling.NameFor("ics3u", 1, folder));
    }
}
