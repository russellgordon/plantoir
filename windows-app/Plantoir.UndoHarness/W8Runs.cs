using System.Diagnostics;
using System.Globalization;
using System.Text;
using System.Text.Json.Nodes;
using Plantoir.Core.Undo;

// #899 W8-7: a step that moves a folder and edits a page inside it (U4b,
// opKinds.wholeOps' one exception), made, undone and redone by a child process
// killed at every point, then recovered by a second process, in shadow and
// live. Every result is one line starting RESULT. In no solution: the unit
// suite never builds it.

namespace Plantoir.UndoHarness;

internal static class W8Runs
{
    private static string Exe => Environment.ProcessPath!;

    private const string Page1 = "courses/TST1O/Section 1/Classes/first.md";
    private const string Page2 = "courses/TST1O/Section 1/Classes/second.md";
    private const string Media = "courses/TST1O/media";
    private const string Renamed = "courses/TST1O/renamed";
    private const string Old = "Intro.\nLine one: old.\nEnd.\n";
    private const string New = "Intro.\nLine one: new.\nEnd.\n";

    private static string Root(string run) => Path.Combine(run, "wf");
    private static string Full(string run, string relative) => UndoDoor.FullPath(Root(run), relative);
    private static UndoForThisProcess List(string run, UndoMode mode) => new(Path.Combine(run, "undo"), mode, trail: null);

    private static byte[] Page(string title, bool published) => Encoding.UTF8.GetBytes($"---\ntitle: {title}\npublish: {(published ? "true" : "false")}\n---\nThe lesson.\n");

    private static void Write(string run, string relative, byte[] bytes)
    {
        string full = Full(run, relative);
        Directory.CreateDirectory(Path.GetDirectoryName(full)!);
        File.WriteAllBytes(full, bytes);
    }

    private static void Lay(string run)
    {
        Write(run, Page1, Page("first", false));
        Write(run, Page2, Page("second", false));
        Write(run, Media + "/a.md", Encoding.UTF8.GetBytes(Old));
        Write(run, Media + "/b.md", "B\n"u8.ToArray());
    }

    /// <summary>The step: the folder moved first, then the two pages, then the edit inside, named at the folder's new place (four swaps).</summary>
    private static UndoOpsDraft TheStep(string run)
    {
        var ops = new JsonArray
        {
            new JsonObject { ["kind"] = "move", ["from"] = Media, ["to"] = Renamed, ["listingSha"] = UndoTreeReading.Read(Full(run, Media)).ListingSha },
        };
        foreach ((string path, string title) in new[] { (Page1, "first"), (Page2, "second") })
        {
            foreach (JsonNode? op in UndoLineOps.ForAFile(path, Page(title, false), Page(title, true))) ops.Add(op!.DeepClone());
        }
        ops.Add(new JsonObject
        {
            ["kind"] = "replaceText", ["path"] = Renamed + "/a.md", ["before"] = "old", ["after"] = "new",
            ["contextBefore"] = "Line one: ", ["contextAfter"] = ".\n",
        });
        return new UndoOpsDraft
        {
            ActionKey = "renameFolder", MadeBy = "menu", WorkingFolder = Root(run), Course = "TST1O", Section = 1, Holds = "section", Ops = ops, Blobs = [],
        };
    }

    /// <summary>
    /// Killed at the work's first point, before each of its four swaps and
    /// before its end, for the step, its Undo and its Redo, in shadow then
    /// live, recovered by a second process. Every place (each page, the
    /// folder's place, the page inside it) whole before or whole after; live,
    /// all one way as the list says; nothing staged inside the folder at
    /// either place, and no staged new content anywhere.
    /// </summary>
    internal static int CarryingMoveKill(string folder)
    {
        int failures = 0;
        int total = 0;
        foreach (UndoMode mode in new[] { UndoMode.Shadow, UndoMode.Live })
        {
            foreach ((string work, string first, string last) in new[] { ("step", "afterBegin", "beforeApplied"), ("undo", "afterUndoing", "beforeUndone"), ("redo", "afterRedoing", "beforeRedone") })
            {
                var points = new List<string> { first };
                for (int index = 0; index < 4; index++) points.Add("beforeSwap@" + index.ToString(CultureInfo.InvariantCulture));
                points.Add(last);
                foreach (string point in points)
                {
                    total++;
                    string run = Path.Combine(folder, "carry-" + mode + "-" + work + "-" + point.Replace('@', '-'));
                    Lay(run);
                    string setUp = "none";
                    if (work != "step")
                    {
                        UndoForThisProcess list = List(run, mode);
                        setUp = list.Door().Perform(TheStep(run)).Word;
                        if (work == "redo") setUp += "," + list.Door().Undo().Word;
                    }
                    string said = Child(["child-w8-carry", run, mode.ToString(), work, point], kill: true);
                    string recovered = Child(["child-w8-recover", run, mode.ToString()], kill: false);
                    (List<string> states, int stagedInside, int stagedNew) = Look(run);
                    UndoFoldedStep? step = List(run, mode).Journal.Read().Folded.Steps.Values.LastOrDefault();
                    bool eachWhole = !states.Contains("NEITHER");
                    bool reachedItsPoint = said.StartsWith("AT ", StringComparison.Ordinal);
                    bool consistent = reachedItsPoint && eachWhole && step is not null && !step.IsInFlight && stagedInside == 0 && stagedNew == 0;
                    if (mode == UndoMode.Live)
                    {
                        string expected = step?.State == UndoStepState.Done ? "after" : "before";
                        consistent = consistent && states.All(state => state == expected);
                    }
                    Console.WriteLine($"RESULT w8-carrying-move-kill mode={mode} work={work} point={point} setUp=[{setUp}] child=[{said}] recovered=[{recovered}] " +
                                      $"step={step?.State.ToString() ?? "none"} places={string.Join(",", states)} stagedInside={stagedInside} stagedNew={stagedNew} {(consistent ? "WHOLE" : "NOT-WHOLE")}");
                    if (!consistent) failures++;
                }
            }
        }
        Console.WriteLine($"RESULT w8-carrying-move-kill total={total} failures={failures}");
        return failures == 0 ? 0 : 1;
    }

    /// <summary>first, second, the folder's place, the page inside it: before, after or NEITHER; the staged entries inside the folder at either place; the staged new contents anywhere.</summary>
    private static (List<string> States, int StagedInside, int StagedNew) Look(string run)
    {
        string Of(byte[]? now, byte[] before, byte[] after) =>
            now is null ? "NEITHER" : now.AsSpan().SequenceEqual(before) ? "before" : now.AsSpan().SequenceEqual(after) ? "after" : "NEITHER";
        byte[]? Read(string relative) => File.Exists(Full(run, relative)) ? File.ReadAllBytes(Full(run, relative)) : null;
        var states = new List<string> { Of(Read(Page1), Page("first", false), Page("first", true)), Of(Read(Page2), Page("second", false), Page("second", true)) };
        bool atMedia = Directory.Exists(Full(run, Media));
        bool atRenamed = Directory.Exists(Full(run, Renamed));
        string folderAt = atMedia == atRenamed ? "NEITHER" : atMedia ? "before" : "after";
        string inside = atRenamed ? Renamed : Media;
        if (Read(inside + "/b.md") is not { } b || Encoding.UTF8.GetString(b) != "B\n") folderAt = "NEITHER";
        states.Add(folderAt);
        states.Add(Of(Read(inside + "/a.md"), Encoding.UTF8.GetBytes(Old), Encoding.UTF8.GetBytes(New)));
        int stagedInside = 0;
        foreach (string place in new[] { Media, Renamed })
        {
            if (!Directory.Exists(Full(run, place))) continue;
            foreach (string entry in Directory.EnumerateFileSystemEntries(Full(run, place), "*", SearchOption.AllDirectories))
            {
                if (Path.GetFileName(entry).Contains(UndoSwap.StagedMarker, StringComparison.Ordinal)) stagedInside++;
            }
        }
        int stagedNew = 0;
        foreach (string entry in Directory.EnumerateFileSystemEntries(Root(run), "*", SearchOption.AllDirectories))
        {
            string name = Path.GetFileName(entry);
            if (name.Contains(UndoSwap.StagedMarker, StringComparison.Ordinal) && name.EndsWith("-new", StringComparison.Ordinal)) stagedNew++;
        }
        return (states, stagedInside, stagedNew);
    }

    /// <summary>The working child: the step, its Undo or its Redo, through a door that stops at <paramref name="point"/>.</summary>
    internal static int ChildCarry(string run, string mode, string work, string point)
    {
        Console.WriteLine("STARTED");
        Console.Out.Flush();
        UndoForThisProcess list = List(run, Enum.Parse<UndoMode>(mode));
        var door = new UndoDoor(list.Journal, list.Mode, list.Maintainers, StopAt(point));
        UndoOutcome outcome = work switch
        {
            "undo" => door.Undo(),
            "redo" => door.Redo(),
            _ => door.Perform(TheStep(run)),
        };
        Console.WriteLine("DONE " + outcome.Word);
        return 0;
    }

    /// <summary>The recovering child: the app's recovery, as a process that sees the killed one as gone.</summary>
    internal static int ChildRecover(string run, string mode)
    {
        Console.WriteLine("STARTED");
        Console.Out.Flush();
        UndoRecoveryRun recovered = List(run, Enum.Parse<UndoMode>(mode)).Door().Recover();
        string settled = string.Join(",", recovered.Settled.Select(result => $"{result.Seq}:{result.Outcome}:{result.FilesPutBack}"));
        Console.WriteLine($"DONE {settled}{(recovered.NotRun is { } why ? " notRun " + why : "")}");
        Console.Out.Flush();
        return 0;
    }

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

    /// <summary>Seams that park this process at <paramref name="at"/> (<c>point</c> or <c>point@index</c>) until the harness kills it.</summary>
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
}
