using System.Text;
using System.Text.RegularExpressions;
using Plantoir.Core.Assist;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// #700: the installer looks for work still running from its own folder
/// BEFORE it changes a file — a preview's server is ended, a build or a deploy
/// is waited for, and a silent install refuses (exit code 7, nothing changed)
/// when the wait runs out. The Pascal lives in
/// <c>windows-app/installer-running-work.iss</c>, which <c>installer.iss</c>
/// includes and calls from <c>PrepareToInstall</c> and again at
/// <c>ssInstall</c>.
/// </summary>
/// <remarks>
/// These read SOURCE TEXT, with comments taken out first, so a call that is
/// commented out or deleted goes red. They cannot see what the Pascal DOES:
/// that is <c>windows-app/installer-tests/run-harness.ps1</c>, which compiles
/// the same include into a harness installer with its own AppId and drives
/// it through every case, and is not run by <c>dotnet test</c> (it installs a
/// program, runs for minutes, and two copies would collide on its folder) —
/// <c>RELEASING.md</c> runs it at every Windows cut.
/// <c>documentation/12-windows-app.md</c> → "The installer waits for work that
/// is still running (#700)".
/// </remarks>
public sealed class InstallerRunningWorkTests
{
    private static string WindowsApp => Path.Combine(ContractLoader.RepositoryRoot, "windows-app");

    // MARK: - Reading Inno Setup source without its comments

    /// <summary>
    /// The script with every comment taken out: outside <c>[Code]</c> a line
    /// starting <c>;</c>; inside it <c>//</c> to the end of the line,
    /// <c>{ }</c> and <c>(* *)</c> — but never inside a Pascal string, where
    /// <c>'{app}'</c> is a constant, not a comment.
    /// </summary>
    internal static string WithoutComments(string script, bool startsInCode = false)
    {
        var output = new StringBuilder();
        bool inCode = startsInCode;
        string? open = null;   // the close of a { } or (* *) comment still open from an earlier line
        foreach (string line in script.Replace("\r\n", "\n").Split('\n'))
        {
            string trimmed = line.Trim();
            if (open is null && Regex.IsMatch(trimmed, @"^\[[A-Za-z]+\]$"))
            {
                inCode = trimmed.Equals("[Code]", StringComparison.OrdinalIgnoreCase);
                output.Append(line).Append('\n');
                continue;
            }
            if (!inCode)
            {
                if (!trimmed.StartsWith(';')) output.Append(line).Append('\n');
                continue;
            }
            output.Append(StripPascalLine(line, ref open)).Append('\n');
        }
        return output.ToString().TrimEnd('\n') + "\n";
    }

    private static string StripPascalLine(string line, ref string? open)
    {
        var kept = new StringBuilder();
        int i = 0;
        while (i < line.Length)
        {
            if (open is not null)
            {
                int close = line.IndexOf(open, i, StringComparison.Ordinal);
                if (close < 0) return kept.ToString();
                i = close + open.Length;
                open = null;
                continue;
            }
            char c = line[i];
            if (c == '\'')
            {
                // A Pascal string, to its closing quote ('' is a quote inside it).
                int j = i + 1;
                while (j < line.Length && line[j] != '\'') j++;
                kept.Append(line, i, Math.Min(j + 1, line.Length) - i);
                i = j + 1;
                continue;
            }
            if (c == '/' && i + 1 < line.Length && line[i + 1] == '/') break;
            if (c == '{') { open = "}"; i++; continue; }
            if (c == '(' && i + 1 < line.Length && line[i + 1] == '*') { open = "*)"; i += 2; continue; }
            kept.Append(c);
            i++;
        }
        return kept.ToString();
    }
    private static string Installer => WithoutComments(File.ReadAllText(Path.Combine(WindowsApp, "installer.iss")));
    private static string Include => WithoutComments(File.ReadAllText(Path.Combine(WindowsApp, "installer-running-work.iss")), startsInCode: true);

    private static string Body(string code, string header)
    {
        int start = code.IndexOf(header, StringComparison.Ordinal);
        Assert.True(start >= 0, $"no `{header}` outside comments");
        // To the `end;` that closes the routine: the first one at the start of a line.
        var end = Regex.Match(code[start..], @"(?m)^end;");
        Assert.True(end.Success, $"`{header}` has no closing end;");
        return code.Substring(start, end.Index + end.Length);
    }

    [Fact]
    public void TheStripperKeepsPascalStringsAndDropsComments()
    {
        string code = "[Code]\n// gone\nx := '{app}'; { gone } y := 1; (* gone *)\n  // Result := 'gone';\nz := 'a//b';\n";
        string stripped = WithoutComments(code);
        Assert.Contains("x := '{app}';", stripped);
        Assert.Contains("y := 1;", stripped);
        Assert.Contains("z := 'a//b';", stripped);
        Assert.DoesNotContain("gone", stripped);
        Assert.Equal("[Setup]\nA=1\n", WithoutComments("[Setup]\n; gone\nA=1"));
    }

    // MARK: - installer.iss calls the check before any file changes

    [Fact]
    public void TheInstallerIncludesTheCheck()
    {
        Assert.Matches(new Regex(@"(?m)^#include ""installer-running-work\.iss""\r?$"), Installer);
        // Inside [Code], where Pascal is.
        Assert.True(Installer.IndexOf("#include \"installer-running-work.iss\"", StringComparison.Ordinal) >
                    Installer.IndexOf("[Code]", StringComparison.Ordinal));
    }

    [Fact]
    public void PrepareToInstallReturnsTheChecksRefusal()
    {
        string body = Body(Installer, "function PrepareToInstall(var NeedsRestart: Boolean): String;");
        Assert.Contains("Result := RunningWorkBeforeChangingFiles(IsUpdate, WantsRelaunch);", body);
    }

    [Fact]
    public void SsInstallLooksAgainBeforeAnythingElse()
    {
        string body = Body(Installer, "procedure CurStepChanged(CurStep: TSetupStep);");
        int install = body.IndexOf("if CurStep = ssInstall then", StringComparison.Ordinal);
        int check = body.IndexOf("if RunningWorkBeforeChangingFiles(IsUpdate, WantsRelaunch) <> '' then", StringComparison.Ordinal);
        int abort = body.IndexOf("Abort;", StringComparison.Ordinal);
        int marker = body.IndexOf("DeleteFile(UpdatedByItselfMarker)", StringComparison.Ordinal);
        Assert.True(install >= 0 && check > install && abort > check && marker > abort,
            "ssInstall must look for running work again, and Abort on a refusal, before it does anything else");
    }

    [Fact]
    public void AnUpgradeEmptiesTheScriptsBytecodeFolder()
    {
        Assert.Matches(new Regex(@"(?m)^Type: filesandordirs; Name: ""\{app\}\\Toolchain\\scripts\\__pycache__""\r?$"), InstallDeleteSection(Installer));
    }

    private static string InstallDeleteSection(string script)
    {
        var header = Regex.Match(script, @"(?m)^\[InstallDelete\]\r?$");
        Assert.True(header.Success, "no [InstallDelete] section");
        int start = header.Index + header.Length;
        var next = Regex.Match(script[start..], @"(?m)^\[");
        return script[start..(next.Success ? start + next.Index : script.Length)];
    }

    [Fact]
    public void TheHarnessDeletesWhatTheInstallerDeletes()
    {
        static string Lines(string section) =>
            string.Join("\n", section.Split('\n').Select(l => l.Trim()).Where(l => l.StartsWith("Type:", StringComparison.Ordinal)));
        string harness = WithoutComments(File.ReadAllText(Path.Combine(WindowsApp, "installer-tests", "harness.iss")));
        Assert.Equal(Lines(InstallDeleteSection(Installer)), Lines(InstallDeleteSection(harness)));
        // And the harness calls the include the way installer.iss does.
        Assert.Contains("#include RunningWorkInclude", harness);
        Assert.Contains("Result := RunningWorkBeforeChangingFiles(IsUpdate, WantsRelaunch);", Body(harness, "function PrepareToInstall(var NeedsRestart: Boolean): String;"));
        Assert.Matches(new Regex(@"AppId=\{\{D7A92D73-E5AF-4D50-978A-D127394C485D\}"), harness);   // never Plantoir's
    }

    // MARK: - The include's rules

    [Fact]
    public void APreviewServerIsNodeRunningQuartzWithTheServeToken()
    {
        string body = Body(Include, "function RwIsPreviewServer(const Path, CommandLine: String): Boolean;");
        Assert.Contains("(Lowercase(ExtractFileName(Path)) = 'node.exe')", body);
        Assert.Contains("(Pos('bootstrap-cli.mjs', Lowercase(CommandLine)) > 0)", body);
        Assert.Contains("RwHasToken(CommandLine, '--serve')", body);
        // The same separator as the launcher's own stop (a whole token).
        Assert.Contains("$token -ceq '--serve'", File.ReadAllText(Path.Combine(ContractLoader.RepositoryRoot, "preview.ps1")));
    }

    [Fact]
    public void WorkIsWaitedForAndAPreviewIsEnded()
    {
        string body = Body(Include, "function RunningWorkRefusal(const AppDir: String; Updating, Silent: Boolean): String;");
        Assert.Contains("else if RwIsPreviewServer(RwPaths[I], Line) then", body);
        // Ended only in the preview, engine and already-tried branches: one RwEnd for each of the first two.
        Assert.Equal(2, Regex.Matches(body, @"RwEnd\(").Count);
        Assert.Contains("if Elapsed >= RwWaitSeconds then", body);
        Assert.Contains("Result := RwRefusedForWork;", body);
        Assert.Contains("SuppressibleMsgBox(RwStillWorkingRetry, mbError, MB_RETRYCANCEL, IDCANCEL)", body);
        Assert.Contains("Sleep(1000);", body);   // and looks again
        Assert.Matches(new Regex(@"#define RunningWorkWaitSeconds 600\b"), File.ReadAllText(Path.Combine(WindowsApp, "installer-running-work.iss")));
    }

    [Fact]
    public void TheReopenedAppIsToldWhyInWordsItKnows()
    {
        Assert.Contains($"RwNotInstalledForWorkArgument = '{AppUpdates.UpdateNotInstalledForWorkArgument}';", Include);
        string reopen = Body(Include, "procedure RunningWorkReopenAfterRefusal(const Refusal: String; Relaunch: Boolean; const ReturnTo: String);");
        Assert.Contains($"Exec(ReturnTo, '{AppUpdates.UpdateNotInstalledArgument}'", reopen);
        Assert.Contains("else if Relaunch then", reopen);
    }

    [Fact]
    public void WhatATeacherReadsNamesNoMachinery()
    {
        string source = File.ReadAllText(Path.Combine(WindowsApp, "installer-running-work.iss"));
        int start = source.IndexOf("  RwStillWorkingRetry =", StringComparison.Ordinal);
        int end = source.IndexOf("  // What the reopened app is told", StringComparison.Ordinal);
        Assert.True(start > 0 && end > start);
        var sentences = Regex.Matches(source[start..end], @"'([^']*)'").Select(m => m.Groups[1].Value).ToList();
        Assert.True(sentences.Count >= 4);
        string[] banned = { "toolchain", "script", "docker", "container", "runtime", "process", "node", "python", "wrangler", "lease", "task", "scheduler" };
        foreach (string sentence in sentences)
            foreach (string word in banned)
                Assert.False(sentence.Contains(word, StringComparison.OrdinalIgnoreCase), $"\"{sentence}\" says \"{word}\"");
    }

    [Fact]
    public void ARefusalForWorkIsSaidAsSuch()
    {
        string? line = AppUpdates.NotInstalledLine(new[] { "Plantoir.exe", AppUpdates.UpdateNotInstalledForWorkArgument });
        Assert.NotNull(line);
        Assert.Contains("built or deployed", line);
        Assert.Contains("offered again", line);
        Assert.DoesNotContain(UpdateWording.AssistantElsewhereWork, line);
        // The assistant's refusal keeps its own words.
        Assert.Contains(UpdateWording.AssistantElsewhereWork, AppUpdates.NotInstalledLine(new[] { "Plantoir.exe", AppUpdates.UpdateNotInstalledArgument })!);
    }

    // MARK: - #700 review: a refusal leaves a record, a copy is marked

    [Fact]
    public void EveryRefusalWritesItsMarker()
    {
        string body = Body(Include, "function RunningWorkBeforeChangingFiles(Updating, Relaunch: Boolean): String;");
        int refused = body.IndexOf("if Result <> '' then", StringComparison.Ordinal);
        int marker = body.IndexOf("RunningWorkWriteRefusalMarker(RwReasonOf(Result));", StringComparison.Ordinal);
        int updating = body.IndexOf("if Updating then", StringComparison.Ordinal);
        Assert.True(refused >= 0 && marker > refused && updating > marker, "the marker is written for EVERY refusal, hand-run included, before the update-only reopen");
        Assert.Contains("RunningWorkWriteRefusalMarker('assistant');", Body(Installer, "function InitializeSetup: Boolean;"));
        Assert.Contains($"RwNotInstalledMarker = '{AppUpdates.NotInstalledMarker}';", Include);
        Assert.Contains($"RwInstallingMarkerPrefix = '{AppUpdates.InstallingMarkerPrefix}';", Include);
        Assert.Contains("Result := ExpandConstant('{param:STATEDIR|}');", Body(Include, "function RunningWorkStateFolder: String;"));
    }

    [Fact]
    public void TheInstallingMarkerSpansOnlyTheCopy()
    {
        string steps = Body(Installer, "procedure CurStepChanged(CurStep: TSetupStep);");
        int abort = steps.IndexOf("Abort;", StringComparison.Ordinal);
        int begins = steps.IndexOf("RunningWorkInstallingBegins;", StringComparison.Ordinal);
        int post = steps.IndexOf("if CurStep = ssPostInstall then", StringComparison.Ordinal);
        int ends = steps.IndexOf("RunningWorkInstallingEnds;", StringComparison.Ordinal);
        Assert.True(abort >= 0 && begins > abort && post > begins && ends > post, "written after the last look, removed at ssPostInstall");
        Assert.Contains("RunningWorkInstalledCleanly;", steps[post..]);
        Assert.Contains("RunningWorkInstallingEnds;", Body(Installer, "procedure DeinitializeSetup;"));
    }

    [Fact]
    public void APlantoirOpenedDuringTheWaitRefusesAtOnceAndNoSecondCopyIsStarted()
    {
        string wait = Body(Include, "function RunningWorkRefusal(const AppDir: String; Updating, Silent: Boolean): String;");
        Assert.Contains("(not RwIn(RwPlantoirAtStart, RwPids[I])) then", wait);
        Assert.Contains("Result := RwRefusedReopened;", wait);
        string reopen = Body(Include, "procedure RunningWorkReopenAfterRefusal(const Refusal: String; Relaunch: Boolean; const ReturnTo: String);");
        Assert.Contains("if (ReturnTo = '') or (Refusal = RwRefusedReopened) then Exit;", reopen);
        Assert.Contains("if RwPlantoirIsOpen then", reopen);
    }

    [Fact]
    public void AFullListOfProcessesIsAskedAgainWithMoreRoom()
    {
        string look = Body(Include, "function RwLookUnder(const AppDir: String): Boolean;");
        Assert.Contains("if Needed < 4 * Room then Break;", look);
        Assert.Contains("Room := Room * 2;", look);
        Assert.Contains("if Room >= 131072 then Exit;", look);
    }

    [Fact]
    public void TheLogNamesNoCommandLine()
    {
        string wait = Body(Include, "function RunningWorkRefusal(const AppDir: String; Updating, Silent: Boolean): String;");
        foreach (Match log in Regex.Matches(wait, @"Log\((.*)\);"))
            Assert.DoesNotContain("Line", log.Groups[1].Value);
    }

    private static string TempFolder()
    {
        string folder = Path.Combine(Path.GetTempPath(), "plantoir-700-" + Guid.NewGuid().ToString("N")[..8]);
        Directory.CreateDirectory(folder);
        return folder;
    }

    [Fact]
    public void ARefusalMarkerIsSaidOnceWithTheVersionThatWaited()
    {
        string folder = TempFolder();
        try
        {
            string marker = Path.Combine(folder, AppUpdates.NotInstalledMarker);
            var running = new Version(1, 9, 0);
            File.WriteAllText(marker, "1.9.3\r\nwork\r\n");
            string? line = AppUpdates.ConsumeNotInstalledMarker(folder, running, DateTime.UtcNow);
            Assert.Equal("the new version was not installed: a course was still being built or deployed when it came to install; it will be offered again (1.9.3 waiting)", line);
            // The PARSED version, spelt as the trail spells versions, never the raw line.
            File.WriteAllText(marker, " 1.9.3.0 \nwork\n");
            Assert.EndsWith("(1.9.3 waiting)", AppUpdates.ConsumeNotInstalledMarker(folder, running, DateTime.UtcNow)!);
            Assert.False(File.Exists(marker));
            Assert.Null(AppUpdates.ConsumeNotInstalledMarker(folder, running, DateTime.UtcNow));   // once only

            File.WriteAllText(marker, "1.9.3\nassistant\n");
            Assert.Contains(UpdateWording.AssistantElsewhereWork, AppUpdates.ConsumeNotInstalledMarker(folder, running, DateTime.UtcNow)!);
            File.WriteAllText(marker, "1.9.3\nreopened\n");
            Assert.Contains("opened again", AppUpdates.ConsumeNotInstalledMarker(folder, running, DateTime.UtcNow)!);

            // The version already installed (the update went in later): no line, and gone.
            File.WriteAllText(marker, "1.9.3\nwork\n");
            Assert.Null(AppUpdates.ConsumeNotInstalledMarker(folder, new Version(1, 9, 3, 0), DateTime.UtcNow));
            Assert.False(File.Exists(marker));
            // Too old to explain anything now.
            File.WriteAllText(marker, "1.9.3\nwork\n");
            Assert.Null(AppUpdates.ConsumeNotInstalledMarker(folder, running, DateTime.UtcNow + AppUpdates.NotInstalledMarkerLongestAge + TimeSpan.FromHours(1)));
            Assert.False(File.Exists(marker));
            // Unreadable.
            File.WriteAllText(marker, "garbage");
            Assert.Null(AppUpdates.ConsumeNotInstalledMarker(folder, running, DateTime.UtcNow));
            Assert.False(File.Exists(marker));
        }
        finally { Directory.Delete(folder, recursive: true); }
    }

    [Fact]
    public void TheAppReadsTheMarkerBeforeTheArgument()
    {
        string app = File.ReadAllText(Path.Combine(WindowsApp, "Plantoir", "App.xaml.cs"));
        Assert.Contains("AppUpdates.ConsumeNotInstalledMarker(AppDataRoot.Current, runningNow, DateTime.UtcNow)\n", app.Replace("\r\n", "\n"));
        Assert.Matches(new Regex(@"ConsumeNotInstalledMarker\([^;]*\)\s*\?\?\s*Plantoir\.Core\.Assist\.AppUpdates\.NotInstalledLine"), app);
    }

    [Fact]
    public void AnInstallingMarkerCountsOnlyWhileItsInstallerLives()
    {
        string folder = TempFolder();
        try
        {
            string live = Path.Combine(folder, AppUpdates.InstallingMarkerPrefix + "111");
            File.WriteAllText(live, "111\nPlantoirSetup\n");
            DateTime written = File.GetLastWriteTimeUtc(live);
            Assert.Equal(111, AppUpdates.LiveInstaller(folder, pid => pid == 111 ? written.AddMinutes(-1) : null));
            Assert.True(File.Exists(live));
            // The pid now belongs to a process started after the marker: stale, deleted.
            Assert.Null(AppUpdates.LiveInstaller(folder, pid => written.AddMinutes(5)));
            Assert.False(File.Exists(live));
            // The process is gone: stale, deleted.
            File.WriteAllText(live, "111\nPlantoirSetup\n");
            Assert.Null(AppUpdates.LiveInstaller(folder, _ => null));
            Assert.False(File.Exists(live));
            // The review's case: a pid that cannot be read (access denied: a
            // SYSTEM process took it) is NOT the teacher's installer.
            File.WriteAllText(live, "111\nPlantoirSetup\n");
            Assert.Null(AppUpdates.LiveInstaller(folder, _ => throw new UnauthorizedAccessException()));
            Assert.False(File.Exists(live));
            File.WriteAllText(live, "111\nPlantoirSetup\n");
            Assert.Null(AppUpdates.LiveInstaller(folder, _ => DateTime.MinValue));
            Assert.False(File.Exists(live));
            // Older than an hour: stale, whatever its process says.
            File.WriteAllText(live, "111\nPlantoirSetup\n");
            DateTime w2 = File.GetLastWriteTimeUtc(live);
            Assert.Null(AppUpdates.LiveInstaller(folder, _ => w2.AddMinutes(-1), w2 + AppUpdates.InstallingMarkerLongestAge + TimeSpan.FromMinutes(1)));
            Assert.False(File.Exists(live));
            File.WriteAllText(live, "111\nPlantoirSetup\n");
            DateTime w3 = File.GetLastWriteTimeUtc(live);
            Assert.Equal(111, AppUpdates.LiveInstaller(folder, _ => w3.AddMinutes(-1), w3 + TimeSpan.FromMinutes(5)));
            File.Delete(live);
            // This process, for real: live.
            string mine = Path.Combine(folder, AppUpdates.InstallingMarkerPrefix + Environment.ProcessId);
            File.WriteAllText(mine, "x");
            Assert.Equal(Environment.ProcessId, AppUpdates.LiveInstaller(folder));
        }
        finally { Directory.Delete(folder, recursive: true); }
    }

    [Fact]
    public void TheAppHandsTheInstallerALogAndKeepsTwo()
    {
        string args = AppUpdates.InstallerArguments(false, @"C:\P\Plantoir.exe", @"C:\L\installer-1.log", @"C:\S");
        Assert.Contains("\"/LOG=C:\\L\\installer-1.log\"", args);
        Assert.Contains("\"/STATEDIR=C:\\S\"", args);
        Assert.DoesNotContain("/LOG", AppUpdates.InstallerArguments(false));
        Assert.DoesNotContain("/STATEDIR", AppUpdates.InstallerArguments(false));

        string folder = TempFolder();
        try
        {
            for (int i = 0; i < 4; i++)
            {
                string path = Path.Combine(folder, $"installer-2026111{i}-000000.log");
                File.WriteAllText(path, "x");
                File.SetLastWriteTimeUtc(path, new DateTime(2026, 11, 10 + i, 0, 0, 0, DateTimeKind.Utc));
            }
            File.WriteAllText(Path.Combine(folder, "activity.txt"), "kept");
            string next = AppUpdates.NextInstallerLog(folder, new DateTime(2026, 11, 20, 1, 2, 3, DateTimeKind.Utc));
            Assert.Equal(Path.Combine(folder, "installer-20261120-010203.log"), next);
            Assert.Equal(new[] { "installer-20261113-000000.log" }, Directory.GetFiles(folder, "installer-*.log").Select(Path.GetFileName).ToArray());
            Assert.True(File.Exists(Path.Combine(folder, "activity.txt")));
        }
        finally { Directory.Delete(folder, recursive: true); }
        Assert.Contains("Updater.InstallerLog = () => Plantoir.Core.Assist.AppUpdates.NextInstallerLog(",
                        File.ReadAllText(Path.Combine(WindowsApp, "Plantoir", "App.xaml.cs")));
    }

    // MARK: - The assistant's engine in the bundle (#700 review: 1.9.0 shipped without llama\)

    /// <summary>A PowerShell script without its comments: &lt;# #&gt; blocks and lines starting #.</summary>
    internal static string PowerShellWithoutComments(string script)
    {
        string text = Regex.Replace(script.Replace("\r\n", "\n"), @"<#.*?#>", "", RegexOptions.Singleline);
        return string.Join("\n", text.Split('\n').Where(line => !line.TrimStart().StartsWith('#')));
    }

    private static string Publish => PowerShellWithoutComments(File.ReadAllText(Path.Combine(WindowsApp, "publish.ps1")));

    [Fact]
    public void PublishRefusesABundleWithoutTheAssistantsEngine()
    {
        string publish = Publish;
        Assert.Contains("$AssistantEngineFiles = @('llama-server.exe', 'llama-server-impl.dll', 'llama.dll', 'llama-common.dll', 'mtmd.dll',", publish);
        // ggml-base.dll and every CPU backend import LLVM's OpenMP runtime (#700 third review).
        Assert.Contains("'ggml.dll', 'ggml-base.dll', 'ggml-vulkan.dll', 'ggml-cpu-x64.dll', 'libomp140.x86_64.dll')", publish);
        // Before the build, from Vendor\llama, and again on the published folder.
        Assert.Contains("$missingVendor = Get-MissingAssistantEngineFiles (Join-Path $PSScriptRoot 'Vendor\\llama')", publish);
        Assert.Contains("$missingPublished = Get-MissingAssistantEngineFiles (Join-Path $publishDir 'llama')", publish);
        Assert.Matches(new Regex(@"if \(\$missingPublished\.Count -gt 0\) \{\s*throw "), publish);
        Assert.Matches(new Regex(@"if \(\$missingVendor\.Count -gt 0\) \{\s*throw "), publish);
        // The developer's way round it never comes with -Sign.
        Assert.Matches(new Regex(@"if \(\$Sign -and \$WithoutAssistantEngine\) \{\s*throw "), publish);
        // And the published check comes before the installer is compiled.
        Assert.True(publish.IndexOf("$missingPublished = ", StringComparison.Ordinal) < publish.IndexOf("& $iscc ", StringComparison.Ordinal));
    }

    [Fact]
    public void FetchLlamaRefusesAZipThatIsNotThePinnedOne()
    {
        string fetch = PowerShellWithoutComments(File.ReadAllText(Path.Combine(WindowsApp, "Vendor", "fetch-llama.ps1")));
        Assert.Contains("$ArchiveSize = 34573315", fetch);
        Assert.Contains("$ArchiveSha256 = \"8e03436cf1b52fb858fcf2985f02d8b8af07b914595777725804353391c14bc1\"", fetch);
        Assert.Matches(new Regex(@"if \(\$size -ne \$ArchiveSize\) \{\s*throw "), fetch);
        Assert.Matches(new Regex(@"if \(\$sha -ne \$ArchiveSha256\) \{\s*throw "), fetch);
        // Checked BEFORE the zip is unpacked.
        Assert.True(fetch.IndexOf("if ($sha -ne $ArchiveSha256)", StringComparison.Ordinal) < fetch.IndexOf("Expand-Archive", StringComparison.Ordinal));
    }
}