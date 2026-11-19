using System.Diagnostics;
using System.Drawing;
using System.Drawing.Imaging;
using System.Net.Http;
using System.Text;
using FlaUI.Core.AutomationElements;
using FlaUI.Core.Definitions;
using FlaUI.Core.Input;
using FlaUI.UIA3;

namespace Plantoir.FirstInstall;

/// <summary>
/// The first-install rehearsal driver (#976). Runs in the logged-in desktop
/// session of a clean Windows machine and does what a teacher does, one step
/// at a time. Three outcomes, as in the macOS rehearsal:
///   PASSED            every step finished;
///   PRODUCT STOPPED   Plantoir (or Windows, about Plantoir) stopped at step N;
///                     the words on the screen are recorded;
///   DRIVER PROBLEM    the driver lost its way; no claim about the product.
/// An unexpected window is a PRODUCT STOPPED at the step it appeared in: the
/// point of the rehearsal is to catch prompts nobody planned for.
///
///   PlantoirFirstInstall.exe --url &lt;PlantoirSetup.exe address&gt; --out C:\rehearsal
///                            [--report http://10.211.55.2:8766/up/]
///
///   PlantoirFirstInstall.exe --self-test-final-watch --out C:\rehearsal --report …
///                            the final watch alone, for win-rehearsal.py's
///                            final-watch self-test; never says PASSED
///                            [--self-test-fail-looks-after N]  every look from
///                            N s into the watch on fails (the failed-looks self-test)
///
/// PASSED is written only after the last step succeeded AND the desktop was
/// then watched for <see cref="WindowRules.FinalWatchLength"/> with nothing
/// unexpected (step 7), AND every decision rested on a successful look made
/// within <see cref="WindowRules.MaxLookAge"/>, with no gap over
/// <see cref="WindowRules.MaxLookGap"/> in the final watch (the fifth review).
/// One driver runs at a time: a second one started while the first is alive
/// does nothing and writes nothing.
///
/// Writes steps.log (a line per event), result.txt (fixed fields the Mac
/// decides by: status, cause, the look record's counts and gaps, times; then
/// the "DRIVER RESULT:" line), small value files (driver-started-PID.txt,
/// step-N.txt, final-watch-began.txt) and shots\NN-label.png into --out, and
/// PUTs each to --report as it is written, so the Mac has the evidence even if
/// the machine stops answering. result.txt is written straight after the last
/// look; notes, shots and uploads come after it.
/// Exit code: 0 passed, 2 product stopped, 1 driver problem, 3 the final-watch
/// self-test ended with nothing seen, 4 another driver was already running.
/// </summary>
internal static class Program
{
    private static string _out = @"C:\rehearsal";
    private static string? _report;
    private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(30) };
    private static readonly StringBuilder Steps = new();
    private static int _shotCount;
    private static int _stepNumber;
    private static string _stepName = "starting";
    private static UIA3Automation _automation = null!;
    private static WindowWatch _watch = null!;
    private static DateTime? _finalWatchBegan;
    private static TimeSpan? _failLooksAfter;
    private static TimeSpan? _finalWatchGap;
    private static int _finalWatchLooks;

    private static long UnixMs(DateTime utc) => new DateTimeOffset(utc, TimeSpan.Zero).ToUnixTimeMilliseconds();

    /// <summary>Writes a small file of values into --out and sends it to the Mac (a step's start, the final watch's start, a driver's start).</summary>
    private static void Mark(string name, string text)
    {
        try
        {
            string path = Path.Combine(_out, name);
            File.WriteAllText(path, text + Environment.NewLine);
            Send(path, name);
        }
        catch (Exception error) { Console.WriteLine($"(could not write {name}: {error.Message})"); }
    }

    public static int Main(string[] args)
    {
        string url = "https://github.com/russellgordon/plantoir/releases/latest/download/PlantoirSetup.exe";
        bool watchOnly = Array.IndexOf(args, "--self-test-final-watch") >= 0;
        for (int i = 0; i < args.Length - 1; i++)
        {
            if (args[i] == "--url") url = args[i + 1];
            if (args[i] == "--out") _out = args[i + 1];
            if (args[i] == "--report") _report = args[i + 1];
            if (args[i] == "--self-test-fail-looks-after") _failLooksAfter = TimeSpan.FromSeconds(int.Parse(args[i + 1]));
        }
        // One driver at a time in the session (the Mac retries a refused
        // launch; the review of 2026-11-18 asked that a late first attempt can
        // never run beside the second). Checked before anything is written.
        using var single = new Mutex(true, @"Local\PlantoirFirstInstallDriver", out bool onlyOne);
        if (!onlyOne)
        {
            Console.WriteLine("another PlantoirFirstInstall is already running in this session; this one does nothing");
            return 4;
        }
        Directory.CreateDirectory(Path.Combine(_out, "shots"));
        // A file per driver that starts, named by its process id, which the Mac
        // counts (exec-refused self-test): a value no other driver can erase.
        Mark($"driver-started-{Environment.ProcessId}.txt", $"pid {Environment.ProcessId}, started {UnixMs(DateTime.UtcNow)} ms");
        try
        {
            _automation = new UIA3Automation();
            _watch = new WindowWatch(_automation);
            Note($"driver started as {Environment.UserName} on {Environment.OSVersion}, {System.Runtime.InteropServices.RuntimeInformation.OSArchitecture}");
            Note($"windows already open, taken as the desktop: {_watch.BaselineDescription}");
            // Recorded because an elevated driver would start the installer
            // elevated too, and then no UAC question could ever appear.
            using (var identity = System.Security.Principal.WindowsIdentity.GetCurrent())
            {
                bool elevated = new System.Security.Principal.WindowsPrincipal(identity)
                    .IsInRole(System.Security.Principal.WindowsBuiltInRole.Administrator);
                Note($"the driver runs {(elevated ? "ELEVATED (an administrator's full token)" : "not elevated (a standard token, as a double-click from the desktop has)")}");
            }
            if (watchOnly)
            {
                Note("SELF-TEST: steps 1 to 6 are not run; only the final watch, which must catch a window planted during it");
                int selfTestLooks = FinalWatch();
                return Finish(Outcome.SelfTestOnly, $"the final watch saw nothing unexpected in {WindowRules.FinalWatchLength.TotalSeconds:0} s ({selfTestLooks} looks); no steps were run, so this is no rehearsal");
            }
            Steps1To6(url);
            int looks = FinalWatch();
            return Finish(Outcome.Passed, "Plantoir was downloaded, installed, opened, set up a working folder, added the example course and served its preview, "
                                          + $"and nothing unexpected appeared in the {WindowRules.FinalWatchLength.TotalSeconds:0} s watched after ({looks} looks)");
        }
        catch (Stopped stop)
        {
            return Finish(stop.Outcome, stop.Message, stop.Cause, stop.WindowProcess, stop.WindowFirstSeen);
        }
        catch (Exception error)
        {
            return Finish(Outcome.DriverProblem, "the driver failed: " + error.GetType().Name + ": " + error.Message);
        }
    }

    private static void Steps1To6(string url)
    {
        Step("download the installer through the browser");
        string installer = Steps_.Download(url);

        Step("run the installer");
        Steps_.Install(installer);

        Step("open Plantoir");
        var window = Steps_.WaitForPlantoir();

        Step("choose a new working folder and set it up");
        Steps_.SetUpWorkingFolder(window);

        Step("add the example course");
        string code = Steps_.AddExampleCourse(window);

        Step("preview the example course");
        Steps_.Preview(window, code);
    }

    /// <summary>
    /// Step 7: the desktop watched for <see cref="WindowRules.FinalWatchLength"/>
    /// after the last step succeeded, with the preview's allow-list, before
    /// PASSED. "FINAL WATCH BEGINS" and "FINAL WATCH ENDED" are read by the
    /// Mac, which keeps its own UAC watch going through the same minute and
    /// requires that it did. At least one real look per three seconds, or the
    /// watch did not happen and the run is a DRIVER PROBLEM.
    /// </summary>
    private static int FinalWatch()
    {
        Step($"watch the desktop for {WindowRules.FinalWatchLength.TotalSeconds:0} s after the last step");
        _watch.Stage = Stage.FinalWatch;
        _finalWatchBegan = DateTime.UtcNow;
        // The Mac knows the watch began from this file, a value, not the log line.
        Mark("final-watch-began.txt", UnixMs(_finalWatchBegan.Value).ToString());
        if (_failLooksAfter is { } after)
        {
            _watch.FailReadsFrom = _finalWatchBegan.Value + after;
            Note($"SELF-TEST: every look from {after.TotalSeconds:0} s into the final watch on is made to fail; the run must not end clean");
        }
        Note($"FINAL WATCH BEGINS: {WindowRules.FinalWatchLength.TotalSeconds:0} s");
        var (looks, gap) = _watch.Observe(WindowRules.FinalWatchLength);
        _finalWatchGap = gap;
        bool enough = WindowRules.LookedEnough(looks, WindowRules.FinalWatchLength, out int required);
        if (!enough)
            throw Stopped.Driver($"the final watch made only {looks} real looks in {WindowRules.FinalWatchLength.TotalSeconds:0} s (at least {required} required), so it did not really watch", "coverage");
        // No note, shot or upload here: the next thing is Finish, which looks
        // once more and writes the result before any slow work (the fifth review).
        _finalWatchLooks = looks;
        return looks;
    }

    // ---- Evidence ------------------------------------------------------------

    internal static UIA3Automation Automation => _automation;
    internal static WindowWatch Watch => _watch;
    internal static string Out => _out;
    internal static int StepNumber => _stepNumber;

    internal static void Step(string name)
    {
        _stepNumber++;
        _stepName = name;
        Mark($"step-{_stepNumber}.txt", UnixMs(DateTime.UtcNow).ToString());
        Note($"STEP {_stepNumber}: {name}");
        Shot("step" + _stepNumber);
    }

    internal static void Note(string text)
    {
        string line = DateTime.Now.ToString("HH:mm:ss") + " " + text;
        Console.WriteLine(line);
        Steps.AppendLine(line);
        string path = Path.Combine(_out, "steps.log");
        File.WriteAllText(path, Steps.ToString());
        Send(path, "steps.log");
    }

    internal static string Shot(string label)
    {
        _shotCount++;
        string name = $"{_shotCount:00}-{label}.png";
        string path = Path.Combine(_out, "shots", name);
        try
        {
            var bounds = System.Windows.Forms.SystemInformation.VirtualScreen;
            using var bitmap = new Bitmap(bounds.Width, bounds.Height);
            using (var graphics = Graphics.FromImage(bitmap))
                graphics.CopyFromScreen(bounds.Left, bounds.Top, 0, 0, bounds.Size);
            bitmap.Save(path, ImageFormat.Png);
            Send(path, "shot-" + name);
        }
        catch (Exception error)
        {
            Console.WriteLine($"(no screenshot {name}: {error.Message})");
        }
        return "shot-" + Path.GetFileNameWithoutExtension(name);   // kept on the Mac as shot-NN-label.jpg
    }

    /// <summary>Sends a file the driver wrote to the Mac as well.</summary>
    internal static void Keep(string path, string name) => Send(path, name);

    private static void Send(string path, string name)
    {
        if (_report is null) return;
        try
        {
            using var content = new ByteArrayContent(File.ReadAllBytes(path));
            Http.PutAsync(_report + name, content).GetAwaiter().GetResult();
        }
        catch { /* the Mac collects the folder at the end too */ }
    }

    private static int Finish(Outcome outcome, string reason, string cause = "", string process = "", DateTime? windowFirstSeen = null)
    {
        // PASSED is written only on a look made now (the fifth review): after
        // the final watch's last look there used to come a note, a shot and
        // uploads (30 s time-outs each) before the result. So: look once more,
        // settle (which insists on a successful look within MaxLookAge), and
        // write the result at once; every slow thing comes after.
        if (outcome == Outcome.Passed)
        {
            try
            {
                _watch.Check(null);
                _watch.Settle("the decision to write PASSED");
            }
            catch (Stopped stop)
            {
                return Finish(stop.Outcome, stop.Message, stop.Cause, stop.WindowProcess, stop.WindowFirstSeen);
            }
            catch (Exception error)
            {
                return Finish(Outcome.DriverProblem, "the look before writing PASSED failed: " + error.GetType().Name + ": " + error.Message);
            }
            if (!_watch.Fresh(DateTime.UtcNow))
                return Finish(Outcome.DriverProblem, "no successful look of the desktop was recent enough to write PASSED on", "coverage");
        }
        var decided = DateTime.UtcNow;
        string word = outcome switch
        {
            Outcome.Passed => "PASSED",
            Outcome.ProductStopped => "PRODUCT STOPPED",
            Outcome.SelfTestOnly => "SELF-TEST WATCH CLEAN",
            _ => "DRIVER PROBLEM",
        };
        string where = outcome is Outcome.Passed or Outcome.SelfTestOnly ? "" : $" at step {_stepNumber} ({_stepName})";
        // "DRIVER RESULT", not "RESULT": the Mac's report carries this line and
        // then its own final outcome, which can override it (a UAC prompt the
        // Mac saw, a final watch it did not cover), so a reader must not take
        // this one for the outcome. The status is a fixed word the Mac decides
        // by; it never searches the sentence (the review of 2026-11-18).
        string status = outcome switch
        {
            Outcome.Passed => "passed",
            Outcome.ProductStopped => "product-stopped",
            Outcome.SelfTestOnly => "self-test-watch-clean",
            _ => "driver-problem",
        };
        string line = $"DRIVER RESULT (the driver's own; the Mac's final outcome is the last line of its report): {word}{where}: {reason}";
        // Fixed fields the Mac decides by, never the sentence. The look
        // record's values let the Mac refuse a PASSED with a stretch nobody
        // looked through (largest-look-gap-ms) or one written on an old look
        // (last-look-age-ms). Times are milliseconds since 1970, UTC, by the
        // driver's clock; the Mac compares them only with each other.
        static string Ms(TimeSpan span) => span == TimeSpan.MaxValue ? "none" : ((long)span.TotalMilliseconds).ToString();
        var fields = new StringBuilder();
        void Field(string name, string value) => fields.Append(name + ": " + value + Environment.NewLine);
        Field("status", status);
        Field("stage", _watch?.Stage.ToString() ?? "Starting");
        Field("cause", cause.Length > 0 ? cause : "none");
        Field("window-process", process.Length > 0 ? process : "none");
        Field("settling-after", _watch?.SettlingAfter ?? "none");
        Field("decided-unix-ms", UnixMs(decided).ToString());
        Field("final-watch-began-unix-ms", _finalWatchBegan is { } began ? UnixMs(began).ToString() : "none");
        Field("window-first-seen-unix-ms", windowFirstSeen is { } seen ? UnixMs(seen).ToString() : "none");
        if (_watch is not null)
        {
            var (gap, gapStage) = _watch.LargestGap(decided);
            Field("looks", _watch.Looks.ToString());
            Field("failed-looks", _watch.FailedLooks.ToString());
            Field("largest-look-gap-ms", Ms(gap));
            Field("largest-look-gap-stage", gapStage);
            Field("last-look-age-ms", Ms(_watch.LastLookAge(decided)));
            Field("final-watch-looks", _finalWatchBegan is null ? "none" : _finalWatchLooks.ToString());
            Field("final-watch-largest-look-gap-ms", _finalWatchGap is { } watchGap ? Ms(watchGap) : "none");
            Field("unreadable-windows", _watch.Unreadable.ToString());
            Field("unreadable-popups", _watch.UnreadablePopups.ToString());
        }
        else
        {
            foreach (string name in new[] { "looks", "failed-looks", "largest-look-gap-ms", "largest-look-gap-stage", "last-look-age-ms",
                                            "final-watch-looks", "final-watch-largest-look-gap-ms", "unreadable-windows", "unreadable-popups" })
                Field(name, "none");
        }
        string path = Path.Combine(_out, "result.txt");
        File.WriteAllText(path, fields + line + Environment.NewLine);
        Send(path, "result.txt");
        // Now the slow work, which no longer stands between the look and the result.
        Note(line);
        Note($"the result's screenshot: {Shot("result")}; looks {(_watch?.Looks.ToString() ?? "none")}, failed looks {(_watch?.FailedLooks.ToString() ?? "none")}");
        return outcome switch { Outcome.Passed => 0, Outcome.ProductStopped => 2, Outcome.SelfTestOnly => 3, _ => 1 };
    }
}

internal enum Outcome { Passed, ProductStopped, DriverProblem, SelfTestOnly }

/// <summary>Ends the run with an outcome. Thrown from any step.</summary>
internal sealed class Stopped : Exception
{
    public Outcome Outcome { get; }
    /// <summary>A fixed word for why ("unexpected-window", "unreadable-window", "blocked", "unsettled"), or empty.</summary>
    public string Cause { get; }
    /// <summary>The process of the window the run stopped on, or empty.</summary>
    public string WindowProcess { get; }
    /// <summary>When the watcher first saw the window the run stopped on (UTC), or null.</summary>
    public DateTime? WindowFirstSeen { get; private set; }
    /// <summary>Records when the window this stop names was first seen.</summary>
    public Stopped Seen(DateTime firstSeen)
    {
        WindowFirstSeen = firstSeen;
        return this;
    }
    public Stopped(Outcome outcome, string message, string cause = "", string windowProcess = "") : base(message)
    {
        Outcome = outcome;
        Cause = cause;
        WindowProcess = windowProcess;
    }

    public static Stopped Product(string message, string cause = "", string windowProcess = "") => new(Outcome.ProductStopped, message, cause, windowProcess);
    /// <summary>A DRIVER PROBLEM; cause "coverage" when nobody was looking (the fifth review).</summary>
    public static Stopped Driver(string message, string cause = "") => new(Outcome.DriverProblem, message, cause);
}
