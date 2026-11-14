using System.Diagnostics;
using System.Text.Json;
using Microsoft.Web.WebView2.Core;
using Plantoir.Core.Models;
using Plantoir.Views;

namespace Plantoir.GuardProbe;

/// <summary>
/// Drives <see cref="GuardedSite"/> on the real WebView2 runtime with no window
/// on screen, and prints what happened, one fact per line, for
/// <c>GuardedSiteTests</c> to read. Never shown, never focused, no sound.
/// </summary>
/// <remarks>
/// <para>Arguments: <c>--root &lt;planning folder&gt;</c>, <c>--udf &lt;user-data folder&gt;</c>,
/// <c>--mode proxy|plain</c> (the local pages' dead proxy, or none: the "made
/// to fail" run), optionally <c>--host &lt;host&gt;</c> and <c>--hand</c> (a
/// coverage-like view that hands <c>plantoir-coverage:</c> clicks to the app),
/// <c>--csp &lt;header&gt;</c> (<c>none</c> for no header: the request handler
/// measured on its own, behind no page policy),
/// then steps: <c>show=&lt;path&gt;</c>, <c>navigate=&lt;address&gt;</c>,
/// <c>click=&lt;x&gt;,&lt;y&gt;</c>, <c>reload</c>, <c>back</c>,
/// <c>wait=&lt;ms&gt;</c>, <c>style=&lt;selector&gt;|&lt;property&gt;</c>, <c>title</c>, <c>source</c>,
/// <c>copy=&lt;from&gt;|&lt;to&gt;</c> (a file changed on disk between two loads).
/// <c>--env-check &lt;folder A&gt; &lt;folder B&gt;</c> instead measures whether
/// <c>WEBVIEW2_USER_DATA_FOLDER</c> (the app sets it for the preview) overrides
/// the folder an environment is created with.</para>
///
/// <para>Printed: <c>REQ served|refused &lt;address&gt;</c>,
/// <c>DECIDE &lt;decision&gt; &lt;address&gt;</c>, <c>DONE &lt;ok&gt; &lt;status&gt;</c>,
/// <c>OUTSIDE</c>, <c>APP</c>, <c>TITLE</c>, <c>SOURCE</c>, <c>STYLE</c>,
/// <c>BROWSER &lt;working set bytes&gt;</c>, <c>STEP</c>, <c>ERROR</c>,
/// and <c>END</c> last.</para>
/// </remarks>
internal static class Program
{
    private static readonly object Gate = new();

    private static void Say(string line)
    {
        lock (Gate) Console.WriteLine(line);
    }

    [STAThread]
    private static int Main(string[] args)
    {
        var form = new Form();
        nint hwnd = form.Handle;   // never shown
        int exit = 0;
        bool done = false;

        async void Run()
        {
            try { exit = await RunAsync(args, hwnd); }
            catch (Exception error) { Say("ERROR " + error.GetType().Name + ": " + error.Message.ReplaceLineEndings(" ")); exit = 3; }
            Say("END");
            done = true;
        }

        var timer = new System.Windows.Forms.Timer { Interval = 50 };
        timer.Tick += (_, _) => { if (done) Application.ExitThread(); };
        timer.Start();
        Run();
        Application.Run();
        return exit;
    }

    private static string? Arg(string[] args, string name)
    {
        int i = Array.IndexOf(args, name);
        return i >= 0 && i + 1 < args.Length ? args[i + 1] : null;
    }

    private static async Task<int> RunAsync(string[] args, nint hwnd)
    {
        if (Array.IndexOf(args, "--env-check") is int check and >= 0) return await EnvironmentCheckAsync(args[check + 1], args[check + 2], hwnd);

        string root = Arg(args, "--root") ?? throw new ArgumentException("--root");
        string udf = Arg(args, "--udf") ?? throw new ArgumentException("--udf");
        string mode = Arg(args, "--mode") ?? "proxy";
        string host = Arg(args, "--host") ?? LocalSiteGuard.PlansHost;
        bool hand = Array.IndexOf(args, "--hand") >= 0;

        var options = new CoreWebView2EnvironmentOptions();
        if (mode == "proxy") options.AdditionalBrowserArguments = LocalPagesEnvironment.BrowserArguments;
        var environment = await CoreWebView2Environment.CreateAsync(null, udf, options);
        var controllerOptions = environment.CreateCoreWebView2ControllerOptions();
        controllerOptions.IsInPrivateModeEnabled = true;
        controllerOptions.ProfileName = LocalPagesEnvironment.PlansProfile;
        var controller = await environment.CreateCoreWebView2ControllerAsync(hwnd, controllerOptions);
        controller.Bounds = new System.Drawing.Rectangle(0, 0, 900, 700);
        controller.IsVisible = true;
        var core = controller.CoreWebView2;

        var guard = new LocalSiteGuard(root, host, LocalSiteGuard.PlanContentTypes);
        var site = GuardedSite.Attach(core, environment, guard, new GuardedSite.Options(
            (address, newWindow, clicked) => hand && address.StartsWith("plantoir-coverage:", StringComparison.OrdinalIgnoreCase)
                ? (clicked ? LocalPageDecision.HandToTheApp : LocalPageDecision.Refuse)
                : PlanNavigation.Decide(address, newWindow, clicked, guard),
            uri => Say("OUTSIDE " + uri.AbsoluteUri),
            hand ? raw => Say("APP " + raw) : null,
            Arg(args, "--csp") is { } csp ? (csp == "none" ? "" : csp) : GuardedSite.PlansContentSecurityPolicy,
            AllowPrint: true), message => Say("ERROR " + message));
        if (site is null) return 2;
        Say("ATTACHED");
        site.Answered += (address, served) => Say((served ? "REQ served " : "REQ refused ") + address);
        site.Decided += (address, decision) => Say("DECIDE " + decision + " " + address);
        core.NewWindowRequested += (_, e) => Say("NEWWINDOW " + e.Uri + " clicked=" + e.IsUserInitiated);
        core.DownloadStarting += (_, e) => Say("DOWNLOAD " + e.DownloadOperation.Uri + " cancelled=" + e.Cancel);
        core.LaunchingExternalUriScheme += (_, e) => Say("EXTERNAL " + e.Uri + " cancelled=" + e.Cancel);

        TaskCompletionSource<bool>? completed = null;
        core.NavigationCompleted += (_, e) =>
        {
            Say($"DONE {e.IsSuccess} {e.HttpStatusCode}");
            completed?.TrySetResult(e.IsSuccess);
        };

        async Task WaitForPage()
        {
            await Task.WhenAny(completed!.Task, Task.Delay(8000));
            await Task.Delay(1200);   // subresources, prefetches, a refresh
        }

        var steps = new List<string>();
        for (int i = 0; i < args.Length; i++)
        {
            if (args[i] == "--hand") continue;
            if (args[i].StartsWith("--", StringComparison.Ordinal)) { i++; continue; }
            steps.Add(args[i]);
        }
        int step = 0;
        foreach (string raw in steps)
        {
            Say("STEP " + (step++) + " " + raw);
            int eq = raw.IndexOf('=');
            string verb = eq < 0 ? raw : raw[..eq];
            string value = eq < 0 ? "" : raw[(eq + 1)..];
            switch (verb)
            {
                case "show":
                    completed = new TaskCompletionSource<bool>();
                    if (!site.Show(value)) Say("ERROR the guard cannot name " + value);
                    await WaitForPage();
                    break;
                case "navigate":
                    completed = new TaskCompletionSource<bool>();
                    core.Navigate(value);
                    await WaitForPage();
                    break;
                case "click":
                    var xy = value.Split(',');
                    completed = new TaskCompletionSource<bool>();
                    foreach (string type in new[] { "mousePressed", "mouseReleased" })
                        await core.CallDevToolsProtocolMethodAsync("Input.dispatchMouseEvent",
                            JsonSerializer.Serialize(new { type, x = int.Parse(xy[0]), y = int.Parse(xy[1]), button = "left", clickCount = 1 }));
                    await Task.WhenAny(completed.Task, Task.Delay(3000));
                    await Task.Delay(1200);
                    break;
                case "reload":
                    completed = new TaskCompletionSource<bool>();
                    site.Reload();
                    await WaitForPage();
                    break;
                case "back":
                    completed = new TaskCompletionSource<bool>();
                    Say("CANGOBACK " + core.CanGoBack);
                    core.GoBack();
                    await WaitForPage();
                    break;
                case "wait":
                    await Task.Delay(int.Parse(value));
                    break;
                case "copy":
                    File.Copy(value.Split('|')[0], value.Split('|')[1], overwrite: true);
                    break;
                case "style":
                    Say("STYLE " + await ComputedStyleAsync(core, value.Split('|')[0], value.Split('|')[1]));
                    break;
                case "title":
                    Say("TITLE " + core.DocumentTitle);
                    break;
                case "source":
                    Say("SOURCE " + core.Source);
                    break;
            }
        }

        try { Say("BROWSER " + Process.GetProcessById((int)core.BrowserProcessId).WorkingSet64); }
        catch (Exception error) { Say("ERROR browser process: " + error.Message); }
        controller.Close();
        return 0;
    }

    /// <summary>A computed CSS property through the DevTools protocol, which needs no page script.</summary>
    private static async Task<string> ComputedStyleAsync(CoreWebView2 core, string selector, string property)
    {
        await core.CallDevToolsProtocolMethodAsync("DOM.enable", "{}");
        await core.CallDevToolsProtocolMethodAsync("CSS.enable", "{}");
        using var document = JsonDocument.Parse(await core.CallDevToolsProtocolMethodAsync("DOM.getDocument", "{}"));
        int rootId = document.RootElement.GetProperty("root").GetProperty("nodeId").GetInt32();
        using var found = JsonDocument.Parse(await core.CallDevToolsProtocolMethodAsync("DOM.querySelector",
            JsonSerializer.Serialize(new { nodeId = rootId, selector })));
        int nodeId = found.RootElement.GetProperty("nodeId").GetInt32();
        using var style = JsonDocument.Parse(await core.CallDevToolsProtocolMethodAsync("CSS.getComputedStyleForNode",
            JsonSerializer.Serialize(new { nodeId })));
        foreach (var entry in style.RootElement.GetProperty("computedStyle").EnumerateArray())
            if (entry.GetProperty("name").GetString() == property) return entry.GetProperty("value").GetString() ?? "";
        return "";
    }

    /// <summary>
    /// With <c>WEBVIEW2_USER_DATA_FOLDER</c> set to <paramref name="preview"/>, as
    /// the app sets it, does an environment created with <paramref name="local"/>
    /// get that folder, and can both live in one process?
    /// </summary>
    private static async Task<int> EnvironmentCheckAsync(string preview, string local, nint hwnd)
    {
        Environment.SetEnvironmentVariable("WEBVIEW2_USER_DATA_FOLDER", preview);
        var first = await CoreWebView2Environment.CreateAsync(null, null, new CoreWebView2EnvironmentOptions());
        Say("PREVIEW " + first.UserDataFolder);
        var previewController = await first.CreateCoreWebView2ControllerAsync(hwnd);
        Say("PREVIEW CONTROLLER " + (previewController.CoreWebView2 is not null));
        var options = new CoreWebView2EnvironmentOptions { AdditionalBrowserArguments = LocalPagesEnvironment.BrowserArguments };
        try
        {
            // The app's way (LocalPagesEnvironment): the variable is taken
            // away for the one call and put back, on the interface thread.
            Environment.SetEnvironmentVariable("WEBVIEW2_USER_DATA_FOLDER", null);
            Task<CoreWebView2Environment> creating;
            try { creating = CoreWebView2Environment.CreateAsync(null, local, options); }
            finally { Environment.SetEnvironmentVariable("WEBVIEW2_USER_DATA_FOLDER", preview); }
            var second = await creating;
            Say("LOCAL " + second.UserDataFolder);
            var controllerOptions = second.CreateCoreWebView2ControllerOptions();
            controllerOptions.IsInPrivateModeEnabled = true;
            controllerOptions.ProfileName = LocalPagesEnvironment.PlansProfile;
            var localController = await second.CreateCoreWebView2ControllerAsync(hwnd, controllerOptions);
            Say("LOCAL CONTROLLER " + (localController.CoreWebView2 is not null) + " pid " + localController.CoreWebView2!.BrowserProcessId
                + " preview pid " + previewController.CoreWebView2.BrowserProcessId);
            localController.Close();
        }
        catch (Exception error) { Say("LOCAL FAILED " + error.GetType().Name + ": " + error.Message.ReplaceLineEndings(" ")); }
        previewController.Close();
        return 0;
    }
}
