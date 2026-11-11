using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;
using Plantoir.Core.Scripting;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// Every launcher the app runs gets its arguments through
/// <see cref="ScriptRunner.QuotedArgument"/> (#749's third review). Until then
/// an argument with a space was wrapped in quotes and nothing was escaped, so a
/// saved deploy folder <c>C:\Sites\pub one\</c> reached deploy.ps1 as
/// <c>C:\Sites\pub one"</c>. These hand each input to a REAL
/// <c>powershell.exe -File</c> on a command line built the way ScriptRunner
/// builds it, and read back what the script received.
/// </summary>
public sealed class ScriptRunnerQuotingTests : IDisposable
{
    private readonly string _folder = Path.Combine(Path.GetTempPath(), "quoting-" + Guid.NewGuid().ToString("N"));

    public ScriptRunnerQuotingTests() => Directory.CreateDirectory(_folder);

    public void Dispose()
    {
        try { Directory.Delete(_folder, recursive: true); } catch { }
    }

    public static readonly TheoryData<string> Inputs = new()
    {
        @"C:\Sites\pub one\",
        @"C:\Sites\pub one\\",
        @"\\server\share name\site\",
        @"\\server\share\site",
        @"C:\Sites\pub one",
        @"C:\Sites\pub\",
        "100% & it's",
        @"a&b\",
        "a\tb",
        @"--to-folder=C:\x y\",
        @"C:\Users\t\Plantoir Here\Sites\ics4u\section 1",
        "$env:USERNAME",
    };

    [Theory]
    [MemberData(nameof(Inputs))]
    public void AnArgumentReachesTheLauncherAsItWasGiven(string input)
    {
        string script = Path.Combine(_folder, "echo args.ps1");
        // Each argument as its UTF-16 code units in hex, so a tab, a quote or
        // a stray backslash cannot be hidden by the console.
        File.WriteAllText(script,
            "foreach ($a in $args) { Write-Output ('ARG ' + (-join ([char[]][string]$a | ForEach-Object { '{0:X4}' -f [int]$_ }))) }\n",
            new UTF8Encoding(false));
        string commandLine = "-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "
            + ScriptRunner.QuotedArgument(script) + " " + ScriptRunner.QuotedArgument(input) + " after";
        var info = new ProcessStartInfo("powershell.exe", commandLine)
        {
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true,
        };
        using var process = Process.Start(info)!;
        string output = process.StandardOutput.ReadToEnd() + process.StandardError.ReadToEnd();
        Assert.True(process.WaitForExit(60_000), "powershell.exe did not finish");

        string Hex(string text) => string.Concat(text.Select(c => ((int)c).ToString("X4")));
        string[] received = output.Replace("\r", "").Split('\n')
            .Where(line => line.StartsWith("ARG ", StringComparison.Ordinal))
            .Select(line => line[4..])
            .ToArray();
        Assert.Equal(new[] { Hex(input), Hex("after") }, received);
    }

    [Fact]
    public void AnArgumentThatNeedsNothingIsLeftAsItIs()
    {
        Assert.Equal("ICS3U", ScriptRunner.QuotedArgument("ICS3U"));
        Assert.Equal(@"C:\Sites\pub\", ScriptRunner.QuotedArgument(@"C:\Sites\pub\"));
        Assert.Equal("\"\"", ScriptRunner.QuotedArgument(""));
        Assert.Equal("\"a \\\"b\\\" c\"", ScriptRunner.QuotedArgument("a \"b\" c"));
    }
}
