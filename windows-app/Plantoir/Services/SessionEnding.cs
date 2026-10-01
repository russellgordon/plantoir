using System;
using System.Runtime.InteropServices;

namespace Plantoir.Services;

/// <summary>
/// Knows when Windows itself is logging off, restarting or shutting down, so
/// the quit question is never put up then (#231;
/// <c>quittingWhileWorkIsUnderWay.neverAskWhen</c>). The signal is
/// <c>WM_QUERYENDSESSION</c>, which Windows sends to every top-level window
/// before a session ends — the mac reads <c>kAEQuitReason</c> off the Apple
/// event for the same fact. A modal raised there holds the log-off until
/// Windows names Plantoir as the program that would not close.
/// </summary>
internal static class SessionEnding
{
    private const uint WM_QUERYENDSESSION = 0x0011;
    private const uint WM_ENDSESSION = 0x0016;

    /// <summary>True from the moment Windows asks to end the session.</summary>
    public static bool IsEnding { get; private set; }

    private delegate IntPtr SubclassProc(IntPtr hWnd, uint message, IntPtr wParam, IntPtr lParam,
                                         UIntPtr id, UIntPtr data);

    // Kept alive for the life of the process: the native side holds a pointer to it.
    private static readonly SubclassProc Proc = OnMessage;

    [DllImport("comctl32.dll", SetLastError = true)]
    private static extern bool SetWindowSubclass(IntPtr hWnd, SubclassProc proc, UIntPtr id, UIntPtr data);

    [DllImport("comctl32.dll")]
    private static extern IntPtr DefSubclassProc(IntPtr hWnd, uint message, IntPtr wParam, IntPtr lParam);

    /// <summary>Listen on one window. Harmless when it cannot: the quit then asks as it always would.</summary>
    public static void Watch(IntPtr hWnd)
    {
        try { SetWindowSubclass(hWnd, Proc, (UIntPtr)0x504C, UIntPtr.Zero); } catch { }
    }

    private static IntPtr OnMessage(IntPtr hWnd, uint message, IntPtr wParam, IntPtr lParam, UIntPtr id, UIntPtr data)
    {
        if (message == WM_QUERYENDSESSION) IsEnding = true;
        else if (message == WM_ENDSESSION && wParam == IntPtr.Zero) IsEnding = false;   // the end was called off
        return DefSubclassProc(hWnd, message, wParam, lParam);
    }
}
