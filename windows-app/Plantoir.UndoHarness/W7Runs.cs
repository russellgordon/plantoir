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

    // ---- W7b1: new pages (Add Classes), and LOW 3's plain write ---------------------

    private static readonly string[] NewPages =
    [
        "courses/ICS3U/section1/All Classes/Unit 2, Day 1.md",
        "courses/ICS3U/section1/All Classes/Unit 2, Day 2.md",
        "courses/ICS3U/section1/All Classes/Unit 2, Day 3.md",
    ];

    private static string NewPage(int day) =>
        $"---\ntitle: Unit 2, Day {day}\npublish: false\ncreated: 2026-09-1{day}T07:00:00.000-0400\n---\n\n## Agenda\n\n1.\n";

    /// <summary>Whether any file under the folder is Hidden that is not a kept copy (<c>-orig</c>).</summary>
    private static int HiddenNotKept(string root)
    {
        int found = 0;
        foreach (string entry in Directory.EnumerateFiles(root, "*", SearchOption.AllDirectories))
        {
            if (!File.GetAttributes(entry).HasFlag(FileAttributes.Hidden)) continue;
            if (Path.GetFileName(entry).EndsWith("-orig", StringComparison.Ordinal)) continue;
            found++;
        }
        return found;
    }

    /// <summary>
    /// Add Classes' step (W7b1): three NEW pages (writeFile, no before) in a
    /// class folder that does not exist yet, made by the swap, killed at every
    /// point of the door, shadow then live, then recovered by a second
    /// process. Each page is absent or whole; live, all one way.
    /// </summary>
    internal static int AddClassesKill(string folder)
    {
        var points = new List<string> { "afterBegin" };
        for (int index = 0; index < NewPages.Length; index++) points.Add("beforeSwap@" + index.ToString(CultureInfo.InvariantCulture));
        points.Add("beforeApplied");
        int failures = 0;
        int total = 0;
        foreach (UndoMode mode in new[] { UndoMode.Shadow, UndoMode.Live })
        {
            foreach (string point in points)
            {
                total++;
                string run = Path.Combine(folder, "add-" + mode + "-" + point.Replace('@', '-'));
                string course = Path.Combine(Root(run), "courses", "ICS3U");
                Directory.CreateDirectory(Path.Combine(course, "section1"));
                File.WriteAllText(Path.Combine(course, "course_config.json"),
                    "{\"course_code\":\"ICS3U\",\"course_name\":\"A course\",\"num_sections\":1,\"section_numbers\":[1],\"per_section_folders\":[\"All Classes\"],\"per_section_files\":[]}");
                string said = Child(["child-w7-add-classes", run, mode.ToString(), point], kill: true);
                string recovered = Child(["child-w7-recover", run, mode.ToString()], kill: false);
                var states = new List<string>();
                for (int index = 0; index < NewPages.Length; index++)
                {
                    string path = Full(run, NewPages[index]);
                    states.Add(!File.Exists(path) ? "absent" : File.ReadAllText(path) == NewPage(index + 1) ? "after" : "NEITHER");
                }
                UndoFoldedStep? step = List(run, mode).Journal.Read().Folded.Steps.Values.LastOrDefault();
                int stagedNew = 0;
                foreach (string entry in Directory.EnumerateFileSystemEntries(Root(run), "*", SearchOption.AllDirectories))
                {
                    string name = Path.GetFileName(entry);
                    if (name.Contains(UndoSwap.StagedMarker, StringComparison.Ordinal) && name.EndsWith("-new", StringComparison.Ordinal)) stagedNew++;
                }
                int hidden = HiddenNotKept(Root(run));
                bool eachWhole = !states.Contains("NEITHER");
                bool reachedItsPoint = said.StartsWith("AT ", StringComparison.Ordinal);
                bool consistent;
                if (mode == UndoMode.Live)
                {
                    string expected = step?.State == UndoStepState.Done ? "after" : "absent";
                    consistent = reachedItsPoint && eachWhole && states.All(state => state == expected) && step is not null && !step.IsInFlight
                                 && stagedNew == 0 && hidden == 0;
                }
                else
                {
                    consistent = reachedItsPoint && eachWhole && (step is null || !step.IsInFlight) && stagedNew == 0 && hidden == 0;
                }
                Console.WriteLine($"RESULT w7-add-classes-kill mode={mode} point={point} child=[{said}] recovered=[{recovered}] " +
                                  $"step={step?.State.ToString() ?? "none"} pages={string.Join(",", states)} stagedNew={stagedNew} hidden={hidden} {(consistent ? "WHOLE" : "NOT-WHOLE")}");
                if (!consistent) failures++;
            }
        }
        Console.WriteLine($"RESULT w7-add-classes-kill total={total} failures={failures}");
        return failures == 0 ? 0 : 1;
    }

    /// <summary>The adding child: three new pages planned into ONE step, as ApplyAddClasses plans them, and made through the door.</summary>
    internal static int ChildAddClasses(string run, string mode, string point)
    {
        Console.WriteLine("STARTED");
        Console.Out.Flush();
        UndoForThisProcess list = List(run, Enum.Parse<UndoMode>(mode));
        var door = new UndoDoor(list.Journal, list.Mode, list.Maintainers, seams: StopAt(point), trail: list.Trail);
        var step = new UndoActionStep(new UndoStepMaker("outsideAssistant::harness", "addClasses"), Root(run), "ICS3U", 1, undo: list, door: door);
        for (int index = 0; index < NewPages.Length; index++) step.Write(Full(run, NewPages[index]), NewPage(index + 1));
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

    /// <summary>
    /// The W7a final review's LOW 3: a plain write (no working folder, so no
    /// list) of three pages killed before each swap and before its end; then a
    /// second process's plain write of the same pages meets what the first
    /// left. Nothing staged of the dead process may stay, a kept copy that is
    /// an only copy stays, each page whole.
    /// </summary>
    internal static int PlainKill(string folder)
    {
        var points = new List<string>();
        for (int index = 0; index < Pages.Length; index++) points.Add("beforeSwap@" + index.ToString(CultureInfo.InvariantCulture));
        int failures = 0;
        foreach (string point in points)
        {
            string run = Path.Combine(folder, "plain-" + point.Replace('@', '-'));
            for (int index = 0; index < Pages.Length; index++)
            {
                string path = Path.Combine(run, Path.GetFileName(Pages[index]));
                Directory.CreateDirectory(run);
                File.WriteAllText(path, Page(index + 1, published: false));
            }
            string said = Child(["child-w7-plain", run, "killed", point], kill: true);
            string again = Child(["child-w7-plain", run, "again", "none"], kill: false);
            var states = new List<string>();
            int leftNew = 0;
            int leftOrigCopies = 0;
            for (int index = 0; index < Pages.Length; index++)
            {
                string path = Path.Combine(run, Path.GetFileName(Pages[index]));
                string text = File.ReadAllText(path);
                states.Add(text == Page(index + 1, true) ? "after" : "NEITHER");
                foreach (string entry in Directory.EnumerateFiles(run, "." + Path.GetFileName(path) + UndoSwap.StagedMarker + "*"))
                {
                    if (entry.EndsWith("-new", StringComparison.Ordinal)) leftNew++;
                    else if (UndoSwap.IsACopyOfItsPlace(entry, path)) leftOrigCopies++;
                }
            }
            bool whole = said.StartsWith("AT ", StringComparison.Ordinal) && !states.Contains("NEITHER") && leftNew == 0 && leftOrigCopies == 0
                         && HiddenNotKept(run) == 0;
            Console.WriteLine($"RESULT w7-plain-kill point={point} child=[{said}] again=[{again}] pages={string.Join(",", states)} leftNew={leftNew} leftCopies={leftOrigCopies} {(whole ? "WHOLE" : "NOT-WHOLE")}");
            if (!whole) failures++;
        }
        Console.WriteLine($"RESULT w7-plain-kill total={points.Count} failures={failures}");
        return failures == 0 ? 0 : 1;
    }

    /// <summary>A plain-writing child: the three pages published through a step with no working folder (so no list), stopped at <paramref name="point"/> unless it is <c>none</c>.</summary>
    internal static int ChildPlain(string run, string what, string point)
    {
        Console.WriteLine("STARTED");
        Console.Out.Flush();
        UndoForThisProcess list = new(Path.Combine(run, "..", "plain-undo"), UndoMode.Shadow, trail: null);
        var step = new UndoActionStep(new UndoStepMaker("menu", "publishPages"), null, null, null, undo: list,
                                      plainSeams: point == "none" ? null : StopAt(point));
        for (int index = 0; index < Pages.Length; index++)
        {
            string path = Path.Combine(run, Path.GetFileName(Pages[index]));
            // The second write plans the published page over whatever is there.
            step.Write(path, Page(index + 1, published: true));
        }
        try
        {
            step.Make();
            Console.WriteLine($"DONE {what} made");
        }
        catch (Exception error)
        {
            Console.WriteLine($"DONE {what} " + error.GetType().Name + ": " + error.Message.Replace('\n', ' '));
        }
        return 0;
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
