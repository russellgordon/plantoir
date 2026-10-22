using System;
using System.Collections.Generic;

namespace Plantoir.Core.Models;

/// <summary>
/// Where a REMEMBERED main window may reopen (#558): exactly where it was, if
/// a teacher can still grab it by its title bar on some display — or else
/// shrunk to fit and centred on the display nearest it.
/// </summary>
/// <remarks>
/// <para>Pure geometry in physical pixels, so it is tested without a desktop
/// (<c>WindowFrameFitTests</c>); <c>MainWindow</c>'s constructor hands it the
/// remembered frame, every display's work area and the nearest one.</para>
///
/// <para><b>Reachable</b> means the title-bar strip (the frame's top
/// <c>titleBarHeight</c> pixels) overlaps SOME work area by at least
/// <c>minimumGrabWidth</c> across and a third of the strip down. The overlap
/// need not be the whole strip, and that is deliberate: a window quit
/// maximised is saved a few pixels outside its display (about (-11, -11) at
/// 150%), a window can straddle two monitors side by side or stacked, and a
/// top taskbar covers part of a strip — all frames a teacher left on
/// purpose, which must come back exactly where they were.</para>
///
/// <para>REJECTED: always clamping the frame into the nearest work area,
/// which moves every one of those deliberate frames; and clamping only the
/// SIZE, which is what #542 left in place — the size fitted the nearest
/// display while the position stayed off it.</para>
/// </remarks>
public static class WindowFrameFit
{
    /// <summary>A rectangle in physical pixels.</summary>
    public readonly record struct Frame(int X, int Y, int Width, int Height)
    {
        public int Right => X + Width;
        public int Bottom => Y + Height;
    }

    /// <summary>The frame to open at: <paramref name="frame"/> itself when its
    /// title bar can be grabbed on some display, else fitted to and centred
    /// on <paramref name="nearestWorkArea"/>.</summary>
    public static Frame Fit(Frame frame, IReadOnlyList<Frame> workAreas, Frame nearestWorkArea,
                            int titleBarHeight, int minimumGrabWidth)
    {
        if (TitleBarIsReachable(frame, workAreas, titleBarHeight, minimumGrabWidth)) return frame;
        return Centred(frame.Width, frame.Height, nearestWorkArea);
    }

    /// <summary>Whether some work area holds enough of the title-bar strip to
    /// drag the window by.</summary>
    public static bool TitleBarIsReachable(Frame frame, IReadOnlyList<Frame> workAreas,
                                           int titleBarHeight, int minimumGrabWidth)
    {
        int stripHeight = Math.Max(1, Math.Min(titleBarHeight, frame.Height));
        int needAcross = Math.Max(1, Math.Min(minimumGrabWidth, frame.Width));
        int needDown = Math.Max(1, stripHeight / 3);
        foreach (var work in workAreas)
        {
            int across = Math.Min(frame.Right, work.Right) - Math.Max(frame.X, work.X);
            int down = Math.Min(frame.Y + stripHeight, work.Bottom) - Math.Max(frame.Y, work.Y);
            if (across >= needAcross && down >= needDown) return true;
        }
        return false;
    }

    /// <summary>A window of this size, no larger than the work area, centred on it.</summary>
    public static Frame Centred(int width, int height, Frame workArea)
    {
        int w = Math.Min(width, workArea.Width);
        int h = Math.Min(height, workArea.Height);
        return new Frame(workArea.X + (workArea.Width - w) / 2, workArea.Y + (workArea.Height - h) / 2, w, h);
    }
}
