using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using ModelContextProtocol.Protocol;
using Plantoir.Core.Assist;
using Plantoir.Mcp;

// plantoir-mcp — an MCP server over one Plantoir working folder.
//
//   plantoir-mcp --folder "C:\Users\me\Documents\Teaching"
//
// The folder is fixed at startup and never changes afterwards. A server that
// could be pointed anywhere mid-session would make every path check meaningless.

string? folder = null;
string? course = null;
for (int i = 0; i < args.Length; i++)
{
    if ((args[i] == "--folder" || args[i] == "-f") && i + 1 < args.Length) folder = args[++i];
    else if (args[i].StartsWith("--folder=", StringComparison.Ordinal)) folder = args[i]["--folder=".Length..];
    else if ((args[i] == "--course" || args[i] == "-c") && i + 1 < args.Length) course = args[++i];
    // outsideAgents.serverArguments: `--mcp-stdio <folder>`, the shape the
    // contract gives every door, and the one the Codex door passes (#210).
    else if (args[i] == "--mcp-stdio" && i + 1 < args.Length) folder = args[++i];
    else if (args[i].StartsWith("--course=", StringComparison.Ordinal)) course = args[i]["--course=".Length..];
}

folder ??= Environment.GetEnvironmentVariable("PLANTOIR_FOLDER");
course ??= Environment.GetEnvironmentVariable("PLANTOIR_COURSE");

if (string.IsNullOrWhiteSpace(folder))
{
    // stderr, not stdout: stdout belongs to the protocol.
    await Console.Error.WriteLineAsync(
        "plantoir-mcp needs the working folder to serve.\n\n" +
        "  plantoir-mcp --folder \"<path to your Plantoir working folder>\"\n\n" +
        "That is the folder holding your courses — the one Plantoir opens.");
    return 2;
}

AssistWorkspace workspace;
try
{
    // --course locks the session to one course. Only Plantoir's OWN assistant
    // window passes it now (McpClient, with PLANTOIR_LOCAL_WINDOW=1): since
    // v1.4.3 (#430) both outside doors pass `--mcp-stdio <folder>` and name
    // the course in their greeting only (app-rules.json → outsideAgents.
    // courseIsNamedInTheGreetingOnly), so an outside session can reach every
    // course in the folder. Both doors still name their course in
    // DoorCourseVariable (the Codex door since #468), and the `assist` lease
    // below is taken on that course without locking to it.
    // The undo history lives for the life of this process, which is the life
    // of the teacher's conversation — so "undo that" works for as long as they
    // are talking, and nothing accumulates on disk afterwards.
    workspace = new AssistWorkspace(folder, new LauncherRunner(), course, new UndoHistory())
    {
        ServesTheLocalWindow = Environment.GetEnvironmentVariable(AssistWorkspace.LocalWindowVariable) == "1",
        RecordsHeldBackups = true,
    };
}
catch (Exception error)
{
    await Console.Error.WriteLineAsync(error.Message);
    return 2;
}

// Tell the app this course is being worked on, so Preview, Publish and Add
// Section decline while the session is open — otherwise both would build into
// the same output folder. Only when locked to a course: an unrestricted
// session has no single course to claim.
// Both doors name the course they were opened from in DoorCourseVariable
// (fix round ruling 3; the Codex door since #468): held, never locked, so
// #283's backup protection, the second-session guard and the hold on
// structural work survive #430.
string? held = workspace.CourseToHoldForTheConversation(
    Environment.GetEnvironmentVariable(AssistWorkspace.DoorCourseVariable));
IDisposable? lease = held is not null
    ? Plantoir.Core.Assist.WorkLease.Take(workspace.FolderPath, held,
        Plantoir.Core.Assist.WorkLease.Assisting)
    : null;
// A DOOR's session says so on the trail (#468, "outside session held a
// course"); this app's own window's server, locked with --course, holds its
// course too and must not be written up as "a Claude or Codex session".
if (held is not null && !workspace.ServesTheLocalWindow)
    Plantoir.Core.Scripting.ActivityTrail.Note(Plantoir.Core.Scripting.ActivityTrail.Event.OutsideSessionHeldACourse,
        AssistWorkspace.HoldingTrailLine(held));
// Its own work stops BEFORE any lease goes (#289): a build this server started
// must not keep writing the section's folder after the course reads as free.
AppDomain.CurrentDomain.ProcessExit += (_, _) =>
{
    LauncherRunner.StopEverythingItStarted();
    Plantoir.Core.Models.HeldBackups.ForgetRecords(workspace.FolderPath);
    lease?.Dispose();
};

var builder = Host.CreateApplicationBuilder();

// Every log line goes to stderr. stdout carries JSON-RPC frames and nothing
// else; one stray line on it corrupts the session for the whole client.
builder.Logging.AddConsole(options => options.LogToStandardErrorThreshold = LogLevel.Trace);

builder.Services.AddSingleton(workspace);
builder.Services.AddMcpServer(options =>
    {
        options.ServerInfo = new Implementation { Name = "plantoir", Version = "0.1.0" };
        // The procedure the tool descriptions used to carry (#352): read by an
        // outside assistant, never by the local router.
        options.ServerInstructions = McpInstructions.Text;
    })
    .WithStdioServerTransport()
    .WithToolsFromAssembly()
    // Nothing writes to a course kept for reference (#241), asked BEFORE the
    // tool is dispatched: ReferenceWriteGate.
    .WithRequestFilters(filters => filters.AddCallToolFilter(next => async (context, cancellation) =>
    {
        var arguments = context.Params?.Arguments is { } given
            ? new Dictionary<string, System.Text.Json.JsonElement>(given) : null;
        if (context.Params?.Name is { } tool && ReferenceWriteGate.Refusal(tool, arguments, workspace) is { } refusal)
            return new CallToolResult { Content = [new TextContentBlock { Text = refusal }] };
        // An outside assistant's change while the course is being BUILT is held
        // back here, before any backup (#436): OutsideChangeGate.
        if (context.Params?.Name is { } asked && OutsideChangeGate.Refusal(asked, arguments, workspace) is { } heldBack)
            return new CallToolResult { Content = [new TextContentBlock { Text = heldBack }] };
        return await next(context, cancellation);
    }));

try { await builder.Build().RunAsync(); }
finally
{
    LauncherRunner.StopEverythingItStarted();
    Plantoir.Core.Models.HeldBackups.ForgetRecords(workspace.FolderPath);
    lease?.Dispose();
}
return 0;
