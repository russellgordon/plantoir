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
/// later with nobody watching.
/// </summary>
public class TaskSchedulingTests
{
    [Fact]
    public void TaskRunCommand_UsesARealQuoteCharacter_NotABackslashAndAQuote()
    {
        string command = TaskScheduling.TaskRunCommand(@"C:\Users\lenov\AppData\Local\Plantoir\scheduled\test.ps1");

        // The literal two-character sequence backslash-then-quote must never
        // appear — that is exactly the bug. A real quote character appears
        // immediately after "-File " and immediately at the end instead.
        Assert.DoesNotContain("\\\"", command);
        Assert.Equal(
            "powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"C:\\Users\\lenov\\AppData\\Local\\Plantoir\\scheduled\\test.ps1\"",
            command);
    }

    [Fact]
    public void TaskRunCommand_QuotesAPathContainingSpaces()
    {
        // The case that actually broke — a Desktop working folder with
        // spaces in its name ("scheduled deploy test").
        string command = TaskScheduling.TaskRunCommand(@"C:\Users\lenov\Desktop\Developer\scheduled deploy test\wrapper.ps1");

        Assert.DoesNotContain("\\\"", command);
        Assert.StartsWith("powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"", command);
        Assert.EndsWith("wrapper.ps1\"", command);
    }
}
