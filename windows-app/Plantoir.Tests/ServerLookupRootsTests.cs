using System;
using System.IO;
using Plantoir.Core.Assist;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// #971 pair A. The app looked for its tools server (<c>plantoir-mcp.exe</c>)
/// and the local assistant's <c>llama-server.exe</c> only beside the running
/// program. Under a test host on Windows ARM the running program is
/// <c>C:\Program Files\dotnet\dotnet.exe</c>, so the lookup found nothing and
/// Claude's door never opened. The search now takes two roots, the process
/// folder and <see cref="AppContext.BaseDirectory"/>; these tests give it a
/// process folder that holds nothing of Plantoir's (as <c>dotnet.exe</c>'s
/// does) and a base folder that holds the server, on any machine.
/// </summary>
public class ServerLookupRootsTests : IDisposable
{
    private readonly string _root = RunOwnedTempFolders.Create("plantoir-971-lookup-");

    public void Dispose()
    {
        try { Directory.Delete(_root, recursive: true); } catch { }
    }

    private string Folder(string name)
    {
        string folder = Path.Combine(_root, name);
        Directory.CreateDirectory(folder);
        return folder;
    }

    private static string Place(string folder, string fileName)
    {
        string path = Path.Combine(folder, fileName);
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, "stand-in");
        return path;
    }

    [Fact]
    public void TheToolsServerIsFoundBesideTheBaseFolderWhenTheProcessIsTheDotnetHost()
    {
        string dotnetFolder = Folder("dotnet");
        Place(dotnetFolder, "dotnet.exe");
        string testsFolder = Folder("tests-bin");
        string server = Place(testsFolder, "plantoir-mcp.exe");

        string? found = ClaudeCodeLauncher.FindServer(dotnetFolder, testsFolder);

        Assert.True(found is not null,
            "No tools server was found although one sits in the base folder " + testsFolder +
            " (the process folder, like dotnet.exe's, holds none).");
        Assert.Equal(server, found, StringComparer.OrdinalIgnoreCase);
    }

    [Fact]
    public void TheInstalledAppFindsTheToolsServerBesidePlantoirExe()
    {
        string installed = Folder("Plantoir");
        Place(installed, "Plantoir.exe");
        string server = Place(installed, "plantoir-mcp.exe");

        Assert.Equal(server, ClaudeCodeLauncher.FindServer(installed, installed), StringComparer.OrdinalIgnoreCase);
        // The same app with a trailing separator on its base folder, as AppContext.BaseDirectory gives it.
        Assert.Equal(server, ClaudeCodeLauncher.FindServer(installed, installed + Path.DirectorySeparatorChar),
            StringComparer.OrdinalIgnoreCase);
    }

    [Fact]
    public void TheToolsServerBesideTheProcessIsStillFoundWhenTheBaseFolderHasNone()
    {
        string installed = Folder("app");
        string server = Place(installed, "plantoir-mcp.exe");
        string elsewhere = Folder("loaded-from");

        Assert.Equal(server, ClaudeCodeLauncher.FindServer(installed, elsewhere), StringComparer.OrdinalIgnoreCase);
    }

    [Fact]
    public void NoToolsServerUnderEitherRootFindsNone()
    {
        Assert.Null(ClaudeCodeLauncher.FindServer(Folder("dotnet"), Folder("tests-bin")));
    }

    [Fact]
    public void TheDevBuildsServerIsFoundByWalkingUpFromTheBaseFolder()
    {
        // The test host's base folder is Plantoir.Tests\bin\Debug\net9.0-…;
        // the server is the sibling project's output.
        string dotnetFolder = Folder("dotnet");
        string testsBin = Folder(Path.Combine("windows-app", "Plantoir.Tests", "bin", "Debug", "net9.0"));
        string server = Place(_root, Path.Combine("windows-app", "Plantoir.Mcp", "bin", "Debug", "net9.0", "win-x64", "plantoir-mcp.exe"));

        Assert.Equal(server, ClaudeCodeLauncher.FindServer(dotnetFolder, testsBin), StringComparer.OrdinalIgnoreCase);
    }

    [Fact]
    public void TheLocalAssistantsServerIsFoundBesideTheBaseFolderWhenTheProcessIsTheDotnetHost()
    {
        string dotnetFolder = Folder("dotnet");
        Place(dotnetFolder, "dotnet.exe");
        string testsFolder = Folder("tests-bin");
        string server = Place(testsFolder, Path.Combine("llama", "llama-server.exe"));

        Assert.Equal(server, LocalModel.FindServer(dotnetFolder, testsFolder), StringComparer.OrdinalIgnoreCase);
    }

    [Fact]
    public void TheInstalledAppFindsTheLocalAssistantsServerInItsLlamaFolder()
    {
        string installed = Folder("Plantoir");
        Place(installed, "Plantoir.exe");
        string server = Place(installed, Path.Combine("llama", "llama-server.exe"));

        Assert.Equal(server, LocalModel.FindServer(installed, installed), StringComparer.OrdinalIgnoreCase);
    }
}
