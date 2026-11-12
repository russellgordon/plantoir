using Plantoir.Core.Models;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// "Open in Terminal" never splices a course's folder into a command string
/// (the fallback used to run <c>powershell -Command "Set-Location '{path}'"</c>,
/// injectable through a <c>'</c>, and <c>wt -d "{path}"</c> split at a <c>;</c>).
/// </summary>
public class OutsideTerminalTests
{
    [Theory]
    [InlineData(@"C:\Teaching\O'Brien & Co; rm")]
    [InlineData(@"C:\Teaching\A;B&C")]
    [InlineData(@"C:\Teaching\ends\")]
    [InlineData(@"C:\Teaching\it's a 'course'")]
    public void TheFolderIsAnArgument_NotSplicedIntoACommand(string path)
    {
        var wt = OutsideTerminal.WindowsTerminal(path);
        Assert.Equal("wt.exe", wt.File);
        Assert.Equal(new[] { "-d", "." }, wt.Arguments);
        Assert.Equal(path, wt.WorkingDirectory);
        Assert.DoesNotContain(wt.Arguments, a => a.Contains(path));   // never on a command line
        Assert.False(wt.UseShellExecute);

        var fallback = OutsideTerminal.Fallback(path);
        Assert.Equal(path, fallback.WorkingDirectory);      // the folder, not in any argument
        Assert.DoesNotContain(fallback.Arguments, a => a.Contains("-Command") || a.Contains(path));
    }
}
