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
}
