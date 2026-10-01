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
/// <para><b>What it measures.</b> With a confirmation up, it presses all four
/// window-level accelerators (F2, Ctrl+Shift+R, Ctrl+N, Ctrl+O), then reads
/// the record <c>DialogGate.Holds</c> writes in this run's state folder: a key
/// listed there is one WinUI DID deliver under the dialog (so the guard is
/// what stopped it); a key pressed and not listed never reached its handler.
/// Either answer passes — the measurement is reported, in the test output and
/// in <c>%TEMP%\plantoir-191-measurement.txt</c>, for the issue's comment.</para>
///
/// <para><b>What it asserts</b> is the desired behaviour whatever the
/// measurement: no rename dialog, no second window, and the confirmation still
/// the one dialog on screen. UNPROVEN as of 2026-10-01: written while no agent
/// could drive the desktop (bundles 8 and 9); compiled, never run.</para>
/// </remarks>
[Collection("drives the real app")]
public class AcceleratorUnderDialogUiTests
{
    /// <summary><c>Plantoir.Services.DialogGate.HeldUnderADialogFileName</c>;
    /// this project references Plantoir.Core only, so the name is repeated.</summary>
    private const string HeldRecord = "accelerators-held-under-a-dialog.txt";

    private readonly ITestOutputHelper _output;

    public AcceleratorUnderDialogUiTests(ITestOutputHelper output) => _output = output;

    [UiFact]
    public void TheFourAcceleratorsUnderAConfirmationDoNothing_AndSayWhetherTheyArrived()
    {
        using var app = new DrivenApp(CourseFixtures.WriteBoth);
        var desktop = app.Window.Automation.GetDesktop();
        int pid = app.Window.Properties.ProcessId.Value;
        int windowsBefore = desktop.FindAllChildren(cf => cf.ByProcessId(pid)).Length;

        app.Find("sidebar-ICS3U", "the ICS3U row").Click();       // F2 renames the SELECTED course
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

        // Ctrl+O LAST: if the guard ever failed it would open the native
        // folder picker, which would sit on top of everything after it.
        Keyboard.Press(VirtualKeyShort.F2);
        Thread.Sleep(800);
        Keyboard.TypeSimultaneously(VirtualKeyShort.CONTROL, VirtualKeyShort.SHIFT, VirtualKeyShort.KEY_R);
        Thread.Sleep(800);
        Keyboard.TypeSimultaneously(VirtualKeyShort.CONTROL, VirtualKeyShort.KEY_N);
        Thread.Sleep(800);
        Keyboard.TypeSimultaneously(VirtualKeyShort.CONTROL, VirtualKeyShort.KEY_O);
        Thread.Sleep(1500);

        // ---- The measurement.
        string record = Path.Combine(app.StateDirectory, HeldRecord);
        var held = File.Exists(record) ? File.ReadAllLines(record).Where(l => l.Length > 0).ToList() : new List<string>();
        string[] pressed = { "F2", "Ctrl+Shift+R", "Ctrl+N", "Ctrl+O" };
        string measured = string.Join(Environment.NewLine, pressed.Select(key =>
            $"{key}: {(held.Contains(key) ? "DELIVERED under the dialog (the guard held it)" : "not delivered (the dialog kept it)")}"));
        _output.WriteLine("#191 measurement, " + DateTime.Now.ToString("yyyy-MM-dd HH:mm") + ":\n" + measured);
        File.WriteAllText(Path.Combine(Path.GetTempPath(), "plantoir-191-measurement.txt"), measured + Environment.NewLine);

        // ---- The behaviour, whatever the measurement.
        Assert.Null(desktop.FindFirstDescendant(cf => cf.ByName("Rename ICS3U")));   // the rename dialog's title
        Assert.Equal(windowsBefore, desktop.FindAllChildren(cf => cf.ByProcessId(pid)).Length);   // no new window, no picker
        Assert.NotNull(desktop.FindFirstDescendant(cf => cf.ByControlType(ControlType.Button).And(cf.ByName("OK"))));
        ok!.Click();
    }
}
