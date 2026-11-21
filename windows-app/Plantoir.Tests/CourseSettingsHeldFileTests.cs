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
/// A SECOND PROCESS doing what a build's Python does to course_config.json
/// (<c>build_site._atomic_write_json_with_backup</c>): write a temporary
/// beside it, then <c>os.replace</c>, which on Windows is
/// <c>MoveFileExW(temporary, target, MOVEFILE_REPLACE_EXISTING)</c>, a
/// refused replace being tried again on the next round. It says "replacing"
/// after its first replace that landed and "done" after <c>count</c> rounds.
/// </summary>
internal sealed class BuildReplacingInALoop : IDisposable
{
    private readonly Process _process;

    /// <summary>The replacer's last line, "done", once it has finished.</summary>
    public Task<string?> Done { get; }

    public BuildReplacingInALoop(string target, int count)
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
            "Add-Type -TypeDefinition 'using System.Runtime.InteropServices; public static class BuildReplace { " +
            "[DllImport(\"kernel32.dll\", CharSet = CharSet.Unicode, SetLastError = true)] " +
            "public static extern bool MoveFileExW(string from, string to, int flags); }'; " +
            "$said = $false; $t = $env:PLANTOIR_REPLACE_TARGET; $d = Split-Path $t; $n = [int]$env:PLANTOIR_REPLACE_COUNT; " +
            "for ($i = 1; $i -le $n; $i++) { " +
            "  $tmp = Join-Path $d ('.course_config.json.build-' + $i + '.tmp'); " +
            "  [System.IO.File]::WriteAllText($tmp, '{\"hidden\":[\"Media\"],\"show_reading_time\":false,\"build_count\":' + $i + '}'); " +
            "  if (-not [BuildReplace]::MoveFileExW($tmp, $t, 1)) { [System.IO.File]::Delete($tmp) } " +
            "  elseif (-not $said) { $said = $true; [Console]::Out.WriteLine('replacing'); [Console]::Out.Flush() } " +
            "} " +
            "[Console]::Out.WriteLine('done'); [Console]::Out.Flush()");
        start.Environment["PLANTOIR_REPLACE_TARGET"] = target;
        start.Environment["PLANTOIR_REPLACE_COUNT"] = count.ToString();
        _process = Process.Start(start)!;
        string? line = _process.StandardOutput.ReadLine();
        if (line != "replacing")
        {
            Dispose();
            throw new InvalidOperationException("the replacer did not start: " + line);
        }
        Done = _process.StandardOutput.ReadLineAsync();
    }

    public void Dispose()
    {
        try { _process.StandardInput.Close(); } catch { }
        // A bound on a broken replacer, not a wait for timing: the exit is the event.
        if (!_process.WaitForExit(120_000)) _process.Kill();
        _process.Dispose();
    }
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

            // The window's own reload makes exactly this call (WorkspaceViewModel.Reload).
            var again = Assert.Single(Workspace.DiscoverCourses(_workspace)); // still listed
            Assert.Equal(listed[0].Code, again.Code);
            Assert.True(JToken.DeepEquals(listed[0].Configuration.Values, again.Configuration.Values));

            Assert.Throws<FileInUseException>(() =>
                window.RecordOnDisk(values => { values["unit_word"] = "Topic"; return values; }, ConfigPath));
        }
        Assert.Equal(before, File.ReadAllBytes(ConfigPath));
        Assert.Empty(Temporaries());
    }

    /// <summary>
    /// The race #874 names: the merge read is refused, then the holder (a
    /// second process) lets go before the write. It lets go on the first
    /// pause after the read's four, which only a write that followed the
    /// refused read reaches; such a write would put the window's whole copy
    /// over what the build wrote. The Save must refuse instead.
    /// </summary>
    [Fact]
    public void ASaveWhoseMergeReadWasRefusedNeverWritesTheWholeCopy()
    {
        var window = CourseConfiguration.Load(ConfigPath);
        window.Values["show_reading_time"] = true;
        File.WriteAllText(ConfigPath, """{"hidden":["Media"],"show_reading_time":false,"footer_html":"from a build"}""");
        byte[] before = File.ReadAllBytes(ConfigPath);
        int pauses = 0;
        var holder = new SecondProcessHold(ConfigPath, FileShare.None);
        using (HeldFiles.PausingWith(_ => { if (++pauses == HeldFiles.Pauses.Count + 1) holder.Release(); }))
        {
            var refused = Assert.Throws<FileInUseException>(() => window.Write(ConfigPath));
            Assert.Equal(HeldFiles.InUseSentence("course_config.json"), refused.Message);
        }
        holder.Dispose();
        Assert.Equal(HeldFiles.Pauses.Count, pauses);
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
    /// H1 of review 1: the window's reload cleared its list before it handed it
    /// over as "previous", so a held course vanished on every reload. The
    /// last good read is now kept by discovery itself, so the reload's own
    /// call (<c>Workspace.DiscoverCourses(folder)</c>, nothing passed in)
    /// keeps the course, and a reference course's doors stay shut.
    /// </summary>
    [Fact]
    public void TheReloadsOwnCallKeepsAHeldCourseAndItsDoorsStayShut()
    {
        File.WriteAllText(ConfigPath, """{"course_code":"ICS3U","kept_for_reference":true,"hidden":[]}""");
        string other = Path.Combine(_workspace, "courses", "MPM2D");
        Directory.CreateDirectory(other);
        string otherConfig = Path.Combine(other, "course_config.json");
        File.WriteAllText(otherConfig, """{"hidden":[]}""");
        Assert.Equal(2, Workspace.DiscoverCourses(_workspace).Count);   // the folder's first read
        using (HeldFiles.PausingWith(_ => { }))
        using (new SecondProcessHold(ConfigPath, FileShare.None))
        using (new SecondProcessHold(otherConfig, FileShare.None))
        {
            var listed = Workspace.DiscoverCourses(_workspace);
            Assert.Equal(new[] { "ICS3U", "MPM2D" }, listed.Select(c => c.Code));
            Assert.True(listed[0].Configuration.KeptForReference);
            Assert.True(Workspace.CourseIsKeptForReference(_workspace, "ICS3U"));
            Assert.False(Workspace.CourseIsKeptForReference(_workspace, "MPM2D"));   // read before: ordinary
            Assert.Equal("ICS3U", ReferenceCourse.KeptOnDisk(CourseDir));
        }
    }

    /// <summary>A course this run has never read, held: the doors cannot tell, so they FAIL CLOSED.</summary>
    [Fact]
    public void AHeldCourseNeverReadBeforeIsTreatedAsKeptForReference()
    {
        using (HeldFiles.PausingWith(_ => { }))
        using (new SecondProcessHold(ConfigPath, FileShare.None))
        {
            Assert.True(Workspace.CourseIsKeptForReference(_workspace, "ICS3U"));
            Assert.Equal("ICS3U", ReferenceCourse.KeptOnDisk(CourseDir));
        }
        Assert.False(Workspace.CourseIsKeptForReference(_workspace, "ICS3U"));
        Assert.Null(ReferenceCourse.KeptOnDisk(CourseDir));
    }

    /// <summary>
    /// A deny-read rule (not a hold): the read is asked again for the bound
    /// (it cannot be told from a build's replace in flight), then refused in
    /// the system's words; Save writes nothing, Revert reverts nothing and
    /// says why, RecordOnDisk writes nothing.
    /// </summary>
    [Fact]
    public void AReadDeniedByARuleRefusesTheSaveAndTheRevertInTheSystemsWords()
    {
        var window = CourseConfiguration.Load(ConfigPath);
        window.Values["show_reading_time"] = true;
        byte[] before = File.ReadAllBytes(ConfigPath);
        var me = System.Security.Principal.WindowsIdentity.GetCurrent().User!;
        var deny = new System.Security.AccessControl.FileSystemAccessRule(me,
            System.Security.AccessControl.FileSystemRights.ReadData, System.Security.AccessControl.AccessControlType.Deny);
        var security = new FileInfo(ConfigPath).GetAccessControl();
        security.AddAccessRule(deny);
        new FileInfo(ConfigPath).SetAccessControl(security);
        var pauses = new List<int>();
        try
        {
            using (HeldFiles.PausingWith(pauses.Add))
            {
                var refused = Assert.Throws<FileRefusedException>(() => window.Write(ConfigPath));
                Assert.Equal("course_config.json could not be read, so it was not changed. Windows said: Access is denied.", refused.Message);
                Assert.Equal(HeldFiles.Pauses, pauses);
                Assert.False(window.RevertToFile(ConfigPath, out string? notReverted));
                Assert.Equal("course_config.json could not be read, so nothing was reverted. Windows said: Access is denied.", notReverted);
                Assert.True(window.HasUnsavedChanges);
                Assert.Throws<FileRefusedException>(() =>
                    window.RecordOnDisk(values => { values["unit_word"] = "Topic"; return values; }, ConfigPath));
            }
        }
        finally
        {
            var undo = new FileInfo(ConfigPath).GetAccessControl();
            undo.RemoveAccessRuleSpecific(deny);
            new FileInfo(ConfigPath).SetAccessControl(undo);
        }
        Assert.Equal(before, File.ReadAllBytes(ConfigPath));
        Assert.Empty(Temporaries());
    }

    /// <summary>
    /// Review 1, low 1: RecordOnDisk's SECOND read (its compare-and-swap) is
    /// refused, and the holder lets go on the first pause after that read's
    /// four, which only a write that followed the refused read reaches. The
    /// change must be refused, the file left as it was.
    /// </summary>
    [Fact]
    public void ARecordWhoseSecondReadWasRefusedWritesNothing()
    {
        var window = CourseConfiguration.Load(ConfigPath);
        byte[] before = File.ReadAllBytes(ConfigPath);
        SecondProcessHold? holder = null;
        int pauses = 0;
        using (HeldFiles.PausingWith(_ => { if (++pauses == HeldFiles.Pauses.Count + 1) holder!.Release(); }))
        {
            Assert.Throws<FileInUseException>(() => window.RecordOnDisk(values =>
            {
                holder ??= new SecondProcessHold(ConfigPath, FileShare.None);   // between the two reads
                values["unit_word"] = "Topic";
                return values;
            }, ConfigPath));
        }
        holder?.Dispose();
        Assert.Equal(HeldFiles.Pauses.Count, pauses);
        Assert.Equal(before, File.ReadAllBytes(ConfigPath));
        Assert.Empty(Temporaries());
    }

    /// <summary>Revert on a held file: the sentence the Settings window shows, and the edits kept.</summary>
    [Fact]
    public void ARevertOnAHeldFileSaysNothingWasRevertedAndWhy()
    {
        var window = CourseConfiguration.Load(ConfigPath);
        window.Values["show_reading_time"] = true;
        using (HeldFiles.PausingWith(_ => { }))
        using (new SecondProcessHold(ConfigPath, FileShare.None))
        {
            Assert.False(CourseSettingsExclusions.Revert(window, "ICS3U", ConfigPath, out string? notReverted));
            Assert.Equal("course_config.json is in use by another program, so nothing was reverted.", notReverted);
        }
        Assert.True(window.Values["show_reading_time"]!.Value<bool>());
    }

    /// <summary>
    /// The temporary is HIDDEN from the moment it is written (a leading dot
    /// hides nothing on Windows), and the file it becomes is not. Looked at on
    /// the rename's first pause, while a reader holds the target, then let go.
    /// </summary>
    [Fact]
    public void TheTemporaryIsHiddenWhileItExistsAndTheSettingsAreNot()
    {
        var window = CourseConfiguration.Load(ConfigPath);
        window.Values["show_reading_time"] = true;
        var seen = new List<FileAttributes>();
        var holder = new SecondProcessHold(ConfigPath, FileShare.Read);
        using (HeldFiles.PausingWith(_ =>
        {
            foreach (string temporary in Temporaries()) seen.Add(File.GetAttributes(temporary));
            holder.Release();
        }))
            window.Write(ConfigPath);
        holder.Dispose();
        var attributes = Assert.Single(seen);
        Assert.True(attributes.HasFlag(FileAttributes.Hidden), attributes.ToString());
        Assert.False(File.GetAttributes(ConfigPath).HasFlag(FileAttributes.Hidden));
        Assert.Empty(Temporaries());
        Assert.Empty(Workspace.DiscoverCourses(_workspace).Where(c => c.Code.StartsWith('.')));
    }

    /// <summary>
    /// #874's measured case, FOR REAL: a second process replaces
    /// course_config.json in a loop with the call a build's <c>os.replace</c>
    /// makes on Windows (<c>MoveFileExW</c> with <c>MOVEFILE_REPLACE_EXISTING</c>),
    /// each copy carrying a new <c>build_count</c>, while the app reads,
    /// lists and saves against it. The two are lined up by a handshake: the
    /// replacer says "replacing" after its first replace and "done" after its
    /// last, and the app works until it reads "done". Every read is a read or
    /// "could not read just now", never "not there" and never a raw refusal;
    /// the course is listed on every reload; and a Save that lands has merged
    /// (it keeps a build's count), never put the window's whole copy back.
    /// </summary>
    [Fact]
    public void ABuildReplacingTheSettingsInALoopNeverLosesTheCourseOrItsChange()
    {
        File.WriteAllText(ConfigPath, """{"hidden":["Media"],"show_reading_time":false,"build_count":0}""");
        byte[] windowsCopy = File.ReadAllBytes(ConfigPath);
        Assert.Single(Workspace.DiscoverCourses(_workspace));
        int pauses = 0, reads = 0, saves = 0, savesLanded = 0, rawDenied = 0, rawSharing = 0, rawOther = 0;
        var failures = new List<string>();
        using (HeldFiles.PausingWith(milliseconds => { Interlocked.Increment(ref pauses); HeldFiles.Sleep(milliseconds); }))
        using (var build = new BuildReplacingInALoop(ConfigPath, 3000))
        {
            while (!build.Done.IsCompleted)
            {
                reads++;
                // What a reader that does not ask again meets, counted for the record (#874's measurement).
                try { File.ReadAllBytes(ConfigPath); }
                catch (UnauthorizedAccessException) { rawDenied++; }
                catch (IOException error) when (HeldFiles.IsSharingViolation(error)) { rawSharing++; }
                catch (IOException) { rawOther++; }
                try
                {
                    var read = CourseConfiguration.ReadBytes(ConfigPath);
                    if (read.Outcome == HeldFiles.ReadOutcome.NotThere) failures.Add("a read answered not there");
                }
                catch (Exception error) { failures.Add("a read threw " + error.GetType().Name); }

                if (Workspace.DiscoverCourses(_workspace).Count != 1) failures.Add("the course vanished from a reload");

                var window = CourseConfiguration.FromBytes(windowsCopy);
                window.Values["show_reading_time"] = true;
                saves++;
                try
                {
                    window.Write(ConfigPath);
                    savesLanded++;
                    if (window.Values["build_count"]!.Value<int>() == 0) failures.Add("a Save put the window's whole copy over the build's");
                }
                catch (IOException) { }                    // refused: nothing written, said in the sentence
                catch (UnauthorizedAccessException) { }    // the rename refused in the system's words: nothing written
            }
            Assert.Equal("done", build.Done.Result);
        }
        string met = $"a reader that does not ask again was refused {rawDenied} times with access denied, {rawSharing} with a sharing violation, {rawOther} otherwise";
        Assert.True(failures.Count == 0, $"{failures.Count} of {reads} rounds ({met}): " + string.Join("; ", failures.Distinct()));
        Assert.True(pauses > 0, $"the replace was never met in {reads} rounds ({met}): nothing was proved");
        Assert.True(savesLanded > 0, $"no Save of {saves} landed");
    }

    /// <summary>
    /// ONE reader of course_config.json's bytes: no product file reads one
    /// with File.ReadAllBytes or File.ReadAllText except
    /// <see cref="CourseConfiguration.ReadBytes"/> (through
    /// <see cref="HeldFiles.ReadBytes"/>). Excepted by name: CourseRestorer.cs
    /// (the restore batch, #873/#805/#911).
    /// </summary>
    [Fact]
    public void EveryReaderOfTheSettingsGoesThroughTheOneReader()
    {
        string windowsApp = Path.Combine(ContractLoader.RepositoryRoot, "windows-app");
        var excepted = new HashSet<string>(StringComparer.Ordinal)
        {
            "Plantoir.Core/Models/CourseRestorer.cs",
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
