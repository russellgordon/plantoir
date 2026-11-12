using Plantoir.Core.Assist;
using Plantoir.Core.Scripting;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// Each door's REAL <c>Open</c> refuses a command line over its bound (#736,
/// third review, finding 2): a stub <c>claude.exe</c> and a stub npm-shaped
/// <c>codex.cmd</c> are first on this process's PATH, so <c>FindClaude</c> and
/// <c>FindCodex</c> find them; app data is the suite's scratch folder
/// (<c>TestAppDataRedirect</c>); the trail is a file of this class's own.
/// Over the bound <c>Open</c> returns false, which both callers show as the
/// door's could-not-start sentence (<see cref="OutsideDoorWording"/>); no
/// "started …" line is written and the stub never runs, so no window opens.
/// Must-fail: remove <see cref="OutsideDoor.WithinCommandLineLimit"/> from the
/// doors and the stub runs.
/// </summary>
/// <remarks>Serialized with the trail's other writers: it owns PATH, an
/// environment variable and the trail's path while it runs.</remarks>
[Collection(SharedActivityState.Name)]
public class OutsideDoorRefusalTests : IDisposable
{
    private readonly string _scratch = Directory.CreateTempSubdirectory("plantoir-refusal").FullName;
    private readonly string _stubs, _output, _trail, _folder;
    private readonly string? _oldPath, _oldOutput, _oldTrail;

    public OutsideDoorRefusalTests()
    {
        _stubs = Directory.CreateDirectory(Path.Combine(_scratch, "stubs")).FullName;
        _folder = Directory.CreateDirectory(Path.Combine(_scratch, "Teaching")).FullName;
        _output = Path.Combine(_scratch, "argv.txt");
        _trail = Path.Combine(_scratch, "activity.txt");
        File.Copy(StubProgramCollection.ProbeExe, Path.Combine(_stubs, "claude.exe"));
        File.Copy(StubProgramCollection.ProbeExe, Path.Combine(_stubs, "node.exe"));
        File.WriteAllText(Path.Combine(_stubs, "cli.js"), "");
        File.WriteAllText(Path.Combine(_stubs, "codex.cmd"), "@\"%~dp0node.exe\" \"%~dp0cli.js\" %*\r\n@exit\r\n");
        _oldPath = Environment.GetEnvironmentVariable("PATH");
        _oldOutput = Environment.GetEnvironmentVariable(StubProgramCollection.OutputVariable);
        _oldTrail = ActivityTrail.CurrentLogPath;
        Environment.SetEnvironmentVariable("PATH", _stubs + Path.PathSeparator + _oldPath);
        Environment.SetEnvironmentVariable(StubProgramCollection.OutputVariable, _output);
        ActivityTrail.SetCustomLogPathForTesting(_trail);
    }

    public void Dispose()
    {
        Environment.SetEnvironmentVariable("PATH", _oldPath);
        Environment.SetEnvironmentVariable(StubProgramCollection.OutputVariable, _oldOutput);
        ActivityTrail.SetCustomLogPathForTesting(_oldTrail);
        try { Directory.Delete(_scratch, recursive: true); } catch { }
        GC.SuppressFinalize(this);
    }

    [Theory]
    [InlineData(9_000)]
    [InlineData(40_000)]
    public void AMessageOverTheBoundIsRefused_ByBothDoors_AndNothingRuns(int characters)
    {
        // The guard's channel is the GREETING argument — Fix with…'s message —
        // since the plain greeting now caps the course name (finding 3) and so
        // cannot reach the bound through the name alone. A caller that hands an
        // over-long message is refused, nothing starts, no line is written.
        string message = "Fix these problems: " + new string('m', characters);

        Assert.False(ClaudeCodeLauncher.Open(_folder, "ICS3U", "ICS3U", message), "Claude's door opened over the bound");
        Assert.False(CodexLauncher.Open(_folder, "ICS3U", "ICS3U", message), "Codex's door opened over the bound");

        Assert.False(File.Exists(_output), "a door started its program over the bound");
        string trail = File.Exists(_trail) ? File.ReadAllText(_trail) : "";
        Assert.DoesNotContain("started Claude Code", trail);
        Assert.DoesNotContain("started Codex", trail);

        // What the caller shows a teacher is the door's own could-not-start
        // sentence, which says restarting may help — the same as any other
        // failure to start, not a new message.
        Assert.Contains("couldn’t start a Claude session", OutsideDoorWording.ClaudeCouldNotStart("ICS3U"));
        Assert.Contains("couldn’t start a Codex session", OutsideDoorWording.CodexCouldNotStart("ICS3U"));
    }

    /// <summary>
    /// A long imported course name is CUT in the plain greeting (finding 3),
    /// so Revise With ▸ opens rather than giving the misleading could-not-start
    /// sentence — the door starts, the name arrives cut to 80 characters with
    /// an ellipsis, and the full name is not in the message.
    /// </summary>
    [Fact]
    public void ALongNameIsCutInThePlainGreeting_AndTheDoorOpens()
    {
        string name = new string('n', 9_000);
        string greeting = ClaudeCodeLauncher.Greeting("ICS3U", name);
        Assert.True(FixWithAssistant.Characters(greeting) < 1_000, "the name was not cut in the greeting");
        Assert.DoesNotContain(new string('n', 100), greeting);
        Assert.Contains("…", greeting);

        Assert.True(ClaudeCodeLauncher.Open(_folder, "ICS3U", name), "Claude's door did not open for a long name");
        Assert.True(File.Exists(_output), "the door wrote nothing");
    }
}
