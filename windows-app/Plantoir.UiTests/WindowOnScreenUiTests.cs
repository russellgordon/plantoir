using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json.Nodes;
using Xunit.Abstractions;

namespace Plantoir.UiTests;

/// <summary>
/// #558: a remembered window whose display is gone reopens INSIDE a work area
/// rather than off every screen. The single-display variant the issue gives:
/// a remembered frame seeded at X = 5000 with "restore windows on launch" on,
/// then the window's visible frame is read in physical pixels and must sit
/// inside the work area of the display nearest it.
/// </summary>
/// <remarks>
/// <para>The geometry itself (when a frame is kept exactly as remembered, when
/// it is moved, by how much) is <c>WindowFrameFitTests</c> in the ordinary
/// suite; this is the proof that the constructor applies it to a real
/// window. The measured line goes to the test output and
/// <c>%TEMP%\plantoir-558-onscreen.txt</c>.</para>
/// </remarks>
[Collection("drives the real app")]
public class WindowOnScreenUiTests
{
    private readonly ITestOutputHelper _output;

    public WindowOnScreenUiTests(ITestOutputHelper output) => _output = output;

    [DllImport("user32.dll")] private static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
    [DllImport("user32.dll")] private static extern IntPtr MonitorFromWindow(IntPtr hwnd, uint flags);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern bool GetMonitorInfo(IntPtr monitor, ref MonitorInfo info);
    [DllImport("dwmapi.dll")] private static extern int DwmGetWindowAttribute(IntPtr hwnd, int attribute, out Rect rect, int size);

    [StructLayout(LayoutKind.Sequential)] private struct Rect { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)]
    private struct MonitorInfo { public int Size; public Rect Monitor, Work; public uint Flags; }

    private static readonly IntPtr PerMonitorAwareV2 = new(-4);
    private const int ExtendedFrameBounds = 9;   // DWMWA_EXTENDED_FRAME_BOUNDS

    private static string Describe(Rect r) => $"{r.Right - r.Left}x{r.Bottom - r.Top} at ({r.Left},{r.Top})";

    [UiFact]
    public void ARememberedFrameOffEveryDisplayOpensInsideTheWorkArea()
    {
        using var app = new DrivenApp(CourseFixtures.WriteBoth, restoreWindows: true, beforeLaunch: folder =>
        {
            string path = Path.Combine(Path.GetDirectoryName(folder)!, "state", "settings.json");
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            var json = File.Exists(path) ? JsonNode.Parse(File.ReadAllText(path))!.AsObject() : new JsonObject();
            json["RestoreWindowsOnLaunch"] = true;
            json["RememberedWindows"] = new JsonArray(new JsonObject
            {
                ["Path"] = folder, ["X"] = 5000, ["Y"] = 200, ["Width"] = 1400, ["Height"] = 900,
            });
            File.WriteAllText(path, json.ToJsonString(), new UTF8Encoding(false));
        });

        var window = app.Window;
        WindowMinimumUiTests.Settle(window);
        IntPtr hwnd = window.Properties.NativeWindowHandle.Value;

        Rect visible, work;
        IntPtr old = SetThreadDpiAwarenessContext(PerMonitorAwareV2);
        try
        {
            DwmGetWindowAttribute(hwnd, ExtendedFrameBounds, out visible, Marshal.SizeOf<Rect>());
            var info = new MonitorInfo { Size = Marshal.SizeOf<MonitorInfo>() };
            GetMonitorInfo(MonitorFromWindow(hwnd, 2 /* nearest */), ref info);
            work = info.Work;
        }
        finally { SetThreadDpiAwarenessContext(old); }

        string measured = $"seeded 1400x900 at (5000,200); visible frame {Describe(visible)}; work area {Describe(work)}";
        _output.WriteLine("#558 measurement, " + DateTime.Now.ToString("yyyy-MM-dd HH:mm") + ": " + measured);
        File.WriteAllText(Path.Combine(Path.GetTempPath(), "plantoir-558-onscreen.txt"), measured + Environment.NewLine);

        // One pixel of slack a side: the visible frame and the work area are
        // both whole pixels, and a centred odd remainder rounds.
        Assert.True(visible.Left >= work.Left - 1 && visible.Top >= work.Top - 1 &&
                    visible.Right <= work.Right + 1 && visible.Bottom <= work.Bottom + 1,
                    $"the window opened outside the work area: {measured}");
    }
}
