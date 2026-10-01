using FlaUI.Core.Definitions;
using FlaUI.Core.Input;
using FlaUI.Core.Tools;
using FlaUI.Core.WindowsAPI;

namespace Plantoir.UiTests;

/// <summary>
/// #191 through the real window: with a confirmation up, F2 raises no rename
/// dialog and the confirmation is still the one dialog on screen. UNPROVEN as
/// of 2026-10-01 (written while the desktop was locked; compiled, never run).
/// It is also the MEASUREMENT #191 asks for: run once with the guard removed
/// to learn whether WinUI delivers the key under a dialog at all.
/// </summary>
[Collection("drives the real app")]
public class AcceleratorUnderDialogUiTests
{
    [UiFact]
    public void F2UnderAConfirmationRaisesNoSecondDialog()
    {
        using var app = new DrivenApp(CourseFixtures.WriteBoth);
        var desktop = app.Window.Automation.GetDesktop();

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

        Keyboard.Press(VirtualKeyShort.F2);
        Thread.Sleep(1500);
        Assert.Null(desktop.FindFirstDescendant(cf => cf.ByName("Rename ICS3U")));   // the rename dialog's title
        ok!.Click();
    }
}
