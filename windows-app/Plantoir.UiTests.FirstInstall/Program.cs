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
///
/// PASSED is written only after the last step succeeded AND the desktop was
/// then watched for <see cref="WindowRules.FinalWatchLength"/> with nothing
/// unexpected (step 7). One driver runs at a time: a second one started while
/// the first is alive does nothing and writes nothing.
///
/// Writes steps.log (a line per event), result.txt (the outcome, last: a
/// "status:" line the Mac decides by, then the "DRIVER RESULT:" line) and
/// shots\NN-label.png into --out, and PUTs each to --report as it is written,
/// so the Mac has the evidence even if the machine stops answering.
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

    public static int Main(string[] args)
    {
        string url = "https://github.com/russellgordon/plantoir/releases/latest/download/PlantoirSetup.exe";
        bool watchOnly = Array.IndexOf(args, "--self-test-final-watch") >= 0;
        for (int i = 0; i < args.Length - 1; i++)
        {
            if (args[i] == "--url") url = args[i + 1];
            if (args[i] == "--out") _out = args[i + 1];
            if (args[i] == "--report") _report = args[i + 1];
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
            return Finish(stop.Outcome, stop.Message);
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
        Note($"FINAL WATCH BEGINS: {WindowRules.FinalWatchLength.TotalSeconds:0} s");
        int looks = _watch.Observe(WindowRules.FinalWatchLength);
        bool enough = WindowRules.LookedEnough(looks, WindowRules.FinalWatchLength, out int required);
        Note($"FINAL WATCH ENDED: nothing unexpected; {looks} real looks (at least {required} required), {_watch.FailedLooks} looks in the whole run could not read the desktop, "
             + $"{_watch.Unreadable} different top-level windows could not be read at some look (each recorded above), {_watch.UnreadablePopups} popups inside Plantoir's window could not be read");
        if (!enough)
            throw Stopped.Driver($"the final watch made only {looks} real looks in {WindowRules.FinalWatchLength.TotalSeconds:0} s (at least {required} required), so it did not really watch");
        Shot("final-watch");
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

    private static int Finish(Outcome outcome, string reason)
    {
        string shot = Shot("result");
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
        string line = $"DRIVER RESULT (the driver's own; the Mac's final outcome is the last line of its report): {word}{where}: {reason} [screenshot {shot}]";
        Note(line);
        string path = Path.Combine(_out, "result.txt");
        File.WriteAllText(path, "status: " + status + Environment.NewLine + line + Environment.NewLine);
        Send(path, "result.txt");
        return outcome switch { Outcome.Passed => 0, Outcome.ProductStopped => 2, Outcome.SelfTestOnly => 3, _ => 1 };
    }
}

internal enum Outcome { Passed, ProductStopped, DriverProblem, SelfTestOnly }

/// <summary>Ends the run with an outcome. Thrown from any step.</summary>
internal sealed class Stopped : Exception
{
    public Outcome Outcome { get; }
    public Stopped(Outcome outcome, string message) : base(message) => Outcome = outcome;

    public static Stopped Product(string message) => new(Outcome.ProductStopped, message);
    public static Stopped Driver(string message) => new(Outcome.DriverProblem, message);
}
