using System.Net;
using System.Net.Http;
using System.Net.Sockets;
using System.Text;
using Plantoir.Core.Models;

namespace Plantoir.Tests;

/// <summary>
/// #514's machinery beside the contract: the navigation ledger in the event
/// orders measured on WebView2 155 (documentation/12 → "Preview at Last
/// Viewed on Windows"), the remembered-page store, the page address built
/// back from a path, and one real HTTP status per try.
/// </summary>
public class PreviewNavigationLedgerTests
{
    private static readonly DateTime T0 = new(2026, 10, 15, 12, 0, 0, DateTimeKind.Utc);

    [Fact]
    public void NothingIsUnderWayUntilTheAppAsks()
    {
        var ledger = new PreviewNavigationLedger();
        ledger.NavigationStarting(1, false);
        ledger.ContentLoading(1);
        Assert.False(ledger.AppLoadUnderWay(T0));
    }

    [Fact]
    public void TheRootLoadEndsAtContentLoadingNotAtCompleted()
    {
        // Measured order: Starting → SourceChanged → ContentLoading → Completed.
        var ledger = new PreviewNavigationLedger();
        ledger.AppLoadRequested(T0);
        Assert.True(ledger.AppLoadUnderWay(T0));
        ledger.NavigationStarting(7, false);
        Assert.True(ledger.AppLoadUnderWay(T0));     // its SourceChanged lands here: ignored
        ledger.ContentLoading(7);
        Assert.False(ledger.AppLoadUnderWay(T0));    // a click while fonts load is the teacher's
        ledger.NavigationCompleted(7);
        Assert.False(ledger.AppLoadUnderWay(T0));
    }

    [Fact]
    public void ARedirectKeepsTheIdAndTheLoadEndsAtItsContent()
    {
        var ledger = new PreviewNavigationLedger();
        ledger.AppLoadRequested(T0);
        ledger.NavigationStarting(3, false);
        ledger.NavigationStarting(3, true);           // /Concepts → /Concepts/
        Assert.True(ledger.AppLoadUnderWay(T0));
        ledger.ContentLoading(3);
        Assert.False(ledger.AppLoadUnderWay(T0));
    }

    [Fact]
    public void AFailedLoadEndsAtItsCompleted()
    {
        // A dead port: ContentLoading (an error page) then Completed, IsSuccess false.
        var ledger = new PreviewNavigationLedger();
        ledger.AppLoadRequested(T0);
        ledger.NavigationStarting(4, false);
        ledger.NavigationCompleted(4);
        Assert.False(ledger.AppLoadUnderWay(T0));
    }

    [Fact]
    public void AnotherNavigationsEndDoesNotEndTheAppsLoad()
    {
        // pushState and fragment clicks consume ids without a Starting: match
        // the CAPTURED id, never "the next one".
        var ledger = new PreviewNavigationLedger();
        ledger.AppLoadRequested(T0);
        ledger.NavigationStarting(10, false);
        ledger.ContentLoading(9);
        ledger.NavigationCompleted(11);
        Assert.True(ledger.AppLoadUnderWay(T0));
        ledger.ContentLoading(10);
        Assert.False(ledger.AppLoadUnderWay(T0));
    }

    [Fact]
    public void TwoAppLoadsBackToBackTheFirstsLateEndDoesNotEndTheSecond()
    {
        // The root, then at once another page (the capture's own load): the
        // first is cancelled and its Completed arrives during the second.
        var ledger = new PreviewNavigationLedger();
        ledger.AppLoadRequested(T0);
        ledger.NavigationStarting(20, false);
        ledger.AppLoadRequested(T0);
        ledger.NavigationCompleted(20);              // the first, cancelled
        Assert.True(ledger.AppLoadUnderWay(T0));
        ledger.NavigationStarting(21, false);
        Assert.True(ledger.AppLoadUnderWay(T0));
        ledger.ContentLoading(21);
        Assert.False(ledger.AppLoadUnderWay(T0));
    }

    [Fact]
    public void TwoAppLoadsAskedForInOneTurnEachWaitForTheirOwnNavigation()
    {
        // Both requests before either navigation starts (one dispatcher turn):
        // the cancelled first one's Completed must not end the second, so the
        // second's SourceChanged is not remembered as the teacher's.
        var ledger = new PreviewNavigationLedger();
        ledger.AppLoadRequested(T0);
        ledger.AppLoadRequested(T0);
        ledger.NavigationStarting(30, false);
        ledger.NavigationCompleted(30);              // the first, cancelled
        Assert.True(ledger.AppLoadUnderWay(T0));
        ledger.NavigationStarting(31, false);
        Assert.True(ledger.AppLoadUnderWay(T0));     // the second's SourceChanged: ignored
        ledger.ContentLoading(31);
        Assert.False(ledger.AppLoadUnderWay(T0));
    }

    [Fact]
    public void ALoadThatNeverStartedEndsByItselfAfterTheBackstop()
    {
        var ledger = new PreviewNavigationLedger();
        ledger.AppLoadRequested(T0);
        Assert.True(ledger.AppLoadUnderWay(T0 + TimeSpan.FromSeconds(14)));
        Assert.False(ledger.AppLoadUnderWay(T0 + PreviewNavigationLedger.Backstop + TimeSpan.FromSeconds(1)));
    }

    [Fact]
    public void ALoadThatStartedWaitsForItsOwnEndNotForTheClock()
    {
        var ledger = new PreviewNavigationLedger();
        ledger.AppLoadRequested(T0);
        ledger.NavigationStarting(5, false);
        Assert.True(ledger.AppLoadUnderWay(T0 + TimeSpan.FromMinutes(2)));
        ledger.NavigationCompleted(5);
        Assert.False(ledger.AppLoadUnderWay(T0 + TimeSpan.FromMinutes(2)));
    }

    [Fact]
    public void AnAddressChangeAfterTheLoadIsTheTeachers()
    {
        // pushState after ContentLoading: SourceChanged only, counted.
        var ledger = new PreviewNavigationLedger();
        ledger.AppLoadRequested(T0);
        ledger.NavigationStarting(8, false);
        ledger.ContentLoading(8);
        Assert.Equal("Unit-1/Lesson-3",
            PreviewStartPage.Remember("http://127.0.0.1:8091/Unit-1/Lesson-3", new Uri("http://127.0.0.1:8091/"),
                                      ledger.AppLoadUnderWay(T0)));
    }
}

public class PreviewPageAddressTests
{
    private static readonly Uri Root = new("http://127.0.0.1:8091/");

    [Theory]
    [InlineData("Unit-1/Lesson-3", "http://127.0.0.1:8091/Unit-1/Lesson-3")]
    [InlineData("Concepts/", "http://127.0.0.1:8091/Concepts/")]
    [InlineData("Unit%201/Lesson%203", "http://127.0.0.1:8091/Unit%201/Lesson%203")]
    [InlineData("C:/Windows", "http://127.0.0.1:8091/C:/Windows")]   // a colon in the first segment is a path, not a scheme
    public void APathIsBuiltOnThisRunsRoot(string path, string expected)
    {
        Assert.Equal(expected, PreviewStartPage.PageAddress(Root, path)?.AbsoluteUri);
    }

    [Fact]
    public void ThePortIsTheRootsNotTheOneTheTeacherLastUsed()
    {
        Assert.Equal("http://127.0.0.1:8101/Help", PreviewStartPage.PageAddress(new Uri("http://127.0.0.1:8101/"), "Help")?.AbsoluteUri);
    }

    [Theory]
    [InlineData("https://example.com/x")]
    public void AnAddressInsteadOfAPathIsRefused(string path)
    {
        Assert.Null(PreviewStartPage.PageAddress(Root, path));
    }

    [Fact]
    public void WhatIsRememberedIsWhatIsAskedBack()
    {
        foreach (string page in new[] { "http://127.0.0.1:8091/Unit%201/Lesson%203", "http://127.0.0.1:8091/Concepts/", "http://localhost:8091/Help" })
        {
            string path = PreviewStartPage.Remember(page, Root, appLoadUnderWay: false)!;
            var back = PreviewStartPage.PageAddress(Root, path)!;
            Assert.Equal(path, PreviewStartPage.Remember(back.AbsoluteUri, Root, appLoadUnderWay: false));
        }
    }
}

[Collection("LastViewedPages")]
public class LastViewedPagesTests : IDisposable
{
    private readonly string _folder = Path.Combine(Path.GetTempPath(), "plantoir-lastviewed-" + Guid.NewGuid().ToString("N")[..8]);

    public LastViewedPagesTests()
    {
        Directory.CreateDirectory(_folder);
        LastViewedPages.FilePathForTests = Path.Combine(_folder, "last-viewed-pages.json");
    }

    public void Dispose()
    {
        LastViewedPages.FilePathForTests = null;
        try { Directory.Delete(_folder, true); } catch { }
    }

    [Fact]
    public void APageIsRememberedPerFolderCourseAndSection()
    {
        Assert.Null(LastViewedPages.PageFor(@"C:\Courses", "ICS3U", 1));
        Assert.True(LastViewedPages.Remember(@"C:\Courses", "ICS3U", 1, "Unit-1/Lesson-3"));
        Assert.Equal("Unit-1/Lesson-3", LastViewedPages.PageFor(@"c:\courses\", "ics3u", 1));
        Assert.Null(LastViewedPages.PageFor(@"C:\Courses", "ICS3U", 2));
        Assert.Null(LastViewedPages.PageFor(@"C:\Other", "ICS3U", 1));
        Assert.Null(LastViewedPages.PageFor(@"C:\Courses", "ICS4U", 1));
    }

    [Fact]
    public void TheFrontPageIsRememberedAsAnEmptyPathNotAsNothing()
    {
        LastViewedPages.Remember(@"C:\Courses", "ICS3U", 1, "Unit-1");
        Assert.True(LastViewedPages.Remember(@"C:\Courses", "ICS3U", 1, ""));
        Assert.Equal("", LastViewedPages.PageFor(@"C:\Courses", "ICS3U", 1));
    }

    [Fact]
    public void TheSamePageIsNotWrittenAgain()
    {
        Assert.True(LastViewedPages.Remember(@"C:\Courses", "ICS3U", 1, "A"));
        var written = File.GetLastWriteTimeUtc(LastViewedPages.FilePath);
        Assert.False(LastViewedPages.Remember(@"C:\Courses", "ICS3U", 1, "A"));
        Assert.Equal(written, File.GetLastWriteTimeUtc(LastViewedPages.FilePath));
    }

    [Theory]
    [InlineData("http://127.0.0.1:8091/A")]
    [InlineData("/A")]
    public void AnAddressIsNeverStored(string path)
    {
        Assert.False(LastViewedPages.Remember(@"C:\Courses", "ICS3U", 1, path));
        Assert.Null(LastViewedPages.PageFor(@"C:\Courses", "ICS3U", 1));
    }

    [Fact]
    public void AnUnreadableFileIsNothingRememberedAndIsReplacedWhole()
    {
        File.WriteAllText(LastViewedPages.FilePath, "{ not json");
        Assert.Null(LastViewedPages.PageFor(@"C:\Courses", "ICS3U", 1));
        Assert.True(LastViewedPages.Remember(@"C:\Courses", "ICS3U", 1, "A"));
        Assert.Equal("A", LastViewedPages.PageFor(@"C:\Courses", "ICS3U", 1));
        Assert.Empty(Directory.GetFiles(_folder, "*.tmp"));
    }

    [Fact]
    public void OnlyTheNewestAreKept()
    {
        var start = new DateTime(2026, 1, 1, 0, 0, 0, DateTimeKind.Utc);
        for (int section = 1; section <= LastViewedPages.Keep + 3; section++)
            LastViewedPages.Remember(@"C:\Courses", "ICS3U", section, "P" + section, start.AddMinutes(section));
        Assert.Null(LastViewedPages.PageFor(@"C:\Courses", "ICS3U", 1));
        Assert.Null(LastViewedPages.PageFor(@"C:\Courses", "ICS3U", 3));
        Assert.Equal("P4", LastViewedPages.PageFor(@"C:\Courses", "ICS3U", 4));
        Assert.Equal("P503", LastViewedPages.PageFor(@"C:\Courses", "ICS3U", LastViewedPages.Keep + 3));
    }
}

/// <summary>One real try against a small server on 127.0.0.1: the status, redirects followed, silence as null.</summary>
public class PreviewPageStatusTests
{
    /// <param name="heard">Completed with the path once a request has been
    /// read, so a test can act at that moment rather than on a timer.</param>
    /// <remarks>
    /// <c>listener.Start()</c> already accepts at the TCP level: the kernel
    /// completes the handshake into the backlog before this returns, so "wait
    /// until the listener accepts" would not change what a slow run meets (#543
    /// REJECTED it). What is late under load is everything in user mode on
    /// BOTH sides, and that needs pool threads.
    /// </remarks>
    private static async Task<(int Port, Task Serving)> ServeAsync(Func<string, string?> answer, CancellationToken stop,
                                                                   TaskCompletionSource<string>? heard = null)
    {
        var listener = new TcpListener(IPAddress.Loopback, 0);
        listener.Start();
        int port = ((IPEndPoint)listener.LocalEndpoint).Port;
        var serving = Task.Run(async () =>
        {
            using var stopping = stop.Register(listener.Stop);
            while (!stop.IsCancellationRequested)
            {
                TcpClient client;
                try { client = await listener.AcceptTcpClientAsync(stop); } catch { return; }
                _ = Task.Run(async () =>
                {
                    using (client)
                    {
                        var stream = client.GetStream();
                        var buffer = new byte[4096];
                        int read = await stream.ReadAsync(buffer, stop);
                        string request = Encoding.ASCII.GetString(buffer, 0, read);
                        string path = request.Split(' ')[1];
                        heard?.TrySetResult(path);
                        string? response = answer(path);
                        if (response is null) { try { await Task.Delay(Timeout.Infinite, stop); } catch { } return; }
                        byte[] bytes = Encoding.ASCII.GetBytes(response);
                        await stream.WriteAsync(bytes, stop);
                    }
                });
            }
        });
        await Task.Yield();
        return (port, serving);
    }

    private static string Status(int code, string extra = "") =>
        $"HTTP/1.1 {code} X\r\nContent-Length: 0\r\nConnection: close\r\n{extra}\r\n";

    [Fact]
    public async Task EachStatusIsReadAsTheServerAnsweredIt()
    {
        using var stop = new CancellationTokenSource();
        var (port, _) = await ServeAsync(path => path switch
        {
            "/ok" => Status(200),
            "/Concepts" => Status(302, "Location: /Concepts/\r\n"),
            "/Concepts/" => Status(200),
            "/gone" => Status(404),
            "/withdrawn" => Status(410),
            "/broken" => Status(500),
            _ => null,   // silence
        }, stop.Token);
        using var client = new HttpClient { Timeout = Timeout.InfiniteTimeSpan };
        Uri At(string path) => new($"http://127.0.0.1:{port}{path}");

        // A generous clock on every ANSWERED path (#543). This test is about
        // reading statuses; the default per-try clock is a product number
        // (previewStartPage.secondsPerAttempt, 5 s), and at the start of a full
        // run the thread pool can be starved for longer than that, which once
        // read a 200 as null here (Expected 200, Actual null, 7 s). A pass
        // takes milliseconds, so the length costs nothing. Only /stalls keeps a
        // short clock: it is the one assert whose subject IS the clock.
        var answered = TimeSpan.FromSeconds(30);
        Assert.Equal(200, await PreviewStartPage.StatusOfAsync(client, At("/ok"), CancellationToken.None, answered));
        Assert.Equal(200, await PreviewStartPage.StatusOfAsync(client, At("/Concepts"), CancellationToken.None, answered));
        Assert.Equal(404, await PreviewStartPage.StatusOfAsync(client, At("/gone"), CancellationToken.None, answered));
        Assert.Equal(410, await PreviewStartPage.StatusOfAsync(client, At("/withdrawn"), CancellationToken.None, answered));
        Assert.Equal(500, await PreviewStartPage.StatusOfAsync(client, At("/broken"), CancellationToken.None, answered));
        Assert.Null(await PreviewStartPage.StatusOfAsync(client, At("/stalls"), CancellationToken.None, TimeSpan.FromMilliseconds(300)));
        stop.Cancel();
    }

    [Fact]
    public async Task AStoppedPreviewEndsTheAskingRatherThanReadingItAsSilence()
    {
        // Deterministic rather than raced (#543). This used to stop the preview
        // with a 200 ms timer against the product's 5 s per-try clock; under a
        // starved pool neither timer's callback ran on time, the per-try one
        // could win, and the method then read silence (null) instead of
        // throwing ("No exception was thrown", 7 s). Now the test stops the
        // preview itself, once the request has ARRIVED, and the per-try clock is
        // a minute so it cannot win. The wait on the asking is 30 s, inside that
        // minute, so a product that ignored the stop fails here with a
        // TimeoutException instead of passing when its own clock ran out.
        using var stop = new CancellationTokenSource();
        var heard = new TaskCompletionSource<string>(TaskCreationOptions.RunContinuationsAsynchronously);
        var (port, _) = await ServeAsync(_ => null, stop.Token, heard);
        using var client = new HttpClient { Timeout = Timeout.InfiniteTimeSpan };
        using var preview = new CancellationTokenSource();
        var started = PreviewStartPage.StatusOfAsync(client, new Uri($"http://127.0.0.1:{port}/x"), preview.Token,
                                                     TimeSpan.FromMinutes(1));
        await heard.Task.WaitAsync(TimeSpan.FromSeconds(30));
        preview.Cancel();
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => started.WaitAsync(TimeSpan.FromSeconds(30)));
        stop.Cancel();
    }
}
