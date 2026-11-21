using System.Diagnostics;
using System.Globalization;
using System.Text;
using Plantoir.Core.Undo;

// #899 W7a, D: a publish of several pages made through the action's step
// (UndoActionStep, the mac's JournaledStep) by a child process killed at every
// point of the door, then recovered by a second process, with the switch off
// (shadow) and on (live), outside and inside OneDrive. By content only: each
// page must be wholly as before or wholly as after; live, all one way, the way
// the list says the step stands; shadow, no staged new content left. Every
// result is one line starting RESULT. In no solution: the unit suite never
// builds it.

namespace Plantoir.UndoHarness;

internal static class W7Runs
{
    private static string Exe => Environment.ProcessPath!;

    private static readonly string[] Pages =
    [
        "courses/ICS3U/section1/All Classes/Unit 1, Day 1.md",
        "courses/ICS3U/section1/All Classes/Unit 1, Day 2.md",
        "courses/ICS3U/section1/All Classes/Unit 1, Day 3.md",
    ];

    private static string Page(int day, bool published) =>
        $"---\ntitle: Unit 1, Day {day}\ncreated: 2026-09-0{day}T07:00:00.000-0400\npublish: {(published ? "true" : "false")}\n---\nThe lesson.\n";

    private static string Root(string run) => Path.Combine(run, "wf");
    private static string Full(string run, string relative) => UndoDoor.FullPath(Root(run), relative);

    private static UndoForThisProcess List(string run, UndoMode mode) => new(Path.Combine(run, "undo"), mode, trail: null);

    private static void MakeTheFolder(string run)
    {
        string course = Path.Combine(Root(run), "courses", "ICS3U");
        Directory.CreateDirectory(course);
        File.WriteAllText(Path.Combine(course, "course_config.json"),
            "{\"course_code\":\"ICS3U\",\"course_name\":\"A course\",\"num_sections\":1,\"section_numbers\":[1],\"per_section_folders\":[\"All Classes\"],\"per_section_files\":[]}");
        for (int index = 0; index < Pages.Length; index++)
        {
            string path = Full(run, Pages[index]);
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            File.WriteAllText(path, Page(index + 1, published: false));
        }
    }

    /// <summary>
    /// The run: for each mode (shadow, live) and each kill point of the door
    /// (afterBegin, before each page's swap, beforeApplied), a child publishes
    /// the three pages through the step and is killed there; a second process
    /// recovers. Then every page is judged by its content.
    /// </summary>
    internal static int PublishKill(string folder)
    {
        var points = new List<string> { "afterBegin" };
        for (int index = 0; index < Pages.Length; index++) points.Add("beforeSwap@" + index.ToString(CultureInfo.InvariantCulture));
        points.Add("beforeApplied");
        int failures = 0;
        int total = 0;
        foreach (UndoMode mode in new[] { UndoMode.Shadow, UndoMode.Live })
        {
            foreach (string point in points)
            {
                total++;
                string run = Path.Combine(folder, mode + "-" + point.Replace('@', '-'));
                MakeTheFolder(run);
                string said = Child(["child-w7-publish", run, mode.ToString(), point], kill: true);
                string recovered = Child(["child-w7-recover", run, mode.ToString()], kill: false);
                var states = new List<string>();
                for (int index = 0; index < Pages.Length; index++)
                {
                    string text = File.Exists(Full(run, Pages[index])) ? File.ReadAllText(Full(run, Pages[index])) : "";
                    states.Add(text == Page(index + 1, false) ? "before" : text == Page(index + 1, true) ? "after" : "NEITHER");
                }
                UndoFolded folded = List(run, mode).Journal.Read().Folded;
                UndoFoldedStep? step = folded.Steps.Values.LastOrDefault();
                int stagedNew = 0;
                foreach (string entry in Directory.EnumerateFileSystemEntries(Root(run), "*", SearchOption.AllDirectories))
                {
                    string name = Path.GetFileName(entry);
                    if (name.Contains(UndoSwap.StagedMarker, StringComparison.Ordinal) && name.EndsWith("-new", StringComparison.Ordinal)) stagedNew++;
                }
                bool eachWhole = !states.Contains("NEITHER");
                bool reachedItsPoint = said.StartsWith("AT ", StringComparison.Ordinal);
                bool consistent;
                if (mode == UndoMode.Live)
                {
                    string expected = step?.State == UndoStepState.Done ? "after" : "before";
                    bool allOneWay = states.All(state => state == expected);
                    consistent = reachedItsPoint && eachWhole && allOneWay && step is not null && !step.IsInFlight && stagedNew == 0;
                }
                else
                {
                    consistent = reachedItsPoint && eachWhole && (step is null || !step.IsInFlight) && stagedNew == 0;
                }
                Console.WriteLine($"RESULT w7-publish-kill mode={mode} point={point} child=[{said}] recovered=[{recovered}] " +
                                  $"step={step?.State.ToString() ?? "none"} pages={string.Join(",", states)} stagedNew={stagedNew} {(consistent ? "WHOLE" : "NOT-WHOLE")}");
                if (!consistent) failures++;
            }
        }
        Console.WriteLine($"RESULT w7-publish-kill total={total} failures={failures}");
        return failures == 0 ? 0 : 1;
    }

    /// <summary>Starts a child, waits for its first line after STARTED, kills it when it reached its point (and <paramref name="kill"/>), and returns that line.</summary>
    private static string Child(string[] arguments, bool kill)
    {
        var start = new ProcessStartInfo(Exe) { RedirectStandardOutput = true, UseShellExecute = false };
        foreach (string argument in arguments) start.ArgumentList.Add(argument);
        using Process child = Process.Start(start)!;
        string? said = child.StandardOutput.ReadLine();
        if (said == "STARTED") said = child.StandardOutput.ReadLine();
        if (kill && said is not null && said.StartsWith("AT ", StringComparison.Ordinal))
        {
            try { child.Kill(entireProcessTree: true); } catch (InvalidOperationException) { }
        }
        child.WaitForExit();
        return said ?? "nothing";
    }

    /// <summary>Says where it is and blocks there until killed: the harness's kill point is the behaviour.</summary>
    private static UndoSeams StopAt(string at)
    {
        string point = at.Contains('@') ? at[..at.IndexOf('@')] : at;
        int index = at.Contains('@') ? int.Parse(at[(at.IndexOf('@') + 1)..], CultureInfo.InvariantCulture) : -1;
        return new UndoSeams
        {
            StopsHere = (name, where) =>
            {
                if (name != point || (index >= 0 && where != index)) return false;
                Console.WriteLine($"AT {name} {where}");
                Console.Out.Flush();
                Thread.Sleep(Timeout.Infinite);
                return true;
            },
        };
    }

    /// <summary>The publishing child: the three pages planned into ONE step, as Publish Pages plans them, and made through the door.</summary>
    internal static int ChildPublish(string run, string mode, string point)
    {
        Console.WriteLine("STARTED");
        Console.Out.Flush();
        UndoMode undoMode = Enum.Parse<UndoMode>(mode);
        UndoForThisProcess list = List(run, undoMode);
        var door = new UndoDoor(list.Journal, list.Mode, list.Maintainers, seams: StopAt(point), trail: list.Trail);
        var step = new UndoActionStep(new UndoStepMaker("menu", "publishPages"), Root(run), "ICS3U", 1, undo: list, door: door);
        for (int index = 0; index < Pages.Length; index++) step.Write(Full(run, Pages[index]), Page(index + 1, published: true));
        try
        {
            step.Make();
            Console.WriteLine("DONE made");
        }
        catch (Exception error)
        {
            Console.WriteLine("DONE " + error.GetType().Name + ": " + error.Message.Replace('\n', ' '));
        }
        return 0;
    }

    /// <summary>The recovering child: the app's recovery, as a process that sees the killed one as gone.</summary>
    internal static int ChildRecover(string run, string mode)
    {
        Console.WriteLine("STARTED");
        Console.Out.Flush();
        UndoForThisProcess list = List(run, Enum.Parse<UndoMode>(mode));
        UndoRecoveryRun recovered = list.Door().Recover();
        string settled = string.Join(",", recovered.Settled.Select(result => $"{result.Seq}:{result.Outcome}:{result.FilesPutBack}"));
        Console.WriteLine($"DONE {settled}{(recovered.NotRun is { } why ? " notRun " + why : "")}");
        Console.Out.Flush();
        return 0;
    }
}
