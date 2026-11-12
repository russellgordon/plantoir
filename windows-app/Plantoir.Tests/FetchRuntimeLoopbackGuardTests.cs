using System.Diagnostics;
using System.Text;
using Plantoir.Core.Assist;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// #730 (the mac's #684): <c>windows-app\Vendor\fetch-runtime.ps1</c> binds the
/// native preview server AND its live-reload websocket to 127.0.0.1 by
/// rewriting Quartz's two bind sites in <c>quartz/cli/handlers.js</c>. Its old
/// guard passed when only ONE site was rewritten (any "127.0.0.1" in the file
/// was enough), so a Quartz bump that respelled the websocket line would have
/// put live reload back on every interface, and the firewall dialog the
/// rewrite exists to prevent would have been the only sign. The function is
/// run as written, lifted between its BEGIN/END markers, through
/// powershell.exe (the shape <see cref="PublishedPagesRecordTests"/> uses).
///
/// The fixture's two bind lines are Quartz v4.5.0's own spelling
/// (upstream quartz/cli/handlers.js lines 442-443), and it carries one of the
/// file's "•" lines (217-219): the old code read the file as ANSI and wrote it
/// back as UTF-8 with a BOM, which turned "•" into "â€¢" in every runtime.
/// The rewrite must leave every byte but the two sites as it found them.
/// </summary>
public class FetchRuntimeLoopbackGuardTests : IDisposable
{
    private const string Listen = "server.listen(argv.port)";
    private const string ListenLoopback = "server.listen(argv.port, \"127.0.0.1\")";
    private const string Websocket = "new WebSocketServer({ port: argv.wsPort })";
    private const string WebsocketLoopback = "new WebSocketServer({ host: \"127.0.0.1\", port: argv.wsPort })";

    private static readonly UTF8Encoding NoBom = new(false);
    private readonly string _root = Directory.CreateTempSubdirectory("plantoir-loopback-guard").FullName;

    public void Dispose()
    {
        try { Directory.Delete(_root, recursive: true); } catch { }
    }

    private static string Function()
    {
        string script = File.ReadAllText(Path.Combine(ContractLoader.RepositoryRoot, "windows-app", "Vendor", "fetch-runtime.ps1"));
        int start = script.IndexOf("# BEGIN Set-QuartzLoopbackBinds", StringComparison.Ordinal);
        int end = script.IndexOf("# END Set-QuartzLoopbackBinds", StringComparison.Ordinal);
        Assert.True(start >= 0 && end > start, "fetch-runtime.ps1 has no Set-QuartzLoopbackBinds between its markers.");
        return script[start..end];
    }

    private static string Fixture(string listenLine, string websocketLine) =>
        "import { WebSocketServer } from \"ws\"\n" +
        "  • Customizing Quartz a bit more by editing \\`quartz.config.ts\\`\n" +
        "    const server = http.createServer(serve)\n" +
        "    " + listenLine + "\n" +
        "    const wss = " + websocketLine + "\n" +
        "    wss.on(\"connection\", (socket) => connections.push(socket))\n";

    private (int ExitCode, string Said, byte[] After) Run(string handlers)
    {
        string file = Path.Combine(_root, "handlers.js");
        File.WriteAllText(file, handlers, NoBom);
        string script = Path.Combine(_root, "run.ps1");
        File.WriteAllText(script, "$ErrorActionPreference = 'Stop'\n" + Function() + $"\nSet-QuartzLoopbackBinds '{file}'\n", new UTF8Encoding(true));
        var process = Process.Start(new ProcessStartInfo("powershell.exe", $"-NoProfile -ExecutionPolicy Bypass -File \"{script}\"")
        {
            WorkingDirectory = _root,
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
        })!;
        string said = process.StandardOutput.ReadToEnd() + process.StandardError.ReadToEnd();
        Assert.True(process.WaitForExit(60_000), "powershell.exe did not finish within 60 s.");
        return (process.ExitCode, said, File.ReadAllBytes(file));
    }

    [Fact]
    public void BothBindSitesAreRewrittenToLoopback_AndNoOtherByteMoves()
    {
        string before = Fixture(Listen, Websocket);
        var run = Run(before);
        Assert.True(run.ExitCode == 0, $"The rewrite refused Quartz v4.5.0's own lines: {run.Said}");
        byte[] expected = NoBom.GetBytes(before.Replace(Listen, ListenLoopback).Replace(Websocket, WebsocketLoopback));
        Assert.Equal(expected, run.After);
    }

    [Fact]
    public void OnlyTheServerSiteFound_Refuses_NamingTheWebsocket()
    {
        var run = Run(Fixture(Listen, "new WebSocketServer({ port: argv.wsPort, })"));
        Assert.NotEqual(0, run.ExitCode);
        Assert.Contains("the live-reload websocket", run.Said);
    }

    [Fact]
    public void OnlyTheWebsocketSiteFound_Refuses_NamingTheServer()
    {
        var run = Run(Fixture("server.listen(argv.port, undefined)", Websocket));
        Assert.NotEqual(0, run.ExitCode);
        Assert.Contains("the preview server", run.Said);
    }

    [Fact]
    public void NeitherSiteFound_Refuses()
    {
        var run = Run(Fixture("server.listen(port)", "new WebSocketServer({ port })"));
        Assert.NotEqual(0, run.ExitCode);
        Assert.Contains("the preview server", run.Said);
    }

    [Fact]
    public void ASiteThatAppearsTwice_Refuses()
    {
        // A second listen in a Quartz bump is a change somebody must look at,
        // not one to rewrite blind.
        var run = Run(Fixture(Listen, Websocket) + "    " + Listen + "\n");
        Assert.NotEqual(0, run.ExitCode);
        Assert.Contains("the preview server", run.Said);
    }
}
