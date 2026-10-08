using System.Diagnostics;
using Plantoir.Core.Assist;
using Plantoir.Core.Models;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// Both doors hold their course (#468, mac #458): <c>shared-rules.json →
/// doorCourseHold</c> and <c>file-formats.json → heldBackupRecord</c>, read as
/// data — and the one thing Windows decides for itself, that its OWN
/// assistant window's lease keeps every hold and is only worded as the window.
/// The twin of the mac's <c>DoorCourseHoldTests.swift</c>.
/// </summary>
[Collection(SharedActivityState.Name)]
public sealed class DoorCourseHoldTests : IDisposable
{
    private readonly string _folder = Directory.CreateTempSubdirectory("door-course-hold").FullName;
    private readonly List<Process> _children = new();

    public DoorCourseHoldTests()
    {
        foreach (string code in new[] { "ICS3U", "MPM2D" })
        {
            string course = Path.Combine(_folder, "courses", code);
            Directory.CreateDirectory(Path.Combine(course, "section1"));
            File.WriteAllText(Path.Combine(course, "course_config.json"), $$"""
                {
                  "course_code": "{{code}}",
                  "course_name": "{{code}} course",
                  "section_numbers": [1],
                  "num_sections": 1,
                  "per_section_folders": ["All Classes"],
                  "per_section_files": []
                }
                """);
        }
        File.WriteAllText(Path.Combine(_folder, "preview.ps1"), "# marker");
        File.WriteAllText(Path.Combine(_folder, "deploy.ps1"), "# marker");
        WindowServers.Reset();
        HeldBackups.Reset();
    }

    public void Dispose()
    {
        WindowServers.Reset();
        HeldBackups.Reset();
        foreach (var child in _children)
        {
            try { child.Kill(entireProcessTree: true); } catch { }
            child.Dispose();
        }
        try { Directory.Delete(_folder, recursive: true); } catch { }
    }

    private static System.Text.Json.Nodes.JsonNode Contract() => ContractLoader.LoadJson("shared-rules.json")["doorCourseHold"]!;

    // ---- Which course a door's server holds -------------------------------

    /// <summary>Every <c>courseToHold</c> case, in a folder with the contract's two courses; and both doors hold.</summary>
    [Fact]
    public void TheCourseToHoldIsTheContracts()
    {
        var hold = Contract();
        Assert.True(hold["whichDoors"]!["claude"]!.GetValue<bool>());
        Assert.True(hold["whichDoors"]!["codex"]!.GetValue<bool>());
        Assert.Equal(new[] { "ICS3U", "MPM2D" }, hold["courseToHold"]!["courses"]!.AsArray().Select(c => c!.ToString()));

        var workspace = new AssistWorkspace(_folder, new FakeLauncher());
        var cases = hold["courseToHold"]!["cases"]!.AsArray();
        Assert.Equal(8, cases.Count);
        foreach (var c in cases)
            Assert.True(c!["expect"]?.ToString() == workspace.CourseToHoldForTheConversation(c["doorCourse"]?.ToString()),
                        c["name"]!.ToString());
    }

    /// <summary>The trail's line is the contract's, word for word, with the course only.</summary>
    [Fact]
    public void TheTrailLineIsTheContracts()
    {
        var entry = ContractLoader.LoadJson("shared-rules.json")["activityTrail"]!["mustRecord"]!.AsArray()
            .Single(e => e!["event"]!.ToString() == "outside session held a course")!;
        Assert.Null(entry["appliesOn"]);
        Assert.Equal(entry["line"]!.ToString(), AssistWorkspace.HoldingTrailLine("{course}"));
        Assert.Equal("outside session held a course",
                     Plantoir.Core.Scripting.ActivityTrail.KeyFor(Plantoir.Core.Scripting.ActivityTrail.Event.OutsideSessionHeldACourse));
    }

    // ---- What a hold greys, and what it says ------------------------------

    /// <summary>
    /// Every <c>reviseCases</c> case Windows runs through the pure rule; each
    /// mac-only case (the mac's lease-less, one-at-a-time window) says what
    /// Windows does instead.
    /// </summary>
    [Fact]
    public void TheReviseCasesAreTheContracts()
    {
        var wording = ContractLoader.LoadJson("assist-wording.json")["wording"]!;
        var cases = Contract()["reviseCases"]!.AsArray();
        Assert.Equal(9, cases.Count);
        int ran = 0;
        foreach (var c in cases)
        {
            string name = c!["name"]!.ToString();
            if (c["appliesOn"] is { } only)
            {
                Assert.Equal(new[] { "mac" }, only.AsArray().Select(p => p!.ToString()));
                Assert.False(string.IsNullOrWhiteSpace(c["onWindows"]?.ToString()), $"{name} says nothing of Windows");
                continue;
            }
            var item = c["item"]!.ToString() switch
            {
                "claude" => CourseActivity.ReviseItem.Claude,
                "codex" => CourseActivity.ReviseItem.Codex,
                "local" => CourseActivity.ReviseItem.Local,
                var other => throw new InvalidOperationException($"an item this app does not know: {other}"),
            };
            string? expected = c["expect"]?.ToString() is { } key ? wording[key]!.ToString() : null;
            Assert.True(expected == CourseActivity.ReviseUnavailableReason(item, c["revisedElsewhere"]!.GetValue<bool>()), name);
            ran++;
        }
        Assert.Equal(5, ran);
    }

    /// <summary>
    /// A live outside session's lease (a process that is NOT one of this app's
    /// window servers) holds the course, greys it, and is said in the
    /// contract's "Claude or Codex" words — for the Revise items, Rename,
    /// restore and Add Section — and nothing on the other course.
    /// </summary>
    [Fact]
    public void AnOutsideSessionHoldsTheCourseInTheContractsWords()
    {
        var session = LongRunningChild();
        WriteLease("ICS3U", WorkLease.Assisting, session);

        Assert.True(CourseActivity.IsAssisting(_folder, "ICS3U"));
        Assert.True(CourseActivity.IsRevisedElsewhere(_folder, "ICS3U"));
        Assert.Null(CourseActivity.WindowRevising(_folder, "ICS3U"));
        Assert.Equal(AssistWording.AvailableOnceYouFinishRevisingWithClaude, CourseActivity.BusyReason(_folder, "ICS3U"));
        Assert.Equal(AssistWording.AvailableOnceYouFinishRevisingWithClaude, CourseActivity.ReviseHoldReason(_folder, "ICS3U"));
        Assert.Equal(AssistWording.ClaudeIsRevisingTheCourseRename("ICS3U"),
                     CourseActivity.AssistHoldRefusal(_folder, "ICS3U", CourseActivity.StructuralWork.Rename));
        Assert.Equal(AssistWording.ClaudeIsRevisingTheCourseRestore("ICS3U"),
                     CourseActivity.AssistHoldRefusal(_folder, "ICS3U", CourseActivity.StructuralWork.Restore));
        Assert.Equal(AssistWording.ClaudeIsRevisingTheCourseAddSection("ICS3U"),
                     CourseActivity.AssistHoldRefusal(_folder, "ICS3U", CourseActivity.StructuralWork.AddSection));
        Assert.False(CourseActivity.IsPreviewingOrPublishing(_folder, "ICS3U"));

        Assert.False(CourseActivity.IsAssisting(_folder, "MPM2D"));
        Assert.Null(CourseActivity.BusyReason(_folder, "MPM2D"));
        Assert.Null(CourseActivity.AssistHoldRefusal(_folder, "MPM2D", CourseActivity.StructuralWork.Rename));
    }

    /// <summary>
    /// This app's OWN window's server holds the course too, and keeps EVERY
    /// hold it had (stack-2 ruling F, review H1) — only its words differ: the
    /// window, never "a Claude or Codex session". Once it is forgotten (its
    /// server gone from the registry), the same lease reads as an outside one.
    /// </summary>
    [Fact]
    public void TheWindowsOwnLeaseKeepsEveryHoldInTheWindowsWords()
    {
        var server = LongRunningChild();
        WriteLease("ICS3U", WorkLease.Assisting, server);
        var registered = WindowServers.Register(server.Id, "ICS3U", 2);

        Assert.True(CourseActivity.IsAssisting(_folder, "ICS3U"));
        Assert.False(CourseActivity.IsRevisedElsewhere(_folder, "ICS3U"));
        Assert.Equal(2, CourseActivity.WindowRevising(_folder, "ICS3U")!.SectionNumber);
        string greyed = WindowHoldWording.AvailableOnceTheAssistantCloses("ICS3U", 2);
        Assert.Equal(greyed, CourseActivity.BusyReason(_folder, "ICS3U"));
        Assert.Equal(greyed, CourseActivity.ReviseHoldReason(_folder, "ICS3U"));
        Assert.Equal(WindowHoldWording.CloseTheAssistantThenRename("ICS3U", 2),
                     CourseActivity.AssistHoldRefusal(_folder, "ICS3U", CourseActivity.StructuralWork.Rename));
        Assert.Equal(WindowHoldWording.CloseTheAssistantThenRestore("ICS3U", 2),
                     CourseActivity.AssistHoldRefusal(_folder, "ICS3U", CourseActivity.StructuralWork.Restore));
        Assert.Equal(WindowHoldWording.CloseTheAssistantThenAddSection("ICS3U", 2),
                     CourseActivity.AssistHoldRefusal(_folder, "ICS3U", CourseActivity.StructuralWork.AddSection));
        foreach (string sentence in new[] { greyed, CourseActivity.AssistHoldRefusal(_folder, "ICS3U", CourseActivity.StructuralWork.Rename)! })
            Assert.DoesNotContain("Claude", sentence);

        // An outside session on the same course as well: its words come first.
        var session = LongRunningChild();
        WriteLease("ICS3U", WorkLease.Assisting, session);
        Assert.True(CourseActivity.IsRevisedElsewhere(_folder, "ICS3U"));
        Assert.Equal(AssistWording.AvailableOnceYouFinishRevisingWithClaude, CourseActivity.ReviseHoldReason(_folder, "ICS3U"));
        File.Delete(LeasePath("ICS3U", WorkLease.Assisting, session.Id));

        registered.Dispose();
        Assert.Null(WindowServers.Find(server.Id));
        Assert.True(CourseActivity.IsRevisedElsewhere(_folder, "ICS3U"));
    }

    // ---- The record a session's backup is kept by --------------------------

    /// <summary>Every <c>heldBackupRecord.nameCases</c> case through the record-name reader.</summary>
    [Fact]
    public void TheRecordNamesAreTheContracts()
    {
        var cases = ContractLoader.LoadJson("file-formats.json")["heldBackupRecord"]!["nameCases"]!.AsArray();
        Assert.Equal(4, cases.Count);
        foreach (var c in cases)
            Assert.True(c!["expectPid"]?.GetValue<int>() == HeldBackups.PidOfRecord(c["file"]!.ToString()), c["name"]!.ToString());
        // And what the writer writes, the reader reads.
        Assert.Equal(4321, HeldBackups.PidOfRecord(Path.GetFileName(HeldBackups.RecordFor(_folder, "ICS3U", 4321))));
    }

    /// <summary>
    /// Every <c>heldBackupRecord.cases</c> case through <see cref="HeldBackups.For"/>
    /// with REAL lease files and a REAL process, so the kind and liveness half
    /// is exercised, not a stubbed list of pids.
    /// </summary>
    [Fact]
    public void TheRecordCasesAreTheContracts()
    {
        var cases = ContractLoader.LoadJson("file-formats.json")["heldBackupRecord"]!["cases"]!.AsArray();
        Assert.Equal(3, cases.Count);
        foreach (var c in cases)
        {
            string name = c!["name"]!.ToString();
            ClearActivity();
            var holder = c["holder"]!;
            var process = holder["alive"]!.GetValue<bool>() ? LongRunningChild() : ExitedChild();
            foreach (var kind in holder["leases"]!.AsArray())
                WriteLease("ICS3U", kind!.ToString(), process);
            string zip = Path.Combine(_folder, "courses", "_backups", "ICS3U", "ICS3U_backup_2026-10-07_120000_assistant-section1.zip");
            // The contract's record is named for pid 4321; the real one is this process's.
            Assert.Equal(4321, HeldBackups.PidOfRecord(c["record"]!.ToString()));
            string record = HeldBackups.RecordFor(_folder, "ICS3U", process.Id);
            Directory.CreateDirectory(Path.GetDirectoryName(record)!);
            File.WriteAllText(record, zip);

            bool held = HeldBackups.For(_folder, Array.Empty<BackupItem>()).Contains(Path.GetFullPath(zip));
            Assert.True(c["expectHeld"]!.GetValue<bool>() == held, name);
            Assert.True(held == HeldBackups.ByOtherSessions(_folder).Contains(Path.GetFullPath(zip)), name);
        }
    }

    /// <summary>
    /// The backups a Claude or Codex session holds are told apart from the
    /// window's (#468): a record by this app's own window server, and a zip
    /// this app's window holds, are held, but never "made by a session".
    /// </summary>
    [Fact]
    public void ASessionsBackupIsToldApartFromTheWindows()
    {
        var session = LongRunningChild();
        var windowServer = LongRunningChild();
        WriteLease("ICS3U", WorkLease.Assisting, session);
        WriteLease("MPM2D", WorkLease.Assisting, windowServer);
        using var registered = WindowServers.Register(windowServer.Id, "MPM2D", 1);
        string backups = Path.Combine(_folder, "courses", "_backups");
        string sessions = Path.Combine(backups, "ICS3U", "ICS3U_backup_2026-10-07_120000_assistant-section1.zip");
        string windows = Path.Combine(backups, "MPM2D", "MPM2D_backup_2026-10-07_120000_assistant-section1.zip");
        Record("ICS3U", session.Id, sessions);
        Record("MPM2D", windowServer.Id, windows);
        using var open = HeldBackups.HoldWhileOpen(windows);

        var held = HeldBackups.For(_folder, Array.Empty<BackupItem>());
        Assert.Contains(Path.GetFullPath(sessions), held);
        Assert.Contains(Path.GetFullPath(windows), held);
        var bySessions = HeldBackups.ByOtherSessions(_folder);
        Assert.Equal(new[] { Path.GetFullPath(sessions) }, bySessions);

        var a = BackupItem.From(sessions, "ICS3U")!;
        var b = BackupItem.From(windows, "MPM2D")!;
        var outcome = new BackupDeleter.Outcome(Array.Empty<BackupItem>(), new[] { a, b }, Array.Empty<BackupDeleter.Failure>());
        string line = BackupDeleter.TrailLine(outcome, new Dictionary<string, long?>(), bySessions);
        Assert.Contains("; kept because an open assistant conversation can restore from it: " + Path.GetFileName(windows), line);
        Assert.Contains("; kept " + Path.GetFileName(sessions) + ", which a Claude or Codex session still open made", line);
    }

    // ---- Helpers ------------------------------------------------------------

    private string Activity => Path.Combine(_folder, "courses", ".internal", "activity");

    private string LeasePath(string course, string kind, int pid) => Path.Combine(Activity, $"{course}.{kind}.{pid}.lease");

    private void WriteLease(string course, string kind, Process owner)
    {
        Directory.CreateDirectory(Activity);
        File.WriteAllText(LeasePath(course, kind, owner.Id), $"{owner.Id}\n{OwnerName(owner)}\n2026-10-07T00:00:00Z\n");
    }

    private void Record(string course, int pid, string zip)
    {
        string record = HeldBackups.RecordFor(_folder, course, pid);
        Directory.CreateDirectory(Path.GetDirectoryName(record)!);
        File.WriteAllText(record, zip);
    }

    private void ClearActivity()
    {
        if (Directory.Exists(Activity)) Directory.Delete(Activity, recursive: true);
    }

    /// <summary>The name a lease records: a live process's own, and "cmd" for one that has exited (it will not say any more).</summary>
    private static string OwnerName(Process owner)
    {
        try { return owner.ProcessName; } catch (InvalidOperationException) { return "cmd"; }
    }

    private Process LongRunningChild()
    {
        var child = Process.Start(new ProcessStartInfo("cmd.exe", "/c pause")
            { CreateNoWindow = true, UseShellExecute = false, RedirectStandardInput = true })!;
        _children.Add(child);
        return child;
    }

    private static Process ExitedChild()
    {
        var child = Process.Start(new ProcessStartInfo("cmd.exe", "/c exit") { CreateNoWindow = true, UseShellExecute = false })!;
        child.WaitForExit();
        return child;
    }
}
