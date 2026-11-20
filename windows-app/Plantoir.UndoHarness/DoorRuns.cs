using System.Diagnostics;
using System.Globalization;
using System.Text;
using Plantoir.Core.Undo;

// #899 W2b: the door and the staged swap against real processes, and the
// swap's measurements, outside and inside OneDrive
// (vm-tools/reference/899-w2b-plan.md). Every result is one line starting
// RESULT. In no solution: the unit suite never builds it.

namespace Plantoir.UndoHarness;

internal static class DoorRuns
{
    private static string Exe => Environment.ProcessPath!;
    private static string Ms(double value) => value.ToString("0.0", CultureInfo.InvariantCulture);
    private static double Median(List<double> values) { values.Sort(); return values.Count == 0 ? 0 : values[values.Count / 2]; }

    private static byte[] OldPage(int number) => Encoding.UTF8.GetBytes($"---\ntitle: Day {number}\npublish: false\n---\nThe lesson for day {number}.\n");
    private static byte[] NewPage(int number) => Encoding.UTF8.GetBytes($"---\ntitle: Day {number}\npublish: true\n---\nThe lesson for day {number}.\n");
    private static string PagePath(int number) => $"courses/TST1O/Section 1/Unit 1/Day {number}.md";

    private static UndoJournal Journal(string folder) =>
        new(Path.Combine(folder, "undo"), TimeProvider.System, UndoJournalChecks.ProcessIsAlive,
            step => UndoJournalChecks.FolderIsReachable(step, TimeProvider.System), isLive: true, memory: new UndoProcessMemory());

    private static string WorkingFolder(string folder) => Path.Combine(folder, "wf");

    private static void MakePages(string folder, int pages)
    {
        string root = WorkingFolder(folder);
        Directory.CreateDirectory(Path.Combine(root, "courses", ".internal"));
        for (int number = 1; number <= pages; number++)
        {
            string path = UndoDoor.FullPath(root, PagePath(number));
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            File.WriteAllBytes(path, OldPage(number));
        }
    }

    private static UndoStepDraft Publish(string folder, int pages)
    {
        var changes = new List<UndoFileChange>();
        for (int number = 1; number <= pages; number++) changes.Add(new UndoFileChange(PagePath(number), OldPage(number), NewPage(number)));
        return new UndoStepDraft
        {
            ActionKey = "publishPages", MadeBy = "menu", WorkingFolder = WorkingFolder(folder), Course = "TST1O", Section = 1, Holds = "section",
            ActionArguments = new Dictionary<string, string>(StringComparer.Ordinal) { ["pageCount"] = pages.ToString(CultureInfo.InvariantCulture) },
            Changes = changes,
        };
    }

    // ---- door-kill: a child making (or undoing) a step, killed at a point ----

    /// <summary>
    /// The two-process test: a CHILD process makes a step of <paramref name="pages"/>
    /// pages through the real door (or undoes one) and is killed with
    /// <see cref="Process.Kill(bool)"/> at each point; this process then reads
    /// every page (each must be wholly the old or wholly the new bytes), counts
    /// the staged files left and under which step, and reads what the journal
    /// says. Nothing settles the step afterwards: that is W3's recovery.
    /// </summary>
    internal static int Kill(string folder, int pages)
    {
        string[] points = ["apply:afterBegin", "apply:beforeSwap@mid", "apply:beforeApplied", "apply:atRandom", "undo:beforeSwap@mid", "undo:atRandom"];
        int failures = 0;
        foreach (string point in points)
        {
            string run = Path.Combine(folder, point.Replace(':', '-').Replace('@', '-'));
            MakePages(run, pages);
            bool undo = point.StartsWith("undo", StringComparison.Ordinal);
            if (undo)
            {
                UndoOutcome made = new UndoDoor(Journal(run), UndoMode.Live).Perform(Publish(run, pages));
                if (made.Kind != UndoOutcomeKind.Applied) { Console.WriteLine($"RESULT door-kill {point} setup {made.Word}"); failures++; continue; }
            }
            var start = new ProcessStartInfo(Exe) { RedirectStandardOutput = true, UseShellExecute = false };
            foreach (string arg in new[] { "child-door", run, pages.ToString(CultureInfo.InvariantCulture), point }) start.ArgumentList.Add(arg);
            using Process child = Process.Start(start)!;
            var clock = Stopwatch.StartNew();
            if (point.EndsWith("atRandom", StringComparison.Ordinal))
            {
                // Killed the moment the first page is seen changed: a real
                // moment inside the swaps, chosen by the race, not by a seam.
                string? said = child.StandardOutput.ReadLine();
                if (said != "STARTED") Console.WriteLine("child said: " + said);
                byte[] watchFor = undo ? OldPage(1) : NewPage(1);
                string first = UndoDoor.FullPath(WorkingFolder(run), PagePath(undo ? pages : 1));
                if (undo) watchFor = OldPage(pages);
                while (!child.HasExited && !Same(TryRead(first), watchFor) && clock.Elapsed < TimeSpan.FromSeconds(60)) Thread.SpinWait(200);
            }
            else
            {
                string? said = child.StandardOutput.ReadLine();
                if (said != "STARTED") Console.WriteLine("child said: " + said);
                said = child.StandardOutput.ReadLine();
                if (said is null || !said.StartsWith("AT ", StringComparison.Ordinal)) { Console.WriteLine($"RESULT door-kill {point} child said {said}"); failures++; }
            }
            bool exitedBeforeTheKill = child.HasExited;
            try { child.Kill(entireProcessTree: true); } catch (InvalidOperationException) { }
            child.WaitForExit();
            int old = 0, made2 = 0, torn = 0;
            for (int number = 1; number <= pages; number++)
            {
                byte[]? now = TryRead(UndoDoor.FullPath(WorkingFolder(run), PagePath(number)));
                if (Same(now, OldPage(number))) old++;
                else if (Same(now, NewPage(number))) made2++;
                else torn++;
            }
            var staged = Directory.EnumerateFiles(WorkingFolder(run), "*", SearchOption.AllDirectories)
                .Select(Path.GetFileName).Where(name => name!.Contains(UndoSwap.StagedMarker, StringComparison.Ordinal)).ToList();
            var stagedByStep = staged.GroupBy(name => name![(name!.IndexOf(UndoSwap.StagedMarker, StringComparison.Ordinal) + UndoSwap.StagedMarker.Length)..].Split('-')[0] + "-" +
                                                      name![(name!.IndexOf(UndoSwap.StagedMarker, StringComparison.Ordinal) + UndoSwap.StagedMarker.Length)..].Split('-')[1])
                                     .Select(group => $"{group.Key}:{group.Count()}");
            UndoReading reading = Journal(run).Read();
            string states = string.Join(",", reading.Folded.Steps.Values.Select(step => $"{step.Seq}={step.State}"));
            bool whole = torn == 0;
            Console.WriteLine($"RESULT door-kill point={point} pages={pages} exitedBeforeKill={exitedBeforeTheKill} oldPages={old} newPages={made2} tornPages={torn} staged={staged.Count} stagedBy={string.Join(",", stagedByStep)} journal={states} fresh={reading.IsFresh} killedAfterMs={Ms(clock.Elapsed.TotalMilliseconds)} {(whole ? "WHOLE-PAGES" : "TORN")}");
            if (!whole) failures++;
        }
        return failures == 0 ? 0 : 1;
    }

    /// <summary>The child of <see cref="Kill"/>: makes or undoes the step, and at its point says so and waits to be killed.</summary>
    internal static int ChildDoor(string folder, int pages, string point)
    {
        string[] parts = point.Split(':');
        string at = parts[1];
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
        Console.WriteLine("STARTED");
        Console.Out.Flush();
        var door = new UndoDoor(Journal(folder), UndoMode.Live, seams: at == "atRandom" ? null : seams);
        UndoOutcome outcome = parts[0] == "undo" ? door.Undo() : door.Perform(Publish(folder, pages));
        Console.WriteLine("DONE " + outcome.Word);
        return 0;
    }

    // ---- door-time: what a step, an undo and the swap cost --------------------

    internal static int Time(string folder, int pages, int runs)
    {
        var perform = new List<double>();
        var undo = new List<double>();
        var swapPerPage = new List<double>();
        for (int run = 0; run < runs; run++)
        {
            string place = Path.Combine(folder, $"run-{run}");
            MakePages(place, pages);
            var door = new UndoDoor(Journal(place), UndoMode.Live);
            var clock = Stopwatch.StartNew();
            UndoOutcome made = door.Perform(Publish(place, pages));
            perform.Add(clock.Elapsed.TotalMilliseconds);
            if (made.Kind != UndoOutcomeKind.Applied) { Console.WriteLine("RESULT door-time step " + made.Word); return 1; }
            clock.Restart();
            UndoOutcome undone = door.Undo();
            undo.Add(clock.Elapsed.TotalMilliseconds);
            if (undone.Kind != UndoOutcomeKind.Undone) { Console.WriteLine("RESULT door-time undo " + undone.Word); return 1; }
            // The swap alone, the pages back to new.
            var targets = new List<UndoSwapTarget>();
            for (int number = 1; number <= pages; number++)
                targets.Add(new UndoSwapTarget(UndoDoor.FullPath(WorkingFolder(place), PagePath(number)), PagePath(number), OldPage(number), NewPage(number)));
            clock.Restart();
            UndoSwapResult swapped = UndoSwap.Swap(targets, "999-redo", WorkingFolder(place));
            swapPerPage.Add(clock.Elapsed.TotalMilliseconds / pages);
            if (swapped is not UndoSwapResult.Swapped) { Console.WriteLine("RESULT door-time swap " + swapped); return 1; }
        }
        Console.WriteLine($"RESULT door-time pages={pages} runs={runs} stepMs median={Ms(Median(perform))} undoMs median={Ms(Median(undo))} swapPerPageMs median={Ms(Median(swapPerPage))} all-step={string.Join(',', perform.Select(Ms))}");
        return 0;
    }

    // ---- swap-cases: a swap onto a page in each state, in a folder -------------

    /// <summary>
    /// A swap onto a page in each state a working folder in OneDrive (or
    /// outside it, for comparison) can hold: a plain page, a page open in a
    /// program that shares delete (Obsidian), one that does not (Word), a page
    /// written a moment ago (OneDrive uploading it), and in OneDrive a page that
    /// is a cloud-only placeholder. For each: the outcome, the time, the
    /// attributes before and after, whether a hard link to it could be made.
    /// Then the folder is watched for anything OneDrive adds (conflict copies).
    /// </summary>
    internal static int SwapCases(string folder, bool inOneDrive, int placeholderWaitSeconds)
    {
        Directory.CreateDirectory(folder);
        int failures = 0;
        var initial = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        string Make(string name, byte[] bytes)
        {
            string path = Path.Combine(folder, name);
            File.WriteAllBytes(path, bytes);
            initial.Add(name);
            return path;
        }

        void One(string label, string path, byte[] expected, byte[] replacement, Func<IDisposable?>? holder = null)
        {
            FileAttributes before = File.GetAttributes(path);
            bool linkable = CanHardLink(path, out int linkError);
            using IDisposable? held = holder?.Invoke();
            var clock = Stopwatch.StartNew();
            UndoSwapResult result = UndoSwap.Swap([new UndoSwapTarget(path, Path.GetFileName(path), expected, replacement)], "1-undo", folder);
            double ms = clock.Elapsed.TotalMilliseconds;
            held?.Dispose();
            string outcome = result switch
            {
                UndoSwapResult.Swapped => "swapped",
                UndoSwapResult.Refused refused => refused.Refusal.Word,
                _ => "stopped",
            };
            byte[]? now = TryRead(path);
            string content = Same(now, replacement) ? "new" : Same(now, expected) ? "old" : "OTHER";
            int stagedLeft = Directory.EnumerateFiles(folder).Count(file => Path.GetFileName(file).Contains(UndoSwap.StagedMarker, StringComparison.Ordinal));
            Console.WriteLine($"RESULT swap-case place={(inOneDrive ? "onedrive" : "outside")} case={label} outcome={outcome} ms={Ms(ms)} content={content} hardLinkToIt={(linkable ? "ok" : "refused-" + linkError)} attributesBefore=[{before}] attributesAfter=[{SafeAttributes(path)}] stagedLeft={stagedLeft}");
            if (content == "OTHER" || stagedLeft > 0) failures++;
        }

        byte[] oldBytes = OldPage(1), newBytes = NewPage(1);
        One("plain", Make("plain.md", oldBytes), oldBytes, newBytes);
        string shared = Make("open-sharing-delete.md", oldBytes);
        One("openSharingDelete", shared, oldBytes, newBytes, () => new FileStream(shared, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete));
        string unshared = Make("open-not-sharing-delete.md", oldBytes);
        One("openNotSharingDelete", unshared, oldBytes, newBytes, () => new FileStream(unshared, FileMode.Open, FileAccess.Read, FileShare.ReadWrite));
        byte[] large = new byte[4 * 1024 * 1024];
        new Random(899).NextBytes(large);
        byte[] largeNew = [.. large, 1, 2, 3];
        One("justWritten4MB", Make("just-written.md", large), large, largeNew);

        if (inOneDrive)
        {
            // A cloud-only placeholder: written, then unpinned so OneDrive frees
            // it once uploaded (Files On Demand), waited for until its data is
            // no longer on the disk (RECALL_ON_DATA_ACCESS) or the wait runs out.
            string cloud = Make("cloud-only.md", oldBytes);
            const FileAttributes Pinned = (FileAttributes)0x00080000, Unpinned = (FileAttributes)0x00100000, Recall = (FileAttributes)0x00400000;
            File.SetAttributes(cloud, (File.GetAttributes(cloud) & ~Pinned) | Unpinned);
            var waited = Stopwatch.StartNew();
            while (!File.GetAttributes(cloud).HasFlag(Recall) && waited.Elapsed < TimeSpan.FromSeconds(placeholderWaitSeconds)) Thread.Sleep(1000);
            bool isPlaceholder = File.GetAttributes(cloud).HasFlag(Recall);
            Console.WriteLine($"RESULT placeholder made={isPlaceholder} afterMs={Ms(waited.Elapsed.TotalMilliseconds)} attributes=[{SafeAttributes(cloud)}]");
            One(isPlaceholder ? "cloudOnlyPlaceholder" : "unpinnedNotYetFreed", cloud, oldBytes, newBytes);
        }

        // Anything OneDrive adds beside the pages (a conflict copy, a stray staged name).
        Thread.Sleep(TimeSpan.FromSeconds(inOneDrive ? 60 : 1));
        var extra = Directory.EnumerateFileSystemEntries(folder).Select(Path.GetFileName).Where(name => !initial.Contains(name!)).ToList();
        Console.WriteLine($"RESULT swap-watch place={(inOneDrive ? "onedrive" : "outside")} extraEntries={extra.Count} {string.Join(" | ", extra)}");
        if (extra.Count > 0) failures++;
        return failures == 0 ? 0 : 1;
    }

    private static string SafeAttributes(string path)
    {
        try { return File.GetAttributes(path).ToString(); }
        catch (Exception error) { return "unreadable " + error.GetType().Name; }
    }

    private static bool CanHardLink(string path, out int error)
    {
        string link = path + ".linkprobe";
        error = 0;
        int? failed = UndoSwap.Keep(path, link);
        bool linked = failed is null && File.Exists(link);
        // Keep copies where it cannot link; whether it LINKED is what is asked: a link shares the file's index.
        if (linked)
        {
            using var a = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
            using var b = new FileStream(link, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
            linked = Equals(UndoFileIdentity.Of(a), UndoFileIdentity.Of(b));
            if (!linked) error = -1;   // copied, not linked
        }
        else error = failed ?? 0;
        try { File.Delete(link); } catch { }
        return linked;
    }

    private static byte[]? TryRead(string path)
    {
        try
        {
            using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
            using var memory = new MemoryStream();
            stream.CopyTo(memory);
            return memory.ToArray();
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException) { return null; }
    }

    private static bool Same(byte[]? a, byte[]? b) => a is null ? b is null : b is not null && a.AsSpan().SequenceEqual(b);
}
