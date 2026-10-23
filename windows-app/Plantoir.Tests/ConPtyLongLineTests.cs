using System.Collections.Concurrent;
using System.Text;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;

namespace Plantoir.Tests;

/// <summary>
/// #662: a machine line LONGER than the pseudo console's screen came back
/// broken in two, so the build's 611-character <c>PLANTOIR_HEALTH:</c> line
/// for a block of code shown as plain code (#567, #650) left no folder problem
/// and no trail line, and the console showed the JSON's tail.
///
/// <para>What ConPTY sends, measured on this PC (i5-8365U, Windows 11 26200)
/// with the child below: when the long line wraps on the BOTTOM row while
/// Quartz's spinner redraws, the first 400 characters, a real CR LF to scroll,
/// <c>ESC[29;400H</c> back to the last column of the row above, then the rest
/// of the line starting again from that column's character. Three of three
/// runs split at 400 columns; none at 4096, 8192 or 32767. With the screen
/// NOT yet full (no scroll) the same line came through whole at 400, which is
/// why the child prints forty lines first: a test without them passes at any
/// width and proves nothing. documentation/12-windows-app.md → "How wide the
/// console is, and why" has the bytes and the costs.</para>
///
/// <para>The child is NODE, not Python, because that is what writes the line
/// in a real build: <c>plantoirSiteSaid.ts</c> runs <c>site_said.py</c> with a
/// blocking <c>execFileSync</c> while Quartz's spinner (<c>readline.clearLine</c>
/// + <c>cursorTo</c> every 20 ms, util/log.ts) owns the row, then writes what it
/// printed — the ⚠️ sentence, the detail and the machine line — in ONE write.
/// libuv turns those readline calls into console calls, a different redraw
/// path from a Python child's escape sequences.</para>
/// </summary>
/// <remarks>In the serialized collection: it redirects the activity trail,
/// a process-wide static.</remarks>
[Collection(SharedActivityState.Name)]
public sealed class ConPtyLongLineTests : IDisposable
{
    /// <summary>The line the check that found #662 printed, byte for byte.</summary>
    private const string HealthLine =
        """PLANTOIR_HEALTH: {"name": "runnableCodeShownAsPlainCode", "sentence": "A block of code on “Discussions/Plain Code Fixture” in MPM2D Section 1 shows as plain code, with no Run button.", "detail": "Students can read the code but cannot run it until it is put right in your notes: “Discussions/Plain Code Fixture”, Swift block 1, line 13: a block of code above it on the page is never closed - close that block with a line like the one that opened it (the same ``` or ~~~, indented the same, inside the same list item or callout), then preview the course again.", "fixable": false, "course": "MPM2D", "section": 1}""";

    private const string WarningLine =
        "⚠️  A block of code on “Discussions/Plain Code Fixture” in MPM2D Section 1 shows as plain code, with no Run button.";

    /// <summary>
    /// Quartz's spinner and the emitter's write, in their real order. The
    /// forty lines first fill the 30-row screen, so the long line lands on the
    /// bottom row and has to scroll — the condition the split needs.
    /// </summary>
    private const string SpinnerChild = """
        import readline from "readline"
        import { execFileSync } from "child_process"
        const [py, said, healthFile] = process.argv.slice(2)
        for (let n = 0; n < 40; n++) console.log(`Parsed line ${n} of the build output so far`)
        const chars = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
        let i = 0
        const tick = () => {
          readline.clearLine(process.stdout, 0)
          readline.cursorTo(process.stdout, 0)
          const columns = process.stdout.columns || 80
          process.stdout.write(`${chars[i]} Emitting output files`.slice(0, columns))
          i = (i + 1) % chars.length
        }
        const sleep = (ms) => new Promise((r) => setTimeout(r, ms))
        const timer = setInterval(tick, 20)
        await sleep(400)
        const printed = execFileSync(py, [said, healthFile], { encoding: "utf-8", windowsHide: true, stdio: ["pipe", "pipe", "pipe"] })
        process.stdout.write(printed.endsWith("\n") ? printed : printed + "\n")
        await sleep(600)
        clearInterval(timer)
        readline.clearLine(process.stdout, 0)
        readline.cursorTo(process.stdout, 0)
        console.log("Emitted 313 files to `public` in 18s")
        """;

    /// <summary>What site_health.announce prints, after the 180–470 ms the call took on this PC.</summary>
    private const string SaidChild = """
        import sys, json, time
        sys.stdout.reconfigure(encoding="utf-8")
        line = open(sys.argv[1], encoding="utf-8").read().strip()
        d = json.loads(line[len("PLANTOIR_HEALTH: "):])
        time.sleep(0.3)
        print("")
        print("⚠️  " + d["sentence"])
        print("   " + d["detail"])
        print(line)
        """;

    private readonly string _folder = Directory.CreateTempSubdirectory("plantoir-662").FullName;
    private readonly string _trailPath;

    public ConPtyLongLineTests()
    {
        _trailPath = Path.Combine(Path.GetTempPath(), $"plantoir-trail-{Guid.NewGuid():N}.txt");
        ActivityTrail.SetCustomLogPathForTesting(_trailPath);
    }

    public void Dispose()
    {
        ActivityTrail.SetCustomLogPathForTesting(TestTrailRedirect.ScratchTrailPath);
        try { File.Delete(_trailPath); } catch { }
        try { Directory.Delete(_folder, recursive: true); } catch { }
    }

    private string CommandLine()
    {
        string runtime = NativeRuntime.Folder!;
        var utf8 = new UTF8Encoding(false);
        File.WriteAllText(Path.Combine(_folder, "spin.mjs"), SpinnerChild, utf8);
        File.WriteAllText(Path.Combine(_folder, "said.py"), SaidChild, utf8);
        File.WriteAllText(Path.Combine(_folder, "health.txt"), HealthLine, utf8);
        return $"\"{Path.Combine(runtime, "node", "node.exe")}\" \"{Path.Combine(_folder, "spin.mjs")}\" " +
               $"\"{Path.Combine(runtime, "python", "python.exe")}\" \"{Path.Combine(_folder, "said.py")}\" " +
               $"\"{Path.Combine(_folder, "health.txt")}\"";
    }

    [Fact]
    public void TheFixtureIsLongerThanTheOldScreenAndFitsTheNewOne()
    {
        Assert.Equal(611, HealthLine.Length);
        Assert.True(HealthLine.Length > 400);
        Assert.True(HealthLine.Length < ConPtyProcess.LauncherColumns);
    }

    /// <summary>
    /// The bytes ConPTY sent at 8192 columns (captured from the child below),
    /// handed over in uneven pieces with the spinner's redraws either side:
    /// the console keeps the ⚠️ sentence and the detail, shows none of the
    /// machine line at any moment — not even while it is still arriving —
    /// and the runner finds the one finding. No runtime needed.
    /// </summary>
    [Fact]
    public void TheWideScreensBytesGiveOneFindingAndAConsoleWithoutTheJson()
    {
        const string spin = "\u001b[K⠋ Emitting output files\r\u001b[K\u001b[23C\r⠙ Emitting output files\r\u001b[K\u001b[23C\r⠸ Emitting output files";
        string detail = "   Students can read the code but cannot run it until it is put right in your notes: “Discussions/Plain Code Fixture”, Swift block 1, line 13: a block of code above it on the page is never closed - close that block with a line like the one that opened it (the same ``` or ~~~, indented the same, inside the same list item or callout), then preview the course again.";
        string bytes = spin + "\r\n" + WarningLine + "\r\n" + detail + "\r\n" + HealthLine + "\r\n" +
                       "⠼ Emitting output files\u001b[K\r⠴ Emitting output files\u001b[K\r\u001b[K\r\nEmitted 313 files to `public` in 18s\r\n";

        int at = bytes.IndexOf(SiteHealthFinding.Marker, StringComparison.Ordinal);
        int[] cuts = { 30, at + 5, at + 250, at + 400, at + 600, bytes.Length };

        var transcript = new TranscriptBuilder();
        var runner = new ScriptRunner();
        int from = 0;
        foreach (int cut in cuts)
        {
            string piece = bytes[from..cut];
            from = cut;
            transcript.Append(piece);
            runner.ReceiveOutput(piece);
            Assert.DoesNotContain("\"fixable\"", transcript.DisplayText);
            Assert.DoesNotContain("runnableCodeShownAsPlainCode", transcript.DisplayText);
        }

        Assert.Contains(WarningLine, transcript.Lines);
        Assert.Contains(detail, transcript.Lines);
        Assert.Contains("Emitted 313 files to `public` in 18s", transcript.Lines);
        Assert.DoesNotContain(transcript.Lines, line => line.Contains("PLANTOIR_", StringComparison.Ordinal));
        Assert.Equal("runnableCodeShownAsPlainCode", Assert.Single(runner.HealthFindings).Name);
    }

    /// <summary>
    /// The product path end to end: ScriptRunner.Run, which starts the
    /// launcher under the real pseudo console at the width it chooses.
    /// </summary>
    [NativeRuntimeFact]
    public async Task ALongMachineLineReachesTheRunnerWholeWhileTheSpinnerRedraws()
    {
        File.WriteAllText(Path.Combine(_folder, "preview.ps1"),
            $"& {CommandLine()}\r\nexit $LASTEXITCODE\r\n",
            new UTF8Encoding(true));

        using var context = new SerialContext();
        var runner = new ScriptRunner(context);
        context.Send(_ => runner.Run("preview.ps1", new[] { "MPM2D", "1" }, _folder), null);
        var waited = runner.WaitUntilFinished();
        Assert.Same(waited, await Task.WhenAny(waited, Task.Delay(TimeSpan.FromSeconds(90))));
        // Let the last posted flush run before reading.
        context.Send(_ => { }, null);

        string transcript = string.Join("\n", runner.Transcript.Lines) + "\n" + runner.Transcript.CurrentLine;
        Assert.True(await waited, "the child exited 0\n" + transcript);
        var finding = Assert.Single(runner.HealthFindings);
        Assert.Equal("runnableCodeShownAsPlainCode", finding.Name);
        Assert.Contains(finding.TrailSentence, File.ReadAllText(_trailPath));
        Assert.Contains(WarningLine, runner.Transcript.Lines);
        Assert.DoesNotContain("\"fixable\"", transcript);
        Assert.DoesNotContain("runnableCodeShownAsPlainCode", transcript);
        // The tail the old width left on a line of its own (the detail line
        // holds the same words mid-sentence, so only a line STARTING with them counts).
        Assert.DoesNotContain(runner.Transcript.Lines, line => line.StartsWith("at block with a line like", StringComparison.Ordinal));
    }

    /// <summary>
    /// The control: the same child at the OLD width splits the line, so the
    /// test above is proving the width rather than passing on a child that
    /// never triggers the fault. If this ever starts failing, conhost has
    /// changed how it repaints a wrapped line: re-measure before narrowing the
    /// screen again (12-windows-app.md → "How wide the console is, and why").
    /// </summary>
    [NativeRuntimeFact]
    public void AtTheOldWidthTheSameLineIsSplit()
    {
        using var pty = ConPtyProcess.Start(CommandLine(), _folder, columns: 400);
        var raw = new StringBuilder();
        var reader = new Thread(() =>
        {
            var decoder = Encoding.UTF8.GetDecoder();
            var buffer = new byte[8192];
            var chars = new char[16384];
            int count;
            while ((count = pty.ReadOutput(buffer)) > 0)
            {
                int charCount = decoder.GetChars(buffer, 0, count, chars, 0);
                lock (raw) raw.Append(chars, 0, charCount);
            }
        }) { IsBackground = true };
        reader.Start();
        Assert.True(pty.WaitForExit(60_000), "the child finished");
        Thread.Sleep(300);
        pty.ClosePty();
        reader.Join(5000);

        var runner = new ScriptRunner();
        string text;
        lock (raw) text = raw.ToString();
        runner.ReceiveOutput(text);
        Assert.Empty(runner.HealthFindings);
        Assert.Contains(runner.Transcript.Lines, line => line.StartsWith("at block with a line like", StringComparison.Ordinal));
    }

    /// <summary>One thread, in order — the interface thread the app posts to.</summary>
    private sealed class SerialContext : SynchronizationContext, IDisposable
    {
        private readonly BlockingCollection<(SendOrPostCallback, object?, ManualResetEventSlim?)> _queue = new();
        private readonly Thread _thread;

        public SerialContext()
        {
            _thread = new Thread(() =>
            {
                SetSynchronizationContext(this);
                foreach (var (callback, state, done) in _queue.GetConsumingEnumerable())
                {
                    try { callback(state); } finally { done?.Set(); }
                }
            }) { IsBackground = true };
            _thread.Start();
        }

        public override void Post(SendOrPostCallback d, object? state) => _queue.Add((d, state, null));

        public override void Send(SendOrPostCallback d, object? state)
        {
            using var done = new ManualResetEventSlim();
            _queue.Add((d, state, done));
            done.Wait();
        }

        public void Dispose() => _queue.CompleteAdding();
    }
}
