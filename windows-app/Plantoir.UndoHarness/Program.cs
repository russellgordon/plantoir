using System.Diagnostics;
using System.Globalization;
using System.Text;
using System.Text.Json.Nodes;
using Plantoir.Core.Undo;

// #899 W2a: the two-process lock test and the measurements, run by hand on a
// real PC (vm-tools/reference/899-w2a-plan.md, "Measured on the PC"). Every
// result is one line starting RESULT, so a log can be read by a script.
// In no solution: the unit suite never builds it.

namespace Plantoir.UndoHarness;

internal static class Program
{
    private static int Main(string[] args)
    {
        if (args.Length < 2) { Console.WriteLine("usage: <mode> <folder> ..."); return 2; }
        string mode = args[0];
        string folder = args[1];
        try
        {
            return mode switch
            {
                "contend" => Contend(folder, Int(args[2]), Int(args[3]), Int(args[4]), args[5] == "1"),
                "child-contend" => ChildContend(folder, Int(args[2]), Int(args[3]), args[4] == "1", long.Parse(args[5], CultureInfo.InvariantCulture)),
                "killed" => Killed(folder, Int(args[2])),
                "child-hold" => ChildHold(folder),
                "child-wait" => ChildWait(folder, Int(args[2])),
                "flush" => Flush(folder, Int(args[2])),
                "read" => ReadSizes(folder),
                "blobs" => Blobs(folder, Int(args[2]), 1) + Blobs(folder + "-p4", Int(args[2]), 4) + Blobs(folder + "-p8", Int(args[2]), 8) + BlobParts(folder + "-parts", Int(args[2])),
                "onedrive" => OneDriveWatch(folder, Int(args[2])),
                "door-kill" => DoorRuns.Kill(folder, Int(args[2])),
                "child-door" => DoorRuns.ChildDoor(folder, Int(args[2]), args[3]),
                "recovery-kill" => DoorRuns.RecoveryKill(folder, Int(args[2])),
                "child-recover" => DoorRuns.ChildRecover(folder, args[2]),
                "door-time" => DoorRuns.Time(folder, Int(args[2]), Int(args[3])),
                "swap-cases" => DoorRuns.SwapCases(folder, args[2] == "1", Int(args[3])),
                "w4-seed" => W4Runs.Seed(folder, args[2], args[3], Int(args[4])),
                "child-w4" => W4Runs.Child(folder, args[2], args[3], Int(args[4])),
                "w4-read" => W4Runs.Read(folder, args[2], Int(args[3])),
                "kinds-kill" => W6Runs.KindsKill(folder),
                "child-kinds" => W6Runs.ChildKinds(folder, args[2]),
                "child-kinds-recover" => W6Runs.ChildKindsRecover(folder, args[2]),
                "w7-publish-kill" => W7Runs.PublishKill(folder),
                "child-w7-publish" => W7Runs.ChildPublish(folder, args[2], args[3]),
                "child-w7-recover" => W7Runs.ChildRecover(folder, args[2]),
                "w7-add-classes-kill" => W7Runs.AddClassesKill(folder),
                "child-w7-add-classes" => W7Runs.ChildAddClasses(folder, args[2], args[3]),
                "w7-plain-kill" => W7Runs.PlainKill(folder),
                "child-w7-plain" => W7Runs.ChildPlain(folder, args[2], args[3]),
                _ => Unknown(mode),
            };
        }
        catch (Exception error)
        {
            Console.WriteLine("RESULT error " + error.GetType().Name + ": " + error.Message.Replace('\n', ' '));
            return 1;
        }
    }

    private static int Unknown(string mode) { Console.WriteLine("unknown mode " + mode); return 2; }

    private static int Int(string text) => int.Parse(text, CultureInfo.InvariantCulture);

    private static UndoJournal Journal(string folder, UndoProcessMemory? memory = null, TimeSpan? readRetry = null) =>
        new(folder, TimeProvider.System, _ => true, _ => true, isLive: false, memory: memory ?? TheProcess, readRetry: readRetry);

    /// <summary>This harness process's own memory of the list, shared by every journal it makes unless a run asks for its own.</summary>
    private static readonly UndoProcessMemory TheProcess = new();

    private static string Exe => Environment.ProcessPath!;

    /// <summary>A begin line shaped like the app's: one editLine op on a page of a working folder.</summary>
    private static JsonObject Begin(long seq, int pid) => new()
    {
        ["seq"] = seq,
        ["event"] = "begin",
        ["process"] = new JsonObject { ["host"] = Environment.MachineName, ["pid"] = pid, ["name"] = "Plantoir.UndoHarness", ["started"] = "1.000000" },
        ["step"] = new JsonObject
        {
            ["seq"] = seq,
            ["madeAt"] = UndoMoment.Format(DateTimeOffset.UtcNow),
            ["madeBy"] = "menu",
            ["holds"] = "section",
            ["course"] = "TST1O",
            ["section"] = 1,
            ["action"] = new JsonObject { ["key"] = "publishPages", ["arguments"] = new JsonObject { ["pageCount"] = "1" } },
            ["workingFolder"] = new JsonObject { ["id"] = "6f1c2b9e-1a2b-4c3d-8e9f-0a1b2c3d4e5f", ["pathAtTheTime"] = @"C:\Users\teacher\Documents\Courses" },
            ["ops"] = new JsonArray(new JsonObject
            {
                ["kind"] = "editLine", ["path"] = $"courses/TST1O/Section 1/Unit 1, Day {seq % 90 + 1}.md", ["key"] = "publish",
                ["before"] = "publish: false", ["after"] = "publish: true", ["afterKey"] = "title",
            }),
        },
    };

    private static JsonObject Applied(long seq) => new() { ["seq"] = seq, ["event"] = "applied" };

    private static double Median(List<double> values) { values.Sort(); return values.Count == 0 ? 0 : values[values.Count / 2]; }

    private static double P95(List<double> values) { values.Sort(); return values.Count == 0 ? 0 : values[Math.Min(values.Count - 1, (int)Math.Ceiling(values.Count * 0.95) - 1)]; }

    private static string Ms(double value) => value.ToString("0.000", CultureInfo.InvariantCulture);

    // ---- contend: N processes x H holds --------------------------------------

    private static int Contend(string folder, int processes, int holds, int waitMs, bool shadow)
    {
        Directory.CreateDirectory(folder);
        long startAt = DateTime.UtcNow.AddSeconds(3).Ticks;
        var children = new List<Process>();
        for (int index = 0; index < processes; index++)
        {
            var start = new ProcessStartInfo(Exe)
            {
                RedirectStandardOutput = true,
                UseShellExecute = false,
            };
            foreach (string arg in new[] { "child-contend", folder, holds.ToString(CultureInfo.InvariantCulture), waitMs.ToString(CultureInfo.InvariantCulture), shadow ? "1" : "0", startAt.ToString(CultureInfo.InvariantCulture) })
                start.ArgumentList.Add(arg);
            children.Add(Process.Start(start)!);
        }
        int recorded = 0, busy = 0;
        double highestWait = 0;
        var seqs = new List<long>();
        foreach (Process child in children)
        {
            string output = child.StandardOutput.ReadToEnd();
            child.WaitForExit();
            foreach (string line in output.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
            {
                if (!line.StartsWith("CHILD ", StringComparison.Ordinal)) { Console.WriteLine("child said: " + line); continue; }
                var fields = line[6..].Split(' ').Select(field => field.Split('=', 2)).ToDictionary(pair => pair[0], pair => pair[1]);
                recorded += Int(fields["ok"]);
                busy += Int(fields["busy"]);
                highestWait = Math.Max(highestWait, double.Parse(fields["maxWaitMs"], CultureInfo.InvariantCulture));
                if (fields["seqs"].Length > 0) seqs.AddRange(fields["seqs"].Split(',').Select(text => long.Parse(text, CultureInfo.InvariantCulture)));
            }
        }
        UndoReading reading = Journal(folder).Read();
        int distinct = seqs.Distinct().Count();
        int doneOnDisk = reading.Folded.Steps.Values.Count(step => step.State == UndoStepState.Done);
        Console.WriteLine($"RESULT contend processes={processes} holds={holds} wait={waitMs}ms shadow={shadow} recorded={recorded} of {processes * holds} busy={busy} distinctSeqs={distinct} doneOnDisk={doneOnDisk} highest={reading.Folded.Highest} barriers={reading.Folded.Barriers.Count} highestWaitMs={Ms(highestWait)} fresh={reading.IsFresh}");
        return recorded == distinct && doneOnDisk == recorded ? 0 : 1;
    }

    private static int ChildContend(string folder, int holds, int waitMs, bool shadow, long startAt)
    {
        UndoJournal journal = Journal(folder);
        while (DateTime.UtcNow.Ticks < startAt) Thread.Sleep(1);
        int ok = 0, busy = 0;
        double maxWait = 0;
        var seqs = new List<long>();
        for (int index = 0; index < holds; index++)
        {
            var clock = Stopwatch.StartNew();
            double waited = -1;
            try
            {
                long seq = journal.WithLock(writer =>
                {
                    waited = clock.Elapsed.TotalMilliseconds;
                    long next = writer.Folded.NextSeq;
                    writer.Append(Begin(next, Environment.ProcessId));
                    writer.Append(Applied(next));
                    return next;
                }, inShadow: shadow, wait: TimeSpan.FromMilliseconds(waitMs));
                ok++;
                seqs.Add(seq);
                maxWait = Math.Max(maxWait, waited);
            }
            catch (UndoJournalException error) when (error.Failure == UndoJournalFailure.LockBusy)
            {
                busy++;
            }
        }
        Console.WriteLine($"CHILD ok={ok} busy={busy} maxWaitMs={Ms(maxWait)} seqs={string.Join(',', seqs)}");
        return 0;
    }

    // ---- killed: a holder killed while another waits ------------------------

    private static int Killed(string folder, int rounds)
    {
        Directory.CreateDirectory(folder);
        var grants = new List<double>();
        for (int round = 0; round < rounds; round++)
        {
            Process holder = Start("child-hold", folder);
            string? said = holder.StandardOutput.ReadLine();
            if (said != "HELD") { Console.WriteLine("RESULT killed holder said " + said); holder.Kill(); return 1; }
            Process waiter = Start("child-wait", folder, "10000");
            Thread.Sleep(500);
            long killedAt = DateTime.UtcNow.Ticks;
            holder.Kill();
            string answer = waiter.StandardOutput.ReadToEnd().Trim();
            waiter.WaitForExit();
            holder.WaitForExit();
            if (!answer.StartsWith("GRANTED ", StringComparison.Ordinal)) { Console.WriteLine("RESULT killed waiter said " + answer); return 1; }
            grants.Add(TimeSpan.FromTicks(long.Parse(answer[8..], CultureInfo.InvariantCulture) - killedAt).TotalMilliseconds);
        }
        Console.WriteLine($"RESULT killed rounds={rounds} grantAfterKillMs median={Ms(Median(grants))} highest={Ms(grants.Max())} all={string.Join(',', grants.Select(Ms))}");
        return 0;
    }

    private static Process Start(params string[] args)
    {
        var start = new ProcessStartInfo(Exe) { RedirectStandardOutput = true, UseShellExecute = false };
        foreach (string arg in args) start.ArgumentList.Add(arg);
        return Process.Start(start)!;
    }

    private static int ChildHold(string folder)
    {
        UndoJournal journal = Journal(folder);
        journal.WithLock(_ =>
        {
            Console.WriteLine("HELD");
            Console.Out.Flush();
            Thread.Sleep(Timeout.Infinite);
        });
        return 0;
    }

    private static int ChildWait(string folder, int waitMs)
    {
        UndoJournal journal = Journal(folder);
        try
        {
            journal.WithLock(_ => Console.WriteLine("GRANTED " + DateTime.UtcNow.Ticks.ToString(CultureInfo.InvariantCulture)),
                             wait: TimeSpan.FromMilliseconds(waitMs));
        }
        catch (UndoJournalException error) when (error.Failure == UndoJournalFailure.LockBusy) { Console.WriteLine("BUSY"); }
        return 0;
    }

    // ---- flush: what FlushFileBuffers costs per hold ---------------------------

    private static int Flush(string folder, int holds)
    {
        Directory.CreateDirectory(folder);
        UndoJournal journal = Journal(folder);
        var appendMs = new List<double>();
        var syncMs = new List<double>();
        var holdMs = new List<double>();
        for (int index = 0; index < holds; index++)
        {
            var hold = Stopwatch.StartNew();
            journal.WithLock(writer =>
            {
                long seq = writer.Folded.NextSeq;
                var clock = Stopwatch.StartNew();
                writer.Append(Begin(seq, Environment.ProcessId));
                appendMs.Add(clock.Elapsed.TotalMilliseconds);
                clock.Restart();
                writer.Sync();
                syncMs.Add(clock.Elapsed.TotalMilliseconds);
            });
            holdMs.Add(hold.Elapsed.TotalMilliseconds);
        }
        Console.WriteLine($"RESULT flush holds={holds} appendMs median={Ms(Median(appendMs))} p95={Ms(P95(appendMs))} flushFileBuffersMs median={Ms(Median(syncMs))} p95={Ms(P95(syncMs))} wholeHoldMs median={Ms(Median(holdMs))} p95={Ms(P95(holdMs))}");
        return 0;
    }

    // ---- read: first read, read on, whole read, at four sizes ----------------

    private static int ReadSizes(string root)
    {
        foreach (long target in new long[] { 106_000, 1_000_000, 4_000_000, 9_950_000 })
        {
            string folder = Path.Combine(root, "read-" + target.ToString(CultureInfo.InvariantCulture));
            Directory.CreateDirectory(folder);
            UndoJournal maker = Journal(folder);
            long seq = 0;
            long written = 0;
            maker.WithLock(writer =>
            {
                while (written < target)
                {
                    seq++;
                    JsonObject begin = Begin(seq, Environment.ProcessId);
                    writer.Append(begin);
                    writer.Append(Applied(seq));
                    written += UndoJournalWriter.Encode(begin).Length + 60;
                }
            });
            long onDisk = Directory.GetFiles(folder, "journal-*.jsonl").Sum(path => new FileInfo(path).Length);
            var first = new List<double>();
            var readOnNothing = new List<double>();
            var readOnOneStep = new List<double>();
            var readOnAfterAPause = new List<double>();
            var whole = new List<double>();
            for (int round = 0; round < 5; round++)
            {
                UndoJournal reader = Journal(folder);
                var clock = Stopwatch.StartNew();
                reader.Read();
                first.Add(clock.Elapsed.TotalMilliseconds);
                clock.Restart();
                reader.Read();
                readOnNothing.Add(clock.Elapsed.TotalMilliseconds);
                maker.WithLock(writer =>
                {
                    long next = writer.Folded.NextSeq;
                    writer.Append(Begin(next, Environment.ProcessId));
                    writer.Append(Applied(next));
                });
                clock.Restart();
                UndoReading readOn = reader.Read();
                readOnOneStep.Add(clock.Elapsed.TotalMilliseconds);
                maker.WithLock(writer =>
                {
                    long next = writer.Folded.NextSeq;
                    writer.Append(Begin(next, Environment.ProcessId));
                    writer.Append(Applied(next));
                });
                Thread.Sleep(500);
                clock.Restart();
                readOn = reader.Read();
                readOnAfterAPause.Add(clock.Elapsed.TotalMilliseconds);
                if (reader.LastReadWasWhole) Console.WriteLine("RESULT read warning: the read after one step was whole");
                UndoJournal wholeReader = Journal(folder);
                wholeReader.ReadWholeEveryTime();
                wholeReader.Read();
                clock.Restart();
                UndoReading wholeReading = wholeReader.Read();
                whole.Add(clock.Elapsed.TotalMilliseconds);
                if (wholeReading.Folded.Highest != readOn.Folded.Highest) Console.WriteLine("RESULT read MISMATCH between read on and whole");
            }
            Console.WriteLine($"RESULT read bytes={onDisk} segments={Directory.GetFiles(folder, "journal-*.jsonl").Length} steps={seq} firstReadMs median={Ms(Median(first))} readOnNothingNewMs median={Ms(Median(readOnNothing))} readOnAfterOneStepMs median={Ms(Median(readOnOneStep))} readOnOneStepHalfASecondLaterMs median={Ms(Median(readOnAfterAPause))} wholeReadMs median={Ms(Median(whole))}");
        }
        return 0;
    }

    // ---- blobs: a 233-page whole-file step's hold, with a waiter beside it ---

    private static int Blobs(string folder, int pages, int parallelism)
    {
        Directory.CreateDirectory(folder);
        var random = new Random(899);
        var contents = new List<byte[]>();
        for (int index = 0; index < pages * 2; index++)
        {
            var page = new byte[2048];
            random.NextBytes(page);
            contents.Add(page);
        }
        UndoJournal journal = Journal(folder);
        UndoJournal other = Journal(folder);
        double holdMs = 0;
        var waiterResult = "";
        using var entered = new ManualResetEventSlim();
        Task waiter = Task.Run(() =>
        {
            entered.Wait();
            var clock = Stopwatch.StartNew();
            try
            {
                other.WithLock(_ => { }, wait: UndoJournal.LiveWait);
                waiterResult = $"granted after {Ms(clock.Elapsed.TotalMilliseconds)} ms";
            }
            catch (UndoJournalException error) when (error.Failure == UndoJournalFailure.LockBusy)
            {
                waiterResult = $"BUSY after {Ms(clock.Elapsed.TotalMilliseconds)} ms";
            }
        });
        var hold = Stopwatch.StartNew();
        journal.WithLock(writer =>
        {
            entered.Set();
            writer.WriteBlobs(contents, parallelism);
            long seq = writer.Folded.NextSeq;
            writer.Append(Begin(seq, Environment.ProcessId));
            writer.Sync();
        });
        holdMs = hold.Elapsed.TotalMilliseconds;
        waiter.Wait();
        Console.WriteLine($"RESULT blobs pages={pages} blobs={contents.Count} parallelism={parallelism} holdMs={Ms(holdMs)} waiter2s={waiterResult}");
        return 0;
    }

    /// <summary>Where a blob's time goes: the create and write, FlushFileBuffers, the close, the no-replace move.</summary>
    private static int BlobParts(string folder, int pages)
    {
        Directory.CreateDirectory(folder);
        var random = new Random(900);
        var create = new List<double>(); var flush = new List<double>(); var close = new List<double>(); var move = new List<double>();
        var clock = new Stopwatch();
        for (int index = 0; index < pages * 2; index++)
        {
            var page = new byte[2048];
            random.NextBytes(page);
            string temporary = Path.Combine(folder, ".tmp-" + index.ToString(CultureInfo.InvariantCulture));
            clock.Restart();
            var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None, bufferSize: 0);
            stream.Write(page, 0, page.Length);
            create.Add(clock.Elapsed.TotalMilliseconds);
            clock.Restart();
            stream.Flush(flushToDisk: true);
            flush.Add(clock.Elapsed.TotalMilliseconds);
            clock.Restart();
            stream.Dispose();
            close.Add(clock.Elapsed.TotalMilliseconds);
            clock.Restart();
            File.Move(temporary, Path.Combine(folder, "blob-" + index.ToString(CultureInfo.InvariantCulture)), overwrite: false);
            move.Add(clock.Elapsed.TotalMilliseconds);
        }
        Console.WriteLine($"RESULT blobparts blobs={pages * 2} createWriteMs median={Ms(Median(create))} sum={Ms(create.Sum())} flushMs median={Ms(Median(flush))} sum={Ms(flush.Sum())} closeMs median={Ms(Median(close))} sum={Ms(close.Sum())} moveMs median={Ms(Median(move))} sum={Ms(move.Sum())}");
        return 0;
    }

    // ---- onedrive: identity, sharing, conflict copies, while it syncs --------

    private static int OneDriveWatch(string folder, int seconds)
    {
        Directory.CreateDirectory(folder);
        UndoJournal journal = Journal(folder, readRetry: TimeSpan.Zero);
        UndoJournal patient = Journal(folder);
        journal.WithLock(writer => { writer.Append(Begin(1, Environment.ProcessId)); writer.Append(Applied(1)); });
        string segment = journal.SegmentPath(1);
        (uint, ulong)? firstIdentity = IdentityOf(segment);
        int identityChanges = 0, notFresh = 0, notFreshPatient = 0, appends = 0, deleteFailures = 0, blobsWritten = 0, lockFailures = 0;
        var deadline = DateTime.UtcNow.AddSeconds(seconds);
        var random = new Random(1);
        while (DateTime.UtcNow < deadline)
        {
            try
            {
                journal.WithLock(writer =>
                {
                    long seq = writer.Folded.NextSeq;
                    var blob = new byte[4096];
                    random.NextBytes(blob);
                    string name = writer.WriteBlob(blob);
                    blobsWritten++;
                    writer.Append(Begin(seq, Environment.ProcessId));
                    writer.Append(Applied(seq));
                    appends++;
                    if (appends % 3 == 0)
                    {
                        try { File.Delete(journal.BlobPath(name)); }
                        catch (IOException) { deleteFailures++; }
                        catch (UnauthorizedAccessException) { deleteFailures++; }
                    }
                });
            }
            catch (UndoJournalException) { lockFailures++; }
            if (!journal.Read().IsFresh) notFresh++;
            if (!patient.Read().IsFresh) notFreshPatient++;
            if (IdentityOf(segment) != firstIdentity) identityChanges++;
            Thread.Sleep(1000);
        }
        var files = Directory.EnumerateFiles(folder, "*", SearchOption.AllDirectories).Select(path => Path.GetRelativePath(folder, path)).ToList();
        var unexpected = files.Where(name =>
            !(name == ".lock" || System.Text.RegularExpressions.Regex.IsMatch(name, @"^journal-\d{6}\.jsonl$")
              || System.Text.RegularExpressions.Regex.IsMatch(name, @"^content\\[0-9a-f]{2}\\[0-9a-f]{64}$"))).ToList();
        var attributes = new FileInfo(segment).Attributes;
        Console.WriteLine($"RESULT onedrive seconds={seconds} holds={appends} lockFailures={lockFailures} identityChanges={identityChanges} notFreshNoRetry={notFresh} notFresh2sRetry={notFreshPatient} blobDeleteFailures={deleteFailures} blobsWritten={blobsWritten} files={files.Count} unexpectedFiles={unexpected.Count} [{string.Join("; ", unexpected.Take(10))}] segmentAttributes={attributes}");
        return 0;
    }

    private static (uint, ulong)? IdentityOf(string path)
    {
        try
        {
            using FileStream stream = UndoJournal.OpenSegmentToRead(path);
            return UndoFileIdentity.Of(stream);
        }
        catch (IOException) { return null; }
    }
}
