using System.Globalization;
using System.Text;
using System.Text.Json.Nodes;
using Plantoir.Core.Undo;

// #899 W8b-21b4 (Windows' copy of the mac's U4b3 review F kill table,
// UndoRelinkTests.testChainedLinkMovesKilledAtEveryStopPointLoseNoLink, and
// review G's five probe shapes): every chained link move Insert Class makes,
// made, undone and redone by a child process killed at EVERY stop point the
// door has, then recovered by a second process, live; once with the links'
// texts as the mac's table writes them (`Unit 1, Day 2.md`) and once with one
// text (Day 2's) leading OUT of the working folder by its full path. After
// recovery every link stands where one of the two states puts it, holding that
// state's text; nothing staged is left; the files the links lead to are
// untouched; the step is settled on the side its links show. A second table
// lays a teacher's own page or link under a staged name while the child is
// parked, before the kill: it must end given back or under a visible name,
// never deleted, never hidden. Every result is one line starting RESULT.

namespace Plantoir.UndoHarness;

internal static class W8bRelinkRuns
{
    private const string Section = "courses/TST1O/section1";

    /// <summary>The mac's four ChainShapes, review G's five probes, and the director's Insert Class at a day whose page is a link.</summary>
    internal static readonly string[] Shapes =
    [
        "twoChainedRelinks", "threeChainedRelinks", "aMoveThenARelinkIntoItsPlace", "aRelinkThenAMoveIntoItsPlace",
        "fourChainedRelinks", "moveRelinkMove", "relinkMoveRelink", "twoRelinksWithTheSameTexts", "twoMovesThenARelink",
        "aRelinkFromADayANewPageFills",
    ];

    private static string Day(int number) => Section + "/Unit 1, Day " + number + ".md";
    private static string Root(string run) => Path.Combine(run, "wf");
    private static string Outside(string run) => Path.Combine(run, "outside");
    private static string Full(string run, string relative) => UndoDoor.FullPath(Root(run), relative);
    private static UndoForThisProcess List(string run) => new(Path.Combine(run, "undo"), UndoMode.Live, trail: null);
    private static byte[] Bytes(string text) => Encoding.UTF8.GetBytes(text);

    /// <summary>The text a class link holds, `Unit 1, Day n.md`; leading out, Day 2's is the full path of a page outside the working folder.</summary>
    private static string Text(string run, int day, bool leadingOut) =>
        leadingOut && day == 2 ? Path.Combine(Outside(run), "Unit 1, Day 2.md") : "Unit 1, Day " + day + ".md";

    private sealed record Laid(UndoOpsDraft Draft, int Swaps, int Relinks);

    /// <summary>Lays the shape's pages and links and answers its step, highest first as Insert Class makes it.</summary>
    private static Laid Lay(string run, string shape, bool leadingOut, bool layingFiles = true)
    {
        if (layingFiles) LayThePages(run, leadingOut);
        string T(int day) => Text(run, day, leadingOut);
        void Link(int day, int holding)
        {
            if (layingFiles) File.CreateSymbolicLink(Full(run, Day(day)), T(holding));
        }
        void Page(int day, string text)
        {
            if (layingFiles) File.WriteAllBytes(Full(run, Day(day)), Bytes(text));
        }
        return Steps(run, shape, leadingOut, T, Link, Page);
    }

    private static void LayThePages(string run, bool leadingOut)
    {
        Directory.CreateDirectory(Path.Combine(Root(run), "courses", ".internal"));
        Directory.CreateDirectory(Full(run, Section));
        // The pages the links lead to: Day 1 and Day 2 (never a link's place), and Day 2's outside.
        File.WriteAllBytes(Full(run, Day(1)), Bytes("One.\n"));
        File.WriteAllBytes(Full(run, Day(2)), Bytes("Two.\n"));
        if (leadingOut)
        {
            Directory.CreateDirectory(Outside(run));
            File.WriteAllBytes(Text(run, 2, true), Bytes("Outside two.\n"));
        }
    }

    private static Laid Steps(string run, string shape, bool leadingOut, Func<int, string> T, Action<int, int> Link, Action<int, string> Page)
    {
        var ops = new JsonArray();
        var texts = new SortedSet<int>();
        int relinks = 0;
        void Relink(int from, int to, int before, int after)
        {
            string beforeSha = UndoCheck.Sha(Bytes(T(before)));
            string afterSha = UndoCheck.Sha(Bytes(T(after)));
            ops.Add(new JsonObject
            {
                ["kind"] = "move", ["from"] = Day(from), ["to"] = Day(to),
                ["linkShaBefore"] = beforeSha, ["linkShaAfter"] = afterSha, ["blobs"] = new JsonArray(beforeSha, afterSha),
            });
            texts.Add(before);
            texts.Add(after);
            relinks++;
        }
        void Move(int from, int to, int holding) => ops.Add(new JsonObject
        {
            ["kind"] = "move", ["from"] = Day(from), ["to"] = Day(to), ["linkSha"] = UndoCheck.Sha(Bytes(T(holding))),
        });
        var blobs = new List<byte[]>();
        switch (shape)
        {
            case "twoChainedRelinks":
                Link(4, 1); Link(5, 2);
                Relink(5, 6, 2, 3); Relink(4, 5, 1, 2);
                break;
            case "threeChainedRelinks":
                Link(4, 1); Link(5, 2); Link(6, 3);
                Relink(6, 7, 3, 4); Relink(5, 6, 2, 3); Relink(4, 5, 1, 2);
                break;
            case "aMoveThenARelinkIntoItsPlace":
                Link(4, 1); Link(5, 2);
                Move(5, 6, 2); Relink(4, 5, 1, 2);
                break;
            case "aRelinkThenAMoveIntoItsPlace":
                Link(4, 2); Link(5, 2);
                Relink(5, 6, 2, 3); Move(4, 5, 2);
                break;
            case "fourChainedRelinks":
                Link(4, 1); Link(5, 2); Link(6, 3); Link(7, 4);
                Relink(7, 8, 4, 5); Relink(6, 7, 3, 4); Relink(5, 6, 2, 3); Relink(4, 5, 1, 2);
                break;
            case "moveRelinkMove":
                // Day 5 to 6 moved, Day 4 to 5 relinked, Day 3 to 4 moved, each into the last's place.
                Link(3, 1); Link(4, 1); Link(5, 2);
                Move(5, 6, 2); Relink(4, 5, 1, 2); Move(3, 4, 1);
                break;
            case "relinkMoveRelink":
                // Day 6 to 7 relinked, Day 5 to 6 moved, Day 4 to 5 relinked.
                Link(4, 1); Link(5, 2); Link(6, 2);
                Relink(6, 7, 2, 3); Move(5, 6, 2); Relink(4, 5, 1, 2);
                break;
            case "twoRelinksWithTheSameTexts":
                // Day 5 to 6 and Day 4 to 5, both `Day 1` becoming `Day 2`.
                Link(4, 1); Link(5, 1);
                Relink(5, 6, 1, 2); Relink(4, 5, 1, 2);
                break;
            case "twoMovesThenARelink":
                Link(4, 1); Link(5, 2); Link(6, 2);
                Move(6, 7, 2); Move(5, 6, 2); Relink(4, 5, 1, 2);
                break;
            case "aRelinkFromADayANewPageFills":
                // Insert Class at Day 4, whose page is a link: the link relinked
                // into Day 5 and the new class page written at Day 4 (the
                // relink's from), staged beside the relink's place.
                Link(4, 1);
                Relink(4, 5, 1, 2);
                ops.Add(UndoLineOps.ForAFile(Day(4), null, Bytes("New.\n"))[0]!.DeepClone());
                blobs.Add(Bytes("New.\n"));
                break;
            case "aRelinkIntoADayAPageLeaves":
                // Window E review 1, MEDIUM (piece 22's Insert Class shape, a
                // teacher's row only): Day 5's PAGE moved to Day 6 and Day 4's
                // link relinked into Day 5. A plain page move stages nothing.
                Link(4, 1);
                Page(5, "Five.\n");
                ops.Add(new JsonObject { ["kind"] = "move", ["from"] = Day(5), ["to"] = Day(6), ["sha"] = UndoCheck.Sha(Bytes("Five.\n")) });
                blobs.Add(Bytes("Five.\n"));
                Relink(4, 5, 1, 2);
                break;
            default:
                throw new ArgumentException("no shape " + shape);
        }
        foreach (int day in texts) blobs.Add(Bytes(T(day)));
        var draft = new UndoOpsDraft
        {
            ActionKey = "insertClass", MadeBy = "menu", WorkingFolder = Root(run), Course = "TST1O", Section = 1, Holds = "section", Ops = ops,
            Blobs = blobs,
        };
        return new Laid(draft, ops.Count, relinks);
    }

    /// <summary>Every stop point the Windows door has, for a step of <paramref name="swaps"/> swaps (the mac's everyStopPoint(swaps:)).</summary>
    internal static List<string> EveryStopPoint(int swaps)
    {
        var points = new List<string> { "afterBegin", "afterTheCheck", "afterUndoing", "afterRedoing" };
        for (int index = 0; index < swaps; index++)
        {
            string at = "@" + index.ToString(CultureInfo.InvariantCulture);
            points.Add("beforeSwap" + at);
            points.Add("relinkStaged" + at);
            points.Add("relinkRenamedIn" + at);
        }
        points.AddRange(["beforeApplied", "beforeUndone", "beforeRedone", "whileDeletingAFolder"]);
        return points;
    }

    /// <summary>
    /// The kill table. <paramref name="shapes"/> and <paramref name="leads"/>
    /// (<c>in</c>, <c>out</c>) choose a part, comma-separated, or <c>all</c>;
    /// <paramref name="teachers"/> also runs the teacher's-item rows.
    /// </summary>
    internal static int RelinkChainKill(string folder, string shapes, string leads, string teachers)
    {
        int failures = 0;
        var counts = new List<string>();
        string[] chosen = shapes == "all" ? Shapes : shapes == "none" ? [] : shapes.Split(',');
        string[] leadsChosen = leads == "all" ? ["in", "out"] : leads.Split(',');
        foreach (string lead in leadsChosen)
        {
            bool leadingOut = lead == "out";
            foreach (string shape in chosen)
            {
                string wholeRun = Path.Combine(folder, "whole-" + shape + "-" + lead);
                Laid laid = Lay(wholeRun, shape, leadingOut);
                string before = W8bRuns.Snapshot(wholeRun);
                UndoOutcome made = List(wholeRun).Door().Perform(laid.Draft);
                string after = W8bRuns.Snapshot(wholeRun);
                Console.WriteLine($"RESULT w8b-relink-chain-kill whole {shape} {lead} made=[{made.Word}] before=[{before}] after=[{after}]");
                if (made.Kind != UndoOutcomeKind.Applied || before == after) { failures++; Console.WriteLine($"RESULT w8b-relink-chain-kill {shape} {lead} whole: NOT-MADE"); continue; }
                if (!leadingOut) failures += Control(wholeRun, shape, before, after);
                int shapeReached = 0;
                int shapeExpected = 0;
                int shapeNotWhole = 0;
                foreach (string work in new[] { "apply", "undo", "redo" })
                {
                    int expected = work == "apply" ? 2 + laid.Swaps + 2 * laid.Relinks : 3 + laid.Swaps + 2 * laid.Relinks;
                    int reached = 0;
                    foreach (string point in EveryStopPoint(laid.Swaps))
                    {
                        string run = Path.Combine(folder, shape + "-" + lead + "-" + work + "-" + point.Replace('@', '-'));
                        KillOne one = KillAt(run, shape, leadingOut, work, point, before, after, layTheTeachers: null);
                        if (!one.Reached) continue;
                        reached++;
                        Console.WriteLine($"RESULT w8b-relink-chain-kill {shape} {work} {point}: {(one.Whole ? "WHOLE" : "NOT-WHOLE")} {one.States}");
                        if (!one.Whole) { failures++; shapeNotWhole++; }
                    }
                    if (reached != expected)
                    {
                        failures++;
                        Console.WriteLine($"RESULT w8b-relink-chain-kill {shape} {lead} {work} REACHED-WRONG reached={reached} expected={expected}");
                    }
                    shapeReached += reached;
                    shapeExpected += expected;
                }
                counts.Add($"{shape}/{lead}={shapeReached} of {shapeExpected} notWhole={shapeNotWhole}");
            }
        }
        if (teachers != "no") failures += TeachersItems(folder, counts, teachers);
        Console.WriteLine("RESULT w8b-relink-chain-kill counts " + string.Join(" ; ", counts));
        Console.WriteLine($"RESULT w8b-relink-chain-kill done failures={failures}");
        return failures == 0 ? 0 : 1;
    }

    /// <summary>
    /// The comparison's own check: the after state with one link given a
    /// different text that leads to the same place (`.\` in front) must read
    /// as neither state. A snapshot that follows links reads it as after.
    /// </summary>
    private static int Control(string wholeRun, string shape, string before, string after)
    {
        string? changed = null;
        foreach (string entry in Directory.EnumerateFileSystemEntries(Full(wholeRun, Section)))
        {
            if (UndoLinks.Look(entry) != UndoLinks.What.Link || new FileInfo(entry).LinkTarget is not { } text || Path.IsPathRooted(text)) continue;
            File.Delete(entry);
            File.CreateSymbolicLink(entry, @".\" + text);
            changed = Path.GetFileName(entry);
            break;
        }
        string now = W8bRuns.Snapshot(wholeRun);
        bool caught = changed is not null && now != after && now != before;
        Console.WriteLine($"RESULT w8b-relink-chain-kill control {shape} {changed}: {(caught ? "CAUGHT" : "NOT-CAUGHT")}");
        return caught ? 0 : 1;
    }

    private sealed record KillOne(bool Reached, bool Whole, string States, string Now);

    /// <summary>
    /// The side and phase a kill of a chain of relinks alone must settle to
    /// (window E review 2, LOW 1), as <c>state/phase</c>; null where either
    /// settled side is accepted. Each relink's just-made link is the one
    /// recovery removes (the LAST that passes, review D), so a work killed
    /// before its close goes back to where it started: an apply to before,
    /// failed while no swap has renamed anything in (afterBegin, the first
    /// beforeSwap and relinkStaged), rolled back after; an Undo to after
    /// (done); a Redo to before (undone). A work killed at its close
    /// (beforeApplied, beforeUndone, beforeRedone) is finished. These are
    /// 21b3's rows for the same chain (<c>AKilledChainRemovesExactlyTheOneLinkTheRuleNames</c>).
    /// The FIRST that passes settles some of them on the other side, which
    /// the either-side check could not tell apart.
    /// </summary>
    internal static string? MustSettleTo(string shape, string work, string point)
    {
        if (shape is not ("twoChainedRelinks" or "threeChainedRelinks" or "fourChainedRelinks")) return null;
        if (point is "beforeApplied" or "beforeRedone") return "after/Done";
        if (point == "beforeUndone") return "before/Undone";
        return work switch
        {
            "apply" => point is "afterBegin" or "beforeSwap@0" or "relinkStaged@0" ? "before/Failed" : "before/RolledBack",
            "undo" => "after/Done",
            _ => "before/Undone",
        };
    }

    /// <summary>One kill: lay, set up the work, run the child to <paramref name="point"/>, lay the teacher's item if asked, kill, recover, judge.</summary>
    private static KillOne KillAt(string run, string shape, bool leadingOut, string work, string point, string before, string after, Action<string>? layTheTeachers)
    {
        Laid laid = Lay(run, shape, leadingOut);
        string setUp = "none";
        if (work != "apply")
        {
            UndoForThisProcess list = List(run);
            setUp = list.Door().Perform(laid.Draft).Word;
            if (work == "redo") setUp += "," + list.Door().Undo().Word;
        }
        string said = W8bRuns.Child(["child-w8b-relink-chain", run, shape, leadingOut ? "out" : "in", work, point], kill: true,
                                    beforeTheKill: layTheTeachers is null ? null : () => layTheTeachers(run));
        if (!said.StartsWith("AT ", StringComparison.Ordinal)) return new KillOne(false, false, "", "");
        string recovered = W8bRuns.Child(["child-w8b-handover-recover", run], kill: false);
        string now = W8bRuns.Snapshot(run);
        int staged = W8bRuns.Staged(run);
        UndoFoldedStep? step = List(run).Journal.Read().Folded.Steps.Values.LastOrDefault();
        string state = now == before ? "before" : now == after ? "after" : "NEITHER";
        bool settled = step is not null && !step.IsInFlight && state switch
        {
            "after" => step.State == UndoStepState.Done,
            "before" => work == "apply" ? step.State is UndoStepState.Failed or UndoStepState.RolledBack : step.State == UndoStepState.Undone,
            _ => false,
        };
        // Where the rule decides the side (window E review 2, LOW 1), the
        // kill must settle to exactly that side and phase, not either one.
        string? mustSettle = MustSettleTo(shape, work, point);
        string settledAs = state + "/" + (step?.State.ToString() ?? "none");
        bool asTheRuleSays = mustSettle is null || mustSettle == settledAs;
        bool whole = state != "NEITHER" && staged == 0 && settled && asTheRuleSays;
        string states = $"setUp=[{setUp}] recovered=[{recovered}] step={step?.State.ToString() ?? "none"} state={state} staged={staged}" +
                        (asTheRuleSays ? "" : $" mustSettle={mustSettle}") +
                        (whole ? "" : " now=[" + now + "]");
        return new KillOne(true, whole, states, now);
    }

    /// <summary>
    /// A teacher's own page or link laid under a relink's staged name while
    /// the child is parked at beforeSwap@0, then the kill: after recovery it
    /// is found once, under a visible name (given back or kept by Undo), not
    /// hidden; nothing staged; the pages the links lead to untouched.
    /// twoChainedRelinks: going forward (apply, redo) beside Day 6 (only a
    /// relink names it) and Day 5 (two relinks name it); going back (undo)
    /// beside Day 4 and Day 5. Window E review 1: aRelinkIntoADayAPageLeaves,
    /// a teacher's page beside Day 5 going forward (apply), Day 5 being the
    /// relink's to and the plain page move's from.
    /// <paramref name="which"/> is <c>yes</c> (every row) or one shape's name.
    /// </summary>
    private static int TeachersItems(string folder, List<string> counts, string which)
    {
        int failures = 0;
        int rows = 0;
        var table = new List<(string Shape, string Work, int Day, string Kind)>();
        foreach (string work in new[] { "apply", "undo", "redo" })
        {
            int[] days = work == "undo" ? new[] { 4, 5 } : new[] { 6, 5 };
            foreach (int day in days)
            {
                foreach (string kind in new[] { "page", "link" }) table.Add(("twoChainedRelinks", work, day, kind));
            }
        }
        table.Add(("aRelinkIntoADayAPageLeaves", "apply", 5, "page"));
        string? laidShape = null;
        string before = "", after = "";
        foreach ((string shape, string work, int day, string kind) in table)
        {
            if (which != "yes" && which != shape) continue;
            if (laidShape != shape)
            {
                string wholeRun = Path.Combine(folder, "whole-teachers-" + shape);
                Laid laid = Lay(wholeRun, shape, false);
                before = W8bRuns.Snapshot(wholeRun);
                List(wholeRun).Door().Perform(laid.Draft);
                after = W8bRuns.Snapshot(wholeRun);
                laidShape = shape;
            }
            rows++;
            string run = Path.Combine(folder, "teachers-" + shape + "-" + work + "-" + day + "-" + kind);
            string hiddenName = "." + Path.GetFileName(Day(day)) + UndoSwap.StagedMarker + "1-" + work + "-new";
            void LayIt(string where)
            {
                string at = Path.Combine(Full(where, Section), hiddenName);
                if (kind == "page") File.WriteAllBytes(at, Bytes("Teacher's own.\n"));
                else File.CreateSymbolicLink(at, "Someone's.md");
            }
            KillOne one = KillAt(run, shape, false, work, "beforeSwap@0", before, after, LayIt);
            string mark = kind == "page" ? "page Teacher's own.\\n" : "link Someone's.md";
            var found = new List<string>();
            bool hidden = false;
            foreach (string part in one.Now.Split(" | "))
            {
                if (!part.EndsWith(": " + mark, StringComparison.Ordinal)) continue;
                string name = part[(part.IndexOf('/') + 1)..part.LastIndexOf(": ", StringComparison.Ordinal)];
                found.Add(name);
                string at = Path.Combine(Full(run, Section), name);
                if (name.StartsWith('.') || (File.GetAttributes(at) & FileAttributes.Hidden) != 0) hidden = true;
            }
            bool targetsUntouched = one.Now.Contains("section1/Unit 1, Day 1.md: page One.\\n", StringComparison.Ordinal)
                                    && one.Now.Contains("section1/Unit 1, Day 2.md: page Two.\\n", StringComparison.Ordinal);
            bool kept = one.Reached && found.Count == 1 && !hidden && W8bRuns.Staged(run) == 0 && targetsUntouched;
            Console.WriteLine($"RESULT w8b-relink-chain-kill teachers {shape} {work} Day{day} {kind} beforeSwap@0: {(kept ? "KEPT" : "NOT-KEPT")} at=[{string.Join(",", found)}] {one.States} now=[{one.Now}]");
            if (!kept) failures++;
        }
        counts.Add($"teachers={rows} rows failures={failures}");
        return failures;
    }

    /// <summary>The working child: lays nothing, makes the step, its Undo or its Redo through a door that stops at <paramref name="point"/>.</summary>
    internal static int ChildChain(string run, string shape, string lead, string work, string point)
    {
        Console.WriteLine("STARTED");
        Console.Out.Flush();
        UndoForThisProcess list = List(run);
        var door = new UndoDoor(list.Journal, list.Mode, list.Maintainers, W8bRuns.StopAt(point));
        UndoOutcome outcome = work switch
        {
            "undo" => door.Undo(),
            "redo" => door.Redo(),
            _ => door.Perform(DraftOnly(run, shape, lead == "out")),
        };
        Console.WriteLine("DONE " + outcome.Word);
        return 0;
    }

    /// <summary>The step's draft for a run already laid (an apply's child), laying nothing.</summary>
    private static UndoOpsDraft DraftOnly(string run, string shape, bool leadingOut) => Lay(run, shape, leadingOut, layingFiles: false).Draft;
}
