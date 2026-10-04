using FlaUI.Core.AutomationElements;
using FlaUI.Core.Definitions;
using FlaUI.Core.Input;
using FlaUI.Core.Tools;
using FlaUI.Core.WindowsAPI;
using Xunit.Abstractions;

namespace Plantoir.UiTests;

/// <summary>
/// #191 through the real window, and the MEASUREMENT #191 asks for.
/// </summary>
/// <remarks>
/// <para><b>The control first (bundle 11, W2).</b> With NO dialog up, each of
/// the four window-level accelerators (Ctrl+Shift+R, F2, Ctrl+N, Ctrl+O) is
/// pressed and what it opens is closed again (the rename dialog, the second
/// window, the folder picker). <c>DialogGate.Holds</c> records every ARRIVAL in
/// a redirected run (<c>accelerators-arrived.txt</c>: "&lt;key&gt; passed" or
/// "held"), and each key must be recorded as "passed" — so keystrokes from
/// this test demonstrably reach the window's handlers. Without that, a key
/// missing from the held list could mean only that the keystroke went
/// somewhere else.</para>
///
/// <para><b>Then the measurement.</b> With a confirmation up, the same four
/// keys again; a key recorded "held" is one WinUI DID deliver under the dialog
/// (the guard stopped it), and one not recorded never reached its handler.
/// Either answer passes — reported in the test output and in
/// <c>%TEMP%\plantoir-191-measurement.txt</c>. What it ASSERTS whatever the
/// measurement: no rename dialog, no second window, the confirmation still the
/// one dialog on screen. First run on an unlocked desktop: bundle 11, run 1.</para>
/// </remarks>
[Collection("drives the real app")]
public class AcceleratorUnderDialogUiTests
{
    /// <summary><c>Plantoir.Services.DialogGate.ArrivedFileName</c>; this project
    /// references Plantoir.Core only, so the name is repeated.</summary>
    private const string ArrivedRecord = "accelerators-arrived.txt";

    private static readonly string[] Pressed = { "Ctrl+Shift+R", "F2", "Ctrl+N", "Ctrl+O" };

    private readonly ITestOutputHelper _output;

    public AcceleratorUnderDialogUiTests(ITestOutputHelper output) => _output = output;

    private static void Press(string key)
    {
        switch (key)
        {
            case "F2": Keyboard.Press(VirtualKeyShort.F2); break;
            case "Ctrl+Shift+R": Keyboard.TypeSimultaneously(VirtualKeyShort.CONTROL, VirtualKeyShort.SHIFT, VirtualKeyShort.KEY_R); break;
            case "Ctrl+N": Keyboard.TypeSimultaneously(VirtualKeyShort.CONTROL, VirtualKeyShort.KEY_N); break;
            case "Ctrl+O": Keyboard.TypeSimultaneously(VirtualKeyShort.CONTROL, VirtualKeyShort.KEY_O); break;
        }
    }

    private static List<string> Arrivals(DrivenApp app)
    {
        string record = Path.Combine(app.StateDirectory, ArrivedRecord);
        return File.Exists(record) ? File.ReadAllLines(record).Where(l => l.Length > 0).ToList() : new List<string>();
    }

    [UiFact]
    public void TheFourAcceleratorsUnderAConfirmationDoNothing_AndSayWhetherTheyArrived()
    {
        using var app = new DrivenApp(CourseFixtures.WriteBoth);
        var desktop = app.Window.Automation.GetDesktop();
        int pid = app.Window.Properties.ProcessId.Value;
        int windowsBefore = desktop.FindAllChildren(cf => cf.ByProcessId(pid)).Length;

        app.Find("sidebar-ICS3U", "the ICS3U row").Click();       // F2 renames the SELECTED course

        // ---- The positive control: no dialog up, each key arrives, and what it opens is shut.
        foreach (string key in Pressed)
        {
            app.Window.Focus();
            int before = Arrivals(app).Count;
            Press(key);
            Assert.True(Retry.WhileFalse(() => Arrivals(app).Skip(before).Contains($"{key} passed"),
                                         TimeSpan.FromSeconds(8), TimeSpan.FromMilliseconds(200)).Result,
                        $"{key}, pressed with no dialog up, never reached its handler — so its absence under a dialog would prove nothing. Recorded: {string.Join(", ", Arrivals(app))}");
            CloseWhatTheKeyOpened(app, key, pid, windowsBefore);
        }

        // ---- The measurement, under a confirmation.
        app.Find("sidebar-ICS3U", "the ICS3U row").RightClick();
        var backUp = Retry.WhileNull(
            () => desktop.FindFirstDescendant(cf => cf.ByName("Back Up Now").And(cf.ByControlType(ControlType.MenuItem))),
            TimeSpan.FromSeconds(5), TimeSpan.FromMilliseconds(200)).Result;
        Assert.NotNull(backUp);
        backUp!.Click();     // its "saved" note is a ContentDialog

        var ok = Retry.WhileNull(
            () => desktop.FindFirstDescendant(cf => cf.ByControlType(ControlType.Button).And(cf.ByName("OK"))),
            TimeSpan.FromSeconds(15), TimeSpan.FromMilliseconds(300)).Result;
        Assert.NotNull(ok);

        int heldFrom = Arrivals(app).Count;
        // Ctrl+O LAST: if the guard ever failed it would open the native
        // folder picker, which would sit on top of everything after it.
        foreach (string key in new[] { "F2", "Ctrl+Shift+R", "Ctrl+N", "Ctrl+O" })
        {
            Press(key);
            Thread.Sleep(key == "Ctrl+O" ? 1500 : 800);
        }

        var under = Arrivals(app).Skip(heldFrom).ToList();
        string measured = string.Join(Environment.NewLine, Pressed.Select(key =>
            $"{key}: {(under.Contains($"{key} held") ? "DELIVERED under the dialog (the guard held it)" : "not delivered (the dialog kept it)")}"))
            + Environment.NewLine + "control (no dialog): all four arrived at their handlers";
        _output.WriteLine("#191 measurement, " + DateTime.Now.ToString("yyyy-MM-dd HH:mm") + ":\n" + measured);
        File.WriteAllText(Path.Combine(Path.GetTempPath(), "plantoir-191-measurement.txt"), measured + Environment.NewLine);

        // ---- The behaviour, whatever the measurement.
        Assert.DoesNotContain(under, line => line.EndsWith(" passed", StringComparison.Ordinal));   // nothing ACTED under the dialog
        Assert.Null(desktop.FindFirstDescendant(cf => cf.ByName("Rename ICS3U")));   // the rename dialog's title
        Assert.Equal(windowsBefore, desktop.FindAllChildren(cf => cf.ByProcessId(pid)).Length);   // no new window, no picker
        Assert.NotNull(desktop.FindFirstDescendant(cf => cf.ByControlType(ControlType.Button).And(cf.ByName("OK"))));
        ok!.Click();
    }

    /// <summary>Shut whatever the key opened in the control, and wait until it has gone.</summary>
    private static void CloseWhatTheKeyOpened(DrivenApp app, string key, int pid, int windowsBefore)
    {
        var desktop = app.Desktop;
        switch (key)
        {
            case "F2":
                var rename = Retry.WhileNull(() => app.OpenDialog(), TimeSpan.FromSeconds(10), TimeSpan.FromMilliseconds(200)).Result
                             ?? throw new Xunit.Sdk.XunitException("F2 arrived but no rename dialog opened");
                rename.FindFirstDescendant(cf => cf.ByAutomationId("CloseButton"))!.AsButton().Invoke();
                Assert.True(Retry.WhileFalse(() => app.OpenDialog() is null, TimeSpan.FromSeconds(10)).Result, "the rename dialog would not close");
                break;
            case "Ctrl+N":
                Assert.True(Retry.WhileFalse(() => desktop.FindAllChildren(cf => cf.ByProcessId(pid)).Length > windowsBefore,
                                             TimeSpan.FromSeconds(15), TimeSpan.FromMilliseconds(250)).Result, "Ctrl+N arrived but no second window opened");
                var second = desktop.FindAllChildren(cf => cf.ByProcessId(pid))
                                    .First(w => w.Properties.NativeWindowHandle.ValueOrDefault != app.Window.Properties.NativeWindowHandle.ValueOrDefault);
                second.AsWindow().Close();
                Assert.True(Retry.WhileFalse(() => desktop.FindAllChildren(cf => cf.ByProcessId(pid)).Length == windowsBefore,
                                             TimeSpan.FromSeconds(15), TimeSpan.FromMilliseconds(250)).Result, "the second window would not close");
                break;
            case "Ctrl+O":
                AutomationElement? Picker() =>
                    app.Window.FindFirstDescendant(cf => cf.ByClassName("#32770"))
                    ?? desktop.FindFirstChild(cf => cf.ByClassName("#32770").And(cf.ByProcessId(pid)));
                var picker = Retry.WhileNull(Picker, TimeSpan.FromSeconds(15), TimeSpan.FromMilliseconds(250)).Result
                             ?? throw new Xunit.Sdk.XunitException("Ctrl+O arrived but no folder picker opened");
                picker.FindFirstDescendant(cf => cf.ByAutomationId("2").And(cf.ByControlType(ControlType.Button)))!.AsButton().Invoke();
                Assert.True(Retry.WhileFalse(() => Picker() is null, TimeSpan.FromSeconds(10)).Result, "the folder picker would not close");
                break;
        }
        app.Window.Focus();
        Thread.Sleep(500);
    }
}
