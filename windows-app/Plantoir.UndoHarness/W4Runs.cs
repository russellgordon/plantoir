using System.Diagnostics;
using System.Globalization;
using System.Text;
using Plantoir.Core.Undo;

// #899 W4: steps left in flight by a killed process in the list of a given
// STATE folder, for the real Plantoir.exe and plantoir-mcp.exe to find at
// their launch (vm-tools/reference/899-w4-plan.md, "Prove"). Every result is
// one line starting RESULT. In no solution: the unit suite never builds it.

namespace Plantoir.UndoHarness;

internal static class W4Runs
{
    private static string Exe => Environment.ProcessPath!;

    private static byte[] OldPage(int number) => Encoding.UTF8.GetBytes($"---\ntitle: Day {number}\npublish: false\n---\nThe lesson for day {number}.\n");
    private static byte[] NewPage(int number) => Encoding.UTF8.GetBytes($"---\ntitle: Day {number}\npublish: true\n---\nThe lesson for day {number}.\n");
    private static string PagePath(int number) => $"courses/TST1O/Section 1/Unit 1/Day {number}.md";

    /// <summary>The list as the app's processes find it: <c>undo\</c> under the state folder, the real liveness and reach checks.</summary>
    private static UndoJournal Journal(string stateRoot) =>
        new(Path.Combine(stateRoot, "undo"), TimeProvider.System, UndoJournalChecks.ProcessIsAlive,
            step => UndoJournalChecks.FolderIsReachable(step, TimeProvider.System), isLive: false, memory: new UndoProcessMemory());

    private static UndoStepDraft Publish(string workingFolder, int pages)
    {
        var changes = new List<UndoFileChange>();
        for (int number = 1; number <= pages; number++) changes.Add(new UndoFileChange(PagePath(number), OldPage(number), NewPage(number)));
        return new UndoStepDraft
        {
            ActionKey = "publishPages", MadeBy = "menu", WorkingFolder = workingFolder, Course = "TST1O", Section = 1, Holds = "section",
            ActionArguments = new Dictionary<string, string>(StringComparer.Ordinal) { ["pageCount"] = pages.ToString(CultureInfo.InvariantCulture) },
            Changes = changes,
        };
    }

    /// <summary>
    /// A child process makes a <paramref name="pages"/>-page step in SHADOW (as
    /// the app records today) into the list under <paramref name="stateRoot"/>,
    /// and is killed at <paramref name="point"/> (<c>afterBegin</c>, or
    /// <c>beforeSwap@mid</c>): the step is left in flight by a process that is
    /// gone, for a launch to find.
    /// </summary>
    internal static int Seed(string stateRoot, string workingFolder, string point, int pages)
    {
        Directory.CreateDirectory(Path.Combine(workingFolder, "courses", ".internal"));
        for (int number = 1; number <= pages; number++)
        {
            string path = UndoDoor.FullPath(workingFolder, PagePath(number));
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            File.WriteAllBytes(path, OldPage(number));
        }
        var start = new ProcessStartInfo(Exe) { RedirectStandardOutput = true, UseShellExecute = false };
        foreach (string arg in new[] { "child-w4", stateRoot, workingFolder, point, pages.ToString(CultureInfo.InvariantCulture) }) start.ArgumentList.Add(arg);
        using Process child = Process.Start(start)!;
        string? said = child.StandardOutput.ReadLine();
        bool stopped = said is not null && said.StartsWith("AT ", StringComparison.Ordinal);
        int pid = child.Id;
        try { child.Kill(entireProcessTree: true); } catch (InvalidOperationException) { }
        child.WaitForExit();
        Console.WriteLine($"RESULT w4-seed point={point} pages={pages} childPid={pid} stoppedAtThePoint={stopped} said={said} {Describe(stateRoot, workingFolder, pages)}");
        return stopped ? 0 : 1;
    }

    /// <summary>The child of <see cref="Seed"/>: at its point it says so and waits to be killed.</summary>
    internal static int Child(string stateRoot, string workingFolder, string point, int pages)
    {
        string at = point;
        int index = -1;
        if (at.Contains('@'))
        {
            index = at.EndsWith("@mid", StringComparison.Ordinal) ? pages / 2 : int.Parse(at[(at.IndexOf('@') + 1)..], CultureInfo.InvariantCulture);
            at = at[..at.IndexOf('@')];
        }
        var seams = new UndoSeams
        {
            StopsHere = (name, where) =>
            {
                if (name != at || (index >= 0 && where != index)) return false;
                Console.WriteLine($"AT {name} {where}");
                Console.Out.Flush();
                Thread.Sleep(Timeout.Infinite);
                return true;
            },
        };
        UndoOutcome outcome = new UndoDoor(Journal(stateRoot), UndoMode.Shadow, seams: seams).Perform(Publish(workingFolder, pages));
        Console.WriteLine("DONE " + outcome.Word);
        return 0;
    }

    /// <summary>What the list under <paramref name="stateRoot"/> and the pages of <paramref name="workingFolder"/> say now.</summary>
    internal static int Read(string stateRoot, string workingFolder, int pages)
    {
        Console.WriteLine("RESULT w4-read " + Describe(stateRoot, workingFolder, pages));
        return 0;
    }

    private static string Describe(string stateRoot, string workingFolder, int pages)
    {
        int old = 0, made = 0, torn = 0;
        for (int number = 1; number <= pages; number++)
        {
            byte[]? now = null;
            try { now = File.ReadAllBytes(UndoDoor.FullPath(workingFolder, PagePath(number))); } catch (IOException) { }
            if (now is not null && now.AsSpan().SequenceEqual(OldPage(number))) old++;
            else if (now is not null && now.AsSpan().SequenceEqual(NewPage(number))) made++;
            else torn++;
        }
        int staged = Directory.Exists(workingFolder)
            ? Directory.EnumerateFiles(workingFolder, "*", SearchOption.AllDirectories).Count(file => Path.GetFileName(file).Contains(UndoSwap.StagedMarker, StringComparison.Ordinal))
            : 0;
        string listFolder = Path.Combine(stateRoot, "undo");
        if (!Directory.Exists(listFolder)) return $"list=none oldPages={old} newPages={made} tornPages={torn} staged={staged}";
        UndoReading reading = Journal(stateRoot).Read();
        var states = new List<string>();
        int inFlight = 0;
        foreach (UndoFoldedStep step in reading.Folded.Steps.Values)
        {
            states.Add($"{step.Seq}={step.State}");
            if (step.IsInFlight) inFlight++;
        }
        int lines = 0;
        foreach (string segment in Directory.EnumerateFiles(listFolder, "journal-*.jsonl"))
            lines += File.ReadAllBytes(segment).Count(value => value == (byte)'\n');
        return $"list={listFolder} lines={lines} steps={string.Join(",", states)} inFlight={inFlight} fresh={reading.IsFresh} oldPages={old} newPages={made} tornPages={torn} staged={staged}";
    }
}
