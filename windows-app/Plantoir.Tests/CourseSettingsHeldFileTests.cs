using System.Diagnostics;
using System.Text.RegularExpressions;
using Newtonsoft.Json.Linq;
using Plantoir.Core.Models;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// A SECOND PROCESS holding a file open with a named share mode (#874's own
/// requirement): PowerShell opens it, says "holding" on standard output, and
/// waits on standard input. The test waits for that line (an event, never a
/// sleep) and lets go by closing standard input and waiting for the exit.
/// </summary>
internal sealed class SecondProcessHold : IDisposable
{
    private readonly Process _process;
    private bool _released;

    public SecondProcessHold(string path, FileShare share)
    {
        var start = new ProcessStartInfo("powershell.exe")
        {
            RedirectStandardInput = true,
            RedirectStandardOutput = true,
            UseShellExecute = false,
            CreateNoWindow = true,
        };
        start.ArgumentList.Add("-NoProfile");
        start.ArgumentList.Add("-Command");
        start.ArgumentList.Add(
            "$f = [System.IO.File]::Open($env:PLANTOIR_HOLD_PATH, 'Open', 'Read', $env:PLANTOIR_HOLD_SHARE); " +
            "[Console]::Out.WriteLine('holding'); [Console]::Out.Flush(); " +
            "[void][Console]::In.ReadToEnd(); $f.Close()");
        start.Environment["PLANTOIR_HOLD_PATH"] = path;
        start.Environment["PLANTOIR_HOLD_SHARE"] = share.ToString();
        _process = Process.Start(start)!;
        string? line = _process.StandardOutput.ReadLine();
        if (line != "holding")
        {
            Release();
            throw new InvalidOperationException("the second process did not take the hold: " + line);
        }
    }

    public void Release()
    {
        if (_released) return;
        _released = true;
        _process.StandardInput.Close();
        // A bound on a broken holder, not a wait for timing: the exit is the event.
        if (!_process.WaitForExit(60_000)) _process.Kill();
        _process.Dispose();
    }

    public void Dispose() => Release();
}

/// <summary>
/// #874: the app's own readers and writer of <c>course_config.json</c> ask
/// again while another program holds it, and a read refused past the bound is
/// "could not read just now", never "no settings" or "unreadable": nothing is
/// written after it, the window keeps its edits, the course stays listed.
/// </summary>
public sealed class CourseSettingsHeldFileTests : IDisposable
{
    private readonly string _workspace = Directory.CreateTempSubdirectory("held-settings-").FullName;
    private string CourseDir => Path.Combine(_workspace, "courses", "ICS3U");
    private string ConfigPath => Path.Combine(CourseDir, "course_config.json");

    public CourseSettingsHeldFileTests()
    {
        Directory.CreateDirectory(CourseDir);
        File.WriteAllText(ConfigPath, """{"hidden":["Media","Tasks","Style"],"show_reading_time":false}""");
    }

    public void Dispose() { try { Directory.Delete(_workspace, true); } catch { } }

    private string[] Temporaries() => Directory.GetFiles(CourseDir, "*.tmp");

    [Fact]
    public void HeldWholeEveryReaderAndTheWriterSayCouldNotReadJustNowAndWriteNothing()
    {
        var window = CourseConfiguration.Load(ConfigPath);
        var listed = Workspace.DiscoverCourses(_workspace);
        Assert.Single(listed);
        window.Values["show_reading_time"] = true;
        byte[] before = File.ReadAllBytes(ConfigPath);
        var pauses = new List<int>();
        using (HeldFiles.PausingWith(pauses.Add))
        using (new SecondProcessHold(ConfigPath, FileShare.None))
        {
            Assert.Throws<FileInUseException>(() => CourseConfiguration.Load(ConfigPath));
            Assert.Equal(HeldFiles.Pauses, pauses);

            var refused = Assert.Throws<FileInUseException>(() => window.Write(ConfigPath));
            Assert.Equal(HeldFiles.InUseSentence("course_config.json"), refused.Message);
            Assert.Equal("course_config.json is in use by another program, so it was not changed.", refused.Message);

            Assert.False(window.RevertToFile(ConfigPath));
            Assert.True(window.Values["show_reading_time"]!.Value<bool>());   // the edit is kept
            Assert.True(window.HasUnsavedChanges);
            Assert.False(window.RereadIfNothingUnsaved(ConfigPath));

            var again = Workspace.DiscoverCourses(_workspace, listed);
            Assert.Same(listed[0], Assert.Single(again));                     // still listed

            Assert.Throws<FileInUseException>(() =>
                window.RecordOnDisk(values => { values["unit_word"] = "Topic"; return values; }, ConfigPath));
        }
        Assert.Equal(before, File.ReadAllBytes(ConfigPath));
        Assert.Empty(Temporaries());
    }

    [Fact]
    public void HeldByAReaderTheRenameIsRefusedPastTheBoundAndTheFileIsUnchanged()
    {
        var window = CourseConfiguration.Load(ConfigPath);
        window.Values["show_reading_time"] = true;
        byte[] before = File.ReadAllBytes(ConfigPath);
        var pauses = new List<int>();
        using (HeldFiles.PausingWith(pauses.Add))
        using (new SecondProcessHold(ConfigPath, FileShare.Read))
        {
            var refused = Assert.Throws<FileInUseException>(() => window.Write(ConfigPath));
            Assert.Equal(HeldFiles.InUseSentence("course_config.json"), refused.Message);
        }
        Assert.Equal(HeldFiles.Pauses, pauses);
        Assert.Equal(before, File.ReadAllBytes(ConfigPath));
        Assert.Empty(Temporaries());
    }

    [Fact]
    public void AReaderThatLetsGoOnTheFirstPauseLetsTheMergedSaveLand()
    {
        // TwoWindowSettingsTests.TheOtherWindowsHidesSurviveAStaleWindowsSave, with a build's reader in the way.
        var windowA = CourseConfiguration.Load(ConfigPath);
        var windowB = CourseConfiguration.Load(ConfigPath);
        windowA.Values["hidden"] = new JArray("Media", "All Classes");
        windowA.Write(ConfigPath);
        windowB.Values["show_reading_time"] = true;

        var pauses = new List<int>();
        var holder = new SecondProcessHold(ConfigPath, FileShare.Read);
        CourseConfiguration.SaveReport report;
        using (HeldFiles.PausingWith(milliseconds => { pauses.Add(milliseconds); holder.Release(); }))
            report = windowB.Write(ConfigPath);
        holder.Dispose();

        Assert.Equal(new[] { HeldFiles.Pauses[0] }, pauses);
        var onDisk = JObject.Parse(File.ReadAllText(ConfigPath));
        Assert.Equal(new[] { "Media", "All Classes" }, onDisk["hidden"]!.Select(t => t.ToString()));
        Assert.True(onDisk["show_reading_time"]!.Value<bool>());
        Assert.Equal(new[] { "hidden" }, report.KeptFromElsewhere);
        Assert.False(windowB.HasUnsavedChanges);
        Assert.Empty(Temporaries());
    }

    [Fact]
    public void AFileThatIsNotValidJsonStillTakesTheWholeCopy()
    {
        var window = CourseConfiguration.Load(ConfigPath);
        window.Values["show_reading_time"] = true;
        File.WriteAllText(ConfigPath, "{ not json");
        var pauses = new List<int>();
        using (HeldFiles.PausingWith(pauses.Add)) window.Write(ConfigPath);
        Assert.Empty(pauses);
        Assert.True(JToken.DeepEquals(window.Values, JObject.Parse(File.ReadAllText(ConfigPath))));
        Assert.Empty(Temporaries());
    }

    /// <summary>
    /// ONE reader of course_config.json's bytes: no product file reads one
    /// with File.ReadAllBytes or File.ReadAllText except
    /// <see cref="CourseConfiguration.ReadBytes"/> (through
    /// <see cref="HeldFiles.ReadBytes"/>). Excepted by name: CourseRestorer.cs
    /// (the restore batch, #873/#805/#911) and CourseSettingsView.xaml.cs,
    /// whose Save is rewritten by #986 (its before-read only chooses what the
    /// trail compares with; the Save itself goes through Write).
    /// </summary>
    [Fact]
    public void EveryReaderOfTheSettingsGoesThroughTheOneReader()
    {
        string windowsApp = Path.Combine(ContractLoader.RepositoryRoot, "windows-app");
        var excepted = new HashSet<string>(StringComparer.Ordinal)
        {
            "Plantoir.Core/Models/CourseRestorer.cs",
            "Plantoir/Views/CourseSettingsView.xaml.cs",
        };
        var call = new Regex(@"\bFile\.ReadAll(?:Bytes|Text|Lines)\w*\s*\(\s*([^;]*?)\)\s*[;),]", RegexOptions.CultureInvariant);
        var found = new List<string>();
        int scanned = 0;
        foreach (string project in new[] { "Plantoir", "Plantoir.Core", "Plantoir.Mcp", "PtyDriver" })
        {
            foreach (string file in Directory.EnumerateFiles(Path.Combine(windowsApp, project), "*.cs", SearchOption.AllDirectories))
            {
                string relative = Path.GetRelativePath(windowsApp, file).Replace('\\', '/');
                if (relative.Contains("/bin/") || relative.Contains("/obj/") || excepted.Contains(relative)) continue;
                scanned++;
                string source = UndoWriterScanTests.WithoutComments(File.ReadAllText(file), file);
                foreach (Match match in call.Matches(source))
                {
                    if (NamesTheSettings(match.Groups[1].Value, source))
                        found.Add(relative + ": " + match.Value.Trim());
                }
            }
        }
        Assert.True(scanned > 100, $"only {scanned} files scanned");
        Assert.True(found.Count == 0, "read course_config.json through CourseConfiguration.ReadBytes or Load: " + string.Join("; ", found));
    }

    /// <summary>The argument names the settings itself, or is a name this file sets from an expression that does.</summary>
    internal static bool NamesTheSettings(string argument, string source)
    {
        var settings = new Regex(@"course_config\.json|ConfigFilePath|ConfigFileName", RegexOptions.CultureInvariant);
        if (settings.IsMatch(argument)) return true;
        var name = Regex.Match(argument.Trim(), @"^[A-Za-z_]\w*$");
        if (!name.Success) return false;
        return new Regex(@"\b" + Regex.Escape(name.Value) + @"\s*=\s*[^;=]*(?:course_config\.json|ConfigFilePath|ConfigFileName)",
                         RegexOptions.CultureInvariant).IsMatch(source);
    }

    [Fact]
    public void TheScanSeesBothShapesOfAReader()
    {
        Assert.True(NamesTheSettings("course.ConfigFilePath", ""));
        Assert.True(NamesTheSettings("config", "string config = Path.Combine(directory, \"course_config.json\");"));
        Assert.False(NamesTheSettings("settings", "string settings = Path.Combine(obsidian, \"app.json\");"));
    }
}
