using System;
using System.IO;
using Plantoir.Core.Models;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// #641: a run started with <c>--state-dir</c> hands it to the window's own
/// <c>plantoir-mcp</c>, which applies it before anything resolves a path.
/// Without it the server's trail lines went to the PC's REAL trail. The rule
/// is pure (<see cref="AppDataRoot.HandOnArguments"/>,
/// <see cref="AppDataRoot.StateDirFrom"/>); the two callers live in projects
/// this suite does not reference (the app) or in top-level statements (the
/// server), so each is pinned by its source as well.
/// </summary>
public class StateDirHandOnTests
{
    [Fact]
    public void ARedirectedRunHandsOnTheFlagAndItsFolder() =>
        Assert.Equal(new[] { "--state-dir", @"C:\Temp\plantoir-ui-x\state" },
                     AppDataRoot.HandOnArguments(@"C:\Temp\plantoir-ui-x\state"));

    [Fact]
    public void AnOrdinaryRunHandsOnNothing() =>
        Assert.Empty(AppDataRoot.HandOnArguments(null));

    [Fact]
    public void ThisSuiteIsRedirected_SoItsOwnAnswerIsItsScratchFolder() =>
        Assert.Equal(new[] { "--state-dir", AppDataRoot.Current }, AppDataRoot.ArgumentsToHandOn);

    [Theory]
    [InlineData(new[] { "--folder", @"C:\W", "--state-dir", @"C:\S" }, @"C:\S")]
    [InlineData(new[] { "--state-dir", @"C:\S", "--course", "ICS3U" }, @"C:\S")]
    [InlineData(new[] { "--state-dir", @"C:\First", "--state-dir", @"C:\Second" }, @"C:\First")]
    public void TheServerReadsTheSpaceSeparatedForm(string[] args, string expected) =>
        Assert.Equal(expected, AppDataRoot.StateDirFrom(args));

    [Theory]
    [InlineData("--folder|C:\\W")]
    [InlineData("--state-dir")]                   // no value after it
    [InlineData("--state-dir=C:\\S")]             // not accepted, by design
    public void NoFolderIsReadWhenNoneIsGivenInThatForm(string args) =>
        Assert.Null(AppDataRoot.StateDirFrom(args.Split('|')));

    private static string WindowsApp
    {
        get
        {
            var dir = new DirectoryInfo(AppContext.BaseDirectory);
            while (dir is not null && dir.Name != "windows-app") dir = dir.Parent;
            return dir?.FullName ?? throw new DirectoryNotFoundException("Could not locate windows-app/ from " + AppContext.BaseDirectory);
        }
    }

    [Fact]
    public void TheWindowsServerIsStartedWithTheHandOn()
    {
        string source = File.ReadAllText(Path.Combine(WindowsApp, "Plantoir", "Services", "McpClient.cs"));
        int start = source.IndexOf("ProcessStartInfo ServerStartInfo(", StringComparison.Ordinal);
        Assert.True(start >= 0, "McpClient.ServerStartInfo is gone; pin wherever the server is started now");
        int end = source.IndexOf("return info;", start, StringComparison.Ordinal);
        Assert.Contains("AppDataRoot.ArgumentsToHandOn", source[start..end]);
    }

    [Fact]
    public void TheServerAppliesItBeforeItOpensTheWorkingFolder()
    {
        string source = File.ReadAllText(Path.Combine(WindowsApp, "Plantoir.Mcp", "Program.cs"));
        int applied = source.IndexOf("AppDataRoot.RedirectTo(", StringComparison.Ordinal);
        int read = source.IndexOf("AppDataRoot.StateDirFrom(args)", StringComparison.Ordinal);
        int opened = source.IndexOf("new AssistWorkspace(", StringComparison.Ordinal);
        Assert.True(read >= 0 && applied > read, "plantoir-mcp no longer reads --state-dir with AppDataRoot.StateDirFrom");
        Assert.True(opened > applied, "plantoir-mcp opens the working folder before applying --state-dir");
    }
}
