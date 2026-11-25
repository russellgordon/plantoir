using System.Text.RegularExpressions;
using Plantoir.Core.Models;

namespace Plantoir.Tests;

/// <summary>
/// #928 items 6 and 7, the review's M1: every way out of the quit question
/// that leaves the app running takes the quit back, so a parked preview start
/// asks <see cref="PreviewStarts.TheStartStillBelongs"/> with the quit not
/// gone ahead and Preview works again. Each pass is driven the way
/// <c>MainWindow.AskBeforeQuittingThroughWork</c> drives it.
/// </summary>
public class QuitGoingAheadTests
{
    private sealed class Close
    {
        public readonly QuitGoingAhead Quit = new(new PreviewAgainPresses());
        public int CopiesLetGo;
        public readonly object Window = new();
        public QuitGoingAhead.Pass Pass() => Quit.BeginPass(whenTakenBack: () => CopiesLetGo++, window: Window);
    }

    /// <summary>Whether a start parked behind a stop would run its launcher now.</summary>
    private static bool PreviewWorks(Close close)
    {
        Guid start = Guid.NewGuid();
        return PreviewStarts.TheStartStillBelongs(start, start, viewIsGone: false, appIsQuitting: close.Quit.HasGoneAhead);
    }

    /// <summary>Asked on the first pass, Keep Working.</summary>
    [Fact]
    public void KeepWorkingOnTheFirstPass()
    {
        var close = new Close();
        using (close.Pass()) { }
        Assert.False(close.Quit.HasGoneAhead);
        Assert.True(PreviewWorks(close));
    }

    /// <summary>
    /// The review's M1: nothing under way, so no question; the quit goes
    /// ahead and waits for a tools copy; the close comes back through, a
    /// preview has begun meanwhile, the question is asked, Keep Working.
    /// </summary>
    [Fact]
    public void KeepWorkingWhenAskedAgainAfterTheWait()
    {
        var close = new Close();
        using (var first = close.Pass())
        {
            first.GoAhead();
            Assert.False(PreviewWorks(close), "a parked start ran while the quit went ahead");
            // The wait for the copy, then Close(): the next pass decides.
            first.HandOnToTheNextPass();
            using (close.Pass()) { }   // asked again: Keep Working
        }
        Assert.False(close.Quit.HasGoneAhead, "Keep Working left the quit set: Preview starts nothing");
        Assert.True(PreviewWorks(close));
        Assert.Equal(1, close.CopiesLetGo);
    }

    /// <summary>Another window opened while this one waited: this close no longer quits.</summary>
    [Fact]
    public void AWindowOpenedDuringTheWait()
    {
        var close = new Close();
        using (var first = close.Pass())
        {
            first.GoAhead();
            using (var second = close.Pass()) second.NotAQuit();   // Close() of a window that is not the last
        }
        Assert.False(close.Quit.HasGoneAhead);
        Assert.True(PreviewWorks(close));
    }

    /// <summary>
    /// Review 2's L11: the pass that waited hands on and ENDS before its
    /// Close() comes back through (a close dispatched later), a window opens
    /// meanwhile, and the next pass finds the close is not the quit. It takes
    /// the quit back, since the pass that set it is gone.
    /// </summary>
    [Fact]
    public void AHandedOnQuitThatIsNoLongerAQuitIsTakenBack()
    {
        var close = new Close();
        using (var first = close.Pass())
        {
            first.GoAhead();
            first.HandOnToTheNextPass();
        }
        Assert.True(close.Quit.HasGoneAhead);
        using (var second = close.Pass()) second.NotAQuit();   // another window is open now
        Assert.False(close.Quit.HasGoneAhead, "the handed-on quit was kept: Preview starts nothing");
        Assert.True(PreviewWorks(close));

        // Another window's close is not handed this window's quit.
        var other = new Close();
        using (var first = other.Pass()) { first.GoAhead(); first.HandOnToTheNextPass(); }
        using (var elsewhere = other.Quit.BeginPass(() => { }, window: new object())) elsewhere.NotAQuit();
        Assert.True(other.Quit.HasGoneAhead);
    }

    /// <summary>The handler failed after the quit went ahead (even after it had handed on).</summary>
    [Fact]
    public void TheHandlerFailed()
    {
        var close = new Close();
        using (var pass = close.Pass())
        {
            pass.GoAhead();
            pass.HandOnToTheNextPass();
            pass.TakeBack();   // the catch
        }
        Assert.False(close.Quit.HasGoneAhead);
        Assert.True(PreviewWorks(close));
    }

    /// <summary>The close goes through, on the first pass or the next: the quit stays gone ahead.</summary>
    [Fact]
    public void TheCloseGoesThrough()
    {
        var close = new Close();
        using (var first = close.Pass())
        {
            first.GoAhead();
            first.HandOnToTheNextPass();
            using (var second = close.Pass())
            {
                second.GoAhead();
                second.TheCloseGoesThrough();
            }
        }
        Assert.True(close.Quit.HasGoneAhead);
        Assert.False(PreviewWorks(close));
        Assert.Equal(0, close.CopiesLetGo);
    }

    /// <summary>A second close while the first waits is no quit of its own and takes nothing back.</summary>
    [Fact]
    public void ASecondCloseDuringTheWaitTakesNothingBack()
    {
        var close = new Close();
        var first = close.Pass();
        first.GoAhead();
        using (var second = close.Pass()) second.NotAQuit();
        Assert.True(close.Quit.HasGoneAhead);
        first.TheCloseGoesThrough();
        first.Dispose();
    }

    /// <summary>The quit going ahead abandons every repair's Preview Again.</summary>
    [Fact]
    public void GoingAheadAbandonsEveryPress()
    {
        var presses = new PreviewAgainPresses();
        var quit = new QuitGoingAhead(presses);
        presses.Press(Guid.NewGuid());
        using (var pass = quit.BeginPass(() => { })) { pass.GoAhead(); pass.TheCloseGoesThrough(); }
        Assert.Empty(presses.UnderWay);
    }

    /// <summary>
    /// The handler sets and clears the quit only through its one pass: no
    /// other call that takes it back, so no path can be forgotten.
    /// </summary>
    [Fact]
    public void TheClosingHandlerUsesOnePass()
    {
        string code = Regex.Replace(File.ReadAllText(Path.Combine(ContractLoader.RepositoryRoot,
            "windows-app", "Plantoir", "MainWindow.xaml.cs")), @"//[^\n]*", "");
        int at = code.IndexOf("private async void AskBeforeQuittingThroughWork(", StringComparison.Ordinal);
        Assert.True(at >= 0, "the closing handler moved");
        int end = code.IndexOf("private void LetHeldCopiesGo(", at, StringComparison.Ordinal);
        string handler = code[at..end];
        Assert.Contains("using var pass = Plantoir.Core.Models.QuitGoingAhead.Shared.BeginPass(whenTakenBack: LetHeldCopiesGo, window: this)", handler);
        Assert.DoesNotContain("LetHeldCopiesGo()", handler);
        Assert.DoesNotContain("TheQuitWasTakenBack", handler);
        Assert.DoesNotContain("LetThePreviewStartsGo", handler);
    }
}
