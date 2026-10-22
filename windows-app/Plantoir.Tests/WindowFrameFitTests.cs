using Plantoir.Core.Models;
using Frame = Plantoir.Core.Models.WindowFrameFit.Frame;

namespace Plantoir.Tests;

/// <summary>
/// #558: a remembered main window reopens exactly where it was when a teacher
/// can grab its title bar on some display, and otherwise fitted to and centred
/// on the nearest one. Physical pixels at 150%: a 48 px title-bar strip
/// (32 epx) and 150 px to grab (100 epx), as <c>MainWindow</c> passes them.
/// </summary>
public class WindowFrameFitTests
{
    private const int TitleBar = 48;
    private const int Grab = 150;

    private static readonly Frame Primary = new(0, 0, 1920, 1032);

    private static Frame Fit(Frame frame, params Frame[] workAreas) =>
        WindowFrameFit.Fit(frame, workAreas, workAreas[0], TitleBar, Grab);

    [Fact]
    public void AFrameOnADisplayIsKeptExactly()
    {
        var frame = new Frame(100, 100, 1400, 900);
        Assert.Equal(frame, Fit(frame, Primary));
    }

    /// <summary>Quit maximised: saved a few pixels OUTSIDE the display, and kept.</summary>
    [Fact]
    public void AFrameQuitMaximisedIsKeptExactly()
    {
        var frame = new Frame(-11, -11, 1942, 1054);
        Assert.Equal(frame, Fit(frame, Primary));
    }

    [Fact]
    public void AFrameAcrossTwoDisplaysSideBySideIsKept()
    {
        var frame = new Frame(1500, 100, 1400, 900);
        Assert.Equal(frame, Fit(frame, Primary, new Frame(1920, 0, 2560, 1392)));
    }

    /// <summary>Stacked monitors: the strip crosses the edge between them.</summary>
    [Fact]
    public void AFrameAcrossStackedDisplaysIsKept()
    {
        var frame = new Frame(200, -24, 1400, 900);
        Assert.Equal(frame, Fit(frame, Primary, new Frame(0, -1080, 1920, 1080)));
    }

    /// <summary>A taskbar at the top covers part of the strip; the rest is enough.</summary>
    [Fact]
    public void AFrameUnderATopTaskbarIsKept()
    {
        var topTaskbar = new Frame(0, 48, 1920, 1032);
        var frame = new Frame(100, 20, 1400, 900);
        Assert.Equal(frame, Fit(frame, topTaskbar));
    }

    [Fact]
    public void ADisplayToTheLeftWithANegativeOriginIsKept()
    {
        var frame = new Frame(-1500, 100, 1400, 900);
        Assert.Equal(frame, Fit(frame, Primary, new Frame(-1920, 0, 1920, 1032)));
    }

    /// <summary>The issue's single-display variant: X = 5000.</summary>
    [Fact]
    public void AFrameOffEveryDisplayIsCentredOnTheNearest()
    {
        Assert.Equal(new Frame(260, 66, 1400, 900), Fit(new Frame(5000, 200, 1400, 900), Primary));
    }

    /// <summary>The second monitor unplugged: the frame it held comes back on the one left.</summary>
    [Fact]
    public void AFrameOnAVanishedDisplayIsCentredOnTheOneLeft()
    {
        Assert.Equal(new Frame(260, 66, 1400, 900), Fit(new Frame(2200, 100, 1400, 900), Primary));
    }

    [Fact]
    public void AFrameLargerThanTheWorkAreaIsShrunkToFitIt()
    {
        Assert.Equal(Primary, Fit(new Frame(5000, 0, 2500, 1500), Primary));
    }

    /// <summary>The body on screen, the title bar above every display: nothing to drag it by.</summary>
    [Fact]
    public void ATitleBarAboveEveryDisplayIsMoved()
    {
        Assert.Equal(new Frame(260, 66, 1400, 900), Fit(new Frame(100, -500, 1400, 900), Primary));
    }

    /// <summary>Only the corner with the window's buttons on screen is not enough to drag by.</summary>
    [Fact]
    public void ASliverOfTitleBarIsNotEnough()
    {
        Assert.NotEqual(new Frame(1800, 100, 1400, 900), Fit(new Frame(1800, 100, 1400, 900), Primary));
        var justEnough = new Frame(1920 - Grab, 100, 1400, 900);
        Assert.Equal(justEnough, Fit(justEnough, Primary));
        // A strip a third in, from below the display: kept; less than a third: moved.
        var third = new Frame(100, 1032 - TitleBar / 3, 1400, 900);
        Assert.Equal(third, Fit(third, Primary));
        var less = new Frame(100, 1032 - TitleBar / 3 + 1, 1400, 900);
        Assert.NotEqual(less, Fit(less, Primary));
    }

    [Fact]
    public void CentredNeverExceedsTheWorkArea()
    {
        Assert.Equal(new Frame(-1920, 0, 1920, 1032), WindowFrameFit.Centred(4000, 3000, new Frame(-1920, 0, 1920, 1032)));
    }
}
