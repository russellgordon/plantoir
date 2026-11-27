using System.Diagnostics;
using System.Globalization;
using System.Text;
using System.Text.Json.Nodes;
using Plantoir.Core.Undo;

// #899 W8b-21a5 (Windows' copy of the mac's U4b3 door-5): a step that hands a
// place over (opKinds.wholeOps' second exception), shape A (a link's move from
// Day 3 to Day 4, then a new page at Day 3) and shape B (Day 4 written, Day 3
// removed, the link moved from Day 2 into Day 3, then a new page at Day 2),
// made, undone and redone by a child process killed before EVERY swap, then
// recovered by a second process, live; once with the links inside the course
// (to its library) and once leading OUT of the working folder. The mac's model
// is UndoHandedOverPlaceTests.killAtEverySwap. Every result is one line
// starting RESULT. In no solution: the unit suite never builds it.

namespace Plantoir.UndoHarness;

internal static class W8bRuns
{
    private static string Exe => Environment.ProcessPath!;

    private const string Section = "courses/TST1O/section1";
    private const string Library = "courses/TST1O/library";

    private static string Day(int number) => Section + "/Unit 1, Day " + number + ".md";
    private static string Root(string run) => Path.Combine(run, "wf");
    private static string Outside(string run) => Path.Combine(run, "outside");
    private static string Full(string run, string relative) => UndoDoor.FullPath(Root(run), relative);
    private static UndoForThisProcess List(string run) => new(Path.Combine(run, "undo"), UndoMode.Live, trail: null);

    private static byte[] Bytes(string text) => Encoding.UTF8.GetBytes(text);

    private static void Write(string run, string relative, string text)
    {
        string full = Full(run, relative);
        Directory.CreateDirectory(Path.GetDirectoryName(full)!);
        File.WriteAllBytes(full, Bytes(text));
    }

    /// <summary>The link at Day <paramref name="day"/>: to the library's page (relative, as Windows writes it) or, leading out, to a page outside the working folder by its full path.</summary>
    private static void LayALink(string run, int day, bool leadingOut)
    {
        string name = "Day " + day + ".md";
        string place = Full(run, Day(day));
        Directory.CreateDirectory(Path.GetDirectoryName(place)!);
        if (leadingOut)
        {
            Directory.CreateDirectory(Outside(run));
            File.WriteAllBytes(Path.Combine(Outside(run), name), Bytes("Linked.\n"));
            File.CreateSymbolicLink(place, Path.Combine(Outside(run), name));
            return;
        }
        Write(run, Library + "/" + name, "Linked.\n");
        File.CreateSymbolicLink(place, @"..\library\" + name);
    }

    private static void Lay(string run, string shape, bool leadingOut)
    {
        Directory.CreateDirectory(Path.Combine(Root(run), "courses", ".internal"));
        if (shape == "A")
        {
            LayALink(run, 3, leadingOut);
            return;
        }
        LayALink(run, 2, leadingOut);
        Write(run, Day(3), "Three.\n");
    }

    private static JsonObject LinksMove(string run, int from, int to) => new()
    {
        ["kind"] = "move", ["from"] = Day(from), ["to"] = Day(to), ["linkSha"] = UndoLinks.LinkSha(Full(run, Day(from))),
    };

    private static JsonNode PageOp(int day, string? before, string? after) =>
        UndoLineOps.ForAFile(Day(day), before is null ? null : Bytes(before), after is null ? null : Bytes(after))[0]!.DeepClone();

    /// <summary>The step, read from the disk as laid: shape A two swaps, shape B four.</summary>
    private static UndoOpsDraft TheStep(string run, string shape)
    {
        JsonArray ops = shape == "A"
            ? new JsonArray(LinksMove(run, 3, 4), PageOp(3, null, "New.\n"))
            : new JsonArray(PageOp(4, null, "Three.\n"), PageOp(3, "Three.\n", null), LinksMove(run, 2, 3), PageOp(2, null, "New.\n"));
        return new UndoOpsDraft
        {
            ActionKey = "insertClass", MadeBy = "menu", WorkingFolder = Root(run), Course = "TST1O", Section = 1, Holds = "section", Ops = ops,
            Blobs = [Bytes("New.\n"), Bytes("Three.\n")],
        };
    }

    /// <summary>
    /// Each shape, each way (the step, its Undo, its Redo), with the links
    /// inside and leading out, killed before each of its swaps and recovered:
    /// section 1, the library and the folder outside exactly as before the step
    /// or exactly as after it (each link where one of the two states puts it,
    /// with its target; no page lost), nothing staged anywhere, the step settled.
    /// </summary>
    internal static int HandoverKill(string folder)
    {
        int failures = 0;
        int total = 0;
        foreach (bool leadingOut in new[] { false, true })
        {
            foreach (string shape in new[] { "A", "B" })
            {
                int swaps = shape == "A" ? 2 : 4;
                // The two whole states, made in a run of their own.
                string wholeRun = Path.Combine(folder, "whole-" + shape + (leadingOut ? "-out" : "-in"));
                Lay(wholeRun, shape, leadingOut);
                string before = Snapshot(wholeRun);
                string made = List(wholeRun).Door().Perform(TheStep(wholeRun, shape)).Word;
                string after = Snapshot(wholeRun);
                Console.WriteLine($"RESULT w8b-handover-kill whole shape={shape} leadingOut={leadingOut} made=[{made}] before=[{before}] after=[{after}]");
                foreach (string work in new[] { "step", "undo", "redo" })
                {
                    for (int index = 0; index < swaps; index++)
                    {
                        total++;
                        string point = "beforeSwap@" + index.ToString(CultureInfo.InvariantCulture);
                        string run = Path.Combine(folder, shape + (leadingOut ? "-out-" : "-in-") + work + "-" + index.ToString(CultureInfo.InvariantCulture));
                        Lay(run, shape, leadingOut);
                        string setUp = "none";
                        if (work != "step")
                        {
                            UndoForThisProcess list = List(run);
                            setUp = list.Door().Perform(TheStep(run, shape)).Word;
                            if (work == "redo") setUp += "," + list.Door().Undo().Word;
                        }
                        string said = Child(["child-w8b-handover", run, shape, work, point], kill: true);
                        string recovered = Child(["child-w8b-handover-recover", run], kill: false);
                        string now = Snapshot(run);
                        int staged = Staged(run);
                        UndoFoldedStep? step = List(run).Journal.Read().Folded.Steps.Values.LastOrDefault();
                        bool reached = said.StartsWith("AT ", StringComparison.Ordinal);
                        string state = now == before ? "before" : now == after ? "after" : "NEITHER";
                        bool whole = reached && state != "NEITHER" && staged == 0 && step is not null && !step.IsInFlight;
                        if (whole) whole = state == (step!.State == UndoStepState.Done ? "after" : "before");
                        Console.WriteLine($"RESULT w8b-handover-kill shape={shape} leadingOut={leadingOut} work={work} point={point} setUp=[{setUp}] child=[{said}] recovered=[{recovered}] " +
                                          $"step={step?.State.ToString() ?? "none"} state={state} staged={staged} {(whole ? "WHOLE" : "NOT-WHOLE now=[" + now + "]")}");
                        if (!whole) failures++;
                    }
                }
            }
        }
        Console.WriteLine($"RESULT w8b-handover-kill total={total} failures={failures}");
        return failures == 0 ? 0 : 1;
    }

    /// <summary>Every entry of section 1, the library and the folder outside, by name: a link with its target as written, a page with its text, or what else stands there.</summary>
    private static string Snapshot(string run)
    {
        var parts = new List<string>();
        foreach ((string label, string full) in new[] { ("section1", Full(run, Section)), ("library", Full(run, Library)), ("outside", Outside(run)) })
        {
            if (!Directory.Exists(full)) continue;
            var names = new List<string>();
            foreach (string entry in Directory.EnumerateFileSystemEntries(full)) names.Add(Path.GetFileName(entry));
            names.Sort(StringComparer.Ordinal);
            foreach (string name in names)
            {
                string at = Path.Combine(full, name);
                string holds = UndoLinks.Look(at) switch
                {
                    UndoLinks.What.Link => "link " + (new FileInfo(at).LinkTarget ?? "notALink"),
                    UndoLinks.What.File => "page " + File.ReadAllText(at).Replace("\n", "\\n"),
                    UndoLinks.What other => other.ToString(),
                };
                parts.Add(label + "/" + name + ": " + holds);
            }
        }
        return string.Join(" | ", parts);
    }

    /// <summary>Every staged entry (the journal's hidden names) anywhere in the working folder or outside it.</summary>
    private static int Staged(string run)
    {
        int count = 0;
        foreach (string place in new[] { Root(run), Outside(run) })
        {
            if (!Directory.Exists(place)) continue;
            foreach (string entry in Directory.EnumerateFileSystemEntries(place, "*", SearchOption.AllDirectories))
            {
                if (Path.GetFileName(entry).Contains(UndoSwap.StagedMarker, StringComparison.Ordinal)) count++;
            }
        }
        return count;
    }

    /// <summary>The working child: the step, its Undo or its Redo, through a door that stops at <paramref name="point"/>.</summary>
    internal static int ChildHandover(string run, string shape, string work, string point)
    {
        Console.WriteLine("STARTED");
        Console.Out.Flush();
        UndoForThisProcess list = List(run);
        var door = new UndoDoor(list.Journal, list.Mode, list.Maintainers, StopAt(point));
        UndoOutcome outcome = work switch
        {
            "undo" => door.Undo(),
            "redo" => door.Redo(),
            _ => door.Perform(TheStep(run, shape)),
        };
        Console.WriteLine("DONE " + outcome.Word);
        return 0;
    }

    /// <summary>The recovering child: the app's recovery, as a process that sees the killed one as gone.</summary>
    internal static int ChildRecover(string run)
    {
        Console.WriteLine("STARTED");
        Console.Out.Flush();
        UndoRecoveryRun recovered = List(run).Door().Recover();
        string settled = string.Join(",", recovered.Settled.Select(result => $"{result.Seq}:{result.Outcome}:{result.FilesPutBack}:{result.FilesInTheWay}"));
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

    /// <summary>Seams that park this process at <paramref name="at"/> (<c>point@index</c>) until the harness kills it.</summary>
    private static UndoSeams StopAt(string at)
    {
        string point = at[..at.IndexOf('@')];
        int index = int.Parse(at[(at.IndexOf('@') + 1)..], CultureInfo.InvariantCulture);
        return new UndoSeams
        {
            StopsHere = (name, where) =>
            {
                if (name != point || where != index) return false;
                Console.WriteLine($"AT {name} {where}");
                Console.Out.Flush();
                Thread.Sleep(Timeout.Infinite);
                return true;
            },
        };
    }
}
