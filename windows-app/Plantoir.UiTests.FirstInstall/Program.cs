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
/// Writes steps.log (a line per event), result.txt (the outcome, last) and
/// shots\NN-label.png into --out, and PUTs each to --report as it is written,
/// so the Mac has the evidence even if the machine stops answering.
/// Exit code: 0 passed, 2 product stopped, 1 driver problem.
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
        for (int i = 0; i < args.Length - 1; i++)
        {
            if (args[i] == "--url") url = args[i + 1];
            if (args[i] == "--out") _out = args[i + 1];
            if (args[i] == "--report") _report = args[i + 1];
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
            Steps1To6(url);
            return Finish(Outcome.Passed, "Plantoir was downloaded, installed, opened, set up a working folder, added the example course and served its preview");
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
            _ => "DRIVER PROBLEM",
        };
        string where = outcome == Outcome.Passed ? "" : $" at step {_stepNumber} ({_stepName})";
        string line = $"RESULT: {word}{where}: {reason} [screenshot {shot}]";
        Note(line);
        string path = Path.Combine(_out, "result.txt");
        File.WriteAllText(path, line + Environment.NewLine);
        Send(path, "result.txt");
        return outcome switch { Outcome.Passed => 0, Outcome.ProductStopped => 2, _ => 1 };
    }
}

internal enum Outcome { Passed, ProductStopped, DriverProblem }

/// <summary>Ends the run with an outcome. Thrown from any step.</summary>
internal sealed class Stopped : Exception
{
    public Outcome Outcome { get; }
    public Stopped(Outcome outcome, string message) : base(message) => Outcome = outcome;

    public static Stopped Product(string message) => new(Outcome.ProductStopped, message);
    public static Stopped Driver(string message) => new(Outcome.DriverProblem, message);
}
