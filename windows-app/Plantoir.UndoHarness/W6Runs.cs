using System.Diagnostics;
using System.Globalization;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Plantoir.Core.Undo;

// #899 W6: every op kind U2b defines, made, undone and redone by a child
// process killed at every step, then recovered by a second process (and once
// with that recovery itself killed part way and a third recovering), outside
// and inside OneDrive (vm-tools/reference/899-w6-plan.md). Every result is one
// line starting RESULT. In no solution: the unit suite never builds it.

namespace Plantoir.UndoHarness;

internal static class W6Runs
{
    private static string Exe => Environment.ProcessPath!;

    private const string Page1 = "courses/TST1O/Section 1/Classes/first.md";
    private const string Page2 = "courses/TST1O/Section 1/Classes/second.md";
    private const string Notes = "courses/TST1O/notes.md";
    private const string Settings = "courses/TST1O/settings.json";
    private const string Removed = "courses/TST1O/extra";
    private const string Made = "courses/TST1O/made";
    private const string MarkerFrom = "courses/TST1O/.netlify_sites/section1.json";
    private const string MarkerTo = "courses/TST1O/.netlify_sites/section1.previous.json";
    private const string Preference = "preference:undoCasesPreference";

    private static byte[] Page(string title, bool published) => Encoding.UTF8.GetBytes($"---\ntitle: {title}\npublish: {(published ? "true" : "false")}\n---\nThe lesson.\n");
    private static readonly byte[] NotesBefore = "Intro.\nLine one: old.\nEnd.\n"u8.ToArray();
    private static readonly byte[] NotesAfter = "Intro.\nLine one: new.\nEnd.\n"u8.ToArray();
    private static readonly byte[] SettingsBefore = "{\n  \"course_name\" : \"Test\",\n  \"school_year\" : \"2025-2026\"\n}\n"u8.ToArray();
    private static readonly byte[] SettingsAfter = "{\n  \"course_name\" : \"Test\",\n  \"school_year\" : \"2026-2027\"\n}\n"u8.ToArray();
    private static readonly byte[] Marker = "{\"site_id\": \"aaa-111\"}\n"u8.ToArray();
    private static readonly (string Path, byte[] Bytes)[] RemovedFiles = [("a.md", "A\n"u8.ToArray()), ("sub/b.md", "B\n"u8.ToArray())];
    private static readonly (string Path, byte[] Bytes)[] MadeFiles = [("index.md", "# New\n"u8.ToArray()), ("Classes/day1.md", "Day 1\n"u8.ToArray())];

    private static string Root(string run) => Path.Combine(run, "wf");
    private static string Full(string run, string relative) => UndoDoor.FullPath(Root(run), relative);

    private static UndoJournal Journal(string run) =>
        new(Path.Combine(run, "undo"), TimeProvider.System, UndoJournalChecks.ProcessIsAlive,
            step => UndoJournalChecks.FolderIsReachable(step, TimeProvider.System), isLive: true, memory: new UndoProcessMemory());

    /// <summary>A preference store on the disk, so a value set by one process is read by the next: one JSON object, replaced whole.</summary>
    private sealed class FilePlaces(string file) : IUndoExternalPlaces
    {
        public UndoExternalReading Read(string target)
        {
            try
            {
                using JsonDocument document = JsonDocument.Parse(File.ReadAllBytes(file));
                return document.RootElement.TryGetProperty(target, out JsonElement value) && UndoJson.From(value) is { } read
                    ? UndoExternalReading.Holding(read)
                    : UndoExternalReading.Unset;
            }
            catch (FileNotFoundException) { return UndoExternalReading.Unset; }
            catch (Exception error) when (error is IOException or JsonException) { return UndoExternalReading.Unknown; }
        }

        public bool Write(string target, UndoJson? value)
        {
            var all = new JsonObject();
            try
            {
                if (File.Exists(file)) all = JsonNode.Parse(File.ReadAllBytes(file))!.AsObject();
                if (value is null) all.Remove(target);
                else all[target] = JsonNode.Parse(value.Spelled()!);
                string temporary = file + ".tmp";
                File.WriteAllText(temporary, all.ToJsonString());
                File.Move(temporary, file, overwrite: true);
                return true;
            }
            catch (Exception error) when (error is IOException or JsonException or UnauthorizedAccessException) { return false; }
        }
    }

    private static FilePlaces Places(string run) => new(Path.Combine(run, "prefs.json"));

    private static void Write(string run, string relative, byte[] bytes)
    {
        string path = Full(run, relative);
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllBytes(path, bytes);
    }

    private static UndoTreeListing Listing((string Path, byte[] Bytes)[] files) =>
        new(files.Select(file => file.Path).Where(path => path.Contains('/')).Select(path => path[..path.LastIndexOf('/')]).Distinct().ToList(),
            files.Select(file => (file.Path, UndoCheck.Sha(file.Bytes))).ToList());

    /// <summary>The working folder before the step: two pages, a page with a hunk, a settings file, a folder to remove, a marker, a preference.</summary>
    private static void MakeTheFolder(string run)
    {
        Directory.CreateDirectory(Path.Combine(Root(run), "courses", ".internal"));
        Write(run, Page1, Page("first", false));
        Write(run, Page2, Page("second", false));
        Write(run, Notes, NotesBefore);
        Write(run, Settings, SettingsBefore);
        foreach ((string path, byte[] bytes) in RemovedFiles) Write(run, Removed + "/" + path, bytes);
        Write(run, MarkerFrom, Marker);
        Places(run).Write(Preference, new UndoJson.Text("a"));
    }

    /// <summary>One step holding every kind: two pages' lines, a hunk, a member, a preference, a folder removed, a folder made, a marker moved (8 swaps).</summary>
    private static UndoOpsDraft TheStep(string run)
    {
        var ops = new JsonArray();
        foreach ((string path, string title) in new[] { (Page1, "first"), (Page2, "second") })
        {
            foreach (JsonNode? op in UndoLineOps.ForAFile(path, Page(title, false), Page(title, true))) ops.Add(op!.DeepClone());
        }
        ops.Add(new JsonObject { ["kind"] = "replaceText", ["path"] = Notes, ["before"] = "old", ["after"] = "new", ["contextBefore"] = "Line one: ", ["contextAfter"] = ".\n" });
        ops.Add(new JsonObject { ["kind"] = "editJSON", ["path"] = Settings, ["keyPath"] = new JsonArray("school_year"), ["before"] = "2025-2026", ["after"] = "2026-2027" });
        ops.Add(new JsonObject { ["kind"] = "external", ["target"] = Preference, ["before"] = "a", ["after"] = "b" });
        var blobs = new List<byte[]>();
        foreach ((string kind, string path, (string Path, byte[] Bytes)[] files) in new[] { ("removeTree", Removed, RemovedFiles), ("createTree", Made, MadeFiles) })
        {
            UndoTreeListing listing = Listing(files);
            var names = new JsonArray(listing.Sha);
            blobs.Add(listing.Bytes);
            foreach ((_, byte[] bytes) in files)
            {
                names.Add(UndoCheck.Sha(bytes));
                blobs.Add(bytes);
            }
            ops.Add(new JsonObject { ["kind"] = kind, ["path"] = path, ["listingSha"] = listing.Sha, ["blobs"] = names });
        }
        ops.Add(new JsonObject { ["kind"] = "move", ["from"] = MarkerFrom, ["to"] = MarkerTo, ["sha"] = UndoCheck.Sha(Marker) });
        return new UndoOpsDraft
        {
            ActionKey = "rollOver", MadeBy = "menu", WorkingFolder = Root(run), Course = "TST1O", Section = 1, Holds = "section", Ops = ops, Blobs = blobs,
        };
    }

    /// <summary>Where every place of the step stands: before, after, or neither (torn or changed), by kind.</summary>
    private static Dictionary<string, string> Places(string run, IUndoExternalPlaces places)
    {
        string Of(bool before, bool after) => before ? "before" : after ? "after" : "NEITHER";
        byte[]? Read(string relative) => File.Exists(Full(run, relative)) ? File.ReadAllBytes(Full(run, relative)) : null;
        bool Same(byte[]? a, byte[] b) => a is not null && a.AsSpan().SequenceEqual(b);
        string? removed = UndoTreeReading.Read(Full(run, Removed)).ListingSha;
        string? made = UndoTreeReading.Read(Full(run, Made)).ListingSha;
        UndoExternalReading preference = places.Read(Preference);
        return new Dictionary<string, string>(StringComparer.Ordinal)
        {
            ["page1"] = Of(Same(Read(Page1), Page("first", false)), Same(Read(Page1), Page("first", true))),
            ["page2"] = Of(Same(Read(Page2), Page("second", false)), Same(Read(Page2), Page("second", true))),
            ["hunk"] = Of(Same(Read(Notes), NotesBefore), Same(Read(Notes), NotesAfter)),
            ["member"] = Of(Same(Read(Settings), SettingsBefore), Same(Read(Settings), SettingsAfter)),
            ["preference"] = Of(preference.Matches(new UndoJson.Text("a")), preference.Matches(new UndoJson.Text("b"))),
            ["removeTree"] = Of(removed == Listing(RemovedFiles).Sha, removed is null && !Directory.Exists(Full(run, Removed))),
            ["createTree"] = Of(made is null && !Directory.Exists(Full(run, Made)), made == Listing(MadeFiles).Sha),
            ["move"] = Of(Same(Read(MarkerFrom), Marker) && Read(MarkerTo) is null, Read(MarkerFrom) is null && Same(Read(MarkerTo), Marker)),
        };
    }

    /// <summary>
    /// The run: for each work (apply, undo, redo) and each kill point (the
    /// work's begin, before each of the 8 swaps, while a folder taken out is
    /// being deleted, before its closing), a child does the work and is
    /// killed there; then (A) a second process recovers, or (B) the recovery
    /// is killed before its first put-back swap and a third recovers. After
    /// the last recovery every place must be wholly before or wholly after,
    /// all one way, the way the list says the step stands, nothing staged
    /// left, the step out of flight; A and B must agree.
    /// </summary>
    internal static int KindsKill(string folder)
    {
        var points = new List<string>();
        foreach (string work in new[] { "apply", "undo", "redo" })
        {
            points.Add(work + ":" + (work == "apply" ? "afterBegin" : work == "undo" ? "afterUndoing" : "afterRedoing"));
            for (int index = 0; index < 8; index++) points.Add(work + ":beforeSwap@" + index.ToString(CultureInfo.InvariantCulture));
            points.Add(work + ":whileDeletingAFolder");
            points.Add(work + ":" + (work == "apply" ? "beforeApplied" : work == "undo" ? "beforeUndone" : "beforeRedone"));
        }
        int failures = 0;
        foreach (string point in points)
        {
            var answers = new Dictionary<string, string>(StringComparer.Ordinal);
            foreach (string variant in new[] { "A", "B" })
            {
                string run = Path.Combine(folder, point.Replace(':', '-').Replace('@', '-') + "-" + variant);
                MakeTheFolder(run);
                string work = point[..point.IndexOf(':')];
                if (work is "undo" or "redo")
                {
                    UndoOutcome made = new UndoDoor(Journal(run), UndoMode.Live, places: Places(run)).Perform(TheStep(run));
                    bool ready = made.Kind == UndoOutcomeKind.Applied
                                 && (work == "undo" || new UndoDoor(Journal(run), UndoMode.Live, places: Places(run)).Undo().Kind == UndoOutcomeKind.Undone);
                    if (!ready) { Console.WriteLine($"RESULT kinds-kill {point} setup {made.Word}"); failures++; continue; }
                }
                var clock = Stopwatch.StartNew();
                string said = Child(["child-kinds", run, point], kill: true);
                string afterTheKill = StateOfTheStep(run);
                bool recoveryKilled = false;
                if (variant == "B") recoveryKilled = Child(["child-kinds-recover", run, "recoveryBeforeSwap@0"], kill: true).StartsWith("AT ", StringComparison.Ordinal);
                string recovered = Child(["child-kinds-recover", run, "none"], kill: false);
                UndoJournal journal = Journal(run);
                UndoReading reading = journal.Read();
                UndoFoldedStep step = reading.Folded.Steps[1];
                Dictionary<string, string> places = Places(run, Places(run));
                string expected = step.State == UndoStepState.Done ? "after" : "before";
                bool allOneWay = places.Values.All(value => value == expected);
                int staged = Directory.EnumerateFileSystemEntries(Root(run), "*", SearchOption.AllDirectories)
                    .Count(entry => Path.GetFileName(entry).Contains(UndoSwap.StagedMarker, StringComparison.Ordinal));
                bool consistent = allOneWay && staged == 0 && !step.IsInFlight && reading.IsFresh;
                string answer = $"state={step.State} places={expected}";
                answers[variant] = answer;
                Console.WriteLine($"RESULT kinds-kill point={point} variant={variant} child=[{said}] afterTheKill={afterTheKill} recoveryKilled={recoveryKilled} " +
                                  $"recovered=[{recovered}] {answer} {string.Join(",", places.Select(pair => pair.Key + "=" + pair.Value))} staged={staged} " +
                                  $"ms={clock.Elapsed.TotalMilliseconds.ToString("0", CultureInfo.InvariantCulture)} {(consistent ? "WHOLE" : "NOT-WHOLE")}");
                if (!consistent) failures++;
            }
            if (answers.Count == 2)
            {
                bool same = answers["A"] == answers["B"];
                Console.WriteLine($"RESULT kinds-same point={point} {(same ? "SAME" : "DIFFERENT")} A[{answers["A"]}] B[{answers["B"]}]");
                if (!same) failures++;
            }
        }
        Console.WriteLine($"RESULT kinds-kill total={points.Count * 2} failures={failures}");
        return failures == 0 ? 0 : 1;
    }

    private static string StateOfTheStep(string run) =>
        Journal(run).Read().Folded.Steps.TryGetValue(1, out UndoFoldedStep? step) ? step.State.ToString() : "none";

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

    /// <summary>The working child: makes, undoes or redoes the step, and at its point says so and waits to be killed.</summary>
    internal static int ChildKinds(string run, string point)
    {
        Console.WriteLine("STARTED");
        Console.Out.Flush();
        string work = point[..point.IndexOf(':')];
        var door = new UndoDoor(Journal(run), UndoMode.Live, seams: StopAt(point[(point.IndexOf(':') + 1)..]), places: Places(run));
        UndoOutcome outcome = work switch
        {
            "undo" => door.Undo(),
            "redo" => door.Redo(),
            _ => door.Perform(TheStep(run)),
        };
        Console.WriteLine("DONE " + outcome.Word);
        return 0;
    }

    /// <summary>The recovering child: the app's recovery, as a process that sees the killed one as gone; stopped at <paramref name="at"/> when it gets there.</summary>
    internal static int ChildKindsRecover(string run, string at)
    {
        Console.WriteLine("STARTED");
        Console.Out.Flush();
        var clock = Stopwatch.StartNew();
        UndoRecoveryRun recovered = new UndoDoor(Journal(run), UndoMode.Live, seams: at == "none" ? null : StopAt(at), places: Places(run)).Recover();
        string settled = string.Join(",", recovered.Settled.Select(result => $"{result.Seq}:{result.Outcome}:{result.FilesPutBack}"));
        Console.WriteLine($"DONE {clock.Elapsed.TotalMilliseconds.ToString("0", CultureInfo.InvariantCulture)}ms {settled}{(recovered.NotRun is { } why ? " notRun " + why : "")}");
        Console.Out.Flush();
        return 0;
    }
}
