using System.Runtime.InteropServices;
using System.Text;
using Plantoir.Core.Scripting;

namespace Plantoir.Tests;

/// <summary>
/// #155 B5: does a creator whose OWN std handles are redirected leak them into
/// a ConPTY child? The test host is exactly that creator — <c>dotnet test</c>
/// runs it with its stdout and stderr redirected — so the probe runs here,
/// in-process, rather than in a separate fixture executable (bundle-8 ruling
/// 4 asked for a fixture under Plantoir.Tests; the host itself is one).
/// </summary>
[Trait("Kind", "Process")]
public class ConPtyRedirectedParentTests
{
    [Fact]
    public void AChildStartedFromARedirectedParentStillWritesToItsPseudoConsole()
    {
        if (!OperatingSystem.IsWindows()) return;
        string handles = StdioState.Describe(StdioState.FileTypeOf) ?? "no std handle redirected";

        using var pty = ConPtyProcess.Start("cmd.exe /c echo PTY-OK", Path.GetTempPath());
        var transcript = new StringBuilder();
        var reader = Task.Run(() =>
        {
            var buffer = new byte[4096];
            int read;
            while ((read = pty.ReadOutput(buffer)) > 0)
            {
                lock (transcript) transcript.Append(Encoding.UTF8.GetString(buffer, 0, read));
                lock (transcript) if (transcript.ToString().Contains("PTY-OK")) return;
            }
        });
        bool exited = pty.WaitForExit(10_000);
        reader.Wait(TimeSpan.FromSeconds(10));
        string seen;
        lock (transcript) seen = transcript.ToString();
        Assert.True(seen.Contains("PTY-OK"),
            $"The child's output did not reach its pseudo console within 10 s (exited: {exited}; {handles}). " +
            $"Transcript: [{seen.Replace("\u001b", "ESC")}]");
    }

    [Fact]
    public void ARedirectedHandleIsDescribedAndAConsoleOneIsNot()
    {
        Assert.Null(StdioState.Describe(_ => StdioState.FileTypeChar));
        string? line = StdioState.Describe(handle => handle == StdioState.StdOutput ? StdioState.FileTypePipe : StdioState.FileTypeChar);
        Assert.NotNull(line);
        Assert.Contains("stdout=pipe", line);
        Assert.Contains("will not show their output", line);
        Assert.Contains("stdin=disk", StdioState.Describe(handle => handle == StdioState.StdInput ? StdioState.FileTypeDisk : StdioState.FileTypeUnknown)!);
    }
}
