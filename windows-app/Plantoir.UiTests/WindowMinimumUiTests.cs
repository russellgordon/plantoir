using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json.Nodes;
using FlaUI.Core.AutomationElements;
using FlaUI.Core.Tools;
using Plantoir.Core.Models;
using Xunit.Abstractions;

namespace Plantoir.UiTests;

/// <summary>
/// #542: at its narrowest the main window still shows the whole toolbar —
/// Preview (titled "Preview at Last Viewed", the longest it gets, #514),
/// Deploy and Open in Browser — at their full width and inside the window.
/// </summary>
/// <remarks>
/// <para>Two moments are checked. At LAUNCH the window must already be at
/// least 900 × 600 epx: on 2026-10-16 it opened at 1190 × 725 px, 793 × 483
/// epx at 150%, because the first-run size was set before the minimum (the
/// defect #542 turned out to be). Then the window is MAXIMISED and each
/// button's width read there, restored, asked for 400 × 400 px and given its
/// minimum; each button's width is compared with its width in the maximised
/// window, so a button squeezed narrower fails as surely as one pushed off
/// the edge. (Not with the launch window: since the fix that IS the minimum
/// here, and the comparison would be with itself.) The right edge is held 8 px × scale inside the window's,
/// because UI Automation's window rectangle includes Windows 11's invisible
/// resize border (about 7 px a side at 150%), so a button flush against the
/// rectangle's edge is already under the border and clipped.</para>
///
/// <para>The setting is SEEDED (<c>"PreviewOpensAt":"lastViewed"</c>), not
/// reached by holding Alt, so the worst title is up without a held key.</para>
///
/// <para>At 100% display scale the minimum is the same in pixels and in
/// epx, so this cannot tell #542's two builds apart there: it is a guard at
/// any scale and a proof at 150% and above. The measured line goes to the
/// test output and <c>%TEMP%\plantoir-542-minimum.txt</c>, with the
/// window's frame read twice — through UI Automation and through
/// <c>GetWindowRect</c> on a thread made per-monitor DPI-aware — so a
/// reader can see which units each number is in.</para>
/// </remarks>
[Collection("drives the real app")]
public class WindowMinimumUiTests
{
    private readonly ITestOutputHelper _output;

    public WindowMinimumUiTests(ITestOutputHelper output) => _output = output;

    [DllImport("user32.dll")] private static extern uint GetDpiForWindow(IntPtr hwnd);
    [DllImport("user32.dll")] private static extern bool ShowWindow(IntPtr hwnd, int command);
    [DllImport("user32.dll")] private static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
    [DllImport("user32.dll")] private static extern bool GetWindowRect(IntPtr hwnd, out Rect rect);
    [DllImport("user32.dll")] private static extern IntPtr MonitorFromWindow(IntPtr hwnd, uint flags);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern bool GetMonitorInfo(IntPtr monitor, ref MonitorInfo info);
    [DllImport("dwmapi.dll")] private static extern int DwmGetWindowAttribute(IntPtr hwnd, int attribute, out Rect rect, int size);

    [StructLayout(LayoutKind.Sequential)] private struct Rect { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)]
    private struct MonitorInfo { public int Size; public Rect Monitor, Work; public uint Flags; }

    private static readonly IntPtr PerMonitorAwareV2 = new(-4);
    private const int ExtendedFrameBounds = 9;   // DWMWA_EXTENDED_FRAME_BOUNDS

    /// <summary>The window's frame and its monitor's work area in PHYSICAL
    /// pixels, read on this thread made per-monitor aware for the call: the
    /// test host itself is not DPI-aware, and a non-aware caller is handed
    /// rectangles virtualised to 96 dpi.</summary>
    private static (Rect window, Rect visible, Rect work) Physical(IntPtr hwnd)
    {
        IntPtr old = SetThreadDpiAwarenessContext(PerMonitorAwareV2);
        try
        {
            GetWindowRect(hwnd, out var window);
            DwmGetWindowAttribute(hwnd, ExtendedFrameBounds, out var visible, Marshal.SizeOf<Rect>());
            var info = new MonitorInfo { Size = Marshal.SizeOf<MonitorInfo>() };
            GetMonitorInfo(MonitorFromWindow(hwnd, 2 /* nearest */), ref info);
            return (window, visible, info.Work);
        }
        finally { SetThreadDpiAwarenessContext(old); }
    }

    private static string Describe(Rect r) => $"{r.Right - r.Left}x{r.Bottom - r.Top} at ({r.Left},{r.Top})";

    /// <summary>Waits until the window's size stops changing, rather than for
    /// a number (the number is what is under test): THREE equal reads in a
    /// row, 300 ms apart, since two can both land before an asynchronous
    /// resize does. Then a moment for the toolbar to lay out.</summary>
    internal static void Settle(FlaUI.Core.AutomationElements.Window window)
    {
        var last = System.Drawing.Rectangle.Empty;
        int same = 0;
        Retry.WhileFalse(() =>
        {
            var now = window.BoundingRectangle;
            same = now == last ? same + 1 : 0;
            last = now;
            return same >= 2;
        }, TimeSpan.FromSeconds(6), TimeSpan.FromMilliseconds(300));
        Thread.Sleep(800);
    }

    [UiFact]
    public void AtItsNarrowestTheWindowStillShowsPreviewDeployAndBrowser()
    {
        using var app = new DrivenApp(CourseFixtures.WriteBoth, beforeLaunch: folder =>
        {
            string path = Path.Combine(Path.GetDirectoryName(folder)!, "state", "settings.json");
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            var json = File.Exists(path) ? JsonNode.Parse(File.ReadAllText(path))!.AsObject() : new JsonObject();
            json["PreviewOpensAt"] = "lastViewed";
            File.WriteAllText(path, json.ToJsonString(), new UTF8Encoding(false));
        });
        app.SelectSection(CourseFixtures.Renamed, 1);

        var preview = app.Find("previewButton", "the Preview button");
        var deploy = app.Find("deployButton", "the Deploy button");
        var browser = app.Find("openInBrowserButton", "Open in Browser");
        Assert.Equal(PreviewStartPage.PreviewAtLastViewed, preview.Name);
        var buttons = new[] { ("Preview", preview), ("Deploy", deploy), ("Browser", browser) };

        var window = app.Window;
        IntPtr hwnd = window.Properties.NativeWindowHandle.Value;
        double scale = GetDpiForWindow(hwnd) / 96.0;
        var before = Physical(hwnd);
        var launchBox = window.BoundingRectangle;
        var launchEdges = buttons.ToDictionary(b => b.Item1, b => launchBox.Right - b.Item2.BoundingRectangle.Right);
        string wideLine = $"at launch: UIA {launchBox.Width}x{launchBox.Height}, " +
                          $"GetWindowRect {Describe(before.window)}, visible {Describe(before.visible)}, right edges inside " +
                          string.Join("/", buttons.Select(b => $"{b.Item1} {launchEdges[b.Item1]}"));

        // The buttons' WIDE widths are read in a MAXIMISED window: after #542
        // the launch window IS the minimum here, so comparing against it would
        // compare a layout with itself.
        // ShowWindow, not UI Automation's WindowPattern: measured 2026-10-16,
        // SetWindowVisualState(Maximized) left this window at 900 × 600 epx.
        ShowWindow(hwnd, 3 /* SW_MAXIMIZE */);
        Settle(window);
        var maximisedBox = window.BoundingRectangle;
        var wide = buttons.ToDictionary(b => b.Item1, b => b.Item2.BoundingRectangle.Width);
        wideLine += $"; maximised: UIA {maximisedBox.Width}x{maximisedBox.Height}, buttons " +
                    string.Join("/", buttons.Select(b => $"{b.Item1} {wide[b.Item1]}"));
        Assert.True(maximisedBox.Width > launchBox.Width,
            $"the window did not grow when maximised, so the wide widths would be the narrow ones: {wideLine}");
        ShowWindow(hwnd, 9 /* SW_RESTORE */);
        Settle(window);

        window.Patterns.Transform.Pattern.Resize(400, 400);
        Settle(window);

        var box = window.BoundingRectangle;
        var after = Physical(hwnd);
        int workWidth = after.work.Right - after.work.Left, workHeight = after.work.Bottom - after.work.Top;
        var parts = new List<string>();
        foreach (var (name, element) in buttons)
        {
            var b = element.BoundingRectangle;
            parts.Add($"{name} {b.Width} wide (was {wide[name]}), right edge {box.Right - b.Right} inside");
        }
        string measured = $"scale {scale:0.##}; {wideLine}; narrowest: UIA {box.Width}x{box.Height}, " +
                          $"GetWindowRect {Describe(after.window)}, visible {Describe(after.visible)}, " +
                          $"work area {workWidth}x{workHeight}; " + string.Join("; ", parts);
        _output.WriteLine("#542 measurement, " + DateTime.Now.ToString("yyyy-MM-dd HH:mm") + ": " + measured);
        File.WriteAllText(Path.Combine(Path.GetTempPath(), "plantoir-542-minimum.txt"), measured + Environment.NewLine);

        // Physical pixels throughout from here, so the units cannot be mixed:
        // UIA's rectangles are in the same units as UIA's window, whatever
        // those are, and the floor is checked on GetWindowRect's physical one.
        // At LAUNCH first (#542 as measured): the first-run size is a share of
        // the work area, 1190 px on a 1920 one, which at 150% is 793 epx, below
        // the 900 epx minimum, because the size was set before the minimum and
        // setting a minimum does not grow a window that is already narrower.
        int launchWidth = before.window.Right - before.window.Left;
        int launchHeight = before.window.Bottom - before.window.Top;
        Assert.True(launchWidth >= Math.Min(Math.Round(900 * scale), workWidth) - 2,
            $"the window opened narrower than 900 epx: {measured}");
        Assert.True(launchHeight >= Math.Min(Math.Round(600 * scale), workHeight) - 2,
            $"the window opened shorter than 600 epx: {measured}");
        double launchUnit = launchBox.Width / (double)launchWidth;
        foreach (var (name, _) in buttons)
            Assert.True(launchEdges[name] >= 8 * scale * launchUnit, $"{name} reaches the window's right edge at launch: {measured}");

        int physicalWidth = after.window.Right - after.window.Left;
        int physicalHeight = after.window.Bottom - after.window.Top;
        Assert.True(physicalWidth >= Math.Min(Math.Round(900 * scale), workWidth) - 2,
            $"the window went narrower than 900 epx: {measured}");
        Assert.True(physicalHeight >= Math.Min(Math.Round(600 * scale), workHeight) - 2,
            $"the window went shorter than 600 epx: {measured}");
        double unit = box.Width / (double)physicalWidth;   // 1 if UIA is physical, 1/scale if virtualised
        foreach (var (name, element) in buttons)
        {
            var b = element.BoundingRectangle;
            Assert.False(element.IsOffscreen, $"{name} is off screen: {measured}");
            Assert.True(Math.Abs(b.Width - wide[name]) <= 1, $"{name} was squeezed from {wide[name]} to {b.Width}: {measured}");
            Assert.True(b.Right <= box.Right - 8 * scale * unit, $"{name} reaches the window's right edge: {measured}");
        }
    }
}
