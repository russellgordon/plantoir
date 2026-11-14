using System.Diagnostics;
using System.Text.Json.Nodes;
using Plantoir.Core.Models;

namespace Plantoir.Tests;

/// <summary>
/// #231 (mac #220, #232): quitting asks before leaving a publish or a preview
/// build unfinished, never for a preview merely open, never while Windows is
/// ending the session; and the quit path's release, though it runs only
/// without a native runtime, refuses to stop anything it cannot prove idle.
/// </summary>
[Collection(SharedActivityState.Name)]
public class QuitConfirmationTests
{
    [Fact]
    public void EveryQuitCaseIsDecidedAsTheContractSays()
    {
        var block = ContractLoader.LoadJson("shared-rules.json")["quittingWhileWorkIsUnderWay"]!;
        // Adopted here (#231): the block names no platform any more.
        Assert.Null(block["appliesOn"]);

        var cases = block["cases"]!.AsArray();
        Assert.True(cases.Count >= 9, $"only {cases.Count} cases");

        // A case naming a set-up of an outside assistant (#855) is held by
        // name against #903 until this app can be setting one up. The hold
        // covers that one key: a held case must name a set-up, and must still
        // be decided DIFFERENTLY here, so the day it is decided as the
        // contract says, the entry fails as closed. Every other case is
        // asserted exactly, and their count is pinned below.
        NamedGapLedger.StillNamed(NamedGapLedger.QuitCases, cases.Select(c => c!["name"]!.ToString()));
        int exact = 0, held = 0;
        foreach (var c in cases)
        {
            var given = c!["given"]!;
            var underWay = new QuitConfirmation.UnderWay(
                given["publishesUnderWay"]!.GetValue<int>(),
                given["previewsOpen"]!.GetValue<int>(),
                given["previewsBeingBuilt"]!.GetValue<int>(),
                given["copiesBeingSaved"]?.GetValue<int>() ?? 0);
            var reason = given["quitReason"]!.ToString() switch
            {
                "theTeacherAskedToQuit" => QuitConfirmation.Reason.TheTeacherAskedToQuit,
                "theMacIsLoggingOutOrShuttingDown" => QuitConfirmation.Reason.TheSystemIsEnding,
                var other => throw new InvalidOperationException($"unknown quitReason {other}"),
            };
            bool decidedAsTheContract = c["expectAsk"]!.GetValue<bool>() == QuitConfirmation.ShouldAsk(underWay, reason);
            if (NamedGapLedger.Holding(NamedGapLedger.QuitCases, c["name"]!.ToString()) is { } entry)
            {
                Assert.True((given["assistantsBeingSetUp"]?.GetValue<int>() ?? 0) > 0,
                    $"NamedGapLedger holds \"{c["name"]}\" under {NamedGapLedger.QuitCases}, but it names no set-up: only a set-up of an outside assistant may be held there");
                Assert.False(decidedAsTheContract, NamedGapLedger.ClosedMessage(entry));
                held++;
                continue;
            }
            Assert.True(decidedAsTheContract, $"\"{c["name"]}\"");
            exact++;
        }
        Assert.Equal(NamedGapLedger.All.Count(e => e.Area == NamedGapLedger.QuitCases), held);
        // 13 cases since #855, one held: at least twelve are asserted exactly.
        Assert.True(exact >= 12, $"only {exact} quit cases were asserted exactly");
    }

    [Fact]
    public void KeepWorkingIsTheDefaultAndAPublishIsNamedFirst()
    {
        var buttons = ContractLoader.LoadJson("shared-rules.json")["quittingWhileWorkIsUnderWay"]!["buttons"]!;
        Assert.Equal("keepWorking", buttons["default"]!.ToString());
        var both = new QuitConfirmation.UnderWay(1, 0, 1, 0);
        Assert.Equal("a deploy", QuitConfirmation.WhatIsUnderWay(both));
        Assert.Contains("could leave it unfinished", QuitConfirmation.Question(both).Message);
        Assert.Contains("Nothing on the class website changes",
            QuitConfirmation.Question(new QuitConfirmation.UnderWay(0, 0, 1, 0)).Message);
        Assert.Contains(QuitConfirmation.KeepWorking, QuitConfirmation.TrailLine(both, quitAnyway: false));
    }

    [Fact]
    public void TheAppsOwnRecordsCountPublishesAndPreviewBuildsNotOpenPreviews()
    {
        CourseActivity.Reset();
        try
        {
            using (CourseActivity.BeginPreviewBuild(@"C:\wf", "ICS3U", 1))
            using (CourseActivity.BeginPublish(@"C:\wf", "ICS3U", 2))
            {
                var underWay = CourseActivity.UnderWay();
                Assert.Equal(1, underWay.Publishes);
                Assert.Equal(1, underWay.PreviewsBeingBuilt);
            }
            Assert.Equal(new QuitConfirmation.UnderWay(0, 0, 0, 0), CourseActivity.UnderWay());
        }
        finally { CourseActivity.Reset(); }
    }

    // ---- The release, hardened (dead while a native runtime is present) ------

    [Fact]
    public void TheReleaseAsksDockerToAnswerAndRefusesWhileALauncherRuns()
    {
        var recorded = new List<string[]>();
        FolderContainers.CommandRunnerOverride = recorded.Add;
        try
        {
            FolderContainers.ReleaseEverythingAtQuit(new[] { @"C:\Windows" });
            if (recorded.Count == 0) return;   // a native runtime beside the tests: nothing to release
            string[] command = Assert.Single(recorded);
            string joined = string.Join(" ", command);
            // Programs by their System32 path, never by name.
            Assert.Equal(FolderContainers.PowerShell, command[0]);
            Assert.Contains(FolderContainers.Wsl, joined);
            // An emptiness check that must ANSWER to count as idle.
            Assert.Contains("rc -eq 0", joined);
            Assert.Contains("$LASTEXITCODE -eq 0", joined);
            // Nothing stopped while a launcher for the folder runs.
            Assert.Contains("Get-CimInstance Win32_Process", joined);
        }
        finally { FolderContainers.CommandRunnerOverride = null; }
    }

    /// <summary>
    /// The launcher check, asked of Windows' real process list: a powershell
    /// running this folder's preview.ps1 counts, the same folder's --stop run
    /// does not, and a folder whose name holds wildcard and regex characters
    /// is matched literally.
    /// </summary>
    [Fact]
    public void ALauncherForTheFolderIsSeenAndItsOwnStopIsNot()
    {
        if (!OperatingSystem.IsWindows()) return;
        string folder = Path.Combine(Path.GetTempPath(), "C++ 26(27) [quit]" + Guid.NewGuid().ToString("N")[..6]);
        Directory.CreateDirectory(folder);
        string script = Path.Combine(folder, "preview.ps1");
        File.WriteAllText(script, "Start-Sleep -Seconds 60");
        Process? building = null, stopping = null;
        try
        {
            Assert.False(Ask(folder), "nothing is running yet");

            stopping = Start(script, "ICS3U", "1", "--stop");
            Assert.False(Ask(folder), "the launcher's own --stop run must not count");

            building = Start(script, "ICS3U", "1", "--build-only");
            Assert.True(Ask(folder), "a build of this folder must count");
        }
        finally
        {
            foreach (var p in new[] { building, stopping })
                try { p?.Kill(entireProcessTree: true); } catch { }
            try { Directory.Delete(folder, true); } catch { }
        }
    }

    private static Process Start(string script, params string[] arguments)
    {
        var info = new ProcessStartInfo(FolderContainers.PowerShell) { CreateNoWindow = true, UseShellExecute = false };
        foreach (string a in new[] { "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", script }.Concat(arguments))
            info.ArgumentList.Add(a);
        var process = Process.Start(info)!;
        Thread.Sleep(1500);   // for the process to appear with its command line
        return process;
    }

    private static bool Ask(string folder)
    {
        var info = new ProcessStartInfo(FolderContainers.PowerShell)
        {
            CreateNoWindow = true, UseShellExecute = false, RedirectStandardOutput = true,
        };
        foreach (string a in new[] { "-NoProfile", "-Command", "if (" + FolderContainers.LauncherRunningFor(folder) + ") { 'BUSY' } else { 'FREE' }" })
            info.ArgumentList.Add(a);
        using var process = Process.Start(info)!;
        string said = process.StandardOutput.ReadToEnd().Trim();
        process.WaitForExit();
        return said == "BUSY";
    }
}
